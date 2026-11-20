-- First schema. Issue #10.
-- Versioned SQL, not an Entity Framework migration. ADR 0001.
--
-- Ten tables. This is the curated answer database: reviewed lists,
-- not a Wikidata fact store. There is no career, cap, or honour
-- table, and a prompt has no generator query. Why an answer is valid
-- lives in prompts.source_notes and the research notes.
-- Diagram: docs/db/erd.md.
--
-- Apply to an empty PostgreSQL 16 database:
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/001_schema.sql
-- Then:
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/001_schema_test.sql
--
-- Entity and alias CSV import is db/002_import_entities.sql.
-- The test file rolls back. It does not leave players behind.
-- Tier points below are the game scale. Issue #56.
-- min_rarity and max_rarity stay empty until issue #21.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- unaccent() is stable, so a generated column cannot call it.
-- Pin the dictionary and mark the wrapper immutable.
CREATE OR REPLACE FUNCTION immutable_unaccent(input text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
STRICT
AS $$
BEGIN
  RETURN public.unaccent('public.unaccent'::regdictionary, input);
END;
$$;

-- Lowercase, strip accents, drop apostrophes and periods, turn other
-- punctuation into spaces, collapse whitespace.
-- Named normalize_answer because PostgreSQL already owns normalize()
-- for Unicode form conversion.
CREATE OR REPLACE FUNCTION normalize_answer(input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT trim(both FROM regexp_replace(
    regexp_replace(
      regexp_replace(
        lower(immutable_unaccent(coalesce(input, ''))),
        '[''’‘ʼ]', '', 'g'
      ),
      '[^[:alnum:][:space:]]', ' ', 'g'
    ),
    '[[:space:]]+', ' ', 'g'
  ));
$$;

CREATE TABLE rarity_tiers (
  tier_number smallint PRIMARY KEY,
  display_name text NOT NULL UNIQUE,
  points integer NOT NULL CHECK (points >= 0),
  min_rarity numeric,
  max_rarity numeric,
  CHECK (tier_number BETWEEN 1 AND 6)
);

COMMENT ON TABLE rarity_tiers IS
  'Tier 1 is the common end and scores the least. Tier 6 is the rare end and scores the most.';

COMMENT ON COLUMN rarity_tiers.min_rarity IS
  'Lower bound of the blended rarity for this tier. Empty until issue #21.';

COMMENT ON COLUMN rarity_tiers.max_rarity IS
  'Upper bound of the blended rarity for this tier. Empty until issue #21.';

INSERT INTO rarity_tiers (tier_number, display_name, points) VALUES
  (1, 'Sunday League', 10),
  (2, 'Championship', 20),
  (3, 'FA Cup', 40),
  (4, 'Premier League', 60),
  (5, 'Champions League', 80),
  (6, 'World Cup', 100);

CREATE TABLE entities (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('player', 'club')),
  canonical_name text NOT NULL,
  disambiguation text,
  wikidata_qid text UNIQUE
);

COMMENT ON COLUMN entities.disambiguation IS
  'Shown with "Did you mean …?" when two entities share an alias. Example: Germany, born 1989.';

CREATE TABLE entity_aliases (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entity_id bigint NOT NULL REFERENCES entities (id),
  alias text NOT NULL,
  alias_normalized text GENERATED ALWAYS AS (normalize_answer(alias)) STORED,
  UNIQUE (entity_id, alias_normalized)
);

CREATE INDEX entity_aliases_normalized_trgm
  ON entity_aliases USING gin (alias_normalized gin_trgm_ops);

COMMENT ON TABLE entity_aliases IS
  'The same normalized alias may belong to more than one entity. Matching asks which one.';

CREATE TABLE prompts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prompt_text text NOT NULL,
  answer_kind text NOT NULL CHECK (answer_kind IN ('player', 'club')),
  difficulty smallint NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  tags text[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'reviewed', 'retired')),
  source_notes text,
  last_used_on date
);

COMMENT ON COLUMN prompts.last_used_on IS
  'A prompt is not reused within 90 days of this date. Played prompts are retired, not deleted.';

CREATE TABLE prompt_answers (
  prompt_id bigint NOT NULL REFERENCES prompts (id),
  entity_id bigint NOT NULL REFERENCES entities (id),
  fame smallint NOT NULL CHECK (fame BETWEEN 1 AND 5),
  prior_rarity numeric,
  observed_count integer NOT NULL DEFAULT 0 CHECK (observed_count >= 0),
  blended_rarity numeric,
  tier_number smallint REFERENCES rarity_tiers (tier_number),
  PRIMARY KEY (prompt_id, entity_id)
);

CREATE INDEX prompt_answers_entity_id ON prompt_answers (entity_id);

CREATE TABLE daily_puzzles (
  puzzle_date date PRIMARY KEY,
  theme text
);

COMMENT ON TABLE daily_puzzles IS
  'The puzzle for a UTC date is this row. No job has to publish it.';

CREATE TABLE daily_puzzle_prompts (
  puzzle_date date NOT NULL REFERENCES daily_puzzles (puzzle_date),
  position smallint NOT NULL CHECK (position >= 1),
  prompt_id bigint NOT NULL REFERENCES prompts (id),
  PRIMARY KEY (puzzle_date, position),
  UNIQUE (puzzle_date, prompt_id)
);

CREATE TABLE prompt_starts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  puzzle_date date NOT NULL,
  prompt_id bigint NOT NULL,
  session_id uuid NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (puzzle_date, prompt_id, session_id),
  FOREIGN KEY (puzzle_date, prompt_id)
    REFERENCES daily_puzzle_prompts (puzzle_date, prompt_id)
);

CREATE TABLE submissions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  puzzle_date date NOT NULL,
  prompt_id bigint NOT NULL REFERENCES prompts (id),
  session_id uuid NOT NULL,
  raw_input text NOT NULL,
  matched_entity_id bigint REFERENCES entities (id),
  correct boolean NOT NULL,
  points integer NOT NULL CHECK (points >= 0),
  UNIQUE (puzzle_date, prompt_id, session_id),
  FOREIGN KEY (puzzle_date, prompt_id)
    REFERENCES daily_puzzle_prompts (puzzle_date, prompt_id)
);

CREATE TABLE answer_reports (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  puzzle_date date NOT NULL,
  prompt_id bigint NOT NULL,
  session_id uuid NOT NULL,
  raw_input text NOT NULL,
  report_kind text NOT NULL CHECK (report_kind IN ('wrong', 'missing')),
  review_status text NOT NULL DEFAULT 'open' CHECK (review_status IN ('open', 'accepted', 'rejected')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (puzzle_date, prompt_id)
    REFERENCES daily_puzzle_prompts (puzzle_date, prompt_id)
);

-- Candidates for one prompt. Exact beats a whole word, which beats a prefix,
-- which beats a typo. A typo needs both a trigram similarity and a short
-- edit distance, on the whole alias or on one word of it.
-- An entity that is not on this prompt cannot be returned.
CREATE OR REPLACE FUNCTION match_prompt_answer(p_prompt_id bigint, p_raw text)
RETURNS TABLE (
  entity_id bigint,
  canonical_name text,
  disambiguation text,
  match_kind text
)
LANGUAGE sql
STABLE
AS $$
  WITH query AS (
    SELECT normalize_answer(p_raw) AS q
  ),
  aliases AS (
    SELECT e.id AS entity_id,
           e.canonical_name,
           e.disambiguation,
           a.alias_normalized
    FROM prompt_answers pa
    JOIN entities e ON e.id = pa.entity_id
    JOIN entity_aliases a ON a.entity_id = e.id
    CROSS JOIN query
    WHERE pa.prompt_id = p_prompt_id
      AND (SELECT q FROM query) <> ''
  ),
  ranked AS (
    SELECT aliases.entity_id,
           aliases.canonical_name,
           aliases.disambiguation,
           CASE
             WHEN aliases.alias_normalized = query.q THEN 1
             WHEN query.q = ANY (string_to_array(aliases.alias_normalized, ' ')) THEN 2
             WHEN length(query.q) >= 3 AND (
               aliases.alias_normalized LIKE query.q || '%'
               OR aliases.alias_normalized LIKE '% ' || query.q || '%'
             ) THEN 3
             WHEN length(query.q) BETWEEN 4 AND 80 AND (
               (
                 similarity(aliases.alias_normalized, query.q) >= 0.4
                 AND levenshtein(left(aliases.alias_normalized, 255), left(query.q, 255)) <= 2
               )
               OR EXISTS (
                 SELECT 1
                 FROM unnest(string_to_array(aliases.alias_normalized, ' ')) AS token
                 WHERE length(token) BETWEEN 4 AND 80
                   AND similarity(token, query.q) >= 0.5
                   AND levenshtein(token, query.q) <= 1
               )
             ) THEN 4
           END AS rank
    FROM aliases
    CROSS JOIN query
  ),
  best AS (
    SELECT min(rank) AS rank
    FROM ranked
    WHERE rank IS NOT NULL
  )
  SELECT DISTINCT
    ranked.entity_id,
    ranked.canonical_name,
    ranked.disambiguation,
    CASE ranked.rank
      WHEN 1 THEN 'exact'
      WHEN 2 THEN 'word'
      WHEN 3 THEN 'prefix'
      WHEN 4 THEN 'typo'
    END AS match_kind
  FROM ranked
  JOIN best ON ranked.rank = best.rank;
$$;

-- Points for one accepted answer. Null when the entity is not on the prompt
-- or the row has no tier yet.
CREATE OR REPLACE FUNCTION score_prompt_answer(p_prompt_id bigint, p_entity_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
  SELECT rarity_tiers.points
  FROM prompt_answers
  JOIN rarity_tiers ON rarity_tiers.tier_number = prompt_answers.tier_number
  WHERE prompt_answers.prompt_id = p_prompt_id
    AND prompt_answers.entity_id = p_entity_id;
$$;
