# Wikidata career-coverage spike

Issue #5. Drafting aid only. These queries do not create answer lists.

Run on 2026-11-13. League totals are below and in `wikidata-career-coverage-run.csv`. Rows are not a partition: a club that has played in more than one of these competitions contributes the same spells to each row.

## Question

For clubs in five top leagues and two lower leagues, how many player–club spells on Wikidata have a start date and an end date? The same question for spells that started before 1990.

## Sample

| League | Wikidata | Role |
| --- | --- | --- |
| Premier League | Q9448 | Top |
| La Liga | Q324867 | Top |
| Serie A | Q15804 | Top. No English `rdfs:label`. Description: Italian men's top division. |
| Bundesliga | Q82595 | Top. No English `rdfs:label`. Description: German men's top league. |
| Ligue 1 | Q13394 | Top |
| EFL Championship | Q19510 | Lower |
| 2. Bundesliga | Q152665 | Lower |
| Football League First Division | Q754839 | Extra. English top flight before the Premier League (1992). Not one of the seven. |

Ids were checked by English description. Nearby items that are the wrong competition: Q219592 is the Austrian Bundesliga, Q922935 is women's Serie A, Q929124 is Italian basketball Serie A.

A spell is one non-deprecated statement of P54 (member of sports team) on a person whose occupation is association football player (Q937857).

| Column | Meaning |
| --- | --- |
| withStart | Has P580 |
| withEnd | Has P582 |
| preferredOpen | Preferred rank and no end date. Treated as the current club. |
| complete | Has a start, and either an end or preferred rank |
| pre1990 | Has a start before 1990-01-01 |
| pre1990WithEnd | pre1990 and has an end |

`pre1990` only includes spells that already have a start. A historical spell with no dates is invisible there. The gap for missing starts is `spells - withStart`.

## How the sample is chosen

P118 (league) on its own is mostly people, not clubs. For the Premier League item, that unfiltered count was 2,580 humans and 19 association football clubs. Every query below keeps items typed Q476028 (association football club) or Q103229495 (men's association football team).

Current members, from `clubs-by-league.rq` (P118 plus that type filter):

| League | Current clubs |
| --- | ---: |
| Premier League | 20 |
| La Liga | 21 |
| Serie A | 27 |
| Bundesliga | 18 |
| Ligue 1 | 22 |
| EFL Championship | 24 |
| 2. Bundesliga | 20 |

A top division has 18 or 20 teams. Counts above that (Serie A 27, Ligue 1 22, La Liga 21, 2. Bundesliga 20) mean extra items still point at the league: reserve sides, stale statements, or a club typed twice. The runner counts distinct clubs.

Clubs that have ever taken part come from a season of the league (P3450) and a participating team (P1923). For the Premier League that was 33 seasons and 50 clubs. The spell sample stays on current P118 clubs. A club that has played in two divisions would otherwise add its whole history to both rows.

The Premier League did not exist before 1992. Pre-1990 rows for its current clubs are careers at today's clubs, not a 1980s league roster. The Football League First Division item still has four clubs on P118, so the script's empty-P118 fallback did not run. Those four clubs have five spells between them. The First Division row in the table below is the 56 season participants, measured with the same date query.

## Queries

| File | What it returns |
| --- | --- |
| `tools/wikidata/clubs-by-league.rq` | Current club counts for all seven leagues. One request. |
| `tools/wikidata/clubs-in-league.rq` | Club ids for one league. Default: Premier League. |
| `tools/wikidata/season-clubs-in-league.rq` | Club–season pairs for one league. Default: Premier League. |
| `tools/wikidata/career-coverage-for-clubs.rq` | The date counts. Default: one club, so the file runs as-is. |
| `tools/wikidata/career-spell-spotcheck.rq` | Spells for the six players in the spot-check. |
| `tools/wikidata/run-career-coverage.ps1` | Runs the date counts in batches of four clubs and prints one CSV row per league. |

A request for every spell in a league exceeds the public query service time limit. One club returns in a few seconds. From the repo root:

```powershell
powershell -File tools/wikidata/run-career-coverage.ps1
```

To run a single file against the query service, send a User-Agent:

```powershell
curl.exe -G "https://query.wikidata.org/sparql" `
  --data-urlencode query@tools/wikidata/clubs-by-league.rq `
  -H "Accept: text/csv" `
  -H "User-Agent: ParkTheBus/0.1 (career coverage spike)"
```

## Worked example

One club (Arsenal, Q9616), same metrics as the league run:

| Spells | With start | With end | Complete | Preferred, no end | Pre-1990 | Pre-1990 with end |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 949 | 872 (91.9%) | 813 (85.7%) | 828 (87.2%) | 18 | 425 | 414 (97.4% of those 425) |

Of the 813 spells with an end, three have no start, so 810 have both. All 18 open preferred-rank spells have a start. 810 + 18 = 828, which matches `complete`. This checks the definition. It does not check that the clubs or the years are right.

## League results

Spell counts are for current P118 clubs, except the First Division row, which is season participants. "Ever" is distinct clubs linked through a season of that competition. Percents use spells as the denominator. The pre-1990 percent uses only spells that have a start before 1990.

| League | Current | Ever | Seasons | Spells | With start | With end | Complete | Open current | Pre-1990 with end |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Premier League | 20 | 50 | 33 | 20,882 | 17,746 (85.0%) | 16,891 (80.9%) | 17,056 (81.7%) | 229 | 8,710 / 8,863 (98.3%) |
| La Liga | 21 | 61 | 96 | 13,688 | 10,362 (75.7%) | 9,923 (72.5%) | 9,832 (71.8%) | 130 | 2,762 / 2,769 (99.7%) |
| Serie A | 27 | 97 | 97 | 20,920 | 18,941 (90.5%) | 18,197 (87.0%) | 18,348 (87.7%) | 157 | 9,800 / 9,818 (99.8%) |
| Bundesliga | 18 | 92 | 63 | 5,668 | 4,929 (87.0%) | 4,533 (80.0%) | 4,574 (80.7%) | 47 | 1,144 / 1,150 (99.5%) |
| Ligue 1 | 22 | 75 | 88 | 10,629 | 9,619 (90.5%) | 9,081 (85.4%) | 9,138 (86.0%) | 71 | 3,394 / 3,397 (99.9%) |
| EFL Championship | 24 | 33 | 3 | 24,501 | 21,961 (89.6%) | 21,126 (86.2%) | 21,141 (86.3%) | 26 | 11,316 / 11,472 (98.6%) |
| 2. Bundesliga | 20 | 81 | 42 | 8,641 | 7,095 (82.1%) | 6,616 (76.6%) | 6,612 (76.5%) | 8 | 1,983 / 1,995 (99.4%) |
| First Division (seasons) | 4 on P118 | 56 | 89 | 56,366 | 49,314 (87.5%) | 47,297 (83.9%) | 47,461 (84.2%) | 242 | 24,561 / 24,937 (98.5%) |

La Liga's `complete` is below `with end` because some ended spells have no start. Everywhere else, open current spells pull `complete` back above `with end`.

The Championship item has only three seasons linked. Its date rates are real for the 24 clubs Wikidata currently places there, and those spells include years the clubs spent in other divisions. "Ever played in the Championship" is not what the three seasons measure.

## Spot-check

`career-spell-spotcheck.rq` was run on 2026-11-13 and compared with the English Wikipedia infobox for each player. Youth teams were ignored. A row passes when the senior clubs for that comparison are present and none of them is the wrong club. Year-only values are stored as 1 January, so they are not treated as real days.

Preferred rank is not a current squad. Eight clubs Wikidata places in the Championship right now (Watford, Lincoln City, Wrexham, Swansea, Cardiff, Middlesbrough, Norwich, Queens Park Rangers) have 0–2 players on a preferred-rank spell. Jordan Rhodes is the lower-league career instead.

| Player | Wikidata | What to compare | Missing clubs | Wrong or missing dates | Pass |
| --- | --- | --- | --- | --- | --- |
| Erling Haaland | Q28967995 | Current career | None of the senior clubs | Dortmund ends, and City starts, on 1 Jan 2022. He joined City in July 2022. | Yes |
| Thierry Henry | Q45901 | Arsenal and Barcelona | None for those two clubs | Juventus is a single timestamp in 1999. The 2012 Arsenal loan is present (6 Jan–15 Feb). | Yes |
| Johan Cruyff | Q17163 | Ajax and Barcelona, pre-1990 | None of the senior clubs | Year precision only. Both clubs are present and start before 1990. | Yes |
| Bobby Moore | Q191492 | Career through 1978 | Edmonton Black Gold, a short 1978 spell | West Ham and Fulham match the years. Herning Fremad is stored as FC Midtjylland. NASL Seattle Sounders is duplicated onto Seattle Sounders FC, through 1979. | No |
| Jordan Rhodes | Q326397 | Championship career | Norwich, Huddersfield from 2021, Blackpool, Mansfield | Sheffield Wednesday has no dates. Middlesbrough starts in 2016 and has no end. The dated spells stop in 2016. | No |
| Joel Campbell | Q356797 | Loans | Lorient II, Monterrey, Atlético Goianiense, Inter de San Carlos. León's 2020–2023 stay. | Arsenal is only the gaps between loans, not 2011–2018. Frosinone has no end from July 2020 and overlaps later clubs. | No |

## Gaps

The rates below are the league counts. The spot-check is where a present spell was still the wrong club.

- Both-clubs prompts need the club link. The lists are uneven. Current Bundesliga clubs average about 315 spells, Ligue 1 about 480, La Liga about 650, Serie A about 775, and the Premier League and Championship about 1,000. A thin list means real careers are absent even when the spells that exist are dated.
- Era prompts need a start. Starts are missing on about 10% of spells in Serie A, Ligue 1, and the Championship, about 13% in the Bundesliga and the First Division season set, about 15% in the Premier League, about 18% in 2. Bundesliga, and about 24% in La Liga.
- Spells that already have a pre-1990 start are almost all closed (98% or better in every row). This run cannot tell whether the undated spells are the old ones.
- Lower leagues: Championship date rates look like the top leagues, with the season-graph hole above. 2. Bundesliga is thinner and less often dated (76.5% complete).
- Pre-1990 England: use the 56 First Division season clubs, not the four clubs still pointing at that league through P118.

## For the data-source ADR

Wikidata stays a drafting aid. The curated answer list is the source of truth. These rates say where a draft is worth reading, not where it can be trusted. Serie A, Ligue 1, the Championship, and the Premier League have the thickest dated lists. La Liga needs the most date repair. The Bundesliga list is the thinnest. Do not copy issue #8's phrase "Wikidata as primary source."

## Decision

Club-based prompts can be drafted from Wikidata career data for review, then checked by hand. In the thicker leagues about 85–91% of spells have a start: Premier League 85%, Championship 90%, Serie A and Ligue 1 91%. A complete spell, with an end or an open current club, is about 82–88% there, 72% in La Liga, and 77% in 2. Bundesliga. The Bundesliga list is too thin to draft from, at about 315 spells per current club.

Drafting queries have to run a few clubs at a time. One request for a whole league exceeds the public query service time limit. Use season items (P3450 on the season, P1923 for the clubs that took part) to choose which clubs have played in a competition. P118 is the current league only, and without a club-type filter it is mostly people.

The spot-check passed for three famous club lists (Haaland, Henry at Arsenal and Barcelona, Cruyff at Ajax and Barcelona). It failed when the club item was wrong (Bobby Moore), when later loans were missing or left open (Joel Campbell), and when a Championship career stopped in 2016 (Jordan Rhodes). A 1 January date means the year, not the day, so it is not safe for a same-season prompt.

Honours and national-team prompts are untested. See #47.
