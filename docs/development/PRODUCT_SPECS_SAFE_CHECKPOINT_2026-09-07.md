# Product specifications: release checkpoint, 2026-09-07

This release includes the implemented specification contract, atomic product/spec saves,
identity and template revision boundaries, retained legacy observations, exact numeric
transport, scoped relations, structured rows, row conditions, coherence and applicable
row cardinality. Server migrations through `20260907026000` were applied and read back.
The existing product editor and compatibility consumers use this shared boundary.

Validation before release preparation: 1,265 PostgreSQL assertions across 23 files,
515 focused Dart checks, and 323 proposed-catalog cases passed. The preserved native
session accepted the reload. Release qualification must still certify the exact commit.

The expanded 105-template catalogue remains a proposal. The full-catalogue adoption
simulation found no blocking populated-value conflicts for currently assigned products;
it still reports missing information, unassigned products and retained legacy fields.
This is not mechanical certification of every family. No bulk product filling or new
catalogue activation is included. Complete global sanitation and evidence-backed
research remain prerequisites to that later rollout.

The historical research, inventory snapshots and backup remain in the private working
folder. Only generic contract/catalogue fixtures needed by automated tests are included
here. The working checkout and canonical native session remain independent from this
isolated release copy.

The paired release also includes the completed OCR review, supplier-intake, image-drop,
amount validation and shared-control changes present at this checkpoint.

Regression boundary: an absent value makes the legacy `is_set` condition false,
so populated dependent fields produce a blocking applicability issue. Numeric
domain tests must retain that guard rather than expect an unknown prerequisite.
