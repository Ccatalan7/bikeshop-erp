-- Persist complete Univer workbook snapshots while retaining legacy sparse
-- cells for one-time migration of existing planillas.
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Deployment verification: workbook_data is jsonb, migration history contains
-- 20260714233000, and the native macOS app persisted a live workbook edit at 80% zoom.

begin;

create table if not exists public.spreadsheets (
  id uuid default gen_random_uuid() primary key,
  tenant_id uuid not null default public.user_tenant_id(),
  name text not null default 'Planilla sin título',
  row_count integer not null default 100,
  col_count integer not null default 26,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.spreadsheets
  add column if not exists workbook_data jsonb;

comment on column public.spreadsheets.workbook_data is
  'Complete versioned workbook snapshot owned by the embedded spreadsheet engine.';

create table if not exists public.spreadsheet_cells (
  id uuid default gen_random_uuid() primary key,
  spreadsheet_id uuid not null references public.spreadsheets(id) on delete cascade,
  row_index integer not null,
  col_index integer not null,
  raw_value text,
  display_value text,
  cell_type text not null default 'text',
  bold boolean not null default false,
  italic boolean not null default false,
  text_align text not null default 'left',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (spreadsheet_id, row_index, col_index)
);

create index if not exists idx_spreadsheets_tenant
  on public.spreadsheets(tenant_id);
create index if not exists idx_cells_spreadsheet
  on public.spreadsheet_cells(spreadsheet_id);
create index if not exists idx_cells_position
  on public.spreadsheet_cells(spreadsheet_id, row_index, col_index);

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_spreadsheets_updated_at'
      and tgrelid = 'public.spreadsheets'::regclass
      and not tgisinternal
  ) then
    create trigger set_spreadsheets_updated_at
      before update on public.spreadsheets
      for each row execute function public.set_updated_at();
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_cells_updated_at'
      and tgrelid = 'public.spreadsheet_cells'::regclass
      and not tgisinternal
  ) then
    create trigger set_cells_updated_at
      before update on public.spreadsheet_cells
      for each row execute function public.set_updated_at();
  end if;
end
$$;

alter table public.spreadsheets enable row level security;
alter table public.spreadsheet_cells enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheets'
      and policyname = 'Tenant users can view spreadsheets'
  ) then
    create policy "Tenant users can view spreadsheets"
      on public.spreadsheets for select
      using (tenant_id = public.user_tenant_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheets'
      and policyname = 'Tenant users can create spreadsheets'
  ) then
    create policy "Tenant users can create spreadsheets"
      on public.spreadsheets for insert
      with check (tenant_id = public.user_tenant_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheets'
      and policyname = 'Tenant users can update spreadsheets'
  ) then
    create policy "Tenant users can update spreadsheets"
      on public.spreadsheets for update
      using (tenant_id = public.user_tenant_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheets'
      and policyname = 'Tenant users can delete spreadsheets'
  ) then
    create policy "Tenant users can delete spreadsheets"
      on public.spreadsheets for delete
      using (tenant_id = public.user_tenant_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheet_cells'
      and policyname = 'Tenant users can view cells'
  ) then
    create policy "Tenant users can view cells"
      on public.spreadsheet_cells for select
      using (
        exists (
          select 1 from public.spreadsheets s
          where s.id = spreadsheet_id
            and s.tenant_id = public.user_tenant_id()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheet_cells'
      and policyname = 'Tenant users can insert cells'
  ) then
    create policy "Tenant users can insert cells"
      on public.spreadsheet_cells for insert
      with check (
        exists (
          select 1 from public.spreadsheets s
          where s.id = spreadsheet_id
            and s.tenant_id = public.user_tenant_id()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheet_cells'
      and policyname = 'Tenant users can update cells'
  ) then
    create policy "Tenant users can update cells"
      on public.spreadsheet_cells for update
      using (
        exists (
          select 1 from public.spreadsheets s
          where s.id = spreadsheet_id
            and s.tenant_id = public.user_tenant_id()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheet_cells'
      and policyname = 'Tenant users can delete cells'
  ) then
    create policy "Tenant users can delete cells"
      on public.spreadsheet_cells for delete
      using (
        exists (
          select 1 from public.spreadsheets s
          where s.id = spreadsheet_id
            and s.tenant_id = public.user_tenant_id()
        )
      );
  end if;
end
$$;

commit;
