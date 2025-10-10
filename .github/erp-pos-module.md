Using `copilot-instructions.md` as global context, scaffold and implement a dedicated POS module for in-store sales. This module is separate from the general Sales module (which handles manual invoice entry and back-office workflows).

1. POS Module Scope
   - Name: PointOfSale
   - Folder: `lib/modules/pos/`
   - Purpose: Real-time, cashier-facing interface for selling products in-store.

2. Core Features
   - Product scanning (by SKU or barcode).
   - Cart system: add/remove products, adjust quantities.
   - Customer selection (optional, searchable).
   - Payment screen: cash, card, voucher, split payments.
   - Cash drawer trigger (via hardware or simulated button).
   - Receipt printing (PDF or thermal printer integration).
   - Real-time inventory deduction.
   - Automatic journal entry posting:
     - Debit: Caja or Banco
     - Credit: Ventas Mercaderías
     - Credit: IVA Débito Fiscal
     - Debit: Costo de Ventas
     - Credit: Inventario Mercaderías

3. POS Pages
   - POSDashboardPage (entry point for cashier).
   - POSCartPage (live cart view).
   - POSPaymentPage (checkout flow).
   - POSReceiptPage (print preview).

4. POS Widgets
   - ProductTile (with image, price, stock).
   - CartItemCard
   - PaymentMethodSelector
   - ReceiptPreview

5. POS Services
   - POSService: startSale(), addToCart(), checkout(), printReceipt(), openCashDrawer()
   - Integrate with InventoryService and AccountingService.

6. Accounting Integration
   - Every POS transaction must generate a JournalEntry with linked JournalLines.
   - Use Chart of Accounts to post correctly (Caja, Ventas, IVA, Inventario, Costo de Ventas).
   - Tag entries as “POS” in JournalEntryListPage.

7. Inventory Sync
   - Deduct inventory in real-time when sale is confirmed.
   - Log StockMovement with reference to POS transaction.

8. Service Configuration Rule
   - If any external service (Firebase, Supabase, PostgreSQL, printer API, cash drawer API) must be configured before continuing:
     - Pause and clearly tell me what service is needed, why, and provide step-by-step setup guidance.
   - If not strictly necessary, continue development without interruption.

Rules:
- Respect Chilean localization (CLP, IVA 19%, DD/MM/YYYY).
- Use ImageService for product thumbnails.
- Add search bars to product and customer selectors.
- POS must be usable with keyboard, mouse, or touchscreen.
- No POS flow is complete until it posts to Accounting and updates Inventory.
