begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  -- Realtime authorizes a private channel by inserting and reading a
  -- synthetic messages row inside a rolled-back transaction. The channel's
  -- private mode is enforced by the Realtime join itself; the authorization
  -- row is not a durable broadcast row and must not be filtered by its
  -- `private` column. Keep authorization scoped to both the Broadcast
  -- extension and the authenticated user's exact tenant topic.
  if to_regclass('realtime.messages') is not null then
    execute
      'drop policy if exists "Tenant members receive financial projection broadcasts" '
      'on realtime.messages';
    execute $policy$
      create policy "Tenant members receive financial projection broadcasts"
        on realtime.messages
        for select
        to authenticated
        using (
          extension = 'broadcast'
          and (select realtime.topic()) =
            'financial-projections:' ||
            (select public.user_tenant_id())::text
        )
    $policy$;
  end if;
end
$$;

commit;
