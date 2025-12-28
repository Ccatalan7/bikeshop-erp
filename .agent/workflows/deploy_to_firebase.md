---
description: Build and deploy the application to Firebase Hosting
---

# ⚠️⚠️⚠️ CRITICAL: READ THIS FIRST ⚠️⚠️⚠️

**There are TWO SEPARATE BUILDS with DIFFERENT entry points!**

| Target | Entry Point | Bundle Size | Deploys To |
|--------|-------------|-------------|------------|
| **Public Store** | `lib/main_store.dart` | **~4.1 MB** | vinabike-store.web.app |
| **ERP Admin** | `lib/main.dart` | ~9.2 MB | project-vinabike.web.app |

**❌ NEVER build the store with `flutter build web` (uses main.dart = 9MB!)** 
**✅ ALWAYS build the store with `-t lib/main_store.dart`**

---

## Workflow Steps

### 1. Sync SEO Settings to index.html
// turbo
Pulls SEO settings from Supabase and regenerates index.html with correct data.
```bash
./scripts/sync_seo_index.sh
```

### 2. Build the Store (Optimized - MUST USE main_store.dart!)
// turbo
Build the public store with the lightweight entry point.
```bash
flutter build web --release -t lib/main_store.dart -o build/web_store
```

**⚠️ VERIFY after build:**
```bash
ls -lh build/web_store/main.dart.js
# MUST be ~4MB! If it's ~9MB, you used the WRONG entry point!
```

### 3. Build the ERP (Full)
// turbo
Build the ERP with the full entry point (includes all modules).
```bash
flutter build web --release -o build/web_erp
```

### 4. Deploy to Firebase
// turbo
Deploy both targets to Firebase Hosting.
```bash
firebase deploy --only hosting
```

Or deploy only the store (faster):
```bash
firebase deploy --only hosting:store
```

---

## Common Mistakes That BREAK The Store

| Mistake | Result | Fix |
|---------|--------|-----|
| `flutter build web --release` without `-t` | 9MB bundle | Add `-t lib/main_store.dart` |
| Copying `build/web/` to `build/web_store/` | Wrong entry point | Rebuild with correct command |
| Not running SEO sync before deploy | Missing meta tags | Run `./scripts/sync_seo_index.sh` first |
| Using `--web-renderer html` flag | Flag doesn't exist anymore | Remove the flag |

## Verification Checklist

After deploying, verify:
- [ ] `vinabike-store.web.app` loads (hard refresh to bypass cache)
- [ ] DevTools → Network → `main.dart.js` is ~4MB (not 9MB!)
- [ ] Page loads fast on mobile (should be <3s on 4G)
