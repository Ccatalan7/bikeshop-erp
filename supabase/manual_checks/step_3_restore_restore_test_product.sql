-- STEP 3: Restore the test product back to inventory with stock/value.
-- Replace PRODUCT_ID_HERE with the product_id from step 1.
-- Replace CONVERSION_REFERENCE_HERE with the reference returned by step 2.

do $$
declare
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_actor_user_id uuid;
begin
  select up.user_id
    into v_actor_user_id
    from public.user_profiles up
   where up.tenant_id = v_tenant_id
     and up.user_id is not null
     and up.role in ('owner', 'admin', 'manager')
   order by case up.role
              when 'owner' then 1
              when 'admin' then 2
              when 'manager' then 3
              else 99
            end,
            up.created_at asc nulls last
   limit 1;

  if v_actor_user_id is null then
    raise exception 'No owner/admin/manager user found for tenant %', v_tenant_id;
  end if;

  perform set_config('request.jwt.claim.sub', v_actor_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end
$$;

select public.restore_product_conversion_state(
  'PRODUCT_ID_HERE'::uuid,
  'TEST SQL separated restore',
  true,
  'CONVERSION_REFERENCE_HERE'
) as restore_result;