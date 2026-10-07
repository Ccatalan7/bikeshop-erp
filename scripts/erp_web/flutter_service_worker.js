// Vinabike ERP on the web: retires Flutter's offline service worker.
//
// Until 2026-10-07 the ERP web was built with Flutter's default
// "offline-first" worker. It keeps each file under its plain name
// (main.dart.js, main.dart.js_1.part.js, ...), and a deploy that lands while
// a tab is loading leaves it holding parts of two builds: the app then stops
// at start with "Deferred library erp was not loaded" and stays stopped on
// every reload (measured in the owner's Chrome on 2026-10-07: main.dart.js
// of 33e1622d next to 17 parts of the build before).
//
// The ERP is now built with `--pwa-strategy=none` (no worker), and every ERP
// web build puts this file in that worker's place, so a browser that still
// has it installed lets it go: Flutter's caches are deleted and the worker
// unregisters itself. Without a fetch handler, requests go to the network
// from that moment; the open page keeps running and is never reloaded under
// the operator. The Firebase Messaging worker (another scope) is untouched.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(
      names
        .filter((name) => name.startsWith('flutter-'))
        .map((name) => caches.delete(name)),
    );
    await self.registration.unregister();
  })());
});
