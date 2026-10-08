import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// On the ERP on the web the editor's «Vista HTML» is a frame, and Flutter's
// web engine leaves every platform view open to the pointer whatever Flutter
// draws over it: with a sheet, a dialog or a menu of the editor open, a touch
// went to the page under it (iPhone Safari, 2026-10-08). The frame's pointer
// only lives in the browser, so these pin the wiring the fix depends on.
void main() {
  final view = File(
    'lib/modules/website/widgets/website_html_draft_view.dart',
  ).readAsStringSync();
  final web = File(
    'lib/modules/website/services/website_html_draft_picks_web.dart',
  ).readAsStringSync();

  test('the web frame takes the pointer only while its route is current', () {
    expect(view, contains('controller.getIFrameId()'));
    expect(view, contains('ModalRoute.isCurrentOf(context)'));
    expect(view, contains('websiteHtmlDraftFramePointer(id, takes: takes)'));
    // Called from didChangeDependencies, where isCurrentOf calls it again.
    expect(
      RegExp(r'void didChangeDependencies\(\)[\s\S]*?_syncFramePointer\(\);')
          .hasMatch(view),
      isTrue,
    );
    expect(web, contains("style.pointerEvents = takes ? '' : 'none'"));
  });

  test('the pointer goes back only after the touch that closed the sheet', () {
    // Handed back at once, the browser's click of that touch hit the page.
    expect(view, contains('_frameBackDelay = Duration(milliseconds: 400)'));
    expect(view, contains('_frameBack?.cancel();'));
  });
}
