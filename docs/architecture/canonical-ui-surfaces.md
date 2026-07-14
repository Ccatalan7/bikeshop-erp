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

## Bicycle And Technical-Profile Surfaces

Status (2026-07-14): this contract is implemented and locally verified but is
not active in production. Deploy the database migration before releasing the
RPC-dependent client.

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
| Layered campaign composition | Carousel slide `Diseño avanzado por capas` and standalone Canvas blocks | `CanvasBlock`, `_CanvasBlockControls`, `DeferredCanvasBlock` | One text/image/shape/button layer schema and inspector used by editor preview and public storefront; clicking a slide layer or its background selects the owning carousel and opens the matching inspector, transformed carousel content clips at the slide boundary, desktop/mobile visibility and theme font roles round-trip, and the shared image picker is primary while raw URL entry remains secondary/advanced only |
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
