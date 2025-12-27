---
description: Build and deploy the application to Firebase Hosting
---

This workflow builds the Flutter web applications and deploys to Firebase Hosting.

**IMPORTANT**: The public store uses `main_store.dart` (optimized, ~4.1MB bundle).
The ERP uses `main.dart` (full app, ~9MB bundle).

1.  **Sync SEO Settings to index.html**
    // turbo
    Pulls SEO settings from Supabase and regenerates index.html with correct data.
    ```bash
    ./scripts/sync_seo_index.sh
    ```

2.  **Build the Store (Optimized)**
    // turbo
    Build the public store with the lightweight entry point.
    ```bash
    flutter build web --release -t lib/main_store.dart -o build/web_store
    ```

3.  **Build the ERP (Full)**
    // turbo
    Build the ERP with the full entry point.
    ```bash
    flutter build web --release -o build/web_erp
    ```

4.  **Deploy to Firebase**
    // turbo
    Deploy both targets to Firebase Hosting.
    ```bash
    firebase deploy --only hosting
    ```
