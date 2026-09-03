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

## Catalog fit is not purchase evidence (2026-08-25)

The migration from Zoho did not preserve every historical purchase. Therefore
the absence of an ERP purchase line is evidence about this ERP, not evidence
that a product does not exist or cannot satisfy a request.

Purchasing resolves two independent questions in this order:

1. **Eligibility and fit.** Evaluate the complete active catalog using identity,
   category and typed technical specifications. Purchase history cannot remove a
   product from this set.
2. **Sourcing evidence.** For every eligible product, classify what is actually
   known: ERP purchase history, a fresh dated supplier check, a catalog supplier
   assignment, or no sourcing history. Only the first class carries historical
   purchase economics. A fresh supplier check may carry only what that dated
   source proved. A catalog assignment may carry its current catalog cost as a
   labelled `de ficha, no pagado` reference; it is not historical economics and
   never gains a purchase date, participation, landed cost or availability.

An exact product without ERP history stays visible in the same sourcing surface
as the supplier alternatives, inside the first `Exacto` section. `Llevar al
plan` stores a null historical candidate and landed economics, while freezing
the labelled catalog reference in the evidence snapshot. A later
real purchase automatically changes subsequent sourcing reads to the historical
class. The versioned historical writer must compare a nullable prior candidate
with `IS DISTINCT FROM`, replace the same need line, freeze the observed
economics and record `changed=true`; a SQL `NULL` may never strand or abort the
promotion. Already frozen plan evidence remains auditable until that writer
replaces it.

Relaxation is a retrieval aid, not coverage. When an exclusive measurement or
other requested predicate is loosened to find nearby purchase history, those
rows must say they are approximate. They may help identify a supplier to ask,
but they cannot count toward exact line coverage, complete a basket, or replace
an eligible exact catalog product. In particular, a 48 mm valve never covers a
request for 60 mm merely because the shop bought it more often.
In a basket, an uncovered exact product stays named and opens its individual
need for sourcing resolution. Basket non-coverage alone does not prove missing
history: a historical supplier may simply sit outside that scenario's bounded
supplier set. The individual evidence view therefore decides whether to compare
another provider or use the exact catalog row's `Llevar al plan` command. The line remains
outside exact supplier coverage and historical subtotals until it is resolved;
the UI must state that boundary rather than dropping it.

Step summaries preserve that same separation. A visible exact catalog product
plus relaxed historical evidence is counted as, for example,
`1 exacta · 2 similares`; it must never collapse to `0 opciones` merely
because the exact product has no historical candidate.

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

## Cómo escribe el catálogo una medida (2026-08-23)

Salió de llenar la ficha de las 134 cámaras leyendo sus nombres. **Ninguna de
estas convenciones es un nombre pobre: son formas distintas de escribir lo
mismo**, y cada una que falta se traduce en productos sin ficha.

| Convención | Ejemplo | Significa |
|---|---|---|
| Rango con barra | `29 X 1.75/2.35` | 1,75″ a 2,35″ |
| Rango con «a» | `26 X 1.95 a 2.125` | igual |
| Rango con guion | `26X1.95-2.125` | igual |
| **Fracción** | `24 X 1.3/8` | 1‑3/8″ = **1,375″**, no «1,3 a 8» |
| **Ancho único** | `700X28C`, `ARO 29 X 1.95C` | un solo ancho: mínimo = máximo |
| Ruta en mm | `700 X 18/25C` | 18 mm a 25 mm, **no pulgadas** |
| Signo `×` | `20×1.5/2.5` | U+00D7, no la letra X |

La fracción se resuelve **antes** del rango, y sólo si es una fracción de verdad
—numerador menor que denominador, denominador potencia de dos—. Sin ese guarda,
`1.5/2.5` se lee como 1 + 5/2 = 3,5.

El rango se busca **después de la X**: en `12 1/2 X 2.1/4` ese `1/2` es la
medida de aro, no el ancho, y así se esquivan también los códigos ETRTO entre
paréntesis (`(40/63-559)`).

### El neumático se escribe casi igual, con cuatro trampas propias (2026-08-24)

Salió de llenar la ficha de los 113 neumáticos, que tenían **cero**. Las
convenciones de medida son las mismas de la cámara, pero un neumático tiene
**un** ancho y no una banda: `26X2.20` es 2,20″ y punto.

Las cuatro trampas se encontraron en un ensayo en seco **antes** de escribir
nada, y cada una devolvía un valor plausible y equivocado — la peor clase,
porque nadie la vuelve a revisar:

| Trampa | Ejemplo | Qué devolvía | Regla |
|---|---|---|---|
| La X dentro de una palabra | `BMX 20x2.25`, `HARTEX 26 X 2.10` | ancho 20 y 26 —el aro— | el par aro×ancho se lee en **una** coincidencia, nunca la X suelta |
| Dos notaciones en un nombre | `700x32 = 28x1 5/8 x 1 1/4` | 1,625″ en vez de 32 mm | la fracción sólo vale si es del **mismo aro** que el par |
| La comilla como separador | `24x1"3/8` | ancho 1 | la fracción admite `-`, espacio, `.` y `"` |
| El decimal sin punto | `24 X 2 125` | ancho 2 | **no se adivina**: queda sin ancho |

Un ancho escrito en fracción está en **pulgadas aunque el aro sea de ruta**:
`28 X 1.5/8` dice pulgadas, y pasarlo a milímetros sería escribir un valor que
el nombre no da.

### Cuándo el silencio NO alcanza: el caso del talón

En las cámaras el silencio autorizó deducir sellante y material porque dos
señales independientes coincidían **sin un solo desacuerdo**. Para el talón del
neumático se evaluó lo mismo y **se rechazó**:

| | neumáticos | precio promedio | mínimo | máximo |
|---|---|---|---|---|
| plegable (kevlar) | 9 | $33.327 | $19.990 | $54.990 |
| alambre declarado | 20 | $23.973 | $14.000 | $35.000 |
| no lo dice | 84 | $15.660 | $8.490 | **$39.990** |

El promedio separa clarísimo, pero **los techos se solapan**: hay silenciosos
por encima del plegable más barato. Ese solape es exactamente el desacuerdo que
en las cámaras no existía. La regla del silencio necesita las dos señales de
acuerdo, no una señal fuerte: con solape se escribe sólo lo que el nombre dice.

### La válvula se escribe de once formas

`V/AMERICANA`, `V/AUTO`, `V/A`, `VA`, `AV`, `A/V`, `Válvula de auto`, `V.Auto`,
`VAL AUTO`, `SV`, `LSV` — todas **Schrader**. Y `V/FRANCESA`, `V/F`, `VF`, `FV`,
`F/V`, `V.Francesa`, `VAL/FRANCESA`, `FV48`, `LFV` — todas **Presta**. `SV`/`FV`
son la nomenclatura Maxxis (Schrader Valve / French Valve, con `L` de Long).

Dos trampas que costaron una ronda cada una:

- **`AUTO` matchea «AUTOsellante»**, que no dice nada de la válvula. Va
  `AUTO(?!SELLANTE)`.
- **Sin borde de palabra antes de la `V`**, el patrón `V\s*[/.]?\s*A` matchea
  cualquier palabra terminada en «VA»: «cámara nue**VA**» quedaba Schrader, y un
  servicio terminaba con ficha de producto.
- **`AUTOMATICA` es un adjetivo del producto, no la válvula** (2026-08-30).
  RBX vende `CAMARA 700 X 25/38C V/DUNLOP 35MM AUTOMATICA`: el tipo declarado es
  **Dunlop** y la palabra `AUTOMATICA` viene después, describiendo la cámara. Un
  lector que se quede con la palabra en vez del tipo declarado la mete en una
  búsqueda de válvula Auto. Lo que manda es el token de tipo —`V/DUNLOP`—, y una
  contradicción con él elimina, aunque el nombre traiga la palabra.

### «aro 700» es una lectura por marcador (2026-08-30)

Un número suelto no es un tamaño de rueda: `700` puede ser un precio, un código
o una cantidad, y por eso el lector exige contexto dimensional —`700x28`,
`700c`, `29"`—. Pero **`aro`, `rodado` y `rin` nombran el tamaño tan
explícitamente como `V/` nombra la válvula**, y sin leerlos la necesidad real
«Cámaras aro 700 para reposición del taller» no declaraba su medida: la ficha
abría muda y el feed se rejuzgaba como «cualquier cámara».

Es lectura por marcador, no un relajamiento del número suelto: «presupuesto 700
pesos» y «código 700 del proveedor» siguen sin declarar nada.

**El mismo lector lee las dos orillas.** La fila del proveedor y la línea que
escribe el operador describen el mismo objeto en el mismo idioma; tener dos
lectores es cómo «Cámaras 700» quedaba muda mientras `CAMARA 700 X 18/25C` sí se
entendía. Lo único que no comparten son los `capturePatterns`, que pertenecen al
adaptador de un portal concreto y no describen una petición.

### Un valor de la ficha escrito literal es un dato (2026-08-30)

Si el texto trae **una de las palabras que la propia ficha ofrece** —`6 pernos`,
`Centerlock`, `Butilo`, `Aluminio`, `700c`, `3/32`—, eso es el dato. No es un
diccionario nuevo: el vocabulario es el de `allowed_values`, la misma lista que
el desplegable le muestra al operador. Vale para las dos orillas: él escribe
`1/8` y el proveedor titula `Cadena 1/2 X 1/8 Kmc`. Sin esta lectura el criterio
se derivaba y **no eliminaba nada**, porque del lado del catálogo nadie sabía
leerlo.

Tres guardas, medidas contra cuatro fichas reales:

- **Nada que sea puro número** una vez normalizado (`26"` → `26`, `140`, `32`):
  un número suelto puede ser cantidad, precio o código. Una **fracción** sí
  pasa: nadie escribe una cantidad con barra.
- **Nunca los comodines** —`Otra`, `Otro`, `Desconocido`—: son la forma que
  tiene la ficha de decir «no consta», y cazarían cualquier «otro» de una frase.
- **Gana el más largo, y lo contenido en él no es ambigüedad.**
  `rotor_material` ofrece `Acero` y `Acero Inoxidable`; tratarlos como
  contradicción cancelaba un criterio que el texto dice sin ninguna duda.

### Un diámetro ETRTO no es una medida francesa (2026-08-30)

`700x28` y `622x30` tienen la misma forma —tres dígitos pegados al ancho— y no
son lo mismo: el segundo es el código ETRTO, o sea **el mismo aro en
milímetros**. Leerlo como medida entregaba `622`, que no existe en ninguna
ficha, así que contradecía `29"` y sacaba del listado la llanta real
`LLANTA 29 DP-30 NEGRA TR 622X30MM. 32H.` — una exclusión falsa, que es peor que
no saber.

Los diámetros ETRTO de bicicleta son una lista cerrada del estándar (622, 635,
630, 584, 571, 559, 547, 540, 507, 451, 406, 349, 305, 203) y se excluyen de esa
lectura. **No se traducen** a `29"` ni a `700c` porque 622 es los dos: elegir uno
sería inventar. La fila queda sin dato y se revisa. Una medida ajena de tres
dígitos —el `350 X 8` de una cámara de carretilla— conserva su contradicción.

### La pulgada se marca con comillas, y el normalizador se las come

`Alexrims Llanta MD30 SSE 27.5" 28h` dice su aro con todas las letras y llegaba
mudo: el patrón de comillas existía, pero corría sobre el texto ya normalizado,
donde la comilla no está. Se lee del crudo, por el mismo motivo que la fracción.

### Un número es una medida por su contexto, no por su puntuación (2026-08-30)

Exigir contexto dimensional (`700x28`), comillas (`27.5"`) o un marcador (`aro
700`) dejaba mudos los nombres que la tienda escribe de verdad: `LLANTA 26
VISION ALUMINIO`, `Cámaras 29 con válvula Schrader`. Con eso una búsqueda de aro
29 conservaba llantas 26 y 27.5 **que declaran su medida** — obviamente
incorrecto.

Lo que convierte un número en medida es **qué palabra tiene al lado**:

- va pegado al `head` de la familia (`camara`, `llanta`, `aro`, `disco`),
  admitiendo entre medio sólo palabras que no cambian de tema;
- y es uno de los valores que la ficha ofrece para ese campo.

Lo que queda fuera queda fuera **por su contexto**: `presupuesto 700 pesos` y
`código 700` tienen otro asunto entre el sustantivo y el número; `llevar 32
cámaras` lo tiene antes; y `Cámaras 29 unidades` —o `Cámaras 29, unidades`, que
el normalizador entrega como `29 ~ unidades`— lo tiene después. Ese último guard
se aplica **al valor, no al camino**: el extractor de identidad leía la cantidad
como aro igual que la lectura por familia.

Sólo se admite para las medidas que **nombran** el objeto —aro y diámetro de
disco—, nunca para los radios o el largo de la válvula, que se escriben con su
propia palabra (`32 hoyos`, `48mm`); si no, «Aro 24» habría declarado además 24
perforaciones. Y una fila que nombra dos medidas —`CAMARA 700X28C Y 26X1.75
SURTIDO`— no afirma ninguna, aunque una de las dos no exista en la ficha.

### Un booleano se nombra con el vocabulario de su propio campo (2026-08-30)

Un booleano no tiene `allowed_values`, pero sí etiqueta y descripción. Vale la
**frase** de la etiqueta sin sus auxiliares (`trae`, `incluye`, `indica`) ni el
sustantivo de la familia —`Cadena direccional` habría declarado direccional toda
cadena—, cada palabra suya que se sostenga sola, y los **sinónimos que la ficha
enumera antes del dos puntos** de su descripción: `Autosellante o anti-pinchazo:
…`. La prosa posterior no se mina, que es donde vive `pinchazo` a secas — y
«cámara con pinchazo» es una cámara reventada, no una autosellante.

Cortar por número de letras era arbitrario y dejaba mudo `Incluye missing link`,
cuya frase es inequívoca aunque sus palabras sean cortas. Se compara por palabra
completa, nunca por dentro de otra, y la negación se busca en las **dos**
palabras anteriores: `sin líquido sellante` la pone dos atrás.

**Un sinónimo que la ficha no tiene no se cablea.** El operador dirá «quick
link» y el campo se llama «missing link»: la corrección es agregarlo al campo.

### Una palabra que nombra un solo valor lo dice (2026-08-30)

Cuando ningún valor de la ficha aparece completo, sirve una palabra distintiva
que nombre **exactamente uno** de ellos: el taller dice «motor de centro
**sellado**» y la ficha ofrece `Rodamiento sellado`, `Integrado` y `Cubetas y
canastillo`. Sigue siendo vocabulario de la ficha —las palabras son de sus
propios valores— y si alcanza a dos, no elige: `eje cuadrado` no distingue
`Cuadrado JIS` de `Cuadrado ISO`, y eso es no saber.

**`valve_type` queda fuera de esta ruta.** Sus valores traen `Dunlop`,
`americana` y `francesa`, que aparecen en cualquier parte de un nombre —y
`Dunlop` es además una marca: `CAMARA DUNLOP 700X25C` no dice nada de su
válvula—. La válvula se lee sólo de su marcador, y esta ruta habría entrado por
la puerta de atrás a ese contrato.

### Una pareja compacta se reparte por los valores de la ficha (2026-08-30)

`Motor de centro 73 x 118` dice las dos medidas, y tirarlas repetía el defecto de
«Cámaras 700»: un dato explícito convertido en «desconocido» sólo porque no es
una rueda. El reparto **no usa un orden fijo ni una tabla por familia**: 73 es un
ancho de caja y no un largo de eje, 118 es un largo de eje y no un ancho de caja,
así que lo decide `allowed_values`. Por eso funciona también escrito al revés y
en un nombre de catálogo (`Eje De Motor Sellado 68 X 113mm`), y por eso no toca
la rueda: una ficha de cámara no tiene dos campos numéricos con valores donde
repartir `700 x 28`. Si un número calza en dos campos, o los dos en el mismo, no
hay reparto.

### El nombre reconocido no reemplaza a la petición (2026-08-30)

La página derivaba la ficha y armaba la búsqueda desde
`productName ?? description`. En cuanto la interpretación reconocía un producto,
todo lo que el operador había escrito y no cabía en ese nombre dejaba de
existir: el fake realista del propio módulo tiene `Neumático 27,5` como nombre y
`neumático económico 27,5 ancho mayor a 2,0` como petición.

**Las dos fuentes se leen por separado y se fusionan por campo:** igual
conserva, distinto omite, lo que sólo una dice se conserva, y lo guardado manda
sobre todo. Concatenarlas y pedirle a cada extractor que resolviera
contradicciones cruzadas fallaba en las dos direcciones —una palabra del nombre
se pegaba a un número de la petición, y una cantidad de la petición borraba la
medida del nombre—.

### Qué cuenta como una segunda medida

Sólo lo que el contexto **declara** como medida: la lectura dimensional
(`700X28C Y 26X1.75`) o la adyacencia al sustantivo (`cámara 700 … cámara aro
26`). Contar cualquier número permitido que apareciera en el texto borraba el
dato bueno: `Cámara 700, código 26 del proveedor` decía 700 y quedaba mudo.

Y una segunda medida dimensional **no marca ambigüedad por sí sola**: hay filas
cuyo segundo número es una nota de equivalencia y no un surtido —`CAMARA 28 X
1.5/8 … (27X1.1/4)`, donde 28 es la medida—, y eso lo resuelve el extractor de
identidad. Dos medidas pegadas a un sustantivo sí se anulan: ahí las dos están
dichas como medida.

Un booleano se lee igual: **todas sus apariciones tienen que coincidir**.
Quedarse con la primera hacía que «autosellante, la quiero sin sellante»
declarara que sí lo trae.

### Una medida ya asignada deja de competir (2026-08-30)

`Aro 26 36 hoyos` —como se escribe de verdad— dejaba las perforaciones mudas:
con dos números pegados el extractor de identidad no separa cuál es cuál, y con
un `de` en medio (`aro 26 de 36 hoyos`) sí. Una vez que la medida que **nombra**
el objeto tiene dueño, el texto se relee sin ese número y el resto se desempata
solo.

No agrega vocabulario: `hoyos` y `agujeros` ya los conoce el extractor, y la
ficha ni siquiera los nombra —el campo se llama «Número de Rayos /
Perforaciones»—. Y no quita nada: lo que la primera lectura sí encontró se
conserva.

### Identidad, specs y compatibilidad son tres ejes (2026-08-31)

Faltar prueba de calce **no** es ser otra clase de pieza. Colapsarlo en
`product_family` mató las diez filas reales de RBX ante «pastillas para frenos
Shimano BR-MT200»: todas traían `head = PASTILLA FRENO DISCO` y, a la vez,
`is_requested = false`.

- **Identidad** — ¿qué pieza es? La decide el `head` **citado** del proveedor
  contra el vocabulario de la familia, no el veredicto del modelo.
- **Specs** — ¿qué declara? El lector con cita; una ausencia no cumple.
- **Compatibilidad** — ¿calza con el modelo pedido? Es un requisito que se
  **conserva pendiente** mientras nadie lo pruebe, y **nunca elimina por
  identidad**.

Al lector se le pregunta por **el objeto**, no por la petición: pasarle
«pastillas para frenos Shimano BR-MT200, de resina y sin aletas» era pedirle
compatibilidad en el campo de identidad, justo lo que su propio prompt dice que
no debe decidir.

Y el veredicto pierde el veto: `is_requested` no crea contradicción por sí solo.
La exclusión real la sostiene la cita —`CUBETA`, `BIELAS`, `FRENO`, `MANGUERA`
tienen otro sustantivo— y por eso ahora se juzga el `head`, no el texto entero:
`CUBETA MOTOR 34.8` sigue fuera aunque su fila diga «motor».

**Un patín de V-Brake no es otra familia.** La taxonomía canónica agrupa
pastilla, zapata y patín en `brake_pad`. Lo que lo separa de una pastilla de
disco es `brake_type`, que es una **spec** y se lee de su propio nombre.
Excluirlo por identidad sería inventar una familia que el dominio no tiene.

**Una referencia de fabricante se reconoce por su forma** —letras, guion y
dígitos: `BR-MT200`, `BP-B05S-RX`, `SM-RT10`—, no por una lista. Si la petición
la nombra y la fila no la trae, la fila puede listarse pero **no puede ser
exacta**: cumplir dos specs no es calzar con el modelo.

### Lo que la ficha no sabe expresar sigue siendo un requisito (2026-08-30)

Una plantilla no tiene campo para todo. La de rodamientos trae aplicación y
código; la de pastillas, el sistema de freno. Cuando el taller pide «con sello
de goma **a ambos lados**» o «**sin** aletas de refrigeración», ese requisito no
tiene dónde vivir, y durante un tiempo simplemente desapareció del juicio: una
fila que no menciona sellos salía **Exacta** por no contradecir nada.

El eje `requested_property` recoge exactamente eso —lo que la petición exige y
la ficha no absorbió— y se juzga con **cuatro** respuestas, no con una:

| En la fila | Veredicto |
|---|---|
| La nombra con la misma polaridad y el alcance pedido | probado |
| La nombra con la polaridad contraria | contradice |
| No la nombra | **pendiente** |
| La nombra con otro alcance (`en un solo lado` ante `a ambos lados`) | **pendiente** |

**La polaridad es del requisito, no de la fila.** El primer intento sólo miraba
si el proveedor negaba una palabra del pedido, y con eso el juicio quedó
invertido justo donde más importa: pedir `SIN ALETAS` contra un producto `SIN
ALETAS` daba contradicción, y contra uno `CON ALETAS` daba exacto. La negación
además alcanza al sintagma completo —«sin aletas de refrigeración» niega las
tres palabras—, no sólo a la palabra siguiente.

**`X de Y` nombra una sola cosa.** `motor de centro` es el objeto, no un motor
con la propiedad «centro»; `aletas de refrigeración` es una exigencia, no dos.
Sin esa regla cada sintagma del castellano se volvía un requisito extra que
ninguna fila podía demostrar, y nada volvía a ser exacto.

**No hay vocabulario por referencia.** Una palabra entra si es lo bastante
específica, no la aporta la familia, no es trámite ni comparador, y ningún
campo, valor permitido o predicado de la ficha ya la representa. Lo que la ficha
sí sabe expresar se juzga como criterio, con su operador y su cita.

**Atribuir una frase a un criterio pide evidencia positiva, nunca una cuenta.**
El primer intento descargaba una palabra suelta contra un criterio que la
petición no nombraba, suponiendo que el operador lo había escrito con otras
palabras. No se sostiene: **un criterio puede haberse elegido después**, en
`Criterios`, sin reescribir la necesidad. Con esa cuenta, un `Aplicación = Maza`
recién agregado se comía la exigencia «sellados», que no tiene ninguna relación
con él, y `RODAMIENTO PARA MAZA 6902 ABIERTO SIN SELLOS` salía **Exacto**.

Lo que sí liga una palabra a un campo es el **vocabulario**: sus rótulos, sus
valores permitidos y las palabras que el dominio reconoce como el mismo valor.
`kSupplierSpecValueSynonyms` es esa normalización canónica —«resina» y
`Orgánico` nombran el mismo compuesto—, y **sirve para las dos orillas**: sin
ella una petición que dice «resina» no reconoce el criterio que ya la
representa, y una fila que titula `PASTILLA DE RESINA` no demuestra su propio
compuesto. Es equivalencia de **valor**: la ficha sigue siendo la dueña de qué
valores existen, y esto nunca decide qué pieza es una fila.

**El participio y el sustantivo son la misma exigencia.** «Rodamientos
sellados» y «sello de goma» dicen lo mismo, y `ABIERTO SIN SELLOS` contradice a
la primera aunque no repita su palabra. Con una raíz sólo de plural esa
contradicción no se veía y la fila quedaba «pendiente» en vez de contradicha.

**El respaldo de un valor tiene un solo dueño.** Un escalar que viaja con la
fila no prueba por existir: puede venir de un recibo sin cita, o de una lectura
que confundió al **fabricante** con el sistema al que la pieza sirve. Esa
decisión estaba escrita dos veces y las dos copias divergieron: la de la
previsualización no distinguía marca de compatibilidad, así que `MAGURA
CLARA/LOUISE`, `A10YS` y `D40.11` —pendientes en la lista— salían contradichas
al abrir la misma ficha **sin cambiar un solo criterio**. Ahora la calcula
`supplierFactsWithoutBacking`, y la lista, la previsualización y el contador
leen de ahí.

Y el eje se comporta como los otros dos: **cualquier** requisito pendiente
—familia, compatibilidad o propiedad pedida— impide llamar cumplida a la fila,
en la lista, en la previsualización y en el contador. Antes sólo la
compatibilidad tenía ese poder.

### Dónde está escrito cada criterio, leído y no adivinado (2026-08-31)

Los criterios salen de la petición, pero al guardarlos se pierde con qué
palabras los escribió el operador: queda `Compuesto = Orgánico` y ya nadie sabe
que eso se pidió «de resina». Sin ese vínculo el eje de requisitos vuelve a
exigir la palabra literal y cuenta dos veces lo mismo.

Una lista de sinónimos sólo conoce las palabras que alguien alcanzó a escribir,
y el objetivo es entender peticiones nuevas. El lector que ya lee la fila de un
proveedor lee ahora también la petición, y responde **una sola** pregunta: en
qué palabras está escrito un criterio que ya existe. Se verifican cinco cosas:

1. la cita está **literal** en la petición;
2. el campo tiene un **criterio vigente** —no puede crear uno—;
3. el valor leído es **el mismo** que el operador pidió;
4. la cita **no nombra otro campo** de la ficha, según el vocabulario de la
   propia ficha —en «… de resina y sin aletas», `Orgánico` citando «sin aletas»
   pasaba los tres primeros y habría borrado la exigencia equivocada—;
5. `relation = same`: la ficha dice **lo mismo**, no una familia que lo
   contenga. «De kevlar» o «titanio» son más específicos que `Orgánico` o
   `Metálico`; descargarlos dejaría el compuesto demostrado y la fibra no.

**Lo que esto NO prueba, dicho sin adorno.** La cita literal impide inventar
texto; no impide una conclusión equivocada sobre texto real. Un modelo puede
responder `same` cuando no lo es, o citar una frase verdadera que no sostiene su
conclusión, y ninguna de las cinco lo detecta. Lo que sí está acotado —y
demostrado por regresión— es el daño: un tramo aceptado **remite** la exigencia
al criterio que la representa y **nunca lo da por demostrado**. Con el mismo
tramo aceptado y una fila que no prueba el compuesto, la fila sigue sin ser
exacta. Por eso esta lectura sólo puede descargar lo que ya se está juzgando, y
por eso cualquier fallo —sin modelo, lento, sin cuota, respuesta ilegible— vuelve
con cero tramos y el juicio sigue con el vocabulario de la ficha.

`kSupplierSpecValueSynonyms` queda como respaldo sin conexión, no como
autoridad.

### Lo que la IA aporta, y hasta dónde llega (2026-08-31)

La ficha no puede preguntar por todo. Para lo que queda fuera —«sellados», «a
ambos lados», «de gel», «3/32», «no cassette»— el módulo usa el mismo lector que
lee la fila de un proveedor, con dos preguntas y una regla de presentación.

**Qué se le pregunta.** Primero, sobre la petición: *dónde está escrito cada
criterio vigente* y *qué exige este texto que la ficha no representa*. Se le da
el texto **completo**, tal como lo escribió el taller, y la lista de lo ya
representado. La extracción determinista filtra por largo, descarta dígitos y
absorbe sintagmas —cada filtro por una buena razón— y aun así deja caer
exigencias antes de que nadie las lea: `gel` por corta, `3/32` por numérica. Lo
que el lector encuentra se **une** a lo determinista; no lo reemplaza, así que
sin modelo el juicio sigue siendo el de siempre. Segundo, sobre cada fila: qué
dice el proveedor de esas exigencias. La exigencia viaja entera —frase del
taller, polaridad, dimensión y alcance—: preguntar por `3` en vez de `3/32` no
es una pregunta que nadie pueda contestar.

**Qué se verifica, y qué no.** La cita tiene que estar literal en el texto que
la origina —petición o fila—, el campo tiene que existir en la ficha, el valor
tiene que ser el que el operador pidió, la cita no puede nombrar otro campo, y
`relation = same` distingue un sinónimo de una familia más amplia. Nada de eso
impide que el modelo se equivoque **dentro** de esos límites: puede responder
`same` cuando no lo es, o citar una frase real que no sostiene su conclusión. La
cita literal impide inventar texto, no una conclusión equivocada sobre texto
real.

**Por eso la frontera es de producto, no de detección.** En la fila se separa
por **cómo se sabe**: lo dice el proveedor, el proveedor dice lo contrario,
leído por IA sin confirmar —con su cita, para poder desmentirla—, la IA lo duda,
o no consta. Una lectura afirmativa nunca se dibuja como cumplimiento; una
negativa que el código no puede corroborar sobre las palabras citadas es una
duda y **no descarta la fila**, porque un producto válido perdido por una
inferencia no vuelve. Y la evidencia directa manda siempre: si el texto del
proveedor lo dice, eso decide.

**Una lectura pertenece a su pregunta, y ninguna parte suelta la identifica.**
Se guarda con la exigencia **completa** —la frase del taller, el término, la
dimensión, la polaridad y el alcance—. El término no basta: «resistente al agua»
y «resistente al calor» comparten `resistente`, polaridad y alcance. La
polaridad tampoco: «puños **con** gel» y «puños **sin** gel» comparten palabra y
frase. Y la frase es además lo que el lector recibe y usa para interpretar, así
que es parte de la identidad de la pregunta, no un rótulo. Un recibo que no dice
qué pregunta contestó no reclama ninguna: la exigencia queda desconocida.

### Buscar no depende de la ficha ni de la categoría (2026-08-31)

Tres necesidades reales de producción —«Motor Sellado 73x118mm», «Puños con
gel», «Sellante tubeless»— quedaron con `identity_unresolved`, sin categoría y
sin familia técnica, y con eso **no se podía ni preguntarle al proveedor**: el
plan devolvía `null`. El extractor canónico sí reconoce `bottom_bracket`, `grip`
y `sealant` en esas mismas palabras.

La familia se deriva de la petición. La plantilla aporta los criterios y la
categoría aporta su sustantivo **cuando existen**; ninguna de las dos es una
precondición para buscar. Sin ficha no hay criterios que juzgar —y eso es lo
honesto—: se busca por la palabra y la identidad se prueba con el vocabulario de
la familia, que es exactamente lo que haría el operador. Una petición que no
nombra ninguna familia sigue sin plan: ahí no hay palabra que preguntar.

### Un ancho es una medida, no una lista

45 pares distintos de ancho en 120 cámaras, y crecen con cada compra. Pero la
razón para que sea numérico no es la cantidad: con números, «¿esta cámara sirve
para un neumático 2.1?» se contesta con aritmética. Con una lista de texto,
`1.95/2.125` nunca calzaría con `1.95 a 2.125`.

### Cuándo el silencio del nombre es evidencia

La regla que decide si un default es legítimo:

- **Lo es** cuando el dato, si existiera, se diría. Una cámara con sellante
  siempre se vende diciéndolo —es lo que justifica el precio—, así que no
  mencionarlo es evidencia de que no lo trae. Corroborado con dos señales
  independientes: 8 lo declaran en el nombre, la categoría «Cámaras
  Anti-Pinchazo» tiene 4, y esas 4 están entre las 8.
- **No lo es** cuando el dato existe igual. Una cámara tiene un largo de válvula
  aunque el nombre lo omita: ahí vacío es la verdad y rellenar sería inventar.

Y un producto que no entrega **ninguna** medida no recibe ficha: «Cámara nueva +
servicio de cambio» es un servicio, y «Camara Para Carretilla 3.50 X 8» no es de
bicicleta.

## El nombre del producto como evidencia verificada

**Medido el 2026-08-31 sobre el catálogo real:** 1.613 productos activos, y
sólo 45 con descripción de más de veinte caracteres. La ficha del taller está
casi vacía, y lo único escrito es el nombre. Antes de esto, un lector
determinista sólo resolvía un campo cuando la palabra pedida aparecía literal,
así que `METALICA` no contradecía `Orgánico` y familias enteras quedaban sin
verificar por silencio en vez de por desacuerdo.

Un modelo sí puede leer ese nombre. Lo que no puede es que se le crea, y el
dueño de esa decisión es **el servidor**, no el cliente: el cliente es la parte
que podría estar equivocada o mentir.

- **La procedencia es `name_reading`**, un token propio. Cada consumidor que
  pregunta `in ('product_spec', 'identity_fallback')` lo ignora hasta que se lo
  habilita explícitamente. Habilitarlo es un acto auditable, no un efecto
  colateral: `assistant_search_inventory_v*` sigue ignorándolo a propósito.
- **La cita tiene que distinguir el valor, no repetir la etiqueta.** La
  comprobación puntúa `(palabras cubiertas / palabras de la etiqueta, palabras
  cubiertas)` y exige que el valor elegido le gane estrictamente a todos sus
  hermanos. Sale de dos formas reales de etiqueta que la cobertura completa
  rechazaba: `Ecosistema Shimano` trae una palabra clasificadora que ningún
  proveedor escribe, y `SGS / larga` escribe dos formas de decir lo mismo. Con
  cobertura completa, las siete lecturas honestas probadas contra el catálogo
  real murieron junto con las falsas.
- **Una palabra corta no tolera flexión.** Con dos o tres letras se exige
  igualdad exacta: `SGS` no prueba `SS` ni `GS`, que es justo lo que hay que
  distinguir. Con cuatro o más se compara por prefijo común, porque el español
  flexiona el final: `METALICA` sí prueba `Metálico`.
- **El booleano se lee, no se rechaza.** Un nombre que dice `SIN ALETAS` prueba
  la ausencia tanto como `CON ALETAS` prueba la presencia; lo que no prueba nada
  es un nombre que no la menciona. La regla es la que ya existía en
  `supplierBooleanFromFieldVocabulary`, y el vocabulario sale de la etiqueta y
  la descripción del propio campo.
- **Una lista (`multi_select`) se rechaza entera.** Leída de un nombre es casi
  siempre parcial: `RD-M2000 9-SPEED` declara el 9 y calla el 8, y con media
  ficha un cassette de 8 pasaría a «no cumple» cuando la verdad es «el nombre no
  lo dice». Media ficha fabrica contradicciones; ninguna sólo deja silencio.
- **La evidencia caduca sola.** El recibo guarda el digest del texto leído y el
  del vocabulario del campo —etiqueta, tipo, descripción y valores activos—.
  Cambiar el nombre del producto, renombrar la etiqueta elegida o agregar un
  valor hermano más específico invalidan la lectura sin que nadie tenga que
  acordarse de borrarla.
- **La persona gana de verdad.** Una lectura nunca pisa un dato de otra
  procedencia, y el guardado manual recupera `source` y retira el recibo. Los
  dos que escriben la ficha de un producto toman el mismo candado
  —`pg_advisory_xact_lock` por producto, no por campo— y el manual lo toma
  **antes** de vaciar los campos omitidos: si no, una lectura en vuelo
  reinsertaba justo el criterio que la persona acababa de vaciar.

Lo que esto **no** arregla: el techo sigue siendo lo que el nombre dice. En las
49 pastillas del taller sólo 4 nombran el compuesto y 2 el disipador, así que
esa necesidad sigue sin alternativas comprobadas — y eso es la respuesta
correcta, no una falla. Su valor real ahí es convertir silencio en
contradicción: una pastilla `METALICA CON DISIPADOR` deja de ser «no verificada»
y pasa a decir por qué no sirve.
