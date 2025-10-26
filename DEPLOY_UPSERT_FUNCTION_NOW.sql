-- Deploy upsert_company_setting function to fix 409 conflicts
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql

-- Drop old function first (if exists)
drop function if exists public.upsert_company_setting(uuid, text, text);

-- Helper function to upsert company settings (prevents 409 conflicts)
create or replace function public.upsert_company_setting(
  p_tenant_id uuid,
  p_key text,
  p_value text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_tenant_id uuid;
begin
  -- Get user's tenant_id
  v_user_tenant_id := public.user_tenant_id();
  
  -- Verify user has access to this tenant
  if p_tenant_id != v_user_tenant_id then
    raise exception 'Access denied: tenant_id % does not match user tenant %', p_tenant_id, v_user_tenant_id;
  end if;
  
  -- Perform upsert
  insert into company_settings (tenant_id, key, value, updated_at)
  values (p_tenant_id, p_key, p_value, now())
  on conflict (tenant_id, key) 
  do update set 
    value = excluded.value,
    updated_at = now();
  
  -- Return success
  return json_build_object('success', true);
exception
  when others then
    -- Return error details
    return json_build_object(
      'success', false,
      'error', SQLERRM,
      'detail', SQLSTATE
    );
end;
$$;

-- Grant execute to authenticated users
grant execute on function public.upsert_company_setting(uuid, text, text) to authenticated;
grant execute on function public.upsert_company_setting(uuid, text, text) to anon;

-- Verify function was created
SELECT 
  routine_name,
  routine_type,
  data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'upsert_company_setting';
-- Expected: 1 row showing the function exists

-- Test the function (optional)
-- SELECT public.upsert_company_setting(
--   '5fb195aa-2ec5-4a5d-b057-ed61156312ec'::uuid,
--   'test_key',
--   'test_value'
-- );

-- Check the result
-- SELECT * FROM company_settings 
-- WHERE tenant_id = '5fb195aa-2ec5-4a5d-b057-ed61156312ec'
--   AND key = 'test_key';
