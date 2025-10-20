# 🧪 Step-by-Step: Create & Test Online Orders

## 📋 Prerequisites

Before you start, make sure:
- ✅ Your Supabase database has the website schema deployed
- ✅ You have at least 3 products in your inventory with stock > 0
- ✅ Your Flutter app is running

---

## 🎯 Part 1: Create Test Orders in Supabase

### Step 1: Open Supabase Dashboard

1. **Go to Supabase:**
   - Open your browser
   - Navigate to: https://app.supabase.com
   - Log in to your account

2. **Select your project:**
   - Click on your Vinabike ERP project

3. **Open SQL Editor:**
   - Click **"SQL Editor"** in the left sidebar
   - Click **"New query"** button

---

### Step 2: Create First Test Order (Paid Order)

**Copy and paste this SQL into the editor:**

```sql
-- ============================================
-- TEST ORDER 1: Paid and Ready for Invoice
-- ============================================

-- First, let's see what products we have
SELECT id, name, sku, price, stock_quantity 
FROM products 
WHERE stock_quantity > 0 
LIMIT 5;

-- Copy one of the product IDs from the result above
-- We'll use it in the next step
```

**Click "Run" (or press Ctrl+Enter)**

You should see a list of products with their IDs. **Copy 2-3 product IDs** - you'll need them in the next step!

---

### Step 3: Insert the Order

**Now paste this SQL** (keep the same SQL Editor window):

```sql
-- Create the order
INSERT INTO online_orders (
  customer_email,
  customer_name,
  customer_phone,
  customer_address,
  subtotal,
  tax_amount,
  shipping_cost,
  discount_amount,
  total,
  status,
  payment_status,
  payment_method,
  created_at
) VALUES (
  'juan.perez@test.com',
  'Juan Pérez',
  '+56 9 8765 4321',
  'Av. Libertador Bernardo O''Higgins 1234, Santiago',
  100000,
  19000,
  5000,
  0,
  124000,
  'confirmed',
  'paid',
  'credit_card',
  NOW() - INTERVAL '2 days'
) RETURNING id, order_number;
```

**Click "Run"**

You'll see output like:
```
id: 123e4567-e89b-12d3-a456-426614174000
order_number: WEB-25-00001
```

**IMPORTANT: Copy the `id` value!** You'll need it for the next step.

---

### Step 4: Add Items to the Order

**Replace `YOUR_ORDER_ID` with the ID you just copied:**

```sql
-- Add order items
-- REPLACE 'YOUR_ORDER_ID' with the actual ID from previous step
INSERT INTO online_order_items (
  order_id,
  product_id,
  product_name,
  product_sku,
  quantity,
  unit_price,
  subtotal
)
SELECT 
  'YOUR_ORDER_ID'::uuid,  -- ← REPLACE THIS!
  id,
  name,
  sku,
  1,
  price,
  price
FROM products 
WHERE stock_quantity > 0
LIMIT 3;

-- Verify items were added
SELECT * FROM online_order_items 
WHERE order_id = 'YOUR_ORDER_ID'::uuid;  -- ← REPLACE THIS TOO!
```

**Click "Run"**

You should see 3 order items in the results!

---

### Step 5: Create Second Test Order (Pending Payment)

**Paste this SQL:**

```sql
-- ============================================
-- TEST ORDER 2: Pending Payment
-- ============================================

INSERT INTO online_orders (
  customer_email,
  customer_name,
  customer_phone,
  subtotal,
  tax_amount,
  total,
  status,
  payment_status,
  created_at
) VALUES (
  'maria.gonzalez@test.com',
  'María González',
  '+56 9 1234 5678',
  50000,
  9500,
  59500,
  'pending',
  'pending',
  NOW() - INTERVAL '1 hour'
) RETURNING id, order_number;
```

**Click "Run"** and copy the new order ID.

**Then add items:**

```sql
-- REPLACE 'YOUR_ORDER_ID_2' with the ID from above
INSERT INTO online_order_items (
  order_id,
  product_id,
  product_name,
  product_sku,
  quantity,
  unit_price,
  subtotal
)
SELECT 
  'YOUR_ORDER_ID_2'::uuid,  -- ← REPLACE THIS!
  id,
  name,
  sku,
  2,
  price,
  price * 2
FROM products 
WHERE stock_quantity > 0
LIMIT 2;
```

---

### Step 6: Create Third Test Order (Delivered)

**Paste this SQL:**

```sql
-- ============================================
-- TEST ORDER 3: Already Delivered
-- ============================================

INSERT INTO online_orders (
  customer_email,
  customer_name,
  customer_phone,
  customer_address,
  subtotal,
  tax_amount,
  shipping_cost,
  total,
  status,
  payment_status,
  payment_method,
  tracking_number,
  shipped_at,
  delivered_at,
  created_at
) VALUES (
  'pedro.rodriguez@test.com',
  'Pedro Rodríguez',
  '+56 9 5555 6666',
  'Calle Moneda 456, Valparaíso',
  200000,
  38000,
  8000,
  246000,
  'delivered',
  'paid',
  'webpay',
  'TRACK-' || LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0'),
  NOW() - INTERVAL '5 days',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '7 days'
) RETURNING id, order_number, tracking_number;
```

**Click "Run"** and copy the order ID.

**Add items:**

```sql
-- REPLACE 'YOUR_ORDER_ID_3'
INSERT INTO online_order_items (
  order_id,
  product_id,
  product_name,
  product_sku,
  quantity,
  unit_price,
  subtotal
)
SELECT 
  'YOUR_ORDER_ID_3'::uuid,  -- ← REPLACE THIS!
  id,
  name,
  sku,
  1,
  price,
  price
FROM products 
WHERE stock_quantity > 0
LIMIT 4;
```

---

### Step 7: Verify All Orders Were Created

**Run this query to see all test orders:**

```sql
SELECT 
  order_number,
  customer_name,
  customer_email,
  total,
  status,
  payment_status,
  created_at
FROM online_orders
ORDER BY created_at DESC
LIMIT 10;
```

You should see your 3 test orders! 🎉

---

## 🖥️ Part 2: Test Orders in the ERP App

### Step 1: Start the App (if not running)

```bash
cd /Users/Claudio/Dev/bikeshop-erp
flutter run -d chrome
```

Wait for the app to load...

---

### Step 2: Navigate to Online Orders

1. **From Dashboard:**
   - Look for the **"Sitio Web"** card
   - It has a **green background** with a **🌐 globe icon**
   - Description says: "Gestión de tienda online"
   - **Click on it!**

2. **You'll see the Website Management Hub with 5 cards:**
   - Banners (Purple)
   - Productos Destacados (Orange)
   - Contenido (Blue)
   - **Pedidos Online (Green)** ← Click this one!
   - Configuración (Gray)

3. **Click "Pedidos Online"**

---

### Step 3: View Your Test Orders

You should now see the **Online Orders page** with:

**Top bar showing:**
- Estado: [Todos ▼]
- Pago: [Todos ▼]  
- "3 pedidos" (or however many you created)

**Your 3 test orders should appear as cards:**

1. **Order 1:** Juan Pérez
   - Status: Confirmado (Blue badge)
   - Payment: Pagado (Green badge)
   - Total: $124.000

2. **Order 2:** María González
   - Status: Pendiente (Yellow badge)
   - Payment: Pendiente (Yellow badge)
   - Total: $59.500

3. **Order 3:** Pedro Rodríguez
   - Status: Entregado (Green badge)
   - Payment: Pagado (Green badge)
   - Total: $246.000
   - Tracking: TRACK-XXXXXX

---

### Step 4: Test Filtering

**Try the filters:**

1. **Filter by Payment Status:**
   - Click "Pago" dropdown
   - Select "Pagado"
   - You should see only 2 orders (Juan and Pedro)

2. **Filter by Order Status:**
   - Click "Estado" dropdown
   - Select "Pendiente"
   - You should see only María's order

3. **Reset filters:**
   - Select "Todos" in both dropdowns
   - All 3 orders appear again

---

### Step 5: Test Creating Invoice from Order 🎯

This is the **main feature**! Let's test it:

1. **Find Juan Pérez's order** (the one marked "Pagado")

2. **Click the "Crear Factura" button** (blue button)

3. **Wait a moment...** You'll see a loading indicator

4. **Success message appears:** "Factura creada exitosamente"

5. **Notice the changes:**
   - The "Crear Factura" button disappears
   - A new "Ver Factura" button appears (blue with eye icon)

6. **Click "Ver Factura"**
   - You're taken to the Sales Invoice detail page
   - Verify the invoice has:
     - Customer: Juan Pérez
     - Email: juan.perez@test.com
     - All 3 products from the order
     - Correct quantities and prices
     - Total: $124.000

---

### Step 6: Verify Inventory Was Reduced

1. **Go to Inventory module:**
   - Click sidebar menu
   - Click "Inventario"
   - Click "Productos"

2. **Find the products that were in Juan's order**

3. **Check stock quantity:**
   - Stock should be **reduced by 1** for each product
   - Example: If product had 10 units, now it has 9

4. **Check stock movements:**
   - Click on a product
   - Look for stock movements
   - You should see a "Sale" movement with -1 quantity

---

### Step 7: Verify Accounting Entries

1. **Go to Accounting module:**
   - Click sidebar menu
   - Click "Contabilidad"
   - Click "Asientos Contables"

2. **Find the most recent entry** (today's date)

3. **Open the journal entry**

4. **Verify the entries:**
   - **Debit:** Cuentas por Cobrar (1105) - $124.000
   - **Credit:** Ventas (4101) - $104.202
   - **Credit:** IVA por Pagar (2106) - $19.798

5. **Check that it's balanced** (total debits = total credits)

---

### Step 8: Test Order Confirmation

Let's test confirming María's pending order:

1. **Go back to Online Orders page**
   - Click "Sitio Web" in sidebar
   - Click "Pedidos Online"

2. **Find María González's order** (Pendiente status)

3. **Click "Confirmar Pedido" button** (green button)

4. **Confirm in the dialog** that appears

5. **Success!** The status badge changes from:
   - Pendiente (Yellow) → Confirmado (Blue)

---

### Step 9: Test Order Cancellation

Now let's cancel an order:

1. **Still on Online Orders page**

2. **Pick any order** (let's use María's)

3. **Click the "×" button** in the top-right corner of the order card

4. **Confirm cancellation** in the dialog

5. **Success!** The status changes to:
   - Cancelado (Red badge)

---

### Step 10: Test Refresh

1. **Click the refresh icon** (🔄) in the top-right corner

2. **Orders reload** from database

3. **Any changes made in Supabase should appear here**

---

## ✅ Verification Checklist

After completing all steps, verify:

- [ ] Can see 3 test orders in the app
- [ ] Can filter by status and payment
- [ ] Can create invoice from paid order
- [ ] Invoice appears in Sales module
- [ ] Inventory was reduced correctly
- [ ] Accounting entries were created
- [ ] Can confirm pending orders
- [ ] Can cancel orders
- [ ] Can refresh the list
- [ ] Can navigate to invoices from orders

---

## 🎨 What Each Order Tests

### Order 1 (Juan Pérez - Paid):
**Tests:** Invoice creation workflow
- ✅ Creating invoice from order
- ✅ Inventory reduction
- ✅ Accounting integration
- ✅ Order-invoice linking

### Order 2 (María González - Pending):
**Tests:** Order status management
- ✅ Pending payment display
- ✅ Order confirmation
- ✅ Status updates
- ✅ Cannot create invoice until paid

### Order 3 (Pedro Rodríguez - Delivered):
**Tests:** Complete order lifecycle
- ✅ Tracking number display
- ✅ Shipped/delivered dates
- ✅ Historical orders
- ✅ Completed order status

---

## 🐛 Common Issues & Solutions

### Issue: "No hay pedidos online"

**Possible causes:**
- Orders weren't created in Supabase
- RLS policies blocking access
- Wrong Supabase project

**Solution:**
1. Check Supabase SQL Editor - run:
   ```sql
   SELECT COUNT(*) FROM online_orders;
   ```
2. Should return a number > 0
3. If 0, re-run the INSERT statements
4. If still 0, check RLS policies

---

### Issue: "Crear Factura" button is disabled

**Possible causes:**
- Payment status is not "paid"
- Invoice already created
- Order has no items

**Solution:**
1. Check payment status badge - must be "Pagado" (green)
2. Check if "Ver Factura" button exists (invoice already created)
3. Verify order has items:
   ```sql
   SELECT * FROM online_order_items WHERE order_id = 'YOUR_ORDER_ID';
   ```

---

### Issue: Error creating invoice

**Error message:** "Error al crear factura"

**Possible causes:**
- Products don't exist
- Insufficient stock
- Database trigger error

**Solution:**
1. Check browser console (F12) for detailed error
2. Verify products exist and have stock:
   ```sql
   SELECT p.name, p.stock_quantity, oi.quantity
   FROM online_order_items oi
   JOIN products p ON p.id = oi.product_id
   WHERE oi.order_id = 'YOUR_ORDER_ID';
   ```
3. If stock is insufficient, add more stock
4. Check Supabase logs for trigger errors

---

### Issue: Inventory not reduced

**Possible causes:**
- Trigger not firing
- Product IDs don't match

**Solution:**
1. Check if invoice was created
2. Verify trigger exists:
   ```sql
   SELECT * FROM pg_trigger 
   WHERE tgname LIKE '%consume%inventory%';
   ```
3. Check stock movements:
   ```sql
   SELECT * FROM stock_movements 
   ORDER BY created_at DESC LIMIT 10;
   ```

---

## 🎓 Understanding the Data Flow

When you click "Crear Factura", here's what happens:

```
1. Frontend (Flutter App)
   ↓ calls websiteService.createInvoiceFromOrder()
   
2. Supabase Function
   ↓ executes process_online_order(order_id)
   
3. Database Function
   ↓ creates sales_invoice record
   ↓ creates sales_invoice_items records
   ↓ updates online_orders.sales_invoice_id
   
4. Database Trigger: handle_sales_invoice_change()
   ↓ fires automatically
   
5. Database Trigger: consume_inventory()
   ↓ reduces product stock
   ↓ creates stock_movements records
   
6. Database Trigger: create_journal_entry()
   ↓ creates accounting entries
   ↓ debits/credits correct accounts
   
7. Frontend
   ↓ receives success response
   ↓ shows success message
   ↓ updates UI
```

**All of this happens in ~1 second!** 🚀

---

## 📊 Sample Data Summary

After completing all tests, you'll have:

**Orders created:** 3
- 1 confirmed + paid (invoice created)
- 1 pending (confirmed but not invoiced)
- 1 delivered (historical)

**Invoices created:** 1
- For Juan Pérez's order

**Stock movements:** 3
- One for each product in Juan's order

**Journal entries:** 1
- For Juan's invoice (debit + 2 credits)

---

## 🎯 Next Steps

Now that you've tested the system:

1. **Create more realistic orders:**
   - Use actual customer data
   - Test with different product combinations
   - Test edge cases (out of stock, etc.)

2. **Test the complete workflow:**
   - Imagine a customer places an order online
   - You receive notification
   - You confirm the order
   - Payment is received
   - You create the invoice
   - Products are packed and shipped
   - You update tracking number
   - Order is delivered

3. **Build the public website:**
   - So real customers can place orders
   - Connect payment gateway
   - Add email notifications

4. **Deploy to production:**
   - Test with real data
   - Train staff on the system
   - Launch! 🚀

---

## 🎉 Congratulations!

You now know how to:
- ✅ Create online orders in Supabase
- ✅ View orders in the ERP app
- ✅ Create invoices from orders
- ✅ Verify inventory reduction
- ✅ Check accounting entries
- ✅ Manage order status
- ✅ Understand the complete workflow

**The system is working perfectly! Time to build the customer-facing website! 🌐**
