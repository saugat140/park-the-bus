# ADR 0002: Data source

Status: accepted, 2026-11-16. Issue #8.

## Context

Each prompt needs a reviewed list of answers before anyone plays it. Wikidata, Wikipedia, and pageview counts are public and tempting to treat as the list. The research notes measured where those sources are wrong, thin, or stale.

## Decision

The curated PostgreSQL answer list is the source of truth. Wikidata and pageviews are drafting aids. They do not set points, and nothing is imported on a schedule. A row scores only after it has been accepted into the curated list.

Drafts follow these rules. The counts and the names that failed a check stay in the research notes.

- Club careers may be drafted from Wikidata only where `docs/research/wikidata-career-coverage.md` says the list is thick enough. Every spell is reviewed. A 1 January date is the year, not the day, so it cannot settle a same-season prompt. Draft a few clubs at a time. A query for a whole league exceeds the public query service time limit.
- Award winners: draft the people, never the year. `docs/research/non-club-drafts.md`.
- Tournament squads: draft by joining participation to the national team, then name-check. The squad item for a tournament does not hold the players. Same note.
- National-team caps: do not draft a cap list from team membership. A membership statement is not a cap. A match-count qualifier is still a draft figure and goes stale. Same note.
- Wikidata's preferred-rank statement on P54 (member of sports team) does not reliably identify a club's current squad. Preferred rank is a flag on one statement. A club can have that flag on the wrong player, or on almost nobody. It is not a squad list.
- Prior rarity, before anyone has played a prompt: sort a draft by English Wikipedia pageviews, and read the language-edition count when a name is old or the English page looks unusually busy. The 1–5 rating is set by hand. After launch, observed answer counts are blended with that rating. `docs/research/pageview-prior.md`.

An entity is stored once, with aliases. Rarity is counted on the entity, not on the typed string. A played prompt is retired, not hard-deleted. A prompt is not reused within 90 days.

## Alternatives

Wikidata as the primary source. This was the original wording of issue #8. The research rejected it. Club spells name the wrong club, stop early, or have no date. Award statements miss a winner, include someone who did not win, and often have no year. National-team membership is not a list of caps.

A live import that writes answers without review. The same gaps would reach players and would score.

Pageviews or language-edition counts as the rating. They sort a draft. They disagree with a hand rating in the middle of the scale, and they disagree with each other. The rating stays a hand edit.

## Consequences

Wikidata is CC0. Attribution is optional. Credit it on the About page. Wikipedia text is CC BY-SA, so prompt text and descriptions are never copied from a Wikipedia article. A pageview total and an edition count are numbers, not article text.

An answer that scores points has been accepted into the curated list. A Wikidata row is not that acceptance.
