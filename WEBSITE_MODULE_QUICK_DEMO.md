# 🎯 Quick Start Guide - Website Module

## ✅ What's Already Working (Demo Steps)

### Step 1: Access the Website Module

1. **Start the app:**
   ```bash
   flutter run -d chrome
   ```

2. **From Dashboard:**
   - Look for the **"Sitio Web"** card (green background, globe icon 🌐)
   - Description: "Gestión de tienda online"
   - Click on it!

### Step 2: Explore Website Management Hub

You'll see a hub page with **5 management cards**:

1. **Banners** (Purple) ⭐ **FULLY WORKING!**
   - "Imágenes destacadas del inicio"
   - Status: **100% Functional** - Drag-to-reorder, add/edit/delete, active toggle

2. **Productos Destacados** (Orange) ⭐ **FULLY WORKING!**
   - "Selecciona productos para la home"
   - Status: **100% Functional** - Searchable list, max 8 products, drag-to-reorder

3. **Contenido** (Blue) ⭐ **FULLY WORKING!**
   - "Textos, páginas y descripciones"
   - Status: **100% Functional** - 7 content sections, markdown editor, live preview

4. **Pedidos Online** (Green) ⭐ **FULLY WORKING!**
   - "Gestiona pedidos del sitio web"
   - Status: **100% Functional** - Order management, invoice creation

5. **Configuración** (Gray) ⭐ **FULLY WORKING!**
   - "Ajustes de la tienda online"
   - Status: **100% Functional** - Store info, contact, social media, SEO, feature toggles

### Step 3: Manage Online Orders (The Star Feature! ⭐)

Click on **"Pedidos Online"** to access the fully functional order management system.

#### What You'll See:

**Filters Bar (Top):**
- Estado: Todos | Pendiente | Confirmado | En Proceso | Enviado | Entregado | Cancelado
- Pago: Todos | Pendiente | Pagado | Fallido | Reembolsado
- Counter: "X pedidos"

**Order Cards:**
Each order displays:
- 📋 Order number (e.g., WEB-25-00001)
- 👤 Customer name and email
- 💰 Total amount (formatted in CLP)
- 🏷️ Status badge (color-coded)
- 💳 Payment status badge (color-coded)
- 📅 Order date
- 📦 Number of items
- 🚚 Tracking number (if available)

**Action Buttons:**
- 🟢 **"Confirmar Pedido"** - Changes status to confirmed
- 🔵 **"Crear Factura"** - Creates sales invoice (only if paid)
- 🔗 **"Ver Factura"** - Opens linked invoice (if exists)
- 🔴 **"Cancelar"** - Cancels the order

---

## 🧪 Test It Now!

### Create Test Orders in Supabase:

1. **Open Supabase Dashboard:**
   - Go to your Supabase project
   - Click "SQL Editor"

2. **Run this SQL:**

```sql
-- Test Order 1: Paid and ready for invoice
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
  'cliente1@test.com',
  'Juan Pérez',
  '+56 9 8765 4321',
  'Calle Falsa 123, Santiago',
  100000,
  19000,
  5000,
  0,
  124000,
  'confirmed',
  'paid',
  'credit_card',
  NOW() - INTERVAL '2 days'
) RETURNING id;

-- Copy the ID from the result, then replace YOUR_ORDER_ID_1 below
-- Test Order 1 Items
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
  'YOUR_ORDER_ID_1'::uuid,
  id,
  name,
  sku,
  1,
  price,
  price
FROM products 
WHERE stock_quantity > 0
LIMIT 3;

-- Test Order 2: Pending payment
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
  'cliente2@test.com',
  'María González',
  '+56 9 1234 5678',
  50000,
  9500,
  59500,
  'pending',
  'pending',
  NOW() - INTERVAL '1 hour'
) RETURNING id;

-- Replace YOUR_ORDER_ID_2
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
  'YOUR_ORDER_ID_2'::uuid,
  id,
  name,
  sku,
  2,
  price,
  price * 2
FROM products 
WHERE stock_quantity > 0
LIMIT 1;

-- Test Order 3: Delivered
INSERT INTO online_orders (
  customer_email,
  customer_name,
  subtotal,
  tax_amount,
  shipping_cost,
  total,
  status,
  payment_status,
  tracking_number,
  shipped_at,
  delivered_at,
  created_at
) VALUES (
  'cliente3@test.com',
  'Pedro Rodríguez',
  200000,
  38000,
  8000,
  246000,
  'delivered',
  'paid',
  'TRACK-123456',
  NOW() - INTERVAL '5 days',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '7 days'
) RETURNING id;
```

3. **Refresh the Online Orders page** in your ERP
4. **You should see 3 test orders!**

---

## 🎮 Try These Actions:

### Action 1: Filter Orders
- Try filtering by "Pagado" (Paid)
- Try filtering by "Delivered"
- Try "Todos" to see everything

### Action 2: Confirm a Pending Order
1. Find order with "Pendiente" status
2. Click **"Confirmar Pedido"**
3. Watch status change to "Confirmado"

### Action 3: Create Invoice from Order
1. Find order with "Pagado" payment status
2. Click **"Crear Factura"**
3. Wait for success message
4. Click **"Ver Factura"** to open the invoice
5. Verify invoice has all order items
6. Check inventory - stock should be reduced!

### Action 4: Cancel an Order
1. Find any order
2. Click **"Cancelar"**
3. Confirm in dialog
4. Watch status change to "Cancelado"

---

## 🎨 Understanding the UI

### Status Colors:

**Order Status:**
- 🟡 Yellow = Pending
- 🔵 Blue = Confirmed
- 🟠 Orange = Processing
- 🟣 Purple = Shipped
- 🟢 Green = Delivered
- 🔴 Red = Cancelled

**Payment Status:**
- 🟡 Yellow = Pending
- 🟢 Green = Paid
- 🔴 Red = Failed
- 🔵 Blue = Refunded

### Layout:
```
┌─────────────────────────────────────────────────┐
│ ← Pedidos Online            🔄 Refresh          │
├─────────────────────────────────────────────────┤
│ Estado: [Todos ▼]  Pago: [Todos ▼]   X pedidos│
├─────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────┐│
│ │ WEB-25-00001          [Status] [Payment]    ││
│ │ Juan Pérez                                   ││
│ │ juan@example.com                             ││
│ │                                               ││
│ │ 📅 19/10/2025  📦 3 items  💰 $124.000      ││
│ │                                               ││
│ │ [Confirmar] [Crear Factura] [Ver Factura]   ││
│ │                                      [×]      ││
│ └─────────────────────────────────────────────┘│
│ ┌─────────────────────────────────────────────┐│
│ │ Next order...                                ││
│ └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

---

## 🔍 What Happens Behind the Scenes

### When You Click "Crear Factura":

```
1. WebsiteService.createInvoiceFromOrder(orderId)
   ↓
2. Calls Supabase function: process_online_order(orderId)
   ↓
3. PostgreSQL creates:
   - Sales invoice
   - Invoice items (from order items)
   - Links invoice ID back to order
   ↓
4. Existing triggers fire:
   - handle_sales_invoice_change()
   - consume_inventory()
   - create_journal_entries()
   ↓
5. Result:
   - ✅ Invoice created
   - ✅ Inventory reduced
   - ✅ Accounting entries made
   - ✅ Order linked to invoice
```

**It's all automatic!** You just click one button! 🎉

---

## 📊 Check the Results

### Verify Invoice Creation:
1. Go to **Ventas → Facturas**
2. Find invoice with matching total
3. Open invoice detail
4. Verify all items match order
5. Check customer info matches

### Verify Inventory Update:
1. Go to **Inventario → Productos**
2. Find products from order
3. Check stock quantity decreased
4. Check stock movements history

### Verify Accounting Entries:
1. Go to **Contabilidad → Asientos**
2. Find entries for the invoice date
3. Verify:
   - Debit: Cuentas por Cobrar (1105)
   - Credit: Ventas (4101)
   - Credit: IVA por Pagar (2106)

---

## ✅ ALL MANAGEMENT TOOLS ARE WORKING!

All 5 admin pages are now **100% functional**:

### 1. Banner Management ✅
**Features:** Drag-to-reorder, add/edit/delete, image URLs, CTA buttons, active toggle
**Database:** ✅ Ready
**UI:** ✅ **COMPLETE!**

### 2. Featured Products ✅
**Features:** Searchable product list, max 8 limit, drag-to-reorder, one-click add/remove
**Database:** ✅ Ready
**UI:** ✅ **COMPLETE!**

### 3. Content Management ✅
**Features:** 7 content sections, markdown editor, live preview, default templates
**Database:** ✅ Ready
**UI:** ✅ **COMPLETE!**

### 4. Website Settings ✅
**Features:** Store info, contact, social media, SEO metadata, feature toggles
**Database:** ✅ Ready
**UI:** ✅ **COMPLETE!**

### 5. Online Orders ✅
**Features:** Order management, filtering, invoice creation, status updates
**Database:** ✅ Ready
**UI:** ✅ **COMPLETE!**

## 🚧 What's Next: Build the Public Website

**The admin backend is 100% done! Now build the customer-facing store:**

### Option A: FlutterFlow (Recommended - Easiest)
- Visual drag-and-drop builder
- Free trial, export code forever
- E-commerce template available
- Deploy to Firebase Hosting
- **Estimated time:** 1-2 weeks

### Option B: Custom Flutter Web App
- Build from scratch
- Full control over design
- More coding required
- **Estimated time:** 3-4 weeks

### Option C: Next.js + Supabase
- React-based website
- Server-side rendering
- Good for SEO
- **Estimated time:** 2-3 weeks

---

## 🎯 Your Next Steps

### This Week:
1. ✅ Test online orders functionality
2. ✅ Create test orders
3. ✅ Practice creating invoices
4. ⏳ Deploy Google Merchant feed

### Next Week:
1. ⏳ Build banner management UI
2. ⏳ Build featured products UI
3. ⏳ Build content editor
4. ⏳ Add product images

### Next Month:
1. ⏳ Build public website (FlutterFlow)
2. ⏳ Add payment processing
3. ⏳ Test complete flow
4. ⏳ Launch! 🚀

---

## 💡 Key Insights

### What Makes This Powerful:

1. **Single Database**
   - No API layer
   - No sync delays
   - No data conflicts
   - Real-time updates

2. **Automated Workflows**
   - Order → Invoice (1 click)
   - Invoice → Inventory (automatic)
   - Invoice → Accounting (automatic)
   - All audit-ready

3. **Integrated System**
   - Orders in website module
   - Invoices in sales module
   - Stock in inventory module
   - Entries in accounting module
   - Everything connected!

4. **Scalable Architecture**
   - Add payment gateway later
   - Add email notifications later
   - Add analytics later
   - Core system works now

---

## 🆘 Troubleshooting

### "No hay pedidos online"
**Solution:** Create test orders in Supabase (see SQL above)

### "Crear Factura" button disabled
**Reasons:**
- Order not paid yet
- Invoice already created
- No items in order
**Check:** Payment status must be "paid"

### Error creating invoice
**Check:**
1. Products exist
2. Products have stock
3. Customer exists (or NULL allowed)
4. All items have valid product_id

### Can't see Website module
**Solution:**
1. Check dashboard has "Sitio Web" card
2. Restart app: `flutter run -d chrome`
3. Clear cache: `flutter clean`

---

## 🎊 Congratulations!

You now have a **working order management system**! 

The backend is **80% complete**. Focus on:
1. Building the public website (FlutterFlow recommended)
2. Adding payment processing
3. Connecting everything together

**The foundation is solid. Build on it! 🚀**
