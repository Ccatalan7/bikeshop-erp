-- Chat sender labels must represent the identity that authored the message.
--
-- A company-owner Auth identity can legitimately have both an active ERP
-- profile and an older public-store customer membership. The previous lookup
-- skipped ERP profiles without an employee row, then returned the customer
-- name. That made Viñabike-authored messages appear as "Usuario" after the
-- company owner was correctly separated from Claudio's employee identity.
--
-- Preserve the existing visibility boundary and employee/customer behavior,
-- but resolve an active ERP profile before considering a customer membership.
-- Forward: replace one stable read RPC; no rows are rewritten.
-- Recovery: restore the prior function definition if the added precedence is
--           rejected; customer/profile data remains unchanged.
-- Lock risk: CREATE OR REPLACE takes only the bounded function-definition lock.
-- Backfill/replay: none; re-execution converges on the same definition and ACL.

create or replace function public.get_public_user_info(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_visible_tenant_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'User id is required' using errcode = '22004';
  end if;

  -- Self lookup is allowed only through a current tenant membership.
  if p_user_id = auth.uid() then
    select tenant_id into v_visible_tenant_id
    from (
      select profile.tenant_id, 1 as priority
      from public.user_profiles profile
      where profile.user_id = p_user_id
        and coalesce(profile.is_active, true)
      union all
      select customer.tenant_id, 2
      from public.customers customer
      where customer.auth_user_id = p_user_id
        and coalesce(customer.is_active, true)
    ) membership
    order by priority
    limit 1;
  else
    -- A target is public to this caller only after an accessible conversation
    -- proves that the target participates in or authored that exact graph.
    select conversation.tenant_id into v_visible_tenant_id
    from public.conversations conversation
    where public.messaging_can_read_conversation_messages(conversation.id)
      and (
        exists (
          select 1
          from public.conversation_participants participant
          where participant.conversation_id = conversation.id
            and participant.tenant_id = conversation.tenant_id
            and participant.user_id = p_user_id
        )
        or exists (
          select 1
          from public.messages message
          where message.conversation_id = conversation.id
            and message.tenant_id = conversation.tenant_id
            and message.sender_id = p_user_id
        )
      )
    order by conversation.last_message_at desc nulls last
    limit 1;
  end if;

  if v_visible_tenant_id is null then
    raise exception 'User is not visible in an accessible conversation'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', employee.user_id,
    'name', coalesce(
      nullif(btrim(concat_ws(' ', employee.first_name, employee.last_name)), ''),
      'Soporte'
    ),
    'avatar_url', employee.photo_url,
    'role', 'employee'
  ) into v_result
  from public.employees employee
  where employee.user_id = p_user_id
    and employee.tenant_id = v_visible_tenant_id
  limit 1;

  if v_result is null then
    select jsonb_build_object(
      'id', profile.user_id,
      'name', coalesce(
        nullif(btrim(concat_ws(' ', employee.first_name, employee.last_name)), ''),
        'Soporte'
      ),
      'avatar_url', employee.photo_url,
      'role', 'employee'
    ) into v_result
    from public.user_profiles profile
    join public.employees employee
      on employee.id = profile.employee_id
     and employee.tenant_id = profile.tenant_id
    where profile.user_id = p_user_id
      and profile.tenant_id = v_visible_tenant_id
      and coalesce(profile.is_active, true)
    limit 1;
  end if;

  -- A corporate owner is an ERP principal even though it intentionally has no
  -- employee row. Resolve that principal before a legacy/customer membership.
  if v_result is null then
    select jsonb_build_object(
      'id', profile.user_id,
      'name', coalesce(
        public.erp_actor_display_name(profile.user_id, profile.tenant_id),
        'Soporte'
      ),
      'avatar_url', auth_user.raw_user_meta_data->>'avatar_url',
      'role', 'erp_user'
    ) into v_result
    from public.user_profiles profile
    join auth.users auth_user
      on auth_user.id = profile.user_id
    where profile.user_id = p_user_id
      and profile.tenant_id = v_visible_tenant_id
      and coalesce(profile.is_active, true)
    limit 1;
  end if;

  if v_result is null then
    select jsonb_build_object(
      'id', customer.auth_user_id,
      'name', coalesce(nullif(btrim(customer.name), ''), 'Cliente'),
      'avatar_url', customer.image_url,
      'role', 'customer'
    ) into v_result
    from public.customers customer
    where customer.auth_user_id = p_user_id
      and customer.tenant_id = v_visible_tenant_id
      and coalesce(customer.is_active, true)
    limit 1;
  end if;

  if v_result is null then
    select jsonb_build_object(
      'id', auth_user.id,
      'name', coalesce(
        nullif(btrim(auth_user.raw_user_meta_data->>'full_name'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'name'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'display_name'), ''),
        'Usuario'
      ),
      'avatar_url', auth_user.raw_user_meta_data->>'avatar_url',
      'role', 'unknown'
    ) into v_result
    from auth.users auth_user
    where auth_user.id = p_user_id;
  end if;

  return coalesce(
    v_result,
    jsonb_build_object(
      'id', p_user_id,
      'name', 'Usuario',
      'avatar_url', null,
      'role', 'unknown'
    )
  );
end;
$$;

revoke all on function public.get_public_user_info(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_user_info(uuid)
  to authenticated;
