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
| Workshop job create/edit | `/taller/pegas/nueva`, `/taller/pegas/:id`, embedded client-logbook job pane | `mechanic_job_form_page.dart` | Stable diff/upsert of job bikes and items; structured diagnosis and task parents survive ordinary saves; duration persists; workflow (`service`/`quotation`/`warranty`) and physical intake (`bike`/`component`/`unspecified`) stay orthogonal behind the four familiar creation choices; saved mode/intake changes use audited table actions instead of the form selector; quotations with a persisted approval/rejection/expiry decision are read-only, while a still-pending quote may extend its validity and a converted quotation becomes a normally editable service whose accepted commercial snapshot remains immutable in the event ledger; quotation decisions/conversion use the audited commands and quotations never own invoices; tax is a read-only invoice mirror; warranty work links to its original delivered job and audited decision command; changing the customer on an unsaved job clears every customer-scoped bike, component, warranty source, outcome, and reason; an unpaid linked invoice exposes the shared routed payment action and a paid invoice does not |
| Workshop list actions | `/taller/pegas` table/list/calendar hosts | `pegas_table_page.dart` + `pegas_calendar_widget.dart` | Canonical job form in one familiar table; existing columns render the workflow/intake distinction without a new permanent column; quotation PDF/status/conversion and mode-review actions use the shared service commands; bicycle counts include only `intake_kind = bike`; status surfaces consume the same immutable delivery/service-warranty projection; removing an active job uses soft delete and preserves its invoice/accounting evidence |
| Linked invoice edit | Job invoice action, routed invoice page, invoice list preview, embedded editor | `invoice_form_page.dart` / `sales_invoice_editor.dart` / list preview | One database-owned bidirectional line sync with stable `mechanic_job_items.id`; a failed invoice read renders an explicit retry state, never an empty saveable invoice |
| Invoice payment and tax choice | Routed payment page and every preview/dialog that composes `PaymentForm` | `invoice_payment_page.dart` + `PaymentForm` + `SalesService.registerPaymentWithInvoiceTax` | One idempotent database transaction posts the invoice when needed, classifies the whole invoice as IVA-included/no-tax, then records settlement; job/payment rows mirror that classification; a fully paid direct route renders a closed summary, not a zero-value form |

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

Quotations are planning documents, not invoices. They may carry proposed
`mechanic_job_items` and a customer-facing quotation PDF, but cannot link a
`sales_invoices` row or own inventory/accounting effects. Approval is audited;
conversion to `service` or `item_service` validates the received bicycle or
component and may create the billable draft invoice atomically. A late approval
after `quotation_valid_until` requires an explicit audited reason and remains a
valid conversion receipt. A conservatively detached legacy quote draft is kept
as a cancelled document, never an actionable orphan. The same
`mechanic_job_mode_view` / `mechanic_job_mode_events` contract must be consumed
by the routed form, embedded form, table, list, calendar and quick actions.

## Bicycle And Technical-Profile Surfaces

Status (2026-07-15): this contract is implemented, locally verified and active
in production through migration
`20260714120000_add_atomic_bike_aggregate_save.sql`.

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
