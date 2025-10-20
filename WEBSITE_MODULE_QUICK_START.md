# 🚀 Quick Start: Website Module

## 5-Minute Setup Guide

### 1️⃣ Deploy Database Schema (1 minute)

```bash
# Open Supabase Dashboard
# Go to: https://supabase.com/dashboard/project/YOUR_PROJECT/sql

# Copy-paste the contents of:
# supabase/sql/core_schema.sql

# Click "Run" or press Ctrl+Enter
```

**✅ Verify:** Run this query to confirm:
```sql
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
  AND (tablename LIKE 'website%' OR tablename LIKE 'online_%');
```

Expected result: 6 tables (website_banners, featured_products, website_content, website_settings, online_orders, online_order_items)

---

### 2️⃣ Run Flutter App (1 minute)

```bash
cd /Users/Claudio/Dev/bikeshop-erp

# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Web
flutter run -d chrome
```

---

### 3️⃣ Access Website Module (30 seconds)

1. **Open app** → You'll see the Dashboard
2. **Click** "Sitio Web" card (green, with globe icon 🌐)
3. **You're in!** Welcome to the Website Management hub

---

### 4️⃣ Test with Sample Data (2 minutes)

**In Supabase SQL Editor, run:**

```sql
-- Create a test order
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
  payment_status
) VALUES (
  'cliente@ejemplo.com',
  'Juan Pérez',
  '+56 9 8765 4321',
  'Av. Principal 123, Santiago',
  100000,  -- $100,000 CLP
  19000,   -- IVA 19%
  5000,    -- Envío
  124000,  -- Total
  'confirmed',
  'paid'
) RETURNING id;

-- Copy the returned ID, then add items:
-- (Replace YOUR_ORDER_ID with the actual UUID from above)

INSERT INTO online_order_items (order_id, product_id, product_name, product_sku, quantity, unit_price, subtotal)
SELECT 
  'YOUR_ORDER_ID'::uuid,  -- Paste order ID here
  id,
  name,
  sku,
  2,
  price,
  price * 2
FROM products
WHERE price > 0
LIMIT 3;
```

---

### 5️⃣ See It in Action! (1 minute)

**In the ERP app:**

1. Go to **Website** → **Pedidos Online**
2. You'll see your test order! 🎉
3. Click **"Crear Factura"** button
4. 💥 Invoice created automatically!
5. Click **"Ver Factura"** to navigate to it

**Behind the scenes:**
- ✅ Sales invoice created
- ✅ Invoice items added
- ✅ Inventory reduced (if stock tracking enabled)
- ✅ Journal entries created (accounting)
- ✅ Order linked to invoice

---

## 🎯 What You Can Do Now

### Manage Orders
- ✅ View all online orders
- ✅ Filter by status (pending, confirmed, shipped, etc.)
- ✅ Filter by payment status (pending, paid, failed)
- ✅ Confirm pending orders
- ✅ Create invoices from paid orders
- ✅ Navigate to sales invoices
- ✅ Cancel orders
- ✅ View customer details
- ✅ Track order history

### Coming Soon (Placeholder Pages)
- ⏳ Manage website banners
- ⏳ Select featured products
- ⏳ Edit content pages
- ⏳ Configure store settings

---

## 📊 Understanding the Flow

### Current Flow (Manual Processing)

```
1. Customer Order Created (Database/Future Store)
   ↓
2. Order appears in ERP → Website → Online Orders
   ↓
3. Staff confirms order → Status: "Confirmed"
   ↓
4. Payment received → Payment Status: "Paid"
   ↓
5. Staff clicks "Crear Factura"
   ↓
6. Magic happens! ✨
   ├─ Sales invoice created
   ├─ Invoice items added
   ├─ Inventory reduced
   ├─ Journal entries created
   └─ Order linked to invoice
```

### Future Flow (Automatic with Store + Payments)

```
1. Customer shops on website
   ↓
2. Pays with Stripe/MercadoPago
   ↓
3. Webhook triggers
   ↓
4. Order & Invoice created AUTOMATICALLY ⚡
   ↓
5. Staff just ships! 📦
```

---

## 🔍 Troubleshooting

### "No orders showing"
- Check database: `SELECT * FROM online_orders;`
- Verify RLS policies allow reading
- Refresh the page

### "Can't create invoice"
- Ensure order has `payment_status = 'paid'`
- Check product_id exists in products table
- Verify function exists: `SELECT proname FROM pg_proc WHERE proname = 'process_online_order';`

### "Website card not on dashboard"
- Restart Flutter app
- Check `lib/shared/screens/dashboard_screen.dart`
- Clear Flutter cache: `flutter clean && flutter pub get`

---

## 📚 Full Documentation

- **[WEBSITE_MODULE_IMPLEMENTATION_SUMMARY.md](./WEBSITE_MODULE_IMPLEMENTATION_SUMMARY.md)** - Complete overview
- **[WEBSITE_MODULE_DEPLOYMENT_GUIDE.md](./WEBSITE_MODULE_DEPLOYMENT_GUIDE.md)** - Detailed deployment guide
- **[ECOMMERCE_WEBSITE_IMPLEMENTATION_PLAN.md](./ECOMMERCE_WEBSITE_IMPLEMENTATION_PLAN.md)** - Original plan

---

## ✨ That's It!

You now have a **fully functional e-commerce backend** integrated into your ERP!

**Total setup time:** ~5 minutes (if database already configured)

**Next steps:**
1. Test the order → invoice flow
2. Deploy to production
3. Build the customer-facing store (Phase 4)
4. Add payment integration (Phase 5)

**Questions?** Check the full documentation linked above!

---

🎉 **Happy selling!** 🚀
