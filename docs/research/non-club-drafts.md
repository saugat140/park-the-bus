# Wikidata drafts for non-club prompts

Issue #47. 

Run on 2026-11-16.

## Prompts

| Prompt | Question | Reference |
| --- | --- | --- |
| Honours | Who has won the men's Ballon d'Or? | France Football palmarès, checked against the UEFA laureates list. 1956 through 2026. Not awarded in 2020. |
| National team | Who has a senior cap for England? | The FA legacy count of 19 March 2025, and the England cap records published on 12 November 2026. |
| Older era | Who was in each 22-man squad at the 1966 World Cup? | The published 1966 squad lists. 16 teams, 22 players each. |

## Honours

`tools/wikidata/ballon-dor-winners.rq` reads award received (P166) for the Ballon d'Or (Q166177) and the FIFA Ballon d'Or (Q2291862, the joint trophy from 2010 to 2015). The result is `docs/research/ballon-dor-winners-run.csv`.

The reference list is 70 awards and 48 people. France Football lists Harry Kane as the 2026 winner. Wikidata returned 68 statements and 49 people.

The people list is one winner short and has two names to remove.

| Case | Name | What the statement says |
| --- | --- | --- |
| Missing | Luis Suárez (Q270367) | The 1960 winner. No Ballon d'Or statement. |
| Remove | Phil Foden (Q30729096) | FIFA Ballon d'Or, normal rank, no date. He did not win it. |
| Remove | Aitana Bonmatí (Q27995553) | Ballon d'Or dated 2024-01-01, conferred by France Football. She won the women's award. That statement uses the same award item as the men's trophy. Rodri is the 2024 men's winner on that item, dated 2024-10-28. |

Cristiano Ronaldo is present for 2008, 2013, and 2014. His 2016 and 2017 wins are absent. Franz Beckenbauer has one undated statement and won in 1972 and 1976.

Fourteen winners are present with no year: Stanley Matthews, Denis Law, Eusébio, Franz Beckenbauer, George Best, George Weah, Gerd Müller, Gianni Rivera, Igor Belanov, Josef Masopust, Lev Yashin, Lothar Matthäus, Paolo Rossi, and Allan Simonsen. A 1 January date is year precision. Kane's 2026 win is stored as 2026-01-01.

## National team

`tools/wikidata/england-senior-members.rq` reads non-deprecated membership (P54) of the England men's national team (Q47762). `caps` is the match count on that statement (P1350). A blank is not zero. The result is `docs/research/england-senior-members-run.csv`.

Wikidata has 1,339 people. 1,229 have a positive match count, 110 have no number, and none are stored as zero. 1,255 have a start date and 1,203 have an end date.

The FA's legacy article of 19 March 2025 counts 1,290 senior men's internationals, with Taylor Harwood-Bellis the most recent debutant named there (November 2024). More players have debuted since. On 12 November 2026 England recorded Harry Kane on 126 caps, Peter Shilton on 125, and Wayne Rooney on 120.

| Player | Wikidata | Published |
| --- | --- | --- |
| Peter Shilton | 125 caps, 1970-01-01 to 1990-01-01 | 125 caps |
| Wayne Rooney | 120 caps, 2003-01-01 to 2018-01-01 | 120 caps |
| Bobby Moore | 108 caps, 1962-01-01 to 1973-01-01 | 108 caps |
| Harry Kane | 125 caps, from 2015-01-01, no end | 126 caps on 12 November 2026 |
| Taylor Harwood-Bellis | Member, no caps, no dates | Debuted November 2024 |

Abbie McManus is the only non-male person on this membership. She is a women's international.

The dates that are present are year precision.

## Older era

`tools/wikidata/wc1966-squads.rq` keeps footballers who are marked as participating in the 1966 World Cup (P1344, Q134202) and who are a member of one of the 16 finalist teams. The result is `docs/research/wc1966-squads-run.csv`.

The 16 squad items exist (class Q25000767, "England at the 1966 FIFA World Cup" and the rest) and none of them lists a player. A raw participant count is 384. That number includes the 16 squad items, the 16 national teams, and the class item, on top of the players.

The join produces 349 rows and 348 players. Héctor De Bourgoing is counted twice.

| Team | Players | Against 22 |
| --- | ---: | --- |
| Argentina | 23 | De Bourgoing, who was in the France squad, is also a member of the Argentina team |
| Brazil | 22 | |
| Bulgaria | 22 | |
| Chile | 22 | |
| England | 22 | |
| France | 21 | Johnny Schuth is a tournament participant and is not a member of the France team item |
| West Germany | 22 | Stored on the Germany men's team, Q43310 |
| Hungary | 22 | |
| Italy | 22 | |
| Mexico | 22 | |
| North Korea | 21 | Ryoo Chang-kil is a tournament participant and is not a member of the North Korea team item |
| Portugal | 20 | João Lourenço is a tournament participant and is not a member of the Portugal team item. José Torres is in the squad list and is not a tournament participant |
| Soviet Union | 22 | |
| Spain | 22 | |
| Switzerland | 22 | |
| Uruguay | 22 | |

A count of 22 was not name-checked. The names above are the ones that were opened against the squad list.

## Decision

A men's Ballon d'Or winner list is worth drafting from Wikidata. Add Luis Suárez and remove Phil Foden and Aitana Bonmatí. Do not draft "who won in this year" from the dates. Fourteen winners have no year, Beckenbauer is stored once, and Cristiano is missing two of his five.

An England cap list is not the membership list. Draft from the 1,229 names that have a match count, then check the 110 with no number before any of them becomes an answer. The count goes stale: Kane is one cap behind the figure England published on 12 November 2026. Checking gender caught one wrong person, Abbie McManus.

A 1966 squad list is worth drafting from the join of tournament participation and national-team membership. Twelve teams come out at 22 players. The checked repairs are De Bourgoing off the Argentina list, three players who are on the tournament but not on their national team, and José Torres, who is missing from the tournament. The squad items themselves are empty.