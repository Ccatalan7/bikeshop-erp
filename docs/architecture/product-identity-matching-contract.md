# Product identity matching contract

Status: canonical. Owner of «¿este producto ya existe en mi catálogo?» for OCR
invoice reconciliation, bulk product creation, and any future surface that asks
the same question.

Implementation: `AIAssistantService`, `ProductIdentityReviewCoordinator`,
`ProductDuplicateMatcherService` and
`lib/modules/inventory/services/product_identity/`. Regressions:
`test/unit/ocr_product_identity_matcher_test.dart` (production-derived fixture
`test/fixtures/ocr/production_catalog_subset.json`) and
`test/unit/product_duplicate_matcher_service_test.dart`.

Live evidence: [2026-08-11 historical AliExpress audit](product-identity-matching-live-audit-2026-08-11.md).
That end-to-end run is authoritative over isolated harness output when the two
disagree.

## Why this document exists

On 2026-08-09 one seven-line AliExpress invoice was measured against the real
production catalog (1555 active, non-service products). Three lines returned
**no candidate at all** while the correct product sat in the catalog; a fourth
returned **six different hubs, every one of them labelled equally strong**; and
each line cost **550–700 ms of pure CPU** on the UI isolate before any network
call. After the rebuild the original focused harness resolved its configured
probes first at **p50 2 ms / p95 7 ms**, with the catalog analysed once per
session instead of once per line. That was a deterministic engine measurement,
not an end-to-end claim: it disabled the production visual/adjudication path and
did not exercise the AliExpress JSON-to-review boundary.

The failures were not tuning. Each had a structural cause, and each cause is
now a rule below. If a future change makes one of these tests fail, the rule is
what has to be re-argued — not the assertion.

## Authority, investigate, validate, then adjudicate

The old engine ranked everything and used thresholds to bury mismatches. That
is why one line could offer six equally "strong" hubs: nothing had *refused*
any of them. The canonical AliExpress review order is now fixed:

1. **Confirmed authority.** An active immutable supplier-variant resolution is
   applied before AI. A lookup error or malformed authority fails closed.
2. **Primary multimodal investigation.** One model call receives the source
   photo, original supplier title, selected variant, line context and the real
   active leaf list. It returns one structured identity receipt and proposed
   leaf IDs from that offered list. Missing, timed-out, malformed or unoffered
   output abstains; the deterministic engine is not a fallback identity owner.
3. **Complete catalog evaluation.** Every active non-service product is
   evaluated. Exact leaf membership defines the normal pool; plausible identity
   matches outside that exact leaf remain visible as catalog conflicts.
4. **Contradiction gates.** Deterministic extraction may corroborate evidence
   or eliminate a proved family, manufacturer or exclusive-spec conflict. An
   unknown word cannot erase a candidate or become the only identity source.
5. **Grounded adjudication.** A second multimodal pass compares the source with
   every viable normal/conflict candidate and their real images. It returns
   `same`, `different`, `composite` or `insufficient` with typed evidence. A
   negative/insufficient decision also orders its bounded manual-review leads
   closest-first; it does not erase the comparison it just performed.
6. **Human review.** AI output is a cached recommendation, never an automatic
   link or a write. Only confirmed authority can bypass review.

The contradiction gates are:

| Gate | Eliminates when |
|---|---|
| Tipo de pieza | Both sides name a part family and the families differ |
| Medida excluyente | Both state the same exclusive spec with different values |
| Fabricante | Both state a manufacturer and they disagree |

Exclusive specs are the ones that decide whether the object physically fits:
spoke count, rotor diameter, handlebar-clamp and seatpost diameter, BCD, wheel
size, axle width and diameter, freehub standard, valve standard, front/rear,
bottom-bracket shell, brake mount. Each gate records what it checked and what it
found, so the review screen can say *why* — never a percentage.

## What a thing *is* versus what it *fits*

Supplier prose names more than one part. The extractor splits every title into
an **identity** segment and a **fitment** segment, and only identity establishes
what the product is.

- `Volante IXF Integrado Black 170Mm + Motor BSA + Corona 34T` is a crankset.
  Reading `Motor` from the bundled bottom bracket classified it as one and the
  fail-closed gate then deleted the only correct candidate in the catalog.
- `Adaptador Presta a Schrader … adaptador de válvula de neumático` is a valve
  adapter. Reading `neumático` classified it as a tyre.
- `IXF … Compatible con SHIMANO/SRAM` asserts IXF and mentions two others. The
  AI hint returned `Shimano`; accepting it made a Shimano crankset the
  recommended duplicate of an IXF one.

Consequences that are now code:

- a **family** comes from the head noun of the identity segment, resolved
  longest-phrase-first with span consumption, so `espaciador de cassette` is
  found before `cassette`;
- a **brand** found in the identity segment is asserted; found in a fitment
  clause it is compatibility, and never identity. A catalog row's `brand`
  column *is* an assertion — a person chose it — while an OCR or AI reading of
  a supplier title is only a hint until the identity text confirms it;
- a **model code** found only in a compatibility clause is fitment. Two rotors
  that both say `compatible M610 M6000` are not the same rotor.

## A measurement is never a model

`32H` is a spoke count. `104BCD` is an interface standard. `160mm` is a rotor
diameter. All three used to pass the model-code filter because they mix letters
and digits, which is how every 32-spoke hub in the catalog became an "exact
model match" for one purchased hub.

Specifications are extracted **typed and scoped by family**, and their
characters are *consumed*: whatever a typed extractor has explained can never be
re-read as a model code or as a descriptor word. A listing that offers options
(`28/32/36 agujeros`) leaves the property **unknown** rather than picking one.

Only a code printed in the product's own name, or declared in its model field,
may make a candidate `strong`. A generic `ROTOR SHIMANO 160MM` can never
outrank the `RT56` the invoice names.

## A shared code does not beat a contradictory manufacturer

Component makers reuse each other's model strings. `Zoom B01S` and
`Bucklos B01S` are different forks; `Risk DS01S` and `ZTTO DS01S` are different
pad sets. The brand gate has **no model-code escape hatch**: two stated
manufacturers that disagree end the comparison. A genuine rebadge is a decision
for the worker, taken through manual search in the picker.

Conversely, a manufacturer that is missing from `product_brands` must never stop
the matcher from finding its product. `IXF` had no brand row while
`AE0093 Volante IXF` sat in the catalog. Missing brand and missing product are
independent problems, and the review says so in words.

## The photo is primary evidence, not exact variant identity

Vision used to run only when the text named no family at all. That gate was the
defect: a *wrong but non-null* family is the ordinary output of a relational
word, and it looked identical to a correct one. `Herradura de freno V-Brake` is
a rim-brake arm whose title names the system it serves; the head-noun reader
answered `freno`, the gate saw a non-null answer, and the only evidence that
could have corrected it was never consulted.

The source photo is read in the primary structured investigation for every row
that has one. Candidate photos are supplied only to the grounded second pass.
They are reconciled with identity-bearing words and typed variant evidence —
`Calipers` and `Herraduras` are both braking and are different shelves, so
agreeing on the physical class proves nothing.

2026-08-11 correction: a high-confidence visual family must not replace the
only textual family before retrieval. Text and photo create provenance-bearing
hypotheses; retrieval takes their union and any disagreement blocks automatic
linking until resolved. Likewise, an identical URL, byte hash or perceptual
photo is a retrieval channel, not an `exact` verdict. AliExpress commonly reuses
one listing photo across variants, and the live app labelled a 22.2x300 seatpost
as the same product as a front axle. Family/manufacturer/exclusive-spec gates
therefore run before image identity can authorize a match.

## A category is a place for an object, not for a word

The primary investigation receives compact `{id, path}` records for real active
leaf categories and may propose only those exact IDs. The client verifies that
every proposed ID was offered and that its path/version still match the row
receipt. A free-form label, fuzzy leaf name, parent node, inactive node or
invented ID has no authority and makes the investigation insufficient.

The deterministic `ProductCategoryResolver` remains a validator and diagnostic
trace. It can object to a proved contradiction but cannot originate the only
category or force an unknown object into a familiar vocabulary. Two validator
rules remain important, and neither names a product:

- **A relational word is not an identity.** The `freno` in `Herradura de freno`
  is the system served. It reaches the profile as a descriptor and can never
  become the head noun.
- **A parent is never a product's category.** `Componentes / Frenos` has
  children, so it organises a system; it is not a thing on a shelf. That missing
  rule — not a missing synonym — is how a Herradura was filed as Frenos.

If the AI investigation is missing or invalid, the row abstains even when the
deterministic resolver could guess a familiar category. If a valid exact leaf is
proposed, products assigned to that same `category_id` form the ordinary list.
A plausible identity match assigned elsewhere or missing a category is not
admitted into that list and is not lost: it is shown separately as a catalog
conflict for hygiene/review.

## A gate eliminates from the recommendation, never from the view

The row and the picker are not the same question, and answering both from one
list turned an uncertain row into a dead end. The row must be conservative: one
honest recommendation, nothing from another family, no filler. The picker is
opened *because* the operator did not accept that recommendation — so hiding
everything a gate ruled out left two exits, take the wrong product or create a
duplicate of one that already exists. Creating that duplicate is the failure
this whole step exists to prevent.

`ProductDuplicateShortlistScope` names the two questions.
`recommendation` keeps today's floor and limit. `operatorChoice` returns every
retrieved product of the same object family, ranked, each stating its own
verdict — including the ones a gate ruled out, under their own heading, with
the gate's reason in words (`Otro fabricante: Ztto ≠ Giant`). They stay
selectable, because the specification this engine read is sometimes the thing
that is wrong.

## The product's own name outranks the listing body

One AliExpress listing sells every speed from one page. Its body offers
6/7/8/9/10/11/12; the variant the shop bought says one. Reading them all as
equals cancelled the property, and a 12-speed master link was offered as the
match for a 9-speed purchase.

A typed specification found inside the product's **name** — the curated,
identity-bearing field, which carries the chosen variant — is a decision and is
not cancelled by the listing body. A conflict *within* the body still leaves the
property unknown, and once a menu has proved the row states no single value, a
later option cannot quietly become the answer.

`speeds` is an exclusive specification for the same reason spoke count is: a
9-speed link does not close an 11-speed chain.

## Supplier aliases require immutable variant identity

An active, confirmed alias keyed by tenant + supplier + listing + immutable
supplier SKU/option ID or ordered property-ID tuple may resolve directly after
checking that the catalog product remains active. Translated labels, image
filenames and `default` are soft retrieval evidence only; absence of an
extracted option is not proof that a listing has one variant.

Corrections are append-only revisions with active/superseded/revoked state and
a negative edge. A model recommendation cannot recursively become authority
without a later confirmed business outcome.

## One source line may resolve to a product set

`one invoice line -> one product` is not an identity invariant. A Shimano
ST-EF500 3x7 set resolves to left and right catalog components; a BUCKLOS
front+rear caliper set does the same. The resolver may return an ordered product
set with quantities, or abstain when package decomposition is uncertain. It
must not choose one component and silently discard the rest.

Composition and packaging are separate decisions. A primary product shipped
with a subordinate accessory (for example, a hub with its quick release) is
still one catalog identity. A set contains two or more independently stocked
identities and may expand to ordered component quantities. A homogeneous pack
contains repeated units of one catalog identity and may multiply inventory
quantity only after the immutable supplier variant and catalog selling unit
prove the conversion. Supplier quantity alone, listing-menu text and a photo
never authorize either expansion; uncertainty must remain review-only.

2026-08-13 correction: composition uncertainty is not identity uncertainty.
The primary investigation runs before catalog comparison and may correctly
identify an object and exact leaf while being unable to prove whether visible
subparts are independent inventory identities. An internally contradictory
composition is downgraded to `insufficient` composition only; it must not erase
the object, leaf or grounded candidate universe. The later catalog-aware pass
owns `single`, homogeneous-pack and multi-product resolution. This prevents a
provider response such as “one BH59 fitting kit” plus separately described
olive/pin hardware from turning a correctly recognized row into zero results.

When the ordered components exactly equal one active canonical inventory set,
the supplier resolution points to that set parent and the established
`product_set_components` stock kernel owns the eventual expansion. Otherwise a
confirmed supplier graph keeps the ordered ordinary products directly. A
`pair` or `set` token never means two by convention: its independently stocked
components and quantities must be proved by the structured investigation. A
plain `10PCS` option may become one homogeneous edge of ten only after the
catalog selling unit is confirmed as one piece.

The document is resolved as a joint assignment rather than independent row
argmaxes. Distinct immutable supplier variants cannot collapse onto one catalog
row without authoritative evidence, while real repeated purchases of the same
product remain valid. This constraint is evidence-aware, not global uniqueness.

## AI investigates first and adjudicates a grounded universe

The first multimodal call owns the row identity used by the canonical review
path. Its strict receipt includes schema/prompt/model versions, row revision,
catalog/tree versions and listing/variant/image identity. The row and picker use
that same immutable snapshot; opening the picker performs no model call, vision
read or catalog reload. Any identity-bearing edit increments the row revision
and produces one new receipt.

After full-catalog evaluation and contradiction validation, the second call
receives the source image/identity plus all viable normal and catalog-conflict
candidates, their real images and explicit differences. It is not restricted
to a deterministic score band. Its strict result is one of `same`, `different`,
`composite` or `insufficient`; every pick/rejection uses only offered product IDs
and typed basis values (`object`, `function`, `shape`, `model`, `spec`,
`manufacturer`, `image`, `name`, `history`, `cost`). For `different` and
`insufficient`, rejected candidates are ordered from the closest sold object to
the farthest. That order drives only manual review and keeps each decisive
difference visible; it cannot populate recommendations or change the decision.
A missing field, invented ID, invalid basis, inconsistent cardinality, timeout,
malformed response or candidate-budget overflow becomes
`insufficient` without silent truncation or heuristic fallback.

The model's self-reported confidence is descriptive and is never a linking
threshold. The complete evidence path must be calibrated on a locked holdout.

The automatic-link policy accepts only an active confirmed immutable supplier
resolution or an equivalently proven catalog/SKU identity. AI `same` is still a
review recommendation. AI `composite` displays grounded product IDs, ordered
roles and per-purchase quantities and offers no single-product link. When the
line also has an immutable supplier variant and non-conflicting package
evidence, the operator may choose `Usar descomposición`; a blocking confirmation
states the invoice-wide stock effect before the versioned writer persists and
reads back the supplier graph. No AI opinion writes or applies itself. A failure
remains retryable and `abstained`; it never implies `Crear nuevo`.

## A missing deterministic family cannot own or erase identity

`Missinglink` and `Sticker protector` once demonstrated why descriptor overlap
cannot stand in for object identity. In the canonical path, an unresolved
deterministic family does not trigger an early return and does not require a new
synonym before the row can be understood: the structured multimodal identity
still reaches complete catalog evaluation. The missing family merely withholds
that validator gate. If the AI identity is itself insufficient, the row abstains
and manual catalog search remains available.

## Deterministic validator regressions

- **Compound heads split.** `Cortacadena RIDERACE` and `Corta cadena RiderAce
  Negro` are the same tool; without splitting they shared exactly one token and
  the line found nothing.
- **Category ancestry is real.** A product row stores its leaf name
  (`Corta Cadena`) while the hint and the selector speak in ancestors
  (`Herramientas`). The tenant tree supplies the link. A leaf that exists under
  more than one parent — `Adaptadores` lives under three — is **omitted** from
  the ancestry map rather than guessed, because guessing would let a brake
  adapter agree with a valve adapter.
- **Sparse text must not win.** Both the descriptor overlap and the spec
  agreement are symmetric and coverage-weighted. Containment over the smaller
  set rewarded emptiness: a product that states almost nothing matched
  everything it happened to mention and tied with the real answer.

## Cost

- **Profiles are built once per catalog**, keyed by product id plus a signature
  of its identity-bearing fields. The previous engine re-derived every
  product's family and tokens once per invoice line — eleven thousand
  extractions for a seven-line invoice.
- **Every regular expression is compiled once.** Building them inside the
  extraction call recompiled roughly two hundred patterns per product per line,
  which was most of the 550–700 ms.
- **At current scale, retrieval is the full catalog.** The active non-service
  catalog has about 1,555 products and cached deterministic profiles score in
  milliseconds. After an authoritative alias/code fast path, every profile
  reaches the gates; the index may order the picker but cannot omit the gold.
  If measured scale later breaks the latency gate, replace this with a
  recall-asserted union of supplier/listing history, lexical/embedding,
  family+spec and image channels plus a broad fallback before `Crear nuevo`.
  Neither an exact nor perceptual photo bypasses the gates.
- **The source photo is investigated once per row revision.** Comparing it
  independently against each catalog row spent one model call per candidate.
  The primary call now returns display cleanup and structured identity together;
  the add-on's `AI_CLEANED` marker is only a display hint and never an identity
  receipt. The grounded second pass receives candidate images in one bounded
  request. Reopening the picker reuses the cached receipt and adjudication.

## Measured gate

The executable production-derived gate is now
`test/unit/product_identity_live_audit_corpus_test.dart`, backed by 48 diagnosed
regression rows, the current 1,555-product catalog snapshot and the real
134-node production category tree. On 2026-08-12 it admitted every clear gold
to a normal or explicit catalog-conflict scope, retained all three acceptable
ambiguous candidate sets, abstained on both explicit no-catalog rows and exposed
both SKUs for the product-set row. The deterministic text-only track measured
37/42 clear top-1 while vision, immutable aliases and AI were deliberately off;
that gap is evidence for runtime verification, not permission to inject the
gold category or relabel image/listing-dependent rows as text matches.

This is a deterministic regression gate, not proof that unmeasured invoices or
live AI are perfect. The original 40-row version passed immediately before the
first unseen date classified a seatpost shim as a saddle; the next opened date
then exposed fitment/content/subcomponent confusion across six more rows. Once
an unseen row is opened to add vocabulary, category mappings or specs, it
becomes regression data and its entire listing/variant group must be replaced
by another sealed holdout group. A listing-group holdout and live AI off/on
calibration are still required before any non-authoritative auto-link policy can
be enabled.

The holdout must execute the production stages rather than inject the expected
product's category, reuse the observed AI category as truth, or disable visual
and adjudication paths. Report normal recommendation, catalog-conflict and
abstention metrics separately; their union is recall diagnostics, not top-1
accuracy.

Selected variant evidence is ordered after product-line evidence. An explicit
colour mismatch is an exclusive gate between sold variants; an agreeing colour
may break a true line-evidence tie but cannot outweigh model, supplier title,
typed material or publication-photo corroboration. A shared listing/photo is
never exact. Document-level listing consistency may expose a contradiction by
abstaining and reordering manual choices, but cannot create a recommendation or
alias without immutable confirmed provenance. Negative controls must include
listings that legitimately map different options to different catalog rows.

Before the live holdout, run catalog taxonomy closure over every active
non-service AliExpress product: a product on a known leaf must resolve to a
family or an explicit reviewed exception, and every `negativeHead` must be
claimed by another positive family or covered by a refusal regression. This
would have caught `adaptador de tija`: `seatpost` rejected the phrase while no
family owned the resulting object.

`test/unit/ocr_product_identity_matcher_test.dart` asserts focused behavior
against a production-derived subset. The full-catalog harness currently has
nine configured probes, no outcome assertions, and disables production visual
reading/adjudication; a green harness is latency and diagnostic evidence, not an
end-to-end accuracy gate.

`test/unit/product_category_resolver_test.dart` holds the cross-family
regressions: rotor, pastilla, a hub that says «compatible con freno de disco»,
an extractor, a rim tape, the herradura and the seatpost shim. They are a family of cases on
purpose — a single herradura exception would have proved nothing about the rule.

`test/unit/seatpost_adapter_identity_regression_test.dart` replays the exact
2024-12-17 row against all 1,555 identity-only fixture products. The committed
catalog uses synthetic record/tenant IDs, omits supplier and image fields, and
zeroes money while retaining the adversarial catalog-scale identity surface.
With corrected catalog placement it
requires `AE0274` top-1, eliminates `AE0266` by its diameter pair and allows no
saddle in normal/operator choices; with the frozen historical placement it
requires `AE0274` to remain visible only as an explicit catalog conflict.
The canonical macOS replay measured the same effective result: dedicated
`Adaptadores de tija` placement, `AE0274` as the sole normal candidate,
`AE0266` explicitly discarded by the `27.2|30` versus `27.2|28.6` pair, and
zero saddle candidates. This closes the diagnosed regression only; it does not
replace the required sealed listing-group holdout.

`test/unit/ai_first_product_identity_coordinator_test.dart` asserts authority
ordering, offered-leaf validation, full-catalog admission, prompt-injection
isolation, typed adjudication, ablation and fail-closed behavior. Widget gates
assert that row and picker render the same cached decision, that an AI composite
exposes no single-product action, and that only the explicit non-audit
confirmation command can persist its decomposition.

`test/unit/aliexpress_sku_reservation_key_test.dart` drives the reservation
authority against a fake sequence with `Completer`s: two byte-identical rows get
different SKUs, a same-row retry spends no call, concurrent rows serialise, and
a number that reappears is refused rather than shown.

`test/harness/ocr_identity_engine_probe.dart` and
`test/harness/ocr_matcher_baseline.dart` run against a full production-derived
catalog dump; they are not part of the automatic suite because they need that
dump. They must gain assertions and production-like visual/adjudication inputs
before they can guard correctness.

The release gate must also replay the real AliExpress JSON -> ERP parser -> review ->
picker path on dates split by listing/variant group, with aliases both enabled
and masked. It records candidate recall@K separately from top-1, product-set
accuracy, exact category ID, false-new, false-link, abstention, AI calls/cost and
stage latency. Known-existing rows require 100% gold retrieval and zero wrong
automatic links; an honest abstention is valid, an invented duplicate is not.
