-- RPC to get basic public user info (name, avatar, role) for chat participants
-- This bypasses strict RLS and table structure differences
create or replace function public.get_public_user_info(p_user_id uuid)
returns jsonb
language plpgsql
security definer -- Runs with elevated privileges
as $$
declare
  v_result jsonb;
begin
  -- 1. Try to find in employees table (via user_id)
  -- Note: user_profiles does not have name column, employees does
  select jsonb_build_object(
    'id', user_id,
    'name', coalesce(first_name || ' ' || last_name, 'Soporte'),
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

  -- 2. If not found, try customers (for completeness)
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

  -- 3. Fallback: try auth.users metadata if absolutely necessary (optional)
  if v_result is null then
     select jsonb_build_object(
      'id', id,
      'name', coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', email),
      'avatar_url', raw_user_meta_data->>'avatar_url',
      'role', 'unknown'
    )
    into v_result
    from auth.users
    where id = p_user_id;
  end if;

  return v_result;
end;
$$;
