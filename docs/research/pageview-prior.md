# Pageviews and language editions as draft signals for prior rarity

Issue #6. Drafting aid only. Neither number sets points.

The working choice is English Wikipedia pageviews, with the number of Wikipedia language editions read beside them.

## What the number is for

Prior rarity is the fame rating, from 1 to 5, on an answer before anyone has played that prompt. After launch, observed answer counts are blended with that rating. Until those counts exist, a public number can suggest the rating while an answer list is being drafted. The rating is still set by hand.

## Window

Twelve complete months: 1 November 2025 through 31 October 2026. The request uses English Wikipedia, every access method, and user views only. A player with no English article has a blank total. A blank is not fame 1.

## Rank these players first

Write a fame rating from 1 to 5 in the last column before running the script. 5 is a name almost everyone would give. 1 is a name only a specialist would give. The pageview script does not read this column.

| Player | Wikidata | Your fame (1–5) |
| --- | --- | --- |
| Lionel Messi | Q615 | 5 |
| Cristiano Ronaldo | Q11571 | 5 |
| Kylian Mbappé | Q21621995 | 5 |
| Erling Haaland | Q28967995 | 5 |
| Kevin De Bruyne | Q357984 | 4 |
| Bukayo Saka | Q59306386 | 3 |
| Harry Kane | Q969725 | 4 |
| Son Heung-min | Q439722 | 3 |
| Jamal Musiala | Q96072055 | 3 |
| Thomas Müller | Q43666 | 3 |
| Thierry Henry | Q45901 | 4 |
| Zinedine Zidane | Q1835 | 4 |
| Johan Cruyff | Q17163 | 4 |
| Pelé | Q12897 | 5 |
| Bobby Moore | Q191492 | 3 |
| Sócrates | Q102331 | 3 |
| Jordan Rhodes | Q326397 | 1 |
| Billy Sharp | Q740239 | 1 |
| Joel Campbell | Q356797 | 1 |
| David Strelec | Q56043497 | 1 |

A name in this table and in `tools/wikidata/enwiki-titles.rq` must be changed together.

## How to pull the totals

From the repo root, after the fame column is filled:

```powershell
powershell -File tools/wikidata/pageview-prior.ps1
```

The script reads English article titles from `enwiki-titles.rq` and writes `docs/research/pageview-prior-run.csv` with `player`, `qid`, `title`, `views`, and `months`. `months` should be 12. A blank `views` means the article title was missing or the request returned no series.

One article, to see the request shape:

```text
GET https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/Erling_Haaland/monthly/2025110100/2026103100
```

Send a User-Agent. Sum the `views` fields on the monthly rows.

## Language editions

The edition count is how many Wikipedia languages have an article on the player. Sister projects (Wiktionary, Wikiquote, Commons, and the rest) are not included.

`tools/wikidata/wikipedia-editions.rq` counts sitelinks whose wiki group is `wikipedia`. On 15 November 2026 the public query service returned nothing within 60 seconds, so the numbers below came from the Wikidata entity API instead: `action=wbgetentities` with `props=sitelinks/urls`, counting sitelinks whose URL is on `wikipedia.org`. The same twenty players. The result is `docs/research/wikipedia-editions-run.csv`.

## Comparison

Pageviews from `pageview-prior-run.csv`, highest first. Every pageview row has 12 months. Editions from `wikipedia-editions-run.csv`, counted 15 November 2026. Fame is the rating in the table above.

| Player | Fame | Pageviews | Editions | Where they pull apart |
| --- | ---: | ---: | ---: | --- |
| Cristiano Ronaldo | 5 | 15,679,918 | 186 | |
| Lionel Messi | 5 | 15,482,601 | 198 | |
| Erling Haaland | 5 | 13,816,325 | 94 | Views put him with the other 5s. Editions put him with Kane (4) and Müller (3). |
| Kylian Mbappé | 5 | 10,138,758 | 119 | Views put him with the 5s. Editions put him just under Zidane (4). |
| Harry Kane | 4 | 7,680,383 | 92 | Views sit closer to Mbappé than to Zidane. Editions sit with the other 4s. |
| Zinedine Zidane | 4 | 3,607,536 | 123 | Editions put him above Mbappé (5). |
| Thierry Henry | 4 | 3,160,811 | 88 | |
| Pelé | 5 | 3,149,677 | 151 | Views tie him with Henry (4). Editions put him third, with the 5s. |
| Bukayo Saka | 3 | 2,270,012 | 70 | Views put him above De Bruyne and Cruyff (both 4). Editions put him below them. |
| Son Heung-min | 3 | 1,714,331 | 76 | Views put him just above De Bruyne (4). Editions put him below De Bruyne and Henry. |
| Kevin De Bruyne | 4 | 1,653,664 | 90 | Views put him below Saka and Son. Editions put him with Kane and Henry. |
| Johan Cruyff | 4 | 1,200,459 | 107 | Views put him with Müller and Musiala (both 3). Editions put him above Haaland (5). |
| Thomas Müller | 3 | 1,188,287 | 91 | Editions put him with De Bruyne and Kane (both 4). |
| Jamal Musiala | 3 | 1,100,776 | 60 | |
| Bobby Moore | 3 | 411,862 | 56 | Views put him near Sharp (1). Editions put him with Musiala and Sócrates. |
| Sócrates | 3 | 353,489 | 61 | Views put him near Sharp (1). Editions put him with Musiala. |
| Billy Sharp | 1 | 168,905 | 24 | |
| Joel Campbell | 1 | 89,693 | 44 | Editions put him closer to Moore (3) than to Sharp. |
| David Strelec | 1 | 52,282 | 23 | |
| Jordan Rhodes | 1 | 50,998 | 21 | |

By pageviews, the four 5s other than Pelé are the top four, all above 10 million, and the four 1s are the bottom four, all under 170,000. Inside the 3s and 4s the order does not follow the ratings. Cruyff, Moore, and Sócrates land too quiet.

By editions the order is Messi 198, Ronaldo 186, Pelé 151, Zidane 123, Mbappé 119, Cruyff 107, Haaland 94, Kane 92, Müller 91, De Bruyne 90, Henry 88, Son 76, Saka 70, Sócrates 61, Musiala 60, Moore 56, Campbell 44, Sharp 24, Strelec 23, Rhodes 21. That puts Pelé with the 5s, puts Saka and Son back under De Bruyne, and pulls Moore and Sócrates away from Sharp. It misses the current peak: Haaland (5) has 94 editions, next to Kane (92) and Müller (91), and Mbappé (119) sits just under Zidane (123). Campbell (1) has 44, nearer Moore (56) than Sharp (24). The four 1s are still the bottom four.

## Decision

Pageviews stay the number used to sort a draft. On this sample they separate the current 5s and the 1s. The edition count is the check beside that total, not a second sort. Read it when a name is old, or when the English page looks unusually busy: it lifts Pelé, Cruyff, Moore, and Sócrates, and it drops Saka and Son below De Bruyne. Sorting by editions alone would drop Haaland in with the 4s and lift Müller in with them. The rating is still set manually initial before live user data.