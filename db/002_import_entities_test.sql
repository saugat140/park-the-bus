-- Tests for db/002_import_entities.sql. Issue #16.
-- Rolls back. Apply 001 and 002 first. This is not the xUnit suite in issue #26.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/002_import_entities_test.sql

BEGIN;

SELECT begin_entity_alias_import();

CREATE FUNCTION pg_temp.expect_import_error(expected text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM import_entity_aliases();
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

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES ('team', 'Arsenal', NULL, NULL, 'Arsenal', 'no');
SELECT pg_temp.expect_import_error('invalid kind:%');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES ('player', '   ', NULL, NULL, 'Arsenal', 'no');
SELECT pg_temp.expect_import_error('missing canonical name');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES ('player', 'Bukayo Saka', NULL, NULL, '   ', 'no');
SELECT pg_temp.expect_import_error('missing alias for Bukayo Saka');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES ('player', 'Bukayo Saka', NULL, NULL, '.', 'no');
SELECT pg_temp.expect_import_error('alias normalizes to empty:%');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES ('player', 'Bukayo Saka', NULL, '43666', 'Saka', 'maybe');
SELECT pg_temp.expect_import_error('accept_shared must be yes or no, got maybe');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES ('player', 'Bukayo Saka', NULL, '43666', 'Saka', 'no');
SELECT pg_temp.expect_import_error('invalid wikidata qid: 43666');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'One', NULL, 'Q1', 'One', 'no'),
  ('player', 'Two', NULL, 'Q1', 'Two', 'no');
SELECT pg_temp.expect_import_error('duplicate entity: qid Q1 is used for more than one player or club');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'Bukayo Saka', NULL, 'Q1', 'Saka', 'no'),
  ('player', 'Bukayo Saka', NULL, 'Q2', 'Bukayo Saka', 'no');
SELECT pg_temp.expect_import_error('duplicate entity: Bukayo Saka has more than one wikidata qid');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', U&'M\00FCller', 'no'),
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', 'Muller', 'no');
SELECT pg_temp.expect_import_error('duplicate alias: Thomas M%ller: muller');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'Alex One', 'England', NULL, 'United', 'no'),
  ('club', 'Alex Two', 'London', NULL, 'United', 'no');
SELECT pg_temp.expect_import_error('shared alias not accepted: united');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'Alex One', 'England', NULL, 'United', 'yes'),
  ('club', 'Alex Two', 'London', NULL, 'United', 'no');
SELECT pg_temp.expect_import_error('shared alias not accepted: united');

-- Yes on a nickname does not accept the canonical name when that name collides.
TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'Ronaldo', 'Brazil, born 1976', NULL, 'R9', 'yes'),
  ('player', 'Cristiano Ronaldo', 'Portugal', NULL, 'Ronaldo', 'yes');
SELECT pg_temp.expect_import_error('shared alias not accepted: ronaldo');

DO $$
BEGIN
  TRUNCATE entity_alias_import;
  INSERT INTO entity_alias_import VALUES
    ('player', 'Alex One', 'England', NULL, 'United', 'yes'),
    ('club', 'Alex Two', 'London', NULL, 'United', 'yes');
  IF import_entity_aliases() <> 2 THEN
    RAISE EXCEPTION 'an accepted shared alias should import both entities';
  END IF;
  IF (
    SELECT count(*)
    FROM entity_aliases
    WHERE alias_normalized = 'united'
  ) <> 2 THEN
    RAISE EXCEPTION 'the shared alias should be stored on both entities';
  END IF;
  RAISE EXCEPTION 'rollback accepted-share probe';
EXCEPTION
  WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'rollback accepted-share probe' THEN
      RAISE;
    END IF;
END;
$$;

DO $$
BEGIN
  IF (SELECT count(*) FROM entities) <> 0 THEN
    RAISE EXCEPTION 'failed imports should have left no entities';
  END IF;
END;
$$;

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('Player', U&'Thomas M\00FCller', 'Germany, born 1989', 'q43666', U&'Thomas M\00FCller', 'no'),
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', U&'M\00FCller', 'no'),
  ('player', 'Cristiano Ronaldo', 'Portugal', 'Q11571', 'Cristiano Ronaldo', 'no'),
  ('player', 'Cristiano Ronaldo', 'Portugal', 'Q11571', 'Ronaldo', 'yes'),
  ('player', 'Ronaldo', 'Brazil, born 1976', 'Q529207', 'Ronaldo', 'yes'),
  ('CLUB', 'Arsenal', NULL, 'Q9617', 'Arsenal FC', ''),
  ('player', 'Bukayo Saka', NULL, NULL, 'Saka', 'no');

DO $$
BEGIN
  IF import_entity_aliases() <> 5 THEN
    RAISE EXCEPTION 'expected 5 entities';
  END IF;
END;
$$;

DO $$
DECLARE
  alias_count integer;
  shared_count integer;
  qid text;
  club_aliases integer;
BEGIN
  SELECT count(*) INTO alias_count FROM entity_aliases;
  IF alias_count <> 9 THEN
    RAISE EXCEPTION 'expected 9 aliases, got %', alias_count;
  END IF;

  IF (SELECT count(*) FROM entities WHERE kind = 'club') <> 1
     OR (SELECT count(*) FROM entities WHERE kind = 'player') <> 4 THEN
    RAISE EXCEPTION 'kind should be stored as player or club';
  END IF;

  SELECT count(*) INTO shared_count
  FROM entity_aliases
  WHERE alias_normalized = 'ronaldo';
  IF shared_count <> 2 THEN
    RAISE EXCEPTION 'Ronaldo should be stored for both players, got %', shared_count;
  END IF;

  SELECT wikidata_qid INTO qid
  FROM entities
  WHERE canonical_name = U&'Thomas M\00FCller';
  IF qid IS DISTINCT FROM 'Q43666' THEN
    RAISE EXCEPTION 'qid should be stored in upper case, got %', qid;
  END IF;

  IF EXISTS (
    SELECT 1 FROM entities
    WHERE canonical_name = 'Bukayo Saka' AND wikidata_qid IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'a blank qid should stay null';
  END IF;

  SELECT count(*) INTO club_aliases
  FROM entity_aliases AS a
  JOIN entities AS e ON e.id = a.entity_id
  WHERE e.kind = 'club' AND e.canonical_name = 'Arsenal';
  IF club_aliases <> 2 THEN
    RAISE EXCEPTION 'Arsenal should keep its name and Arsenal FC, got %', club_aliases;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM entity_aliases AS a
    JOIN entities AS e ON e.id = a.entity_id
    WHERE e.canonical_name = 'Bukayo Saka'
      AND a.alias = 'Bukayo Saka'
  ) THEN
    RAISE EXCEPTION 'the canonical name should be stored when the CSV only lists a nickname';
  END IF;
END;
$$;

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', U&'Thomas M\00FCller', 'Germany, born 1989', 'Q43666', U&'M\00FCller', 'no');
SELECT pg_temp.expect_import_error('duplicate entity: Thomas M%ller already exists');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'Tommy Muller', 'a different Muller', NULL, 'Muller', 'no');
SELECT pg_temp.expect_import_error('shared alias not accepted: muller');

TRUNCATE entity_alias_import;
INSERT INTO entity_alias_import VALUES
  ('player', 'Tommy Muller', 'a different Muller', NULL, 'Muller', 'yes');

DO $$
BEGIN
  IF import_entity_aliases() <> 1 THEN
    RAISE EXCEPTION 'a shared alias marked yes should import beside the existing player';
  END IF;
  IF (
    SELECT count(*) FROM entity_aliases WHERE alias_normalized = 'muller'
  ) <> 2 THEN
    RAISE EXCEPTION 'the accepted collision should leave two muller aliases';
  END IF;
END;
$$;

ROLLBACK;
