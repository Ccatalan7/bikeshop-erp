# Private production-data migrations

The public repository contains schema and non-sensitive regression fixtures;
it does not contain migrations whose assertions embed exact production invoice,
supplier, tenant, price, or cost records.

## Registered private versions

| Version | Status | Public-safe evidence |
|---|---|---|
| `20260811161000` | Applied and registered on 2026-08-11; exact deployed SHA-256 `b8d1444104cede4f250bb834ca852b2a93707e38b9c20dd6af1ef94c8d28321b` | Applied nine owner-reviewed supplier login origins through the metadata-only command; no credential value was embedded or changed. |
| `20260811200000` | Applied and registered on 2026-08-12; exact deployed SHA-256 `886b18450b0a58053aa537b1bc3c8414d68c8bb06238a9cede1f67cd57d80a26` | Created the seatpost-adapter leaf and moved the two reviewed MUQZI variants; stock, accounting, supplier, purchase and alias data were unchanged. |
| `20260812033000` | Applied and registered on 2026-08-12; exact deployed SHA-256 `8defa72838c6b5b6d565b4104b072e637741a4c3ecbd82476c7c4c7b1cf6f4f2` | Created the canonical ENLEE brand and assigned four reviewed products; production health passed. |
| `20260812034000` | Applied and registered on 2026-08-12; exact deployed SHA-256 `c0823d836d2bd71a99046774e0313522de838bae76231d08f4d3b37eb2cc99bb` | Created two reviewed catalog leaves, moved twelve cable products and one applicator, and cleared five false brand assertions; production health passed. |
| `20260812035000` | Applied and registered on 2026-08-12; exact deployed SHA-256 `72cf5421d92d16c7c88f99a6c433f757752606ae2556653f62a3a3f81b1e7b5c` | Deactivated one reviewed duplicate while preserving its canonical identity and historical evidence; production health passed. |
| `20260812041000` | Applied and registered on 2026-08-12; exact deployed SHA-256 `04e8aed639354e4435a29d7b6e5d7540dc9e46d49a474b31e4653717ec4afe5c` | Seeded eight confirmed immutable AliExpress variant identities and ten ordered product/unit/allocation edges. Exact replay was a no-op, live health passed, and no historical invoice source row was staged. |

The exact SQL files are retained only as ignored local evidence under
`.tmp/private-migrations/`. They are immutable after deployment and must not be
reconstructed from this summary. These are tenant-data repairs, not bootstrap
schema. Their reusable schema owners remain public—for example,
`20260811160000_supplier_credential_origin_metadata_command.sql` and
`20260812040000_supplier_variant_resolution_graph.sql` plus their
`core_schema.sql` mirrors. Public pgTAP fixtures use synthetic identifiers and
amounts.

Future data-bearing migrations follow the same split: guarded private SQL and
read-back remain local evidence, while reusable schema, contracts, and
sanitized tests remain reviewable in the public repository.
