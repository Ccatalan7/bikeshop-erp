# 🗺️ Website Module - Development Roadmap

## 📊 Current Status Overview

```
E-commerce Website Module Progress: 80% Complete
```

### ✅ Completed (80%):
- Database schema (100%)
- Models and services (100%)
- Online orders management (100%)
- Google Merchant feed function (100%)
- Navigation integration (100%)

### 🚧 In Progress (0%):
- Content management UI
- Banner management UI
- Featured products UI
- Settings UI

### ⏳ Not Started (0%):
- Public website
- Payment gateway
- Email notifications

---

## 🎯 Development Phases

### **Phase 1: Complete Content Management (Priority: HIGH)**
**Time Estimate:** 1-2 weeks  
**Status:** Not started

#### Task 1.1: Banner Management UI
**File:** `lib/modules/website/pages/banners_management_page.dart`

**Requirements:**
- [ ] List all banners with thumbnails
- [ ] Add new banner form
- [ ] Upload banner images to Supabase Storage
- [ ] Edit existing banners
- [ ] Delete banners (with confirmation)
- [ ] Reorder banners (drag-and-drop)
- [ ] Toggle active/inactive
- [ ] Preview banner

**Implementation Steps:**

1. **Create Banner Form Widget:**
```dart
class BannerFormDialog extends StatefulWidget {
  final WebsiteBanner? banner; // null for new banner
  
  // Form fields:
  // - Title (required)
  // - Subtitle (optional)
  // - Image (upload)
  // - Link (optional)
  // - CTA Text (optional)
  // - CTA Link (optional)
  // - Active toggle
}
```

2. **Add Image Upload:**
```dart
Future<String?> _uploadBannerImage(File imageFile) async {
  final fileName = 'banner_${DateTime.now().millisecondsSinceEpoch}.jpg';
  
  await Supabase.instance.client.storage
    .from('banners')
    .upload(fileName, imageFile);
  
  final url = Supabase.instance.client.storage
    .from('banners')
    .getPublicUrl(fileName);
  
  return url;
}
```

3. **Add Reordering:**
```dart
ReorderableListView(
  onReorder: (oldIndex, newIndex) {
    // Update order_index in database
    websiteService.reorderBanners(newOrder);
  },
  children: banners.map((banner) => 
    BannerCard(key: ValueKey(banner.id), banner: banner)
  ).toList(),
)
```

**Dependencies Needed:**
```yaml
# Add to pubspec.yaml
dependencies:
  image_picker: ^1.0.0
  cached_network_image: ^3.0.0  # Already included
```

---

#### Task 1.2: Featured Products Selector
**File:** `lib/modules/website/pages/featured_products_page.dart`

**Requirements:**
- [ ] Show all products with images
- [ ] Search/filter products
- [ ] Multi-select products
- [ ] See currently featured products
- [ ] Reorder featured products
- [ ] Set maximum number (e.g., 8 featured)
- [ ] Save changes

**Implementation Steps:**

1. **Create Product Selector:**
```dart
class FeaturedProductsPage extends StatefulWidget {
  // Show two columns:
  // Left: All products (searchable)
  // Right: Selected featured products (reorderable)
}
```

2. **Add Search:**
```dart
TextField(
  decoration: InputDecoration(
    hintText: 'Buscar productos...',
    prefixIcon: Icon(Icons.search),
  ),
  onChanged: (query) {
    // Filter products list
    setState(() {
      _filteredProducts = _allProducts
        .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    });
  },
)
```

3. **Add Selection Logic:**
```dart
void _toggleFeatured(Product product) {
  if (_featuredProducts.contains(product)) {
    _featuredProducts.remove(product);
  } else {
    if (_featuredProducts.length < 8) {
      _featuredProducts.add(product);
    } else {
      // Show error: Max 8 products
    }
  }
}
```

4. **Save to Database:**
```dart
Future<void> _saveFeaturedProducts() async {
  // Delete all current featured
  await supabase.from('featured_products')
    .delete()
    .eq('active', true);
  
  // Insert new featured with order
  for (int i = 0; i < _featuredProducts.length; i++) {
    await supabase.from('featured_products').insert({
      'product_id': _featuredProducts[i].id,
      'active': true,
      'order_index': i,
    });
  }
  
  await websiteService.loadFeaturedProducts();
}
```

---

#### Task 1.3: Content Editor
**File:** `lib/modules/website/pages/content_management_page.dart`

**Requirements:**
- [ ] List content blocks (About Us, Terms, etc.)
- [ ] Rich text editor
- [ ] Preview mode
- [ ] Save/publish
- [ ] Markdown or HTML support

**Implementation Steps:**

1. **Add Rich Text Editor Package:**
```yaml
# pubspec.yaml
dependencies:
  flutter_quill: ^9.0.0
```

2. **Create Content List:**
```dart
// Predefined content blocks
final contentBlocks = [
  {'id': 'about_us', 'title': 'Acerca de Nosotros'},
  {'id': 'shipping_policy', 'title': 'Política de Envíos'},
  {'id': 'return_policy', 'title': 'Política de Devoluciones'},
  {'id': 'terms_conditions', 'title': 'Términos y Condiciones'},
  {'id': 'privacy_policy', 'title': 'Política de Privacidad'},
  {'id': 'faq', 'title': 'Preguntas Frecuentes'},
];
```

3. **Create Editor Widget:**
```dart
class ContentEditorDialog extends StatefulWidget {
  final String contentId;
  final String title;
  final String? currentContent;
  
  // Uses QuillEditor for rich text
  // Converts to HTML on save
}
```

4. **Save Content:**
```dart
Future<void> _saveContent(String id, String content) async {
  await supabase.from('website_content').upsert({
    'id': id,
    'content': content,
    'updated_at': DateTime.now().toIso8601String(),
  });
}
```

---

#### Task 1.4: Website Settings
**File:** `lib/modules/website/pages/website_settings_page.dart`

**Requirements:**
- [ ] Store name
- [ ] Store URL
- [ ] Contact email
- [ ] Phone number
- [ ] Social media links
- [ ] Enable/disable features
- [ ] Currency settings
- [ ] Shipping options

**Implementation Steps:**

1. **Create Settings Form:**
```dart
// Key-value pairs stored in website_settings table
final settings = [
  {'key': 'store_name', 'label': 'Nombre de la Tienda', 'value': 'Vinabike'},
  {'key': 'store_url', 'label': 'URL del Sitio', 'value': 'https://tienda.vinabike.cl'},
  {'key': 'contact_email', 'label': 'Email de Contacto', 'value': 'contacto@vinabike.cl'},
  {'key': 'contact_phone', 'label': 'Teléfono', 'value': '+56 9 1234 5678'},
  {'key': 'facebook_url', 'label': 'Facebook', 'value': ''},
  {'key': 'instagram_url', 'label': 'Instagram', 'value': ''},
  {'key': 'enable_guest_checkout', 'label': 'Compra como Invitado', 'value': 'true'},
  {'key': 'free_shipping_threshold', 'label': 'Envío Gratis Sobre', 'value': '50000'},
];
```

2. **Save Settings:**
```dart
Future<void> _saveSetting(String key, String value) async {
  await supabase.from('website_settings').upsert({
    'key': key,
    'value': value,
    'updated_at': DateTime.now().toIso8601String(),
  });
}
```

---

### **Phase 2: Google Merchant Center Deployment (Priority: HIGH)**
**Time Estimate:** 2-3 hours  
**Status:** Function created, needs deployment

#### Task 2.1: Deploy Edge Function

**Steps:**

1. **Install Supabase CLI:**
```bash
# macOS
brew install supabase/tap/supabase

# Verify installation
supabase --version
```

2. **Login to Supabase:**
```bash
supabase login
```

3. **Link Project:**
```bash
cd /Users/Claudio/Dev/bikeshop-erp
supabase link --project-ref YOUR_PROJECT_REF

# Find YOUR_PROJECT_REF in Supabase Dashboard → Settings → API
```

4. **Deploy Function:**
```bash
supabase functions deploy google-merchant-feed
```

5. **Get Function URL:**
```
Output will show:
https://YOUR_PROJECT.supabase.co/functions/v1/google-merchant-feed

Copy this URL!
```

6. **Test Function:**
```bash
curl https://YOUR_PROJECT.supabase.co/functions/v1/google-merchant-feed
# Should return XML feed
```

#### Task 2.2: Configure Google Merchant Center

**Steps:**

1. **Create Account:**
   - Go to: https://merchants.google.com
   - Sign in with Google account
   - Click "Create account"
   - Choose "Single store"
   - Enter store details

2. **Verify Website:**
   - Tools → Website verification
   - Choose method:
     - **HTML file:** Download file, upload to Firebase hosting
     - **HTML tag:** Add to website header
     - **Google Analytics:** Link GA account
   - Click "Verify"

3. **Add Product Feed:**
   - Products → Feeds → Add Feed
   - Primary feeds → Create primary feed
   - Country: Chile
   - Language: Spanish (es)
   - Destinations: Free listings
   - Input method: "Scheduled fetch"
   - File name: Paste your Supabase function URL
   - Fetch schedule: Daily at 6:00 AM
   - Time zone: America/Santiago
   - Click "Create feed"

4. **Wait for Initial Fetch:**
   - Google will fetch within 24 hours
   - Check for errors in feed diagnostics
   - Fix any issues (missing images, descriptions, etc.)

5. **Enable Free Listings:**
   - Growth → Manage programs
   - "Surfaces across Google" → Get started
   - Read terms → Accept
   - Done! Products will appear in Google Shopping

**Expected Result:** Your products appear in Google search results with images and prices! 🎉

---

### **Phase 3: Public Website (Priority: MEDIUM)**
**Time Estimate:** 2-4 weeks  
**Status:** Not started

#### Option A: FlutterFlow (Recommended for Speed)

**Pros:**
- Visual builder (no coding)
- E-commerce templates available
- Supabase integration built-in
- Can export code later
- Fast development (~1 week)

**Steps:**

1. **Sign Up:**
   - Go to: https://flutterflow.io
   - Create free account
   - Start free trial (14 days)

2. **Create Project:**
   - New project → From template
   - Search "ecommerce" or "shop"
   - Pick template with shopping cart
   - Clone template

3. **Connect Database:**
   - Integrations → Supabase
   - Enter your Supabase URL and anon key
   - Test connection

4. **Map Data:**
   - Link pages to tables:
     - Product catalog → `products` table
     - Product detail → `products` table
     - Cart → Local state
     - Checkout → `online_orders` table
     - Account → `customers` table

5. **Customize Design:**
   - Colors: `#714B67` (Vinabike purple)
   - Logo: Upload Vinabike logo
   - Fonts: Match ERP fonts
   - Images: Add placeholder products

6. **Configure Pages:**
   - Homepage:
     - Query: `website_banners` (active=true, order by order_index)
     - Query: `featured_products` with product details
   - Product catalog:
     - Query: `products` (show_on_website=true, stock>0)
     - Add filters by category
     - Add search bar
   - Product detail:
     - Show images, description, price, stock
     - Add to cart button
     - Related products
   - Checkout:
     - Customer form
     - Order summary
     - Payment integration (Stripe/MercadoPago)
     - Insert into `online_orders` and `online_order_items`

7. **Test in FlutterFlow:**
   - Use preview mode
   - Test complete flow:
     - Browse → Add to cart → Checkout → Order placed
   - Fix any issues

8. **Export Code:**
   - Download → Export Code
   - Extract ZIP file
   - You now own the code forever!

9. **Deploy:**
```bash
cd /path/to/exported/project
flutter build web --release
firebase deploy --only hosting:store
```

**Time:** ~1 week with FlutterFlow

---

#### Option B: Custom Flutter Web App

**Pros:**
- Full control
- Reuse ERP components
- Deep integration
- No FlutterFlow dependency

**Cons:**
- More time (~3-4 weeks)
- More coding required

**Structure:**
```
vinabike_store/
├── lib/
│   ├── pages/
│   │   ├── home_page.dart
│   │   ├── catalog_page.dart
│   │   ├── product_detail_page.dart
│   │   ├── cart_page.dart
│   │   ├── checkout_page.dart
│   │   ├── order_confirmation_page.dart
│   │   ├── account_page.dart
│   │   └── order_history_page.dart
│   ├── widgets/
│   │   ├── product_card.dart
│   │   ├── banner_carousel.dart
│   │   ├── category_filter.dart
│   │   ├── shopping_cart_badge.dart
│   │   └── footer.dart
│   ├── services/
│   │   ├── supabase_service.dart
│   │   ├── cart_service.dart
│   │   └── checkout_service.dart
│   └── main.dart
└── pubspec.yaml
```

**Key Pages to Build:**

1. **Homepage** (`home_page.dart`):
   - Banner carousel (from `website_banners`)
   - Featured products grid (from `featured_products`)
   - Categories
   - Promotions
   - Footer with links

2. **Product Catalog** (`catalog_page.dart`):
   - Product grid/list
   - Search bar
   - Category filters
   - Price filters
   - Sort options
   - Pagination

3. **Product Detail** (`product_detail_page.dart`):
   - Image gallery
   - Title, price, SKU
   - Description
   - Stock availability
   - Add to cart button
   - Quantity selector
   - Related products

4. **Shopping Cart** (`cart_page.dart`):
   - Cart items list
   - Update quantities
   - Remove items
   - Subtotal/total
   - Checkout button
   - Continue shopping

5. **Checkout** (`checkout_page.dart`):
   - Customer information form
   - Shipping address
   - Payment method selection
   - Order summary
   - Place order button
   - Payment processing

6. **Order Confirmation** (`order_confirmation_page.dart`):
   - Order number
   - Thank you message
   - Order details
   - Payment confirmation
   - Email notification
   - Track order link

**Time:** ~3-4 weeks for custom build

---

### **Phase 4: Payment Integration (Priority: HIGH)**
**Time Estimate:** 1 week  
**Status:** Not started

#### Option A: Stripe (International-friendly)

**Setup:**

1. **Create Stripe Account:**
   - Go to: https://stripe.com
   - Sign up for Chile
   - Verify business details

2. **Install Stripe Flutter Package:**
```yaml
dependencies:
  stripe_checkout: ^2.0.0
```

3. **Create Checkout Session:**
```dart
Future<void> processPayment(Order order) async {
  final response = await supabase.functions.invoke(
    'create-stripe-checkout',
    body: {
      'amount': order.total,
      'currency': 'clp',
      'order_id': order.id,
    },
  );
  
  final sessionUrl = response.data['url'];
  // Redirect to Stripe checkout
  html.window.location.href = sessionUrl;
}
```

4. **Create Edge Function:** `supabase/functions/create-stripe-checkout/index.ts`

5. **Handle Webhook:**
   - Stripe sends webhook on successful payment
   - Update order payment_status to 'paid'
   - Send confirmation email

**Fees:** 2.9% + $0.30 per transaction

---

#### Option B: MercadoPago (Chile-optimized)

**Better for Chilean customers:**
- Lower fees for local payments
- Supports local payment methods
- Spanish interface
- CLP currency native

**Setup:**

1. **Create MercadoPago Account:**
   - Go to: https://www.mercadopago.cl
   - Register business
   - Get API credentials

2. **Install Package:**
```yaml
dependencies:
  mercado_pago: ^1.0.0
```

3. **Implementation similar to Stripe**

**Fees:** ~2.5% per transaction (lower than Stripe)

---

### **Phase 5: Email Notifications (Priority: MEDIUM)**
**Time Estimate:** 3-4 days  
**Status:** Not started

#### Create Email Templates

1. **Order Confirmation Email**
2. **Order Shipped Email**
3. **Order Delivered Email**
4. **Password Reset Email**

#### Implement with Supabase Edge Functions

Create: `supabase/functions/send-order-confirmation/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { orderId } = await req.json()
  
  // Get order details
  const { data: order } = await supabase
    .from('online_orders')
    .select('*, online_order_items(*)')
    .eq('id', orderId)
    .single()
  
  // Send email using Resend (free tier: 3000/month)
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Vinabike <pedidos@vinabike.cl>',
      to: order.customer_email,
      subject: `Pedido Confirmado #${order.order_number}`,
      html: generateOrderEmailHTML(order),
    }),
  })
  
  return new Response(JSON.stringify({ success: true }))
})
```

**Service:** Use Resend.com (free tier available)

---

## 📅 Recommended Timeline

### **Week 1-2: Content Management**
- Mon-Tue: Banner management
- Wed-Thu: Featured products
- Fri: Content editor
- Weekend: Website settings

### **Week 3: Google Merchant**
- Mon: Deploy Edge function
- Tue-Wed: Set up Google Merchant Center
- Thu-Fri: Test and fix feed errors

### **Week 4-5: Public Website**
- **If FlutterFlow:**
  - Week 4: Build in FlutterFlow
  - Week 5: Export, customize, deploy
- **If Custom:**
  - Week 4-5: Build core pages
  - Week 6-7: Polish and test

### **Week 6: Payment Integration**
- Mon-Tue: Choose provider (Stripe vs MercadoPago)
- Wed-Thu: Implement checkout
- Fri: Test transactions

### **Week 7: Email & Polish**
- Mon-Tue: Set up email service
- Wed-Thu: Create templates
- Fri: Final testing

### **Week 8: Launch! 🚀**
- Mon-Tue: Final bug fixes
- Wed: Deploy to production
- Thu: Monitor and fix issues
- Fri: Celebrate! 🎉

---

## 🎯 Success Metrics

### Technical Metrics:
- [ ] All pages load < 3 seconds
- [ ] Mobile responsive (works on phones/tablets)
- [ ] No console errors
- [ ] Lighthouse score > 90
- [ ] SEO-friendly URLs

### Business Metrics:
- [ ] Products appear in Google search
- [ ] Customers can complete checkout
- [ ] Orders appear in ERP automatically
- [ ] Inventory syncs in real-time
- [ ] Payment processing works

### User Experience:
- [ ] Easy to find products
- [ ] Clear pricing
- [ ] Simple checkout (< 5 clicks)
- [ ] Mobile-friendly
- [ ] Fast loading

---

## 🆘 Need Help?

### Resources:
- FlutterFlow: https://docs.flutterflow.io
- Supabase Edge Functions: https://supabase.com/docs/guides/functions
- Google Merchant Center: https://support.google.com/merchants
- Stripe Integration: https://stripe.com/docs
- MercadoPago: https://www.mercadopago.cl/developers

### Community:
- Flutter Discord: https://discord.gg/flutter
- Supabase Discord: https://discord.supabase.com
- FlutterFlow Community: https://community.flutterflow.io

---

## 🎉 You've Got This!

The foundation is solid. The hard backend work is done. Now it's time to build the frontend and launch!

**Remember:**
- Start with FlutterFlow (fastest path to launch)
- Test early and often
- Launch with basic features, iterate later
- Focus on user experience
- Monitor Google Merchant feed

**Good luck! 🚀**
