# park-the-bus

Park the Bus is a free daily soccer trivia game. Everyone plays the same prompts. Many answers are valid, and a rarer correct answer scores more. The curated database is the source of truth. Wikidata and pageviews are drafting aids only.

A Truepeak Software LLC game. This repository is separate from org-platform.

## Decisions

- [Stack](docs/adr/0001-stack.md). Next.js, ASP.NET Core, PostgreSQL. Matching and scoring are versioned SQL.
- [Data source](docs/adr/0002-data-source.md). A reviewed answer list. Wikidata is not the primary source.
- [Hosting requirements](docs/adr/0003-hosting.md). Proposed. No provider is chosen.
- [Answer judging](docs/adr/0004-answer-judging.md). The server is the only judge. No autocomplete, and no model during play.

## Research

- [Wikidata career coverage](docs/research/wikidata-career-coverage.md). Where a club-career draft is worth reading.
- [Pageview prior rarity](docs/research/pageview-prior.md). Pageviews sort a fame draft. Language editions are the check.
- [Non-club drafts](docs/research/non-club-drafts.md). Ballon d'Or winners, England caps, and the 1966 squads.

## Status

Research and setup. There is no application code in this repository yet. `api/`, `web/`, and CI arrive with the first code that needs them.
