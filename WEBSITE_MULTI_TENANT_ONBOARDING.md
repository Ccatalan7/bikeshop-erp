# 🌐 Website Multi-Tenant Onboarding Guide

## 🎯 Overview

Every new tenant gets their **OWN COMPLETE WEBSITE** from scratch with:
- ✅ Isolated website blocks (hero, products, services, etc.)
- ✅ Isolated website settings (store name, colors, SEO, etc.)
- ✅ Isolated online orders and order items
- ✅ Isolated featured products
- ✅ Isolated banners and content

**No tenant sees another tenant's website configuration!**

---

## 📊 Website Tables Now Tenant-Isolated

### Updated Tables (5 additional)
1. ✅ **website_blocks** - Added `tenant_id`, visual editor blocks
2. ✅ **website_settings** - Added `tenant_id`, unique(tenant_id, key)
3. ✅ **featured_products** - Added `tenant_id`, homepage featured items
4. ✅ **online_orders** - Added `tenant_id`, unique(tenant_id, order_number)
5. ✅ **website_banners** - Already had `tenant_id` ✓
6. ✅ **website_content** - Already had `tenant_id` ✓
7. ✅ **online_order_items** - Already had `tenant_id` ✓

**Total Website Tables: 7** (all now tenant-isolated)

---

## 🎨 Default Website Template: "Modern Bike Shop"

Every new tenant automatically gets a complete homepage with **6 pre-configured blocks**:

### 1. Hero Block 🎯
```json
{
  "title": "¡Bienvenido a [Tenant Name]!",
  "subtitle": "Las mejores bicicletas y servicio técnico especializado",
  "ctaText": "Ver Productos",
  "ctaLink": "/products",
  "backgroundImage": "",
  "textAlign": "center"
}
```

### 2. Products Block 🛒
```json
{
  "title": "Productos Destacados",
  "subtitle": "Descubre nuestra selección de bicicletas y accesorios",
  "displayMode": "grid",
  "itemsToShow": 8,
  "showFeaturedOnly": true
}
```

### 3. Services Block 🔧
```json
{
  "title": "Nuestros Servicios",
  "subtitle": "Mantenimiento y reparación especializada",
  "services": [
    {
      "icon": "build",
      "title": "Mantenimiento",
      "description": "Servicio completo y revisión técnica"
    },
    {
      "icon": "settings",
      "title": "Reparaciones",
      "description": "Reparación de frenos, cambios y más"
    },
    {
      "icon": "star",
      "title": "Asesoría",
      "description": "Te ayudamos a elegir la bici perfecta"
    }
  ]
}
```

### 4. About Block 📖
```json
{
  "title": "Sobre Nosotros",
  "content": "<p>En <strong>[Tenant]</strong> somos apasionados por las bicicletas...</p>",
  "imageUrl": "",
  "layout": "image-left"
}
```

### 5. Features Block ⭐
```json
{
  "title": "¿Por qué elegirnos?",
  "features": [
    {
      "icon": "verified",
      "title": "Garantía",
      "description": "Todos nuestros productos con garantía oficial"
    },
    {
      "icon": "local_shipping",
      "title": "Envíos",
      "description": "Despacho a todo Chile"
    },
    {
      "icon": "support_agent",
      "title": "Soporte",
      "description": "Atención personalizada y asesoría experta"
    },
    {
      "icon": "workspace_premium",
      "title": "Calidad",
      "description": "Solo trabajamos con las mejores marcas"
    }
  ]
}
```

### 6. Contact Block 📞
```json
{
  "title": "Contáctanos",
  "subtitle": "Estamos aquí para ayudarte",
  "email": "contacto@[tenant].cl",
  "phone": "+569 1234 5678",
  "address": "Santiago, Chile",
  "showMap": false,
  "mapUrl": ""
}
```

---

## ⚙️ Default Website Settings (17 Settings)

Every new tenant gets these pre-configured settings:

### Store Configuration
- `store_name` → Tenant name
- `store_tagline` → "Tu tienda de bicicletas"
- `store_enabled` → `false` (change to `true` when ready to go live)
- `shipping_enabled` → `false`
- `shipping_cost` → `0` CLP
- `free_shipping_threshold` → `50000` CLP

### Contact Information
- `contact_email` → `contacto@[tenant].cl`
- `contact_phone` → `+569 1234 5678`
- `contact_address` → `Santiago, Chile`
- `social_facebook` → (empty, fill later)
- `social_instagram` → (empty, fill later)
- `social_whatsapp` → `+569 1234 5678`

### Theme & Branding
- `theme_primary_color` → `#2563eb` (blue)
- `theme_secondary_color` → `#10b981` (green)

### SEO Settings
- `seo_meta_title` → `[Tenant] - Tienda de Bicicletas`
- `seo_meta_description` → `Encuentra las mejores bicicletas y accesorios en [Tenant]`
- `seo_keywords` → `bicicletas,bikes,accesorios,repuestos,servicio técnico`

---

## 📝 New Tenant Onboarding Steps

When a new tenant is created, they should follow these steps to customize their website:

### Step 1: Add Products (Inventory Module)
- Add 5-10 products to inventory
- Upload product images
- Set competitive prices
- Mark 3-5 products as "Featured" (`website_featured = true`)
- Enable "Show on Website" (`show_on_website = true`)

### Step 2: Customize Website Blocks (Website Editor)
- **Hero Block**: Upload hero image, customize text
- **Products Block**: Will auto-show featured products
- **Services Block**: Update services to match what you offer
- **About Block**: Write your store's story, upload team photo
- **Features Block**: Highlight your unique selling points
- **Contact Block**: Update with real contact info

### Step 3: Configure Website Settings
- Update `contact_email`, `contact_phone`, `contact_address`
- Add social media links (Facebook, Instagram)
- Choose brand colors (`theme_primary_color`, `theme_secondary_color`)
- Configure shipping (`shipping_enabled`, `shipping_cost`)
- Optimize SEO (`seo_meta_title`, `seo_meta_description`)

### Step 4: Upload Logo & Branding
- Upload company logo (Settings → Company Settings → Logo)
- Upload favicon
- Ensure logo appears in website header

### Step 5: Test Before Going Live
- Preview website
- Test product browsing
- Test add to cart flow
- Test checkout process (with test products)
- Verify MercadoPago integration

### Step 6: Enable Store
- Set `store_enabled = true` in website settings
- Share website URL with customers
- Monitor first orders

---

## 🎨 Future: Additional Website Templates

In the future, we can add more template options for new tenants to choose from:

### Template 1: "Modern Bike Shop" (Current Default)
- Hero with CTA
- Featured products grid
- Services showcase
- About section
- Features/benefits
- Contact form

### Template 2: "Minimalist Store" (Future)
- Large product carousel
- Category navigation
- Minimal text, focus on images
- Quick buy buttons
- Instagram feed integration

### Template 3: "Service-First Workshop" (Future)
- Services/packages as primary focus
- Book appointment CTA
- Testimonials
- Before/after gallery
- Products as secondary

### Template 4: "Brand Showcase" (Future)
- Multiple brand sections (Trek, Specialized, etc.)
- Brand-specific product filtering
- Brand logos and descriptions
- Expert recommendations

---

## 🔐 Security & Isolation

### Data Isolation Guarantees
- ✅ Each tenant has their own website blocks (cannot see/edit others)
- ✅ Each tenant has their own website settings (colors, SEO, contact info)
- ✅ Each tenant has their own featured products (Vinabike's featured ≠ Claudio's featured)
- ✅ Each tenant has their own online orders (complete separation)
- ✅ Each tenant has their own banners and content

### RLS Policies
All website tables have Row Level Security enabled:
- `website_blocks` → Filtered by `tenant_id`
- `website_settings` → Filtered by `tenant_id`
- `featured_products` → Filtered by `tenant_id`
- `online_orders` → Filtered by `tenant_id`
- `website_banners` → Filtered by `tenant_id`
- `website_content` → Filtered by `tenant_id`
- `online_order_items` → Filtered by `tenant_id`

### Public Access (Storefront)
- Website blocks: Public can read active blocks for specific tenant
- Featured products: Public can read featured products for specific tenant
- Online orders: Only authenticated users (customers) can see their own orders

---

## 🚀 Deployment Checklist

When deploying website multi-tenancy:

1. ✅ **Deploy updated `core_schema.sql`** with tenant_id on website tables
2. ✅ **Run data migration** to assign existing website data to Vinabike
3. ✅ **Deploy RLS policies** for all 7 website tables
4. ✅ **Deploy auto-seed trigger** with default template
5. ✅ **Test with test tenant**: Create new tenant, verify it gets default template
6. ✅ **Verify isolation**: Ensure Tenant A can't see Tenant B's blocks/settings

---

## 📊 Database Updates Summary

### Tables Updated (5 new + 3 existing)
1. ✅ `website_blocks` - Added `tenant_id`, index
2. ✅ `website_settings` - Added `tenant_id`, unique(tenant_id, key)
3. ✅ `featured_products` - Added `tenant_id`, index
4. ✅ `online_orders` - Added `tenant_id`, unique(tenant_id, order_number)
5. ✅ `website_banners` - Already had `tenant_id` ✓
6. ✅ `website_content` - Already had `tenant_id` ✓
7. ✅ `online_order_items` - Already had `tenant_id` ✓

### Auto-Seed Trigger Updates
- ✅ Creates 17 default website settings
- ✅ Creates 6 default website blocks (complete homepage)
- ✅ Personalizes content with tenant name
- ✅ Sets `store_enabled = false` by default (manual enable required)

---

## 💡 Best Practices for New Tenants

### DO:
- ✅ Start with the default template, then customize
- ✅ Upload high-quality product images (min 800x800px)
- ✅ Write unique, SEO-friendly product descriptions
- ✅ Test the entire checkout flow before enabling store
- ✅ Set realistic shipping costs
- ✅ Add social proof (testimonials, reviews)

### DON'T:
- ❌ Enable store before adding products
- ❌ Use low-quality or generic stock photos
- ❌ Copy content from other websites (SEO penalty)
- ❌ Skip testing checkout flow
- ❌ Forget to configure MercadoPago credentials
- ❌ Leave placeholder contact info (users will call wrong number!)

---

## 🎯 Success Metrics

After website onboarding, tenant should have:

- ✅ At least 10 products with images
- ✅ 3-5 featured products on homepage
- ✅ Customized hero image and text
- ✅ Real contact information
- ✅ MercadoPago configured and tested
- ✅ SEO metadata optimized
- ✅ Social media links added
- ✅ Store enabled and live

---

## 📞 Next Steps

1. **Deploy schema changes** (`core_schema.sql` with updated website tables)
2. **Migrate existing data** to Vinabike tenant
3. **Deploy RLS policies** for website tables
4. **Deploy auto-seed trigger** with default template
5. **Create tenant onboarding UI** in Flutter app:
   - Welcome screen for new tenants
   - "Setup your website" wizard
   - Template preview/selection (future)
   - Guided steps with progress tracker
6. **Add website editor tutorial** (interactive guide)
7. **Test with 2-3 test tenants** to verify complete isolation

---

## 🎉 Result

Every new tenant gets a **COMPLETE, PROFESSIONAL WEBSITE FROM DAY ONE**:

- ✅ Ready-to-customize homepage template
- ✅ All essential settings pre-configured
- ✅ Complete isolation from other tenants
- ✅ SEO-optimized structure
- ✅ Mobile-responsive blocks
- ✅ Ecommerce-ready (just add products!)

**No more starting from blank slate. No more shared website data. COMPLETE MULTI-TENANT WEBSITE ISOLATION!** 🚀
