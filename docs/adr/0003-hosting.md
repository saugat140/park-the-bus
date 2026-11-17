# ADR 0003: Hosting requirements

Status: proposed, 2026-11-16. Issue #8.

No provider is chosen. A later ADR supersedes this one with that choice. This note is the list that choice has to satisfy.

## Decision

The puzzle a player sees is the row whose date is the current UTC date. The API reads that row. No job has to run for today's puzzle to exist, so a missed job cannot take the game down. The client shows the countdown to the next UTC date in local time.

The scheduled job is the nightly rarity recompute from ADR 0001. That job is not on the path that serves the puzzle.

The host has to provide:

- The Next.js app on a static or edge host, and the API as a container, deployable separately. The container is what makes a later change of host possible.
- The API and PostgreSQL in the same region. Matching runs in the database on the request path.
- PostgreSQL 16 or newer, with permission to create `pg_trgm`, `unaccent`, and `fuzzystrmatch`.
- Staging and production, with separate databases.
- Automated backups and a restore that has been run, not only configured.
- CDN caching for today's puzzle until the UTC date rolls over.
- A monthly spending cap with alerts.
- Secrets outside the repository. Connection strings, API keys, and deploy credentials are not committed.

The provider, the region, and whether the database is managed or run beside the API are not decided.

## Alternatives

A job at 00:00 UTC that publishes today's puzzle. One clock for the whole game. A missed or delayed run means there is no puzzle to serve. Dating the rows, and reading the row for the current UTC date, keeps a missed job off that path.

## Consequences

Local development does not wait on a provider. Empty `api/` and `web/` trees, and CI that builds them, wait until there is code to build. Issue #7 stays a README update until then.
