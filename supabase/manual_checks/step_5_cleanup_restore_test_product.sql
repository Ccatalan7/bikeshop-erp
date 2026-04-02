-- STEP 5: Optional cleanup if you ran the separated test outside a transaction.
-- Replace PRODUCT_ID_HERE with the product_id from step 1.
-- Only run this after you are done inspecting evidence.

delete from public.user_activity_log
where details->>'product_id' = 'PRODUCT_ID_HERE'
  and action in ('product_conversion', 'product_conversion_restore');

delete from public.journal_lines
where entry_id in (
  select id
  from public.journal_entries
  where source_reference = 'PRODUCT_ID_HERE'
    and source_module in ('product_conversion', 'product_restore')
);

delete from public.journal_entries
where source_reference = 'PRODUCT_ID_HERE'
  and source_module in ('product_conversion', 'product_restore');

delete from public.stock_adjustments
where product_id = 'PRODUCT_ID_HERE'::uuid
  and (
    reference like 'product_conversion:%'
    or reference like 'product_restore:%'
  );

delete from public.products
where id = 'PRODUCT_ID_HERE'::uuid;