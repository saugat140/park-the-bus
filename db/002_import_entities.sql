-- CSV import for entities and aliases. Issue #16.
-- Apply after db/001_schema.sql. This does not add a curated table.
-- Players and clubs share entity_aliases. There is no country, spell,
-- or honour import. Prompt answer lists are issue #55.
--
-- One row per alias. Repeat the entity columns on each of its rows.
-- The canonical name is stored as an alias when the file does not
-- already list it. A second load of the same entity fails. This does
-- not update or delete.
--
-- kind: player or club.
-- wikidata_qid: blank, or Q and digits. q43666 is stored as Q43666.
-- accept_shared: yes or no. Blank means no.
--
-- The same normalized alias may already belong to two entities.
-- The import allows that only when every entity that would carry it
-- has a row for that alias marked yes. Yes on a different alias does
-- not cover the name. A collision with an alias already in the
-- database is allowed only when the incoming rows for that alias
-- are marked yes.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/002_import_entities.sql
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -v csvpath=/tmp/entities.csv -f tools/import/load-entities.sql
--
-- tools/import/load-entities.sql reads the CSV from the database
-- server. In Docker, copy the file into the container first. The
-- sample is tools/import/entities.sample.csv.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/002_import_entities_test.sql

CREATE OR REPLACE FUNCTION begin_entity_alias_import()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS entity_alias_import (
    kind text,
    canonical_name text,
    disambiguation text,
    wikidata_qid text,
    alias text,
    accept_shared text
  );
  TRUNCATE entity_alias_import;
END;
$$;

COMMENT ON FUNCTION begin_entity_alias_import() IS
  'Creates or empties the session staging table for one entity CSV load.';

CREATE OR REPLACE FUNCTION import_entity_aliases()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  entity_count integer;
  problem text;
BEGIN
  IF to_regclass('pg_temp.entity_alias_import') IS NULL THEN
    RAISE EXCEPTION 'import staging table is missing';
  END IF;

  IF to_regclass('pg_temp.entity_import_rows') IS NOT NULL THEN
    DROP TABLE entity_import_rows;
  END IF;
  CREATE TEMP TABLE entity_import_rows AS
  SELECT
    lower(trim(kind)) AS kind,
    nullif(trim(canonical_name), '') AS canonical_name,
    nullif(trim(disambiguation), '') AS disambiguation,
    nullif(upper(trim(wikidata_qid)), '') AS wikidata_qid,
    nullif(trim(alias), '') AS alias,
    coalesce(nullif(lower(trim(accept_shared)), ''), 'no') AS accept_shared,
    normalize_answer(nullif(trim(alias), '')) AS alias_normalized
  FROM entity_alias_import;

  IF NOT EXISTS (SELECT 1 FROM entity_import_rows) THEN
    RAISE EXCEPTION 'empty import';
  END IF;

  SELECT coalesce(kind, '(blank)') INTO problem
  FROM entity_import_rows
  WHERE kind IS NULL OR kind NOT IN ('player', 'club')
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'invalid kind: %', problem;
  END IF;

  IF EXISTS (SELECT 1 FROM entity_import_rows WHERE canonical_name IS NULL) THEN
    RAISE EXCEPTION 'missing canonical name';
  END IF;

  SELECT canonical_name INTO problem
  FROM entity_import_rows
  WHERE alias IS NULL
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'missing alias for %', problem;
  END IF;

  SELECT alias INTO problem
  FROM entity_import_rows
  WHERE alias_normalized = ''
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'alias normalizes to empty: %', problem;
  END IF;

  SELECT canonical_name INTO problem
  FROM entity_import_rows
  WHERE normalize_answer(canonical_name) = ''
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'canonical name normalizes to empty: %', problem;
  END IF;

  SELECT accept_shared INTO problem
  FROM entity_import_rows
  WHERE accept_shared IS NOT NULL AND accept_shared NOT IN ('yes', 'no')
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'accept_shared must be yes or no, got %', problem;
  END IF;

  SELECT wikidata_qid INTO problem
  FROM entity_import_rows
  WHERE wikidata_qid IS NOT NULL AND wikidata_qid !~ '^Q[0-9]+$'
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'invalid wikidata qid: %', problem;
  END IF;

  SELECT wikidata_qid INTO problem
  FROM entity_import_rows
  WHERE wikidata_qid IS NOT NULL
  GROUP BY wikidata_qid
  HAVING count(DISTINCT (kind, canonical_name, coalesce(disambiguation, ''))) > 1
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'duplicate entity: qid % is used for more than one player or club', problem;
  END IF;

  SELECT canonical_name INTO problem
  FROM entity_import_rows
  GROUP BY kind, canonical_name, disambiguation
  HAVING count(DISTINCT wikidata_qid) > 1
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'duplicate entity: % has more than one wikidata qid', problem;
  END IF;

  SELECT canonical_name || ': ' || alias_normalized INTO problem
  FROM entity_import_rows
  GROUP BY kind, canonical_name, disambiguation, alias_normalized
  HAVING count(*) > 1
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'duplicate alias: %', problem;
  END IF;

  SELECT i.canonical_name INTO problem
  FROM (
    SELECT kind, canonical_name, disambiguation, max(wikidata_qid) AS wikidata_qid
    FROM entity_import_rows
    GROUP BY kind, canonical_name, disambiguation
  ) AS i
  JOIN entities AS e
    ON (
      e.wikidata_qid IS NOT NULL
      AND e.wikidata_qid = i.wikidata_qid
    )
    OR (
      e.kind = i.kind
      AND e.canonical_name = i.canonical_name
      AND e.disambiguation IS NOT DISTINCT FROM i.disambiguation
    )
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'duplicate entity: % already exists', problem;
  END IF;

  IF to_regclass('pg_temp.entity_import_aliases') IS NOT NULL THEN
    DROP TABLE entity_import_aliases;
  END IF;
  CREATE TEMP TABLE entity_import_aliases AS
  SELECT
    kind,
    canonical_name,
    disambiguation,
    alias_normalized,
    min(alias) AS alias,
    bool_or(accept_shared = 'yes') AS accepted
  FROM entity_import_rows
  GROUP BY kind, canonical_name, disambiguation, alias_normalized;

  INSERT INTO entity_import_aliases (
    kind, canonical_name, disambiguation, alias_normalized, alias, accepted
  )
  SELECT DISTINCT
    r.kind,
    r.canonical_name,
    r.disambiguation,
    normalize_answer(r.canonical_name),
    r.canonical_name,
    false
  FROM entity_import_rows AS r
  WHERE NOT EXISTS (
    SELECT 1
    FROM entity_import_aliases AS a
    WHERE a.kind = r.kind
      AND a.canonical_name = r.canonical_name
      AND a.disambiguation IS NOT DISTINCT FROM r.disambiguation
      AND a.alias_normalized = normalize_answer(r.canonical_name)
  );

  SELECT a.alias_normalized INTO problem
  FROM entity_import_aliases AS a
  WHERE NOT a.accepted
    AND (
      EXISTS (
        SELECT 1
        FROM entity_import_aliases AS other
        WHERE other.alias_normalized = a.alias_normalized
          AND (
            other.kind,
            other.canonical_name,
            other.disambiguation
          ) IS DISTINCT FROM (
            a.kind,
            a.canonical_name,
            a.disambiguation
          )
      )
      OR EXISTS (
        SELECT 1
        FROM entity_aliases AS existing
        WHERE existing.alias_normalized = a.alias_normalized
      )
    )
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'shared alias not accepted: %', problem;
  END IF;

  INSERT INTO entities (kind, canonical_name, disambiguation, wikidata_qid)
  SELECT kind, canonical_name, disambiguation, max(wikidata_qid)
  FROM entity_import_rows
  GROUP BY kind, canonical_name, disambiguation;

  GET DIAGNOSTICS entity_count = ROW_COUNT;

  INSERT INTO entity_aliases (entity_id, alias)
  SELECT e.id, a.alias
  FROM entity_import_aliases AS a
  JOIN entities AS e
    ON e.kind = a.kind
   AND e.canonical_name = a.canonical_name
   AND e.disambiguation IS NOT DISTINCT FROM a.disambiguation;

  DROP TABLE entity_import_rows;
  DROP TABLE entity_import_aliases;
  RETURN entity_count;
END;
$$;

COMMENT ON FUNCTION import_entity_aliases() IS
  'Loads entity_alias_import into entities and entity_aliases. Raises on a duplicate entity or a shared alias that was not marked yes.';
