# 🚀 PUBLIC STORE - DEPLOYMENT GUIDE

## Deploying Vinabike Public Store to Firebase Hosting

This guide walks through deploying the public-facing e-commerce store to Firebase Hosting at `vinabike-store.web.app`.

---

## 📋 Pre-Deployment Checklist

### 1. Code Readiness ✅
- [x] All public store pages compile without errors
- [x] Complete purchase flow tested locally
- [x] All images load correctly
- [x] Database integration working
- [x] Cart functionality working
- [x] Checkout and order creation working
- [x] No console errors

### 2. Database Setup ✅
Ensure these tables exist in Supabase:
- [x] `products` (with `show_on_website` column)
- [x] `website_banners`
- [x] `featured_products`
- [x] `online_orders`
- [x] `online_order_items`

### 3. Content Setup ✅
- [x] At least 10-15 products with images
- [x] Products marked `show_on_website = true`
- [x] At least 1 active banner in `website_banners`
- [x] At least 8 featured products
- [x] Product images uploaded to Supabase Storage
- [x] All image URLs valid and accessible

### 4. Configuration Files ✅
Verify these files are correctly configured:
- [x] `lib/firebase_options.dart` (Firebase config)
- [x] `web/index.html` (Firebase SDK scripts)
- [x] `firebase.json` (hosting configuration)
- [x] `.firebaserc` (project aliases)

---

## 🏗️ Build Process

### Step 1: Clean Previous Builds
```bash
cd /Users/Claudio/Dev/bikeshop-erp
flutter clean
```

### Step 2: Get Dependencies
```bash
flutter pub get
```

### Step 3: Build for Web (Production)
```bash
flutter build web --release --web-renderer canvaskit
```

**Build flags explained:**
- `--release`: Optimized production build (smaller, faster)
- `--web-renderer canvaskit`: Better rendering, consistent across browsers

**Expected output:**
```
✓ Built build/web
```

**Build directory:** `build/web/`

---

## 🔧 Firebase Configuration

### Check Current Firebase Project
```bash
firebase projects:list
```

### Select Correct Project
```bash
firebase use default
# or
firebase use vinabike-erp
```

### Verify firebase.json Configuration

Your `firebase.json` should look like this:

```json
{
  "hosting": [
    {
      "target": "erp",
      "public": "build/web",
      "ignore": [
        "firebase.json",
        "**/.*",
        "**/node_modules/**"
      ],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ],
      "headers": [
        {
          "source": "**/*.@(jpg|jpeg|gif|png|svg|webp)",
          "headers": [
            {
              "key": "Cache-Control",
              "value": "max-age=31536000"
            }
          ]
        }
      ]
    },
    {
      "target": "store",
      "public": "build/web",
      "ignore": [
        "firebase.json",
        "**/.*",
        "**/node_modules/**"
      ],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ],
      "headers": [
        {
          "source": "**/*.@(jpg|jpeg|gif|png|svg|webp)",
          "headers": [
            {
              "key": "Cache-Control",
              "value": "max-age=31536000"
            }
          ]
        }
      ]
    }
  ]
}
```

### Check .firebaserc Configuration

Your `.firebaserc` should have:

```json
{
  "projects": {
    "default": "vinabike-erp"
  },
  "targets": {
    "vinabike-erp": {
      "hosting": {
        "erp": [
          "vinabike-erp"
        ],
        "store": [
          "vinabike-store"
        ]
      }
    }
  }
}
```

---

## 🌐 Deployment Options

### Option 1: Deploy Both Sites (ERP + Store)
```bash
firebase deploy --only hosting
```

### Option 2: Deploy Only Public Store
```bash
firebase deploy --only hosting:store
```

### Option 3: Deploy Only Admin ERP
```bash
firebase deploy --only hosting:erp
```

**Recommended:** Use Option 2 for first public store deployment.

---

## 📦 Deployment Command

### Deploy Public Store to vinabike-store.web.app
```bash
# Build production web app
flutter build web --release --web-renderer canvaskit

# Deploy to Firebase Hosting (store target)
firebase deploy --only hosting:store
```

**Expected output:**
```
=== Deploying to 'vinabike-erp'...

i  deploying hosting
i  hosting[vinabike-store]: beginning deploy...
i  hosting[vinabike-store]: found 50 files in build/web
✔  hosting[vinabike-store]: file upload complete
i  hosting[vinabike-store]: finalizing version...
✔  hosting[vinabike-store]: version finalized
i  hosting[vinabike-store]: releasing new version...
✔  hosting[vinabike-store]: release complete

✔  Deploy complete!

Project Console: https://console.firebase.google.com/project/vinabike-erp/overview
Hosting URL: https://vinabike-store.web.app
```

---

## ✅ Post-Deployment Verification

### 1. Check Live Site
Open in browser: `https://vinabike-store.web.app`

### 2. Test Complete Flow
- [ ] Homepage loads correctly
- [ ] Products display with images
- [ ] Search and filters work
- [ ] Product detail pages load
- [ ] Add to cart works
- [ ] Cart page displays correctly
- [ ] Checkout form works
- [ ] Order creation succeeds
- [ ] Order confirmation displays
- [ ] Contact page loads
- [ ] All navigation works
- [ ] No console errors

### 3. Test on Multiple Devices
- [ ] Desktop Chrome
- [ ] Desktop Safari
- [ ] Mobile iOS Safari
- [ ] Mobile Android Chrome
- [ ] Tablet

### 4. Performance Check
Open Chrome DevTools → Lighthouse:
- [ ] Performance score > 80
- [ ] Accessibility score > 90
- [ ] Best Practices score > 90
- [ ] SEO score > 80

### 5. Database Connection
- [ ] Verify orders save to Supabase
- [ ] Check order appears in admin ERP
- [ ] Verify inventory updates (if configured)

---

## 🔒 Security Checklist

### Supabase RLS (Row Level Security)
Ensure these policies exist:

**online_orders table:**
```sql
-- Allow anyone to insert orders (public store)
CREATE POLICY "Anyone can create orders"
ON online_orders FOR INSERT
TO anon, authenticated
WITH CHECK (true);

-- Allow reading own orders (optional, if you add customer accounts later)
CREATE POLICY "Users can view own orders"
ON online_orders FOR SELECT
TO authenticated
USING (customer_email = auth.jwt()->>'email');
```

**online_order_items table:**
```sql
-- Allow inserting order items with orders
CREATE POLICY "Anyone can create order items"
ON online_order_items FOR INSERT
TO anon, authenticated
WITH CHECK (true);
```

**products table:**
```sql
-- Allow public read of website products
CREATE POLICY "Anyone can view website products"
ON products FOR SELECT
TO anon, authenticated
USING (show_on_website = true);
```

**website_banners table:**
```sql
-- Allow public read of active banners
CREATE POLICY "Anyone can view active banners"
ON website_banners FOR SELECT
TO anon, authenticated
USING (active = true);
```

---

## 🐛 Troubleshooting

### Issue: Site shows blank page
**Possible causes:**
1. JavaScript not loading
2. Firebase config incorrect
3. Supabase connection failed

**Solution:**
- Check browser console for errors
- Verify `firebase_options.dart` has correct config
- Check Supabase URL and anon key in environment

### Issue: Images don't load
**Solution:**
- Check Supabase Storage bucket is public
- Verify image URLs in database
- Check CORS settings in Supabase

### Issue: Orders fail to create
**Solution:**
- Check Supabase RLS policies allow INSERT
- Verify table structure matches models
- Check browser console for error messages

### Issue: 404 on page refresh
**Solution:**
- Verify `firebase.json` has rewrites rule:
  ```json
  "rewrites": [
    {
      "source": "**",
      "destination": "/index.html"
    }
  ]
  ```

### Issue: Slow loading
**Solution:**
- Enable caching in `firebase.json`
- Optimize images (WebP format, compress)
- Use CDN for large files

---

## 🔄 Updating After Deployment

### To deploy updates:
```bash
# 1. Make code changes
# 2. Test locally
flutter run -d chrome --web-port=52010

# 3. Build production
flutter build web --release --web-renderer canvaskit

# 4. Deploy
firebase deploy --only hosting:store

# 5. Verify changes live
open https://vinabike-store.web.app
```

### Clear cache if needed:
```bash
# Clear Flutter cache
flutter clean

# Clear browser cache (hard refresh)
# Chrome: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Windows)
```

---

## 📊 Monitoring & Analytics

### Firebase Hosting Analytics
View in Firebase Console:
- Page views
- Bandwidth usage
- Error rates
- Geographic distribution

### Set Up Google Analytics (Optional)
1. Create GA4 property
2. Add tracking code to `web/index.html`
3. Monitor:
   - Page views
   - Purchase events
   - User flow
   - Conversion rate

---

## 🎯 Success Criteria

Deployment is successful when:
- ✅ Site loads at https://vinabike-store.web.app
- ✅ All pages accessible and functional
- ✅ Products display with images
- ✅ Complete purchase flow works
- ✅ Orders save to database
- ✅ No console errors
- ✅ Responsive on all devices
- ✅ Lighthouse score > 80
- ✅ Admin can view orders in ERP

---

## 📝 Deployment Checklist

```bash
# Copy and paste this checklist when deploying

[ ] Code changes tested locally
[ ] flutter clean completed
[ ] flutter pub get completed
[ ] flutter build web --release succeeded
[ ] build/web directory exists
[ ] firebase.json configured correctly
[ ] .firebaserc has store target
[ ] firebase deploy --only hosting:store executed
[ ] Deployment succeeded (check output)
[ ] Site loads at vinabike-store.web.app
[ ] Homepage displays correctly
[ ] Products load with images
[ ] Can add products to cart
[ ] Can complete checkout
[ ] Order saves to database
[ ] Order appears in admin ERP
[ ] Contact page works
[ ] All navigation works
[ ] No console errors
[ ] Tested on mobile device
[ ] Lighthouse score checked
[ ] Team notified of deployment
```

---

## 🌐 Live URLs

After deployment:
- **Public Store:** https://vinabike-store.web.app
- **Admin ERP:** https://vinabike-erp.web.app
- **Firebase Console:** https://console.firebase.google.com/project/vinabike-erp
- **Supabase Dashboard:** https://app.supabase.com/project/YOUR_PROJECT_ID

---

## 📞 Support

If you encounter issues:
1. Check browser console for errors
2. Check Firebase Hosting logs
3. Check Supabase logs
4. Review this guide
5. Check Flutter web documentation

---

**Ready to deploy?** Run the commands above and make your store live! 🚀✨
