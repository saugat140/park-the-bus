-- Open answer reports for review. Issue #25.
-- Run against the game database:
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f tools/review/list-open-answer-reports.sql
--
-- wrong  = the player says a scored/rejected guess was judged incorrectly
-- missing = the player says a valid answer is absent from the curated list
-- Accept or reject by updating review_status; do not delete rows.

SELECT
  r.id,
  r.created_at,
  r.puzzle_date,
  r.prompt_id,
  p.prompt_text,
  r.report_kind,
  r.raw_input,
  r.notes,
  r.session_id
FROM answer_reports AS r
JOIN prompts AS p ON p.id = r.prompt_id
WHERE r.review_status = 'open'
ORDER BY r.created_at, r.id;
