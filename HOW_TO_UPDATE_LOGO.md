# 🖼️ How to Update Company Logo (Quick Guide)

## ✅ The Fix is Now Live!

As of **October 17, 2025 at 20:43**, the logo caching issue has been fixed and deployed.

---

## 📋 How to Update Your Company Logo

### Step 1: Go to Appearance Settings
1. Open your app: https://project-vinabike.web.app
2. Click **Settings** (gear icon in top right)
3. Click **Apariencia** in the settings menu

### Step 2: Upload New Logo
1. Scroll down to the **"Logo de la empresa"** section
2. Click **"Seleccionar archivo"**
3. Choose your new logo image (PNG, JPG recommended)
4. Click **"Actualizar Logo"**

### Step 3: Verify It Works
✅ The new logo should appear **immediately** in the sidebar  
✅ No need to refresh the page  
✅ No need to clear cache

### Step 4: Check on Other Devices
1. Open the app on another computer or phone
2. The new logo should show up **immediately**
3. If you're already logged in, you might need to reload the page once

---

## 🔧 What Was Fixed

### Before (❌ Problem)
- Logo would update on the computer where you uploaded it
- Other computers kept showing the old logo
- Even hard refresh (Ctrl+F5) didn't help

### After (✅ Fixed)
- Logo updates **instantly** on all devices
- Browser cache is automatically handled
- No manual intervention needed

### How It Works
We now add a unique timestamp to each logo URL:
```
Old: company_logos/logo.png
New: company_logos/logo.png?v=1729220840123
```

Each upload gets a new timestamp, so browsers treat it as a new image.

---

## 📱 Testing Checklist

After uploading a new logo, verify:

- [ ] Logo shows in sidebar on upload computer
- [ ] Logo shows in sidebar on mobile view
- [ ] Open app on different computer - logo updates
- [ ] Open app on phone - logo updates
- [ ] Open app in different browser - logo updates
- [ ] No need to clear cache on any device

---

## 🚨 Troubleshooting

### Logo Not Updating?

1. **Make sure you're on the latest version**
   - Check URL: https://project-vinabike.web.app
   - Deployed: October 17, 2025 at 20:43

2. **Try a hard refresh (just once)**
   - Windows/Linux: `Ctrl + F5`
   - Mac: `Cmd + Shift + R`
   - This loads the latest app code

3. **Check if upload succeeded**
   - Go to Settings → Appearance
   - You should see the new logo in the preview
   - If not, try uploading again

4. **Mobile devices**
   - Close and reopen the app
   - Or reload the browser tab

### Still Having Issues?

- Clear browser cache completely (as last resort)
- Check browser console for errors (F12)
- Verify you're logged in with the right account
- Make sure image file is valid (PNG, JPG, max 5MB)

---

## 📝 Technical Details

For developers/admins who want to understand the fix:

### What Was Changed

**File:** `lib/modules/settings/services/appearance_service.dart`

**Change:** Added timestamp query parameter to logo URLs

```dart
// Add cache-busting timestamp
final timestamp = DateTime.now().millisecondsSinceEpoch;
final cacheBustedUrl = '$imageUrl?v=$timestamp';
```

### Why It Works

1. **Browser caches images by URL**
   - Same URL = cached version
   - Different URL = fetch new version

2. **Timestamp makes URL unique**
   - Every upload gets a new timestamp
   - Browser sees each as a different resource

3. **No performance impact**
   - Images are still cached (good for performance)
   - Only new logos trigger fresh downloads

### Deployment Info

- **Build time:** Oct 17, 2025 at 20:43
- **File size:** 3.9M (main.dart.js)
- **Deploy method:** `firebase deploy --only hosting`
- **Live URL:** https://project-vinabike.web.app

---

## ✅ Summary

Logo updates now work correctly across all devices thanks to automatic cache-busting. Just upload your new logo in Settings → Appearance and it will appear everywhere immediately!

---

**Last Updated:** October 17, 2025  
**Deployed:** October 17, 2025 at 20:43  
**Status:** ✅ LIVE
