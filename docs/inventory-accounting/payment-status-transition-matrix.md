# Payment and Status Transition Matrix

**Status:** Implemented, tested, and deployed to production on 2026-07-10
**Rule:** Payment-only actions may change balances, statuses, linked-job paid state, and payment journals. Their inventory delta is always zero.

| Source state/action | Expected invoice result | Job result | Stock | Accounting trace |
|---|---|---|---|---|
| Sales confirmed + partial payment | confirmed; exact paid/balance | linked job unpaid | 0 | one payment journal |
| Sales partial + remaining payment | paid; balance 0 | linked job paid | 0 | one journal per active payment |
| Sales paid + reduce/delete final payment | confirmed; exact remaining balance | linked job unpaid | 0 | replaced/deleted journal snapshot retained |
| Purchase received + any payment/edit/undo | received; exact paid/balance | n/a | 0 | payment journal only |
| Purchase confirmed prepayment + partial | confirmed | n/a | 0 | payment journal only |
| Purchase confirmed prepayment + exact full | paid | n/a | 0 | payment journal only |
| Purchase paid prepayment + reduce/delete final payment | confirmed | n/a | 0 | journal replacement/reversal retained |
| Purchase paid before physical receipt → received | received | n/a | receipt quantity added once | invoice receipt operation, not payment operation |
| Edit/undo uniquely matched legacy purchase payment | status from exact active sum | n/a | 0 | invoice-number journal is snapshotted and replaced by payment-ID journal |
| Edit/undo ambiguous duplicate legacy journal | no mutation; explicit error | n/a | 0 | blocked for discrepancy review |
| Multi-bike job payment | shared invoice-level balance | one job-level `is_paid` flag | 0 | source `mechanic_job_payment`; no per-bike allocation |

Every row requires whole-CLP arithmetic, tenant/actor attribution, an operation ID, before/after source snapshots, balanced journals, and no incomplete trace root.
