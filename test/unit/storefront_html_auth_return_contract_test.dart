import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_oauth_intent.dart';

/// The HTML login redeems Google's return and an account's confirmation
/// (2026-10-08) and hands Flutter the editor's own Google link, which it
/// tells by the intent the editor leaves in this browser: the page must read
/// the key the editor writes.
void main() {
  test('the login page reads the editor\'s OAuth intent by its owner\'s key',
      () {
    final script = File(
      'services/storefront_html/lib/src/login_page_script.dart',
    ).readAsStringSync();
    expect(
      script,
      contains(
          "var EDITOR_INTENT = '${WebsiteEditorOAuthIntentGate.storageKey}';"),
    );
  });
}
