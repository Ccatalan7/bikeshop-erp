-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-05-20
-- Deployment verification: product_bulk_edit_history_operation_check includes 'custom'

alter table if exists product_bulk_edit_history
  drop constraint if exists product_bulk_edit_history_operation_check;

alter table if exists product_bulk_edit_history
  add constraint product_bulk_edit_history_operation_check
  check (operation in ('classification', 'channels', 'pricing', 'stock', 'images', 'custom'));
