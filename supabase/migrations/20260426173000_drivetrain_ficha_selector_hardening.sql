-- Harden standardized drivetrain ficha selectors for common chain/cassette counts.
-- Mirrors the canonical definitions in supabase/sql/core_schema.sql.

update public.spec_definitions
set
  allowed_values = '["72","76","80","82","84","86","88","90","92","94","96","98","100","102","104","106","108","110","112","114","116","118","120","122","124","126","128","130","132","134","136"]'::jsonb,
  validation_rules = '{"min":72,"max":136}'::jsonb,
  updated_at = now()
where tenant_id is null
  and key = 'link_count';

update public.spec_definitions
set
  allowed_values = '["8","9","10","11","12","13","14","15","16"]'::jsonb,
  validation_rules = '{"min":8,"max":24}'::jsonb,
  updated_at = now()
where tenant_id is null
  and key = 'smallest_cog_teeth';

update public.spec_definitions
set
  allowed_values = '["14","15","16","18","20","21","22","24","25","26","27","28","30","32","34","36","38","40","42","44","46","48","50","51","52","54","56","58","60"]'::jsonb,
  validation_rules = '{"min":14,"max":60}'::jsonb,
  updated_at = now()
where tenant_id is null
  and key = 'largest_cog_teeth';