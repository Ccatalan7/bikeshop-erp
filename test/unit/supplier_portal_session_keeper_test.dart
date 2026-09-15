import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_portal_session_keeper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps only validated sessions for the current ERP user alive',
      () async {
    var userId = 'user-a';
    final pings = <String>[];
    final keeper = SupplierPortalSessionKeeper(
      currentUserId: () => userId,
      ping: (url) async => pings.add(url),
      scheduleAutomatically: false,
    );

    keeper.activate(
      supplierId: 'supplier-1',
      url: 'http://legacy.example/catalog?code=ABC',
    );
    keeper.activate(
      supplierId: 'supplier-2',
      url: 'https://modern.example/search?q=camera',
    );
    await keeper.keepAliveNow();

    expect(
      pings,
      <String>[
        'http://legacy.example/catalog?code=ABC',
        'https://modern.example/search?q=camera',
      ],
    );
    expect(keeper.activeSessionCount, 2);

    userId = 'user-b';
    await keeper.keepAliveNow();
    expect(pings, hasLength(2));
    expect(keeper.activeSessionCount, 0);
  });

  test('rejects malformed, credential-bearing and non-web URLs', () async {
    final pings = <String>[];
    final keeper = SupplierPortalSessionKeeper(
      currentUserId: () => 'user-a',
      ping: (url) async => pings.add(url),
      scheduleAutomatically: false,
    );

    for (final url in <String>[
      'javascript:alert(1)',
      'file:///tmp/catalog.html',
      'https://user:secret@supplier.example/catalog',
      'not a url',
    ]) {
      keeper.activate(supplierId: 'supplier', url: url);
    }
    await keeper.keepAliveNow();

    expect(keeper.activeSessionCount, 0);
    expect(pings, isEmpty);
  });

  test('one failed portal does not block the remaining sessions', () async {
    final pings = <String>[];
    final keeper = SupplierPortalSessionKeeper(
      currentUserId: () => 'user-a',
      ping: (url) async {
        pings.add(url);
        if (url.contains('first')) throw StateError('offline');
      },
      scheduleAutomatically: false,
    );

    keeper.activate(
      supplierId: 'first',
      url: 'https://first.example/catalog',
    );
    keeper.activate(
      supplierId: 'second',
      url: 'https://second.example/catalog',
    );
    await keeper.keepAliveNow();

    expect(pings, hasLength(2));
    keeper.stop();
  });
}
