-- Tests for db/003_import_prompt_answers.sql. Issue #55.
-- Rolls back. Apply 001 and 003 first. This is not the xUnit suite in issue #26.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/003_import_prompt_answers_test.sql

BEGIN;

INSERT INTO entities (kind, canonical_name, disambiguation, wikidata_qid) VALUES
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666'),
  ('player', 'Cristiano Ronaldo', 'Portugal', 'Q11571'),
  ('player', 'Ronaldo', 'Brazil, born 1976', 'Q529207'),
  ('player', 'Harry Kane', NULL, NULL),
  ('club', 'Arsenal', NULL, 'Q9617'),
  ('player', 'Alex', NULL, 'Q100'),
  ('player', 'Alex', NULL, 'Q101');

SELECT begin_prompt_answer_import();

CREATE FUNCTION pg_temp.expect_import_error(expected text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM import_prompt_answers();
  RAISE EXCEPTION 'import should have failed matching %', expected;
EXCEPTION
  WHEN raise_exception THEN
    IF SQLERRM LIKE 'import should have failed%' THEN
      RAISE;
    ELSIF SQLERRM NOT LIKE expected THEN
      RAISE EXCEPTION 'expected % but got %', expected, SQLERRM;
    END IF;
END;
$$;

SELECT pg_temp.expect_import_error('empty import');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('  ', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('missing prompt text');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'team', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('invalid answer kind:%');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '   ', 'draft', NULL, 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('missing difficulty');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '9', 'draft', NULL, 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('difficulty must be 1 to 5, got 9');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'live', NULL, 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('invalid status: live');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, '4'),
  ('Name a club', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('one prompt per file');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, '   ', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('missing canonical name');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, '43666', '4');
SELECT pg_temp.expect_import_error('invalid wikidata qid: 43666');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, U&'Thomas M\00FCller', 'Germany, born 1989', NULL, '  ');
SELECT pg_temp.expect_import_error('missing fame for Thomas M%ller');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, '0');
SELECT pg_temp.expect_import_error('fame must be 1 to 5, got 0');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, '6');
SELECT pg_temp.expect_import_error('fame must be 1 to 5, got 6');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Harry Kane', NULL, NULL, 'x');
SELECT pg_temp.expect_import_error('fame must be 1 to 5, got x');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Nobody', NULL, NULL, '3');
SELECT pg_temp.expect_import_error('unknown entity: Nobody');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, U&'Thomas M\00FCller', NULL, NULL, '3');
SELECT pg_temp.expect_import_error('unknown entity: Thomas M%ller');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Nobody', NULL, 'Q999999', '3');
SELECT pg_temp.expect_import_error('unknown entity: Q999999');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Arsenal', NULL, 'Q9617', '2');
SELECT pg_temp.expect_import_error('entity kind does not match the prompt: Arsenal');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Someone', 'Germany, born 1989', 'Q43666', '3');
SELECT pg_temp.expect_import_error('entity does not match wikidata qid: Q43666');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', '3'),
  ('Name a forward', 'player', '2', 'draft', NULL, U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', '4');
SELECT pg_temp.expect_import_error('duplicate answer: Thomas M%ller');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'draft', NULL, 'Alex', NULL, NULL, '1');
SELECT pg_temp.expect_import_error('more than one entity matches: Alex');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'Player', '2', 'reviewed', 'Sample list', U&'Thomas M\00FCller', 'Germany, born 1989', 'q43666', '3'),
  ('Name a forward', 'player', '2', 'reviewed', 'Sample list', 'Cristiano Ronaldo', 'Portugal', 'Q11571', '5'),
  ('Name a forward', 'player', '2', 'reviewed', 'Sample list', 'Ronaldo', 'Brazil, born 1976', NULL, '4');

DO $$
BEGIN
  IF import_prompt_answers() <> 3 THEN
    RAISE EXCEPTION 'expected 3 answers';
  END IF;
END;
$$;

DO $$
DECLARE
  answer_count integer;
  muller_fame smallint;
BEGIN
  SELECT count(*) INTO answer_count FROM prompt_answers;
  IF answer_count <> 3 THEN
    RAISE EXCEPTION 'expected 3 stored answers, got %', answer_count;
  END IF;

  IF (
    SELECT count(*)
    FROM prompts
    WHERE prompt_text = 'Name a forward'
      AND answer_kind = 'player'
      AND difficulty = 2
      AND status = 'reviewed'
      AND source_notes = 'Sample list'
  ) <> 1 THEN
    RAISE EXCEPTION 'the prompt was not stored from the file';
  END IF;

  SELECT pa.fame INTO muller_fame
  FROM prompt_answers AS pa
  JOIN entities AS e ON e.id = pa.entity_id
  WHERE e.wikidata_qid = 'Q43666';
  IF muller_fame IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'Muller fame should be 3, got %', muller_fame;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM prompt_answers
    WHERE fame NOT IN (3, 4, 5)
       OR tier_number IS NOT NULL
       OR observed_count <> 0
  ) THEN
    RAISE EXCEPTION 'fame should be stored and tier should stay empty';
  END IF;

  IF (
    SELECT pa.fame
    FROM prompt_answers AS pa
    JOIN entities AS e ON e.id = pa.entity_id
    WHERE e.canonical_name = 'Ronaldo'
  ) IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'Ronaldo should be found without a qid';
  END IF;
END;
$$;

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'reviewed', 'Sample list', U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', '3');
SELECT pg_temp.expect_import_error('duplicate answer: Thomas M%ller');

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '3', 'reviewed', 'Sample list', 'Harry Kane', NULL, NULL, '4');
SELECT pg_temp.expect_import_error('prompt already exists with different values');

DO $$
BEGIN
  IF (SELECT count(*) FROM prompt_answers) <> 3 THEN
    RAISE EXCEPTION 'a rejected load should not have added an answer';
  END IF;
END;
$$;

TRUNCATE prompt_answer_import;
INSERT INTO prompt_answer_import VALUES
  ('Name a forward', 'player', '2', 'reviewed', 'Sample list', 'Harry Kane', NULL, NULL, '4');

DO $$
BEGIN
  IF import_prompt_answers() <> 1 THEN
    RAISE EXCEPTION 'a new entity on the same prompt should be added';
  END IF;
  IF (
    SELECT pa.fame
    FROM prompt_answers AS pa
    JOIN entities AS e ON e.id = pa.entity_id
    WHERE e.canonical_name = 'Harry Kane'
  ) IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'Harry Kane should score fame 4';
  END IF;
END;
$$;

DO $$
BEGIN
  TRUNCATE prompt_answer_import;
  INSERT INTO prompt_answer_import VALUES
    ('Name a club', 'club', '1', 'draft', NULL, 'Arsenal', NULL, 'Q9617', '2');
  IF import_prompt_answers() <> 1 THEN
    RAISE EXCEPTION 'a club prompt should import into the same answer table';
  END IF;
  RAISE EXCEPTION 'rollback club probe';
EXCEPTION
  WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'rollback club probe' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM prompts WHERE prompt_text = 'Name a club') THEN
    RAISE EXCEPTION 'the club probe should have rolled back';
  END IF;
  IF (SELECT count(*) FROM prompt_answers) <> 4 THEN
    RAISE EXCEPTION 'the player answers should still be there';
  END IF;
END;
$$;

ROLLBACK;
