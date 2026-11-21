-- Tests for db/004_tier_assignment.sql. Issue #21.
-- Rolls back. Apply 001 and 004 first. This is not the xUnit suite in issue #26.
--
--   psql -d park_the_bus -v ON_ERROR_STOP=1 -f db/004_tier_assignment_test.sql

BEGIN;

DO $$
DECLARE
  probe numeric;
  tier smallint;
  match_count integer;
BEGIN
  FOREACH probe IN ARRAY ARRAY[0, 19.999, 20, 39.999, 40, 59.999, 60, 79.999, 80, 99.999, 100, 250]::numeric[]
  LOOP
    SELECT count(*) INTO match_count
    FROM rarity_tiers
    WHERE (min_rarity IS NULL OR probe >= min_rarity)
      AND (max_rarity IS NULL OR probe < max_rarity);
    IF match_count <> 1 THEN
      RAISE EXCEPTION 'rarity % matched % tiers', probe, match_count;
    END IF;
  END LOOP;

  IF tier_for_rarity(0) IS DISTINCT FROM 1
     OR tier_for_rarity(19.999) IS DISTINCT FROM 1
     OR tier_for_rarity(20) IS DISTINCT FROM 2
     OR tier_for_rarity(40) IS DISTINCT FROM 3
     OR tier_for_rarity(60) IS DISTINCT FROM 4
     OR tier_for_rarity(79.999) IS DISTINCT FROM 4
     OR tier_for_rarity(80) IS DISTINCT FROM 5
     OR tier_for_rarity(99.999) IS DISTINCT FROM 5
     OR tier_for_rarity(100) IS DISTINCT FROM 6
     OR tier_for_rarity(250) IS DISTINCT FROM 6 THEN
    RAISE EXCEPTION 'a boundary landed in the wrong tier';
  END IF;

  IF tier_for_rarity(NULL) IS NOT NULL OR tier_for_rarity(-1) IS NOT NULL THEN
    RAISE EXCEPTION 'a rarity below 0 or a null rarity should not score a tier';
  END IF;

  IF prior_rarity_from_fame(5::smallint) IS DISTINCT FROM 0
     OR prior_rarity_from_fame(4::smallint) IS DISTINCT FROM 25
     OR prior_rarity_from_fame(3::smallint) IS DISTINCT FROM 50
     OR prior_rarity_from_fame(2::smallint) IS DISTINCT FROM 75
     OR prior_rarity_from_fame(1::smallint) IS DISTINCT FROM 100
     OR prior_rarity_from_fame(NULL::smallint) IS NOT NULL THEN
    RAISE EXCEPTION 'fame did not map onto 0, 25, 50, 75, 100';
  END IF;

  SELECT tier_for_rarity(prior_rarity_from_fame(2::smallint)) INTO tier;
  IF tier IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'fame 2 should be Premier League before any blend, got %', tier;
  END IF;

  IF tier_for_rarity(prior_rarity_from_fame(1::smallint)) IS DISTINCT FROM 6
     OR tier_for_rarity(prior_rarity_from_fame(3::smallint)) IS DISTINCT FROM 3
     OR tier_for_rarity(prior_rarity_from_fame(5::smallint)) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'a hand fame rating landed in the wrong tier';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM generate_series(1, 5) AS fame
    WHERE tier_for_rarity(prior_rarity_from_fame(fame::smallint)) = 5
  ) THEN
    RAISE EXCEPTION 'Champions League is the blend band and no hand fame rating should land there';
  END IF;
END;
$$;

INSERT INTO entities (kind, canonical_name) VALUES
  ('player', 'Fame 5'),
  ('player', 'Fame 4'),
  ('player', 'Fame 3'),
  ('player', 'Fame 2'),
  ('player', 'Fame 1');

INSERT INTO prompts (prompt_text, answer_kind, difficulty, status) VALUES
  ('Name a fame probe', 'player', 1, 'reviewed');

INSERT INTO prompt_answers (prompt_id, entity_id, fame)
SELECT p.id, e.id, right(e.canonical_name, 1)::smallint
FROM prompts AS p
JOIN entities AS e ON e.canonical_name LIKE 'Fame %'
WHERE p.prompt_text = 'Name a fame probe';

DO $$
BEGIN
  IF assign_prompt_answer_tiers() <> 5 THEN
    RAISE EXCEPTION 'expected to assign five answers';
  END IF;
END;
$$;

DO $$
DECLARE
  points integer;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM prompt_answers AS pa
    JOIN entities AS e ON e.id = pa.entity_id
    WHERE (e.canonical_name = 'Fame 5' AND (pa.prior_rarity, pa.tier_number) IS DISTINCT FROM (0, 1))
       OR (e.canonical_name = 'Fame 4' AND (pa.prior_rarity, pa.tier_number) IS DISTINCT FROM (25, 2))
       OR (e.canonical_name = 'Fame 3' AND (pa.prior_rarity, pa.tier_number) IS DISTINCT FROM (50, 3))
       OR (e.canonical_name = 'Fame 2' AND (pa.prior_rarity, pa.tier_number) IS DISTINCT FROM (75, 4))
       OR (e.canonical_name = 'Fame 1' AND (pa.prior_rarity, pa.tier_number) IS DISTINCT FROM (100, 6))
  ) THEN
    RAISE EXCEPTION 'stored priors or tiers do not match the fame scale';
  END IF;

  SELECT score_prompt_answer(pa.prompt_id, pa.entity_id) INTO points
  FROM prompt_answers AS pa
  JOIN entities AS e ON e.id = pa.entity_id
  WHERE e.canonical_name = 'Fame 1';
  IF points IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'fame 1 should score World Cup, got %', points;
  END IF;

  SELECT score_prompt_answer(pa.prompt_id, pa.entity_id) INTO points
  FROM prompt_answers AS pa
  JOIN entities AS e ON e.id = pa.entity_id
  WHERE e.canonical_name = 'Fame 5';
  IF points IS DISTINCT FROM 10 THEN
    RAISE EXCEPTION 'fame 5 should score Sunday League, got %', points;
  END IF;
END;
$$;

UPDATE prompt_answers AS pa
SET blended_rarity = 80
FROM entities AS e
WHERE e.id = pa.entity_id
  AND e.canonical_name = 'Fame 2';

UPDATE prompt_answers AS pa
SET blended_rarity = 100
FROM entities AS e
WHERE e.id = pa.entity_id
  AND e.canonical_name = 'Fame 5';

SELECT assign_prompt_answer_tiers();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM prompt_answers AS pa
    JOIN entities AS e ON e.id = pa.entity_id
    WHERE (e.canonical_name = 'Fame 2' AND (pa.prior_rarity, pa.tier_number, pa.blended_rarity) IS DISTINCT FROM (75, 5, 80))
       OR (e.canonical_name = 'Fame 5' AND (pa.prior_rarity, pa.tier_number, pa.blended_rarity) IS DISTINCT FROM (0, 6, 100))
  ) THEN
    RAISE EXCEPTION 'a blended rarity should choose the tier and leave the fame prior in place';
  END IF;
END;
$$;

ROLLBACK;
