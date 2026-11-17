# ADR 0004: Answer judging

Status: accepted, 2026-11-16. Issue #8.

## Context

A correct answer is worth more when fewer players give it, so the judge has to be the same for everyone and the same tomorrow as today. The tempting alternative is to send the typed text to a model and trust the reply.

## Decision

The server is the only judge. Matching and scoring run in the API, against that prompt's curated list. Answer lists, aliases, and fame ratings never reach the client before the prompt is finished for that session. The full list is returned only then.

Players type free text. The MVP has no autocomplete. The server normalizes the input and matches it against this prompt's entities only: exact alias, then prefix or word, then a typo match. One confident match is scored. Several plausible matches return "Did you mean …?" choices, names and disambiguation only, drawn from that prompt's matches. No match is incorrect.

Scoring is deterministic. The same input for the same prompt always produces the same result. No language model, and no other non-deterministic service, runs during play.

A language model may be used offline to draft candidate answers, suggest aliases, or triage unmatched guesses. Every suggestion is reviewed before it changes data. Accuracy is measured on an evaluation set of known answers, famous and obscure, and recorded under `docs/research/`, before a model is relied on. The set is rerun when the model or the prompt changes.

Play is anonymous at launch. A random session id in browser storage. No accounts and no personal data.

## Alternatives

Autocomplete against the entity pool. Faster to type. The suggestion list would show valid answers before the player has thought of them. Revisit it only when the pool is large enough that a suggestion does not give the prompt away.

A model judging answers during play. This was considered and rejected:

- Rate limits. A daily puzzle is a burst of requests at the same minute, and a limit would fail answers that the database would have scored.
- Data terms. The typed guess, and the prompt, would be sent to a third party.
- Obscure players. The misses that matter are the uncommon correct answers, which is where a model is weakest.
- Inconsistency. The same guess can be accepted one day and rejected the next, which breaks a shared score.
- Prompt injection. Player text would be instructions to the model. In the database it is a string to normalize and match.

## Consequences

Any change to normalization, matching thresholds, or scoring needs tests. Player input is untrusted text and is never interpreted as instructions or code. Answer and start endpoints are rate-limited per IP and per session.
