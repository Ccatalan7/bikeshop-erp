# Packaged spreadsheet engine

The Planillas editor embeds [Univer](https://github.com/dream-num/univer),
pinned in the root `package.json` under the Apache-2.0 license. Univer owns the
spreadsheet interaction model; Flutter owns the surrounding ERP route,
authentication, and persistence. The bundled core preset uses Univer's
official `es-ES` locale for its menus and formula assistance.

Build the self-hosted assets before running or building Flutter on web, macOS,
or Windows:

```sh
npm ci
npm run build:spreadsheet-engine
```

The generated `univer.bundle.js` and `univer.bundle.css` files are ignored by
Git and are produced by bootstrap, the desktop VS Code launch tasks, and CI.
Flutter web lazy-loads them only when a Planillas workbook is opened. Native
desktop packages the same files as Flutter assets and loads
`univer_desktop_host.html` inside WKWebView on macOS or WebView2 on Windows.
No CDN runtime or separate spreadsheet implementation is used.
