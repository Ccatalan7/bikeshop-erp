┌───────────────────────────────────────────────────────────────────────────┐
│                            pg_get_functiondef                             │
├───────────────────────────────────────────────────────────────────────────┤
│ CREATE OR REPLACE FUNCTION public.handle_purchase_payment_change()        │
│  RETURNS trigger                                                          │
│  LANGUAGE plpgsql                                                         │
│ AS $function$                                                             │
│ begin                                                                     │
│   if TG_OP = 'INSERT' then                                                │
│     perform public.create_purchase_payment_journal_entry(NEW.id);         │
│     perform public.recalculate_purchase_invoice_payments(NEW.invoice_id); │
│   elsif TG_OP = 'UPDATE' then                                             │
│     perform public.delete_purchase_payment_journal_entry(OLD.id);         │
│     perform public.create_purchase_payment_journal_entry(NEW.id);         │
│     perform public.recalculate_purchase_invoice_payments(NEW.invoice_id); │
│   elsif TG_OP = 'DELETE' then                                             │
│     perform public.delete_purchase_payment_journal_entry(OLD.id);         │
│     perform public.recalculate_purchase_invoice_payments(OLD.invoice_id); │
│   end if;                                                                 │
│   return NULL;                                                            │
│ end;                                                                      │
│ $function$                                                                │
└───────────────────────────────────────────────────────────────────────────┘
