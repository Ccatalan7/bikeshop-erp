import { execFileSync } from "node:child_process";

const fixtureProductId = "e2e00000-0000-4000-8000-000000000101";
const paymentFixtureInvoiceId = "e2e00000-0000-4000-8000-000000000201";

function runDatabaseCommand(args: string[]) {
  return execFileSync("bash", ["scripts/db/query.sh", "staging", ...args], {
    cwd: process.cwd(),
    encoding: "utf8",
    env: {
      ...process.env,
      VINABIKE_DB_WRITE_CONFIRM: "staging",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

export function resetStagingInventoryFixture() {
  runDatabaseCommand([
    "--file",
    "scripts/e2e/reset_staging_fixture.sql",
    "--write",
  ]);
}

export function readStagingFixtureStock() {
  const output = runDatabaseCommand([
    "--sql",
    `select inventory_qty::integer as stock from public.products where id = '${fixtureProductId}'`,
    "--format",
    "json",
  ]);
  const rows = JSON.parse(output) as Array<{ stock: number }>;
  if (rows.length !== 1) {
    throw new Error(
      `Expected one staging fixture product, found ${rows.length}`,
    );
  }
  return Number(rows[0].stock);
}

export interface PaymentFixtureState {
  status: string;
  total: number;
  paid: number;
  balance: number;
  activePayments: number;
  paymentJournals: number;
  paymentStockMovements: number;
  incompleteOperations: number;
}

export function readStagingPaymentFixture(): PaymentFixtureState {
  const output = runDatabaseCommand([
    "--sql",
    `
      select
        invoice.status,
        invoice.total::integer,
        invoice.paid_amount::integer as paid,
        invoice.balance::integer,
        (count(distinct payment.id) filter (where payment.id is not null))::integer as active_payments,
        count(distinct entry.id)::integer as payment_journals,
        count(distinct movement.id)::integer as payment_stock_movements,
        (count(distinct operation.id) filter (
          where operation.outcome is distinct from 'completed'
        ))::integer as incomplete_operations
      from public.sales_invoices invoice
      left join public.sales_payments payment
        on payment.invoice_id = invoice.id
       and payment.deleted_at is null
      left join public.journal_entries entry
        on entry.source_module = 'sales_payments'
       and entry.source_reference = payment.id::text
      left join public.inventory_accounting_operations operation
        on operation.document_type = 'sales_payment'
       and operation.document_id = payment.id
      left join public.stock_movements movement
        on movement.operation_id = operation.id
      where invoice.id = '${paymentFixtureInvoiceId}'
      group by invoice.id
    `,
    "--format",
    "json",
  ]);
  const rows = JSON.parse(output) as Array<{
    status: string;
    total: number;
    paid: number;
    balance: number;
    active_payments: number;
    payment_journals: number;
    payment_stock_movements: number;
    incomplete_operations: number;
  }>;
  if (rows.length !== 1) {
    throw new Error(
      `Expected one payment fixture invoice, found ${rows.length}`,
    );
  }
  const row = rows[0];
  return {
    status: row.status,
    total: Number(row.total),
    paid: Number(row.paid),
    balance: Number(row.balance),
    activePayments: Number(row.active_payments),
    paymentJournals: Number(row.payment_journals),
    paymentStockMovements: Number(row.payment_stock_movements),
    incompleteOperations: Number(row.incomplete_operations),
  };
}
