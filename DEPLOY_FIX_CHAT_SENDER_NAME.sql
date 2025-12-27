-- ============================================================
-- FIX: Chat sender name showing "Usuario" instead of employee name
-- Deploy to: Supabase SQL Editor
-- Date: Dec 26, 2025
-- ============================================================

-- The issue: When employees send messages, their name shows as "Usuario"
-- instead of their actual name. This happens because:
-- 1. The RPC wasn't checking all possible sources for employee names
-- 2. There was a duplicate (incorrect) function definition

-- This enhanced RPC checks:
-- 1. employees table (by user_id)
-- 2. user_profiles joined with employees (by employee_id)
-- 3. customers table (by auth_user_id)
-- 4. auth.users metadata (fallback)
-- 5. Default to "Soporte" if nothing found

create or replace function public.get_public_user_info(p_user_id uuid)
returns jsonb
language plpgsql
security definer -- Runs with elevated privileges
as $$
declare
  v_result jsonb;
begin
  -- 1. Try to find in employees table directly (via user_id)
  select jsonb_build_object(
    'id', user_id,
    'name', coalesce(nullif(trim(first_name || ' ' || last_name), ''), 'Soporte'),
    'avatar_url', photo_url,
    'role', 'employee'
  )
  into v_result
  from public.employees
  where user_id = p_user_id
  limit 1;

  if v_result is not null then
    return v_result;
  end if;

  -- 2. Try user_profiles joined with employees (for when employee_id is linked)
  select jsonb_build_object(
    'id', up.user_id,
    'name', coalesce(nullif(trim(e.first_name || ' ' || e.last_name), ''), 'Soporte'),
    'avatar_url', e.photo_url,
    'role', 'employee'
  )
  into v_result
  from public.user_profiles up
  inner join public.employees e on e.id = up.employee_id
  where up.user_id = p_user_id
  limit 1;

  if v_result is not null then
    return v_result;
  end if;

  -- 3. If not an employee, try customers
  select jsonb_build_object(
    'id', auth_user_id,
    'name', coalesce(name, 'Cliente'),
    'avatar_url', image_url,
    'role', 'customer'
  )
  into v_result
  from public.customers
  where auth_user_id = p_user_id
  limit 1;

  if v_result is not null then
    return v_result;
  end if;

  -- 4. Fallback: try auth.users metadata
  select jsonb_build_object(
    'id', id,
    'name', coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', split_part(email, '@', 1)),
    'avatar_url', raw_user_meta_data->>'avatar_url',
    'role', 'unknown'
  )
  into v_result
  from auth.users
  where id = p_user_id;

  -- 5. Absolute fallback - never return null
  return coalesce(v_result, jsonb_build_object('id', p_user_id, 'name', 'Soporte', 'avatar_url', null, 'role', 'employee'));
end;
$$;

-- Grant execute permission
grant execute on function public.get_public_user_info(uuid) to authenticated;
grant execute on function public.get_public_user_info(uuid) to anon;
