import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

/// Supabase's edge closes a kept-alive connection after a quiet spell; the
/// next read on it failed with «Connection reset by peer» and the visitor got
/// a bare 500 (2026-10-05). A read is idempotent: it is asked again once.
void main() {
  test('a read on a connection the other side dropped is asked again', () async {
    var calls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls++;
      if (calls == 1) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'settings': {}, 'navigation': []}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final reads = SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
    );
    final shell = await reads.shell();
    expect(shell.shell['navigation'], isEmpty);
    // The shell and the payment methods, plus the one retried.
    expect(calls, greaterThanOrEqualTo(3));
  });
}
