# Sums English Wikipedia pageviews for the players in enwiki-titles.rq.
# Window: November 2025 through October 2026, twelve complete months.
# Counts user views on every access method. Spider and automated traffic
# are excluded.
#
#   powershell -File tools/wikidata/pageview-prior.ps1

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here "..\..")
$endpoint = "https://query.wikidata.org/sparql"
$pageviews = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user"
$userAgent = "ParkTheBus/0.1 (pageview prior spike)"
$start = "2025110100"
$end = "2026103100"
$out = Join-Path $repo "docs\research\pageview-prior-run.csv"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Invoke-Sparql([string]$Query) {
    $queryFile = Join-Path $env:TEMP ("ptb-" + [guid]::NewGuid().ToString() + ".rq")
    $bodyFile = Join-Path $env:TEMP ("ptb-" + [guid]::NewGuid().ToString() + ".csv")
    [System.IO.File]::WriteAllText($queryFile, $Query, $utf8)
    try {
        & curl.exe -sS --max-time 40 -G $endpoint --data-urlencode "query@$queryFile" -o $bodyFile -H "Accept: text/csv" -H "User-Agent: $userAgent"
        if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
        $text = [System.IO.File]::ReadAllText($bodyFile, $utf8)
    } finally {
        Remove-Item $queryFile, $bodyFile -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrWhiteSpace($text) -or $text -match "timeout|Exception|Malformed|Gateway") {
        throw $text
    }
    return @($text | ConvertFrom-Csv)
}

function Get-Pageviews([string]$Title) {
    $article = [Uri]::EscapeDataString($Title.Replace(" ", "_"))
    $url = "$pageviews/$article/monthly/$start/$end"
    $tmp = Join-Path $env:TEMP ("ptb-" + [guid]::NewGuid().ToString() + ".json")
    $delay = 5
    try {
        for ($try = 1; $try -le 6; $try++) {
            $code = (& curl.exe -sS --max-time 30 -o $tmp -w "%{http_code}" $url -H "Accept: application/json" -H "User-Agent: $userAgent").Trim()
            if ($code -eq "200") { break }
            if ($code -eq "404") { return $null }
            if (($code -eq "429" -or $code -eq "503") -and $try -lt 6) {
                Write-Host "  HTTP $code, waiting ${delay}s"
                Start-Sleep -Seconds $delay
                $delay = [Math]::Min($delay * 2, 60)
                continue
            }
            throw "pageviews HTTP $code for $Title"
        }
        $json = [System.IO.File]::ReadAllText($tmp, $utf8) | ConvertFrom-Json
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    $sum = 0
    $months = 0
    foreach ($item in @($json.items)) {
        $sum += [int]$item.views
        $months += 1
    }
    return [pscustomobject]@{ Views = $sum; Months = $months }
}

$query = [System.IO.File]::ReadAllText((Join-Path $here "enwiki-titles.rq"))
$rows = @(Invoke-Sparql $query)
[System.IO.File]::WriteAllLines($out, @("player,qid,title,views,months"), $utf8)
foreach ($row in $rows) {
    $qid = ""
    if ($row.player -match "(Q\d+)$") { $qid = $Matches[1] }
    $views = ""
    $months = ""
    if ($row.title) {
        Write-Host $row.playerLabel
        $result = Get-Pageviews $row.title
        if ($null -ne $result) {
            $views = $result.Views
            $months = $result.Months
        }
        Start-Sleep -Seconds 1
    }
    $title = ($row.title -replace ",", " ")
    $name = ($row.playerLabel -replace ",", " ")
    [System.IO.File]::AppendAllText($out, ("{0},{1},{2},{3},{4}`n" -f $name, $qid, $title, $views, $months), $utf8)
}
Write-Host "Wrote $out"