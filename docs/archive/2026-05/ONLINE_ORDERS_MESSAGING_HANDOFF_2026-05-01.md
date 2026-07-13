# Online Orders + Internal Messaging Handoff

Date: 2026-05-01

This handoff is for continuing the ERP-side refactor around Online Orders, the WhatsApp-backed support inbox, delivery coordination, online-sale notifications, and accounting/invoice confidence.

## User Intent

The original request was not just a small button fix. The desired product direction is:

- Online Orders should feel like a professional ERP operations surface, not an old table bolted to a store.
- Any WhatsApp/client-contact action in ERP must route through the app's own **Internal Messaging** / **Mensajeria interna** workflow, not directly through `WhatsAppService.sendMessage(...)` from operational pages.
- Staff should be able to review, personalize, and send buyer messages from the internal chat UI.
- Online order staff workflows should make delivery/pickup coordination obvious.
- The messaging module should become intuitive for both coworker chats and client conversations.
- Staff should receive clear ERP alerts/notifications when online sales happen, regardless of which module they are using.
- Online order invoice/accounting automation should be audited end-to-end and made trustworthy.

## Current Product Doctrine

Already documented in [.github/copilot-instructions.md](.github/copilot-instructions.md):

- The ERP customer communication platform is **Internal Messaging** or **WhatsApp-backed support inbox**.
- Spanish UI/context name: **Mensajeria interna**.
- `WhatsAppService` is transport only for WhatsApp Cloud API/manual fallback.
- Operational pages should open/create an internal support conversation and route staff to `/chat?conversation=<conversation_id>`.
- For online orders, context vocabulary is `context_type = 'order'`, not `online_order`.
- Use `MessagingService`, `ChatProvider`, `EmployeeChatPage`, and `ChatWindow` as the workflow surface.
- Direct transport sends are only appropriate inside the messaging workflow itself or explicitly approved automated notifications.

## What Is Already Implemented

### Public Store Checkout Cleanup

Files:

- [lib/public_store/pages/checkout_page.dart](lib/public_store/pages/checkout_page.dart)
- [lib/public_store/pages/order_confirmation_page.dart](lib/public_store/pages/order_confirmation_page.dart)
- [lib/modules/website/pages/online_orders_page.dart](lib/modules/website/pages/online_orders_page.dart)

Implemented state:

- Removed `Pago contra entrega` from payment methods.
- Added a proper fulfillment section in checkout:
  - `Despacho a domicilio`
  - `Retiro en tienda`
- `Retiro en tienda` now lives under delivery/fulfillment, not payment.
- Pickup orders write `delivery_type = pickup`.
- Shipping/address fields are hidden when pickup is selected.
- Pickup instructions are shown in checkout:
  - wait for ready confirmation
  - bring order number and buyer name
  - note if someone else will pick up
  - store pickup point comes from `website_settings.contact_address`
- Payment step now only shows real payment methods:
  - `MercadoPago`
  - `Transferencia bancaria`
- Order confirmation displays `Entrega` and labels pickup as `Punto de retiro`.
- ERP Online Orders detail/draft text now respects pickup vs delivery.

Validation already run after these changes:

```bash
flutter analyze --no-fatal-infos lib/public_store/pages/checkout_page.dart lib/public_store/pages/order_confirmation_page.dart lib/modules/website/pages/online_orders_page.dart
git diff --check -- lib/public_store/pages/checkout_page.dart lib/public_store/pages/order_confirmation_page.dart lib/modules/website/pages/online_orders_page.dart
flutter build web --release -t lib/main_store.dart -o build/web_check
flutter build web --release -t lib/main.dart -o build/web_erp_check
```

Observed bundle checks:

- Store `main.dart.js`: about `4.7M`.
- ERP `main.dart.js`: about `7.3M`.

### Customer Address Modal Cleanup

Files:

- [lib/public_store/pages/customer_addresses_page.dart](lib/public_store/pages/customer_addresses_page.dart)
- [lib/public_store/theme/public_store_theme.dart](lib/public_store/theme/public_store_theme.dart)

Implemented state:

- Saved-address modal can use Google Places autocomplete through existing `AddressAutocompleteService` and `google-places-proxy`.
- Manual address fields remain visible/editable.
- Google suggestion selection fills street, number, apartment if present, comuna, city, region, postal code.
- Added `Usar mis datos de cuenta` option:
  - uses logged-in customer `name` and `phone`
  - only enabled when both exist
  - fills and locks recipient name/phone while enabled
- Added `PublicStoreTheme.logoBlue = Color(0xFF093357)`.
- Address modal `Guardar` now uses logo blue; `Cancelar` uses theme muted text instead of default dialog colors.

Validation already run:

```bash
flutter analyze --no-fatal-infos lib/public_store/pages/customer_addresses_page.dart lib/public_store/theme/public_store_theme.dart
git diff --check -- lib/public_store/pages/customer_addresses_page.dart lib/public_store/theme/public_store_theme.dart
flutter build web --release -t lib/main_store.dart -o build/web_check
```

### Online Orders -> Internal Messaging Handoff

Files:

- [lib/modules/website/pages/online_orders_page.dart](lib/modules/website/pages/online_orders_page.dart)
- [lib/modules/messaging/services/messaging_service.dart](lib/modules/messaging/services/messaging_service.dart)
- [lib/modules/messaging/providers/chat_provider.dart](lib/modules/messaging/providers/chat_provider.dart)
- [lib/modules/messaging/widgets/chat_context_panel.dart](lib/modules/messaging/widgets/chat_context_panel.dart)
- [lib/modules/messaging/widgets/chat_window.dart](lib/modules/messaging/widgets/chat_window.dart)

Implemented state:

- Online Orders contact/coordination action opens an internal conversation through:

```dart
MessagingService().openWhatsAppSupportConversation(
  phoneNumber: phone,
  contactName: order.customerName,
  customerId: order.customerId,
  contextType: 'order',
  contextId: order.id,
)
```

- It then stages a reviewable draft with `ChatProvider.setConversationDraft(...)`.
- Staff are routed to `/chat?conversation=<conversation_id>`.
- Nothing is sent automatically at this handoff point.
- `ChatProvider` now supports `ConversationDraft` with title/subtitle/body.
- Support chat titles prefer `creatorName` / contact name before falling back to title or `Cliente`.
- `ChatContextPanel` supports `contextType == 'order'`:
  - loads order by ID
  - shows `PEDIDO WEB`
  - shows delivery type (`Retiro en tienda` vs `Despacho`)
  - shows order/invoice context
- Chat first-template UX is improved:
  - recognizes `last_first_contact_template_at`
  - falls back to recent outbound/template state where needed
  - hides/relabels the initial-template button after a template/outbound was sent and no client reply has arrived yet

### Messaging Service Context Fixes

File:

- [lib/modules/messaging/services/messaging_service.dart](lib/modules/messaging/services/messaging_service.dart)

Implemented state:

- `openWhatsAppSupportConversation(...)` resolves active WhatsApp channel, normalizes phone, calls `ensure_whatsapp_conversation_binding`, activates conversation, stores context on `conversations`, and adds current user as participant.
- Context normalization maps legacy/incorrect order aliases like `online_order`, `website_order`, `web_order` to `order`.
- Current user participant insertion avoids RLS/upsert gotchas by using insert with duplicate handling in the implementation.
- Conversation list loading injects WhatsApp binding contact names/phones so support threads can show customer name instead of bare phone.

### Continuation: Online Orders Command Center + ERP Alerts

Files:

- [lib/modules/website/pages/online_orders_page.dart](lib/modules/website/pages/online_orders_page.dart)
- [lib/shared/widgets/main_layout.dart](lib/shared/widgets/main_layout.dart)
- [lib/shared/routes/app_router.dart](lib/shared/routes/app_router.dart)
- [lib/shared/services/notification_service.dart](lib/shared/services/notification_service.dart)
- [lib/public_store/pages/order_confirmation_page.dart](lib/public_store/pages/order_confirmation_page.dart)

Implemented state:

- Online Orders now accepts `?order=<order_id>` and selects that order when opened from an ERP alert.
- App-shell online-sale alerts now route to `/website/orders?order=<order_id>`.
- New online sales increment a small Sitio Web badge in desktop/mobile navigation until staff opens Online Orders.
- App-shell order alerts now use durable `erp_notifications` and have a polling/resume fallback in addition to Supabase Realtime, so the badge/top alert catches up if the live insert event is missed.
- `Sitio Web` in the ERP sidebar is now an expandable module with:
  - `Dashboard`
  - `Editor`
  - `Órdenes / Notificaciones`
  - the unread online-order count visible on the collapsed module and the orders/notifications child row.
- Clicking the `Sitio Web` alert badge or the `Órdenes / Notificaciones` child row now opens the newest unread order route when one exists.
- Opening a specific order from a notification route marks only that order notification as read; opening the generic Online Orders inbox no longer clears every unread order alert.
- The order queue is now priority-sorted by operational attention instead of only newest-first.
- Added operational queue lanes:
  - Atención
  - Bloqueados
  - Preparar
  - Coordinar
  - Retiro
  - Despacho
  - Cerrados
  - Todos
- Summary strip now tracks new orders, paid orders, orders needing coordination, ready-for-pickup orders, and fulfillment blockers.
- Queue rows now show a concise next-action / blocker line.
- Detail action area is now a command block with one recommended primary action plus secondary actions.
- Fixed the info-card overflow caused by forcing the four detail cards into a fixed-height grid.
- Detail inspector now exposes real backend workflow actions:
  - confirm
  - prepare
  - mark ready for pickup
  - mark shipped with optional carrier/tracking details
  - mark delivered / picked up
  - cancel
  - open Mensajería with a staged draft
  - create/view invoice
- Legacy `cash_on_delivery` confirmation formatting no longer presents pickup as a payment method.

Validation run in this continuation:

```bash
git diff --check -- lib/modules/website/pages/online_orders_page.dart lib/shared/widgets/main_layout.dart lib/shared/routes/app_router.dart lib/shared/services/notification_service.dart lib/public_store/pages/order_confirmation_page.dart
rg "Pago contra entrega|contra entrega|cash_on_delivery" lib
rg "WhatsAppService\(\)|sendMessage\(|sendTemplate|sendReadyForPickup" lib/modules lib/shared
```

Follow-up validation:

- After a live test order (`WEB-TEST-260502033200`) created an unread `erp_notifications` row but the long-running desktop debug app did not show a badge, the app-shell fallback was added.
- Focused validation with `/Users/Claudio/flutter/bin/flutter analyze lib/shared/services/notification_service.dart lib/shared/widgets/main_layout.dart --no-fatal-warnings` passes with one existing warning: `_initWeb` is unused in `notification_service.dart`.

### Continuation: Messaging UX Clarity Pass

File:

- [lib/modules/messaging/pages/employee_chat_page.dart](lib/modules/messaging/pages/employee_chat_page.dart)

Implemented state:

- Desktop Mensajería sidebar is wider and now has a compact header explaining the split between team chats and WhatsApp/client conversations.
- Header metrics show team chats, active client conversations, and pending support requests.
- The client tab is labeled as `Clientes` instead of only `WhatsApp`.
- Customer inbox now has a `Bandeja de clientes WhatsApp` overview with order-context and unread counts.
- Support sections now use clearer labels:
  - Solicitudes pendientes
  - Conversaciones activas
  - Resueltas
- Conversations are sorted with unread threads first, then latest activity.
- Conversation subtitles now show business context and status in plain text, e.g. `Pedido web · Cliente WhatsApp`, instead of emoji-prefixed labels.
- Unknown non-pending/non-resolved support statuses stay visible in the active section instead of disappearing from the grouped list.
- Online Orders handoff drafts are now delivery-state aware:
  - pickup coordination
  - ready-for-pickup notice
  - shipping address/time-window coordination
  - shipped/tracking follow-up
- Draft title/subtitle now tell staff what they are about to send and reinforce that the message is reviewable/manual in Mensajería.

Validation run:

```bash
git diff --check -- lib/modules/messaging/pages/employee_chat_page.dart
```

### Database Migration Created

File:

- [supabase/migrations/20260501120000_promote_whatsapp_handoff_context.sql](supabase/migrations/20260501120000_promote_whatsapp_handoff_context.sql)

Purpose:

- Reused WhatsApp threads should not keep stale `invoice`/`job` context as primary when a new online order handoff happens.
- The migration replaces `public.ensure_whatsapp_conversation_binding(...)` so the latest handoff:
  - demotes old `conversation_contexts.is_primary`
  - inserts/upserts the current context as primary
  - updates active `conversations.context_type/context_id`
  - updates the conversation title to contact name when current title is blank/phone-like

Important deployment status:

- This migration file exists in the repo.
- Earlier production deployment attempt failed due DB connection issues.
- A specific live bad thread was manually corrected, but the global DB function still needs deployment verification in a fresh session.
- Before relying on production behavior, inspect whether the live `ensure_whatsapp_conversation_binding` matches this migration.

## Live Incident Context Already Investigated

The specific order that triggered the stale context bug was:

- Order number: `WEB-26-00012`
- Order ID: `233446cd-7f50-4209-90cb-c211e06ce252`
- Status: `confirmed`
- Payment status: `paid`
- Customer: `Claudio Catalan`
- Phone: `+56976431387`
- Linked sales invoice ID: `bcd8e79a-d1d3-450c-ad8c-1d50c9581e55`
- Invoice number: `INV-26-00010`
- Invoice status: `paid`

Conclusion from that incident:

- The invoice existed and was paid.
- `Factura no encontrada` was caused by stale chat context on a reused WhatsApp conversation, not missing accounting/invoice generation.

## Current Worktree Note

At the start of this handoff, `git status --short` showed only:

- modified Firebase hosting cache files under `.firebase/`
- one untracked screenshot under `Screenshots vinabikeProject/`

Those are likely generated/unrelated. Do not revert user/generator artifacts unless explicitly asked.

This handoff file itself is newly added.

## What Is Not Done Yet

The big ERP request is still not complete. Remaining work is substantial.

### 1. Online Orders Command Center UI

Current state:

- Some operational fixes exist.
- The full visual/workflow refactor is not done.

Recommended direction:

- Rebuild Online Orders as a dense operations workbench:
  - left queue/list with status chips and urgency
  - right detail panel with customer, delivery/pickup, payment, invoice, fulfillment, and messaging action surfaces
  - top summary strip: new, paid, awaiting coordination, ready for pickup, fulfillment blocked
  - explicit action lanes: confirm, prepare, coordinate, mark ready for pickup, mark shipped/delivered, cancel/refund if applicable
- Avoid marketing-page UI. This is ERP: compact, calm, scan-friendly.
- Keep actions tied to real state transitions.

Key file:

- [lib/modules/website/pages/online_orders_page.dart](lib/modules/website/pages/online_orders_page.dart)

### 2. Internal Messaging UX Refactor

Current state:

- Basic handoff works.
- The messaging module is still confusing as a broader UX surface.

Recommended direction:

- Separate/label conversation types clearly:
  - client support / WhatsApp-backed
  - coworker/internal
  - pending requests
  - active conversations
- Make current context obvious in the right panel:
  - order
  - invoice
  - job
  - customer
  - bike
- Make first-contact/template states self-explanatory:
  - no template sent
  - template sent, waiting for customer reply
  - inbound received, free-form messaging available
- Do not auto-send operational order text. Stage a draft and make staff send it.
- Keep `ChatWindow` as the sending surface.

Key files:

- [lib/modules/messaging/providers/chat_provider.dart](lib/modules/messaging/providers/chat_provider.dart)
- [lib/modules/messaging/services/messaging_service.dart](lib/modules/messaging/services/messaging_service.dart)
- [lib/modules/messaging/widgets/chat_window.dart](lib/modules/messaging/widgets/chat_window.dart)
- [lib/modules/messaging/widgets/chat_context_panel.dart](lib/modules/messaging/widgets/chat_context_panel.dart)
- likely [lib/modules/messaging/pages/employee_chat_page.dart](lib/modules/messaging/pages/employee_chat_page.dart)

### 3. Online Sale ERP Notifications

Implemented as a durable ERP signal.

Current behavior:

- When an online order is created through the existing app-shell realtime subscription, staff see a visible ERP signal even if they are in another module.
- The top notification routes to `/website/orders?order=<order_id>` and Online Orders selects that order on load.
- The desktop/mobile `Sitio Web` navigation item shows a small badge count until staff opens Online Orders.
- Notification state persists in `public.erp_notifications`, so unread online-order alerts survive refresh/login/device changes.
- A database trigger on `online_orders` writes `online_order_created` notifications.
- The app shell reads unread durable notifications, subscribes to `erp_notifications`, and marks online-order alerts read when staff opens Online Orders.

Files:

- [lib/shared/services/notification_service.dart](lib/shared/services/notification_service.dart)
- [lib/shared/widgets/main_layout.dart](lib/shared/widgets/main_layout.dart)
- [lib/shared/routes/app_router.dart](lib/shared/routes/app_router.dart)
- [lib/modules/website/pages/online_orders_page.dart](lib/modules/website/pages/online_orders_page.dart)
- [supabase/migrations/20260501200000_durable_erp_order_notifications.sql](supabase/migrations/20260501200000_durable_erp_order_notifications.sql)
- [supabase/sql/core_schema.sql](supabase/sql/core_schema.sql)

Deployment status:

- Migration SQL was applied to the linked Supabase project.
- Verified live table, trigger, function, and realtime publication exist.
- Supabase migration-history repair hit the CLI temp-role auth issue, so `20260501200000` was recorded directly in `supabase_migrations.schema_migrations`.

### 4. Accounting / Invoice Automation Audit

Live read-only audit continued on 2026-05-01.

Findings from Viñabike production, tenant `5443b130-cc28-45af-a420-cd500b288890`:

- In the last 180 days there are 69 online orders and 21 paid online orders.
- 7 paid online orders have linked invoices.
- 14 paid online orders are missing `sales_invoice_id`; these are older December 2025 test-looking orders with item name `test`, total `$100`, payment method `mercadopago`, and status `confirmed`.
- Paid orders that do have linked invoices showed healthy downstream accounting in the audit query:
  - payment row present
  - payment journal present
  - sales invoice journal present
  - expected stock movement present where a stock-tracked item required one
- `WEB-26-00012` remains healthy:
  - order payment status `paid`
  - linked invoice `bcd8e79a-d1d3-450c-ad8c-1d50c9581e55`
  - invoice status `paid`
  - payment row, sale journal, payment journal, and stock movement present

Code/schema issue found and fixed:

- Live `cancel_online_order(...)` still referenced removed `online_orders.invoice_id` even though production only has `sales_invoice_id`.
- Added [supabase/migrations/20260501180000_fix_online_order_cancel_reference.sql](supabase/migrations/20260501180000_fix_online_order_cancel_reference.sql).
- Mirrored the same function fix into [supabase/sql/core_schema.sql](supabase/sql/core_schema.sql).
- Also mirrored `sales_payments.deleted_at` into the canonical schema snapshot because production already has it and payment journal code depends on it.
- Applied the targeted migration directly with `supabase db query --linked -f ...`.
- Verified live `cancel_online_order(...)` no longer contains an exact old `invoice_id = null` assignment and now clears `sales_invoice_id = null`; live function config has `search_path=public`.
- Migration-history bookkeeping was repaired: `20260501180000` is now recorded as applied in `supabase_migrations.schema_migrations`.
- Added [supabase/migrations/20260501190000_online_order_recovery_invoice_dates.sql](supabase/migrations/20260501190000_online_order_recovery_invoice_dates.sql) and mirrored it into [supabase/sql/core_schema.sql](supabase/sql/core_schema.sql).
- `process_online_order(...)` now dates recovered paid invoices from `paid_at` / order creation instead of the day staff clicks `Crear factura`; invoice numbering year, due date, payment date, sales journal date, and stock movement date follow that invoice date.
- Migration-history bookkeeping was repaired: `20260501190000` is now recorded as applied in `supabase_migrations.schema_migrations`.
- Online Orders now warns staff before creating a missing invoice for a paid order older than 7 days, so old test/artifact orders are harder to process accidentally.

MercadoPago webhook hardening:

- Updated [supabase/functions/mercadopago-webhook/index.ts](supabase/functions/mercadopago-webhook/index.ts) so the webhook no longer blindly uses the first `mercadopago_access_token`.
- The webhook now loads configured tenant tokens, fetches MercadoPago resources through the matching token path, looks up the order by `external_reference`, and filters the `online_orders` update by both `id` and `tenant_id`.
- Deployed only `mercadopago-webhook` to project `xzdvtzdqjeyqxnkqprtf` with `--no-verify-jwt --use-api`.

Important caution:

- Do not auto-backfill the 14 old December 2025 paid test orders without a business/accounting decision. Calling `process_online_order(...)` now would create new accounting documents now for old payments unless a deliberate dated backfill is designed.
- The Online Orders UI can now surface these as paid-but-missing-invoice blockers, and staff can create/view invoices from the command panel. Decide whether those December test rows should be backfilled, cancelled, or left as test artifacts.

### 5. Deploy/Verify WhatsApp Context Migration

Function patch deployed to the linked Supabase project on 2026-05-01.

Verification performed:

1. `supabase migration list --linked` showed `20260501120000` was local-only before this continuation.
2. A live function fingerprint query showed the production `ensure_whatsapp_conversation_binding` did not demote old primary contexts, did not update `conversations.context_type/context_id`, and did not refresh phone-like titles.
3. Applied only [supabase/migrations/20260501120000_promote_whatsapp_handoff_context.sql](supabase/migrations/20260501120000_promote_whatsapp_handoff_context.sql) with `supabase db query --linked -f ...`.
4. Re-ran the live fingerprint query and confirmed all three expected behaviors are present.

Important caution:

- Do not run a broad `supabase db push` casually. The remote migration list shows many local migrations are not recorded remotely, so a broad push could attempt much more than this WhatsApp function patch.
- Migration-history bookkeeping was repaired after the direct SQL deploy: `20260501120000` is now recorded as applied in `supabase_migrations.schema_migrations`.
- A real reused-thread handoff should still be smoke-tested from the app UI when Flutter/browser validation is available:
  - old primary contexts are demoted
  - `context_type = order`
  - `context_id = <current order id>`
  - chat right panel shows `PEDIDO WEB`, not stale invoice/job.

## Suggested Next Session Plan

Best next chunk: **Legacy paid-order cleanup decision + UI smoke tests**.

Suggested order:

1. Re-read this handoff.
2. Re-read `.github/copilot-instructions.md`, especially:
   - Internal Messaging / WhatsApp-backed support inbox
   - GUI design rules
   - production incident inspection protocol
   - public store split build rules
3. Inspect current files:
   - [lib/modules/website/pages/online_orders_page.dart](lib/modules/website/pages/online_orders_page.dart)
   - [lib/modules/messaging/services/messaging_service.dart](lib/modules/messaging/services/messaging_service.dart)
   - [lib/modules/messaging/providers/chat_provider.dart](lib/modules/messaging/providers/chat_provider.dart)
   - [lib/modules/messaging/widgets/chat_window.dart](lib/modules/messaging/widgets/chat_window.dart)
   - [lib/modules/messaging/widgets/chat_context_panel.dart](lib/modules/messaging/widgets/chat_context_panel.dart)
   - [lib/modules/website/services/website_service.dart](lib/modules/website/services/website_service.dart)
4. Leave the 14 old December 2025 paid test orders untouched unless Claudio explicitly changes that decision.
5. Smoke-test a reused WhatsApp order handoff from the app UI once Flutter/browser validation is available.
6. Smoke-test Online Orders cancellation on a safe non-production/test order, because the live cancellation function was patched.
7. Verify durable `erp_notifications` badge/read behavior during the next browser pass.
8. Run focused analyzer and ERP build.

## Acceptance Checklist For The Next Phase

### Online Orders

- Staff can immediately see which orders need action.
- Pickup vs delivery is obvious.
- Payment and invoice state are obvious.
- The messaging action opens Internal Messaging and stages a draft, never direct-sends.
- Detail panel shows all buyer/order context needed for staff to act.
- No old `Pago contra entrega` wording returns.

### Messaging

- Client conversations are visually distinct from coworker/internal chats.
- Conversation title uses customer/contact name where available.
- Right context panel shows the active workflow context, not stale context.
- First-contact template state is clear and not repeated after send.
- Drafted order message is visible, editable, and explicitly staff-sent.

### Notifications

- New online order creates a visible ERP signal.
- Signal links to the relevant order.
- Staff do not need to be in the website module to notice it.

### Accounting/Invoice Confidence

- For paid MercadoPago order: order, payment, invoice, journal entry, and stock movements are traceable.
- Messaging context panel does not say invoice missing when the order has a linked invoice.
- Online Orders page surfaces invoice status accurately.

## Useful Commands

Focused Dart validation:

```bash
flutter analyze --no-fatal-infos lib/modules/website/pages/online_orders_page.dart lib/modules/messaging/services/messaging_service.dart lib/modules/messaging/providers/chat_provider.dart lib/modules/messaging/widgets/chat_window.dart lib/modules/messaging/widgets/chat_context_panel.dart
```

ERP build after ERP/messaging changes:

```bash
flutter build web --release -t lib/main.dart -o build/web_erp_check
ls -lh build/web_erp_check/main.dart.js
```

Store build after public-store changes:

```bash
flutter build web --release -t lib/main_store.dart -o build/web_check
ls -lh build/web_check/main.dart.js
```

Search for forbidden direct operational WhatsApp sends:

```bash
rg "WhatsAppService\(\)|sendMessage\(|sendTemplate|sendReadyForPickup" lib/modules lib/shared
```

Search for old delivery/payment wording:

```bash
rg "Pago contra entrega|contra entrega|cash_on_delivery" lib
```
