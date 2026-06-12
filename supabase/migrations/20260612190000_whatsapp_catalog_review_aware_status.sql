-- Make WhatsApp catalog sync status review-aware.
--
-- Meta accepting a catalog product upsert (returning a product id and
-- visibility=published) does NOT mean the product is visible to customers in
-- WhatsApp. Customer visibility is gated by the asynchronous per-product review
-- field capability_to_review_status[WHATSAPP] == APPROVED. The old 'synced'
-- value falsely implied customer visibility. We now persist the real lifecycle:
--   under_review     -> Meta accepted it, still pending/NO_REVIEW (hidden)
--   customer_visible -> capability_to_review_status[WHATSAPP] = APPROVED (live)
--   rejected         -> capability_to_review_status[WHATSAPP] = REJECTED
-- The legacy 'synced' value is kept so historical rows remain valid.
--
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-06-12
-- Deployment verification: pg_get_constraintdef confirms products_whatsapp_catalog_sync_status_check
--   allows not_synced, pending, syncing, synced, under_review, customer_visible, rejected, removed, failed.

alter table public.products
  drop constraint if exists products_whatsapp_catalog_sync_status_check;

alter table public.products
  add constraint products_whatsapp_catalog_sync_status_check
  check (
    whatsapp_catalog_sync_status in (
      'not_synced',
      'pending',
      'syncing',
      'synced',
      'under_review',
      'customer_visible',
      'rejected',
      'removed',
      'failed'
    )
  );
