-- =====================================================
-- HOTFIX: Fix invalid input syntax for uuid: "" in trigger function
-- =====================================================
-- Problem: auto_update_purchase_list_on_invoice_status crashes when an invoice item
-- has product_id="" (empty string) instead of null.
-- Solution: Use nullif(..., '')::uuid to handle empty strings safely.
-- =====================================================

create or replace function public.auto_update_purchase_list_on_invoice_status()
returns trigger
language plpgsql
security definer
as $$
declare
  v_item jsonb;
  v_product_id uuid;
begin
  -- When invoice is confirmed or received, mark linked items as ordered
  if NEW.status in ('confirmed', 'received') and OLD.status not in ('confirmed', 'received') then
    -- Loop through items in the JSONB array
    for v_item in select * from jsonb_array_elements(NEW.items)
    loop
      -- FIX: Handle empty string product_id safely before casting to UUID
      begin
        v_product_id := (nullif(v_item->>'product_id', '')::uuid);
      exception when others then
        v_product_id := null;
      end;
      
      if v_product_id is not null then
        update smart_purchase_list spl
        set 
          status = 'ordered',
          linked_purchase_invoice_id = NEW.id,
          ordered_date = coalesce(ordered_date, now()),
          stock_at_order = (select stock_quantity from products where id = v_product_id),
          updated_at = now()
        where spl.product_id = v_product_id
          and spl.tenant_id = NEW.tenant_id
          and spl.status = 'pending'
          and (spl.linked_purchase_invoice_id is null or spl.linked_purchase_invoice_id = NEW.id);
      end if;
    end loop;
  end if;
  
  -- When invoice is received or paid, UPDATE status to 'received' (keep history!)
  if NEW.status in ('received', 'paid') and OLD.status not in ('received', 'paid') then
    -- Loop through items in the JSONB array
    for v_item in select * from jsonb_array_elements(NEW.items)
    loop
      -- FIX: Handle empty string product_id safely before casting to UUID
      begin
        v_product_id := (nullif(v_item->>'product_id', '')::uuid);
      exception when others then
        v_product_id := null;
      end;
      
      if v_product_id is not null then
        -- Update status to 'received' and record the date + final stock
        update smart_purchase_list
        set 
          status = 'received',
          received_date = now(),
          stock_at_receipt = (select stock_quantity from products where id = v_product_id),
          updated_at = now()
        where product_id = v_product_id
          and tenant_id = NEW.tenant_id
          and status in ('pending', 'ordered')
          and (linked_purchase_invoice_id is null or linked_purchase_invoice_id = NEW.id);
        
        raise notice '✅ Marked product % as received in purchase list (invoice % received)', v_product_id, NEW.id;
      end if;
    end loop;
  end if;
  
  return NEW;
end;
$$;
