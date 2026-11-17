-- Smoke test for db/001_schema.sql. Issue #10.
-- Rolls back. Safe to run against a database that already has the schema.
-- This is not the xUnit suite in issue #26.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/001_schema_test.sql
-- Accented letters are written as U& escapes so a Windows pipe
-- cannot drop them before they reach the database.

BEGIN;

INSERT INTO entities (kind, canonical_name, disambiguation) VALUES
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989'),
  ('player', 'Thomas Muller', 'a different Muller'),
  ('player', U&'N''Golo Kant\00E9', NULL),
  ('player', 'Harry Kane', NULL),
  ('player', U&'Martin \00D8degaard', NULL),
  ('player', 'Jean-Pierre Papin', NULL),
  ('player', 'Someone Else', 'not on the prompt');

INSERT INTO entity_aliases (entity_id, alias)
SELECT id, canonical_name FROM entities;

INSERT INTO entity_aliases (entity_id, alias)
SELECT id, U&'M\00FCller' FROM entities WHERE canonical_name = U&'Thomas M\00FCller'
UNION ALL
SELECT id, 'Muller' FROM entities WHERE canonical_name = 'Thomas Muller';

INSERT INTO prompts (prompt_text, answer_kind, difficulty, status) VALUES
  (U&'Name either M\00FCller', 'player', 1, 'reviewed');

INSERT INTO prompt_answers (prompt_id, entity_id, fame, tier_number)
SELECT p.id, e.id, 3, 1
FROM prompts p
JOIN entities e ON e.canonical_name IN (U&'Thomas M\00FCller', 'Thomas Muller')
WHERE p.prompt_text = U&'Name either M\00FCller';

INSERT INTO prompt_answers (prompt_id, entity_id, fame, tier_number)
SELECT p.id, e.id, 4, 2
FROM prompts p
JOIN entities e ON e.canonical_name = 'Harry Kane'
WHERE p.prompt_text = U&'Name either M\00FCller';

DO $$
DECLARE
  prompt_id bigint;
  match_count integer;
  match_kind text;
  points integer;
BEGIN
  IF normalize_answer(U&'M\00FCller') IS DISTINCT FROM normalize_answer('muller') THEN
    RAISE EXCEPTION 'accent fold failed: %', normalize_answer(U&'M\00FCller');
  END IF;

  IF normalize_answer(U&'\00D8degaard') IS DISTINCT FROM normalize_answer('odegaard') THEN
    RAISE EXCEPTION 'odegaard fold failed: %', normalize_answer(U&'\00D8degaard');
  END IF;

  IF normalize_answer('N''Golo') IS DISTINCT FROM 'ngolo' THEN
    RAISE EXCEPTION 'apostrophe fold failed: %', normalize_answer('N''Golo');
  END IF;

  IF normalize_answer('Jean-Pierre') IS DISTINCT FROM 'jean pierre' THEN
    RAISE EXCEPTION 'hyphen fold failed: %', normalize_answer('Jean-Pierre');
  END IF;

  IF normalize_answer('J. J. Okocha') IS DISTINCT FROM 'j j okocha' THEN
    RAISE EXCEPTION 'period fold failed: %', normalize_answer('J. J. Okocha');
  END IF;

  IF normalize_answer('  Harry   Kane ') IS DISTINCT FROM 'harry kane' THEN
    RAISE EXCEPTION 'whitespace fold failed: %', normalize_answer('  Harry   Kane ');
  END IF;

  IF normalize_answer('') IS DISTINCT FROM '' OR normalize_answer(NULL) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'empty input should normalize to empty';
  END IF;

  IF length(normalize_answer(repeat('A', 5000))) <> 5000 THEN
    RAISE EXCEPTION 'long input was not preserved';
  END IF;

  SELECT id INTO prompt_id FROM prompts WHERE prompt_text = U&'Name either M\00FCller';

  SELECT count(*), min(m.match_kind)
  INTO match_count, match_kind
  FROM match_prompt_answer(prompt_id, U&'M\00FCller') AS m;

  IF match_count <> 2 OR match_kind IS DISTINCT FROM 'exact' THEN
    RAISE EXCEPTION 'two Mullers should both be exact matches, got % %', match_count, match_kind;
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(prompt_id, 'Kane') AS m
  WHERE m.match_kind = 'word' AND m.canonical_name = 'Harry Kane';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'surname Kane should word-match Harry Kane';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(prompt_id, 'muler') AS m
  WHERE m.match_kind = 'typo';

  IF match_count <> 2 THEN
    RAISE EXCEPTION 'muler should typo-match both Mullers, got %', match_count;
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(prompt_id, 'Someone Else');

  IF match_count <> 0 THEN
    RAISE EXCEPTION 'a player who is not an answer was returned';
  END IF;

  SELECT count(*) INTO match_count FROM match_prompt_answer(prompt_id, '');
  IF match_count <> 0 THEN
    RAISE EXCEPTION 'empty input returned a match';
  END IF;

  SELECT score_prompt_answer(prompt_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = 'Harry Kane';

  IF points IS DISTINCT FROM 20 THEN
    RAISE EXCEPTION 'Harry Kane should score the Championship placeholder, got %', points;
  END IF;

  SELECT score_prompt_answer(prompt_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = 'Someone Else';

  IF points IS NOT NULL THEN
    RAISE EXCEPTION 'a non-answer should not score';
  END IF;
END;
$$;

ROLLBACK;
