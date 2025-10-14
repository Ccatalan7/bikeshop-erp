# 🔧 Supabase Configuration for Deployed App

## Your App URLs:
- **Production URL:** https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app
- **Vercel Dashboard:** https://vercel.com/ccatalan7s-projects/vinabike-erp

---

## ⚠️ REQUIRED: Update Supabase Settings

### Step 1: Go to Supabase Dashboard
https://supabase.com/dashboard

### Step 2: Select Your Project
Find and click on your Vinabike project

### Step 3: Update Authentication Settings

**Navigation:** Settings → Authentication → URL Configuration

#### 3.1 Update Site URL:
```
https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app
```

#### 3.2 Add Redirect URLs:
Click "Add URL" for each:
```
https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app/**
https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app/auth/callback
http://localhost:3000/** (keep for local development)
```

### Step 4: Update CORS Settings

**Navigation:** Settings → API → CORS

Add this origin:
```
https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app
```

### Step 5: Save All Changes

Click "Save" in each section.

---

## ✅ Verification Checklist

After updating Supabase settings:

1. Open: https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app
2. Test login with email/password
3. Test loading data from database
4. Test uploading company logo
5. Test creating/editing records

---

## 🌐 Add Custom Domain (Optional)

To use `vinabike.com` instead of the Vercel subdomain:

### Quick Steps:

1. **Buy Domain** (if not already owned):
   - Namecheap: ~$10-15/year
   - Google Domains
   - Cloudflare Registrar

2. **Add to Vercel:**
   - Go to: https://vercel.com/ccatalan7s-projects/vinabike-erp/settings/domains
   - Click "Add Domain"
   - Enter: `vinabike.com`
   - Follow DNS configuration instructions

3. **Update Supabase Again:**
   - Replace Vercel subdomain with your custom domain
   - Site URL: `https://vinabike.com`
   - Redirect URLs: `https://vinabike.com/**`

---

## 🔄 How to Update Your App

Whenever you make changes:

```powershell
# 1. Navigate back to project root
cd C:\dev\ProjectVinabike

# 2. Build new version
flutter build web --release

# 3. Deploy updated version
cd build\web
vercel --prod
```

Takes ~30 seconds to deploy!

---

## 📊 Monitor Your App

**Vercel Dashboard:**
- Analytics: https://vercel.com/ccatalan7s-projects/vinabike-erp/analytics
- Deployment History
- Domain Settings
- Environment Variables

---

## 🐛 Troubleshooting

### Login doesn't work?
- ✅ Updated Supabase Site URL?
- ✅ Updated Supabase Redirect URLs?
- ✅ Saved changes in Supabase?
- ✅ Wait 1-2 minutes for changes to propagate

### White screen?
- Open browser console (F12)
- Check for CORS errors
- Verify Supabase CORS settings include your Vercel URL

### Images won't upload?
- Check Supabase Storage CORS settings
- Verify Storage bucket is public (if needed)

---

## 🎯 Next Steps Priority

1. ✅ **URGENT:** Update Supabase settings (see above)
2. ✅ Test app functionality
3. ⏰ Optional: Add custom domain
4. ⏰ Optional: Set up CI/CD with GitHub
5. ⏰ Optional: Add Google Analytics

---

**Your app is live! 🚴‍♂️**

Share this URL with your team: https://vinabike-pxlybszpn-ccatalan7s-projects.vercel.app
