# ADR 0001: Stack

Status: accepted, 2026-11-16. Issue #8.

## Context

The game needs a web client, an API that judges answers, and a database that can do trigram and edit-distance matching. This product is a separate repository from org-platform, and the matching work there is C#.

How answers are judged is ADR 0004. Where this runs is ADR 0003.

## Decision

- The web app is Next.js (App Router), React, TypeScript in strict mode, and Tailwind.
- The API is ASP.NET Core on .NET 10, with controllers.
- The database is PostgreSQL 16 or newer, with `pg_trgm`, `unaccent`, and `fuzzystrmatch`. Access is through Npgsql.
- Entity Framework Core is for ordinary create, read, update, and delete. Matching, scoring, and the normalization function are hand-written parameterized SQL.
- The whole schema is versioned SQL files under `db/`, always committed. That includes tables, the normalization function, indexes, and seed data. Entity Framework does not generate or own migrations.
- Normalization is one SQL function: lowercase, strip accents, drop apostrophes and periods, turn other punctuation into spaces, and collapse whitespace.
- Tests are xUnit with Testcontainers for the API, Vitest for the web app, and one Playwright test that plays the daily game.
- The puzzle for a UTC date is a row in the database. No job publishes it. The only scheduled job is the nightly rarity recompute. Hangfire with PostgreSQL storage, or a host cron, may run that job. ADR 0003.
- Do not add MediatR, AutoMapper, MassTransit, or FluentAssertions.

## Alternatives

Next.js API routes only. One deploy, and one language on the server. Matching would be rewritten in TypeScript, and the C# work shared with org-platform would not carry over.

One ASP.NET app that also serves the pages. One process. The web app would give up the App Router and a separate static or edge deploy.

Entity Framework for matching and scoring. One data-access style. The match is trigram and edit distance in SQL. An ORM query would hide the plan that has to stay deterministic and covered by tests.

Entity Framework migrations, including raw-SQL steps for the functions. The functions and indexes are the schema that scores the game, and the ORM does not model them. Two migration styles in one project drift. Versioned SQL files keep that schema in one place.

MediatR, AutoMapper, MassTransit, and FluentAssertions. Each now carries a commercial license. The API is controllers, records, and SQL, and does not need them.

## Consequences

A new library needs a reason, and a license check, before it is added. A change to normalization, matching, or scoring is a change to a SQL file under `db/`, with tests. The API and the web app deploy separately once a host is chosen.
