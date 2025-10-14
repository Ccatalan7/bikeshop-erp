# 🌐 Deploy Vinabike ERP (Supabase) to Custom Domain - Complete Guide

## 📋 Overview

This guide will help you deploy your **Supabase-based** Flutter ERP app to the web with a custom domain so users worldwide can access it via any web browser.

**Architecture:**
- **Frontend:** Flutter Web (static files)
- **Backend:** Supabase (PostgreSQL, Auth, Storage)
- **Hosting:** Static hosting provider (Vercel/Netlify)
- **Custom Domain:** Your own domain (e.g., vinabike.com)

---

## 🎯 Deployment Options (Best for Supabase Apps)

### Option 1: Vercel (Recommended)
- ✅ **Free tier:** Unlimited bandwidth
- ✅ **Automatic SSL/HTTPS**
- ✅ **Global CDN**
- ✅ **Perfect for Supabase apps**
- ✅ **GitHub integration** (auto-deploy on push)
- ✅ **Zero configuration needed**
- ⏱️ **Setup time:** 10-15 minutes

### Option 2: Netlify
- ✅ **Free tier:** 100GB bandwidth/month
- ✅ **Automatic SSL/HTTPS**
- ✅ **Global CDN**
- ✅ **Drag-and-drop deployment**
- ⏱️ **Setup time:** 10-15 minutes

### Option 3: Cloudflare Pages
- ✅ **Free tier:** Unlimited bandwidth
- ✅ **Automatic SSL/HTTPS**
- ✅ **Global CDN** (Cloudflare's network)
- ✅ **Fast deployment**
- ⏱️ **Setup time:** 15-20 minutes

### Option 4: Self-Hosted (VPS)
- 💰 **Cost:** $5-20/month
- ⚙️ **Full control**
- 🔧 **Manual setup required**
- ⏱️ **Setup time:** 1-2 hours

---

## 📍 We'll Use Vercel (Best Choice)

Vercel is the best option for Supabase apps - it's free, fast, and requires zero configuration!

---

## 📝 Step-by-Step Deployment Process

### 🔹 Phase 1: Build Your Web App (5 minutes)

#### 1.1 Clean Previous Builds
```powershell
cd C:\dev\ProjectVinabike
flutter clean
```

#### 1.2 Build Production Web App
```powershell
flutter build web --release
```

**This creates:** `build/web/` folder with:
- `index.html`
- `flutter.js`
- `main.dart.js`
- `assets/`
- All optimized files

#### 1.3 Verify Build
```powershell
ls build/web/
```

---

### 🔹 Phase 2: Deploy to Vercel (10 minutes)

#### Method A: Using Vercel CLI (Fastest)

##### 2.1 Install Vercel CLI
```powershell
npm install -g vercel
```

##### 2.2 Login to Vercel
```powershell
vercel login
```
- Opens browser
- Login with GitHub, GitLab, or email

##### 2.3 Deploy Your App
```powershell
# Navigate to build folder
cd build/web

# Deploy
vercel --prod
```

**Follow prompts:**
- ❓ **Set up and deploy?** → Y
- ❓ **Which scope?** → Select your account
- ❓ **Link to existing project?** → N
- ❓ **Project name?** → vinabike-erp
- ❓ **Directory?** → ./ (current)
- ❓ **Override settings?** → N

**Output:**
```
✅ Deployed to production!
🔗 https://vinabike-erp.vercel.app
```

#### Method B: Using Vercel Dashboard (No CLI needed)

##### 2.1 Go to Vercel
https://vercel.com/

##### 2.2 Sign Up/Login
- Use GitHub, GitLab, or Email

##### 2.3 Create New Project
1. Click **"Add New"** → **"Project"**
2. Click **"Continue with GitHub"** (or GitLab/Bitbucket)
3. Authorize Vercel to access your repos

##### 2.4 Import Your Repository
1. Find `bikeshop-erp` in the list
2. Click **"Import"**

##### 2.5 Configure Project
- **Framework Preset:** Other
- **Root Directory:** ./
- **Build Command:** `flutter build web --release`
- **Output Directory:** `build/web`
- **Install Command:** Leave empty (Flutter pre-installed)

##### 2.6 Add Environment Variables (if needed)
- Click **"Environment Variables"**
- Add any Flutter/Supabase env vars if you use them

##### 2.7 Deploy
- Click **"Deploy"**
- Wait 2-5 minutes
- ✅ Done!

Your app is now live at: `https://vinabike-erp-xxxxx.vercel.app`

---

### 🔹 Phase 3: Configure Supabase for Web (Important!)

#### 3.1 Update Supabase Project Settings

1. Go to: https://supabase.com/dashboard
2. Select your project
3. Go to **Settings** → **API**

#### 3.2 Add Your Vercel URL to Allowed Origins

**Site URL:**
```
https://vinabike-erp.vercel.app
```

**Redirect URLs:** Add these:
```
https://vinabike-erp.vercel.app/**
https://vinabike-erp.vercel.app/auth/callback
```

This ensures OAuth (Google login, etc.) works correctly!

#### 3.3 Update CORS Settings

In **Settings** → **API** → **CORS Settings**:
- Add: `https://vinabike-erp.vercel.app`

---

### 🔹 Phase 4: Get a Custom Domain (15-30 minutes)

#### 4.1 Register a Domain

**Popular Domain Registrars:**
- **Namecheap** (Recommended): https://www.namecheap.com
  - ~$10-15/year for .com
  - ~$15-20/year for .cl (Chile)
- **Google Domains**: https://domains.google/
- **Cloudflare**: https://www.cloudflare.com/products/registrar/ (cheapest)
- **GoDaddy**: https://www.godaddy.com

**Choose a domain:**
- `vinabike.com`
- `vinabike.cl` (Chile)
- `erp.vinabike.com`
- `app.vinabike.com`

#### 4.2 Purchase Domain
1. Search for domain
2. Add to cart
3. Complete checkout
4. Receive confirmation email

---

### 🔹 Phase 5: Connect Custom Domain to Vercel (20 minutes)

#### 5.1 Add Domain in Vercel

1. Go to: https://vercel.com/dashboard
2. Select your **vinabike-erp** project
3. Go to **Settings** → **Domains**
4. Click **"Add Domain"**
5. Enter your domain: `vinabike.com`
6. Click **"Add"**

#### 5.2 Configure DNS

Vercel will show you DNS records to add. Two options:

**Option A: Using Vercel Nameservers (Easiest)**

Vercel provides nameservers like:
```
ns1.vercel-dns.com
ns2.vercel-dns.com
```

**Steps:**
1. Go to your domain registrar (e.g., Namecheap)
2. Go to **Domain List** → **Manage**
3. Find **Nameservers** section
4. Select **"Custom DNS"**
5. Add Vercel's nameservers
6. Save changes
7. Wait 1-48 hours for propagation (usually 1-4 hours)

**Option B: Using A/CNAME Records**

Vercel shows records like:
```
Type: A
Name: @
Value: 76.76.21.21
TTL: 3600

Type: CNAME  
Name: www
Value: cname.vercel-dns.com
TTL: 3600
```

**Steps:**
1. Go to domain registrar → **DNS Management**
2. Add the A record for root domain (`@`)
3. Add the CNAME record for www
4. Save changes
5. Wait 5-60 minutes for propagation

#### 5.3 Verify Domain

1. Back in Vercel, click **"Refresh"**
2. Once DNS propagates, Vercel auto-issues SSL certificate
3. Takes 5-30 minutes
4. Status shows **"Valid"** when ready

#### 5.4 Set as Production Domain

1. Click **"Edit"** next to your domain
2. Check **"Redirect to this domain"** (makes it primary)
3. Save

---

### 🔹 Phase 6: Update Supabase with Custom Domain (Critical!)

#### 6.1 Update Site URL

1. Go to Supabase Dashboard
2. **Settings** → **API**
3. Update **Site URL** to:
   ```
   https://vinabike.com
   ```

#### 6.2 Update Redirect URLs

Add these:
```
https://vinabike.com/**
https://vinabike.com/auth/callback
https://www.vinabike.com/**
https://www.vinabike.com/auth/callback
```

#### 6.3 Update OAuth Providers

If using Google/GitHub login:

**For Google OAuth:**
1. Go to: https://console.cloud.google.com/
2. Select your project
3. Go to **APIs & Services** → **Credentials**
4. Edit your OAuth 2.0 Client
5. Add **Authorized redirect URIs:**
   ```
   https://vinabike.com/auth/callback
   https://[your-supabase-project].supabase.co/auth/v1/callback
   ```

**For GitHub OAuth:**
1. Go to: https://github.com/settings/developers
2. Select your OAuth App
3. Update **Authorization callback URL:**
   ```
   https://[your-supabase-project].supabase.co/auth/v1/callback
   ```

---

### 🔹 Phase 7: Test Your Deployment

#### 7.1 Test Basic Access
Visit: `https://vinabike.com`
- ✅ App loads correctly
- ✅ HTTPS (green padlock)
- ✅ No console errors

#### 7.2 Test Authentication
- ✅ Login with email/password works
- ✅ Google OAuth works (if configured)
- ✅ Session persists

#### 7.3 Test Supabase Connection
- ✅ Can load data from database
- ✅ Can create/update records
- ✅ Images load from Supabase Storage

#### 7.4 Test Logo Upload Feature
- ✅ Can upload company logo
- ✅ Logo displays in header
- ✅ Logo is clickable

---

## 🎉 You're Live!

Your app is now accessible at:
- ✅ `https://vinabike.com` (your custom domain)
- ✅ `https://www.vinabike.com` (if configured)
- ✅ Secure HTTPS connection
- ✅ Accessible worldwide
- ✅ Connected to Supabase backend

---

## 🔄 Updating Your App

### Method 1: Vercel CLI (Fast)
```powershell
# Build new version
flutter build web --release

# Deploy
cd build/web
vercel --prod
```

### Method 2: GitHub Integration (Automatic)

If you connected GitHub:
1. Push changes to your repository:
   ```powershell
   git add .
   git commit -m "Update app"
   git push origin main
   ```
2. Vercel automatically builds and deploys!
3. Live in ~2 minutes

### Method 3: Vercel Dashboard
1. Go to your project in Vercel
2. Click **"Redeploy"**
3. Done!

---

## 🚀 Optional: Set Up CI/CD with GitHub

### 8.1 Connect GitHub to Vercel

1. In Vercel Dashboard → Project Settings
2. Go to **Git** tab
3. Click **"Connect Git Repository"**
4. Select your repo: `bikeshop-erp`

### 8.2 Configure Build Settings

Vercel will detect Flutter automatically, but verify:
- **Build Command:** `flutter build web --release`
- **Output Directory:** `build/web`
- **Install Command:** (leave empty)

### 8.3 Enable Auto-Deploy

- ✅ **Production Branch:** `main` or `master`
- ✅ **Deploy on Push:** Enabled
- ✅ **Preview Branches:** All branches get preview URLs

Now every push to `main` automatically deploys to production!

---

## 💰 Cost Estimate

### Free Tier (Vercel)
- ✅ **Bandwidth:** Unlimited
- ✅ **Builds:** 6,000 minutes/month
- ✅ **Serverless Functions:** 100GB-hours
- ✅ **SSL:** Free
- ✅ **CDN:** Free
- ✅ **Custom Domain:** Free

**Good for:** Unlimited users (within reason)

### Domain Cost
- **Registration:** $10-20/year
- **Renewal:** Same annually

### Supabase Free Tier
- ✅ **Database:** 500MB
- ✅ **Storage:** 1GB
- ✅ **Bandwidth:** 2GB
- ✅ **API Requests:** Unlimited

**Total Cost:** $10-20/year (just domain!)

---

## 💡 Performance Optimization

### Enable Caching in Flutter Web

Update `web/index.html`:
```html
<meta http-equiv="Cache-Control" content="max-age=31536000, immutable">
```

### Add Service Worker for PWA

Already included in Flutter web build!

### Optimize Images

In Supabase Storage, enable:
- Image transformation
- WebP conversion
- Automatic resizing

---

## 🐛 Troubleshooting

### "Site can't be reached"
- **Check DNS:** Use https://dnschecker.org/
- **Wait:** DNS changes take 5-60 minutes
- **Clear cache:** Ctrl+Shift+R or incognito mode

### "Not Secure" warning
- **Wait:** SSL takes 5-30 minutes after DNS propagates
- **Check Vercel:** Domain status should show "Valid"

### White screen / App won't load
- **Check console:** F12 → Console tab
- **CORS error?** Update Supabase allowed origins
- **Rebuild:** `flutter clean && flutter build web --release`

### Authentication not working
- **Check Supabase:** Site URL and Redirect URLs correct?
- **Check OAuth:** Updated provider redirect URIs?
- **Test:** Try email/password first, then OAuth

### Images not loading
- **Check Supabase Storage:** Bucket is public?
- **Check CORS:** Supabase allows your domain?
- **Check URLs:** Image URLs point to Supabase?

---

## 🚀 Quick Deploy Script

Save as `deploy-web.ps1`:

```powershell
# Vinabike ERP - Quick Web Deploy Script

Write-Host "🚀 Building Vinabike ERP for Web..." -ForegroundColor Cyan

# Clean previous build
flutter clean

# Build web app
flutter build web --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build complete!" -ForegroundColor Green
    Write-Host "📤 Deploying to Vercel..." -ForegroundColor Cyan
    
    # Navigate to build folder
    cd build/web
    
    # Deploy to Vercel
    vercel --prod
    
    Write-Host "🎉 Deployment complete!" -ForegroundColor Green
    Write-Host "🌐 Your app is live!" -ForegroundColor Yellow
    
    # Return to project root
    cd ../..
} else {
    Write-Host "❌ Build failed!" -ForegroundColor Red
}
```

Run with:
```powershell
.\deploy-web.ps1
```

---

## 📊 Alternative: Deploy to Netlify

If you prefer Netlify:

### Install Netlify CLI
```powershell
npm install -g netlify-cli
```

### Login
```powershell
netlify login
```

### Deploy
```powershell
cd build/web
netlify deploy --prod
```

Follow prompts, and you're done!

---

## 📚 Additional Resources

- **Vercel Docs:** https://vercel.com/docs
- **Netlify Docs:** https://docs.netlify.com/
- **Supabase Docs:** https://supabase.com/docs
- **Flutter Web Docs:** https://docs.flutter.dev/platform-integration/web
- **DNS Checker:** https://dnschecker.org/

---

## ✅ Deployment Checklist

- [ ] Build web app (`flutter build web --release`)
- [ ] Deploy to Vercel (CLI or Dashboard)
- [ ] Add custom domain in Vercel
- [ ] Configure DNS (nameservers or A/CNAME records)
- [ ] Wait for SSL certificate (5-30 minutes)
- [ ] Update Supabase Site URL
- [ ] Update Supabase Redirect URLs
- [ ] Update Supabase CORS settings
- [ ] Update OAuth provider redirect URIs (if using Google/GitHub)
- [ ] Test login/auth
- [ ] Test database connection
- [ ] Test image uploads
- [ ] Test logo customization
- [ ] Set up GitHub auto-deploy (optional)
- [ ] Add Google Analytics (optional)

---

## 🎯 Next Steps

1. **Test thoroughly** on multiple devices/browsers
2. **Monitor performance** in Vercel Analytics
3. **Set up monitoring** (Sentry, LogRocket)
4. **Add Google Analytics** for user insights
5. **Create user documentation** 
6. **Train your team** on using the web version

---

Need help with any step? Just ask! 🚴‍♂️
