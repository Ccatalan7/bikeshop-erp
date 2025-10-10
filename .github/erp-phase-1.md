Using `copilot-instructions.md` as global context and the existing scaffolding as the base, continue development to make the app fully usable.

1. Accounting first
   - Generate a complete Chart of Accounts based on standard accounting models (Assets, Liabilities, Equity, Income, Expenses, Taxes). Do not request a predefined list; infer and propose the accounts and codes needed for all app transactions (Sales, Purchases, Payments, Inventory movements).
   - Implement JournalEntry + JournalLine with strict double-entry validation (debits = credits).
   - Add JournalEntryListPage (shows auto + manual entries with source tags).
   - Add JournalEntryFormPage (manual entries, must balance).

2. In-page navigation
   - Ensure all modules (Accounting, Clients, Inventory, Sales, Purchases) are accessible via the sidebar and dashboard.
   - Use in-page navigation only (Dashboard → Module → List → Form → Detail), no redundant submenus.

3. Forms with traceable data
   - Customer, Product, Invoice, Supplier forms must:
     - Save with stable primary keys and references (id, RUT, SKU, invoice_id, supplier_id).
     - Validate required fields and amounts.
     - Maintain referential integrity across modules.

4. POS & business flows
   - Sales: InvoiceFormPage with searchable customer and product selectors; auto post:
     - Debit Accounts Receivable
     - Credit Revenue
     - Credit IVA Débito Fiscal
     - Debit Costo de Ventas; Credit Inventario (for stock items)
     - Deduct inventory quantities; log StockMovement with references.
   - Purchases: SupplierInvoiceFormPage; auto post:
     - Debit Inventario
     - Debit IVA Crédito Fiscal
     - Credit Cuentas por Pagar
     - Increase inventory; log StockMovement with references.

5. Inventory management
   - Every Sale reduces stock; every Purchase increases stock.
   - StockMovement must store product_id, qty, type, source module, and source reference (invoice/receipt).

6. Journal entries
   - Auto-generate JournalEntries for every transaction (Sale, Purchase, Payment, Inventory adjustment) with linked JournalLines and source metadata.
   - Drill-down: clicking an entry shows its lines and cross-module references.

7. Service configuration rule
   - If any external service (Firebase, Supabase, PostgreSQL, etc.) is required before continuing:
     - Pause and clearly tell me what service is needed, why, and provide step-by-step setup guidance.
   - If not strictly necessary, continue development without interruption.

Rules
- Respect Chilean localization (CLP, IVA 19%, DD/MM/YYYY, America/Santiago).
- Add search bars to all long lists (accounts, products, customers, suppliers).
- Use the unified ImageService for product images (upload, cache, placeholders).
- No module is complete until it is routable, usable, and posts to Accounting.
