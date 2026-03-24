-- Backfill script to fix missing IVA breakdown in journal entries
-- Created: 2026-03-24
-- This script identifies posted invoices with 'tax_included' that are missing the account 2150 in their JEs.

do $$
declare
    v_inv public.sales_invoices%rowtype;
    v_has_tax boolean;
    v_entry_id uuid;
    v_count int := 0;
begin
    raise notice 'Starting IVA breakdown backfill...';

    for v_inv in (
        select * from public.sales_invoices 
        where tax_treatment = 'tax_included'
          and status in ('confirmed', 'sent', 'paid')
          and total > 0
    ) loop
        -- Find existing JE
        select id into v_entry_id
        from public.journal_entries
        where source_module = 'sales_invoices' 
          and source_reference = v_inv.invoice_number 
          and tenant_id = v_inv.tenant_id;

        if v_entry_id is not null then
            -- Check if JE already has the IVA line (Account 2150)
            select exists (
                select 1 
                from public.journal_lines 
                where entry_id = v_entry_id 
                  and account_code = '2150'
                  and credit_amount > 0
            ) into v_has_tax;

            if not v_has_tax then
                raise notice 'Fixing missing IVA breakdown for invoice %', v_inv.invoice_number;
                
                -- Delete the old incorrect entries
                delete from public.journal_lines where entry_id = v_entry_id;
                delete from public.journal_entries where id = v_entry_id;
                
                -- Regenerate using the fixed function
                perform public.create_sales_invoice_journal_entry(v_inv);
                
                v_count := v_count + 1;
            end if;
        end if;
    end loop;

    raise notice 'Backfill complete. Fixed % journal entries.', v_count;
end $$;
