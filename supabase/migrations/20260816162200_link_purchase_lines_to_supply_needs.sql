-- Preserve the exact supply need that opened a direct purchase draft. The
-- canonical purchase line remains the economic owner; this FK is provenance,
-- not an implicit need-state transition or stock mutation.
begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

alter table public.purchase_invoice_lines
  add column if not exists source_need_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.purchase_invoice_lines'::regclass
      and constraint_row.conname =
        'purchase_invoice_lines_source_need_fkey'
  ) then
    alter table public.purchase_invoice_lines
      add constraint purchase_invoice_lines_source_need_fkey
      foreign key (tenant_id, source_need_id)
      references public.supply_needs(tenant_id, id)
      on update restrict
      on delete restrict;
  end if;
end;
$$;

create index if not exists idx_purchase_invoice_lines_source_need
  on public.purchase_invoice_lines(tenant_id, source_need_id, id)
  where source_need_id is not null;

create or replace function
  public.preserve_purchase_invoice_line_supply_need_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_raw text;
  v_from_source uuid;
  v_resolved uuid;
begin
  v_raw := nullif(btrim(coalesce(
    new.source_item ->> 'source_need_id',
    ''
  )), '');

  if v_raw is not null then
    if v_raw !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'Invalid supply need provenance.'
        using errcode = '22023';
    end if;
    v_from_source := v_raw::uuid;
  end if;

  if new.source_need_id is not null
     and v_from_source is not null
     and new.source_need_id <> v_from_source then
    raise exception 'Purchase line supply need provenance disagrees with its source snapshot.'
      using errcode = '22023';
  end if;

  v_resolved := coalesce(new.source_need_id, v_from_source);

  if tg_op = 'UPDATE'
     and old.source_need_id is not null
     and v_resolved is distinct from old.source_need_id then
    raise exception 'Purchase line supply need provenance is immutable.'
      using errcode = '22023';
  end if;

  if tg_op = 'UPDATE' then
    new.source_need_id := coalesce(v_resolved, old.source_need_id);
  else
    new.source_need_id := v_resolved;
  end if;
  return new;
end;
$$;

revoke all on function
  public.preserve_purchase_invoice_line_supply_need_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_preserve_purchase_invoice_line_supply_need
  on public.purchase_invoice_lines;
create trigger trg_preserve_purchase_invoice_line_supply_need
  before insert or update of source_item, source_need_id, tenant_id
  on public.purchase_invoice_lines
  for each row
  execute function public.preserve_purchase_invoice_line_supply_need_v1();

update public.purchase_invoice_lines
set source_need_id = null
where source_need_id is null
  and source_item ? 'source_need_id';

comment on column public.purchase_invoice_lines.source_need_id is
  'Immutable tenant-scoped provenance linking a purchased line to the exact supply need that opened the draft. It does not mutate need state.';

commit;
