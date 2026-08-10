# Product identity matching contract

Status: canonical. Owner of «¿este producto ya existe en mi catálogo?» for OCR
invoice reconciliation, bulk product creation, and any future surface that asks
the same question.

Implementation: `lib/modules/inventory/services/product_identity/` plus
`ProductDuplicateMatcherService`. Regressions:
`test/unit/ocr_product_identity_matcher_test.dart` (production-derived fixture
`test/fixtures/ocr/production_catalog_subset.json`) and
`test/unit/product_duplicate_matcher_service_test.dart`.

## Why this document exists

On 2026-08-09 one seven-line AliExpress invoice was measured against the real
production catalog (1555 active, non-service products). Three lines returned
**no candidate at all** while the correct product sat in the catalog; a fourth
returned **six different hubs, every one of them labelled equally strong**; and
each line cost **550–700 ms of pure CPU** on the UI isolate before any network
call. After the rebuild the same seven lines resolve **first, every time**, at
**p50 2 ms / p95 7 ms**, with the catalog analysed once per session instead of
once per line.

The failures were not tuning. Each had a structural cause, and each cause is
now a rule below. If a future change makes one of these tests fail, the rule is
what has to be re-argued — not the assertion.

## Eliminate, then rank

The old engine ranked everything and used thresholds to bury mismatches. That
is why one line could offer six equally "strong" hubs: nothing had *refused*
any of them. The order is now fixed and non-negotiable:

1. **Gates.** A candidate that fails one is eliminated and never displayed.
2. **Ranking.** Only survivors are ordered.
3. **Shortlist policy.** Only useful survivors are shown; a top-k is never
   padded. An empty list is an honest answer.

Gates, in order:

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

## The photo is evidence, and text cannot silence it

Vision used to run only when the text named no family at all. That gate was the
defect: a *wrong but non-null* family is the ordinary output of a relational
word, and it looked identical to a correct one. `Herradura de freno V-Brake` is
a rim-brake arm whose title names the system it serves; the head-noun reader
answered `freno`, the gate saw a non-null answer, and the only evidence that
could have corrected it was never consulted.

The photo is now read for every product that has one, and reconciled against
the words at **family** level — `Calipers` and `Herraduras` are both braking and
are different shelves, so agreeing on the physical class proves nothing. Three
bands, in `ProductIdentityProfile`:

| Visual confidence | What happens |
|---|---|
| below 0.35 | the photo is not evidence; the words stand |
| 0.35 – 0.6 | a contradiction sends the row to review |
| 0.6 and above | the photo overrules the head noun |

## A category is a place for an object, not for a word

`ProductCategoryResolver` runs before any hint. It establishes the object, maps
it to the leaves that family may occupy, and matches those against the tenant's
real tree. Two rules do the work, and neither names a product:

- **A relational word is not an identity.** The `freno` in `Herradura de freno`
  is the system served. It reaches the profile as a descriptor and can never
  become the head noun.
- **A parent is never a product's category.** `Componentes / Frenos` has
  children, so it organises a system; it is not a thing on a shelf. That missing
  rule — not a missing synonym — is how a Herradura was filed as Frenos.

When the object is unknown, the evidence conflicts, the family has no leaf in
this tenant, or two unrelated branches answer to the same leaf name, the
resolver **refuses in words** and the row goes to review. A plausible wrong leaf
is the outcome it exists to prevent. `Adaptadores` living under three parents is
refused for exactly this reason, and only then does the catalog semantic
resolver get to answer.

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

## A family that is missing is a family that cannot eliminate

`Missinglink` and `Sticker protector` were not in the taxonomy. Neither side of
the comparison had a family, so the family gate never fired, and a chain
*sticker* that shared the brand and the word `cadena` became the top candidate
for a master link. The gap was not in the ranking; the object simply had no
name. Adding a family is therefore a correctness fix, not a convenience, and a
head noun the shop actually writes belongs in `BikePartTaxonomy` before anything
downstream can reason about it.

## Words the shop actually writes

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
- **Retrieval is bounded.** A line is scored against a shortlist selected by
  shared evidence — supplier code, listing id, image identity, model code,
  family combined with brand or a decisive measurement — capped at 120, never
  against the whole catalog. Deterministic evidence enters unconditionally, so a
  shared SKU or the same photo reaches the matcher even when the two titles have
  no word in common.
- **The photo is read once per image, not once per candidate and not twice per
  row.** Comparing the invoice image against each catalog image cost one model
  call and one download per candidate per line — up to twenty-one vision calls
  and over a hundred downloads for one invoice, all between the operator and
  their first decision. One structured reading per distinct image, cached by
  canonical image identity, replaces it. The title cleaner already sends that
  same photo, so it returns the object reading in the *same* call and hands it
  over (`primeVisualReading`); asking a second time doubled latency and quota
  for an answer already paid for.

## Measured gate

`test/unit/ocr_product_identity_matcher_test.dart` asserts, against real
catalog rows: top-1 and top-3 on all seven lines, **zero** candidates from a
different physical class, p95 under 150 ms per line without network (measured
~7 ms), and zero AI calls when visual reading is not needed.

`test/unit/product_category_resolver_test.dart` holds the cross-family
regressions: rotor, pastilla, a hub that says «compatible con freno de disco»,
an extractor, a rim tape and the herradura. They are a family of cases on
purpose — a single herradura exception would have proved nothing about the rule.

`test/unit/ocr_single_vision_reading_test.dart` asserts the AI budget: one call
carries both the name and the object reading, a reading obtained without a photo
is refused, and a primed reading costs zero model calls.

`test/unit/aliexpress_sku_reservation_key_test.dart` drives the reservation
authority against a fake sequence with `Completer`s: two byte-identical rows get
different SKUs, a same-row retry spends no call, concurrent rows serialise, and
a number that reappears is refused rather than shown.

`test/harness/ocr_identity_engine_probe.dart` and
`test/harness/ocr_matcher_baseline.dart` run the same seven lines against a
full production-derived catalog dump; they are not part of the automatic suite
because they need that dump, and they are how a future change is re-measured
rather than re-argued.
