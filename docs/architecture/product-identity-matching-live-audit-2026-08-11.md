# Product identity matching: live AliExpress audit, 2026-08-11

Status: read-only production-backed measurement. This report is evidence for
the canonical [product identity matching contract](product-identity-matching-contract.md),
not an implementation claim.

Implementation follow-up, corrected 2026-08-12: the original 40-row replay was
green, but it was a regression set rather than an unseen holdout. The first
unseen date, 2024-12-17, misread a MUQZI seatpost shim as a saddle and offered
saddles in `Buscar parecidos`. The next opened date, 2024-12-20, exposed seven
more rows where sold object, fitment, contained object or visible subcomponent
were confused, and where ruled-out catalog rows were called “8 opciones”. The
two opened dates are now regression rows 41–48; the 39-row table below remains
the original pre-fix runtime baseline and has not been rewritten after the fact.

## Scope and method

The canonical macOS debug session was reused. Ten historical AliExpress
purchase days were opened through `Compras del día`, consolidated with
`Preparar factura`, and handed to the purchase-invoice OCR review. Every row's
recommendation and complete `Buscar parecidos` overlay were inspected. No
candidate was linked, no product was created, no invoice was saved, and no
production row was mutated.

Dates tested:

- 2024-12-26
- 2025-01-01, 01-02, 01-06, 01-10, 01-15, 01-21, 01-24, 01-27 and 01-30

This path does **not** send the generated PDF through Veryfi. AliExpress hands
trusted `structuredInvoiceData` directly to the OCR review; therefore the
findings below isolate source extraction, identity resolution, catalog
retrieval, ranking and category inference rather than document-text OCR.

AliExpress purchase invoices stored in the current production invoice tables
start later than this corpus, so `purchase_invoice_lines.product_id` cannot be
used as historical gold for these dates. Gold was reconstructed conservatively
from exact model/variant evidence, catalog products created immediately after
the corresponding purchase, and candidate/product images. Ambiguous rows stay
labelled ambiguous rather than being forced into the score.

The purchase-day index and the order-detail page sometimes disagree on the
displayed date: for example, 2025-01-02 rows showed 2025-01-19 in detail. The
generator intentionally retained the requested/list date. That discrepancy is
separate from product identity and should be covered by an extraction test.

## What the Claude session changed

The screenshot was taken before the live discrepancy was closed. The relevant
Claude-authored history is:

- `af7906c8`: typed identity extraction, eliminate-then-rank gates, bounded
  catalog index, category/visual reading and the redesigned review flow;
- `6e0af173`: supplier-title precedence, ambiguous-head vocabulary and AI
  adjudication among deterministic survivors;
- `018cb2f3`: map `doble pivote`/`tiro lateral` to the shop's `Herraduras`
  family and restrict AI promotion to a 0.10 engine-score tie band.

The screenshot's outstanding V-brake-noodle result was eventually traced in the
running app to `probeBrand=doble`: `doble` from `doble pivote` was asserted as a
manufacturer, so the brand gate rejected the correct ZTTO product. The current
uncommitted Claude-owned change in `product_identity_extractor.dart` consumes
words already explained by the object phrase before brand extraction and adds
its regression. The June 15 invoice then displayed 6/6. That change was left
uncommitted because this audit did not authorize staging or committing.

Verified locally: 119 focused tests passed, and the deterministic harness
loaded 1,555 products and printed nine configured probes at rank 1 with roughly
p50 1.7 ms / p95 7.3 ms. That harness has no outcome assertions and disables
the live visual/AI behavior, so it cannot certify this workflow.

Static review also found implementation gaps that explain why the screenshot's
fix is too narrow as a closure claim:

- AliExpress retains the raw supplier title in `originalNoisyTitle`, but both
  matching and category flow pass the cleaned description as `sourceTitle`;
- a high-confidence visual family can replace the text family before retrieval;
- `sameImageIdentity` returns `exact` before family/spec/manufacturer gates;
- the AI judge does not receive candidate images/typed specs, ignores returned
  confidence, and treats `id: null` as keeping the original ranking;
- perceptual fingerprints are compared only after textual retrieval and image/
  category changes are absent from the cached index signature;
- opening `Buscar parecidos` constructs a fresh matcher and recomputes the row;
- alias variant keys can fall back to translated labels, image filenames or
  `default` rather than an immutable supplier variant ID.

## Result

There were **39 rows**:

| Outcome | Rows | Meaning |
|---|---:|---|
| Unequivocally correct top-1 | 25 | Source and catalog identity/variant agree |
| Unequivocally wrong top-1 | 9 | A different object/variant wins or the gold is absent |
| Ambiguous | 3 | Catalog duplication or insufficient retained provenance prevents a safe exact judgment |
| No catalog product found | 2 | Two zip-tie variants appear to be operational supplies, not inventory products |

The two scooter-pad listings both receive AE0285 first while the catalog has two
separately created products, AE0284 and AE0285. At least one of those two
recommendations is therefore additionally wrong. Excluding the two lines for
which no inventory product exists, current top-1 accuracy has a conservative
ceiling of **27/37 = 73.0%**. Under the manual gold reconstruction, the correct
identity is present somewhere in the overlay for at least 31/37 rows, while six
resolvable rows never retrieve the needed product or product set. Retrieval and
selection must therefore be measured as different failure modes.

The confidence words are not calibrated safety signals. `Es el mismo` includes
the tija-to-front-axle false match, while `Parecido` covers both exact model
matches and clearly different objects.

## Row-by-row evidence

Legend: `OK` exact/defensible top-1, `WRONG` incorrect top-1, `AMB` unresolved
catalog duplication, `N/A` no inventory product found.

| Date | # | Source identity | Recommendation and inspected alternatives | Verdict |
|---|---:|---|---|---|
| 2025-01-01 | 1 | ZTTO CG-02S chain guide | AE0278 first; AE0249 is a different ISCG05 model | OK |
| 2025-01-02 | 1 | Black zip tie 2.6x200 | No candidates; no corresponding catalog product found | N/A |
| 2025-01-02 | 2 | TOOPRE FR5 black brake levers | AE0279 first; child levers GZ001 second | OK |
| 2025-01-02 | 3 | Black zip tie 3.5x200 | No candidates; no corresponding catalog product found | N/A |
| 2025-01-02 | 4 | Generic black alloy road brake levers | AE0279 TOOPRE first; the catalog gold AE0280 is absent | WRONG |
| 2025-01-06 | 1 | Seatpost 22.2x300 | A front axle is labelled `Misma imagen`; AE0282 gold is rank 3 | WRONG |
| 2025-01-06 | 2 | RISK DS-06S pads | AE0020 first; other DS models follow with explicit objections | OK |
| 2025-01-06 | 3 | M10x14 stainless bushing/adapter | Wheel hub 17180 first; AE0281 gold is absent | WRONG |
| 2025-01-10 | 1 | GOLDIX 175mm, 34T, BSA crankset | AE0283 is the sole offered product | OK |
| 2025-01-10 | 2 | Shimano RT56 160mm | AE0155 first; RT10/RT26/generic rotors follow | OK |
| 2025-01-10 | 3 | ENLEE CR-2 black pedal | AE0276 `Misma imagen`; the red CR-2 is correctly objected to | OK |
| 2025-01-10 | 4 | IXF 170mm, 34T crankset | AE0093 is the sole offered product | OK |
| 2025-01-15 | 1 | Presta-to-Schrader adapter | AE0001 `Misma imagen`; unrelated pumps follow | OK |
| 2025-01-21 | 1 | GIYO GL-09 rear light | AE0288 `Misma imagen`; duplicate GL-09 AE0193 follows | OK |
| 2025-01-21 | 2 | KUGOO scooter pads, four pairs | AE0285 then AE0284; no evidence explains which image/model owns the row | AMB |
| 2025-01-21 | 3 | RISK DS-01S pads | AE0016 first; other DS variants follow with model objections | OK |
| 2025-01-21 | 4 | Xiaomi M365 Pro pads, eight pieces | AE0285 then AE0284, identical order to the KUGOO row | AMB |
| 2025-01-21 | 5 | TOOPRE blue valve-core extractor | AE0286 first; a crank-bolt extractor follows | OK |
| 2025-01-21 | 6 | Deemount Presta F/V 40mm | F/V 60mm AE0046 first; correct 40mm AE0287 is rank 2 | WRONG |
| 2025-01-24 | 1 | T6 front light, 1000lm | AE0322 first; AE0151 is a near-duplicate T6/1000lm catalog row | AMB |
| 2025-01-27 | 1 | GOLDIX K1105 Ti-color pedal | Grey K1105 AE0289 first; black K1105 AE0306 second | OK |
| 2025-01-27 | 2 | ENLEE CR-2 black pedal | AE0276 `Misma imagen`; red and other pedals follow | OK |
| 2025-01-27 | 3 | Shimano RT56 180mm | AE0160 first; 160mm rows are explicitly discarded | OK |
| 2025-01-27 | 4 | G3/HS1 160mm rotor | AE0212 G3 160mm first; generic 160mm rotors follow | OK |
| 2025-01-27 | 5 | Traditional black metal bell | Electronic 125dB horn AE0201 is the only result; AE0290 is absent | WRONG |
| 2025-01-30 | 1 | Shimano RT56 160mm | AE0155 first | OK |
| 2025-01-30 | 2 | RISK missing link 11-speed | AE0099 first; 8/9/10/12-speed rows are discarded | OK |
| 2025-01-30 | 3 | RISK missing link 12-speed | AE0100 first; all other speeds are discarded | OK |
| 2025-01-30 | 4 | RISK missing link 10-speed | AE0098 first; all other speeds are discarded | OK |
| 2024-12-26 | 1 | Five 5mm 1-1/8 headset spacers | A complete stem AE0366 is first; 5mm spacer AE0041 is absent | WRONG |
| 2024-12-26 | 2 | Shimano ST-EF500 3x7 shifter/brake set | No candidates; the identity is a set of AE0031 + AE0034 | WRONG |
| 2024-12-26 | 3 | Black gel saddle | AE0154 `Misma imagen`; other saddles and seatposts follow | OK |
| 2024-12-26 | 4 | BK02/T6 front light | AE0151 first | OK |
| 2024-12-26 | 5 | Padded saddle cover | AE0113 first; cable housings follow because `funda` is overloaded | OK |
| 2024-12-26 | 6 | Front T6 light | An unrelated white safety light is first; likely gold AE0151 is rank 6 | WRONG |
| 2024-12-26 | 7 | BK02/T6 front light | AE0151 first | OK |
| 2024-12-26 | 8 | Black tubeless plug/repair tool | Brake-piston lever 18648 first; catalog kit AE0047 is absent | WRONG |
| 2024-12-26 | 9 | ODI 510185 black grips | AE0101 first; ergonomic ODI and color variants follow | OK |
| 2024-12-26 | 10 | ODI ergonomic lock-on grips | AE0257 `Misma imagen`; other ODI/color variants follow | OK |

The June 2026 six-row case that triggered the preceding Claude work was also
re-read after its reserved-word fix and reached 6/6 recommendations. It exposed
one additional data-model limit: a BUCKLOS front+rear caliper set can only be
represented as either AE0144 or AE0145, not both.

## What the failures establish

1. **Candidate recall is a first-class gate.** AE0280, AE0281, AE0290, AE0041
   and AE0047 are not ranking losses; they never reach the operator.
2. **Image equality is not exact product identity.** A supplier/listing image
   may be reused, stale, copied or variant-generic. The tija-to-axle result proves
   that `sameImageIdentity` must not return before family/manufacturer/spec gates.
3. **Typed variant dimensions work, but only where implemented.** Chain speed
   and rotor diameter behave correctly. Valve length, set composition, product
   role and some dimensions do not.
4. **One invoice line is not necessarily one catalog row.** Shimano 3x7 and
   BUCKLOS front+rear require a product-set/bundle resolution with quantities.
5. **Supplier vocabulary is not commercial brand authority.** `China`, `PRO`,
   `Alligator` and words consumed by a compound noun can become false brands.
6. **Category and identity currently have split authorities.** A bushing becomes
   `Maza`, spacers become `Tee`, a saddle cover enters cable `Fundas`, and a valve
   adapter becomes `Bombines`. Existing-product linkage must inherit the chosen
   catalog product's category; it must not reclassify it from supplier prose.
7. **The AI judge is under-grounded.** It does not receive candidate images or
   typed candidate specs, its returned confidence is ignored, and `id: null`
   does not currently produce abstention.
8. **The row and picker are not one decision.** Opening the picker creates a new
   matcher and can repeat visual/AI work, change ordering and lose reproducibility.
9. **Non-merchandise is a valid outcome.** Consumables such as shop zip ties
   should be classifiable as operational supplies instead of forcing either a
   duplicate product or a new inventory product.

## Post-audit implementation measurement

The original 39 audited rows, the subsequently observed RISK cable-cap row and
a sanitized 1,555-product identity-only catalog were frozen as executable
fixtures. Record and tenant IDs are synthetic, supplier/image fields are
omitted and money is zeroed; raw snapshots remain ignored local evidence. That
40-row regression passed, but the first unseen date
proved it was not a generalization result: 2024-12-17 lacked a typed seatpost
shim family, became `Asiento` and offered saddles. After diagnosis, that MUQZI
row became regression row 41. Seven rows from 2024-12-20 then became rows
42–48; the extra ENLEE CR-2 row is a correct guardian rather than a diagnosed
failure.
The current gate replays them against that deterministic 1,555-product fixture
and the sanitized 134-node category tree without injecting the gold product's
category. It
admits every clear gold to a normal or explicitly labelled catalog-conflict
scope, keeps all three ambiguous sets complete, abstains on both explicit
absences and mixes no off-category product into normal operator choices. Its
text-only track is 37/42 clear top-1 with vision, aliases and AI disabled;
image/listing-dependent ties stay visible for runtime closure instead of being
hidden by a leaked oracle.

The first repaired 2024-12-20 replay also measured a row-independent variant
failure: blue/red ZTTO rows selected `AE0275`, while black selected `AE0123`
from colour alone even though `AE0275` carried the shared publication photo.
Claude's independent review and the code audit agreed this was not a category
or global-weight problem. Colour now gates incompatible variants and only
breaks an exact product-line tie; typed material and the honest reason `Misma
foto de la publicación; no confirma la variante` preserve provenance.
Document consistency is fail-closed: a majority can make a dissenting row
abstain and put the common viable option first, but cannot turn it into a match.
WAKE colour variants and MT200 front/rear are permanent negative controls.

The measured repairs were structural rather than a score-weight change:
supplier title and selected option retain model/variant evidence; category may
fill an otherwise unknown object family but never replace or compete with a
resolved title/photo family; full-catalog gates precede ranking; and narrow
compound families/specs cover only the audited failures. The AI adjudicator is
now multimodally grounded in labelled source/candidate images and typed fields,
but remains review-only and fail-closed. No alias, product or invoice was
written during either the live audit or the replay.

The prior canonical macOS pass regenerated 2024-12-26 and completed all ten
rows returned by AliExpress in that attempt. The spacer overlay placed
`AE0041` first and contained only `Espaciadores`; the tubeless overlay contained
only `AE0047` in `Tripas Tubeless`; and the EF500 abstention retained both
`AE0034` and `AE0031`. The RISK listing was omitted by AliExpress in this final
attempt, although it had appeared as an eleventh row in the preceding pass and
resolved to `AE0360`. The final leaf-category regression proves `Cambios` for
that shift-cable cap rather than the unrelated `Accesorios / Fundas`. No
`Vincular`, `Es este`, `Nuevo`, invoice apply or other production write was
used. It remains valid regression evidence, but not an unseen holdout.

After the taxonomy, diameter-pair and catalog-placement repair, the canonical
macOS session regenerated 2024-12-17. The MUQZI row was categorized as
`Adaptadores de tija`; `AE0274` was the sole normal candidate and appeared
first as `Casi seguro`. The picker kept `AE0266` only in the same-family
discarded section with the measured objection `27.2 ↔ 30 != 27.2 ↔ 28.6` and
contained no saddle. The second invoice row continued to resolve to the purple
ODI grips. No persistence action was used. Runtime closure now requires
replacing the opened holdout with still-sealed listing groups; replaying this
diagnosed row again is only regression evidence.

## Product Identity Resolver V2

The replacement should preserve fast deterministic elimination while making
retrieval, provenance, bundles and calibrated abstention explicit.

### 1. Immutable source evidence

Persist one versioned `SourceIdentityProfile` per row:

- supplier, order ID and line ID;
- listing ID and immutable supplier SKU/option ID or ordered property-ID tuple;
- raw title, selected variant attributes and listing-body text as separate
  evidence sources;
- source quantity, units per purchase and package/set semantics;
- image URL, bytes SHA-256 and perceptual fingerprint;
- typed family hypotheses, asserted manufacturer, compatibility makers, model
  codes, family-scoped specs, uncertainty, conflicts and evidence spans.

The AI-cleaned title must never replace the retained supplier title. One
multimodal observation is cached by image SHA + schema + model version and is
reused for naming, category hints and matching.

### 2. Alias authority

An exact fast path requires tenant + supplier + listing + immutable variant
identity. Human-readable labels, translated option text, image filename and
`default` are candidate evidence only unless the listing is proven single
variant.

Aliases need append-only `confirmed`, `provisional`, `superseded` and `revoked`
states, a source decision, evidence strength, confirmer, matcher version and a
negative edge when corrected. AI output alone never becomes training truth.

Production currently has only six supplier alias rows after many processed
AliExpress invoices. Repair and read back the learning/persistence path before
refining its key; a better schema cannot help if confirmed decisions never
reach it.

### 3. Full-catalog recall now; indexed union only at scale

The active non-service catalog has 1,555 products and the deterministic engine
already evaluates profiles in milliseconds. After an authoritative alias/code
fast path, evaluate the **entire catalog** through the deterministic gates for
each row. Do not cap candidates before family/spec/manufacturer elimination.
The current inverted index may order the picker, but it must not decide whether
the gold is allowed to exist.

Only when measured catalog scale makes the full scan miss the latency gate
should retrieval become an independent union of confirmed aliases/codes,
listing history, lexical/embedding evidence, family+spec postings and
exact/perceptual image channels. At that point every channel reserves slots,
candidate recall is asserted, and a broad fallback runs before `Crear nuevo`.
Do not add BM25/vector/visual ANN infrastructure to solve a 1,555-row problem.
Listing/photo similarity remains evidence, never an exact-identity shortcut.

### 4. Eliminate, rank and resolve bundles

Apply family-scoped hard contradictions to every survivor: exact object family,
asserted manufacturer, model, side, speed, size, interface and the dimensions
owned by that family. Unknown is not agreement. Keep package quantity separate
from identity while supporting outputs of one source line to multiple catalog
products and quantities.

Rank only survivors with transparent reason codes. Model/variant evidence
outranks lexical/category/image similarity. A correct typed pattern should look
like the measured 10/11/12-speed missing-link rows.

Resolve the invoice as a **joint assignment**, not independent per-row argmaxes.
The output maps source lines to zero, one or several catalog products with
quantities. Distinct immutable supplier variants must not collapse onto one
catalog row without authoritative evidence, while genuine repeated purchases
of the same product remain allowed. This is the missing representation behind
both scooter-pad rows and the EF500/BUCKLOS bundles.

An unresolved family is an explicit state, not permission to rank by descriptor
overlap. Request/inspect the image or abstain and expose manual catalog search.

### 5. Grounded multimodal adjudication

Only ambiguous survivors reach AI. The request contains the source image and
profile plus each candidate's authoritative fields, typed specs and image. The
schema requires `same`, `different` or `insufficient`, evidence references,
contradictions and one offered ID or null. AI cannot invent an ID or override a
hard conflict.

Model confidence does not directly authorize linking. Calibrate the complete
decision path on held-out supplier/listing groups. For high-risk ambiguity, a
candidate-order-randomized second pass may be measured; disagreement abstains.

### 6. Decision and observability

Return one of `AUTO_LINK`, `RECOMMEND_REVIEW`, `ABSTAIN`,
`NON_MERCHANDISE`, or `NO_MATCH_AFTER_BROAD_SEARCH`. The row and picker consume
the same cached shortlist and adjudication.

Persist a per-row decision event containing source hash, catalog/index/taxonomy
versions, every retrieved candidate/channel, gate result and rank feature, AI
model/prompt/schema response, final actor/action, alias mutation and invoice-line
read-back. It must answer why a product entered, why another was rejected and
why AI ran.

### 7. Release gate

Freeze this corpus and add unseen dates split by listing/variant group, not by
random row. Run both aliases-enabled and alias-masked tracks. Required metrics:
candidate recall@K, exact top-1/top-3/MRR, bundle accuracy, exact category ID,
false-new, false-link, abstention, per-family confusion, AI calls/cost and stage
latency.

Before automatic linking, require:

- 100% retrieval of the gold identity/product set on known-existing rows;
- zero wrong auto-links and zero false-new outcomes on the locked holdout;
- no hard conflict and agreement between deterministic and AI conclusions for
  non-authoritative matches;
- a calibrated singleton/margin for the relevant evidence path and family;
- a kill switch plus continuing shadow evaluation.

The first release auto-links **only** an active confirmed immutable alias or a
catalog/SKU identity with equivalent provenance. All other outcomes remain
recommendations requiring review. A later locked holdout may earn narrowly
scoped non-authoritative auto-linking family by family; it is not assumed in V2.

Ten days expose structural defects; they cannot prove perfection. The safe
system approaches human accuracy by combining deterministic authority with
multimodal reasoning and honest abstention, not by converting a similarity
score into certainty.

## Independent Claude review and final decision

The active Claude session was given the evidence and proposal with an explicit
read-only instruction. Its independent review agreed on recall as the dominant
failure, removing image bypasses, one cached shortlist/trace, product-set output
and first-class abstention. It also identified concrete current mechanisms:

- `deterministic.isExact` returns before family gates for the image path;
- family retrieval has a 120-row cliff and falls back to family/brand/spec or
  descriptors, so large/unknown families omit the gold;
- valve `lengthMm` is a soft stated difference rather than an exclusive spec;
- picker loading creates a fresh matcher;
- independent row argmaxes cannot express distinct variants or product sets;
- an unknown family silently degrades into descriptor ranking.

Its strongest disagreement was correct for this catalog size: a BM25/vector/ANN
retrieval rewrite is more machinery than a full deterministic scan. The final
decision is therefore **not** to discard eliminate-then-rank. Preserve and
extend the measured-good gate layer, but replace precision-first retrieval with
full-catalog evaluation now, introduce joint document assignment, and defer ANN
until measured scale requires it.

One point remains stricter than Claude's suggestion: even a byte-identical
photo is not exact variant authority. Multi-variant supplier listings reuse the
same bytes; both byte and perceptual identity stay behind the gates. Only an
immutable supplier variant alias or equivalent proven code can take the exact
fast path.

Minimum safe implementation order:

1. neutralize every image exact shortcut;
2. freeze diagnosed rows plus adversarial negative controls, and keep the
   replacement listing-group holdout sealed until it is labelled;
3. add the durable per-row trace and make row/picker share one decision;
4. score the full catalog and measure candidate recall/top-1 again;
5. make unknown family abstain and add missing family-scoped exclusive specs;
6. implement joint assignment and one-to-many quantities;
7. repair alias persistence, then migrate keys/authority/history;
8. enrich multimodal AI and compare it off/on in shadow mode;
9. consider family-scoped automation only after the locked gate passes.
