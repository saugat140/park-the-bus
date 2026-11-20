-- Smoke test for db/001_schema.sql. Issues #10, #54, and #56.
-- Rolls back. Safe to run against a database that already has the schema.
-- This is not the xUnit suite in issue #26.
--
-- #54 adds the cases the first pass left out: curly apostrophes, a
-- hyphen and a period inside a match, a swapped pair and a missing
-- letter, a shared alias, and a real player who is not on the prompt.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/001_schema_test.sql
-- Accented letters are written as U& escapes so a Windows pipe
-- cannot drop them before they reach the database.

BEGIN;

-- Issue #56. Tier 1 is the common end. Each higher tier is worth more.
DO $$
BEGIN
  IF (SELECT count(*) FROM rarity_tiers) <> 6 THEN
    RAISE EXCEPTION 'expected the six game tiers';
  END IF;

  IF EXISTS (
    SELECT tier_number, display_name, points, min_rarity, max_rarity
    FROM rarity_tiers
    EXCEPT
    SELECT *
    FROM (VALUES
      (1::smallint, 'Sunday League'::text, 10, NULL::numeric, NULL::numeric),
      (2::smallint, 'Championship', 20, NULL, NULL),
      (3::smallint, 'FA Cup', 40, NULL, NULL),
      (4::smallint, 'Premier League', 60, NULL, NULL),
      (5::smallint, 'Champions League', 80, NULL, NULL),
      (6::smallint, 'World Cup', 100, NULL, NULL)
    ) AS scale(tier_number, display_name, points, min_rarity, max_rarity)
  ) THEN
    RAISE EXCEPTION 'rarity tiers are not the game scale';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM rarity_tiers AS low
    JOIN rarity_tiers AS high ON high.tier_number = low.tier_number + 1
    WHERE high.points <= low.points
  ) THEN
    RAISE EXCEPTION 'a higher tier should be worth more points';
  END IF;
END;
$$;

INSERT INTO entities (kind, canonical_name, disambiguation) VALUES
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989'),
  ('player', 'Thomas Muller', 'a different Muller'),
  ('player', U&'N''Golo Kant\00E9', NULL),
  ('player', 'Harry Kane', NULL),
  ('player', U&'Martin \00D8degaard', NULL),
  ('player', 'Jean-Pierre Papin', NULL),
  ('player', 'Someone Else', 'not on the prompt'),
  ('player', 'Cristiano Ronaldo', 'Portugal'),
  ('player', 'Ronaldo', 'Brazil, born 1976'),
  ('player', 'J. J. Okocha', 'Nigeria');

INSERT INTO entity_aliases (entity_id, alias)
SELECT id, canonical_name FROM entities;

INSERT INTO entity_aliases (entity_id, alias)
SELECT id, U&'M\00FCller' FROM entities WHERE canonical_name = U&'Thomas M\00FCller'
UNION ALL
SELECT id, 'Muller' FROM entities WHERE canonical_name = 'Thomas Muller'
UNION ALL
SELECT id, 'Ronaldo' FROM entities WHERE canonical_name = 'Cristiano Ronaldo';

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

INSERT INTO prompts (prompt_text, answer_kind, difficulty, status) VALUES
  ('Name a squad player', 'player', 1, 'reviewed');

INSERT INTO prompt_answers (prompt_id, entity_id, fame, tier_number)
SELECT p.id, e.id, v.fame, v.tier_number
FROM prompts p
CROSS JOIN (
  VALUES
    (U&'N''Golo Kant\00E9', 4::smallint, 2::smallint),
    (U&'Martin \00D8degaard', 4::smallint, 2::smallint),
    ('Jean-Pierre Papin', 3::smallint, NULL::smallint),
    ('Cristiano Ronaldo', 5::smallint, 5::smallint),
    ('Ronaldo', 5::smallint, 5::smallint),
    ('J. J. Okocha', 3::smallint, 3::smallint)
) AS v(canonical_name, fame, tier_number)
JOIN entities e ON e.canonical_name = v.canonical_name
WHERE p.prompt_text = 'Name a squad player';

DO $$
DECLARE
  prompt_id bigint;
  squad_id bigint;
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

  IF normalize_answer('N''Golo') IS DISTINCT FROM 'ngolo'
     OR normalize_answer(U&'N\2019Golo') IS DISTINCT FROM 'ngolo'
     OR normalize_answer(U&'N\2018Golo') IS DISTINCT FROM 'ngolo'
     OR normalize_answer(U&'N\02BCGolo') IS DISTINCT FROM 'ngolo' THEN
    RAISE EXCEPTION 'apostrophe fold failed: %', normalize_answer(U&'N\2019Golo');
  END IF;

  IF normalize_answer('Jean-Pierre') IS DISTINCT FROM 'jean pierre' THEN
    RAISE EXCEPTION 'hyphen fold failed: %', normalize_answer('Jean-Pierre');
  END IF;

  IF normalize_answer('J. J. Okocha') IS DISTINCT FROM 'j j okocha'
     OR normalize_answer('J.J. Okocha') IS DISTINCT FROM 'j j okocha'
     OR normalize_answer('JJ Okocha') IS DISTINCT FROM 'jj okocha' THEN
    RAISE EXCEPTION 'period fold failed: %', normalize_answer('J.J. Okocha');
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
    RAISE EXCEPTION 'Harry Kane should score Championship, got %', points;
  END IF;

  SELECT score_prompt_answer(prompt_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = 'Someone Else';

  IF points IS NOT NULL THEN
    RAISE EXCEPTION 'a non-answer should not score';
  END IF;

  SELECT score_prompt_answer(prompt_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = U&'Thomas M\00FCller';

  IF points IS DISTINCT FROM 10 THEN
    RAISE EXCEPTION 'Thomas Muller should score Sunday League, got %', points;
  END IF;

  SELECT id INTO squad_id FROM prompts WHERE prompt_text = 'Name a squad player';

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(prompt_id, U&'Martin \00D8degaard');

  IF match_count <> 0 THEN
    RAISE EXCEPTION 'Odegaard is a real player and is not an answer on this prompt';
  END IF;

  SELECT score_prompt_answer(prompt_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = U&'Martin \00D8degaard';

  IF points IS NOT NULL THEN
    RAISE EXCEPTION 'Odegaard should not score on a prompt he is not on';
  END IF;

  SELECT count(*), min(m.match_kind) INTO match_count, match_kind
  FROM match_prompt_answer(squad_id, U&'N\2019Golo Kant\00E9') AS m
  WHERE m.canonical_name = U&'N''Golo Kant\00E9';

  IF match_count <> 1 OR match_kind IS DISTINCT FROM 'exact' THEN
    RAISE EXCEPTION 'a curly apostrophe and an accent should exact-match Kante, got % %', match_count, match_kind;
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(squad_id, 'Jean-Pierre Papin') AS m
  WHERE m.match_kind = 'exact' AND m.canonical_name = 'Jean-Pierre Papin';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'a hyphenated name should exact-match once the hyphen is a space';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(squad_id, 'Papin') AS m
  WHERE m.match_kind = 'word' AND m.canonical_name = 'Jean-Pierre Papin';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'Papin should word-match Jean-Pierre Papin';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(squad_id, 'J.J. Okocha') AS m
  WHERE m.match_kind = 'exact' AND m.canonical_name = 'J. J. Okocha';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'initials with periods should exact-match J. J. Okocha';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(squad_id, 'JJ Okocha') AS m
  WHERE m.match_kind = 'typo' AND m.canonical_name = 'J. J. Okocha';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'JJ Okocha should typo-match, not exact-match';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(prompt_id, 'Harry Kena') AS m
  WHERE m.match_kind = 'typo' AND m.canonical_name = 'Harry Kane';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'Harry Kena should typo-match the swapped pair in Harry Kane, got %', match_count;
  END IF;

  SELECT count(*) INTO match_count FROM match_prompt_answer(prompt_id, 'Kaen');
  IF match_count <> 0 THEN
    RAISE EXCEPTION 'Kaen is a swapped surname and is too short to count as a typo';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(squad_id, 'Odegard') AS m
  WHERE m.match_kind = 'typo' AND m.canonical_name = U&'Martin \00D8degaard';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'Odegard should typo-match the missing letter in Odegaard, got %', match_count;
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(prompt_id, 'Harr') AS m
  WHERE m.match_kind = 'prefix' AND m.canonical_name = 'Harry Kane';

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'Harr should prefix-match only Harry Kane, got %', match_count;
  END IF;

  SELECT count(*) INTO match_count FROM match_prompt_answer(prompt_id, 'Ka');
  IF match_count <> 0 THEN
    RAISE EXCEPTION 'a two-letter prefix should not match';
  END IF;

  SELECT count(*) INTO match_count FROM match_prompt_answer(prompt_id, '   ');
  IF match_count <> 0 THEN
    RAISE EXCEPTION 'whitespace-only input returned a match';
  END IF;

  SELECT count(*) INTO match_count
  FROM match_prompt_answer(squad_id, 'Ronaldo') AS m
  WHERE m.match_kind = 'exact'
    AND m.disambiguation IN ('Portugal', 'Brazil, born 1976');

  IF match_count <> 2 THEN
    RAISE EXCEPTION 'Ronaldo is a shared alias and should exact-match both players, got %', match_count;
  END IF;

  SELECT score_prompt_answer(squad_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = 'Ronaldo';

  IF points IS DISTINCT FROM 80 THEN
    RAISE EXCEPTION 'Ronaldo should score Champions League, got %', points;
  END IF;

  SELECT score_prompt_answer(squad_id, e.id) INTO points
  FROM entities e
  WHERE e.canonical_name = 'Jean-Pierre Papin';

  IF points IS NOT NULL THEN
    RAISE EXCEPTION 'an answer with no tier should not score';
  END IF;
END;
$$;

ROLLBACK;
