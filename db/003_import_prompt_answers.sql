-- CSV import for one prompt's answer list. Issue #55.
-- Apply after db/001_schema.sql. Entities must already be loaded.
-- This does not add a curated table, and it does not create entities.
-- Tier numbers are not in this file. Fame is the rating it stores.
--
-- One file is one prompt. Repeat the prompt columns on every row.
-- The entity is matched by Wikidata Qid when that cell is filled,
-- and the name and disambiguation must be that entity. Without a
-- Qid, the match is answer kind, canonical name, and disambiguation.
-- An alias is not a key. A second load of an entity already on the
-- prompt fails. This does not update fame or the prompt.
--
-- answer_kind: player or club. It must be the entity's kind.
-- difficulty: 1 to 5.
-- status: draft, reviewed, or retired. Blank means draft.
-- fame: 1 to 5. Blank fails.
-- wikidata_qid: blank, or Q and digits.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/003_import_prompt_answers.sql
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -v csvpath=/tmp/prompt-answers.csv -f tools/import/load-prompt-answers.sql
--
-- The loader reads the CSV from the database server. In Docker, copy
-- the file into the container first. The sample is
-- tools/import/prompt-answers.sample.csv, and its players are the
-- ones in tools/import/entities.sample.csv.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/003_import_prompt_answers_test.sql

CREATE OR REPLACE FUNCTION begin_prompt_answer_import()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS prompt_answer_import (
    prompt_text text,
    answer_kind text,
    difficulty text,
    status text,
    source_notes text,
    canonical_name text,
    disambiguation text,
    wikidata_qid text,
    fame text
  );
  TRUNCATE prompt_answer_import;
END;
$$;

COMMENT ON FUNCTION begin_prompt_answer_import() IS
  'Creates or empties the session staging table for one prompt answer CSV.';

CREATE OR REPLACE FUNCTION import_prompt_answers()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  answer_count integer;
  prompt_count integer;
  target_prompt_id bigint;
  file_prompt_text text;
  file_answer_kind text;
  file_difficulty smallint;
  file_status text;
  file_source_notes text;
  problem text;
BEGIN
  IF to_regclass('pg_temp.prompt_answer_import') IS NULL THEN
    RAISE EXCEPTION 'import staging table is missing';
  END IF;

  IF to_regclass('pg_temp.prompt_answer_rows') IS NOT NULL THEN
    DROP TABLE prompt_answer_rows;
  END IF;

  CREATE TEMP TABLE prompt_answer_rows AS
  SELECT
    nullif(trim(prompt_text), '') AS prompt_text,
    lower(trim(answer_kind)) AS answer_kind,
    CASE
      WHEN nullif(trim(difficulty), '') ~ '^[1-5]$' THEN trim(difficulty)::smallint
    END AS difficulty,
    nullif(trim(difficulty), '') AS difficulty_raw,
    coalesce(nullif(lower(trim(status)), ''), 'draft') AS status,
    nullif(trim(source_notes), '') AS source_notes,
    nullif(trim(canonical_name), '') AS canonical_name,
    nullif(trim(disambiguation), '') AS disambiguation,
    nullif(upper(trim(wikidata_qid)), '') AS wikidata_qid,
    CASE
      WHEN nullif(trim(fame), '') ~ '^[1-5]$' THEN trim(fame)::smallint
    END AS fame,
    nullif(trim(fame), '') AS fame_raw,
    NULL::bigint AS entity_id
  FROM prompt_answer_import;

  IF NOT EXISTS (SELECT 1 FROM prompt_answer_rows) THEN
    RAISE EXCEPTION 'empty import';
  END IF;

  IF EXISTS (SELECT 1 FROM prompt_answer_rows WHERE prompt_text IS NULL) THEN
    RAISE EXCEPTION 'missing prompt text';
  END IF;

  SELECT coalesce(answer_kind, '(blank)') INTO problem
  FROM prompt_answer_rows
  WHERE answer_kind IS NULL OR answer_kind NOT IN ('player', 'club')
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'invalid answer kind: %', problem;
  END IF;

  SELECT canonical_name INTO problem
  FROM prompt_answer_rows
  WHERE difficulty IS NULL AND difficulty_raw IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'missing difficulty';
  END IF;

  SELECT difficulty_raw INTO problem
  FROM prompt_answer_rows
  WHERE difficulty IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'difficulty must be 1 to 5, got %', problem;
  END IF;

  SELECT status INTO problem
  FROM prompt_answer_rows
  WHERE status NOT IN ('draft', 'reviewed', 'retired')
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'invalid status: %', problem;
  END IF;

  IF (
    SELECT count(DISTINCT prompt_text)
         + count(DISTINCT answer_kind)
         + count(DISTINCT difficulty)
         + count(DISTINCT status)
         + count(DISTINCT coalesce(source_notes, ''))
    FROM prompt_answer_rows
  ) > 5 THEN
    RAISE EXCEPTION 'one prompt per file';
  END IF;

  IF EXISTS (SELECT 1 FROM prompt_answer_rows WHERE canonical_name IS NULL) THEN
    RAISE EXCEPTION 'missing canonical name';
  END IF;

  SELECT wikidata_qid INTO problem
  FROM prompt_answer_rows
  WHERE wikidata_qid IS NOT NULL AND wikidata_qid !~ '^Q[0-9]+$'
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'invalid wikidata qid: %', problem;
  END IF;

  SELECT canonical_name INTO problem
  FROM prompt_answer_rows
  WHERE fame IS NULL AND fame_raw IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'missing fame for %', problem;
  END IF;

  SELECT fame_raw INTO problem
  FROM prompt_answer_rows
  WHERE fame IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'fame must be 1 to 5, got %', problem;
  END IF;

  UPDATE prompt_answer_rows AS r
  SET entity_id = e.id
  FROM entities AS e
  WHERE r.wikidata_qid IS NOT NULL
    AND e.wikidata_qid = r.wikidata_qid;

  SELECT r.wikidata_qid INTO problem
  FROM prompt_answer_rows AS r
  WHERE r.wikidata_qid IS NOT NULL
    AND r.entity_id IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'unknown entity: %', problem;
  END IF;

  SELECT r.canonical_name INTO problem
  FROM prompt_answer_rows AS r
  JOIN entities AS e ON e.id = r.entity_id
  WHERE e.kind <> r.answer_kind
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'entity kind does not match the prompt: %', problem;
  END IF;

  SELECT r.wikidata_qid INTO problem
  FROM prompt_answer_rows AS r
  JOIN entities AS e ON e.id = r.entity_id
  WHERE r.wikidata_qid IS NOT NULL
    AND (
      e.canonical_name IS DISTINCT FROM r.canonical_name
      OR e.disambiguation IS DISTINCT FROM r.disambiguation
    )
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'entity does not match wikidata qid: %', problem;
  END IF;

  SELECT r.canonical_name INTO problem
  FROM prompt_answer_rows AS r
  WHERE r.wikidata_qid IS NULL
    AND (
      SELECT count(*)
      FROM entities AS e
      WHERE e.kind = r.answer_kind
        AND e.canonical_name = r.canonical_name
        AND e.disambiguation IS NOT DISTINCT FROM r.disambiguation
    ) > 1
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'more than one entity matches: %', problem;
  END IF;

  UPDATE prompt_answer_rows AS r
  SET entity_id = e.id
  FROM entities AS e
  WHERE r.wikidata_qid IS NULL
    AND e.kind = r.answer_kind
    AND e.canonical_name = r.canonical_name
    AND e.disambiguation IS NOT DISTINCT FROM r.disambiguation;

  SELECT canonical_name INTO problem
  FROM prompt_answer_rows
  WHERE entity_id IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'unknown entity: %', problem;
  END IF;

  SELECT canonical_name INTO problem
  FROM prompt_answer_rows
  GROUP BY entity_id, canonical_name
  HAVING count(*) > 1
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'duplicate answer: %', problem;
  END IF;

  SELECT prompt_text, answer_kind, difficulty, status, source_notes
  INTO file_prompt_text, file_answer_kind, file_difficulty, file_status, file_source_notes
  FROM prompt_answer_rows
  LIMIT 1;

  SELECT count(*) INTO prompt_count
  FROM prompts
  WHERE prompt_text = file_prompt_text;

  IF prompt_count > 1 THEN
    RAISE EXCEPTION 'more than one prompt has this text';
  END IF;

  IF prompt_count = 1 THEN
    SELECT id INTO target_prompt_id
    FROM prompts
    WHERE prompt_text = file_prompt_text;

    IF EXISTS (
      SELECT 1
      FROM prompts
      WHERE id = target_prompt_id
        AND (
          answer_kind IS DISTINCT FROM file_answer_kind
          OR difficulty IS DISTINCT FROM file_difficulty
          OR status IS DISTINCT FROM file_status
          OR source_notes IS DISTINCT FROM file_source_notes
        )
    ) THEN
      RAISE EXCEPTION 'prompt already exists with different values';
    END IF;

    SELECT r.canonical_name INTO problem
    FROM prompt_answer_rows AS r
    JOIN prompt_answers AS pa
      ON pa.prompt_id = target_prompt_id
     AND pa.entity_id = r.entity_id
    LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'duplicate answer: %', problem;
    END IF;
  ELSE
    INSERT INTO prompts (prompt_text, answer_kind, difficulty, status, source_notes)
    VALUES (
      file_prompt_text,
      file_answer_kind,
      file_difficulty,
      file_status,
      file_source_notes
    )
    RETURNING id INTO target_prompt_id;
  END IF;

  INSERT INTO prompt_answers (prompt_id, entity_id, fame)
  SELECT target_prompt_id, entity_id, fame
  FROM prompt_answer_rows;

  GET DIAGNOSTICS answer_count = ROW_COUNT;

  DROP TABLE prompt_answer_rows;
  RETURN answer_count;
END;
$$;

COMMENT ON FUNCTION import_prompt_answers() IS
  'Loads prompt_answer_import as one prompt and its fame ratings. Raises on an unknown entity, a missing fame rating, or an empty file.';
