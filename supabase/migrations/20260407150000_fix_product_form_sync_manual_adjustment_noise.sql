-- Fix product-form/manual-save phantom stock adjustments caused by legacy
-- inventory_qty and stock_quantity drift.
--
-- This migration does two things:
-- 1) Updates track_product_stock_changes() so pure column resyncs do not emit
--    fake manual stock adjustments, and intentional edits from a drifted state
--    are measured from inventory_qty instead of the stale stock_quantity.
-- 2) Deletes the exact standalone phantom manual-adjustment rows confirmed on
--    2026-04-07 and 2026-04-04 in the stock movements screen.

create or replace function track_product_stock_changes()
returns trigger as $$
declare
  v_adjustment_type text;
  v_reason text;
  v_reference text;
  v_context text;
  v_stock_before integer;
  v_stock_after integer;
  v_adjustment_qty integer;
begin
  if coalesce(NEW.product_type, 'product') = 'service'
     or coalesce(NEW.track_stock, true) = false then
    return NEW;
  end if;

  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true' then
    return NEW;
  end if;

  if (TG_OP = 'UPDATE' and OLD.stock_quantity <> NEW.stock_quantity) then
    if OLD.inventory_qty is distinct from OLD.stock_quantity
       and NEW.stock_quantity = NEW.inventory_qty then
      v_stock_before := OLD.inventory_qty;
      v_stock_after := NEW.inventory_qty;
    else
      v_stock_before := OLD.stock_quantity;
      v_stock_after := NEW.stock_quantity;
    end if;

    v_adjustment_qty := v_stock_after - v_stock_before;

    if v_adjustment_qty = 0 then
      return NEW;
    end if;

    v_context := current_setting('app.stock_adjustment_context', true);

    if v_context = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(current_setting('app.import_reason', true), 'Stock updated via import');
      v_reference := current_setting('app.import_reference', true);
    elsif v_context = 'purchase' then
      v_adjustment_type := 'purchase';
      v_reason := 'Compra recibida (Invoice ' || coalesce(current_setting('app.stock_adjustment_reference', true), 'Unknown') || ')';
      v_reference := current_setting('app.stock_adjustment_reference', true);
    else
      v_adjustment_type := 'manual';
      v_reason := 'Ajuste Manual';
      v_reference := null;
    end if;

    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      v_adjustment_qty,
      v_stock_before,
      v_stock_after,
      v_reason,
      v_reference,
      auth.uid()
    );

  elsif (TG_OP = 'INSERT' and NEW.stock_quantity > 0) then
    v_context := current_setting('app.stock_adjustment_context', true);

    if v_context = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(current_setting('app.import_reason', true), 'Initial stock via import');
      v_reference := current_setting('app.import_reference', true);
    else
      v_adjustment_type := 'initial';
      v_reason := 'Initial stock on product creation';
      v_reference := null;
    end if;

    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity,
      0,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );
  end if;

  return NEW;
end;
$$ language plpgsql security definer;

begin;

create temp table tmp_product_form_sync_noise_adjustments on commit drop as
select *
from public.stock_adjustments
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and id in (
    'e5aa304d-25b4-4138-9252-39cc4157428c',
    'b7368f4b-4d99-4042-a967-37f222a8969f',
    'f52a82f2-7ee4-4fb7-90e8-86754ceb5428',
    '606802ed-0371-41ab-9007-fb28d145784e',
    'b4bb1996-71a5-4644-80cb-36ff76967e9b'
  );

create temp table tmp_product_form_sync_noise_movements on commit drop as
select sm.*
from public.stock_movements sm
join tmp_product_form_sync_noise_adjustments sa
  on sm.tenant_id = sa.tenant_id
 and sm.product_id = sa.product_id
 and sm.created_at = sa.created_at
 and coalesce(sm.movement_type, '') = 'manual'
 and coalesce(sm.notes, '') = coalesce(sa.reason, '')
 and coalesce(sm.reference, '') = coalesce(sa.reference, '');

delete from public.stock_movements sm
using tmp_product_form_sync_noise_movements doomed
where sm.id = doomed.id;

delete from public.stock_adjustments sa
using tmp_product_form_sync_noise_adjustments doomed
where sa.id = doomed.id;

commit;