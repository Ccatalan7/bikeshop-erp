# Canonical UI Surface Registry

Website Builder work must also follow the mandatory parity, selection,
clipping, routing, media, and save contract in
[`website-editor-contract.md`](website-editor-contract.md).

**Purpose:** prevent business actions from being implemented on an unrouted,
obsolete, or partial UI while the screen employees actually use remains
unchanged.

## Required Rule

A business workflow is not UI-complete until the same shared action is present
on every registered surface where the underlying document can be operated.
Routes, list previews, embedded editors, side panels, quick actions, and mobile
layouts are separate surfaces even when they display the same record.

- Put business behavior in a shared service/widget; surfaces only compose it.
- Do not retain competing `*_old.dart` or unrouted detail/list pages. Git history
  is the archive.
- Before editing UI, trace the real route in `app_router.dart`, its barrel
  export, and every constructor reference with `rg`.
- After editing, verify the employee's normal click path, not only a direct URL
  or isolated widget test.
- Critical workflows require an architecture test that asserts every registered
  surface consumes the shared action and obsolete competitors stay absent.

## Global Workspace Surfaces

| Surface | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Right toolbar shell | Every desktop workspace, in over-content and reserved-width appearance modes | `_WorkspaceRouterView` in `main.dart` hosting `RightToolbar` | The toolbar occupies the full workspace height and its collapsed or expanded rail starts at the top edge immediately below the workspace tab bar. Reserved-width mode must stretch the hosting row vertically rather than centering the rail at its intrinsic icon height; long tool lists scroll inside the anchored rail. |

## Current Invoice Surfaces

| Document | User entry point | Canonical implementation | Required shared workflow |
|---|---|---|---|
| Sales invoice list/preview | `/sales/invoices` | `invoice_list_page.dart` (`_buildInvoicePreview` / `_buildActionBar`) | `SalesCorrectionsMenu` |
| Sales invoice full page | `/sales/invoices/:id`, `/sales/invoices/:id/edit` | `invoice_form_page.dart` | `SalesCorrectionsMenu` |
| Sales invoice embedded editor | Workshop/calendar/side-panel embeddings | `sales_invoice_editor.dart` | `SalesCorrectionsMenu` |
| Sales invoice payment | `/sales/invoices/:id/payment` and preview payment terminal | `invoice_payment_page.dart` / `PaymentForm` | Atomic sales payment command |
| Purchase invoice list | `/purchases` | `purchase_invoice_list_page.dart` | Navigation to canonical form/workflows |
| Purchase invoice full page | `/purchases/:id`, `/purchases/:id/detail`, `/purchases/:id/edit` | `purchase_invoice_form_page.dart` | Receiving plus visible receipt history/reversal, supplier return, purchase credit note |

`SalesCorrectionsMenu` applies Viñabike's operating policy consistently:

- `sent`: no correction;
- `confirmed` / `overdue`: financial credit note only;
- `paid`: financial credit note and physical customer return.

Sales invoice confirmation on the list preview, full page, and embedded editor
uses `SalesService.previewNegativeStock`: staff posting is never blocked by a
negative projection, while a compact amber message identifies the affected
products and the database preserves the normal movement/accounting trace.

### Workshop, invoice, and payment contract

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Approved standalone quotation | Approved `Cotización` chip in `/taller/pegas` | `pegas_table_page.dart` + `MechanicJobQuotationCommandCoordinator` + `convert_mechanic_job_to_billable` | The compact menu always keeps PDF download. Conversion offers `Venta`, `Bicicleta`, and `Componente`; `Venta` is enabled only when every line is a catalog product. Sale conversion preserves the same job and approval history, persists `workflow_kind=sale` / `intake_kind=none`, creates exactly one linked invoice atomically, and never creates physical intake or a parallel inventory/tax/accounting owner. |
| Workshop job create/edit | `/taller/pegas/nueva`, `/taller/pegas/:id`, embedded client-logbook job pane | `mechanic_job_form_page.dart` | Stable diff/upsert of job bikes and items; structured diagnosis and task parents survive ordinary saves; legacy duration/work-summary/technician-note/approval fields remain compatible in persistence but are not competing intake controls. General owns only mode/document choice, reception priority/dates, the customer's request, proposal validity, and warranty source; diagnosis owns technical findings and Products and Services owns planned work. Its shared catalog autocomplete may use a bounded mixed-catalog preview for initial speed, but an exclusive `Productos` or `Servicios` filter is sent to the database search and must not be evaluated only against that preview. Operational status, proposal decisions and warranty coverage are displayed read-only in the form and changed only from the visibly interactive State chip in the canonical table. Workflow (`service`/`quotation`/`warranty`/`sale`) and physical intake (`bike`/`component`/`none`/`unspecified`) stay orthogonal behind five familiar creation choices. `Servicio` defaults only for new rows to `Presupuestar primero`: it receives and preserves the bicycle/ficha/diagnosis but creates no invoice or financial effect; `Facturar ahora` preserves the established immediate-invoice path. The standalone no-object choice is `Cotización`. Existing rows hydrate from their canonical axes, so historical billable services never change behavior. `Venta / cobro` requires a customer and catalog product, receives no physical object, hides diagnosis/mechanical scheduling and creates the normal invoice after its lines are saved; its optional agreement text is operational notes only and the linked invoice remains the sole source of stock, tax, receivable, balance and payments. A creation-mode change that removes bicycle context requires confirmation, preserves commercial lines in General, and copies nonempty standalone narrative into the first bicycle without overwriting bicycle-specific text; changing an unsaved warranty source with source-scoped draft data also requires confirmation and preserves its lines before replacing the physical diagnosis context. Saved mode/intake changes use audited table actions instead of the form selector. Proposals with a persisted approval/rejection/expiry decision are read-only, while a still-pending proposal may extend its validity and a converted proposal becomes a normally editable service whose accepted commercial snapshot remains immutable in the event ledger; decisions/conversion use the audited commands and proposals never own invoices. Tax is a read-only invoice mirror; warranty work links to its original delivered job and audited decision command; any persisted job with active-payment evidence on its linked invoice, or an unreadable linked-payment state, keeps allowed operational notes editable but locks the physical object, products, discount, totals and mutable job-to-invoice projection; changing the customer on an unsaved job clears every customer-scoped bike, component, warranty source, outcome, and reason; an unpaid linked invoice exposes the shared routed payment action and a paid invoice does not |
| Workshop list actions | `/taller/pegas` table/list/calendar hosts | `pegas_table_page.dart` + `pegas_calendar_widget.dart` + `pega_detail_view.dart` + `get_mechanic_job_time_metrics` + client-logbook list + workshop mode coordinators | Canonical job form in one familiar table; existing columns render the workflow/intake distinction without a new permanent column. The table `Flujo` column and every host of `PegaDetailView` consume the same tenant-scoped lifecycle projection: first credible start/completion plus first immutable delivery, with source and quality flags. Historical bitácora evidence may be reconstructed at read time but never written back as if it were an original timestamp; terminal jobs with missing evidence render `Sin dato`, not a duration from reception, and a reopened job keeps its first delivery visible. Diagnostic time is not inferred from `diagnosis_added` because adding findings is not proof that a diagnostic was sent. The existing State chip is the primary lifecycle/action control and must render a dropdown affordance plus hover label, rather than hiding state decisions only in row overflow. A bike-backed quotation workflow renders as `Servicio · Presupuesto`, keeps its real bicycle/count/calendar capacity, downloads a PRESUPUESTO PDF and converts directly with the persisted object. In the table's existing `Factura` column, pressing an approved `Presupuesto` chip opens the compact choices `Descargar presupuesto` and `Facturar presupuesto`; the latter delegates to the same confirmed, idempotent conversion command and never creates a parallel invoice path. Pending, rejected or expired proposals cannot expose this billing shortcut, and the server refuses approval until at least one product/service line exists. New proposal-status feedback replaces any older snackbar instead of queueing it across routes; reopening as pending, starting conversion, or opening the linked invoice removes obsolete proposal feedback before navigation. A standalone quotation renders as `Cotización · Sin objeto recibido`, is excluded from bicycle counts/mechanical capacity, downloads a COTIZACIÓN PDF and keeps the explicit intake picker on conversion. Both use the shared status/conversion commands and are excluded from total/paid/receivable figures while appearing separately as `Presupuestado` and `Cotizado`. `sale/none` renders as `Venta / cobro · Sin objeto recibido`, uses the existing total/invoice payment progress, remains active while the invoice has balance, leaves Activos when fully paid, and is excluded from bicycle/component/warranty counts and mechanical calendar/Gantt. A flagged `REVISAR MODO` row opens the same compact classification action from its chip or overflow menu, offering bicycle, component, or product sale and calling the corresponding idempotent audited command; each coordinator owns one stable operation key per attempt, reuses it for readback/replay after a lost ACK and keeps an explicit uncertain outcome instead of reporting a false rollback; removing an active job uses soft delete and preserves its invoice/accounting evidence |
| Strategic dashboard deck | `/` and `/dashboard` | `dashboard_screen.dart` + `strategic_dashboard_deck.dart` + `get_strategic_dashboard_metrics` | The existing accounting charts remain the first layer. Arrow navigation and one restrained position indicator expose separate workshop-flow, capacity/service, and product/rotation layers without a grid of disconnected KPI tiles. Every duration, ratio and margin names its denominator and exposes sample or coverage. Workshop services, products and ambiguous lines are separated at invoice-line level; an unknown line remains visibly `Sin clasificar` and is never silently assigned to products. Classification coverage is shown beside the mix. Service contribution subtracts backed mechanic payroll (or a disclosed attendance-rate estimate) and never claims to be net business profit. Capacity keeps business open clock-hours, mechanic attendance person-hours and explicit job labor hours distinct. Product margin uses historical line cost only where present; stock coverage is not mislabeled as accounting turnover. Period changes use one shared compact menu with current month, previous month, rolling 30/90-day and 12-month windows, plus a calendar-backed custom range; every selection feeds the same tenant-scoped read model in the store's `America/Santiago` time zone. |
| Linked invoice edit | Job invoice action, routed invoice page, invoice list preview, embedded editor | `invoice_form_page.dart` / `sales_invoice_editor.dart` / list preview | New invoice creation with a job context delegates atomically to `create_billable_invoice_from_mechanic_job`; neither routed nor embedded surfaces may insert a generic invoice and then link the job best-effort, and command failure must never produce success feedback. `mechanic_jobs.invoice_id` is the single enforced relationship: the job opens that invoice directly and invoice surfaces resolve their job through the reverse lookup, without a second writable pointer. Existing linked invoices use one database-owned bidirectional line sync with stable `mechanic_job_items.id`; an omitted/blank/JSON-null invoice `job_bike_id` preserves the existing physical attribution for that same stable item, while an explicit value must resolve inside the same job/tenant; a failed invoice read renders an explicit retry state, never an empty saveable invoice |
| Invoice payment and tax choice | Routed payment page and every preview/dialog that composes `PaymentForm` | `invoice_payment_page.dart` + `PaymentForm` + `SalesService.registerPaymentWithInvoiceTax` | One idempotent database transaction posts the invoice when needed, classifies the whole invoice as IVA-included/no-tax, then records settlement; job/payment rows mirror that classification; a fully paid direct route renders a closed summary, not a zero-value form |

Every employee status control in the table, legacy list and calendar delegates
to `BikeshopService.transitionJobStatus` and
`MechanicJobStatusTransitionCoordinator`. The server command
`transition_mechanic_job_status` owns the legacy `status` mirror, lifecycle
timestamps, invoice-before-job locking and the append-only exact-key receipt.
Routed and embedded forms show lifecycle state as context only and direct staff
to the table's State chip. An ordinary form update omits `status`, `status_id`, `started_at`,
`completed_at` and `delivered_at`. Public-store customer history remains
read-only; the obsolete direct approve/reject status writers are removed rather
than bypassing the employee tenant contract.

The payment terminal is the only interactive sales-tax owner. Invoice editors
show the persisted net/IVA breakdown, but do not infer or change tax from the
payment method. Workshop editors never write invoice tax. The invoice remains
the owner of revenue, IVA, receivable, inventory and COGS; payment journals only
settle receivable, and the workshop job only mirrors total/tax/paid state.
The job's `Registrar pago` action must route to
`/sales/invoices/:id/payment`; it must not embed a second payment/tax form.
Accounting navigation and labels may show the invoice number, but persistence
and journal ownership use the invoice/payment UUID, never that visible number.
On web, `WorkspaceManager` and the active workspace router consume the captured
deep link. Flutter's temporary root-Navigator fallback for that already-owned
URL is explicitly suppressed as non-fatal log noise; the routed destination
must still load and be verified through the employee URL.

Delivery and service warranty use a different clock from the mutable current
status mirror. `mechanic_job_delivery_events` records the server timestamp and
actor on the first delivered transition; reopening clears the legacy
`mechanic_jobs.delivered_at` current-state field but never deletes that event.
The first delivery freezes the default 14-day window. Re-delivery does not
silently reset it, while an explicit extension requires a reason and appends a
new event. Table, calendar, routed form, and embedded form consume
`mechanic_job_service_warranty_view` / `mechanic_job_warranty_claims_view`.

Covered warranty parts are represented by a zero-customer-value internal linked
sales invoice. That invoice remains the only stock/accounting owner: posting
debits `5115 Garantías de Servicio Técnico` and credits inventory at catalog
cost, with no revenue, IVA, receivable, or payment. Reopening/rejecting coverage
uses the same invoice-owned reversal path before returning to the billable draft
flow. The table labels this artifact `Respaldo interno`, never as a customer
invoice.

Proposal workflows are planning documents, not invoices. A bike-backed service
budget uses a PRESUPUESTO PDF and keeps its received bicycle/ficha/diagnosis;
a standalone no-object inquiry uses a COTIZACIÓN PDF. Both may carry proposed
`mechanic_job_items`, but cannot link a `sales_invoices` row or own inventory/
accounting effects. Approval is audited. Service-budget conversion reuses the
persisted bicycle; standalone conversion to `service` or `item_service`
validates the selected received object, while a catalog-product-only standalone
quotation may convert to `sale/none` with no received object. Every outcome
creates the billable draft invoice atomically. A late approval
after `quotation_valid_until` requires an explicit audited reason and remains a
valid conversion receipt. A conservatively detached legacy quote draft is kept
as a cancelled document, never an actionable orphan. The same
`mechanic_job_mode_view` / `mechanic_job_mode_events` contract must be consumed
by the routed form, embedded form, table, list, calendar and quick actions.

The release migrations intentionally keep operational risk bounded. Migration
`20260716030000` defines its function bodies before requesting a short
`ACCESS EXCLUSIVE NOWAIT` DDL window; contention aborts instead of queueing
behind or blocking workshop traffic. The only quotation data repair lives in
`20260716035000`, uses a read-friendly `SHARE ROW EXCLUSIVE NOWAIT` lock and an
exact one-row fingerprint, writes immutable evidence, and never replays invoice,
payment, stock, or journal effects. `20260716040000` owns the audited manual
classification command. `20260716050000` connects online manual-payment child
traces by their exact deterministic operation keys rather than wall-clock
timestamps and aborts if a required completed child is missing.
`20260716060000` preserves stable per-bicycle workshop attribution during
invoice sync and is a function-only change with no backfill.
`20260716070000` appends canonical intake/review fields to the warranty-source
view and makes claim registration replace stale form state with the exact
original bicycle or loose component. It also aligns direct job sync and the
existing-invoice retry with the payment kernel's invoice-to-job lock order.
Payment first locks invoice then job and rejects a stale commercial snapshot.
After settlement, job/invoice commercial rows, payment, stock and journal rows
are exact no-ops. It is a function/view/trigger-only install with no backfill or
install-time financial posting.
`20260716080000` adds the canonical replay-safe job-status command and immutable
receipt ledger. It derives the active tenant status and database-clock
timestamps, follows invoice-before-job lock order and rejects covered-warranty
status effects when payment evidence exists. Its installation creates only
schema/functions/triggers and performs no business backfill.
`20260716090000` completes the ordinary service/component invoice trace root
created by a nested status effect before restoring the parent trace context.
Covered warranties retain that root until their explicit invoice-owned
stock/cost writer completes it. It replaces trigger logic only and performs no
historical backfill.

Release state (2026-07-16): migrations `20260716010000` through
`20260716060000` in this workshop-mode sequence are deployed, registered and
read back in production. The surgical normalization changed exactly PG-00468,
left PG-00455 untouched and produced no payment, stock or journal effects. Two
fresh canonical database rebuilds each passed 52 pgTAP files/1.210 assertions,
and the post-write production health check has zero critical failures. The
matching client surfaces remain pending publication and employee-path smoke;
the active database contract remains backwards compatible with the prior
client during that rollout. Migrations `20260716070000`, `20260716080000` and
`20260716090000` remain locally gated release candidates until the final
repeatable database, Flutter and browser gates complete and the coordinated
database-before-client rollout is verified.

## Bicycle And Technical-Profile Surfaces

Status (2026-07-16): the aggregate database contract is implemented, locally
verified, deployed and registered in production through migration
`20260714120000`. Production RPC/ACL/RLS readback and a browser canary confirmed
the atomic bike/profile/events/receipt graph. Client changes must continue to
use this already-active command; do not restore paired `bikes` then
`bike_profiles` writes.

`BikeFormDialog` is the one full bicycle identity/intake/technical-profile
editor. It consumes `BikeshopService.getBikeAggregate` and
`saveBikeAggregate`; host surfaces must not recreate a local `bikes` then
`bike_profiles` write sequence. Existing-bike editors treat aggregate load
failure as an error with retry, never as an authoritative empty profile.
An uncertain save response blocks edits and dismissal and reuses the same
command while the dialog remains alive; crash-safe local outbox recovery is a
documented follow-up, not a property of the current client.

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Job bicycle create/edit | `/taller/pegas/nueva`, `/taller/pegas/:id`, and the client-logbook embedded Jobs pane | `mechanic_job_form_page.dart` hosting `BikeFormDialog` | Atomic bicycle aggregate save; returned bike selected only after commit/replay; failed profile reads stay explicit. A routed new-job handoff carrying `customer_id` plus `bike_id` must hydrate that customer and select the exact active, customer-owned bicycle instead of silently discarding the bicycle context. |
| Customer bicycle create/edit | Client logbook Bikes tab, desktop embedded pane, and mobile modal | `client_logbook_page.dart` hosting `BikeFormDialog` | Same aggregate command and load-state contract across embedded/modal variants |
| Quick bicycle finder | Right-toolbar bicycle finder | `QuickBikeFinderPanel` + `bike_finder_search.dart`, routing to the client logbook `BikeRecordPanel`, mechanic-job form, and full bicycle directory | This is a bounded search/navigation read surface, not another editor. Default to recent active bicycles; tokenize the query with AND semantics across bicycle, customer, telephone, serial, QR and descriptive fields, so each word may resolve through a different related record; normalize accents and punctuation and tolerate one small alphabetic typo without fuzzing numeric identifiers. Expose one scope dropdown for workshop, warranty, history, archive, or all; mark archived bicycles explicitly and never offer new work for them. The row opens the canonical bicycle record, its visible workshop action opens the newest active job or creates a new job with customer and bicycle preselected, and customer access remains secondary. |
| Jobs-table bicycle profile | `/taller/pegas` single-bike and per-bike row actions | `pegas_table_page.dart` hosting `BikeFormDialog` | Open the canonical aggregate editor; no competing quick profile writer |
| Calendar base identity editor | `/taller/calendario` and calendar mode embedded in Jobs | `pegas_calendar_widget.dart` | Base-only edits must preserve `bike_profiles`; full technical edits route to `BikeFormDialog` |
| Debug workshop fixture | Debug-only `Prueba rápida` launcher | `pegas_table_page.dart` fixture helpers | Use `saveBikeAggregate` for repeatable profile/backbone validation; never retain the old paired-write path or expose a production-visible competing editor |

The database command owns tenant checks, optimistic versions, idempotent
replay, `bikes` + optional `bike_profiles`, and their save events in one
transaction. `bike_aggregate_save_operations` is command/audit evidence only;
technical truth remains exclusively in `bikes` and `bike_profiles`.

## Expense Capture Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Quick expense OCR | Right-toolbar `Gastos` panel; image/PDF picker, whole-panel drop target, and file-library OCR handoff | `QuickAccessExpenseRail` + `QuickExpenseReceiptParser` + shared PDF/Veryfi extraction | Every supported entry point feeds the same parser and editable quick-expense form. The toolbar surface uses one compact expense pulse, an open Capture / Data / Classification / Support sequence, a single dropdown for reusable templates, responsive paired fields, bounded recent activity, and a fixed total-and-register footer; exceptional purchase-invoice linkage stays collapsed until explicitly enabled. Payment receipts remain receipts rather than tax invoices. NIC Chile WebPay confirmations infer NIC only from the domain-restoration signature, extract the payment identifier, amount, authorization, debit/credit hint and purchase detail, and resolve the partial `MM / DD` transaction date against a dated filename before the current year fallback. Domain restoration selects ledger account `6207-01 · Dominios y Hosting` and operational category `Servicios Digitales`; the database owns the same account-to-category fallback so an older client cannot leave the stored expense uncategorized. Registration keeps the `GTO` sequence above both live expenses and preserved expense journals, while accounting trace matching uses the immutable expense UUID so a legacy orphan journal cannot block a new expense. Every OCR value remains reviewable before the user explicitly registers the expense. |

## Messaging Inbox Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Routed employee inbox | `/chat` desktop split, compact, and mobile layouts | `EmployeeChatPage` + `ChatProvider` + shared `ConversationTile` | Conversation previews and unread state load independently from derived job, bicycle, invoice, and supplier context. A context refresh remains server-authoritative, preserves the last tenant-and-user-scoped known hint while in flight, coalesces concurrent callers, and notifies only when the rendered context actually changes. |
| Right-toolbar customer messages | Right-toolbar `Mensajería` | `QuickMessagesPanel` + `ChatProvider` + shared `ConversationTile` | Opening the panel refreshes only contextual hints after the fast inbox pass instead of repeating the complete inbox read. A manual reload waits for both the inbox and its context. Last-known chips render immediately after restart when cached, then genuine label, status, color, bicycle, or document changes use one short fade-and-rise transition without decorative motion. |
| Right-toolbar supplier messages | Right-toolbar supplier messaging tool | `QuickSupplierMessagesPanel` + `ChatProvider` + shared `ConversationTile` | Uses the same scoped cache, authoritative context-only refresh, awaited reload, and restrained chip transition as the customer panel; it must not fork conversation or context state. |

## Operational Briefing Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Daily operational briefing | Right-toolbar bell and the slide-in notifications entry point | `NotificationsToolbarPanel` / `showNotificationsPanel`, both composing `_NotificationBriefing` in `notifications_panel.dart` | Default to the local calendar day with an explicit seven-day comparison; use an open, minimally framed composition with an animated hourly/daily activity pulse, one lightweight metric ribbon and a color-coded timeline; expose one compact icon dropdown for quickly filtering that timeline by jobs, payments, email, chat, orders, files or other alerts without replacing the mixed default; summarize workshop jobs, payments, online orders and stored files; surface unread mail and chat as attention items; show a bounded cross-module activity list rather than an unbounded inbox; route every summary and activity item through `WorkspaceManager` |
| Notification attention badge | Collapsed right-toolbar bell | `NotificationService.unreadNotificationsCount` consumed by `RightToolbar` | Count unread ERP alerts from the current local business day only, so historical unread rows cannot create a permanent `99+` badge; older activity remains visible in the seven-day briefing and is not deleted |

`NotificationService.notificationsFeed`, `MailAccountManager`, `ChatProvider`
and `AppFileStorageService` remain the owners of their respective data. The
briefing composes their read models and routes into the canonical modules; it
does not create parallel email, chat, file or business-event persistence.

## File Library Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| File library | Sidebar `Archivos`, `/storage`, and right-toolbar `Archivos` | `AppFilesPanel` backed by `AppFileStorageService` | Shared tenant-scoped search, smart folders, upload/drop, origin metadata, download, delete, OCR, and module handoffs; the right-toolbar list is compact but must not fork file actions or persistence |
| Docked file runner | Right-toolbar `Ejecutar archivos` | `AppFilesPanel(runnerMode: true)`, `_InlineStorageFileRunner`, and `StoredSpreadsheetRunner` | Opens beside the active module rather than replacing it; image/PDF/text previews stay inline; PDF exposes zoom/print/download/reload controls; text files save through `replaceFileBytes`; images use the shared crop-and-replace flow; XLSX/CSV decode into the packaged Univer engine inside the panel and encode back through `replaceFileBytes` with guarded pending/error states; the separate Planillas handoff remains an optional full-workspace action; unsupported binary formats remain downloadable and must not claim an editable preview |

## Email Workspace Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Unified inbox desktop | `/mail`, desktop content width at or above the mail split breakpoint | `mail_inbox_page.dart` desktop split hosting `EmailListItemUnified` and `EmailDetailViewUnified` | Visible account and unread/attachment filters; selected-message provider must match the active account filter; resizable persisted list width; fixed-height count/load-more status row; move-to-trash confirmation |
| Unified inbox compact/mobile | `/mail`, compact desktop/web and mobile layouts | `mail_inbox_page.dart` list/detail stack hosting the same list and detail widgets | Same account/filter and fixed-height status-row contract; one focused list or detail surface at a time; explicit Back action from detail |
| Compose and reply | Inbox `Redactar`, message `Responder`, and `Responder a todos` actions | `compose_email_dialog.dart` | New mail defaults to the active account; replies default to the message provider; recipient validation, CC/CCO, required subject/body, and draft-discard protection |
| Message body and attachments | Selected message on routed desktop, compact, and mobile layouts | `email_detail_view_unified.dart` | Shared sender/actions/attachments; fit-safe HTML on web and native WebView; existing anchors and bare HTTP(S) URLs are visibly clickable and open only in the ERP browser workspace; compatible `.xlsx`/`.csv` attachment bytes open through the canonical Planillas handoff without a download round trip; destructive actions remain outside the renderer |

`MailAccountManager` is the shared owner of connected-provider state, merged
messages, selection, account filtering, read state, search, send, and trash
commands. Host layouts must not retain a selected message from an account that
the active provider filter excludes, and reply surfaces must never silently
fall back to the first connected account.

## Embedded Browser Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Browser workspace | Workspace-tab `+ > Navegador web`, `/tools/web`, email HTTP(S) links, supplier portals, and web-tool handoffs | `WebViewModulePage` + `BrowserProfileService` + supplier portal catalog + supplier portal credential resolver + `BrowserCredentialVault` + `WorkspaceManager` browser-session contract | HTTP(S) content remains inside the ERP workspace unless the embedded engine refuses it or the user explicitly chooses the external fallback. Every ERP user owns a separate app-history, bookmark, permission and restored-tab record. The omnibox combines a shared `catálogo corporativo` built from the name and website of every active supplier with durable per-user domain memory (`memoria de dominios`): supplier prefixes are therefore available on `cualquier equipo` immediately after loading ERP data, while local visits improve ranking and preserve the best last route without synchronizing personal browsing activity. Both sources refresh whenever a browser tab focuses the address field, rank before remote search suggestions, and provide Chrome-style `autocompletado inline` by selecting only the untyped host suffix. Accepting that completion opens the locally visited `última ruta útil` when one exists, otherwise the centrally configured supplier URL; query strings, fragments, URL user-info and all supplier credentials are excluded from the suggestion catalog. A later root visit cannot replace a previously useful path, preserving authenticated supplier landing pages whose public root still displays a login form. Native engine cookies/cache/local storage persist across ordinary app restarts and are shared by tabs on the same device; explicit ERP sign-out clears website-owned state, while supplier credentials and saved local credentials remain isolated to that ERP user so an expired supplier session can recover automatically. Windows tabs share one writable WebView2 user-data folder/environment. The app records each tab's actual last URL/title without replacing its live router, restores tabs lazily, opens `target=_blank` in a fresh internal workspace, uses the installed engine's real user agent, and never grants camera/microphone/location or other protected resources without a visible per-site decision. |
| Supplier portal credentials | `/purchases/suppliers/:id/edit`, supplier summary, corporate omnibox suggestions, and automatic login in any ERP browser tab | `SupplierFormPage` + `PurchaseService` + supplier portal catalog + supplier portal credential resolver | `website` identifies both the centrally suggested portal URL and the exact host eligible for login; `portal_username` / `portal_password` provide its automatic login but never enter the suggestion model. The password is obscured by default in both edit and summary presentations while retaining explicit reveal/copy controls. Saving the supplier refreshes the shared supplier cache consumed by the browser; no browser-specific duplicate record is required. |

The embedded browser is not Google Chrome and must not claim Chrome Sync,
Chrome's password vault, or cross-platform Chrome-extension compatibility.
For a domain registered in an active supplier record, the supplier's `website`,
`portal_username`, and `portal_password` are the primary login source. Matching
is limited to the exact host with only `www.` treated as an equivalent alias;
arbitrary sibling subdomains never receive the credential, and ambiguous
duplicate supplier domains do not autofill. The ERP browser also owns a bounded
fallback vault backed by the operating system's secure store for non-supplier
sites or a more recently corrected login. The supplier source remains usable
when that optional native vault is unavailable, including during a development
hot reload/restart that cannot register a newly added native plugin. Only an
unsigned/ad-hoc macOS build must remain launchable without an Apple development
certificate, so the committed Runner entitlements do not request Keychain
Sharing. On that development configuration the optional local vault may be
unavailable and must fail closed without affecting supplier-backed login; a
future Apple-signed distribution may enable that capability in its signing
configuration. Only an
HTTPS main-frame form with
exactly one current-password field may send its submitted username/password
through the private WebView bridge; the value goes directly to Keychain or the
platform encrypted store and must never enter SharedPreferences, history, logs,
analytics, URLs or remote ERP storage. Local credentials are keyed by ERP user
plus exact HTTPS origin. On a later login page the browser fills the selected
credential and may submit once per origin per tab, but must stop at CAPTCHA,
OTP, additional required fields or a failed repeated login. `Olvidar credenciales
del sitio` deletes a local vault entry; credentials sourced from a supplier are
edited only in that supplier's canonical record. `Limpiar datos` deletes local
vault credentials but never mutates supplier business data.

A legacy HTTP page may receive credentials only from the single active supplier
record matching its exact host (with the same bounded `www.` alias). The local
vault remains unavailable to HTTP. If either the page or its form action is not
HTTPS, the browser may fill the fields but must not submit them automatically;
it shows a visible warning and leaves the final login action to the employee.

## Spreadsheet Workspace Surfaces

| Workflow / host | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Workbook list | Sidebar `Herramientas > Planillas`; `/tools/spreadsheets` | `spreadsheet_dashboard_page.dart` | `SpreadsheetStore` owns create/list/rename/delete; search stays visible; transport failures remain explicit and retryable rather than rendering a false empty state |
| Stored workbook import and file editing | Planillas `Importar`; Archivos file row and Correo attachment preview `Abrir en Planillas`; right-toolbar docked runner | Shared `SpreadsheetFileHandoffService`, `SpreadsheetFileImporter`, `SpreadsheetFileExporter`, and `StoredSpreadsheetRunner` | Every entry accepts `.xlsx` and `.csv`, consumes the same immutable file bytes, and keeps XLSX ZIP/XML encode/decode plus large CSV parsing behind Flutter's `compute` boundary (a background isolate on native); imported Planillas documents create metadata plus the complete workbook snapshot in one insert, while the docked runner mounts Univer directly and replaces the stored file only after a complete encoded result exists; compact CSV may decode after yielding one frame; `.xlsx` round-trips worksheets, values, formulas, merges, sizing, and common styles on populated cells while omitting unbounded style-only empty tails; global overlays navigate through `WorkspaceManager`, not a dialog-local `GoRouter`; legacy `.xls` must request conversion rather than pretending to import it |
| Workbook editor | Workbook row or create flow; `/tools/spreadsheets/:id` on macOS desktop, Windows desktop, or web | `spreadsheet_editor_page.dart` hosting the self-hosted `UniverSpreadsheetView` package bridge; WKWebView/WebView2 on native desktop and `HtmlElementView` on web | Univer owns direct in-cell editing, keyboard navigation, selections, formula engine/autocomplete, formula-time click/drag references, clipboard, formatting, undo/redo, row/column operations, and sheet tabs; every host uses the same bundle and snapshot contract; Flutter owns route/auth, workbook name, guarded exit, and visible pending/saved/error state |

`SpreadsheetStore` is the shared persistence boundary for both routed surfaces.
It stores the package engine's complete versioned `workbook_data` JSON snapshot;
legacy `spreadsheet_cells` rows are read only to migrate an existing workbook on
its first package-engine open. The engine bundle is pinned in `package.json`,
built locally, packaged as a Flutter native asset for WKWebView/WebView2,
served as a web asset for Flutter web, and must never be loaded from a CDN.
macOS is the primary verification target. Native spreadsheet hosts must preserve
the app zoom boundary so cell hit testing stays aligned at both the default 80%
zoom and 100% zoom.
If the deployed database is missing the snapshot column, the editor must report
that schema rollout mismatch explicitly, keep the workbook pending, and stop
automatic retry-on-edit requests until the user asks it to check again.
The editor must not reintroduce a hand-built grid, formula parser, keyboard
model, or parallel Flutter formatting toolbar.
`/tools/sheets` is the separate Google Sheets browser integration and is not a
second implementation of the Viñabike workbook model.

## Website Builder Surfaces

| Workflow | User entry point | Canonical implementation | Required shared behavior |
|---|---|---|---|
| Page composition | Public-store route with `?edit=true` | `PublicStoreLayout`, `PersistentEditorShell`, `WebsiteEditorPanel` | Editor block/settings state staged through `WebsiteEditModeProvider` and global `Guardar` |
| Page structure and insertion | Page composition `Agregar` tab | `_AddBlocksTab`, `WebsiteBlockRegistry`, `CanvasElementFactory`, typed `WebsiteEditorDragPayload` variants | `Capas` shows only the current page hierarchy; `Insertar` searches registry-backed page blocks and Canvas elements in separate groups. Click-add and drag-add share canonical defaults, page targets reject layer payloads, and Canvas targets reject page-block payloads. |
| Block inspector navigation | Page composition `Editar` tab after selecting a block | `_EditBlockTab`, `_CollapsibleSection`, `_SchemaRepeaterEditor`, block-specific controls | Sticky block identity/actions; Content, Design, and Style workspaces; selection resets to Content/top; dense controls use progressive disclosure; schema-defined collections show a compact overview and one active item editor with shared add/duplicate/reorder/delete behavior; carousel canvas and inspector share the same transient slide selection |
| Nested Canvas layer selection | Canvas or composed-carousel layer click, inline toolbar, or layer list | `WebsiteEditModeProvider` transient Canvas selection, `_CanvasBlockControls`, `CanvasBlock` | Block, slide, and layer selection are one transient context and never serialize into `block_data` or dirty history. The inspector identifies the selected layer, keeps the owner breadcrumb, and exposes Content, Design, and Style without traversing the parent carousel form. |
| Website media library | Any inline image replacement, schema image field, or Canvas image toolbar | `WebsiteMediaPickerDialog`, `WebsiteImagePickerField`, `WebsiteMediaService` | One searchable visual library and upload path serves every active image entry point; PNG/WebP/GIF transparency is preserved. URL remains an advanced secondary option, and background removal creates a reusable derived asset while keeping the original. |
| Catalog publication | Top bar `Catálogo web > Productos`; `/website/product-visibility` | `ProductWebsiteVisibilityPage` | Product publication/readiness and public catalog rules |
| Public catalog rendering | Header/menu/CTA routes and editor page selector at `/productos` | `ProductCatalogPage` inside `PublicStoreLayout` | Initial inventory load and route filters work in every mode; preview uses the same public policy and server pagination customers see, while active edit mode may filter the loaded complete set locally |
| Public category inclusion | Top bar `Catálogo web > Categorías` | `ProductWebsiteVisibilityPage(section: WebsiteCatalogSection.categories)` | One owner for `product_categories.show_on_website`; inventory taxonomy edits preserve this value |
| Featured collection | Top bar `Catálogo web > Destacados`; `/website/featured` | `FeaturedProductsPage` | One reusable featured-product set consumed by editor product blocks |
| Page structure | Top bar `Estructura > Páginas`; `/website/pages` | `PageManagementPage` | Canonical `website_pages` CRUD and publication |
| Header/footer navigation | Top bar `Estructura > Navegación y menús`; `/website/navigation` | `NavigationManagementPage` and `WebsiteLinkValueEditor` | Canonical `website_navigation` records; no competing renderer-only menu source |
| Campaign destination integrity | Top bar `Estructura > Destinos y enlaces`; `/website/destinations` | `WebsiteDestinationManagementPage`, `WebsiteDestinationAuditService` | Every saved block/menu href is classified, resolved to its owner, checked for readiness, and shown with usage/menu placement |
| Campaign destinations | Every CTA/link control | `WebsiteLinkValueEditor`, `WebsiteWorkspaceScope` | Typed Page/Category/Product/System selection, canonical saved href, readiness feedback, and configure-owner/return-to-editor handoff |
| Website CTA actions | Banner/block/slide/Canvas action inspector | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` | One label/destination/presentation contract, atomic legacy-alias reconciliation, shared public rendering, and normalized navigation |
| Layered campaign composition | Carousel slide `Diseño avanzado por capas` and standalone Canvas blocks | `CanvasBlock`, `CanvasElementToolbar`, `_CanvasBlockControls`, `DeferredCanvasBlock`, `createCanvasElement` | One canonical text/image/shape/button layer schema, factory, contextual toolbar, and inspector used by editor preview and public storefront; selection restores the owning block; every transformable layer has eight inline frame handles, direct rotation, alignment/arrangement, keyboard nudging, and precise inspector geometry; images use non-destructive frame crop plus persisted fit/focal point with picker-first media and shared background removal; the safe-area constraint remains one canvas/slide-wide policy; editor chrome stays outside the bounded content clip while Preview/public consume identical transforms; responsive visibility and theme font roles round-trip |
| Website image background removal | Canvas image toolbar and every schema image picker | `WebsiteBackgroundRemovalDialog`, `WebsiteBackgroundRemovalService`, `website-remove-background` | One Before/After workflow preserves the original and writes a new transparent PNG. Uniform backgrounds are removed locally without API cost; already-transparent cutouts are detected as a no-op and never sent to the paid provider; complex removal is an explicit authenticated, tenant-scoped provider action and never exposes its secret to the client. |
| Global website theme | Editor `Tema` tab | `WebsiteEditModeProvider`, `WebsiteThemeBuilder` | Saved colors/fonts/background plus global button shape/size consumed by page blocks, banners, header/footer descendants, and Canvas buttons unless explicitly overridden |
| Adaptive storefront header | Header inspector and every routed/editor/preview/public storefront surface | `PublicStoreLayout`, `PublicHeaderContrastMode`, `_HeaderBlockControls` | One global automatic contrast policy tints the logo and header controls together; transparent home headers add a restrained tonal protection over arbitrary hero layers, while solid headers follow their configured background luminance. Explicit light/dark modes remain intentional site-wide overrides and editor preview/public rendering use the same resolver. |

The Website Builder top bar switches workspaces. Only page composition may
show the persistent block inspector; catalog, structure, settings, and
operations use the full workspace while preserving the active page draft.
Category catalog visibility and navigation placement are distinct workflows:
the former controls catalog eligibility, while the latter controls menu links.
The header inspector never writes `header_nav_links`; header/footer links are
`website_navigation` records. Legacy `/website/content` bookmarks redirect to
`/website/destinations` because storefront content is owned by page blocks.

## Change Checklist

1. Identify all routes and constructor references for the business entity.
2. Update this table if any user entry point or implementation changed.
3. Implement the action once as a reusable component/service.
4. Compose it into every applicable surface and responsive variant.
5. Add/update widget tests for status/permission visibility.
6. Add/update the architecture guard for surface coverage and dead-page absence.
7. Build the supported desktop/web targets.
8. After deployment, sign in and verify the normal employee click path.
