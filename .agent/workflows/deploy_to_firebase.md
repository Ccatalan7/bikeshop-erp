---
description: Build and deploy the application to Firebase Hosting
---

This workflow builds the Flutter web application and deploys it to Firebase Hosting.

1.  **Build the Web Application**
    // turbo
    Build the Flutter application for the web. This generates the static files in `build/web`.
    ```bash
    flutter build web --release --wasm
    ```
    *Note: We use `--wasm` for better performance.*

2.  **Deploy to Firebase**
    // turbo
    Deploy the built files to Firebase Hosting using the Firebase CLI.
    ```bash
    firebase deploy --only hosting
    ```
