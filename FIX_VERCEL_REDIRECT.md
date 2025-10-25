# 🚨 FIX VERCEL REDIRECT ISSUE

## Problem
After Google Sign-In, you're being redirected to a Vercel URL instead of localhost.

## Root Cause
The **Site URL** in Supabase dashboard is probably set to a Vercel domain from a previous deployment.

---

## 🔧 IMMEDIATE FIX

### Go to Supabase Dashboard:
**https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/url-configuration**

### Update These Settings:

#### 1. **Site URL** (at the top)
**Change from:** `https://something.vercel.app` or whatever Vercel URL is there  
**Change to:** `http://localhost:3000/`

#### 2. **Redirect URLs** (verify these are present)
Make sure you have:
```
http://localhost:3000/
http://localhost:8080/
http://localhost:5000/
io.supabase.vinabikeerp://login-callback/
```

**Remove any Vercel URLs like:**
- ❌ `https://your-app.vercel.app`
- ❌ `https://anything.vercel.app`

#### 3. Click **"Save"**

---

## 🧪 Test Again

1. Close all browser tabs
2. Clear browser cache (Ctrl+Shift+Delete)
3. Restart app: `flutter run -d chrome`
4. Click "Sign in with Google"
5. Select ccatalansandoval7@gmail.com

**Expected:** Should redirect to `http://localhost:3000/` instead of Vercel

---

## 📝 What to Look For in Dashboard

The page should look like this:

```
┌────────────────────────────────────────────────┐
│ Site URL                                       │
├────────────────────────────────────────────────┤
│ http://localhost:3000/          ← CHANGE THIS │
└────────────────────────────────────────────────┘

┌────────────────────────────────────────────────┐
│ Redirect URLs                                  │
├────────────────────────────────────────────────┤
│ http://localhost:3000/                         │
│ http://localhost:8080/                         │
│ http://localhost:5000/                         │
│ io.supabase.vinabikeerp://login-callback/      │
│                                                │
│ ❌ DELETE ANY VERCEL URLS HERE                │
└────────────────────────────────────────────────┘
```

---

## 🗑️ Additional Cleanup (Optional)

If you want to remove all Vercel traces from the project:

### Check package.json
If you have Vercel deployment scripts, you can remove them.

### Check for vercel.json
```powershell
Get-ChildItem -Path . -Recurse -Filter "vercel.json" | Remove-Item
```

But the main issue is just the **Supabase Site URL** setting - fix that first!

---

**Go update the Site URL in Supabase dashboard and let me know if it works!** 👍
