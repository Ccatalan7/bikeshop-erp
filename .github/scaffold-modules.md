# 🚀 ERP Scaffolding Master Prompt

**General Instruction:**  
Use `copilot-instructions.md` as the single source of truth.  
Scaffold the following modules **in order**:  
1. Accounting  
2. Clients (CRM)  
3. Inventory  
4. Sales  
5. Purchases  

For each module:  
- Create the folder structure under `lib/modules/[module]/`  
- Implement models, services, pages, and widgets as specified  
- Integrate the module into the main navigation (drawer/sidebar + dashboard shortcut)  
- Ensure Chilean localization (CLP currency, IVA 19%, DD/MM/YYYY, America/Santiago timezone)  
- Follow the GUI design system, search/filtering rules, and image handling rules  
- No module is considered complete until it is visible and accessible in the app navigation  

---

## 🧮 1. Accounting Module

**Folder:** `lib/modules/accounting/`

**Models:**
- Account (id, code, name, type [Asset, Liability, Equity, Income, Expense], parent_id)  
- JournalEntry (id, date, description)  
- JournalLine (id, entry_id, account_id, debit, credit)  

**Services:**
- AccountingService: createAccount(), getChartOfAccounts(), createJournalEntry(), postTransaction(), getLedger()  

**Pages:**
- ChartOfAccountsPage (tree view of accounts)  
- JournalEntryListPage (list with filters)  
- JournalEntryFormPage (form with debit/credit validation)  

**Widgets:**
- AccountTreeWidget  
- JournalEntryCard  
- LedgerTable  

**Rules:**
- Preload Chilean Chart of Accounts (Assets, Liabilities, Equity, Income, Expenses, Taxes)  
- Enforce double-entry (debits = credits)  
- All other modules must post into this ledger  

---

## 👥 2. Clients (CRM) Module

**Folder:** `lib/modules/crm/`

**Models:**
- Customer (id, name, RUT, email, phone, address, bike_history)  
- Loyalty (id, customer_id, points, tier)  

**Services:**
- CustomerService: addCustomer(), updateCustomer(), getCustomers(), getCustomerHistory()  
- LoyaltyService: addPoints(), redeemPoints(), getLoyaltyStatus()  

**Pages:**
- CustomerListPage (searchable, filterable)  
- CustomerFormPage (add/edit)  
- CustomerDetailPage (profile, bike history, loyalty points)  

**Widgets:**
- CustomerCard  
- LoyaltyBadge  

**Rules:**
- Validate Chilean RUT  
- Customers must be linkable to invoices in Sales  

---

## 📦 3. Inventory Module

**Folder:** `lib/modules/inventory/`

**Models:**
- Product (id, name, sku, price, cost, inventory_qty, image_url)  
- StockMovement (id, product_id, qty, type [IN/OUT], date, reference)  

**Services:**
- InventoryService: addProduct(), updateProduct(), adjustStock(), getStockMovements()  

**Pages:**
- InventoryListPage (paginated, searchable, with product images)  
- ProductFormPage (add/edit with image upload)  

**Widgets:**
- ProductCard (with thumbnail)  
- StockMovementTable  

**Rules:**
- Deduct/add stock automatically when Sales or Purchases post  
- Post accounting entries (Inventory, COGS, IVA)  
- Use ImageService for product images (upload, cache, placeholder)  

---

## 💰 4. Sales Module

**Folder:** `lib/modules/sales/`

**Models:**
- Invoice (id, customer_id, date, total, tax, status)  
- Payment (id, invoice_id, amount, method, date)  

**Services:**
- SalesService: createInvoice(), addPayment(), getInvoices(), getPayments()  

**Pages:**
- InvoiceListPage (searchable, filterable)  
- InvoiceFormPage (create/edit)  
- PaymentFormPage (record payments)  

**Widgets:**
- InvoiceCard  
- PaymentTable  

**Rules:**
- Deduct inventory when invoice is created  
- Post accounting entries:  
  - Debit Accounts Receivable  
  - Credit Revenue  
  - Credit IVA Debit  
- Respect CLP, IVA (19%), DD/MM/YYYY  

---

## 🛒 5. Purchases Module

**Folder:** `lib/modules/purchases/`

**Models:**
- Supplier (id, name, RUT, email, phone, address)  
- PurchaseOrder (id, supplier_id, date, total, status)  
- SupplierInvoice (id, supplier_id, date, total, tax, status)  

**Services:**
- PurchaseService: createPurchaseOrder(), receiveGoods(), recordSupplierInvoice()  

**Pages:**
- PurchaseOrderListPage  
- PurchaseOrderFormPage  
- SupplierInvoiceListPage  

**Widgets:**
- SupplierCard  
- PurchaseOrderTable  

**Rules:**
- Increase inventory when goods are received  
- Post accounting entries:  
  - Debit Inventory  
  - Debit IVA Credit  
  - Credit Accounts Payable  
- Respect Chilean localization  

---
