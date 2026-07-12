# Purchase Receiving, Returns, and Credit Notes Standard

**Status:** Architecture implemented and deployed inactive; no tenant workflow is activated
**Rule:** Payment, physical custody, supplier/customer settlement, tax document, and stock disposition are separate events connected by one trace.

## Current Gap

- Purchase receiving is currently a full-quantity `purchase_invoices.status = received` update.
- The distributed application still uses the legacy full-receipt route until an updated build is released and the tenant control is deliberately activated.
- The repository now includes guided receipt, supplier-return, customer-return/disposition, and sales/purchase credit-note workspaces.
- The database documents and commands are installed in production but all four control tables contain zero rows, so installation changed no business workflow or balance.

The existing status toggle must remain in place until the replacement command and UI pass all gates. It must then delegate to the receipt command; it must never remain a second stock writer.

## Document Ownership

| Document | Owns | Must not own |
|---|---|---|
| Purchase invoice | Supplier charge, AP, recoverable tax | Physical quantity received |
| Purchase payment | Cash/bank settlement, invoice balance | Inventory movement |
| Goods receipt | Accepted physical quantity and receipt evidence | Supplier credit or payment |
| Supplier return | Quantity physically returned to supplier | Credit unless a credit note is posted |
| Purchase credit note | Supplier financial/tax correction | Stock unless linked disposition requires it |
| Sales return | Customer-returned physical quantity/disposition | Revenue correction by itself |
| Sales credit note | Revenue/AR/tax correction | Automatic restock without inspected return |
| Inventory loss | Owned stock written off after verified loss/damage | Supplier short-shipment correction |

## Goods Receipt Command

One tenant-scoped, idempotent database command must:

1. Lock the purchase invoice and affected products in deterministic order.
2. Resolve stable invoice line identities and the remaining receivable quantity.
3. Reject negative, duplicate, excessive, service, non-stock, or cross-tenant quantities unless an explicit approved variance path applies.
4. Insert an immutable receipt header and receipt lines containing expected, previously received, accepted, rejected/damaged, and remaining quantities.
5. Increase both stock columns only for accepted stock-tracked quantities.
6. Append exact before/after stock movements connected to the receipt operation and invoice line.
7. Record inspection/discrepancy checkpoints and finish only after invariants pass.
8. Derive invoice fulfilment state from receipts; never infer a receipt merely from payment status.

Multiple partial receipts are allowed. Retrying the same idempotency key returns the original receipt without additional stock.

## Receiving UI

The purchase invoice action becomes `Recibir productos` and opens a guided workspace:

- header: supplier, invoice, warehouse/location, receipt date, delivery reference;
- per line: expected, previously received, default `recibir ahora`, accepted, damaged/rejected, remaining;
- default `recibir ahora` is the remaining expected quantity;
- clear totals and warnings before confirmation;
- explicit discrepancy reason and evidence notes/attachments;
- review step showing exact stock and accounting effects;
- success screen linking the receipt, trace, remaining items, and next resolution actions.

The user can save a partial receipt without pretending the invoice was fully received.

## Discrepancy Resolution

- **Missing/not delivered:** keep as open supplier claim or backorder; no stock and no inventory-loss journal.
- **Damaged/rejected before acceptance:** quarantine or reject; no available stock until accepted.
- **Owned stock subsequently lost/damaged:** traced inventory-loss adjustment and approved balanced journal.
- **Return to supplier:** append a supplier-return document and linked stock reversal for the quantity actually shipped back.
- **Supplier financial correction:** post a purchase credit note referencing the original invoice and affected lines.
- **Over-delivery:** hold as unmatched receipt pending explicit acceptance/invoice correction; never silently increase the invoiced quantity.

## Credit Notes

Sales and purchase credit notes require:

- immutable header/line identifiers, tenant, actor, original document reference, reason, issue date, tax treatment, status, and operation ID;
- draft → approved → posted → voided/reversed lifecycle;
- partial quantities/amounts with cumulative limits against the original document;
- original account/tax context, balanced journals, and append-only reversal evidence;
- an explicit physical-disposition link when stock is affected;
- separate internal and official-DTE states.

The SII workflow requires selecting the original electronic document being modified, and correction notes require a reference reason. An internal Vinabike document must not claim official issuance until it has been signed/sent through an approved DTE path.

## Required Tests Before Activation

- full, partial, repeated, concurrent, backdated, and multi-receipt cases;
- missing, damaged, rejected, over-delivered, service/non-stock, set/component, and cross-tenant lines;
- retry after timeout and duplicate employee submission;
- supplier return with and without later credit note;
- sales return with restock, quarantine, loss, and no-return financial credit;
- full/partial sales and purchase credit notes, cumulative over-credit rejection, void/reversal, and payment-balance effects;
- exact stock chain, dual-column equality, balanced journals, trace completeness, and N/N-1/N-2 client compatibility.

## Rollout

1. Add schema and read-only views with no writer activation.
2. Run production-shaped pgTAP and UI tests.
3. Deploy the idempotent receipt command behind a tenant feature flag.
4. Shadow-compare derived receipt totals without moving stock.
5. Activate the guided UI for one tenant after preflight.
6. Remove direct receipt status writes only after the command is stable and old-client compatibility is handled.
7. Activate one tenant only after a supervised no-surprise smoke; keep previous clients compatible during the observation window.

## Deployed Inactive Implementation

- `purchase_receipts`, receipt lines, and receipt-to-movement mappings preserve one commercial line while recording every physical product/component movement.
- `purchase_supplier_returns`, return lines, and return-to-receipt movement mappings preserve the physical return independently from financial settlement.
- Receipt and supplier-return voids append exact linked reversals; they never delete evidence.
- A receipt cannot be voided while it has a posted downstream supplier return.
- The guided receipt screen is connected locally from invoice detail and list actions. It calls the receipt command only in `enforce`; disabled, shadow, and older pre-schema backends retain the current behavior.
- The supplier-return workspace selects an original posted receipt, shows only stock-backed unreturned quantities, records the physical return separately from financial credit, shows immutable history, and voids through linked stock restoration.
- Compatibility guards leave legacy receipt status behavior untouched while disabled, but block old-client receipt writes atomically once `enforce` is explicitly activated.
- Physical returns own the inventory-value/COGS posting. Linked credit notes own AP/AR, revenue/purchase, and tax settlement and therefore do not duplicate inventory effects.
- Customer quarantine is a valued held-inventory state. Release reclassifies it to available inventory; scrap reclassifies it to verified inventory loss. Both actions and voids remain linked and append-only.
- Production installation on 2026-07-11 preserved all business counts and left zero stock-column drift, zero posting-ledger continuity breaks, zero current-ledger drift, and zero unbalanced journals. Existing negative stock and legacy evidence were not changed.
- The clean canonical database suite passes 528 assertions across 32 files; all 180 Flutter tests and the ERP release web build pass. Activation still requires controlled tenant rollout.

## Primary Tax References

- SII: https://www.sii.cl/factura_electronica/factura_sii/guias_ayuda/nota_credito_corrige_monto_fe.htm
- SII: https://www.sii.cl/factura_electronica/factura_sii/guias_ayuda/nota_credito_anular_fe.htm
