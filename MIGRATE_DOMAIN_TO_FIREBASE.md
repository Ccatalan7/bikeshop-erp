# 🌐 Migrate Custom Domain from Odoo to Firebase Hosting

## Overview

This guide helps you migrate your existing domain from Odoo to Firebase Hosting for the public store. You'll be updating DNS records in Cloudflare to point to Firebase instead of Odoo.

---

## Prerequisites

- ✅ Domain registered on nic.cl
- ✅ DNS managed through Cloudflare
- ✅ Firebase project: `project-vinabike`
- ✅ Firebase Hosting targets: `erp` and `store`
- ✅ Firebase CLI installed and authenticated

---

## Step 1: Connect Custom Domain in Firebase Console

### 1.1 Open Firebase Hosting Settings

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **project-vinabike**
3. Navigate to: **Hosting** → **Get Started** (or view existing sites)
4. Find your **store** site (should be something like `project-vinabike-store` or similar)

### 1.2 Add Custom Domain

1. Click **Add custom domain** button
2. Enter your domain name (e.g., `www.vinabike.cl` or `vinabike.cl`)
   - **Recommended:** Start with `www.vinabike.cl` first
   - You can add the apex domain (`vinabike.cl`) later and redirect it to `www`

3. Firebase will guide you through verification and provide DNS records

---

## Step 2: Firebase Provides DNS Records

After adding your domain, Firebase will show you the required DNS records. These typically include:

### For `www.vinabike.cl` (subdomain):

**Type:** `A`  
**Name:** `www`  
**Value:** Firebase IP addresses (usually 4 IPs like):
- `151.101.1.195`
- `151.101.65.195`
- `151.101.129.195`
- `151.101.193.195`

Or sometimes Firebase uses:

**Type:** `CNAME`  
**Name:** `www`  
**Value:** `<your-project>.web.app` or similar

### For `vinabike.cl` (apex/root domain):

**Type:** `A`  
**Name:** `@` (or leave empty)  
**Value:** Firebase IP addresses (same as above)

---

## Step 3: Update DNS Records in Cloudflare

### 3.1 Login to Cloudflare

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Select your domain: **vinabike.cl**
3. Go to **DNS** tab

### 3.2 Identify Current Odoo Records

Before changing anything, **document your current DNS records**:

```bash
# Take screenshots or note down:
- Current A records pointing to Odoo
- Current CNAME records
- Current TXT records (keep these if they're for email verification)
- Current MX records (keep these - they're for email)
```

### 3.3 Update DNS Records for Firebase

**Option A: Using A Records (Recommended for reliability)**

1. Delete or modify existing `A` record for `www`:
   - Click the existing `A` record for `www.vinabike.cl`
   - Click **Edit**
   - Replace the IP with Firebase IPs (you'll need to add 4 separate A records):

   ```
   Type: A
   Name: www
   IPv4 address: 151.101.1.195
   Proxy status: DNS only (gray cloud) ⚠️ IMPORTANT
   TTL: Auto
   ```

   Repeat for the other 3 Firebase IPs:
   - `151.101.65.195`
   - `151.101.129.195`
   - `151.101.193.195`

2. **⚠️ CRITICAL:** Set Proxy status to **DNS only** (gray cloud icon)
   - Click the orange cloud to turn it gray
   - Firebase SSL won't work with Cloudflare's proxy enabled

**Option B: Using CNAME (If Firebase provides one)**

1. Delete existing `A` record for `www`
2. Create new `CNAME` record:

   ```
   Type: CNAME
   Name: www
   Target: <your-firebase-subdomain>.web.app
   Proxy status: DNS only (gray cloud) ⚠️ IMPORTANT
   TTL: Auto
   ```

### 3.4 Add Apex Domain (Optional - Do this AFTER www works)

If you want `vinabike.cl` (without www) to work:

1. Add 4 `A` records with **Name: @** (or leave empty):
   - Same Firebase IPs as above
   - Proxy status: DNS only (gray cloud)

2. Or use **Cloudflare Page Rules** to redirect `vinabike.cl` → `www.vinabike.cl`

---

## Step 4: Verify DNS Changes

### 4.1 Check DNS Propagation

DNS changes can take **5 minutes to 48 hours** to propagate globally. Check status:

```bash
# Check DNS records (macOS/Linux)
dig www.vinabike.cl
dig vinabike.cl

# Or use online tools:
# - https://dnschecker.org/
# - https://www.whatsmydns.net/
```

### 4.2 Monitor Firebase Console

1. Return to Firebase Console → Hosting → Custom domains
2. Firebase will automatically verify DNS records
3. Status will change from:
   - **Needs Setup** → **Pending** → **Connected**
4. Firebase will provision SSL certificate (automatic, takes 10-30 minutes)

---

## Step 5: Test the Migration

### 5.1 Wait for SSL Certificate

- Firebase will automatically provision a free SSL certificate
- This takes **10-30 minutes** after DNS propagation
- You'll see "Certificate provisioning in progress" in Firebase Console

### 5.2 Test the Domain

Once status shows **Connected**:

```bash
# Test HTTP redirect to HTTPS
curl -I http://www.vinabike.cl

# Test HTTPS works
curl -I https://www.vinabike.cl

# Test in browser
open https://www.vinabike.cl
```

### 5.3 Verify Public Store Works

1. Open: `https://www.vinabike.cl`
2. Should see your public store (anonymous access)
3. Check subdomain detection works:
   - URLs should work for tenant-specific stores
   - Products should load correctly
   - Checkout should work for guest users

---

## Step 6: Migrate from Odoo (Downtime Strategy)

### Option A: Zero-Downtime Migration (Recommended)

1. **Keep Odoo running** on old DNS while setting up Firebase
2. Use a **temporary subdomain** for testing:
   - Set up `store.vinabike.cl` → Firebase first
   - Test thoroughly
   - Then switch `www.vinabike.cl` → Firebase
3. DNS changes are instant once propagated (no downtime)

### Option B: Scheduled Downtime

1. Put up a maintenance page on Odoo
2. Update DNS records
3. Wait for propagation (30 minutes - 2 hours typically)
4. Firebase goes live

### Option C: Parallel Run

1. Set up Firebase on `www.vinabike.cl`
2. Keep Odoo on `shop.vinabike.cl` (if you have it)
3. Gradually migrate users
4. Shut down Odoo once Firebase is stable

---

## Step 7: Update Firebase Hosting Configuration

### 7.1 Verify Target Deployment

After domain is connected, deploy to the store target:

```bash
# Build Flutter app
flutter build web --release

# Deploy only the store site
firebase deploy --only hosting:store

# Or deploy both sites
firebase deploy --only hosting
```

### 7.2 Set Store Site as Default Domain (Optional)

If you want `www.vinabike.cl` to be the primary domain for the store site:

1. Firebase Console → Hosting → Store site
2. Click on the 3 dots next to your custom domain
3. Select **Set as default domain**

---

## Troubleshooting

### DNS Not Propagating

```bash
# Clear local DNS cache (macOS)
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Check Cloudflare DNS settings
# Make sure Proxy is OFF (gray cloud)
```

### SSL Certificate Issues

- **Problem:** "Not Secure" warning in browser
- **Solution:** Wait 30 minutes after DNS propagation
- Firebase auto-provisions SSL via Let's Encrypt
- Check Firebase Console for certificate status

### Subdomain Detection Not Working

- **Problem:** Tenant detection fails on custom domain
- **Solution:** Check `PublicStoreTenantProvider` logic
- May need to update subdomain parsing logic for custom domain

### Cloudflare Proxy Issues

- **Problem:** Firebase shows "DNS verification failed"
- **Solution:** Disable Cloudflare proxy (orange cloud → gray cloud)
- Firebase needs direct DNS control for SSL provisioning

### Multiple A Records

If you see multiple A records for the same subdomain:
1. Delete ALL existing A records for `www`
2. Add the 4 Firebase A records (one for each IP)
3. Save and wait for propagation

---

## Rollback Plan (If Things Go Wrong)

### Quick Rollback to Odoo

1. Go to Cloudflare DNS
2. Change `www` A/CNAME records back to Odoo IP/hostname
3. DNS propagation: 5-30 minutes
4. Odoo site will be live again

### Keep Old DNS Records

Before deleting, save your old Odoo DNS records:

```
# Example (replace with your actual values)
Type: A
Name: www
Value: 123.456.789.0 (Odoo server IP)
```

---

## Post-Migration Checklist

- [ ] Custom domain shows in Firebase Console as **Connected**
- [ ] SSL certificate provisioned (green lock in browser)
- [ ] Public store loads on `https://www.vinabike.cl`
- [ ] Tenant subdomain detection works
- [ ] Product catalog loads correctly
- [ ] Guest checkout works (order creation)
- [ ] Images/assets load from Firebase Storage
- [ ] No mixed content warnings (HTTP resources on HTTPS page)
- [ ] Mobile responsive design works
- [ ] SEO meta tags present (check view-source)
- [ ] Analytics/tracking still works (if applicable)

---

## Additional Resources

- [Firebase Custom Domain Documentation](https://firebase.google.com/docs/hosting/custom-domain)
- [Cloudflare DNS Documentation](https://developers.cloudflare.com/dns/)
- [DNS Propagation Checker](https://dnschecker.org/)

---

## Summary

**Total Migration Time:** 1-4 hours (mostly waiting for DNS propagation)

**Steps:**
1. Add custom domain in Firebase Console (5 min)
2. Update DNS in Cloudflare (10 min)
3. Wait for DNS propagation (30 min - 2 hours)
4. Firebase provisions SSL (10-30 min)
5. Test and verify (15 min)

**Downtime:** Near-zero if using temporary subdomain for testing first

**Risk:** Low - DNS changes are reversible

---

## Need Help?

If you encounter issues:
1. Check Firebase Console status messages
2. Verify DNS records in Cloudflare
3. Test DNS propagation with `dig` or online tools
4. Check browser console for errors
5. Review Firebase Hosting logs

**Firebase Hosting is production-ready and handles SSL, CDN, and global distribution automatically!**
