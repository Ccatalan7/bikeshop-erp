# Vinabike Android WebView patch

This directory vendors `flutter_inappwebview_android` 1.1.3 from pub.dev. The
source archive hash pinned by the original lockfile was:

`62557c15a5c2db5d195cb3892aab74fcaec266d7b86d59a6f0027abd672cddba`

Vinabike changes one security-sensitive behavior in
`InAppWebViewChromeClient.onConsoleMessage`: after forwarding an optional
console callback to Dart, the method returns `true` instead of delegating to
the default `false` implementation.

In debuggable Android WebViews, returning `false` makes Chromium mirror the
console message and its source URL to logcat. A source URL can contain OAuth
query data even when the ERP never logs the navigation itself. Returning
`true` marks the message handled, preventing that fallback while keeping CDP
inspection and the plugin's optional Dart callback available.

When upgrading `flutter_inappwebview`, compare the upstream Android method
again. Remove this path override only if the installed version provides an
equivalent handled-console contract, then repeat the source regression and the
physical OAuth/logcat gate documented in `.github/copilot-instructions.md`.
