-- Enable cross-device realtime sync for the global smart tasks panel.
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-06-21.
-- REPLICA IDENTITY FULL lets delete events include enough row data for
-- tenant-filtered realtime clients to remove tasks immediately.

do $$
begin
  if to_regclass('public.smart_tasks') is not null then
    alter table public.smart_tasks replica identity full;

    if exists (
      select 1
      from pg_publication
      where pubname = 'supabase_realtime'
    ) and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'smart_tasks'
    ) then
      alter publication supabase_realtime add table public.smart_tasks;
    end if;
  end if;
end $$;
