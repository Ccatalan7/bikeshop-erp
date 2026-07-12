# Sales Channel Entrypoint Standard

Deployed 2026-07-11. Preventive only; no historical business row was corrected.

## Ownership

- POS, Quick Sale, and ecommerce may create a sales invoice, but the invoice is the only stock/revenue/COGS owner.
- Payments change settlement and payment journals only; they never own stock.
- Legacy `orders/order_items` is closed because it bypassed the movement ledger and had zero production rows.

## Online controls

- A stable checkout key returns the original order on replay and rejects different content under the same key.
- Product names, prices, totals, tax, and MercadoPago preference items come from database state.
- Provider events require the matching tenant/order, exact rounded amount, and `CLP` currency.
- Replayed events do not recreate invoices, payments, movements, or journals.
- A second distinct approved provider payment is recorded as a conflict instead of reposting.
- Provider evidence is append-only and links order -> invoice -> inventory/accounting operation.

## Production certification snapshot

Before/after deployment: inventory `1244/1244`, stock `1244/1244`, movements `2471`, journals `2129`, active sales payments `728`, online orders/items `72/72`, legacy orders/items `0/0`. Two POS drafts were created by live activity during the window; the migration itself created no business row.

Local verification: 24 pgTAP assertions, Dart analysis, and Deno type checks passed. Migration `20260711123000_harden_sales_channel_entrypoints.sql` and all three MercadoPago functions are deployed. The storefront bundle was deployed and verified to contain `checkout_idempotency_key`.

## Open work

1. Make POS and Quick Sale invoice + split-payment checkout one atomic idempotent database command.
2. Replace online hard deletion/cancellation with preserved document status, soft payment reversal, and linked reversal evidence.
3. Review the 14 historical paid orders without invoice links and four POS retry candidates manually; never infer or repair them automatically.
