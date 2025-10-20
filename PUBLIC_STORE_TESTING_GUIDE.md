# 🧪 PUBLIC STORE - TESTING GUIDE

## Complete Purchase Flow Test

### Prerequisites
- App running on Chrome (port 52010)
- Supabase database connection active
- At least 3-4 products with images in database
- Featured products and banners configured in admin

---

## 🔄 End-to-End Test Flow

### 1. Homepage (/) ✅
**Test Steps:**
1. Navigate to `http://localhost:52010/`
2. Verify hero banner displays (from `website_banners` table)
3. Verify featured products grid shows 8 products
4. Click "Ver Productos" button
5. Verify categories section displays
6. Check WhatsApp floating button (bottom-right)

**Expected Results:**
- Clean white background
- Blue navigation header with cart icon
- Hero banner with overlay text
- Product cards with images, names, prices
- Footer with company info
- No console errors

---

### 2. Product Catalog (/productos) ✅
**Test Steps:**
1. Click "Productos" in header or "Ver Productos" button
2. Verify product grid displays all products
3. Test search bar (type product name)
4. Test category filters (click different categories)
5. Test price range slider
6. Test sort dropdown (name, price asc/desc, newest)
7. Click on a product card

**Expected Results:**
- Sidebar with filters on left
- Product grid (3 columns) on right
- Search filters products in real-time
- Category filter shows only selected category
- Price slider filters by range
- Sort changes product order
- Stock badges show correctly
- "In cart" badges appear for added items

---

### 3. Product Detail (/producto/:id) ✅
**Test Steps:**
1. From catalog, click any product
2. Verify breadcrumb navigation works (Home > Productos > Product Name)
3. Check image gallery (thumbnails + main image)
4. Verify product info displays (name, brand, SKU, price, stock)
5. Test quantity selector:
   - Click + button (increases quantity)
   - Click - button (decreases quantity)
   - Try to exceed stock (should be limited)
6. Click "Agregar al Carrito" button
7. Verify success message appears
8. Check cart icon badge updates with item count
9. Scroll to related products section
10. Click breadcrumb to go back

**Expected Results:**
- Image gallery works (click thumbnails changes main image)
- Stock status displays correctly (green "En stock" or red "Agotado")
- Quantity cannot exceed stock
- Add to cart shows green SnackBar with success message
- Cart badge increments
- Related products show 4 items from same category
- Product description and specifications display

---

### 4. Shopping Cart (/carrito) ✅
**Test Steps:**
1. Click cart icon in header
2. Verify all added items display
3. Test quantity controls:
   - Click + to increase quantity
   - Click - to decrease quantity
   - Verify stock warnings appear if insufficient stock
4. Click trash icon to remove item
5. Confirm removal in dialog
6. Verify totals update:
   - Subtotal
   - IVA (19%)
   - Total
7. Click "Proceder al Pago" button

**Expected Results:**
- Cart items show product image, name, SKU
- Quantity controls work correctly
- Stock warnings show when quantity > available stock
- Remove dialog asks for confirmation
- Order summary card shows correct calculations
- Benefits list displays (shipping, pickup, secure, support)
- "Seguir Comprando" button returns to products
- Empty cart state shows when all items removed

---

### 5. Checkout (/checkout) ✅
**Test Steps:**
1. From cart, click "Proceder al Pago"
2. Fill out customer form:
   - Nombre completo: "Juan Pérez"
   - Email: "juan@example.com"
   - Teléfono: "+56912345678"
   - Dirección: "Av. Libertad 1234, Viña del Mar"
3. Try submitting with empty fields (should show validation errors)
4. Select payment method:
   - Try "Transferencia Bancaria"
   - Try "Pago contra entrega"
5. Add optional notes: "Por favor llamar antes de entregar"
6. Verify order summary shows:
   - All products with thumbnails
   - Correct quantities
   - Correct prices
   - Subtotal + IVA + Total
7. Click "Realizar Pedido" button
8. Watch for loading state (button disabled)

**Expected Results:**
- Form validation works (red error messages)
- Email validation checks for @ symbol
- Phone and address required
- Payment method selection works (radio buttons)
- Order summary matches cart
- Button shows loading during order creation
- No console errors

---

### 6. Order Confirmation (/pedido/:id) ✅
**Test Steps:**
1. After placing order, verify redirect to confirmation page
2. Check order number displays prominently
3. Verify customer info shows correctly
4. Check product list matches order
5. Verify totals are correct
6. If payment method was "Transferencia":
   - Check yellow payment instructions card displays
   - Verify bank details show
7. Read "What's Next" section
8. Click "Seguir Comprando" button (should go to /productos)
9. Click "Volver al Inicio" button (should go to /)

**Expected Results:**
- Big green success icon with "¡Pedido Recibido!"
- Order number in blue (format: ORD-XXXXXX or similar)
- Customer details display correctly
- Product list with quantities and prices
- Payment instructions show ONLY for transfer method
- Timeline with 3 steps (email, processing, contact)
- Both action buttons work
- Cart is now empty (badge shows 0)

---

### 7. Contact Page (/contacto) ✅
**Test Steps:**
1. Click "Contacto" in header navigation
2. Verify hero section displays
3. Check contact cards (Address, Phone, Email)
4. Click each card to test links:
   - Address opens Google Maps
   - Phone opens phone dialer
   - Email opens email client
5. Try contact form:
   - Fill name, email, message
   - Submit (should open email client with pre-filled data)
6. Click "O escríbenos por WhatsApp" button
7. Check business hours section
8. Verify map placeholder displays

**Expected Results:**
- Hero section with blue gradient
- 3 contact cards in row (or stacked on mobile)
- Click actions work (maps, phone, email)
- Contact form validation works
- WhatsApp button opens WhatsApp with pre-filled message
- Business hours show with green dots for open days
- All sections properly formatted

---

## 🔍 Database Verification

### After Order Creation:
1. Open Supabase dashboard
2. Check `online_orders` table:
   ```sql
   SELECT * FROM online_orders ORDER BY created_at DESC LIMIT 1;
   ```
   - Verify order exists
   - Check `order_number` is auto-generated
   - Verify customer info saved correctly
   - Check `status` = 'pending'
   - Check `payment_status` = 'pending'
   - Check `subtotal`, `tax_amount`, `total` are correct
   - Verify `payment_method` saved

3. Check `online_order_items` table:
   ```sql
   SELECT * FROM online_order_items WHERE order_id = 'ORDER_ID_HERE';
   ```
   - Verify all cart items saved
   - Check quantities correct
   - Check prices match cart
   - Verify product references exist

---

## 🐛 Common Issues & Solutions

### Issue: Products don't display
**Solution:** 
- Check products have `show_on_website = true`
- Check products have `stock_quantity > 0`
- Verify images uploaded to Supabase Storage

### Issue: Cart icon doesn't update
**Solution:**
- Check CartProvider is registered in main.dart
- Verify ChangeNotifierProvider wraps MaterialApp

### Issue: Order creation fails
**Solution:**
- Check Supabase connection
- Verify online_orders table exists with correct schema
- Check database triggers are working
- Look for console errors

### Issue: Images don't load
**Solution:**
- Verify image URLs in database
- Check Supabase Storage bucket is public
- Test image URLs directly in browser

### Issue: Navigation doesn't work
**Solution:**
- Check GoRouter configuration
- Verify publicRoutes array includes all public paths
- Check context.go() vs context.push()

---

## ✅ Success Criteria

### All tests pass if:
- ✅ Can browse products without errors
- ✅ Can search and filter products
- ✅ Can add products to cart
- ✅ Cart updates correctly (quantity, totals)
- ✅ Can complete checkout form
- ✅ Order saves to database
- ✅ Cart clears after order
- ✅ Confirmation page displays order details
- ✅ Navigation works between all pages
- ✅ Contact page links work
- ✅ No console errors throughout flow
- ✅ WhatsApp button works
- ✅ All images load correctly

---

## 📝 Test Checklist

Copy this to track your testing:

```
[ ] Homepage displays correctly
[ ] Featured products load (8 items)
[ ] Hero banner shows
[ ] Product catalog displays all products
[ ] Search filters products
[ ] Category filters work
[ ] Price slider filters
[ ] Sort options work
[ ] Product detail shows correctly
[ ] Image gallery works
[ ] Add to cart succeeds
[ ] Cart badge updates
[ ] Related products display
[ ] Shopping cart shows items
[ ] Quantity controls work
[ ] Remove item works
[ ] Totals calculate correctly
[ ] Checkout form validates
[ ] Payment method selection works
[ ] Order creates successfully
[ ] Order saves to database
[ ] Cart clears after order
[ ] Confirmation page displays
[ ] Order number shows
[ ] Payment instructions show (if transfer)
[ ] Navigation buttons work
[ ] Contact page loads
[ ] Contact cards work
[ ] Contact form submits
[ ] WhatsApp button works
[ ] No console errors anywhere
```

---

## 🎯 Performance Checks

### Page Load Times:
- Homepage: < 2 seconds
- Product catalog: < 2 seconds
- Product detail: < 1 second
- Cart: < 1 second
- Checkout: < 1 second

### Image Loading:
- Product images should load progressively
- No broken image icons
- Placeholder while loading

### Responsiveness:
- Test on different screen sizes
- Desktop (1920x1080)
- Tablet (768x1024)
- Mobile (375x667)

---

**Next Step:** Deploy to production! 🚀
