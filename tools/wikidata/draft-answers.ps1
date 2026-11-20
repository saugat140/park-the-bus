# Draft answer candidates for review. Issue #57. ADR 0002.
#
# This does not write the curated list. The files under drafts/ are not
# the entity CSV or the prompt answer CSV, and nothing here is loaded
# into PostgreSQL. National-team caps are not a draft type: membership
# is not a cap list.
#
#   powershell -File tools/wikidata/draft-answers.ps1 -Type club -League premier-league -Club Q9617
#   powershell -File tools/wikidata/draft-answers.ps1 -Type award -Award Q166177,Q2291862
#   powershell -File tools/wikidata/draft-answers.ps1 -Type tournament -Tournament Q134202 -TeamsFile tools/wikidata/wc1966-teams.txt
#
# Club drafts are one club at a time, and only for a league the
# career-coverage note calls thick enough: premier-league,
# championship, serie-a, ligue-1. Passing the league name does not
# check that the club plays in it. A whole league times out the
# public query service. A 1 January date is the year, not the day.
# Preferred rank is not a current squad.
#
# Award drafts are one row per person. The year is detail for the
# reviewer, not an answer.
#
# Tournament drafts join participation to the national teams in the
# file, then stop. A count of 22 is not a name check. Squad items do
# not hold the players.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("club", "award", "tournament")]
    [string]$Type,

    [string]$Club,
    [string]$League,
    [string]$Award,
    [string]$Tournament,
    [string]$TeamsFile,
    [string]$Out
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here "..\..")
$endpoint = "https://query.wikidata.org/sparql"
$userAgent = "ParkTheBus/0.1 (answer draft)"
$utf8 = New-Object System.Text.UTF8Encoding $false

$thickLeagues = @(
    "premier-league",
    "championship",
    "serie-a",
    "ligue-1"
)
$refusedLeagues = @{
    "bundesliga" = "The Bundesliga list is too thin to draft from. See docs/research/wikidata-career-coverage.md."
    "2-bundesliga" = "2. Bundesliga is outside the thicker leagues in the career-coverage note."
    "la-liga" = "La Liga needs the most date repair. The career-coverage note does not call it thick enough to draft."
}
$notClubs = @{
    "Q9448" = "Premier League"
    "Q19510" = "Championship"
    "Q15804" = "Serie A"
    "Q13394" = "Ligue 1"
    "Q324867" = "La Liga"
    "Q82595" = "Bundesliga"
    "Q152665" = "2. Bundesliga"
    "Q754839" = "Football League First Division"
    "Q219592" = "Austrian Bundesliga, not the German Bundesliga"
    "Q922935" = "women's Serie A, not Serie A"
    "Q929124" = "Italian basketball Serie A, not Serie A"
}

function Assert-Qid([string]$Value, [string]$Label) {
    if ($Value -notmatch "^Q[0-9]+$") {
        throw "$Label must be a Wikidata Qid such as Q9617, got '$Value'."
    }
}

function Get-Qid([string]$Uri) {
    if ($Uri -match "(Q[0-9]+)$") { return $Matches[1] }
    return ""
}

function Format-CsvField([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    if ($Value -match '[",\r\n]') {
        return '"' + ($Value.Replace('"', '""')) + '"'
    }
    return $Value
}

function Format-Day([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    if ($Value -match "^(\d{4}-\d{2}-\d{2})") { return $Matches[1] }
    return $Value
}

function Test-YearPrecision([string]$Value) {
    return (Format-Day $Value) -match "^\d{4}-01-01$"
}

function Invoke-Sparql([string]$Query) {
    $queryFile = Join-Path $env:TEMP ("ptb-" + [guid]::NewGuid().ToString() + ".rq")
    $bodyFile = Join-Path $env:TEMP ("ptb-" + [guid]::NewGuid().ToString() + ".csv")
    [System.IO.File]::WriteAllText($queryFile, $Query, $utf8)
    try {
        $text = ""
        $code = ""
        for ($try = 1; $try -le 4; $try++) {
            $code = (& curl.exe -sS --max-time 60 -G $endpoint --data-urlencode "query@$queryFile" -o $bodyFile -w "%{http_code}" -H "Accept: text/csv" -H "User-Agent: $userAgent").Trim()
            if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
            if (($code -eq "429" -or $code -eq "503") -and $try -lt 4) {
                Start-Sleep -Seconds (5 * $try)
                continue
            }
            $text = [System.IO.File]::ReadAllText($bodyFile, $utf8)
            break
        }
    } finally {
        Remove-Item $queryFile, $bodyFile -ErrorAction SilentlyContinue
    }
    if ($code -ne "200") {
        $snippet = $text
        if ($snippet.Length -gt 400) { $snippet = $snippet.Substring(0, 400) }
        throw "Wikidata HTTP $code. $snippet"
    }
    $header = ($text -split "`n", 2)[0]
    if ([string]::IsNullOrWhiteSpace($text) -or ($header -notmatch "^player," -and $header -notmatch "^team,")) {
        throw "Wikidata did not return a CSV."
    }
    return @($text | ConvertFrom-Csv)
}

function Write-Draft([object[]]$Rows, [string]$Slug) {
    $dir = Join-Path $repo "drafts"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $path = $Out
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $dir ("draft-" + $Slug + ".csv")
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("draft_type,context,label,qid,description,detail,review_note")
    foreach ($row in $Rows) {
        $lines.Add((
            (Format-CsvField $row.DraftType),
            (Format-CsvField $row.Context),
            (Format-CsvField $row.Label),
            (Format-CsvField $row.Qid),
            (Format-CsvField $row.Description),
            (Format-CsvField $row.Detail),
            (Format-CsvField $row.ReviewNote)
        ) -join ",")
    }
    [System.IO.File]::WriteAllLines($path, $lines, $utf8)
    Write-Host ("{0} rows written to {1}" -f $Rows.Count, $path)
}

$clubNote = "Review every spell before this person is an answer. A 1 January date is the year, not the day. Preferred rank is not the current squad. Youth spells and loans stay in this draft until you remove them. Do not load this file."
$awardNote = "One row is one person. Do not draft who won in a year. A 1 January date is year precision. Check the people against a list you trust before anyone is an answer. See docs/research/non-club-drafts.md. Do not load this file."
$tournamentNote = "Name-check the squad. A count of 22 is not a check. Squad items do not hold the players. The same person on two teams needs a decision. See docs/research/non-club-drafts.md. Do not load this file."

if ($Type -eq "club") {
    if ([string]::IsNullOrWhiteSpace($League) -or [string]::IsNullOrWhiteSpace($Club)) {
        throw "A club draft needs -League and -Club."
    }
    $leagueKey = $League.ToLowerInvariant()
    if ($refusedLeagues.ContainsKey($leagueKey)) {
        throw $refusedLeagues[$leagueKey]
    }
    if ($thickLeagues -notcontains $leagueKey) {
        throw "League must be premier-league, championship, serie-a, or ligue-1. See docs/research/wikidata-career-coverage.md."
    }
    Assert-Qid $Club "Club"
    if ($notClubs.ContainsKey($Club)) {
        throw "$Club is $($notClubs[$Club]). Pass one club, not a league."
    }

    $query = @"
SELECT ?player ?playerLabel ?playerDescription ?start ?end WHERE {
  ?player p:P54 ?spell .
  ?spell ps:P54 wd:$Club .
  FILTER NOT EXISTS { ?spell wikibase:rank wikibase:DeprecatedRank . }
  OPTIONAL { ?spell pq:P580 ?start . }
  OPTIONAL { ?spell pq:P582 ?end . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"@
    $raw = @(Invoke-Sparql $query)
    $draft = foreach ($group in @($raw | Group-Object { Get-Qid $_.player })) {
        $spells = foreach ($spell in $group.Group) {
            $start = Format-Day $spell.start
            $end = Format-Day $spell.end
            $text = "$(if ($start) { $start } else { 'start missing' })..$(if ($end) { $end } else { 'open' })"
            if ((Test-YearPrecision $spell.start) -or (Test-YearPrecision $spell.end)) {
                $text += " [year precision]"
            }
            $text
        }
        $first = $group.Group[0]
        [pscustomobject]@{
            DraftType = "club"
            Context = $leagueKey
            Label = [string]$first.playerLabel
            Qid = Get-Qid $first.player
            Description = [string]$first.playerDescription
            Detail = ($spells -join "; ")
            ReviewNote = $clubNote
        }
    }
    Write-Draft @($draft | Where-Object { $_ } | Sort-Object Label) ("club-" + $leagueKey + "-" + $Club)
    return
}

if ($Type -eq "award") {
    if ([string]::IsNullOrWhiteSpace($Award)) {
        throw "An award draft needs -Award and one or more Qids."
    }
    $awardIds = @($Award.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($awardIds.Count -eq 0) { throw "An award draft needs at least one Qid." }
    foreach ($id in $awardIds) { Assert-Qid $id "Award" }
    $values = ($awardIds | ForEach-Object { "wd:$_" }) -join " "
    $query = @"
SELECT ?player ?playerLabel ?playerDescription ?when WHERE {
  VALUES ?award { $values }
  ?player p:P166 ?stmt .
  ?stmt ps:P166 ?award .
  FILTER NOT EXISTS { ?stmt wikibase:rank wikibase:DeprecatedRank . }
  OPTIONAL { ?stmt pq:P585 ?when . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"@
    $raw = @(Invoke-Sparql $query)
    $draft = foreach ($group in @($raw | Group-Object { Get-Qid $_.player })) {
        $years = New-Object System.Collections.Generic.List[string]
        $undated = 0
        $yearPrecision = 0
        foreach ($stmt in $group.Group) {
            $day = Format-Day $stmt.when
            if ([string]::IsNullOrWhiteSpace($day)) {
                $undated += 1
            } else {
                $years.Add($day.Substring(0, 4))
                if (Test-YearPrecision $stmt.when) { $yearPrecision += 1 }
            }
        }
        $yearText = if ($years.Count -eq 0) { "no year" } else { ($years | Sort-Object -Unique) -join " " }
        $first = $group.Group[0]
        [pscustomobject]@{
            DraftType = "award"
            Context = ($awardIds -join " ")
            Label = [string]$first.playerLabel
            Qid = Get-Qid $first.player
            Description = [string]$first.playerDescription
            Detail = "statements=$($group.Count); undated=$undated; year-precision=$yearPrecision; years=$yearText"
            ReviewNote = $awardNote
        }
    }
    Write-Draft @($draft | Where-Object { $_ } | Sort-Object Label) ("award-" + ($awardIds -join "-"))
    return
}

if ([string]::IsNullOrWhiteSpace($Tournament) -or [string]::IsNullOrWhiteSpace($TeamsFile)) {
    throw "A tournament draft needs -Tournament and -TeamsFile."
}
Assert-Qid $Tournament "Tournament"
if (-not (Test-Path -LiteralPath $TeamsFile)) {
    throw "Teams file not found: $TeamsFile"
}
$teamIds = New-Object System.Collections.Generic.List[string]
foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $TeamsFile), $utf8)) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
    $id = ($trimmed -split "\s+")[0]
    Assert-Qid $id "Team"
    if (-not $teamIds.Contains($id)) { $teamIds.Add($id) }
}
if ($teamIds.Count -eq 0) { throw "The teams file has no Qids." }
if ($teamIds.Count -gt 32) {
    throw "The teams file has $($teamIds.Count) teams. Draft at most 32 at a time so the public query service can answer."
}
$values = ($teamIds | ForEach-Object { "wd:$_" }) -join " "
$query = @"
SELECT DISTINCT ?team ?teamLabel ?player ?playerLabel ?playerDescription WHERE {
  VALUES ?team { $values }
  ?player wdt:P1344 wd:$Tournament ;
          wdt:P106 wd:Q937857 ;
          wdt:P54 ?team .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"@
$raw = @(Invoke-Sparql $query)
$draft = foreach ($row in $raw) {
    [pscustomobject]@{
        DraftType = "tournament"
        Context = $Tournament
        Label = [string]$row.playerLabel
        Qid = Get-Qid $row.player
        Description = [string]$row.playerDescription
        Detail = [string]$row.teamLabel
        ReviewNote = $tournamentNote
    }
}
Write-Draft @($draft | Where-Object { $_ } | Sort-Object Detail, Label) ("tournament-" + $Tournament)
