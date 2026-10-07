import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_html_canvas_preference.dart';

/// The site editor opens on its «Vista HTML» where the view is measured with
/// a mouse (macOS, the ERP on the web), and on the operator's own choice on
/// each device once they make one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebsiteHtmlCanvasPreference.resetForTest();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('on by default on macOS; the Flutter canvas elsewhere', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(WebsiteHtmlCanvasPreference.initial, isTrue);
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(WebsiteHtmlCanvasPreference.initial, isFalse, reason: '$platform');
    }
  });

  test('the operator\'s choice is kept on the device', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await WebsiteHtmlCanvasPreference.remember(false);
    WebsiteHtmlCanvasPreference.resetForTest();
    await WebsiteHtmlCanvasPreference.load();
    expect(WebsiteHtmlCanvasPreference.initial, isFalse);
  });

  test('the editor opens on it unless the operator chose in this run', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: '/inicio',
      );
    addTearDown(provider.dispose);
    expect(provider.showsHtmlCanvas, isTrue);

    provider.setShowsHtmlCanvas(false);
    provider.enterEditMode(
      const <Map<String, dynamic>>[],
      const <String, dynamic>{},
      pageId: 'page-b',
      pageSlug: '/nosotros',
    );
    expect(provider.showsHtmlCanvas, isFalse);
  });
}
