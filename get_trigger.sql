┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                            pg_get_functiondef                                                            │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()                                                                       │
│  RETURNS trigger                                                                                                                         │
│  LANGUAGE plpgsql                                                                                                                        │
│  SECURITY DEFINER                                                                                                                        │
│  SET search_path TO 'public'                                                                                                             │
│ AS $function$                                                                                                                            │
│ declare                                                                                                                                  │
│   v_old_status text;                                                                                                                     │
│   v_new_status text;                                                                                                                     │
│ begin                                                                                                                                    │
│   raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;                                                                         │
│                                                                                                                                          │
│   if TG_OP = 'INSERT' then                                                                                                               │
│     v_new_status := NEW.status;                                                                                                          │
│     raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;                                     │
│                                                                                                                                          │
│     -- Inventory: ONLY if inserted directly as 'received' (rare case)                                                                    │
│     if v_new_status = 'received' then                                                                                                    │
│       raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';                                            │
│       perform public.consume_purchase_invoice_inventory(NEW);                                                                            │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     -- Journal: If inserted at 'confirmed' or later                                                                                      │
│     if v_new_status IN ('confirmed', 'received', 'paid') then                                                                            │
│       raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';                          │
│       perform public.create_purchase_invoice_journal_entry(NEW);                                                                         │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     perform public.recalculate_purchase_invoice_payments(NEW.id);                                                                        │
│     return NEW;                                                                                                                          │
│                                                                                                                                          │
│   elsif TG_OP = 'UPDATE' then                                                                                                            │
│     v_old_status := OLD.status;                                                                                                          │
│     v_new_status := NEW.status;                                                                                                          │
│                                                                                                                                          │
│     raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;     │
│                                                                                                                                          │
│     -- INVENTORY HANDLING: ONLY at 'received' status                                                                                     │
│     -- Different logic for standard vs prepayment models:                                                                                │
│     --                                                                                                                                   │
│     -- STANDARD MODEL: Draft→Confirmed→RECEIVED→Paid                                                                                     │
│     --   Inventory added at 'received', stays through 'paid'                                                                             │
│     --   So: received<->paid transitions do NOT change inventory                                                                         │
│     --                                                                                                                                   │
│     -- PREPAYMENT MODEL: Draft→Confirmed→Paid→RECEIVED                                                                                   │
│     --   Inventory added at 'received' (after payment)                                                                                   │
│     --   So: received<->paid transitions DO change inventory                                                                             │
│                                                                                                                                          │
│     if NEW.prepayment_model then                                                                                                         │
│       -- PREPAYMENT MODEL: Inventory changes whenever entering/leaving 'received'                                                        │
│       if v_old_status != 'received' AND v_new_status = 'received' then                                                                   │
│         -- Transitioning TO received (from any status): add inventory                                                                    │
│         raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning TO received from %, consuming inventory', v_old_status; │
│         perform public.consume_purchase_invoice_inventory(NEW);                                                                          │
│                                                                                                                                          │
│       elsif v_old_status = 'received' AND v_new_status != 'received' then                                                                │
│         -- Transitioning FROM received (to any status): remove inventory                                                                 │
│         raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning FROM received to %, restoring inventory', v_new_status; │
│         perform public.restore_purchase_invoice_inventory(OLD);                                                                          │
│                                                                                                                                          │
│       elsif v_old_status = 'received' AND v_new_status = 'received' then                                                                 │
│         -- Staying at received but invoice data changed: update inventory                                                                │
│         raise notice 'handle_purchase_invoice_change: [PREPAYMENT] staying at received, updating inventory';                             │
│         perform public.restore_purchase_invoice_inventory(OLD);                                                                          │
│         perform public.consume_purchase_invoice_inventory(NEW);                                                                          │
│       end if;                                                                                                                            │
│                                                                                                                                          │
│     else                                                                                                                                 │
│       -- STANDARD MODEL: Inventory changes only when entering/leaving 'received' from/to non-paid statuses                               │
│       if v_old_status NOT IN ('received', 'paid') AND v_new_status = 'received' then                                                     │
│         -- Transitioning TO received from confirmed/sent/draft: add inventory                                                            │
│         raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning TO received from %, consuming inventory', v_old_status;   │
│         perform public.consume_purchase_invoice_inventory(NEW);                                                                          │
│                                                                                                                                          │
│       elsif v_old_status = 'received' AND v_new_status NOT IN ('received', 'paid') then                                                  │
│         -- Transitioning FROM received to confirmed/sent/draft: remove inventory                                                         │
│         -- Note: received→paid does NOT remove (goods stay in standard flow)                                                             │
│         raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning FROM received to %, restoring inventory', v_new_status;   │
│         perform public.restore_purchase_invoice_inventory(OLD);                                                                          │
│                                                                                                                                          │
│       elsif v_old_status = 'received' AND v_new_status = 'received' then                                                                 │
│         -- Staying at received but invoice data changed: update inventory                                                                │
│         raise notice 'handle_purchase_invoice_change: [STANDARD] staying at received, updating inventory';                               │
│         perform public.restore_purchase_invoice_inventory(OLD);                                                                          │
│         perform public.consume_purchase_invoice_inventory(NEW);                                                                          │
│       end if;                                                                                                                            │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     -- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting                                                         │
│     -- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)                                        │
│     -- It should NOT be recreated when moving between confirmed→received→paid                                                            │
│     -- It should ONLY be recreated if staying at same status but amounts changed                                                         │
│                                                                                                                                          │
│     if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then                         │
│       -- Transitioning TO confirmed/received/paid: create journal entry                                                                  │
│       raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';                   │
│       perform public.create_purchase_invoice_journal_entry(NEW);                                                                         │
│                                                                                                                                          │
│     elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then                      │
│       -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry                                        │
│       raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';                 │
│       perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);                                                          │
│                                                                                                                                          │
│     elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then                                         │
│       -- Staying at same confirmed+ status but invoice data might have changed                                                           │
│       -- Only recreate journal if amounts changed (not just status transition)                                                           │
│       if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR                                                                                   │
│          OLD.tax IS DISTINCT FROM NEW.tax OR                                                                                             │
│          OLD.total IS DISTINCT FROM NEW.total OR                                                                                         │
│          OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then                                                                           │
│         raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';                         │
│         perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);                                                        │
│         perform public.create_purchase_invoice_journal_entry(NEW);                                                                       │
│       end if;                                                                                                                            │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     -- Only recalculate if this is NOT a payment-only update (prevents infinite recursion)                                               │
│     -- If only paid_amount, balance, or status changed → skip recalculate (it's from recalculate itself)                                 │
│     -- If items, total, subtotal, tax, or other fields changed → call recalculate                                                        │
│     if OLD.items IS DISTINCT FROM NEW.items OR                                                                                           │
│        OLD.subtotal IS DISTINCT FROM NEW.subtotal OR                                                                                     │
│        OLD.tax IS DISTINCT FROM NEW.tax OR                                                                                               │
│        OLD.total IS DISTINCT FROM NEW.total OR                                                                                           │
│        OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR                                                                               │
│        OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then                                                                   │
│       raise notice 'handle_purchase_invoice_change: invoice data changed, recalculating payments';                                       │
│       perform public.recalculate_purchase_invoice_payments(NEW.id);                                                                      │
│     else                                                                                                                                 │
│       raise notice 'handle_purchase_invoice_change: only payment fields changed, skipping recalculate to avoid recursion';               │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     return NEW;                                                                                                                          │
│                                                                                                                                          │
│   elsif TG_OP = 'DELETE' then                                                                                                            │
│     v_old_status := OLD.status;                                                                                                          │
│     raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;                                     │
│                                                                                                                                          │
│     -- Restore inventory if was received                                                                                                 │
│     if v_old_status = 'received' then                                                                                                    │
│       raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';                                     │
│       perform public.restore_purchase_invoice_inventory(OLD);                                                                            │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     -- Delete journal entry if was confirmed or later                                                                                    │
│     if v_old_status IN ('confirmed', 'received', 'paid') then                                                                            │
│       raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';                   │
│       perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);                                                          │
│     end if;                                                                                                                              │
│                                                                                                                                          │
│     return OLD;                                                                                                                          │
│   end if;                                                                                                                                │
│                                                                                                                                          │
│   return NULL;                                                                                                                           │
│ end;                                                                                                                                     │
│ $function$                                                                                                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
