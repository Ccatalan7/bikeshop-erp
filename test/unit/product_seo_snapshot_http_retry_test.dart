// The daily store build reads Supabase through Cloudflare. On 23 and
// 24-nov-2026 it failed on a single «error code: 522» while reading the
// published services, and the sitemap went two days without the products
// published since. A transient answer is asked again; anything else still
// fails at once.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

/// Serves [statuses] in order, one per request, and counts the requests.
Future<({Uri url, List<int> served})> _serve(List<int> statuses) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final served = <int>[];
  server.listen((request) async {
    final status = statuses[served.length.clamp(0, statuses.length - 1)];
    served.add(status);
    request.response.statusCode = status;
    request.response
        .write(status == 200 ? '[{"id":"ok"}]' : 'error code: $status');
    await request.response.close();
  });
  return (
    url: Uri.parse('http://127.0.0.1:${server.port}/rest/v1/products'),
    served: served,
  );
}

const _noWait = [Duration.zero, Duration.zero, Duration.zero];

void main() {
  test('a 522 from the edge is asked again until the answer arrives', () async {
    final server = await _serve([522, 522, 200]);
    final body = await snapshots.seoSnapshotHttpGet(
      server.url,
      headers: const {},
      retryWaits: _noWait,
    );
    expect(body, '[{"id":"ok"}]');
    expect(server.served, [522, 522, 200]);
  });

  test('a status that is not transient fails at once', () async {
    final server = await _serve([404, 200]);
    await expectLater(
      snapshots.seoSnapshotHttpGet(
        server.url,
        headers: const {},
        retryWaits: _noWait,
      ),
      throwsA(isA<HttpException>()
          .having((e) => e.message, 'message', contains('404'))),
    );
    expect(server.served, [404]);
  });

  test('a transient answer that never clears fails after the last wait',
      () async {
    final server = await _serve([503]);
    await expectLater(
      snapshots.seoSnapshotHttpGet(
        server.url,
        headers: const {},
        retryWaits: _noWait,
      ),
      throwsA(isA<HttpException>()
          .having((e) => e.message, 'message', contains('503'))),
    );
    expect(server.served, [503, 503, 503, 503]);
  });
}
