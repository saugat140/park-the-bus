-- Assign a rarity tier from the curated fame rating. Issue #21.
-- Apply after db/001_schema.sql.
--
-- Fame 5 is the answer almost everyone gives. Fame 1 is the specialist
-- answer. The prior is a number on this scale, higher when the answer
-- is rarer. Pageviews are not an input.
--
--   fame 5 → 0    Sunday League
--   fame 4 → 25   Championship
--   fame 3 → 50   FA Cup
--   fame 2 → 75   Premier League
--   fame 1 → 100  World Cup
--
-- A tier runs from its minimum inclusive to its maximum exclusive.
-- Champions League is 80 up to 100. No hand rating lands there. Issue
-- #27 writes blended_rarity from observed counts, and the tier then
-- follows the blend instead of the fame prior.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/004_tier_assignment.sql
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/004_tier_assignment_test.sql
--
-- After a prompt answer CSV is loaded:
--   SELECT assign_prompt_answer_tiers();

UPDATE rarity_tiers
SET min_rarity = v.min_rarity, max_rarity = v.max_rarity
FROM (VALUES
  (1::smallint, 0::numeric, 20::numeric),
  (2, 20, 40),
  (3, 40, 60),
  (4, 60, 80),
  (5, 80, 100),
  (6, 100, NULL)
) AS v(tier_number, min_rarity, max_rarity)
WHERE rarity_tiers.tier_number = v.tier_number;

COMMENT ON COLUMN rarity_tiers.min_rarity IS
  'Inclusive lower bound. Tier 1 starts at 0.';

COMMENT ON COLUMN rarity_tiers.max_rarity IS
  'Exclusive upper bound. Tier 6 has no upper bound.';

CREATE OR REPLACE FUNCTION prior_rarity_from_fame(p_fame smallint)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE p_fame
    WHEN 5 THEN 0
    WHEN 4 THEN 25
    WHEN 3 THEN 50
    WHEN 2 THEN 75
    WHEN 1 THEN 100
  END;
$$;

COMMENT ON FUNCTION prior_rarity_from_fame(smallint) IS
  'Curated fame 5 through 1 as a rarity prior, 0 through 100. Pageviews are not an input.';

CREATE OR REPLACE FUNCTION tier_for_rarity(p_rarity numeric)
RETURNS smallint
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT tier_number
  FROM rarity_tiers
  WHERE p_rarity IS NOT NULL
    AND (min_rarity IS NULL OR p_rarity >= min_rarity)
    AND (max_rarity IS NULL OR p_rarity < max_rarity);
$$;

COMMENT ON FUNCTION tier_for_rarity(numeric) IS
  'The tier whose minimum is inclusive and whose maximum is exclusive.';

CREATE OR REPLACE FUNCTION assign_prompt_answer_tiers()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  updated integer;
BEGIN
  UPDATE prompt_answers
  SET prior_rarity = prior_rarity_from_fame(fame),
      tier_number = tier_for_rarity(COALESCE(blended_rarity, prior_rarity_from_fame(fame)));
  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated;
END;
$$;

COMMENT ON FUNCTION assign_prompt_answer_tiers() IS
  'Sets each answer prior from fame, then the tier from blended rarity when issue #27 has written one, otherwise from the prior.';
