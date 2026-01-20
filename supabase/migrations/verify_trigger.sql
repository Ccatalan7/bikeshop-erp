-- VERIFICATION SCRIPT: Confirm Trigger Installation
-- This checks if 'trg_handle_purchase_invoice_deletion' exists on 'purchase_invoices'

select 
    trigger_name,
    event_manipulation as event,
    event_object_table as table_name,
    action_timing as timing
from information_schema.triggers
where event_object_table = 'purchase_invoices'
and trigger_name = 'trg_handle_purchase_invoice_deletion';
