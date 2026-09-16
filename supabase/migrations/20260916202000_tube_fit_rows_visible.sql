-- A tube is bought by wheel size. Its diameter lives in the fit rows
-- (20260916200000 filled 123 of them); the storefront can now render row
-- facts, so the rows become customer-visible under a shop label. Not
-- filterable: a row table is not a filter value.
-- Rerunnable: only the pending state is touched.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
update public.spec_definitions
   set is_customer_visible = true,
       label = 'Aro y ancho de neumático',
       updated_at = now()
 where tenant_id is null and key = 'tube_fit_rows'
   and (is_customer_visible is distinct from true or label is distinct from 'Aro y ancho de neumático');
commit;
