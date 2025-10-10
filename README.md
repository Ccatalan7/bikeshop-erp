# Vinabike ERP

Vinabike ERP is a modular back-office platform for bicycle workshops built with Flutter and Supabase. The application covers sales, purchases, inventory, CRM, accounting, and POS workflows while targeting desktop, web, and mobile deployments.

## Sales → Invoices → Payments Flow

The sales module now mirrors the Zoho Books lifecycle: invoices move from `borrador` → `enviado` → `pagado`, supporting partial and full payments. A dedicated payments list keeps all receipts in sync with their source invoices.

### Payment Lifecycle

1. Create or edit an invoice from **Ventas → Facturas**.
2. Open the invoice detail view to review line items, balances, and payment history.
3. Press **Pagar** to launch the payment form. The amount defaults to the outstanding balance and cannot exceed it.
4. Submit the payment to:
	 - Insert a row into `sales_payments`.
	 - Recalculate `sales_invoices.paid_amount` and `sales_invoices.balance`.
	 - Transition the invoice status to `pagado` when total paid ≥ total invoice; otherwise it remains `enviado` (or `overdue` if already vencida).
	 - Generate the accounting journal entry (debit cash/bank, credit accounts receivable) atomically in the same transaction.
5. Navigate to **Ventas → Pagos** to see the global payment feed with realtime updates.

### Database Automations

The Supabase schema (`supabase/sql/core_schema.sql`) now includes:

- `paid_amount` and `balance` columns on `sales_invoices` (back-filled via `ALTER TABLE`).
- `recalculate_sales_invoice_payments(invoice_id)` — idempotent helper that aggregates payments, refreshes balances, and normalises status transitions.
- `create_sales_payment_journal_entry(payment)` and `delete_sales_payment_journal_entry(payment_id)` — bookkeeping helpers that post or remove the double-entry accounting lines bound to the payment id.
- Trigger `trg_sales_payments_change` wired to `handle_sales_payment_change()` to recalc invoices and manage journal entries after `INSERT`, `UPDATE`, or `DELETE` events.

> **Deployment tip:** run the updated `core_schema.sql` (or at minimum the new functions and trigger blocks) in Supabase SQL Editor. The script uses `add column if not exists` guards, so it will extend existing tables without dropping user data.

### Flutter Integration

- **Models:** `Invoice` now exposes `paidAmount` and `balance`; `Payment` remains the payment entity.
- **Service:** `SalesService` orchestrates invoices and payments, subscribes to Supabase realtime changes, recalculates invoice caches after each payment, and exposes helper queries for the UI.
- **UI:**
	- `InvoiceListPage` shows totals, paid amounts, and quick access to the detail view.
	- `InvoiceDetailPage` renders invoice metadata, itemised lines, payment history, and contextual actions (Edit, Send, Pay).
	- `PaymentForm` provides validation, method selection, reference fields, and balance safeguards.
	- `PaymentsPage` lists all receipts with search and deep links back to the originating invoice.

Supabase realtime channels keep invoice and payment views in sync without manual refreshes. All actions share the shared widget system (`MainLayout`, buttons, search) to maintain UI consistency.

## Local Development

1. Configure Supabase credentials in `lib/shared/config/supabase_config.dart` or via `--dart-define` flags.
2. Apply the SQL updates described above to your Supabase project.
3. Run the app with `flutter run -d windows` (or any connected device).

## Contributing

Follow the project guidelines described in `.github/copilot-instructions.md`. When adding modules, remember to register their routes in `lib/shared/routes/app_router.dart` and expose entry points in the main navigation drawer.
