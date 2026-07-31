# Website Builder progressive refactor guardrails

This refactor preserves the editor-owned round trip:

`Edit -> Preview -> Guardar/recargar -> Publico`

Its canonical boundary is:

- **Owner:** the existing `WebsiteEditModeProvider` document/draft state and the
  tenant/page-scoped Website tables.
- **Control:** the inline editor and its single global `Guardar`.
- **Operation:** one `WebsiteSaveCoordinator`; page blocks are replaced only by
  the transactional `replace_page_blocks` RPC.
- **Consumers:** Home, dynamic CMS pages, policy pages, Preview and the public
  storefront.

## Progressive replacement rules

1. Each batch replaces its prior owner and removes that old path in the same
   change. A second provider, renderer, save coordinator or runtime feature flag
   is not a transition mechanism.
2. Do not add timers, elapsed-time mode synchronization, anti-rebounce flags
   or timing-based post-frame workarounds. Existing mode timers are frozen debt
   until the provider-owned FSM batch removes them with behavioral coverage.
   A framework-required post-frame mutation may only dispatch an idempotent
   owner command, recheck the active page/TickerMode before it runs and carry
   no elapsed-time semantics; it must never become a second mode owner.
3. Do not add responsibilities to `public_store_layout.dart`,
   `website_editor_panel.dart`, `website_service.dart` or an existing renderer
   monolith. New orchestration and composition have small named owners; later
   physical splits are mechanical.
4. Source-text assertions do not prove editor behavior. Save, discard,
   navigation, mode precedence, atomic failure and round-trip contracts require
   behavioral tests.
5. A failed save keeps the affected client draft and a visible retry path.
   Successfully acknowledged sections may clear only when their captured
   snapshot still matches the current draft.

## Phase gates

- Run focused widget/unit tests and analyzer before moving to the next batch.
- Database batches add an idempotent migration, the canonical-schema mirror and
  pgTAP proving tenant isolation, page scope and rollback on induced failure.
- A production-bound database batch is not complete at local green. Deploy the
  exact migration, read it back live, register its version, and run the relevant
  health/application smoke in the same task, following
  `docs/development/AGENT_DATABASE_CONTRACT.md`.
- Do not start a browser, Flutter preview or additional native runtime while
  the shared macOS session remains owned by another task.
