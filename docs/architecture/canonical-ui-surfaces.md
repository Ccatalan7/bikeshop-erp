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
| Workshop job create/edit | `/taller/pegas/nueva`, `/taller/pegas/:id`, embedded client-logbook job pane | `mechanic_job_form_page.dart` | Stable diff/upsert of job bikes and items; structured diagnosis and task parents survive ordinary saves; duration persists; workflow (`service`/`quotation`/`warranty`/`sale`) and physical intake (`bike`/`component`/`none`/`unspecified`) stay orthogonal behind five familiar creation choices. `Servicio` defaults only for new rows to `Presupuestar primero`: it receives and preserves the bicycle/ficha/diagnosis but creates no invoice or financial effect; `Facturar ahora` preserves the established immediate-invoice path. The standalone no-object choice is `Cotización`. Existing rows hydrate from their canonical axes, so historical billable services never change behavior. `Venta / cobro` requires a customer and catalog product, receives no physical object, hides diagnosis/mechanical scheduling and creates the normal invoice after its lines are saved; its optional agreement text is operational notes only and the linked invoice remains the sole source of stock, tax, receivable, balance and payments. A creation-mode change that removes bicycle context requires confirmation, preserves commercial lines in General, and copies nonempty standalone narrative into the first bicycle without overwriting bicycle-specific text; changing an unsaved warranty source with source-scoped draft data also requires confirmation and preserves its lines before replacing the physical diagnosis context. Saved mode/intake changes use audited table actions instead of the form selector. Proposals with a persisted approval/rejection/expiry decision are read-only, while a still-pending proposal may extend its validity and a converted proposal becomes a normally editable service whose accepted commercial snapshot remains immutable in the event ledger; decisions/conversion use the audited commands and proposals never own invoices. Tax is a read-only invoice mirror; warranty work links to its original delivered job and audited decision command; any persisted job with active-payment evidence on its linked invoice, or an unreadable linked-payment state, keeps allowed operational notes editable but locks the physical object, products, discount, totals and mutable job-to-invoice projection; changing the customer on an unsaved job clears every customer-scoped bike, component, warranty source, outcome, and reason; an unpaid linked invoice exposes the shared routed payment action and a paid invoice does not |
| Workshop list actions | `/taller/pegas` table/list/calendar hosts | `pegas_table_page.dart` + `pegas_calendar_widget.dart` + `pega_detail_view.dart` + client-logbook list + workshop mode coordinators | Canonical job form in one familiar table; existing columns render the workflow/intake distinction without a new permanent column. A bike-backed quotation workflow renders as `Servicio · Presupuesto`, keeps its real bicycle/count/calendar capacity, downloads a PRESUPUESTO PDF and converts directly with the persisted object. In the table's existing `Factura` column, pressing an approved `Presupuesto` chip opens the compact choices `Descargar presupuesto` and `Facturar presupuesto`; the latter delegates to the same confirmed, idempotent conversion command and never creates a parallel invoice path. Pending, rejected or expired proposals cannot expose this billing shortcut, and the server refuses approval until at least one product/service line exists. New proposal-status feedback replaces any older snackbar instead of queueing it across routes; reopening as pending, starting conversion, or opening the linked invoice removes obsolete proposal feedback before navigation. A standalone quotation renders as `Cotización · Sin objeto recibido`, is excluded from bicycle counts/mechanical capacity, downloads a COTIZACIÓN PDF and keeps the explicit intake picker on conversion. Both use the shared status/conversion commands and are excluded from total/paid/receivable figures while appearing separately as `Presupuestado` and `Cotizado`. `sale/none` renders as `Venta / cobro · Sin objeto recibido`, uses the existing total/invoice payment progress, remains active while the invoice has balance, leaves Activos when fully paid, and is excluded from bicycle/component/warranty counts and mechanical calendar/Gantt. A flagged `REVISAR MODO` row opens the same compact classification action from its chip or overflow menu, offering bicycle, component, or product sale and calling the corresponding idempotent audited command; each coordinator owns one stable operation key per attempt, reuses it for readback/replay after a lost ACK and keeps an explicit uncertain outcome instead of reporting a false rollback; removing an active job uses soft delete and preserves its invoice/accounting evidence |
| Linked invoice edit | Job invoice action, routed invoice page, invoice list preview, embedded editor | `invoice_form_page.dart` / `sales_invoice_editor.dart` / list preview | New invoice creation with a job context delegates atomically to `create_billable_invoice_from_mechanic_job`; neither routed nor embedded surfaces may insert a generic invoice and then link the job best-effort, and command failure must never produce success feedback. `mechanic_jobs.invoice_id` is the single enforced relationship: the job opens that invoice directly and invoice surfaces resolve their job through the reverse lookup, without a second writable pointer. Existing linked invoices use one database-owned bidirectional line sync with stable `mechanic_job_items.id`; an omitted/blank/JSON-null invoice `job_bike_id` preserves the existing physical attribution for that same stable item, while an explicit value must resolve inside the same job/tenant; a failed invoice read renders an explicit retry state, never an empty saveable invoice |
| Invoice payment and tax choice | Routed payment page and every preview/dialog that composes `PaymentForm` | `invoice_payment_page.dart` + `PaymentForm` + `SalesService.registerPaymentWithInvoiceTax` | One idempotent database transaction posts the invoice when needed, classifies the whole invoice as IVA-included/no-tax, then records settlement; job/payment rows mirror that classification; a fully paid direct route renders a closed summary, not a zero-value form |

Every employee status control in the table, legacy list, calendar, routed form
and embedded form delegates to `BikeshopService.transitionJobStatus` and
`MechanicJobStatusTransitionCoordinator`. The server command
`transition_mechanic_job_status` owns the legacy `status` mirror, lifecycle
timestamps, invoice-before-job locking and the append-only exact-key receipt.
An ordinary form update omits `status`, `status_id`, `started_at`,
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
| Job bicycle create/edit | `/taller/pegas/nueva`, `/taller/pegas/:id`, and the client-logbook embedded Jobs pane | `mechanic_job_form_page.dart` hosting `BikeFormDialog` | Atomic bicycle aggregate save; returned bike selected only after commit/replay; failed profile reads stay explicit |
| Customer bicycle create/edit | Client logbook Bikes tab, desktop embedded pane, and mobile modal | `client_logbook_page.dart` hosting `BikeFormDialog` | Same aggregate command and load-state contract across embedded/modal variants |
| Jobs-table bicycle profile | `/taller/pegas` single-bike and per-bike row actions | `pegas_table_page.dart` hosting `BikeFormDialog` | Open the canonical aggregate editor; no competing quick profile writer |
| Calendar base identity editor | `/taller/calendario` and calendar mode embedded in Jobs | `pegas_calendar_widget.dart` | Base-only edits must preserve `bike_profiles`; full technical edits route to `BikeFormDialog` |
| Debug workshop fixture | Debug-only `Prueba rápida` launcher | `pegas_table_page.dart` fixture helpers | Use `saveBikeAggregate` for repeatable profile/backbone validation; never retain the old paired-write path or expose a production-visible competing editor |

The database command owns tenant checks, optimistic versions, idempotent
replay, `bikes` + optional `bike_profiles`, and their save events in one
transaction. `bike_aggregate_save_operations` is command/audit evidence only;
technical truth remains exclusively in `bikes` and `bike_profiles`.

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
| Message body and attachments | Selected message on routed desktop, compact, and mobile layouts | `email_detail_view_unified.dart` | Shared sender/actions/attachments; fit-safe HTML on web and native WebView; web links open the ERP browser workspace; compatible `.xlsx`/`.csv` attachment bytes open through the canonical Planillas handoff without a download round trip; destructive actions remain outside the renderer |

`MailAccountManager` is the shared owner of connected-provider state, merged
messages, selection, account filtering, read state, search, send, and trash
commands. Host layouts must not retain a selected message from an account that
the active provider filter excludes, and reply surfaces must never silently
fall back to the first connected account.

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
| Block inspector navigation | Page composition `Editar` tab after selecting a block | `_EditBlockTab`, `_CollapsibleSection`, `_SchemaRepeaterEditor`, block-specific controls | Sticky block identity/actions; Content, Design, and Style workspaces; selection resets to Content/top; dense controls use progressive disclosure; schema-defined collections show a compact overview and one active item editor with shared add/duplicate/reorder/delete behavior; carousel canvas and inspector share the same transient slide selection |
| Catalog publication | Top bar `Catálogo web > Productos`; `/website/product-visibility` | `ProductWebsiteVisibilityPage` | Product publication/readiness and public catalog rules |
| Public catalog rendering | Header/menu/CTA routes and editor page selector at `/productos` | `ProductCatalogPage` inside `PublicStoreLayout` | Initial inventory load and route filters work in every mode; preview uses the same public policy and server pagination customers see, while active edit mode may filter the loaded complete set locally |
| Public category inclusion | Top bar `Catálogo web > Categorías` | `ProductWebsiteVisibilityPage(section: WebsiteCatalogSection.categories)` | One owner for `product_categories.show_on_website`; inventory taxonomy edits preserve this value |
| Featured collection | Top bar `Catálogo web > Destacados`; `/website/featured` | `FeaturedProductsPage` | One reusable featured-product set consumed by editor product blocks |
| Page structure | Top bar `Estructura > Páginas`; `/website/pages` | `PageManagementPage` | Canonical `website_pages` CRUD and publication |
| Header/footer navigation | Top bar `Estructura > Navegación y menús`; `/website/navigation` | `NavigationManagementPage` and `WebsiteLinkValueEditor` | Canonical `website_navigation` records; no competing renderer-only menu source |
| Campaign destination integrity | Top bar `Estructura > Destinos y enlaces`; `/website/destinations` | `WebsiteDestinationManagementPage`, `WebsiteDestinationAuditService` | Every saved block/menu href is classified, resolved to its owner, checked for readiness, and shown with usage/menu placement |
| Campaign destinations | Every CTA/link control | `WebsiteLinkValueEditor`, `WebsiteWorkspaceScope` | Typed Page/Category/Product/System selection, canonical saved href, readiness feedback, and configure-owner/return-to-editor handoff |
| Website CTA actions | Banner/block/slide/Canvas action inspector | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` | One label/destination/presentation contract, atomic legacy-alias reconciliation, shared public rendering, and normalized navigation |
| Layered campaign composition | Carousel slide `Diseño avanzado por capas` and standalone Canvas blocks | `CanvasBlock`, `CanvasElementToolbar`, `_CanvasBlockControls`, `DeferredCanvasBlock`, `createCanvasElement` | One canonical text/image/shape/button layer schema, factory, contextual toolbar, and inspector used by editor preview and public storefront; selection restores the owning block; every transformable layer has eight inline frame handles, direct rotation, alignment/arrangement, keyboard nudging, and precise inspector geometry; images use non-destructive frame crop plus persisted fit/focal point with picker-first media; the safe-area constraint remains one canvas/slide-wide policy; editor chrome stays outside the bounded content clip while Preview/public consume identical transforms; responsive visibility and theme font roles round-trip |
| Global website theme | Editor `Tema` tab | `WebsiteEditModeProvider`, `WebsiteThemeBuilder` | Saved colors/fonts/background plus global button shape/size consumed by page blocks, banners, header/footer descendants, and Canvas buttons unless explicitly overridden |

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
