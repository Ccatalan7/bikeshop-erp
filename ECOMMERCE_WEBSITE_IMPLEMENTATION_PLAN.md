# 🛍️ E-commerce Website Implementation Plan

## 📋 Project Overview

**Objective:** Build a fully integrated e-commerce website for Vinabike that syncs seamlessly with the existing Flutter ERP app.

**Key Requirements:**
- ✅ 100% FREE (except domain ~$12/year)
- ✅ Easiest and most automated Google Merchant Center sync
- ✅ User-friendly website builder tools
- ✅ Real-time sync with ERP (NO API layer - direct database access)
- ✅ Use existing Firebase hosting infrastructure

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────┐
│         FIREBASE HOSTING (Already Setup!)       │
│  ┌──────────────┐    ┌──────────────┐         │
│  │ vinabike-erp │    │vinabike-store│         │
│  │  (Internal)  │    │   (Public)   │         │
│  └──────────────┘    └──────────────┘         │
└────────────────────────────────────────────────┘
         ↓                      ↓
         └──────────┬───────────┘
                    ↓ (DIRECT DATABASE ACCESS - NO API!)
┌────────────────────────────────────────────────┐
│           SUPABASE (Single Source of Truth)     │
│  ┌─────────────┐  ┌──────────┐  ┌──────────┐ │
│  │  Products   │  │ Orders   │  │ Customers│ │
│  │  Inventory  │  │ Invoices │  │ Content  │ │
│  │  Stock      │  │ Payments │  │ Banners  │ │
│  └─────────────┘  └──────────┘  └──────────┘ │
└────────────────────────────────────────────────┘
         ↓ (Supabase Edge Function)
┌────────────────────────────────────────────────┐
│      GOOGLE MERCHANT CENTER (Auto-sync!)       │
│  Feed URL: supabase.co/functions/v1/google-feed│
│  Updates: Automatic (daily fetch by Google)    │
└────────────────────────────────────────────────┘
```

---

## 🛠️ Technology Stack

### **Frontend**
- **Builder:** FlutterFlow (visual drag-and-drop editor)
  - Use FREE trial to build visually
  - Export code (free forever!)
  - Deploy exported code to Firebase
- **Framework:** Flutter Web
- **Template:** FlutterFlow e-commerce template (pre-built)

### **Backend**
- **Database:** Supabase (existing setup)
- **Authentication:** Supabase Auth (for ERP) + customer accounts
- **Storage:** Supabase Storage (for product images)

### **Hosting**
- **Platform:** Firebase Hosting (already configured!)
- **Sites:**
  - `vinabike-erp.web.app` → Internal ERP
  - `vinabike-store.web.app` → Public store
- **Custom Domain:** `tienda.vinabike.cl` (optional)

### **E-commerce Integration**
- **Payments:** Stripe or Mercado Pago (Chile-friendly)
- **Inventory Sync:** Real-time (same database!)
- **Order Processing:** Auto-creates sales invoices in ERP
- **Google Shopping:** Automated feed via Supabase Edge Function

---

## 📦 What Needs to Be Built

### **Phase 1: Website Store (Week 1-2)**

#### **1.1 FlutterFlow Visual Design**
- Pick e-commerce template in FlutterFlow
- Connect to Supabase (point-and-click)
  - Products table → Product catalog
  - Customers table → User accounts
  - Orders table → Order management
- Customize:
  - Brand colors: Primary `#714B67` (purple)
  - Logo: Vinabike logo
  - Images: Product photos
  - Text: Store name, descriptions

#### **1.2 Export & Deploy**
```bash
# After designing in FlutterFlow, export code
# Then deploy to Firebase:

flutter build web --release --web-renderer html --output=build/web-store
firebase deploy --only hosting:store
```

#### **1.3 Core Features to Implement**
- Product catalog with search/filters
- Product detail pages
- Shopping cart
- Checkout flow
- Customer account (registration/login)
- Order history
- Order tracking

---

### **Phase 2: Google Merchant Center Integration (Week 2)**

#### **2.1 Create Supabase Edge Function**

Create: `supabase/functions/google-merchant-feed/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )
  
  // Get all active products
  const { data: products, error } = await supabase
    .from('products')
    .select('*')
    .eq('status', 'active')
  
  if (error) throw error
  
  // Generate Google Shopping Feed (XML)
  const feed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:g="http://base.google.com/ns/1.0">
  <channel>
    <title>Vinabike - Tienda de Bicicletas</title>
    <link>https://tienda.vinabike.cl</link>
    <description>Bicicletas y accesorios en Chile</description>
    ${products.map(p => `
    <item>
      <g:id>${p.id}</g:id>
      <g:title>${escapeXml(p.name)}</g:title>
      <g:description>${escapeXml(p.description || '')}</g:description>
      <g:link>https://tienda.vinabike.cl/products/${p.id}</g:link>
      <g:image_link>${p.image_url || ''}</g:image_link>
      <g:condition>new</g:condition>
      <g:availability>${p.stock > 0 ? 'in stock' : 'out of stock'}</g:availability>
      <g:price>${p.price} CLP</g:price>
      <g:brand>Vinabike</g:brand>
      <g:gtin>${p.barcode || ''}</g:gtin>
      <g:mpn>${p.sku}</g:mpn>
      <g:product_type>${p.category || 'Bicicletas'}</g:product_type>
    </item>
    `).join('')}
  </channel>
</rss>`
  
  return new Response(feed, {
    headers: { 
      'Content-Type': 'application/xml; charset=utf-8',
      'Cache-Control': 'public, max-age=3600'
    }
  })
})

function escapeXml(unsafe: string): string {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}
```

**Deploy:**
```bash
supabase functions deploy google-merchant-feed
```

**Feed URL:** `https://[project].supabase.co/functions/v1/google-merchant-feed`

#### **2.2 Add Structured Data to Product Pages**

In Flutter web product detail pages, inject JSON-LD for Google:

```dart
// lib/modules/store/pages/product_detail_page.dart
import 'dart:convert';
import 'dart:html' as html;

class ProductDetailPage extends StatelessWidget {
  final Product product;
  
  @override
  void initState() {
    super.initState();
    _injectStructuredData();
  }
  
  void _injectStructuredData() {
    final schema = {
      '@context': 'https://schema.org/',
      '@type': 'Product',
      'name': product.name,
      'image': product.imageUrl,
      'description': product.description,
      'sku': product.sku,
      'brand': {
        '@type': 'Brand',
        'name': 'Vinabike'
      },
      'offers': {
        '@type': 'Offer',
        'url': 'https://tienda.vinabike.cl/products/${product.id}',
        'priceCurrency': 'CLP',
        'price': product.price,
        'availability': product.stock > 0 
          ? 'https://schema.org/InStock'
          : 'https://schema.org/OutOfStock',
        'seller': {
          '@type': 'Organization',
          'name': 'Vinabike'
        }
      }
    };
    
    final script = html.ScriptElement()
      ..type = 'application/ld+json'
      ..text = jsonEncode(schema);
    
    html.document.head?.append(script);
  }
  
  // ... rest of widget
}
```

#### **2.3 Google Merchant Center Setup**

1. **Create Account:** [merchants.google.com](https://merchants.google.com)
2. **Verify Website:**
   - Add HTML verification file to Firebase hosting
   - Or use Google Analytics/Tag Manager
3. **Add Product Feed:**
   - Products → Feeds → Add Feed
   - Country: Chile
   - Language: Spanish
   - Feed URL: `https://[project].supabase.co/functions/v1/google-merchant-feed`
   - Schedule: Daily automatic fetch
4. **Enable Free Listings:**
   - Growth → Manage Programs
   - Surfaces across Google → Enable

**Result:** Products automatically appear in Google Shopping searches! 🎉

---

### **Phase 3: ERP Integration (Week 3)**

#### **3.1 Create Website Content Manager Module**

Create new module: `lib/modules/website/`

```dart
// lib/modules/website/website_module.dart
class WebsiteModule {
  static const String routeName = '/website';
  
  static List<NavigationItem> getNavigationItems() {
    return [
      NavigationItem(
        icon: Icons.language,
        label: 'Website',
        route: routeName,
      ),
    ];
  }
}
```

#### **3.2 Homepage Content Editor**

```dart
// lib/modules/website/pages/content_manager_page.dart
class ContentManagerPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Gestión de Contenido Web',
      child: Column(
        children: [
          // Homepage Banner Editor
          _buildSection(
            title: 'Banner Principal',
            child: BannerEditor(
              onSave: (banner) async {
                await supabase.from('website_banners').upsert({
                  'id': 'homepage_main',
                  'title': banner.title,
                  'subtitle': banner.subtitle,
                  'image_url': banner.imageUrl,
                  'link': banner.link,
                  'active': true,
                });
              },
            ),
          ),
          
          // Featured Products Selector
          _buildSection(
            title: 'Productos Destacados',
            child: FeaturedProductsSelector(
              onSave: (productIds) async {
                await supabase.from('featured_products').delete().eq('active', true);
                for (var id in productIds) {
                  await supabase.from('featured_products').insert({
                    'product_id': id,
                    'active': true,
                    'order': productIds.indexOf(id),
                  });
                }
              },
            ),
          ),
          
          // Promotional Text
          _buildSection(
            title: 'Texto Promocional',
            child: RichTextEditor(
              onSave: (html) async {
                await supabase.from('website_content').upsert({
                  'id': 'homepage_promo',
                  'content': html,
                });
              },
            ),
          ),
          
          // Preview Button
          ElevatedButton.icon(
            icon: Icon(Icons.preview),
            label: Text('Ver Vista Previa'),
            onPressed: () {
              // Open store website in browser
              html.window.open('https://vinabike-store.web.app', '_blank');
            },
          ),
        ],
      ),
    );
  }
}
```

#### **3.3 Database Tables for Website Content**

Add to `supabase/sql/core_schema.sql`:

```sql
-- Website content tables
CREATE TABLE IF NOT EXISTS website_banners (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  subtitle TEXT,
  image_url TEXT,
  link TEXT,
  active BOOLEAN DEFAULT true,
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS featured_products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  active BOOLEAN DEFAULT true,
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS website_content (
  id TEXT PRIMARY KEY,
  content TEXT,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Row Level Security
ALTER TABLE website_banners ENABLE ROW LEVEL SECURITY;
ALTER TABLE featured_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE website_content ENABLE ROW LEVEL SECURITY;

-- Public can read
CREATE POLICY "Public can read banners" ON website_banners FOR SELECT USING (active = true);
CREATE POLICY "Public can read featured" ON featured_products FOR SELECT USING (active = true);
CREATE POLICY "Public can read content" ON website_content FOR SELECT USING (true);

-- Only authenticated users can edit
CREATE POLICY "Authenticated can edit banners" ON website_banners FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated can edit featured" ON featured_products FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated can edit content" ON website_content FOR ALL USING (auth.role() = 'authenticated');
```

#### **3.4 Order Processing Integration**

When customer places order on website, automatically create invoice in ERP:

```dart
// lib/modules/store/services/order_service.dart
class OrderService {
  Future<void> processOrder(Order order) async {
    // 1. Create sales invoice in ERP
    final invoice = await supabase.from('sales_invoices').insert({
      'customer_id': order.customerId,
      'date': order.createdAt.toIso8601String(),
      'status': 'pending',
      'total': order.total,
      'source': 'website',
    }).select().single();
    
    // 2. Create invoice items
    for (var item in order.items) {
      await supabase.from('sales_invoice_items').insert({
        'invoice_id': invoice['id'],
        'product_id': item.productId,
        'quantity': item.quantity,
        'price': item.price,
      });
    }
    
    // 3. Update inventory (triggers handle journal entries automatically)
    for (var item in order.items) {
      await supabase.rpc('update_product_stock', {
        'product_id': item.productId,
        'quantity_change': -item.quantity,
      });
    }
    
    // 4. Send confirmation email (Supabase Edge Function)
    await supabase.functions.invoke('send-order-confirmation', body: {
      'order_id': order.id,
      'customer_email': order.customerEmail,
    });
  }
}
```

---

### **Phase 4: Payment Integration (Week 4)**

#### **4.1 Stripe Integration (Recommended)**

```dart
// lib/modules/store/services/payment_service.dart
import 'package:stripe_checkout/stripe_checkout.dart';

class PaymentService {
  Future<void> processPayment(Order order) async {
    final session = await StripeCheckout.createSession(
      amount: (order.total * 100).toInt(), // Convert to cents
      currency: 'clp',
      successUrl: 'https://tienda.vinabike.cl/order-success?session={CHECKOUT_SESSION_ID}',
      cancelUrl: 'https://tienda.vinabike.cl/checkout',
      metadata: {
        'order_id': order.id,
        'customer_id': order.customerId,
      },
    );
    
    // Redirect to Stripe checkout
    await redirectToCheckout(session.id);
  }
}
```

**Alternative: Mercado Pago (Better for Chile)**
- Lower fees for Chilean customers
- Local payment methods
- Same integration pattern

---

## 🔄 How Real-time Sync Works

### **Scenario 1: Add Product in ERP**
```
ERP App → Insert into Supabase products table
         ↓ (instant, same database)
Website → Product appears automatically (queries same table)
         ↓ (Google fetches feed daily)
Google Merchant → Product shows in search results
```

### **Scenario 2: Customer Buys on Website**
```
Website → Insert order into Supabase orders table
         ↓ (instant, same database)
ERP App → Order appears in sales invoices list
         ↓ (instant, database trigger)
Inventory → Stock decreases automatically
         ↓ (next Google feed fetch)
Google Merchant → Shows updated stock level
```

### **Scenario 3: Update Price in ERP**
```
ERP App → Update Supabase products.price
         ↓ (instant, same database)
Website → Shows new price immediately
         ↓ (next Google feed fetch)
Google Merchant → Shows new price
```

**Key Point:** NO API calls, NO sync delays, NO conflicts! Everything uses the SAME database! ✨

---

## 📊 Cost Summary

| Item | Annual Cost |
|------|-------------|
| **Domain (vinabike.cl)** | $12 |
| **FlutterFlow** | $0 (use free trial, export code) |
| **Firebase Hosting** | $0 (free tier: 10GB storage, 360MB/day bandwidth) |
| **Supabase Database** | $0 (free tier: 500MB DB, 2GB bandwidth) |
| **Google Merchant Center** | $0 (free listings, pay only for ads if wanted) |
| **SSL Certificate** | $0 (Firebase includes) |
| **Payment Processing** | $0 monthly (2.9% per transaction only) |
| **TOTAL** | **$12/year** |

**vs. Shopify Basic:** $468/year  
**Savings:** $456/year! 💰

---

## 🎯 Implementation Timeline

### **Week 1: Website Foundation**
- [ ] Set up FlutterFlow account (free trial)
- [ ] Pick e-commerce template
- [ ] Connect to Supabase database
- [ ] Customize branding (colors, logo, images)
- [ ] Export Flutter code

### **Week 2: Deployment & Google Integration**
- [ ] Deploy to Firebase Hosting
- [ ] Create Google Merchant feed Edge Function
- [ ] Add structured data to product pages
- [ ] Set up Google Merchant Center account
- [ ] Submit product feed

### **Week 3: ERP Integration**
- [ ] Create Website module in ERP
- [ ] Build content management UI
- [ ] Test order → invoice flow
- [ ] Implement email notifications

### **Week 4: Testing & Launch**
- [ ] Set up payment gateway (Stripe/MercadoPago)
- [ ] Test complete purchase flow
- [ ] Verify Google Shopping listings
- [ ] Set up custom domain
- [ ] Go live! 🚀

---

## 🚀 Deployment Commands Reference

### **Build Store for Firebase:**
```bash
cd /path/to/project
flutter build web --release --web-renderer html --output=build/web-store
```

### **Deploy to Firebase:**
```bash
# Deploy only store site
firebase deploy --only hosting:store

# Deploy everything
firebase deploy
```

### **Deploy Supabase Functions:**
```bash
# Deploy Google Merchant feed
supabase functions deploy google-merchant-feed

# Deploy order confirmation email sender
supabase functions deploy send-order-confirmation
```

### **Update Database Schema:**
```bash
# Apply SQL changes
supabase db push
```

---

## ✅ Success Criteria

### **Functionality:**
- ✅ Customers can browse products and add to cart
- ✅ Checkout and payment works smoothly
- ✅ Orders automatically create invoices in ERP
- ✅ Inventory syncs in real-time (website ↔ ERP)
- ✅ Products appear in Google Shopping searches
- ✅ Non-technical staff can edit website content

### **Performance:**
- ✅ Page load time < 3 seconds
- ✅ Mobile responsive design
- ✅ Works on all major browsers

### **Integration:**
- ✅ Zero manual data entry between systems
- ✅ Stock always accurate across all platforms
- ✅ Google Merchant feed updates automatically

---

## 📚 Additional Resources

### **FlutterFlow:**
- Documentation: [docs.flutterflow.io](https://docs.flutterflow.io)
- E-commerce templates: Search "shop" or "store" in template marketplace

### **Supabase:**
- Edge Functions: [supabase.com/docs/guides/functions](https://supabase.com/docs/guides/functions)
- Row Level Security: [supabase.com/docs/guides/auth/row-level-security](https://supabase.com/docs/guides/auth/row-level-security)

### **Google Merchant Center:**
- Getting Started: [support.google.com/merchants/answer/188924](https://support.google.com/merchants/answer/188924)
- Product Data Specification: [support.google.com/merchants/answer/7052112](https://support.google.com/merchants/answer/7052112)

### **Firebase Hosting:**
- Multiple Sites: [firebase.google.com/docs/hosting/multisites](https://firebase.google.com/docs/hosting/multisites)
- Custom Domains: [firebase.google.com/docs/hosting/custom-domain](https://firebase.google.com/docs/hosting/custom-domain)

---

## 🔧 Troubleshooting

### **Issue: FlutterFlow export doesn't connect to Supabase**
**Solution:** Manually add Supabase configuration in exported code:
```dart
// lib/main.dart
final supabase = Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);
```

### **Issue: Google Merchant Center rejects feed**
**Solution:** Validate feed with [Google's Merchant Feed Validator](https://support.google.com/merchants/answer/7052112)
- Ensure all required fields present (id, title, description, link, image_link, price)
- Check product URLs are accessible
- Verify GTIN/MPN if available

### **Issue: Orders not creating invoices**
**Solution:** Check Supabase database triggers and RLS policies:
```sql
-- Verify trigger exists
SELECT * FROM pg_trigger WHERE tgname LIKE '%invoice%';

-- Check RLS policies
SELECT * FROM pg_policies WHERE tablename = 'sales_invoices';
```

---

## 🎬 Next Steps for Implementation

When ready to start building, follow this sequence:

1. **Set up FlutterFlow** (15 minutes)
   - Create free account
   - Browse e-commerce templates
   - Pick one that matches your vision

2. **Connect to Supabase** (30 minutes)
   - Add Supabase as data source in FlutterFlow
   - Map products, orders, customers tables
   - Test queries

3. **Customize Design** (2-3 hours)
   - Change colors to brand purple (#714B67)
   - Upload Vinabike logo
   - Add sample product images
   - Edit text content

4. **Export & Deploy** (1 hour)
   - Export Flutter code from FlutterFlow
   - Build for web
   - Deploy to Firebase

5. **Google Merchant Setup** (2 hours)
   - Create Supabase Edge Function for feed
   - Set up Google Merchant Center
   - Submit feed URL

6. **ERP Integration** (3-4 hours)
   - Create Website module
   - Build content manager
   - Test order flow

**Total estimated time:** 1-2 weeks of focused work

---

## 💡 Pro Tips

1. **Start simple:** Launch with basic product catalog first, add features iteratively
2. **Test early:** Deploy to Firebase staging site before going live
3. **Mobile first:** Design for mobile, desktop will follow
4. **SEO matters:** Use descriptive product titles and descriptions
5. **High-quality images:** Product photos significantly impact conversion
6. **Monitor analytics:** Use Firebase Analytics to track user behavior
7. **A/B testing:** Try different homepage layouts to see what converts better

---

**This is a complete, production-ready plan. Everything needed to build a FREE, fully-integrated e-commerce website for Vinabike! 🚀**
