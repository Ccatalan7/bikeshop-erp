-- Restore the original product configuration from the latest unreversed
-- workshop-consumable conversion snapshot.
--
-- Safe default:
-- - restores configuration only
-- - keeps stock at 0
-- - does NOT recreate inventory value
--
-- Full restore:
-- - set p_restore_inventory => true
-- - this only succeeds if there was no product activity after conversion

-- Example 1: restore configuration only (safe default)
select public.restore_product_conversion_state(
  p_product_id => 'ca14c728-690d-4bee-9ffc-7aad041efb77'::uuid,
  p_reason => 'Rollback de configuración de producto',
  p_restore_inventory => false
);

-- Example 2: full restore including stock/value
-- This will fail safely if there were sales, purchases, or stock activity after conversion.
--
-- select public.restore_product_conversion_state(
--   p_product_id => 'ca14c728-690d-4bee-9ffc-7aad041efb77'::uuid,
--   p_reason => 'Rollback completo de conversión',
--   p_restore_inventory => true
-- );
