# 🚀 Deploying Flutter Web App to Vercel

## 📋 Overview
This guide shows you how to deploy your Vinabike ERP Flutter app to Vercel, including all the recent Financial Reports changes.

---

## ✅ Pre-Deployment Checklist

### 1. **Database Schema Updated?**
Before deploying, make sure you've deployed the SQL functions to Supabase:

```powershell
# If you haven't already, deploy core_schema.sql to Supabase
# See DEPLOY_FINANCIAL_REPORTS_SQL.md for details
```

**Why?** The Financial Reports feature requires SQL functions in your Supabase database.

### 2. **Supabase Configuration**
Verify your `lib/shared/config/supabase_config.dart` has your production credentials:

```dart
class SupabaseConfig {
  static const String url = 'https://YOUR_PROJECT.supabase.co';
  static const String anonKey = 'your-anon-key-here';
  static const bool isConfigured = true;
}
```

### 3. **Test Locally**
Make sure everything works on Windows first:

```powershell
flutter run -d chrome
# Or
flutter run -d windows
```

---

## 🔧 Step-by-Step Deployment

### Method 1: Git Push (Automatic Deployment)

This is the easiest method - Vercel automatically deploys when you push to your repository.

#### 1. **Commit Your Changes**

```powershell
# Navigate to your project
cd C:\dev\ProjectVinabike

# Check what changed
git status

# Add all changes
git add .

# Commit with a descriptive message
git commit -m "feat: Add Financial Reports module with Income Statement and Balance Sheet"

# Push to your repository
git push origin main
# Or if you're on a different branch:
git push origin claude-sonnet-inv.management-fix
```

#### 2. **Vercel Auto-Deploy**
- Vercel will automatically detect the push
- Build process starts automatically
- Check deployment status at: https://vercel.com/dashboard

#### 3. **Monitor Build**
- Go to your Vercel dashboard
- Click on your project
- Watch the build logs
- Wait for "Ready" status (usually 2-5 minutes)

---

### Method 2: Manual Vercel CLI Deploy

If automatic deployment doesn't work or you prefer manual control:

#### 1. **Install Vercel CLI** (if not already installed)

```powershell
npm install -g vercel
```

#### 2. **Login to Vercel**

```powershell
vercel login
```

#### 3. **Build Flutter Web**

```powershell
# Clean previous builds
flutter clean

# Build for web (production mode)
flutter build web --release --web-renderer canvaskit

# Or if you prefer html renderer (faster but less features):
# flutter build web --release --web-renderer html
```

**Why CanvasKit?** Better rendering quality, especially for custom graphics and charts in reports.

#### 4. **Deploy to Vercel**

```powershell
# From project root
vercel --prod
```

Or deploy a specific folder:

```powershell
vercel build/web --prod
```

---

## 📁 Vercel Configuration

### Create `vercel.json` (if you don't have one)

Create this file in your project root:

```json
{
  "version": 2,
  "public": true,
  "github": {
    "enabled": true,
    "autoAlias": true,
    "silent": true
  },
  "builds": [
    {
      "src": "package.json",
      "use": "@vercel/static-build",
      "config": {
        "distDir": "build/web"
      }
    }
  ],
  "routes": [
    {
      "src": "/assets/(.*)",
      "dest": "/assets/$1"
    },
    {
      "src": "/icons/(.*)",
      "dest": "/icons/$1"
    },
    {
      "src": "/(.*)",
      "dest": "/index.html"
    }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "Cross-Origin-Embedder-Policy",
          "value": "require-corp"
        },
        {
          "key": "Cross-Origin-Opener-Policy",
          "value": "same-origin"
        }
      ]
    }
  ]
}
```

### Create `package.json` (if you don't have one)

```json
{
  "name": "vinabike-erp",
  "version": "1.0.0",
  "description": "Vinabike ERP - Flutter Web Application",
  "scripts": {
    "build": "flutter build web --release --web-renderer canvaskit"
  },
  "devDependencies": {
    "@vercel/static-build": "^2.0.0"
  }
}
```

---

## 🔄 Deployment Workflow

### Complete Workflow from Changes to Production:

```powershell
# 1. Make your changes (already done!)
# Financial Reports, bug fixes, etc.

# 2. Test locally
flutter run -d chrome

# 3. Clean build
flutter clean
flutter pub get

# 4. Build for production
flutter build web --release --web-renderer canvaskit

# 5. Commit changes
git add .
git commit -m "feat: Financial Reports with Income Statement and Balance Sheet"

# 6. Push to repository
git push origin main

# 7. Vercel automatically deploys (if connected to GitHub)
# Or manually:
# vercel --prod
```

---

## 🐛 Troubleshooting

### Issue 1: "Build Failed"

**Check Vercel Logs:**
- Go to Vercel Dashboard → Your Project → Deployments
- Click on failed deployment
- Check build logs

**Common Fixes:**
```powershell
# Clear Flutter cache
flutter clean
flutter pub get

# Rebuild
flutter build web --release
```

### Issue 2: "Page Shows Blank Screen"

**Solution 1: Check Web Renderer**
```powershell
# Try HTML renderer instead of CanvasKit
flutter build web --release --web-renderer html
```

**Solution 2: Check Browser Console**
- Open browser DevTools (F12)
- Look for JavaScript errors
- Common issue: CORS errors with Supabase

### Issue 3: "Supabase Connection Failed"

**Check Configuration:**
1. Verify `supabase_config.dart` has correct credentials
2. Check Supabase dashboard → Settings → API
3. Ensure anon key is correct
4. Check if Supabase project is active

**CORS Issue:**
- Go to Supabase Dashboard
- Authentication → URL Configuration
- Add your Vercel domain to allowed URLs

### Issue 4: "Routes Not Working (404)"

**Fix in `vercel.json`:**
```json
{
  "routes": [
    {
      "src": "/(.*)",
      "dest": "/index.html"
    }
  ]
}
```

This ensures all routes go through Flutter's router.

### Issue 5: "Financial Reports Show Error"

**Remember:**
You need to deploy `core_schema.sql` to your Supabase database!

```sql
-- In Supabase SQL Editor, run:
-- Full contents of supabase/sql/core_schema.sql
```

See `DEPLOY_FINANCIAL_REPORTS_SQL.md` for details.

---

## 🌐 Environment Variables in Vercel

If you want to use environment variables instead of hardcoding credentials:

### 1. **Update Flutter Config**

Modify `lib/shared/config/supabase_config.dart`:

```dart
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );
  
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key',
  );
  
  static const bool isConfigured = true;
}
```

### 2. **Add to Vercel Dashboard**

- Go to Vercel Dashboard
- Select your project
- Settings → Environment Variables
- Add:
  - `SUPABASE_URL` = `https://yourproject.supabase.co`
  - `SUPABASE_ANON_KEY` = `your-anon-key-here`

### 3. **Build with Variables**

```powershell
flutter build web --release --dart-define=SUPABASE_URL=https://yourproject.supabase.co --dart-define=SUPABASE_ANON_KEY=your-key
```

---

## 📊 Vercel Build Settings

### In Vercel Dashboard:

**Framework Preset:** Other

**Build Command:**
```
flutter build web --release --web-renderer canvaskit
```

**Output Directory:**
```
build/web
```

**Install Command:**
```
if cd flutter; then git pull && cd .. ; else git clone https://github.com/flutter/flutter.git; fi && flutter/bin/flutter doctor && flutter/bin/flutter clean && flutter/bin/flutter pub get
```

---

## 🚀 Quick Deploy Commands

### Option 1: Push to Git (Recommended)
```powershell
git add .
git commit -m "feat: Add Financial Reports"
git push origin main
```

### Option 2: Vercel CLI
```powershell
flutter build web --release
vercel --prod
```

### Option 3: GitHub Integration
- Push to GitHub
- Vercel auto-deploys from GitHub
- No manual commands needed!

---

## ✅ Post-Deployment Checklist

After deployment, verify:

- [ ] App loads at your Vercel URL
- [ ] Login works (Supabase authentication)
- [ ] Dashboard shows data
- [ ] Navigation works (all menu items)
- [ ] **Financial Reports accessible** (Contabilidad → Reportes Financieros)
- [ ] Income Statement loads without errors
- [ ] Balance Sheet loads without errors
- [ ] No console errors in browser DevTools

---

## 🔐 Security Considerations

### Supabase RLS (Row Level Security)

Make sure RLS is enabled on all tables:

```sql
-- Enable RLS on tables
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_lines ENABLE ROW LEVEL SECURITY;
-- etc.

-- Create policies for authenticated users
CREATE POLICY "Enable read for authenticated users" ON accounts
  FOR SELECT USING (auth.role() = 'authenticated');
```

### Environment Variables

- ✅ Use environment variables for sensitive data
- ❌ Don't commit API keys to Git
- ✅ Use `.env` files locally (add to `.gitignore`)
- ✅ Use Vercel Environment Variables for production

---

## 📈 Performance Optimization

### 1. **Enable Caching**

In `vercel.json`:
```json
{
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    }
  ]
}
```

### 2. **Optimize Images**

```powershell
# Use WebP format for better compression
# Compress assets before deployment
```

### 3. **Code Splitting**

Flutter web automatically splits code, but you can optimize:

```powershell
flutter build web --release --split-debug-info=build/debug-info --tree-shake-icons
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions (Optional)

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Vercel

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      
      - run: flutter pub get
      - run: flutter build web --release --web-renderer canvaskit
      
      - uses: amondnet/vercel-action@v20
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          working-directory: ./build/web
```

---

## 🎯 Summary

**Quickest Way to Deploy:**

```powershell
# 1. Build
flutter build web --release --web-renderer canvaskit

# 2. Push
git add .
git commit -m "Update: Financial Reports module"
git push origin main

# 3. Done! Vercel auto-deploys
```

**Verification URL:**
- Production: `https://your-project.vercel.app`
- Deployment logs: `https://vercel.com/dashboard`

**Need Help?**
- Vercel docs: https://vercel.com/docs
- Flutter web: https://docs.flutter.dev/deployment/web
- Your deployment status: https://vercel.com/dashboard

---

## 📞 Support

If deployment fails:
1. Check Vercel build logs
2. Test locally first: `flutter run -d chrome`
3. Verify Supabase connection
4. Check browser console for errors
5. Ensure `core_schema.sql` is deployed to Supabase

**Happy Deploying! 🚀✨**
