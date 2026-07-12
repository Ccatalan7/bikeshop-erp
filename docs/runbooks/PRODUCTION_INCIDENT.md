# Production Incident Runbook

1. Stop the damaging action or deployment; preserve logs, timestamps, actor and commit SHA.
2. Do not repair data from intuition. Run read-only invariants and identify affected tenant/documents.
3. Decide containment: disable the narrow trigger/action, roll back the app release, revoke a credential, or pause a queue.
4. Take/confirm an independent backup before data mutation.
5. Reproduce the failure in staging and add a regression contract.
6. Preview any repair with exact before/after rows and accounting/stock totals.
7. Apply the smallest reviewed repair, then rerun invariants and smoke checks.
8. Record root cause, timeline, customer/business impact, evidence links and prevention.

Inventory/accounting incidents additionally require stock-ledger continuity, current-stock reconciliation, document lifecycle evidence, balanced journals and payment/credit balances. A green UI alone is not closure.
