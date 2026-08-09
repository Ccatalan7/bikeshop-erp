---
description: Build and deploy the application to Firebase Hosting
---

# ⚠️⚠️⚠️ CRITICAL: READ THIS FIRST ⚠️⚠️⚠️

**There are TWO SEPARATE BUILDS with DIFFERENT entry points!**

| Target | Entry Point | Bundle Size | Deploys To |
|--------|-------------|-------------|------------|
| **Public Store** | `lib/main_store.dart` | **~5.5 MB raw / ~1.56 MB gzip** | vinabike-store.web.app |
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

The script loads the public Supabase key without embedding it in the repo. It
accepts `SUPABASE_PUBLISHABLE_KEY` (or the legacy `SUPABASE_ANON_KEY`), then
accepts the existing CI-only `SUPABASE_SECRET_KEY` process-variable fallback,
then uses the documented publishable-key macOS Keychain entry. It never lists
project keys through the Supabase CLI. To verify credentials and database
access without changing `web/index.html`, run:

```bash
./scripts/sync_seo_index.sh --check
```

The deploy launcher also resolves `SUPABASE_SECRET_KEY` before starting either
Flutter build, because the product snapshot generator needs privileged catalog
read access. macOS resolves the documented Keychain entry and injects it into
the snapshot process; Windows requires `SUPABASE_SECRET_KEY` in the protected
process environment (for example, injected from Windows Credential Manager).
The GitHub snapshot job already receives `SUPABASE_SECRET_KEY` from the
protected `Production` environment. The generator never reads `.env`, lists
project keys, prints the key, or passes it as a Dart define.

Run `bash scripts/deploy.sh --check` for a fast preflight of both credentials
before launching the full build/deploy task.

### 2. Build the Store (Optimized - MUST USE main_store.dart!)
// turbo
Build the public store with the lightweight entry point.
```bash
flutter build web --release -t lib/main_store.dart -o build/web_store
```

**⚠️ VERIFY after build:**
```powershell
Get-Item build/web_store/main.dart.js | Select-Object Name, @{N='Size(MB)';E={[math]::Round($_.Length/1MB,2)}}
# Must pass scripts/check_storefront_bundle_budget.sh.
```

### 2.5 Generate Product SEO Snapshots (CRITICAL for Google Merchant)
// turbo
Generates static HTML files for canonical product URLs so `/productos/<uuid>` can be served as real HTML (meta + Product JSON-LD) even when bots don’t execute Flutter JS reliably.

```bash
dart run scripts/generate_product_seo_snapshots.dart \
	--build-dir build/web_store \
	--tenant-id 5443b130-cc28-45af-a420-cd500b288890 \
	--expected-store-url https://vinabike.cl \
	--product-scope published
```

**Quick sanity check:**
```powershell
Get-ChildItem build/web_store/productos | Select-Object -First 5
Get-Content build/web_store/robots.txt
Select-String -Path build/web_store/sitemap.xml -Pattern "/productos/"
```

Notes:
- Firebase Hosting serves these snapshots as static files if present (SPA rewrite is only a fallback).
- Hosting headers for `/productos/**` are configured in `firebase.json`.
- `robots.txt` and `sitemap.xml` are generated in the same step so Google can discover the full public product catalog.
- The consistency guard reads every production owner twice. Every paginated
  owner must use a total order: URL aliases are ordered by
  `created_at.asc,alias_path.asc`, where `alias_path` is tenant-unique. A
  timestamp-only order can duplicate and omit tied rows even with no writes.
  Never bypass that guard; after an abort, fix the source read and rerun the
  complete deploy because the local build outputs are incomplete.

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
