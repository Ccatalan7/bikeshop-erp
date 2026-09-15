# Product Identity Resolver V3 — implementation plan

Status: AI-first source integration implemented and canonical 2025-06-28 replay
is 6/6; a certified sealed-day holdout and paired release remain pending  
Date: 2026-08-11  
Owner: Inventory / purchase OCR

This plan turns the 10-day AliExpress audit into one coherent implementation.
It replaces the current chain of independently inferred name, category and
duplicate candidates with one row identity and one reproducible decision.

The original measured baseline contained 39 invoice rows: 25 clear top-1
matches, 9 wrong top-1 matches, 3 ambiguous rows and 2 rows with no sellable
catalog product. Reopening 2024-12-26 exposed one intermittently returned RISK
cable-cap row, so the original regression oracle contained 40 rows. The first
truly unseen date, 2024-12-17, then exposed a missing seatpost-adapter family:
the row was categorized as `Asiento` and the picker offered physical saddles.
That row became regression row 41. A second unseen date, 2024-12-20, exposed
seven more production rows and production-flow defects: phone holders were confused with the
handlebar they mount to, bottle cages with the bottle they contain, plural
`portabotellas` was missing, complete hydraulic brakes were reduced to the
pictured caliper, selected `Right Rear` was cancelled by a front/rear listing
menu, and the UI called ruled-out rows “8 opciones”. The newly surfaced ENLEE
CR-2 row was already correct and remains as a guardian. Those seven rows are
now regression rows 42–48 and neither opened day remains a holdout. The dominant
defect was not a missing score weight: candidate admission and authority were
inconsistent, and the taxonomy gate must also prove generalization.

## Corrected implementation checkpoint — 2026-08-12

The canonical AliExpress review path is AI-first, not AI-after-ranking. A
confirmed immutable supplier-variant resolution is checked first and is the only
path that may materialize an existing product or product set without AI. A
not-found lookup invokes one strict multimodal investigation before any family
or taxonomy return. A lookup error, unavailable model, timeout, malformed JSON,
unoffered category ID or insufficient investigation fails closed with zero
heuristic recommendation.

The investigation receives the original supplier title, selected variant and
immutable key separately, row context, one source image and the tenant's real
active leaf `{id, path}` list. Its versioned receipt carries the row revision,
catalog/tree/prompt/model versions and listing/variant/image identities. The
same row snapshot feeds both the collapsed row and picker; opening/closing the
picker spends no AI, vision or catalog call. An identity-bearing edit invalidates
the receipt and schedules one new row revision.

Every active non-service catalog product reaches evaluation. The AI-proposed
exact leaf `category_id` controls the normal pool; plausible identity matches
outside that exact leaf, including missing-category rows, remain separately
visible as catalog conflicts. Deterministic taxonomy/extraction is a
contradiction validator and retrieval trace. It may corroborate or veto a proved
family/manufacturer/exclusive-spec conflict, but it cannot originate the only
identity, return early on an unknown term or supply a fallback recommendation.

The original 40-row replay was green, but it did not certify unseen listings.
It reused observed/known catalog categories, disabled production visual/AI
behavior and had no seatpost-adapter example. Calling the implementation
complete from that evidence was incorrect. The repaired regression gate now
also requires:

- the exact 2024-12-17 source resolves to `seatpost_shim`, never `saddle`;
- category resolves to the dedicated leaf `Accesorios / Asientos /
  Adaptadores de tija`;
- unordered diameter pair `27.2|30` admits `AE0274` and eliminates the
  `27.2|28.6` sibling `AE0266`;
- the complete 1,555-product catalog returns `AE0274` first with no saddle in
  normal/operator choices;
- a historically misfiled gold is isolated as a catalog conflict instead of
  being replaced by an in-category wrong object;
- the then-current 41-row checkpoint measured 35/35 single-product rows at
  top-1 and top-3; that historical result is not the current 48-row metric;
- all three genuinely ambiguous rows retain their acceptable candidates;
- both explicit no-catalog rows abstain;
- the EF500 set row exposes both `AE0031` and `AE0034` without pretending the
  current one-product purchase-line model can persist the pair;
- with the categories actually observed in the original run, all 43 clear/set
  known-existing rows remain in a named safe scope, all three ambiguous sets
  remain complete, both absences abstain, and no off-category product is mixed
  into normal operator choices.

The grounded second multimodal pass receives the source plus every viable normal
and catalog-conflict candidate, real candidate images and explicit typed
differences. It returns `same`, `different`, `composite` or `insufficient` with
offered product IDs, positive quantities and typed basis values. It is not
restricted to a deterministic score band. Invalid IDs/basis/cardinality,
malformed output, timeout or a request exceeding the explicit model budget
becomes `insufficient` without silent truncation. Confidence is descriptive,
never an auto-link threshold. AI composite components expose no `Vincular` or
`Es este`. They stay review evidence until a separate operator confirmation
shows the complete inventory impact and persists an immutable supplier graph.

The prior read-only canonical macOS pass regenerated 2024-12-26 and inspected
the completed picker without pressing a persistence action. The spacer row was
placed in `Espaciadores`, offered `AE0041` first and showed only that catalog
scope. The tubeless repair row was placed in `Tripas Tubeless` and offered only
`AE0047`; the former pump and truing-stand leakage was gone. The EF500 set row
abstained and exposed both `AE0034` and `AE0031`. AliExpress returned 10 rows in
this final pass and omitted the RISK row that it had returned in the preceding
pass. That row had already resolved to `AE0360`; the final deterministic leaf
tests place shift cable caps in `Componentes / Fundas y piolas / Cambios`,
brake cable caps in `/ Frenos`, and abstain on a generic undecidable housing.
No alias, product or invoice was written. It was a regression pass, not an
unseen holdout.

The canonical macOS session then regenerated 2024-12-17 after a hot restart
and a production catalog refresh. The MUQZI row resolved to `Adaptadores de
tija` and offered `AE0274` first as `Casi seguro`. Its picker contained only
`AE0274` plus the same-family `AE0266` under “descartados”; `AE0266` was
eliminated by the explicit `27.2 ↔ 30 != 27.2 ↔ 28.6` diameter-pair conflict.
No saddle appeared in the row or picker. The ODI row on the same invoice still
resolved to its purple ODI grips. No persistence action was pressed.

The next regression gate uses a sanitized 1,555-product identity-only catalog
and the corresponding 134-node category tree rather than a flat leaf-only
invention. Synthetic record/tenant IDs, omitted supplier/image fields and
zeroed money preserve the public-repository boundary without weakening the
catalog-scale identity competition. It no
longer injects the gold SKU's category. Across 48 diagnosed rows it requires
every clear gold to remain in a normal or explicit catalog-conflict scope,
keeps all ambiguous sets complete, abstains on both absences and keeps ordinary
suggestions inside the resolved object/category. The deterministic text-only
track is 37/42 clear top-1; the remaining rows require the image, listing or
catalog-placement evidence that the real runtime owns, so they are not relabelled
as text matches merely to make the metric perfect.

Runtime closure still requires replaying 2024-12-20 after restart and then
replacement unseen listing groups that remain sealed until they are labelled.
The repaired 2024-12-17 and 2024-12-20 rows are regression evidence and cannot
be counted again as holdout data.

### AI-first runtime checkpoint — 2026-08-12

The first live AI-first replay used the six product rows from 2025-06-28. It
resolved all six expected catalog identities in the canonical macOS review,
read-only: the misfiled MicroSpline lockring (`AE0333`) and the five WAKE tee
variants black (`AE0136`), blue (`AE0139`), red (`AE0137`), golden (`AE0301`)
and purple (`AE0138`). No link, alias, product or invoice write was performed.

This run exposed four protocol/admission failures that had appeared random in
the UI but were independent and reproducible: malformed/alternate provider JSON,
a semantically correct candidate returned with an invented UUID, a redundant
model/prompt receipt echoed incorrectly by the model, and a correctly
identified product excluded before adjudication because its catalog category
was wrong. The repair is structural, not product-specific:

- provider output is normalized into the strict structured identity shape and
  receives one bounded retry;
- leaves and candidates are sent as opaque request-local references and are
  restored only from the client-owned offered map;
- model/prompt versions are stamped by the client rather than trusted as model
  echoes;
- the exact AI leaf is adjudicated first; a resolved leaf skips the expensive
  global pass;
- an unresolved leaf triggers deterministic, complete-catalog AI screening in
  bounded chunks, followed by one grounded multimodal adjudication; legacy
  taxonomy cannot suppress an off-leaf row before that pass.

The red WAKE row proved the fast path after hot reload: all 17 direct `Tee`
rows were offered, the model returned opaque `C001`, the client restored it to
the exact `AE0137` UUID, and the trace recorded
`catalog_match.global_screen_skipped`. The misfiled lockring proved the fallback:
all 1,554 eligible catalog rows were covered once in deterministic chunks,
`AE0333` survived despite its `Accesorios` placement, and the final grounded
pass selected it while retaining the category conflict.

This is strong runtime regression evidence, not a generalization claim. The
next sealed-day attempt (2025-07-20) was rejected before OCR because the
AliExpress browser session no longer had a captured orders request and was
redirected to login. It produced zero matcher rows and is not counted. Runtime
closure still requires at least one complete, certified, listing-distinct day
that has not been opened by this implementation.

The 2024-12-20 runtime also exposed a product-line/variant authority bug after
the object/category repair: the black ZTTO cage ranked a different black
catalog row above the multicolour listing row although blue and red from the
same immutable listing resolved to `AE0275`. The repair does not add a colour
weight or assume one listing is one product. Selected colour is an exclusive
mismatch gate and only the final tie-break after line evidence; explicit
construction material may eliminate an incompatible candidate; a shared
publication photo is line corroboration, never exact variant identity.
Listing-group reconciliation may only downgrade a dissenting row to abstention
and reorder viable manual choices. It cannot promote, auto-link, revive
review-only recall, reinterpret AI output or collapse real multi-product
listings such as WAKE red/purple tees or MT200 front/rear sets.

Still deliberately outside this delivery: durable per-row decision events,
append-only alias history, a typed `NON_MERCHANDISE` persistence outcome and
lossless one-source-row-to-many purchase persistence. Those need additive data
models and guarded production read-back; hiding them behind a single product ID
would be a data-integrity regression.

## Product decision

The implementation follows these rules.

1. **The supplier title is immutable evidence.** The cleaned display name may
   improve the draft, but never replaces `originalNoisyTitle` for identity,
   category or alias decisions.
2. **The primary multimodal investigation answers what the object is and
   proposes where it belongs.** Category proposals are exact IDs selected from
   the offered active leaf list; labels and fuzzy/ancestor matches carry no
   authority.
3. **An exact leaf is a display scope, not an admission filter or `+0.08`.**
   Normal row/picker choices have the same exact `category_id`. The full active
   non-service catalog is still evaluated, and plausible identity matches with
   another/missing category are quarantined as catalog conflicts rather than
   disappearing or mixing into the normal list.
4. **Unknown deterministic vocabulary cannot decide the row.** It neither
   erases a candidate nor causes an early return. Missing/invalid AI identity
   abstains; the old taxonomy/ranker never takes over.
5. **An image is corroboration, never exact identity.** AliExpress reuses
   listing photos across variants. Image equality must pass family, model and
   variant gates.
6. **Exact means provenance.** Only a catalog-owned SKU or a confirmed alias
   keyed by supplier + listing + immutable variant identity is eligible for an
   exact path. Translated labels, image filenames and `default` aliases are
   provisional evidence.
7. **One row revision produces one investigation and at most one
   adjudication.** The automatic row and alternatives picker consume the same
   cached receipt/result. Opening a picker never reloads the catalog, rereads
   the image or spends AI quota; an identity edit creates a new revision.
8. **AI owns identity and grounded comparison, not authority.** The second pass
   sees every viable normal/conflict candidate, not a score band. Invalid IDs,
   invalid typed basis, contradictory shapes, timeout, malformed output or
   budget overflow are explicit insufficiency. Even `same` at confidence 1.0
   cannot link, learn or write.
9. **Existing-product linkage inherits catalog truth.** Linking a draft never
   reclassifies the catalog product from supplier prose.
10. **Automation fails closed.** The first release auto-links only confirmed
    immutable aliases or equivalent catalog-owned codes. Every inferred match
    remains a recommendation requiring operator review.

## Authority and candidate policy

| Row state | Normal recommendation | Alternatives | Automatic action |
| --- | --- | --- | --- |
| Confirmed immutable supplier resolution, compatible active product/set | Exact product or ordered components | Authority trace | Materialize in review with zero AI |
| Authority lookup error or malformed graph row | None | Retryable error | Fail closed, zero AI |
| Valid investigation + exact offered active leaf | Same exact `category_id`, after proved contradiction gates | Same normal pool; ruled-out rows carry objections | Review only |
| Plausible identity, another or missing catalog category | Never mixed into normal ranking | Separate `Conflictos de catálogo` group and grounded adjudication | Review/hygiene only |
| Missing, timeout, malformed or invalid-leaf investigation | None | Cached manual catalog search | Abstain; no heuristic fallback |
| AI `same` | One offered review recommendation | Same stored snapshot | Never auto-link |
| AI `different` / `insufficient` | None | Stored operator choices and conflicts | Abstain |
| AI `composite` | Ordered components/quantities, no single-product action | `Usar descomposición` only with immutable variant + coherent package evidence | Persist guarded graph after explicit confirmation |
| Proved family/manufacturer/exclusive-spec contradiction | Excluded from recommendation | Ruled-out diagnostic with typed objection | Never |
| Same image/listing without immutable variant authority | Supporting evidence only | Grounded comparison | Never by itself |
| Non-merchandise / workshop consumable | No catalog duplicate recommendation | Explicit operational-supply outcome | Never create sellable product implicitly |

Normal category compatibility is exact `category_id` equality with the offered
AI leaf. Ancestors/descendants and repeated leaf names do not expand this pool.

## Runtime data model

The strict primary model is shared by OCR and the matcher:

```dart
final class AIProductIdentityInvestigation {
  final String schemaVersion;
  final String promptVersion;
  final String modelId;
  final AIProductObject object;
  final AIProductManufacturer manufacturer;
  final List<AIProductModel> models;
  final List<AIProductSpec> specs;
  final AIProductComposition composition;
  final List<AIProductLeafProposal> leafProposals;
  final AIProductIdentityReceipt receipt;
}
```

`AIProductIdentityReceipt` binds the result to row revision, catalog/tree/prompt
versions, model, listing, immutable variant and source-image identity. Offered
leaf validation happens before the result reaches matching.

The matcher returns one snapshot:

```dart
final class ProductDuplicateSearchResult {
  final AIProductIdentityInvestigation? investigation;
  final AIProductMatchDecision? adjudication;
  final ProductDuplicateDecisionKind decision;
  final List<ProductDuplicateCandidate> recommendations;
  final List<ProductDuplicateCandidate> normalCandidates;
  final List<ProductDuplicateCandidate> operatorChoices;
  final List<ProductDuplicateCandidate> categoryConflicts;
  final List<AIProductMatchPick> compositeComponents;
  final String? abstentionReason;
}
```

The snapshot is stored on `_NewProductEntry` with its row revision and is
invalidated only by identity-bearing edits: supplier title/variant, name,
brand, category, model or image. UI-only changes do not rerun it.

## Implementation slices

### A. Authority-first primary investigation

- `ProductIdentityReviewCoordinator` resolves the immutable supplier graph
  before downloading an image or calling either model pass.
- The OCR host passes the original supplier title, selected variant, immutable
  key and listing identity separately; cleaned text remains display-only.
- `AIAssistantService` returns one strict multimodal identity and versioned
  receipt from real offered active leaves. Unknown/inactive/parent IDs,
  malformed JSON and model failure are rejected before matching.
- `_NewProductEntry` owns the receipt/result for one row revision. The add-on's
  `AI_CLEANED` flag cannot substitute for it.

### B. Complete catalog universe and exact-leaf scopes

- Cache a diagnostic identity for every active, non-service catalog product and
  evaluate the complete set; retrieval postings/order cannot omit a gold row.
- Exact proposed leaf `category_id` defines the normal pool. Plausible identity
  matches with another/missing category go only to `categoryConflicts` and are
  included in adjudication.
- Deterministic family/manufacturer/exclusive-spec logic may reject only a
  proved contradiction. Missing vocabulary is neutral, not a return condition.
- Image equality remains supporting evidence and never exact authority.
- A safe explicit candidate-budget overflow abstains and preserves operator
  choices; no candidate list is silently truncated.

### C. One decision for row and picker

- Introduce `resolveCandidates`; keep `findCandidates` only as a compatibility
  wrapper while callers migrate.
- Build recommendation, operator and conflict lists from the same evaluation
  and one AI adjudication.
- Store the result on `_NewProductEntry` and pass stored lists to
  `OcrCandidatePicker`. Delete the automatic picker recomputation path.
- The picker has three deliberate surfaces: normal category-scoped choices,
  catalog-conflict diagnostics, and an explicit all-catalog manual search.
  Cross-family manual selection requires confirmation and is never learned as
  an authoritative alias without an explicit operator decision.

### D. Fail-closed grounded adjudication

- Send the source investigation/image plus every viable normal/conflict
  candidate, its real image and explicit reasons/objections.
- Parse only `same`, `different`, `composite` or `insufficient`, with offered
  product IDs, positive quantities and typed basis values. Validate cardinality
  and every ID/basis before exposing a recommendation.
- Preserve the typed result in the row snapshot. Confidence is descriptive;
  all inferred choices remain review evidence and never auto-link or write.

### E. Supplier resolution graph safety

- The deployed append-only supplier variant resolution graph is the sole
  exact/composite AliExpress authority. Client lookup distinguishes
  resolved/not-found/error and validates active non-service catalog targets.
- A confirmed graph resolution materializes its normal or composite review state
  with zero AI. An error or malformed edge fails closed with zero AI.
- AI and discovery never create, revise or learn graph edges. Only the
  separately confirmed `Usar descomposición` outcome may do so through its
  guarded writer/read-back flow.

### F. Sets and document-level consistency

- Reuse existing `product_set_components` only as catalog composition.
- Add a document-level consistency pass over row snapshots: distinct immutable
  supplier variants cannot collapse onto one catalog variant without exact
  evidence; genuine repeated purchases may share a product.
- AI composite recommendations are rendered as ordered components/quantities in
  an abstained state with no single-product link. An explicit operator command
  may confirm the entire graph; it never confirms only one component.
- Exact existing `product_set_components` composition is reused through its set
  parent. If no exact set exists, the supplier graph keeps ordered ordinary
  component edges; it never reparents those products or invents a new set.
- The deployed source-resolution application expands direct graph edges into
  ordinary purchase lines with exact landed-cost allocation and immutable
  source-line provenance. Set-parent edges remain one purchase line and expand
  later through the existing receipt/stock kernel, so the client never
  double-expands them.

### G. Trace and rollback

- Keep a redacted in-memory receipt/trace containing source identity hashes,
  versions, offered/admitted candidates, hard gates, scopes and adjudication.
  Do not log full invoice prose or image bytes.
- Production has one AI-first review path. Deterministic ranking can be disabled
  in tests to prove AI independence; it is not a runtime fallback switch.
- Durable production decision events require a later additive migration and
  are not a prerequisite for read-only accuracy validation.

## File map and ownership

| File / owner | Change |
| --- | --- |
| `ai_service.dart` | Strict structured investigation/adjudication prompts, parsers and versioned receipts |
| `product_identity_review_coordinator.dart` | Confirmed authority before AI; explicit error/not-found ordering |
| `product_identity_profile.dart` | Deterministic validator profile and hypotheses; no primary authority |
| `product_category_resolver.dart` | Category contradiction/diagnostic compatibility only |
| `product_catalog_identity_index.dart` | Cache complete catalog identities; no admission cliff |
| `product_identity_matcher.dart` | Corroboration and proved family/spec/manufacturer contradiction gates |
| `product_duplicate_matcher_service.dart` | Full-catalog exact-leaf/conflict scopes and typed grounded adjudication |
| `ocr_upload_widget.dart` | Real leaf offer, row-revision receipt/cache, coordinator integration |
| `ocr_candidate_picker.dart` | Consume cached scopes; explicit diagnostic/manual escape hatches |
| focused unit/widget/contract tests | Lock every invariant below |

The earlier concurrent ownership of `product_identity_extractor.dart` and
`ocr_product_identity_matcher_test.dart` was released before integration. The
compound-head/brand fix was retained and the measured taxonomy additions were
applied on top of it.

## Verification gates

### Focused tests

- confirmed immutable authority wins with zero AI; lookup error fails closed
  with zero AI;
- unknown deterministic taxonomy plus image/structured AI identity can select
  an offered active leaf and find its gold without new vocabulary;
- parent/inactive/invented leaf IDs, malformed JSON and timeout fail closed;
- every active non-service catalog row is evaluated; inactive/service rows are
  excluded;
- exact leaf products are normal and a plausible misfiled/missing-category gold
  is isolated as a catalog conflict without disappearing;
- image-equal conflicting family or variant is never exact;
- `same`, `different`, two-or-more-pick `composite` and `insufficient` remain
  distinct; invented product IDs, invalid basis and contradictory shapes fail;
- prompt instructions embedded in supplier/catalog data cannot alter authority;
- with deterministic ranking disabled, fake investigation/adjudication still
  recommends correctly; with AI disabled/failing, the row abstains;
- opening/closing the picker spends zero additional visual or adjudication
  calls and preserves ordering;
- an identity edit makes exactly one new revision/call;
- AI composite has no single-product action and discovery mutation spies remain
  zero before a human action.

### Locked real-data gate

The 48 diagnosed rows are regression data with expected catalog SKU sets or
explicit absence. The deterministic replay runs from observed invoice fields,
the sanitized full identity catalog and category tree; it does not inject the
gold placement. Full-catalog retrieval is 100% by construction and is not
presented as an accuracy metric. A replacement unseen listing-group holdout,
alias-enabled/masked comparison and calibrated live AI off/on metrics remain
required before widening automatic linking beyond the authoritative exact
paths.

Release requirements:

- every known-existing row has an expected SKU and every absent row is labelled
  `no existe` before running the gate;
- every clear gold admitted in normal or explicit catalog-conflict scope;
- deterministic text-only top-1 at least 36/42 clear rows, with every remaining
  image/listing-dependent tie verified in the real runtime rather than hidden
  through oracle leakage;
- all three ambiguous candidate sets retained, both absences abstaining and
  both EF500 component SKUs exposed;
- zero wrong automatic links and zero false-new outcomes;
- no different-family product in normal suggestions;
- no off-category product mixed into normal suggestions when category authority
  is resolved;
- row and picker expose the identical stored decision;
- one structured investigation per row revision and at most one adjudication;
- focused analyzer/tests green and a read-only pass through the canonical macOS
  debug session.

Accuracy validation must not press `Vincular`, `Es este`, `Nuevo`, `Crear
nuevo` or apply an invoice. Alias persistence gets its own later guarded write
and immediate database read-back.

## Delivery order

1. Close focused coordinator/service/widget gates, analyzer and the existing
   matcher/OCR/corpus regression suite without weakening legacy assertions.
2. Hot-restart the existing canonical macOS session and inspect 2025-06-07 plus
   two listing-distinct days never used by this AI-first flow, read-only.
3. Record row-level matcher evidence separately from uncertified daily extraction
   coverage; never use database ordinal as alias authority.
4. Re-audit the complete shared dirty tree and ensure no other writer/task is
   active.
5. Only then resume the existing exact-SHA paired release task for Prepare,
   qualification and parallel macOS/Android publication.
