-- Load one prompt answer CSV. Issue #55.
-- The functions come from db/003_import_prompt_answers.sql.
-- COPY reads the path on the database server, not on the client.
-- In Docker, copy the CSV into the container first.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -v csvpath=/tmp/prompt-answers.csv -f tools/import/load-prompt-answers.sql

BEGIN;
SELECT begin_prompt_answer_import();
COPY prompt_answer_import (
  prompt_text, answer_kind, difficulty, status, source_notes,
  canonical_name, disambiguation, wikidata_qid, fame
) FROM :'csvpath' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
SELECT import_prompt_answers();
COMMIT;
