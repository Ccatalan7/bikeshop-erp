# 🔗 WHERE TO ADD OAUTH REDIRECT URLs

## 📍 EXACT LOCATION IN SUPABASE DASHBOARD

### **Your Supabase Project URL:**
`https://xzdvtzdqjeyqxnkqprtf.supabase.co`

---

## 🎯 STEP-BY-STEP WITH SCREENSHOTS GUIDE

### **STEP 1: Open Supabase Dashboard**

Click this link: **https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf**

(Make sure you're logged in to Supabase)

---

### **STEP 2: Navigate to Authentication Settings**

In the left sidebar, click:
```
Authentication → URL Configuration
```

**Or use this direct link:**
**https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/url-configuration**

---

### **STEP 3: Find "Redirect URLs" Section**

On the URL Configuration page, you'll see several sections:

1. **Site URL** (at the top)
2. **Redirect URLs** ← **THIS IS WHERE YOU ADD THEM**
3. **Additional Redirect URLs**

---

### **STEP 4: Add URLs to "Redirect URLs" Field**

In the **"Redirect URLs"** text area, you'll see existing URLs (or it might be empty).

**Add these URLs (one per line):**

```
http://localhost:3000/
http://localhost:8080/
http://localhost:5000/
io.supabase.vinabikeerp://login-callback/
```

**It should look like this:**

```
┌─────────────────────────────────────────────┐
│ Redirect URLs                               │
├─────────────────────────────────────────────┤
│ http://localhost:3000/                      │
│ http://localhost:8080/                      │
│ http://localhost:5000/                      │
│ io.supabase.vinabikeerp://login-callback/   │
│                                             │
└─────────────────────────────────────────────┘
```

---

### **STEP 5: Verify Site URL**

Scroll to the top of the same page.

In the **"Site URL"** field, make sure it says:
```
http://localhost:3000/
```

(This is the default redirect after successful OAuth login)

---

### **STEP 6: Save Changes**

Click the green **"Save"** button at the bottom of the page.

**You'll see a success notification:** "Successfully updated settings"

---

## ✅ VERIFICATION

After saving, the URLs should appear in the dashboard like this:

**Redirect URLs:**
- ✅ `http://localhost:3000/`
- ✅ `http://localhost:8080/`
- ✅ `http://localhost:5000/`
- ✅ `io.supabase.vinabikeerp://login-callback/`

---

## 🚨 TROUBLESHOOTING

### **Can't find "URL Configuration"?**

1. Make sure you're in the correct project: `xzdvtzdqjeyqxnkqprtf`
2. Check the left sidebar under "Authentication"
3. Click "Configuration" → then "URL Configuration" tab

### **Don't see "Redirect URLs" field?**

- Make sure you're on the **"URL Configuration"** tab, not "Providers" or "Policies"
- It's usually the second field after "Site URL"

### **Save button is disabled?**

- Make sure you've made changes to the field
- Try clicking in the text area first, then adding URLs

---

## 🔍 WHAT THESE URLs DO

| URL | Purpose |
|-----|---------|
| `http://localhost:3000/` | Web app running on port 3000 (most common) |
| `http://localhost:8080/` | Alternative port for web app |
| `http://localhost:5000/` | Another common dev port |
| `io.supabase.vinabikeerp://login-callback/` | **Deep link for desktop/mobile app** - allows OAuth to redirect back to your Flutter app |

---

## ⚡ AFTER ADDING URLs

1. ✅ Click "Save"
2. ✅ Close any open browser tabs with your app
3. ✅ Restart your Flutter app if it's running
4. ✅ Clear browser cache (Ctrl+Shift+Delete → Cookies)
5. ✅ Try Google Sign-In again

**Expected result:** Google Sign-In should now redirect properly without getting stuck! 🎉

---

## 📸 VISUAL GUIDE

**What you're looking for in the dashboard:**

```
┌──────────────────────────────────────────────────────────┐
│  Authentication > URL Configuration                      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Site URL                                                │
│  ┌────────────────────────────────────────────────┐     │
│  │ http://localhost:3000/                         │     │
│  └────────────────────────────────────────────────┘     │
│                                                          │
│  Redirect URLs                                           │
│  ┌────────────────────────────────────────────────┐     │
│  │ http://localhost:3000/                         │     │
│  │ http://localhost:8080/                         │     │
│  │ http://localhost:5000/                         │     │
│  │ io.supabase.vinabikeerp://login-callback/      │     │
│  └────────────────────────────────────────────────┘     │
│                                                          │
│  Additional Redirect URLs                                │
│  ┌────────────────────────────────────────────────┐     │
│  │ (optional - can leave empty)                   │     │
│  └────────────────────────────────────────────────┘     │
│                                                          │
│                           [ Save ]                       │
└──────────────────────────────────────────────────────────┘
```

---

**Need more help? Let me know if you can't find the page!**
