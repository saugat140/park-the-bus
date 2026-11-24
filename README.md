# park-the-bus

Park the Bus is a free daily soccer trivia game. Everyone plays the same prompts. Many answers are valid, and a rarer correct answer scores more. The curated database is the source of truth. Wikidata and pageviews are drafting aids only.

A Truepeak Software LLC game. The [purpose note](docs/product-purpose.md) is the business record: who it is for, and no revenue in the MVP.

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

The first schema is [`db/001_schema.sql`](db/001_schema.sql). The diagram is [`docs/db/erd.md`](docs/db/erd.md).

`GET /puzzles/today` returns the prompts scheduled for the current UTC date. The body is the prompt text, its id, and its position. Answers, aliases, fame ratings, and tiers stay in the database. A date with nothing playable is not cached. A playable puzzle is cached until the next 00:00 UTC. The number of prompts is whatever that date has. Five or seven a day is still an open choice. `web/` and CI arrive with the first code that needs them.

The API reads `ConnectionStrings__ParkTheBus`. Publish port 5432 on the local database, apply the schema, then:

```powershell
$env:ConnectionStrings__ParkTheBus = "Host=localhost;Database=park_the_bus;Username=postgres;Password=postgres"
dotnet run --project api/ParkTheBus.Api
```

That password is only the local database. `dotnet test api/ParkTheBus.slnx` starts its own PostgreSQL 16 container and calls the route.
