# Sums career-coverage-for-clubs.rq across the current clubs in each league.
# Prints one CSV row per league. A public Wikidata query of a whole league
# times out, so clubs are sent in small batches.
#
#   powershell -File tools/wikidata/run-career-coverage.ps1

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$endpoint = "https://query.wikidata.org/sparql"
$userAgent = "ParkTheBus/0.1 (career coverage spike)"
$batchSize = 4

$leagues = @(
    @{ Name = "Premier League"; Id = "Q9448" },
    @{ Name = "La Liga"; Id = "Q324867" },
    @{ Name = "Serie A"; Id = "Q15804" },
    @{ Name = "Bundesliga"; Id = "Q82595" },
    @{ Name = "Ligue 1"; Id = "Q13394" },
    @{ Name = "EFL Championship"; Id = "Q19510" },
    @{ Name = "2. Bundesliga"; Id = "Q152665" },
    # P118 on this defunct league is a handful of leftover clubs.
    # docs/research records spell counts for its season participants instead.
    @{ Name = "Football League First Division"; Id = "Q754839" }
)

$clubQuery = [System.IO.File]::ReadAllText((Join-Path $here "clubs-in-league.rq"))
$seasonQuery = [System.IO.File]::ReadAllText((Join-Path $here "season-clubs-in-league.rq"))
$coverageQuery = [System.IO.File]::ReadAllText((Join-Path $here "career-coverage-for-clubs.rq"))

function Invoke-Sparql([string]$Query) {
    $tmp = Join-Path $env:TEMP ("ptb-" + [guid]::NewGuid().ToString() + ".rq")
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $Query, $utf8)
    try {
        $lines = & curl.exe -sS --max-time 45 -G $endpoint --data-urlencode "query@$tmp" -H "Accept: text/csv" -H "User-Agent: $userAgent"
        if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    if ($lines -is [string]) { $lines = @($lines) }
    $lines = @($lines | Where-Object { $_ -and $_.Trim() -ne "" })
    if ($lines.Count -eq 0) { throw "empty response" }
    if ($lines[0] -match "timeout|Exception|Malformed|Gateway") { throw ($lines -join " ") }
    return @($lines | ConvertFrom-Csv)
}

function Get-ClubIds([string]$QueryText, [string]$LeagueId) {
    $query = $QueryText.Replace("wd:Q9448", "wd:$LeagueId")
    $rows = @(Invoke-Sparql $query)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        if ($row.club -match "(Q\d+)$") { $ids.Add($Matches[1]) }
    }
    return @($ids | Select-Object -Unique)
}

function Get-BatchCoverage([string[]]$ClubIds) {
    if ($ClubIds.Count -eq 0) { return $null }
    $values = ($ClubIds | ForEach-Object { "wd:$_" }) -join " "
    $query = $coverageQuery.Replace("wd:Q9616", $values)
    try {
        $rows = @(Invoke-Sparql $query)
        return $rows[0]
    } catch {
        if ($ClubIds.Count -eq 1) { throw }
        $mid = [Math]::Floor($ClubIds.Count / 2)
        $left = Get-BatchCoverage @($ClubIds[0..($mid - 1)])
        $right = Get-BatchCoverage @($ClubIds[$mid..($ClubIds.Count - 1)])
        $merged = [ordered]@{}
        foreach ($name in @("spells", "withStart", "withEnd", "complete", "preferredOpen", "pre1990", "pre1990WithEnd")) {
            $merged[$name] = [int]$left.$name + [int]$right.$name
        }
        return [pscustomobject]$merged
    }
}

Write-Output "league,currentClubs,everClubs,seasons,spells,withStart,withEnd,complete,preferredOpen,pre1990,pre1990WithEnd,sample"

foreach ($league in $leagues) {
    Write-Host "Querying $($league.Name)..."
    try {
        $current = @(Get-ClubIds $clubQuery $league.Id)
        $ever = @()
        $seasons = ""
        try {
            $seasonRows = @(Invoke-Sparql ($seasonQuery.Replace("wd:Q9448", "wd:$($league.Id)")))
            $ever = @($seasonRows | ForEach-Object { if ($_.club -match "(Q\d+)$") { $Matches[1] } } | Select-Object -Unique)
            $seasons = @($seasonRows | ForEach-Object { $_.season } | Select-Object -Unique).Count
        } catch {
            Write-Host ("  season list failed: {0}" -f $_.Exception.Message)
            $seasons = "timeout"
        }
        $sample = "current league (P118)"
        $sampleIds = $current
        if ($sampleIds.Count -eq 0) {
            $sample = "season participants (P118 empty)"
            $sampleIds = $ever
        }
        $totals = [ordered]@{
            spells = 0; withStart = 0; withEnd = 0; complete = 0
            preferredOpen = 0; pre1990 = 0; pre1990WithEnd = 0
        }
        for ($i = 0; $i -lt $sampleIds.Count; $i += $batchSize) {
            $last = [Math]::Min($i + $batchSize - 1, $sampleIds.Count - 1)
            $batch = @($sampleIds[$i..$last])
            Write-Host ("  clubs {0}-{1} of {2}" -f ($i + 1), ($last + 1), $sampleIds.Count)
            $row = Get-BatchCoverage $batch
            foreach ($name in @($totals.Keys)) {
                $totals[$name] += [int]$row.$name
            }
            Start-Sleep -Seconds 1
        }
        Write-Output ("{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11}" -f `
            $league.Name, $current.Count, $ever.Count, $seasons, `
            $totals.spells, $totals.withStart, $totals.withEnd, $totals.complete, `
            $totals.preferredOpen, $totals.pre1990, $totals.pre1990WithEnd, $sample)
    } catch {
        Write-Output ("{0},ERROR,,,,,,,,,,,{1}" -f $league.Name, ($_.Exception.Message -replace ",", ";"))
    }
}
