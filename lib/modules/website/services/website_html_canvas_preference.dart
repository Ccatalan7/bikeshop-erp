import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the site editor opens on its «Vista HTML» on this device: the
/// operator's last choice there, or, until they make one, where the view
/// has been measured — macOS and the ERP on the web since 2026-10-07, and
/// Android (by finger, in the emulator) since 2026-10-08 (phase 5d of
/// `storefront-html-migration-plan.md`). Windows (its zoom is not measured
/// yet) and the iPhone keep the Flutter canvas.
abstract final class WebsiteHtmlCanvasPreference {
  static const _key = 'website_editor_html_canvas';

  static bool? _stored;

  /// Reads the choice kept on this device; the editor opens with the default
  /// until it is read.
  static Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _stored = preferences.getBool(_key);
    } on Object {
      // No storage (a test, a private window): the default.
    }
  }

  static bool get defaultOn =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// What the editor opens with.
  static bool get initial => _stored ?? defaultOn;

  /// Keeps the operator's choice for the next time on this device.
  static Future<void> remember(bool on) async {
    _stored = on;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_key, on);
    } on Object {
      // Kept for this run only.
    }
  }

  @visibleForTesting
  static void resetForTest() => _stored = null;

  /// A test of the Flutter canvas on a phone: widget tests run as Android,
  /// where the editor now opens on the «Vista HTML» (a real web view).
  @visibleForTesting
  static void chooseForTest(bool on) => _stored = on;
}
