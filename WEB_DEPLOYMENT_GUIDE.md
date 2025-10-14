# 🌐 Deploy Vinabike ERP to Custom Domain - Complete Guide

## 📋 Overview

This guide will help you deploy your **Supabase-based** Flutter ERP app to the web with a custom domain (e.g., `vinabike.com`, `erp.yourbikeshop.com`) so users worldwide can access it via any web browser.

**Important:** Your app uses **Supabase** for everything (PostgreSQL, Auth, Storage), so we'll deploy the Flutter web app to a static hosting provider.

---

## 🎯 Deployment Options

### Option 1: Vercel (Recommended - Best for Supabase)
- ✅ **Free tier:** Unlimited bandwidth
- ✅ **Automatic SSL/HTTPS**
- ✅ **Global CDN** (fast worldwide)
- ✅ **Perfect for Supabase apps**
- ✅ **Zero configuration**
- ✅ **GitHub integration**
- ⏱️ **Setup time:** 10-15 minutes

### Option 2: Vercel (Great Alternative)
- ✅ **Free tier:** Unlimited bandwidth
- ✅ **Automatic SSL/HTTPS**
- ✅ **Global CDN**
- ✅ **Fast deployment**
- ⏱️ **Setup time:** 20-30 minutes

### Option 3: Netlify (Another Good Option)
- ✅ **Free tier:** 100GB bandwidth/month
- ✅ **Automatic SSL/HTTPS**
- ✅ **Global CDN**
- ⏱️ **Setup time:** 20-30 minutes

### Option 4: Self-Hosted VPS (Advanced)
- 💰 **Cost:** $5-20/month (DigitalOcean, Linode, AWS)
- ⚙️ **Full control** over server
- 🔧 **Manual SSL setup** required
- ⏱️ **Setup time:** 1-2 hours

---

## 📍 We'll Use Firebase Hosting (Easiest Path)

Since you already have Firebase configured, this is the fastest route!

---

## 📝 Step-by-Step Deployment Process

### 🔹 Phase 1: Prerequisites (5 minutes)

#### 1.1 Install Firebase CLI
```powershell
# Install via npm (Node.js required)
npm install -g firebase-tools

# Verify installation
firebase --version
```

**Don't have Node.js?**
- Download from: https://nodejs.org/
- Install LTS version
- Restart PowerShell after installation

#### 1.2 Login to Firebase
```powershell
firebase login
```
- Opens browser for Google authentication
- Login with your Google account (same one used for Firebase project)

#### 1.3 Verify Firebase Project
```powershell
# Check your project ID
firebase projects:list

# Should show: project-vinabike
```

---

### 🔹 Phase 2: Configure Firebase Hosting (10 minutes)

#### 2.1 Initialize Firebase Hosting
```powershell
cd C:\dev\ProjectVinabike

# Initialize hosting
firebase init hosting
```

**When prompted, answer:**
- ❓ **Project?** → Select `project-vinabike`
- ❓ **Public directory?** → Enter: `build/web`
- ❓ **Single-page app?** → **YES** (important!)
- ❓ **Overwrite index.html?** → **NO**
- ❓ **Set up GitHub Actions?** → NO (unless you want CI/CD)

#### 2.2 Update firebase.json
The firebase.json should look like this:

```json
{
  "hosting": {
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
        "source": "**",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "no-cache, no-store, must-revalidate"
          }
        ]
      },
      {
        "source": "**/*.@(jpg|jpeg|gif|png|svg|webp|js|css|woff|woff2)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "max-age=31536000"
          }
        ]
      }
    ]
  },
  "firestore": {
    "rules": "firestore.rules"
  }
}
```

---

### 🔹 Phase 3: Build Your Web App (5 minutes)

#### 3.1 Clean Previous Builds
```powershell
flutter clean
```

#### 3.2 Build Production Web App
```powershell
# Build optimized web version
flutter build web --release

# This creates: build/web/
```

**Output:**
- HTML, CSS, JavaScript files
- Optimized for production
- Ready to deploy

#### 3.3 Verify Build
```powershell
# Check if build folder exists
ls build/web/
```

Should see:
- `index.html`
- `flutter.js`
- `main.dart.js`
- `assets/`
- `icons/`

---

### 🔹 Phase 4: Deploy to Firebase (2 minutes)

#### 4.1 Deploy to Firebase Hosting
```powershell
firebase deploy --only hosting
```

**Output example:**
```
✔ Deploy complete!

Project Console: https://console.firebase.google.com/project/project-vinabike/overview
Hosting URL: https://project-vinabike.web.app
```

#### 4.2 Test Your App
Open the Hosting URL in your browser:
- `https://project-vinabike.web.app`
- OR: `https://project-vinabike.firebaseapp.com`

**✅ Your app is now live!** (But still on Firebase's default domain)

---

### 🔹 Phase 5: Get a Custom Domain (15-30 minutes)

#### 5.1 Register a Domain

**Popular Domain Registrars:**
- **Namecheap** (Recommended): https://www.namecheap.com
  - ~$10-15/year for .com
- **Google Domains**: https://domains.google/
- **GoDaddy**: https://www.godaddy.com
- **Cloudflare**: https://www.cloudflare.com/products/registrar/

**Choose a domain:**
- `vinabike.com`
- `vinabike.cl` (if in Chile)
- `vinabike-erp.com`
- `erp.yourbikeshop.com` (subdomain)

#### 5.2 Purchase Domain
1. Search for your desired domain
2. Add to cart
3. Complete checkout
4. You'll receive confirmation email

---

### 🔹 Phase 6: Connect Custom Domain to Firebase (20 minutes)

#### 6.1 Add Domain in Firebase Console

1. Go to: https://console.firebase.google.com/project/project-vinabike/hosting
2. Click **"Add custom domain"**
3. Enter your domain (e.g., `vinabike.com` or `www.vinabike.com`)
4. Click **"Continue"**

#### 6.2 Verify Domain Ownership

Firebase will show you a **TXT record** to add:

```
Type: TXT
Name: @
Value: something-like-firebase=abcdef123456
TTL: 3600
```

#### 6.3 Add TXT Record to Your Domain Registrar

**Example for Namecheap:**
1. Login to Namecheap
2. Go to **Domain List** → Click **Manage** on your domain
3. Go to **Advanced DNS** tab
4. Click **Add New Record**
5. Select **TXT Record**
   - **Host:** `@`
   - **Value:** (paste from Firebase)
   - **TTL:** Automatic
6. Click **Save All Changes**

**Wait 5-60 minutes** for DNS propagation (usually 5-10 min)

#### 6.4 Verify in Firebase

1. Back in Firebase Console
2. Click **"Verify"**
3. Firebase will check the TXT record
4. ✅ Once verified, you'll see DNS configuration instructions

#### 6.5 Add DNS Records for Your Domain

Firebase will show you **A records** to add:

```
Type: A
Name: @ (or your subdomain)
Value: 151.101.1.195
TTL: 3600

Type: A
Name: @ (or your subdomain)
Value: 151.101.65.195
TTL: 3600
```

**Add these in your domain registrar:**

1. Go back to **Advanced DNS** tab
2. Remove any existing A records for `@` or `www`
3. Add the A records provided by Firebase
4. Click **Save All Changes**

#### 6.6 Wait for SSL Certificate

- Firebase automatically provisions an **SSL certificate**
- Takes **5-60 minutes** (usually 15-20 min)
- You'll receive an email when ready
- Status shows in Firebase Console

---

### 🔹 Phase 7: Configure WWW Redirect (Optional but Recommended)

To make both `vinabike.com` and `www.vinabike.com` work:

#### 7.1 Add WWW Domain in Firebase
1. Click **"Add custom domain"** again
2. Enter `www.vinabike.com`
3. Follow same verification process

#### 7.2 Configure Redirect
Firebase can automatically redirect `www` to non-www or vice versa.

---

### 🔹 Phase 8: Update Your App Configuration (Important!)

#### 8.1 Update index.html Title and Meta
```powershell
# Edit: web/index.html
```

Update to:
```html
<title>Vinabike ERP - Sistema de Gestión</title>
<meta name="description" content="Sistema ERP completo para gestión de bikeshop">
```

#### 8.2 Rebuild and Redeploy
```powershell
flutter build web --release
firebase deploy --only hosting
```

---

## 🎉 You're Live!

Your app is now accessible at:
- ✅ `https://vinabike.com` (or your domain)
- ✅ `https://www.vinabike.com` (if configured)
- ✅ Secure HTTPS connection
- ✅ Accessible worldwide

---

## 🔒 Security Considerations

### Update Supabase Settings

1. Go to: https://supabase.com/dashboard/project/your-project
2. **Settings** → **API**
3. Add your custom domain to **Site URL**:
   - `https://vinabike.com`
4. Add to **Redirect URLs**:
   - `https://vinabike.com/**`

This ensures OAuth and authentication work correctly.

---

## 📊 Monitoring & Analytics

### Firebase Hosting Dashboard
- View traffic stats
- Monitor bandwidth usage
- Check deployment history
- URL: https://console.firebase.google.com/project/project-vinabike/hosting

### Add Google Analytics (Optional)
1. Create GA4 property
2. Add tracking code to `web/index.html`
3. Monitor user behavior

---

## 🔄 Updating Your App

Whenever you make changes:

```powershell
# 1. Make your code changes
# 2. Build new version
flutter build web --release

# 3. Deploy to Firebase
firebase deploy --only hosting

# Done! Changes live in ~30 seconds
```

---

## 💡 Performance Optimization

### Enable Caching (Already in firebase.json)
- Static assets cached for 1 year
- HTML/data not cached (always fresh)

### Enable Compression
Firebase automatically enables gzip compression

### Use CDN
Firebase Hosting uses Google's global CDN automatically

---

## 🐛 Troubleshooting

### "Site can't be reached"
- **Wait:** DNS changes take 5-60 minutes
- **Check DNS:** Use https://dnschecker.org/
- **Clear cache:** Try incognito mode

### "Not Secure" warning
- **Wait:** SSL certificate takes 15-60 minutes
- **Check:** Firebase console shows "Connected" status

### App loads but white screen
- **Check console:** Open browser DevTools (F12)
- **CORS issues:** Update Supabase allowed origins
- **Build again:** `flutter clean && flutter build web`

### Authentication not working
- **Update Supabase:** Add domain to allowed URLs
- **Check OAuth:** Update redirect URLs

---

## 💰 Cost Estimate

### Firebase Hosting Free Tier:
- ✅ **Storage:** 10 GB
- ✅ **Bandwidth:** 360 MB/day (~10 GB/month)
- ✅ **SSL:** Free
- ✅ **CDN:** Free

**Good for:** 50-100 daily users

### Paid Tier (if needed):
- **Blaze Plan:** Pay as you go
- **Storage:** $0.026/GB/month
- **Bandwidth:** $0.15/GB
- **Typical cost:** $5-20/month for small business

### Domain Cost:
- **Registration:** $10-15/year
- **Renewal:** Same annually

**Total first year:** ~$10-15 (just domain)

---

## 🚀 Quick Deploy Script

Save this as `deploy.ps1`:

```powershell
# Vinabike ERP - Quick Deploy Script

Write-Host "🚀 Building Vinabike ERP for Web..." -ForegroundColor Cyan

# Clean previous build
flutter clean

# Build web app
flutter build web --release

Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host "📤 Deploying to Firebase..." -ForegroundColor Cyan

# Deploy to Firebase
firebase deploy --only hosting

Write-Host "🎉 Deployment complete!" -ForegroundColor Green
Write-Host "🌐 Your app is live!" -ForegroundColor Yellow
```

Run with:
```powershell
.\deploy.ps1
```

---

## 📚 Additional Resources

- **Firebase Hosting Docs:** https://firebase.google.com/docs/hosting
- **Flutter Web Docs:** https://docs.flutter.dev/platform-integration/web
- **Custom Domain Setup:** https://firebase.google.com/docs/hosting/custom-domain
- **DNS Checker:** https://dnschecker.org/

---

## ✅ Checklist

- [ ] Install Firebase CLI
- [ ] Login to Firebase
- [ ] Initialize Firebase Hosting
- [ ] Build web app (`flutter build web --release`)
- [ ] Deploy to Firebase (`firebase deploy --only hosting`)
- [ ] Register custom domain
- [ ] Add domain to Firebase
- [ ] Verify domain ownership (TXT record)
- [ ] Configure DNS (A records)
- [ ] Wait for SSL certificate
- [ ] Update Supabase allowed URLs
- [ ] Test app on custom domain
- [ ] Configure www redirect (optional)
- [ ] Set up monitoring/analytics (optional)

---

Need help with any step? Just ask! 🚴‍♂️
