# Editor Upgrade Gameplan

## 1. Discovery & Benchmarking
- Audit `lib/modules/website/pages/odoo_style_editor_page.dart`, `website_block_renderer.dart`, Supabase `website_blocks` tables, and related services.
- Capture current block catalog, data schema, styling controls, preview capabilities, and stored assets.
- Benchmark against Odoo, Webflow, Shopify, and Elementor focusing on block variety, styling depth, responsive tools, animations, collaboration, and publishing workflows.
- Produce a gap matrix summarizing missing features, parity requirements, and differentiation opportunities.

### Inventory Snapshot — October 2025
- `hero`, `carousel`, `products`, `services`, `about`
- `testimonials`, `features`, `cta`, `gallery`
- `contact`, `faq`, `pricing`, `team`, `stats`, `footer`
- All blocks currently flagged `usesCustomEditor = true`; shared field schemas only defined for FAQ.
- Renderer coverage complete for existing set; new registry sourced from Dart constants.

## 2. Architecture Uplift
- Define JSON-driven block schema format (fields, validation, control widgets, default content, responsive capabilities).
- Create a `lib/modules/website/block_marketplace/` directory containing:
  - Block metadata files (`*.block.json`).
  - Companion Flutter config classes for validation/control binding.
  - Documentation stubs describing data expectations.
- Implement registry loader that parses schema files, exposing definitions to editor and renderer.
- Build schema validation utilities and versioning support for blocks.

### Latest Progress
- Created `assets/block_marketplace/` with JSON definitions for the full catalog plus control metadata (category, tags, responsive flags, grouped fields).
- Added `BlockMarketplaceLoader` to ingest marketplace assets and hydrate `WebsiteBlockRegistry.ensureInitialized()`.
- Updated `WebsiteBlockDefinition` models with control sections, grouping, and versioning to unlock richer editor tooling.
- Updated editor “Agregar” tab to group blocks by marketplace category and surface tags/metadata for quicker discovery.
- Wired the Edit tab to render schema-driven control sections (text, select, sliders, color picker, image picker) so hero/features/pricing blocks can be edited without bespoke Flutter code.
- Added repeater field support to the schema/loader/editor, enabling array-based blocks like “Características” to be edited with add/reorder/remove flows driven by metadata.
- Extended repeater tooling to pricing plans (schema + editor) and surfaced CTA link defaults so conversion blocks stay data-driven.

## 3. Block Library Expansion
- Implement new block definitions and renderers for:
  - Pricing tables (tier cards, feature comparison).
  - FAQs (accordion, multi-column options).
  - Team bios (avatars, roles, social links).
  - Testimonials (avatar, rating, carousel layout).
  - Multi-column content and feature grids.
  - Blog/news teasers (Supabase-backed collections).
  - Countdown timers (launch, promo).
  - Contact forms with embedded map and Supabase form submissions.
  - Video lightboxes and hero video backgrounds.
  - Timeline/roadmap displays.
  - Footer builders with flexible columns.
- Ensure every block has default content for previews and configurable fields per schema.

## 4. Layout & Drag-and-Drop Enhancements
- Introduce drag-and-drop ordering with ghost previews using `ReorderableListView` or custom gestures.
- Add nested layout controls: multi-column grid builders inside blocks, adjustable column spans, and ordering per breakpoint.
- Expose padding/margin sliders with breakpoint overrides, alignment controls, width constraints (full-bleed vs contained).
- Provide visual guides during drag/drop and spacing adjustments.

## 5. Styling & Typography Controls
- Expand control panel to include:
  - Per-block color palettes and gradient backgrounds.
  - Font selector integrated with Google Fonts and stored preferences.
  - Heading/body size sliders with responsive overrides, weight toggles, letter spacing, and line height.
  - Border radius, shadows, divider styles, and icon packs.
  - Per-element visibility toggles (show/hide icons, buttons, subtext).
- Sync controls with global theme manager and ensure renderer respects overrides.

## 6. Media Tooling
- Integrate inline image cropping, focal point selection, and preset aspect ratios.
- Support background videos (MP4/WebM) with poster images and autoplay policies.
- Enable animated GIF/WebP previews with lazy-loading.
- Build gallery lightbox component shared across blocks.
- Connect to Supabase storage folders, providing asset browser with tagging, search, and reuse.

## 7. Interactions & Animations
- Implement scroll-triggered animations (fade, slide, zoom) with duration/delay controls.
- Add hover states for cards/buttons, including micro-interactions.
- Provide reveal-on-scroll toggles and simple parallax backgrounds.
- Ensure animation settings are available per block and previewed live.

## 8. Responsive Editing Experience
- Introduce breakpoint tabs (desktop/tablet/mobile) with independent adjustments.
- Show safe-area guides and adjustable canvas widths per device.
- Offer device frame preview (desktop, tablet, phone outlines).
- Allow block visibility toggles per breakpoint and per-element responsive overrides.

## 9. Global Theme Manager
- Create centralized theme panel managing:
  - Color palette (primary, accent, neutrals, gradients).
  - Typography scale (font families, sizes, weights).
  - Spacing system (baseline grid, padding defaults).
  - Button, card, badge, and icon styles.
- Support multiple theme presets with save/apply/delete actions.
- Ensure changes propagate to all blocks and can be versioned.

## 10. Content Reuse & Global Sections
- Implement reusable block snippets stored in Supabase with metadata and usage tracking.
- Add global sections (header, footer, nav bars) with versioning and page assignments.
- Provide clone-to-other-pages functionality and shared asset references.

## 11. SEO, Metadata & Compliance
- Extend page settings for meta title, description, keywords, Open Graph image, canonical URL.
- Enforce alt text requirements and structured data templates (products, events, testimonials).
- Build sitemap generator and robots.txt controls.
- Add accessibility checklist (contrast, heading order, ARIA hints) and performance hints (bundle weight, lazy loading recommendations).

## 12. Collaboration & Workflow Tools
- Implement revision history with undo/redo across sessions, storing deltas in Supabase.
- Provide draft vs published states, scheduled publish times, and publish logs.
- Add comment pins on blocks with mention support.
- Generate shareable preview links (time-limited tokens).

## 13. Performance & Safety Nets
- Integrate Lighthouse scoring hints and actionable suggestions.
- Surface image optimization prompts (compression, responsive sizes).
- Offer lazy-loading toggles per media-heavy block.
- Run automated accessibility scans and warnings.

## 14. Extensibility & Developer Experience
- Document block schema format and lifecycle in `/docs/editor/`.
- Create CLI or wizard to scaffold new blocks (schema + default renderer + control panel wiring).
- Ensure Supabase tables (`website_blocks`, `website_assets`, etc.) accommodate upcoming modules (blog, landing pages, campaigns).
- Provide unit/widget test templates for blocks and renderers.

## 15. Implementation Sequencing
1. Finalize schema refactor, registry loader, and block marketplace foundation.
2. Migrate existing blocks to schemas and ensure renderer/editor read from definitions.
3. Ship expanded block catalog in batches (pricing/faq/testimonials first).
4. Layer in styling controls, typography, and responsive overrides.
5. Add drag/drop upgrades, multi-column layouts, and media tooling.
6. Introduce interactions, animations, and global theme manager.
7. Implement reusable blocks, global sections, and SEO tooling.
8. Deliver collaboration features and performance safeguards.
9. Document extensibility and ship scaffolding tooling.

## 16. Milestones & Releases
- **Milestone A**: Schema-driven editor with expanded block basics (Weeks 1-3).
- **Milestone B**: Styling + responsive overhaul with drag/drop improvements (Weeks 4-6).
- **Milestone C**: Media tooling, animations, and global theme manager (Weeks 7-9).
- **Milestone D**: Collaboration, SEO, performance safeguards (Weeks 10-12).
- **Milestone E**: Extensibility tooling and documentation (Weeks 13-14).

## 17. Success Metrics
- Time to create a landing page reduced by 50% vs current editor.
- Block reuse rate across pages >40% within three releases.
- Lighthouse performance >90 for default themes, accessibility checklist passing.
- Editor engagement: drag/drop satisfaction >4/5 in user testing, responsive edits under 2 minutes.

## 18. Risks & Mitigations
- **Scope creep**: lock schema format early, feature-flag experimental blocks.
- **Performance**: cache schema files, lazy-load heavy assets, benchmark animations.
- **Complex UX**: run usability tests each milestone, keep progressive disclosure in UI.
- **Data migrations**: version schemas, provide migration scripts for existing blocks.
- **Team alignment**: maintain living roadmap, weekly sync with stakeholders.

## 19. Tooling & Dependencies
- Evaluate packages: `reorderables`, `flutter_staggered_grid_view`, `google_fonts`, `flutter_animate`, `image_cropper`, `rive` (optional).
- Ensure Supabase RPC/functions cover asset management, block versioning, and snapshots.
- Update CI to run widget tests and Lighthouse audits for sample pages.

## 20. Next Actions
- Validate editor/render parity using marketplace JSON (remove reliance on hard-coded registry map once confirmed).
- Expand schema-driven controls to cover remaining complex field types (chips with suggestions, nested repeaters) and hook them into other array-based blocks (services, testimonials, FAQs with accordions).
- Extend renderer/editor to honour new field entries for hero/features/pricing while planning migration for remaining blocks.
- Set up tracking board (Linear/Jira) aligned to milestones and share the updated schema docs with stakeholders.
