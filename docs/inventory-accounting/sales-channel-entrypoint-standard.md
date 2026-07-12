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
- Manual bank-transfer confirmation requires a reference and effective date, locks the order and invoice, posts one whole-CLP payment, and links the order action to the invoice/payment child operations.
- Concurrent or repeated manual confirmation returns the original payment; invoices with partial payments are routed to the invoice payment workspace.

## Production certification snapshot

Before/after deployment: inventory `1244/1244`, stock `1244/1244`, movements `2471`, journals `2129`, active sales payments `728`, online orders/items `72/72`, legacy orders/items `0/0`. Two POS drafts were created by live activity during the window; the migration itself created no business row.

Local verification includes 29 manual-payment assertions, a real two-session race, the complete 583-assertion database suite, 180 Flutter tests, and analysis with no errors. Migrations `20260711123000_harden_sales_channel_entrypoints.sql`, `20260712123000_preserve_online_order_cancellation_evidence.sql`, and `20260712133000_harden_online_manual_payment_confirmation.sql` are deployed.

## Open work

1. Review historical paid orders without invoice links and POS retry candidates manually; never infer or repair them automatically.
