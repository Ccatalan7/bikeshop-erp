---
description: Build and deploy the application to Firebase Hosting using WebAssembly (Wasm)
---

# 🚀 Deploy to Firebase (Wasm)

This workflow builds the application using the `--wasm` flag for better performance.
**Fallback:** If this fails, use the standard `/deploy_to_firebase` workflow.

## Workflow Steps

### 1. Sync SEO Settings
// turbo
```bash
./scripts/sync_seo_index.sh
```

### 2. Build the Store (Wasm)
// turbo
Builds with `--wasm`.
```bash
flutter build web --wasm --release -t lib/main_store.dart -o build/web_store
```

**Verification:**
Check if `main.dart.wasm` exists in `build/web_store`.

### 3. Generate Product SEO Snapshots
// turbo
```bash
dart run scripts/generate_product_seo_snapshots.dart \
	--build-dir build/web_store \
	--tenant-id 5443b130-cc28-45af-a420-cd500b288890 \
	--store-url https://vinabike.cl
```

### 4. Build the ERP (Wasm)
// turbo
Builds with `--wasm`.
```bash
flutter build web --wasm --release -t lib/main.dart -o build/web_erp
```

### 5. Deploy
// turbo
```bash
firebase deploy --only hosting
```
