-- Deployment status: DEPLOYED 2026-07-11. No tenant was activated by this migration.
-- Old clients keep the legacy status path while disabled/shadow; enforce mode
-- blocks that writer before it can race or double-post the receipt command.

begin;

create or replace function public.guard_legacy_purchase_receiving_when_enforced()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_mode text := 'disabled';
begin
  if new.status = 'received'
     and (tg_op = 'INSERT' or old.status is distinct from 'received') then
    select coalesce(setting.control_mode, 'disabled') into v_mode
    from (select 1) seed
    left join public.purchase_receipt_control_settings setting
      on setting.tenant_id = new.tenant_id;

    if v_mode = 'enforce' then
      raise exception using
        errcode = 'P0001',
        message = 'Professional receiving is active; use the goods receipt command';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_legacy_purchase_receiving_when_enforced
  on public.purchase_invoices;
create trigger trg_guard_legacy_purchase_receiving_when_enforced
before insert or update of status on public.purchase_invoices
for each row execute function public.guard_legacy_purchase_receiving_when_enforced();

comment on function public.guard_legacy_purchase_receiving_when_enforced() is
  'Compatibility guard: legacy invoice-status receipt remains available until tenant enforce activation, then fails before stock effects.';

commit;
