// Puts the whole app on the shop's clock (`kShopTimeZone`) at startup.
//
// The ERP is the shop's tool, and every hour it shows is the shop's: on
// 2026-10-14 the owner's Mac ran on Pacific time and the supplier inbox said
// 09:25 for a WhatsApp the daily summary dated 13:25 — the inbox formatted
// with `toLocal()`, the summary with the shop clock. 69 files formatted with
// the device's zone. On the platforms whose C library reads `TZ` (macOS,
// iOS, Android), Dart's local time follows the process `TZ`, so setting it
// once makes every `toLocal()`, `DateTime.now()` and «today» the shop's.
// The browser keeps its own zone; business code that must hold on the web
// too reads `shopTime()`.
export 'shop_clock_process_io.dart'
    if (dart.library.js_interop) 'shop_clock_process_web.dart';
