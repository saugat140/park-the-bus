-- Load one entity and alias CSV. Issue #16.
-- The functions come from db/002_import_entities.sql.
-- COPY reads the path on the database server, not on the client.
-- In Docker, copy the CSV into the container first.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -v csvpath=/tmp/entities.csv -f tools/import/load-entities.sql

BEGIN;
SELECT begin_entity_alias_import();
COPY entity_alias_import (
  kind, canonical_name, disambiguation, wikidata_qid, alias, accept_shared
) FROM :'csvpath' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
SELECT import_entity_aliases();
COMMIT;
