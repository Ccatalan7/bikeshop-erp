---
description: Run the website (customer portal) locally in debug mode
---

To run the website (public store) locally and debug it, you need to set the `FORCE_SUBDOMAIN` environment variable. This tells the app to skip the ERP login flow and load the specific tenant's website data.

1.  Run the following command in your terminal:

```bash
flutter run -d chrome --dart-define=FORCE_SUBDOMAIN=vinabike
```

**Notes:**

*   Replace `vinabike` with a different subdomain if you need to test a different tenant.
*   The `--dart-define` flag injects the environment variable at compile time.
*   This works with `flutter run` as well as VS Code execution profiles (you can add `"args": ["--dart-define=FORCE_SUBDOMAIN=vinabike"]` to your `launch.json`).
