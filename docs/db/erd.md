# Curated answer database

Issue #10. The database stores reviewed answer lists. It does not store career spells, caps, or honours, and a prompt is not a query. Why an answer is valid lives in `source_notes` and the research notes.

```mermaid
erDiagram
  entities ||--o{ entity_aliases : "spelled as"
  entities ||--o{ prompt_answers : "approved for"
  prompts ||--o{ prompt_answers : "lists"
  rarity_tiers ||--o{ prompt_answers : "scores"
  daily_puzzles ||--o{ daily_puzzle_prompts : "schedules"
  prompts ||--o{ daily_puzzle_prompts : "used on"
  daily_puzzle_prompts ||--o{ prompt_starts : "timer"
  daily_puzzle_prompts ||--o{ submissions : "receives"
  entities ||--o{ submissions : "matched"
  daily_puzzle_prompts ||--o{ answer_reports : "reported on"
```

`entities` is one row per player or club curated, with a disambiguation line and an optional Wikidata id. `entity_aliases` is one alias table for both. `prompt_answers` is the list reviewed, with a fame rating from 1 to 5. `prompt_starts` is the server time a session first saw a scheduled prompt.