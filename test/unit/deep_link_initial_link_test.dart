import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/deep_link_handler.dart';

/// macOS hands the launch link back on every query and a hot restart runs
/// the handler again in the same process: the app jumped to the last shared
/// supplier on every restart (2026-09-03). A launch link is acted on once per
/// process.
void main() {
  final link = Uri.parse(
      'vinabike://app/open?route=/purchases/suppliers/f910b968-de7e-4c26-a0a2-866d13613ab4');

  test('the same process does not act on the same launch link twice', () {
    final marker = deepLinkInitialLinkMarker(4242, link);
    expect(
      deepLinkInitialLinkAlreadyConsumed(
          storedMarker: marker, processId: 4242, uri: link),
      isTrue,
    );
  });

  test('a cold start (new process) honours the link again', () {
    final marker = deepLinkInitialLinkMarker(4242, link);
    expect(
      deepLinkInitialLinkAlreadyConsumed(
          storedMarker: marker, processId: 4243, uri: link),
      isFalse,
    );
  });

  test('a different link in the same process is honoured', () {
    final marker = deepLinkInitialLinkMarker(4242, link);
    expect(
      deepLinkInitialLinkAlreadyConsumed(
        storedMarker: marker,
        processId: 4242,
        uri: Uri.parse('vinabike://mail/oauth?provider=gmail&oauth_code=x'),
      ),
      isFalse,
    );
    expect(
      deepLinkInitialLinkAlreadyConsumed(
          storedMarker: null, processId: 4242, uri: link),
      isFalse,
    );
  });

  test('initialize consults the marker before acting on the launch link', () {
    final source =
        File('lib/shared/services/deep_link_handler.dart').readAsStringSync();
    final guard =
        source.indexOf('if (await _consumeInitialLinkOnce(initialUri))');
    final handle = source.indexOf('_handleDeepLink(initialUri);');
    expect(guard, greaterThan(-1));
    expect(handle, greaterThan(guard));
    expect(source, contains('deepLinkInitialLinkMarker(io.pid, uri)'));
    expect(source, contains('if (kIsWeb) return true;'),
        reason: 'the process id does not exist on the web build');
  });
}
