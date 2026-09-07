-- Synthetic-test prerequisite only. The minimal historical local fixture lacks
-- the two reading columns added by 20260831270000. Their production constraints
-- are covered by that migration's own tests, not recreated by this binding test.
alter table public.spec_fact_readings add column if not exists vocabulary_digest text;
alter table public.spec_fact_readings add column if not exists definition_id uuid;
