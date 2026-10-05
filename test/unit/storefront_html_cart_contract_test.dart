// The HTML storefront's «Agregar al carrito» writes the cart the Flutter store
// reads (phase 1 of docs/architecture/storefront-html-migration-plan.md). This
// runs the page script itself in Node against a stub of the page and decodes
// what it stored with the Flutter cart's own reader, both ways.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/services/cart_store.dart';

const _tenant = '5443b130-cc28-45af-a420-cd500b288890';
const _product = '6f1d2a3e-0000-4000-8000-000000000911';
const _other = '6f1d2a3e-0000-4000-8000-000000000912';

/// The page script, as the server sends it.
String _pageScript() {
  final source = File(
    'services/storefront_html/lib/src/storefront_script.dart',
  ).readAsStringSync();
  final start = source.indexOf("r'''") + 4;
  return source.substring(start, source.indexOf("'''", start));
}

/// The key `shared_preferences` uses on the web for the Flutter cart.
String _webKey() => 'flutter.${SharedPreferencesCartStore.storageKeyForTenant(_tenant)}';

/// The key every store shared before the cart was kept per store.
const _legacyWebKey =
    'flutter.${SharedPreferencesCartStore.legacyStorageKey}';

/// Runs the script with [stored] in localStorage, submits the add form once
/// per quantity in [adds], and returns what localStorage holds and the Web
/// Lock it asked for.
Future<({String? stored, String? legacy, List<String> locks})> _runAdds({
  String? stored,
  String? legacy,
  required List<int> adds,
  int max = 0,
  bool failRemove = false,
}) async {
  final dir = await Directory.systemTemp.createTemp('cart-contract');
  addTearDown(() => dir.delete(recursive: true));
  final page = File('${dir.path}/page.js')..writeAsStringSync(_pageScript());
  final harness = File('${dir.path}/harness.js')
    ..writeAsStringSync('''
const store = {};
const initial = ${jsonEncode(stored)};
if (initial !== null) store[${jsonEncode(_webKey())}] = initial;
const legacy = ${jsonEncode(legacy)};
if (legacy !== null) store[${jsonEncode(_legacyWebKey)}] = legacy;
const locks = [];
const noop = () => {};
const classList = { add: noop };
const quantity = { value: '1' };
const product = { dataset: {
  productId: '$_product', itemId: 'H911', itemName: 'Horquilla',
  price: '550000', max: '$max' } };
let submit = null;
const form = { addEventListener: (type, fn) => { if (type === 'submit') submit = fn; } };
globalThis.window = globalThis;
window.addEventListener = noop;
globalThis.location = { hash: '', href: 'https://vinabike.cl/productos/x/H911' };
globalThis.localStorage = {
  getItem: (k) => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: (k) => { if ($failRemove) throw new Error('quota'); delete store[k]; },
};
Object.defineProperty(globalThis, 'navigator', { value: { locks: {
  request: (name, fn) => { locks.push(name); return Promise.resolve().then(fn); },
} } });
globalThis.document = {
  documentElement: { classList },
  body: { dataset: { tenant: '$_tenant', cartKey: ${jsonEncode(_webKey())} } },
  head: { appendChild: noop },
  createElement: () => ({}),
  addEventListener: noop,
  getElementById: () => null,
  querySelector: (s) => s === '[data-product-id]' ? product
    : s === 'form.cart input[name=cantidad]' ? quantity : null,
  querySelectorAll: (s) => s === 'form.cart' ? [form] : [],
};
require(${jsonEncode(page.path)});
(async () => {
  for (const q of ${jsonEncode(adds)}) {
    quantity.value = String(q);
    submit({ preventDefault: noop });
    await new Promise((r) => setTimeout(r, 10));
  }
  const key = ${jsonEncode(_webKey())};
  const old = ${jsonEncode(_legacyWebKey)};
  process.stdout.write(JSON.stringify({
    stored: key in store ? store[key] : null,
    legacy: old in store ? store[old] : null,
    locks,
  }));
})();
''');
  final result = await Process.run('node', [harness.path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final out = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return (
    stored: out['stored'] as String?,
    legacy: out['legacy'] as String?,
    locks: (out['locks'] as List).cast<String>(),
  );
}

/// The stored value decoded the way `SharedPreferencesCartBackend` reads it on
/// the web: a JSON string holding the cart document.
PersistedCart? _decode(String stored) =>
    PersistedCart.fromJson(jsonDecode(jsonDecode(stored) as String));

void main() {
  final hasNode = Process.runSync('which', ['node']).exitCode == 0;

  test(
    'an HTML add writes a cart the Flutter store reads',
    () async {
      final run = await _runAdds(adds: [2, 1]);
      final cart = _decode(run.stored!);
      expect(cart, isNotNull, reason: run.stored);
      expect(cart!.tenantId, _tenant);
      expect(cart.lines.single.productId, _product);
      expect(cart.lines.single.quantity, 3);
      expect(cart.revision, isNotEmpty);
      expect(cart.appliedMutations, hasLength(2));
      expect(
        DateTime.now().toUtc().difference(cart.savedAt).inMinutes,
        lessThan(1),
      );
      // The same lock the Flutter store writes under.
      final lockName = RegExp(
        r"_storageLockName =\s*'([^']+)'",
      ).firstMatch(
        File('lib/public_store/services/cart_store.dart').readAsStringSync(),
      )!.group(1);
      expect(run.locks, everyElement(lockName));
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test(
    'an HTML add keeps what the Flutter store saved, and its stock limit',
    () async {
      final saved = PersistedCart(
        tenantId: _tenant,
        savedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        lines: const [
          PersistedCartLine(productId: _other, quantity: 2),
          PersistedCartLine(productId: _product, quantity: 1),
        ],
        revision: 'flutter-revision',
        appliedMutations: {
          'flutter-op': DateTime.now().toUtc().subtract(
            const Duration(hours: 1),
          ),
        },
      );
      final run = await _runAdds(
        stored: jsonEncode(jsonEncode(saved.toJson())),
        adds: [5],
        max: 3,
      );
      final cart = _decode(run.stored!)!;
      final quantities = {
        for (final line in cart.lines) line.productId: line.quantity,
      };
      expect(quantities, {_other: 2, _product: 3});
      expect(cart.appliedMutations.keys, contains('flutter-op'));
      expect(cart.revision, isNot('flutter-revision'));
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test(
    'a cart older than the Flutter retention is replaced, not extended',
    () async {
      final old = PersistedCart(
        tenantId: _tenant,
        savedAt: DateTime.now().toUtc().subtract(
          CartStore.maxAge + const Duration(hours: 1),
        ),
        lines: const [PersistedCartLine(productId: _other, quantity: 4)],
      );
      final run = await _runAdds(
        stored: jsonEncode(jsonEncode(old.toJson())),
        adds: [1],
      );
      final cart = _decode(run.stored!)!;
      expect(cart.lines.single.productId, _product);
      expect(cart.lines.single.quantity, 1);
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test(
    'an HTML add moves this store\'s basket out of the old shared key',
    () async {
      final saved = PersistedCart(
        tenantId: _tenant,
        savedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        lines: const [PersistedCartLine(productId: _other, quantity: 2)],
      );
      final run = await _runAdds(
        legacy: jsonEncode(jsonEncode(saved.toJson())),
        adds: [1],
      );
      final cart = _decode(run.stored!)!;
      expect(
        {for (final line in cart.lines) line.productId: line.quantity},
        {_other: 2, _product: 1},
      );
      expect(run.legacy, isNull);
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test(
    'a failure to clear the old key does not undo nor repeat the add',
    () async {
      final saved = PersistedCart(
        tenantId: _tenant,
        savedAt: DateTime.now().toUtc(),
        lines: const [PersistedCartLine(productId: _other, quantity: 2)],
      );
      final run = await _runAdds(
        legacy: jsonEncode(jsonEncode(saved.toJson())),
        adds: [1, 1],
        failRemove: true,
      );
      final cart = _decode(run.stored!)!;
      // Two adds of one unit: two units, not three from a retried failure.
      expect(
        {for (final line in cart.lines) line.productId: line.quantity},
        {_other: 2, _product: 2},
      );
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test(
    'another store\'s basket in the old shared key is left alone',
    () async {
      final other = PersistedCart(
        tenantId: '00000000-0000-4000-8000-000000000000',
        savedAt: DateTime.now().toUtc(),
        lines: const [PersistedCartLine(productId: _other, quantity: 2)],
      );
      final legacy = jsonEncode(jsonEncode(other.toJson()));
      final run = await _runAdds(legacy: legacy, adds: [1]);
      expect(_decode(run.stored!)!.lines.single.productId, _product);
      expect(run.legacy, legacy);
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test(
    'a write id in Flutter\'s first encoding survives an HTML add',
    () async {
      final savedAt = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final document = {
        'v': 1,
        'tenant': _tenant,
        'saved_at': savedAt.toIso8601String(),
        'lines': [
          {'id': _other, 'q': 1},
        ],
        'revision': 'r1',
        'applied_mutations': ['flutter-op'],
      };
      expect(PersistedCart.fromJson(document), isNotNull);
      final run = await _runAdds(
        stored: jsonEncode(jsonEncode(document)),
        adds: [1],
      );
      final cart = _decode(run.stored!)!;
      expect(cart.appliedMutations.keys, contains('flutter-op'));
      expect(cart.appliedMutations, hasLength(2));
    },
    skip: hasNode ? false : 'node is not installed',
  );

  test('the page and the script use the Flutter key, schema and limits', () {
    final script = _pageScript();
    expect(script, contains('v: 1, tenant: tenant, saved_at: at, lines: lines'));
    expect(CartStore.schemaVersion, 1);
    expect(script, contains('var maxAge = 7 * 864e5;'));
    expect(CartStore.maxAge, const Duration(days: 7));
    expect(script, contains('var futureSkew = 5 * 6e4;'));
    expect(CartStore.allowedFutureSkew, const Duration(minutes: 5));
    final layout = File(
      'services/storefront_html/lib/src/site_layout.dart',
    ).readAsStringSync();
    expect(
      layout,
      contains(
        r"'flutter.public_store_cart_v2.${base64Url.encode(utf8.encode(context.tenantId))}'",
      ),
    );
    expect(
      SharedPreferencesCartStore.storageKeyForTenant(_tenant),
      'public_store_cart_v2.${base64Url.encode(utf8.encode(_tenant))}',
    );
  });
}
