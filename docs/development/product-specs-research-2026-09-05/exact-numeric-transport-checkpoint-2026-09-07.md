# Exact scalar editor transport — applied and verified, 2026-09-07

User scope remains all-family sanitation before any fill. Production product
assignments and facts remain unchanged. The last deployed forward is 20260907010000.

Local edits now preserve numeric input as decimal text, compare scalar bounds
exactly, reject unsafe machine-number magnitudes, and write canonical strings
through the existing aggregate command. Removed the unused Dart legacy writer;
its v1 server endpoint remains intact for old clients. The shared parser now
rejects a very negative exponent before subtracting the fractional scale:
`0.0e-9223372036854775808` previously overflowed native int64. Numeric transport,
relations and rows: **134 tests passed**, log
`.tmp/product-spec-catalog/numeric-transport-tests.log`.

`20260907010000_product_spec_exact_editor_reads.sql` is **APPLIED and verified**
in production at 2026-09-07T07:45:05Z. SHA-256
`8c5603bdf7064532b51515af03e1f1fc70b6183396fbb49c8271fd4ce5cc1e4b`.
Receipt `.tmp/db/migration-receipts/20260907010000.receipt`; immutable forward.
New v2 functions, previous v1 function hashes/ACLs, conditions200 and preserved
product data all passed the executable verifiers and migration-history stamp.

Scalar facts, defaults, min/max and legacy operands now travel as decimal text
from PostgreSQL. Editor facts, template fields and revision share one SQL
snapshot. Category readers and reference readers use v2, with strict DTO checks
and no fallback to v1. The old public functions remain byte-identical.

Final focused evidence:
- 117 pgTAP tests in three files, including 23 new exact-read cases. Local
  reapplication is pinned/idempotent. Log `.tmp/db/spec-exact-reads-final-tests.log`.
- Independent 62 Dart tests: 35 scalar, 20 decoder, seven HTTP Mock boundary
  checks (one v2 request, product/category identity, no imprecise fallback).
  `.tmp/product-spec-catalog/numeric-final-boundary-tests.log`.
- 103 editor/rule integration tests and the previously run relation/rows cases
  remain green. Six authenticated-transport Python tests pass. Focused analyzer:
  zero errors or warnings, 35 infos (style/known module issues).
- Authenticated production read-back: 38 products covering 35 families,
  17 non-null numeric observations/defaults/bounds, plus references for all 35
  families. No errors. Exact report
  `.tmp/product-spec-catalog/authenticated-exact-editor-verification.json`.
- Canonical session payroll, PID90499: hot reload147/5381 libraries, 8.283s;
  refreshed the live fiche using Actualizar ficha. KMC HV408 and the draft
  values remain intact. In the real I-01 input, `1e-` stays visible and is
  invalid; `-7,1` stays visible and fails positivity (not syntax). Restored7.1;
  did not save. Frame `.tmp/product-spec-catalog/runtime-exact-numeric-restored.png`,
  with partial-exponent and negative-comma frames beside it. No Flutter
  exception/failed reload/SpecEngine error in the post-reload log segment.

Scope limit: this closes the **scalar fiche editor**. It does not certify every
consumer (purchase-criteria numeric bounds still use their own double parser),
Dart web runtime, every responsive layout, or mechanical catalogue coverage.
Old mounted drafts/older clients are not a source for recovering already-lost
digits. All-family metadata, product assignments and fill remain separate gates.

Independent numeric review is frozen in
`test/unit/product_spec_numeric_transport_boundary_test.dart` and
`numeric-transport-independent-review-2026-09-07.md`; root owns implementation,
SQL, tests in SQL and integration. Local DB commands must remain serialized.

Claude message 42 has completed in `Diagnóstico fichas técnicas Viñabike`
(Code, Fable 5.1, Ultracode). Delivered
`all-family-field-addendum-2026-09-07.json` SHA-256
`86c7f7d6b7360d01a771f1aaf63ddba0e63352999d65dc4ea78038da58d25440`
and companion MD: 82 proposed patches over eight templates, 48 definitions,
11 row schemas, 20 representation cases. These are **not adjudicated or
integrated**. Important stated gaps: exact OEM identification for most of the
115 affected real products; recipe/photo evidence cannot yet use row URL
provenance. Current catalogue compiler output remains unchanged at
`7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa`.

Claude message43 is now researching addendum-b (ND03/04/05/06/07/08/11/14/15/16/17/18/19/20/24)
against the frozen `.tmp/product-spec-catalog/claude-fields-input-20260907.json`.
It writes only `all-family-field-addendum-b-2026-09-07.json/.md`. Codex may now
integrate the first addendum without altering Claude's input. Independent agent
reviews addendum A in `field-addendum-independent-adjudication-2026-09-07.json/.md`;
root owns compiler and final integration. No file overlaps.

User explicitly used a reset and said continue. Verified Codex0% used afterward,
one reset still available; no reset consumed by the agent. Claude last read:
Fable79% used, shared weekly40% used, 5-hour25% used. Conditional switch to Opus5
is authorized when needed. No percentage is a product-completeness claim.
