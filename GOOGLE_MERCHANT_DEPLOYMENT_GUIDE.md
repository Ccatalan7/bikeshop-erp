# 🛍️ Google Merchant Center Deployment Guide

## 📋 Overview

This guide will help you deploy the Google Merchant product feed and connect it to Google Merchant Center for FREE product listings on Google Shopping.

---

## ✅ Prerequisites

Before starting, make sure you have:

- ✅ Supabase CLI installed
- ✅ Supabase project credentials
- ✅ Products in your database with images
- ✅ Website settings configured (store name, URL)

---

## 🚀 Step 1: Deploy the Edge Function

### 1.1 Login to Supabase CLI

```bash
supabase login
```

This will open a browser to authenticate.

### 1.2 Link Your Project

```bash
cd /Users/Claudio/Dev/bikeshop-erp
supabase link --project-ref YOUR_PROJECT_REF
```

**Find your project ref:**
- Go to [app.supabase.com](https://app.supabase.com)
- Open your project
- Settings → General → Project URL
- Extract the ref from: `https://YOUR_PROJECT_REF.supabase.co`

### 1.3 Deploy the Function

```bash
supabase functions deploy google-merchant-feed
```

**Expected output:**
```
Deploying function google-merchant-feed (project ref: your-project-ref)
Deployed function google-merchant-feed
URL: https://your-project-ref.supabase.co/functions/v1/google-merchant-feed
```

✅ **Copy this URL! You'll need it for Google Merchant Center.**

---

## 🧪 Step 2: Test the Feed

### 2.1 Open the Feed URL in Browser

```
https://YOUR_PROJECT_REF.supabase.co/functions/v1/google-merchant-feed
```

**You should see XML like this:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:g="http://base.google.com/ns/1.0">
  <channel>
    <title>Vinabike</title>
    <link>https://tienda.vinabike.cl</link>
    <description>Bicicletas y accesorios en Chile</description>
    <item>
      <g:id>123e4567-e89b-12d3-a456-426614174000</g:id>
      <g:title>Bicicleta MTB Expert 29"</g:title>
      <g:description>Bicicleta de montaña con suspensión...</g:description>
      <g:link>https://tienda.vinabike.cl/products/123...</g:link>
      <g:image_link>https://...</g:image_link>
      <g:condition>new</g:condition>
      <g:availability>in stock</g:availability>
      <g:price>450000 CLP</g:price>
      <g:brand>Vinabike</g:brand>
      <g:mpn>MTB-EXPERT-29</g:mpn>
      <g:product_type>Bicicletas</g:product_type>
    </item>
    <!-- More products... -->
  </channel>
</rss>
```

### 2.2 Verify Feed Content

Check that:
- ✅ All your active products appear
- ✅ Images have valid URLs
- ✅ Prices are in CLP
- ✅ Stock quantities are accurate
- ✅ Product descriptions are present

### 2.3 Troubleshooting

**❌ "Function not found" error:**
- Make sure you deployed successfully
- Check the URL matches your project ref

**❌ Empty feed:**
- Check products have `show_on_website = true`
- Check products have `stock_quantity > 0`
- Run in Supabase SQL editor:
```sql
SELECT id, name, stock_quantity, show_on_website 
FROM products 
WHERE show_on_website = true AND stock_quantity > 0;
```

**❌ Missing images:**
- Products need valid `image_url` column
- Upload images through the app first

---

## 🏪 Step 3: Create Google Merchant Center Account

### 3.1 Sign Up

1. Go to [merchants.google.com](https://merchants.google.com)
2. Click **"Get started"**
3. Sign in with Google account
4. Choose **Business name:** "Vinabike" (or your store name)
5. Choose **Country:** Chile 🇨🇱
6. Choose **Time zone:** America/Santiago

### 3.2 Verify Your Website

You need to prove you own your website. Choose one method:

#### Option A: HTML File Upload (Easiest for Firebase)

1. Google will give you a file like: `google1234567890abcdef.html`
2. Upload to Firebase Hosting:
```bash
# Save the file to public/ folder
echo "google-site-verification: google1234567890abcdef.html" > public/google1234567890abcdef.html

# Deploy
firebase deploy --only hosting:store
```
3. Click **"Verify"** in Google Merchant Center

#### Option B: Meta Tag (If using HTML index)

1. Google gives you a tag like:
```html
<meta name="google-site-verification" content="abc123..." />
```
2. Add to `web/index.html` in `<head>`:
```html
<head>
  <meta name="google-site-verification" content="YOUR_CODE" />
  ...
</head>
```
3. Rebuild and deploy:
```bash
flutter build web
firebase deploy --only hosting:store
```

#### Option C: Google Analytics (If already using)

1. If you have Google Analytics on your site
2. Just link the same account
3. Instant verification ✅

### 3.3 Claim Your Website URL

After verification:
1. Go to **Tools & Settings** → **Business information**
2. Click **"Claim website URL"**
3. Enter: `https://tienda.vinabike.cl` (or your domain)
4. Complete verification

---

## 📦 Step 4: Add Product Feed

### 4.1 Create a Feed

1. In Google Merchant Center, go to **Products** → **Feeds**
2. Click **"+" (Add feed)**
3. Choose:
   - **Country of sale:** Chile
   - **Language:** Spanish
   - **Destinations:** Surfaces across Google (Free listings)
   - **Feed name:** "Vinabike Products"

### 4.2 Configure Feed Settings

1. **Input method:** Scheduled fetch
2. **File name / URL:**
```
https://YOUR_PROJECT_REF.supabase.co/functions/v1/google-merchant-feed
```
3. **Fetch schedule:**
   - Frequency: Daily
   - Time: 3:00 AM (your choice)
   - Time zone: America/Santiago

### 4.3 Save and Test Fetch

1. Click **"Create feed"**
2. Click **"Fetch now"** to test immediately
3. Wait 1-2 minutes for processing

### 4.4 Check for Errors

After processing, you'll see:
- ✅ **Active products:** X items
- ⚠️ **Warnings:** Y items (optional fixes)
- ❌ **Errors:** Z items (must fix)

**Common errors:**

| Error | Fix |
|-------|-----|
| Missing GTIN | Add barcodes to products, or apply for GTIN exemption |
| Image URL broken | Check product `image_url` column |
| Invalid price | Make sure price > 0 |
| Missing description | Add description to products |

### 4.5 Request GTIN Exemption (If Needed)

If you don't have barcodes (GTINs):

1. Go to **Tools** → **GTIN exemptions**
2. Select categories (e.g., "Sporting Goods > Cycling")
3. Explain: "We sell custom/generic products without manufacturer barcodes"
4. Submit request
5. Usually approved in 2-3 days

---

## 🌟 Step 5: Enable Free Listings

### 5.1 Enroll in Surfaces Across Google

1. Go to **Growth** → **Manage programs**
2. Find **"Surfaces across Google"**
3. Click **"Get started"** or **"Enable"**
4. Accept terms and conditions
5. Choose **Free listings** (no cost!)

### 5.2 Program Options

- **Free listings:** Show products on Google Shopping tab (FREE ✅)
- **Shopping ads:** Pay-per-click ads (optional, costs money ❌)

Choose **Free listings only** for 100% free exposure!

---

## 🎉 Step 6: Verify Products Are Live

### 6.1 Wait for Processing

- Initial processing: 3-7 days
- Updates: Within 24 hours

### 6.2 Check Product Status

1. Go to **Products** → **Diagnostics**
2. Filter: **"Active"**
3. You should see your products listed

### 6.3 Search on Google

Try searching:
```
bicicleta mtb chile
bicicleta ruta santiago
```

Look for your products in the **Shopping** tab!

**Note:** It may take 1-2 weeks to start appearing in searches. Google needs to:
- Index your products
- Learn your relevance
- Build search rankings

---

## 📊 Step 7: Monitor Performance

### 7.1 Performance Dashboard

Go to **Performance** → **Dashboard** to see:
- Impressions (how many people saw your products)
- Clicks (how many clicked to your site)
- Click-through rate (CTR)

### 7.2 Optimize Listings

To improve visibility:

1. **Better product titles:**
   - Include brand, model, key features
   - Example: "Bicicleta MTB Giant Talon 29\" Frenos Disco"

2. **Quality images:**
   - High resolution (at least 800x800px)
   - White or neutral background
   - Multiple angles

3. **Detailed descriptions:**
   - Include specifications
   - Mention key features
   - Use natural language

4. **Competitive pricing:**
   - Check competitor prices
   - Offer fair value

5. **Keep stock updated:**
   - Mark out-of-stock items
   - Update regularly

---

## 🔧 Maintenance

### Daily (Automatic)

✅ Google fetches your feed daily at scheduled time
✅ Product updates sync automatically
✅ Stock changes reflected within 24 hours

### Weekly (Manual - Optional)

Review in Google Merchant Center:
1. Check for new errors/warnings
2. Fix any disapproved products
3. Monitor click-through rates
4. Adjust product titles/descriptions if needed

### Monthly (Manual - Recommended)

1. **Update product images** - Add new photos
2. **Add new products** - Make sure `show_on_website = true`
3. **Review pricing** - Stay competitive
4. **Check analytics** - See what's working

---

## 🚨 Troubleshooting

### Feed Not Updating

**Problem:** Changes don't appear in Google
**Solution:**
1. Check Supabase function logs:
```bash
supabase functions logs google-merchant-feed
```
2. Manually trigger fetch in Merchant Center
3. Wait 1-2 hours for cache to clear

### Products Disapproved

**Problem:** Products marked as disapproved
**Solution:**
1. Go to **Products** → **Diagnostics**
2. Click on disapproved item
3. Read the specific error
4. Fix in your database
5. Wait for next feed fetch

### Low Click-Through Rate

**Problem:** Products shown but not clicked
**Solution:**
1. Improve product titles (add keywords)
2. Use better images
3. Check pricing competitiveness
4. Add more product details

---

## 📚 Additional Resources

### Google Documentation

- [Merchant Center Help](https://support.google.com/merchants/)
- [Product Data Specification](https://support.google.com/merchants/answer/7052112)
- [Feed Specification](https://support.google.com/merchants/answer/7052112)

### Supabase Documentation

- [Edge Functions](https://supabase.com/docs/guides/functions)
- [Function Logs](https://supabase.com/docs/guides/functions/debugging)

---

## ✅ Checklist

Use this checklist to track your progress:

- [ ] Supabase CLI installed
- [ ] Project linked to CLI
- [ ] Edge function deployed
- [ ] Feed URL tested in browser
- [ ] Products appearing in feed
- [ ] Images loading correctly
- [ ] Google Merchant account created
- [ ] Website verified
- [ ] Website URL claimed
- [ ] Product feed added
- [ ] Test fetch successful
- [ ] No critical errors
- [ ] GTIN exemption requested (if needed)
- [ ] Free listings enabled
- [ ] Products showing as "Active"
- [ ] Products appearing in Google Shopping (after 1-2 weeks)

---

## 🎊 Success!

Once complete, your products will:

- ✅ Appear in Google Shopping searches (FREE!)
- ✅ Update automatically daily
- ✅ Show current stock and pricing
- ✅ Drive traffic to your website
- ✅ Increase sales with zero ad spend

**This is 100% FREE marketing! 🎉**

---

## 💡 Pro Tips

1. **Use high-quality images** - They get more clicks
2. **Optimize titles** - Include brand + model + key features
3. **Price competitively** - Check what others charge
4. **Keep stock updated** - Out-of-stock hurts rankings
5. **Monitor weekly** - Fix errors quickly
6. **Add new products** - More products = more visibility
7. **Use promotions** - Google loves sales/discounts
8. **Get reviews** - If possible, add product ratings

---

**Need help? Check Supabase logs or Google Merchant diagnostics!**
