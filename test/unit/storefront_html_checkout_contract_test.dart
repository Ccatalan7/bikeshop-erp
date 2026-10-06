// The HTML checkout and order page (phases 3b and 3c of
// docs/architecture/storefront-html-migration-plan.md) keep the same records
// as Flutter's `CheckoutSessionStore`, so an order started in one store is
// shown and closed by the other (the app still runs Flutter's pages). This
// runs the pages' own records script in Node (with the page script that owns
// the cart) and reads what it wrote with Flutter's readers, both ways.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/public_store/services/cart_store.dart';
import 'package:vinabike_erp/public_store/services/checkout_session_store.dart';

const _tenant = '5443b130-cc28-45af-a420-cd500b288890';
const _a = '6f1d2a3e-0000-4000-8000-000000000911';
const _b = '6f1d2a3e-0000-4000-8000-000000000912';
const _order = '0b9b6a52-0000-4000-8000-000000000001';
const _attempt = '3d1c2b4a-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _token = 'tok_0123456789abcdefghijklmnopqrstuvwxyzABCDEF';

String _script(String file) {
  final source = File(file).readAsStringSync();
  final start = source.indexOf("r'''") + 4;
  return source.substring(start, source.indexOf("'''", start));
}

String _cartKey() =>
    'flutter.${SharedPreferencesCartStore.storageKeyForTenant(_tenant)}';

/// Runs [steps] (JavaScript, with `cart` and `R` in scope) after loading the
/// page script and the records script over the given storage, and returns
/// both storages as they end.
Future<({Map<String, String> session, Map<String, String> local, Object? out})>
    _run({
  Map<String, String> session = const {},
  Map<String, String> local = const {},
  required String steps,
}) async {
  final dir = await Directory.systemTemp.createTemp('checkout-contract');
  addTearDown(() => dir.delete(recursive: true));
  final page = File('${dir.path}/page.js')
    ..writeAsStringSync(
      _script('services/storefront_html/lib/src/storefront_script.dart'),
    );
  final records = File('${dir.path}/records.js')
    ..writeAsStringSync(
      _script('services/storefront_html/lib/src/checkout_records_script.dart'),
    );
  final harness = File('${dir.path}/harness.js')..writeAsStringSync('''
function storage(initial) {
  const values = Object.assign({}, initial);
  return {
    values,
    getItem: (k) => (k in values ? values[k] : null),
    setItem: (k, v) => { values[k] = String(v); },
    removeItem: (k) => { delete values[k]; },
  };
}
const noop = () => {};
globalThis.window = globalThis;
window.addEventListener = noop;
globalThis.localStorage = storage(${jsonEncode(local)});
globalThis.sessionStorage = storage(${jsonEncode(session)});
globalThis.location = { hash: '', href: 'https://vinabike.cl/checkout' };
Object.defineProperty(globalThis, 'navigator', { value: { locks: {
  request: (name, fn) => Promise.resolve().then(fn),
} } });
globalThis.document = {
  documentElement: { classList: { add: noop } },
  body: { dataset: { tenant: '$_tenant', cartKey: ${jsonEncode(_cartKey())} } },
  head: { appendChild: noop },
  createElement: () => ({}),
  addEventListener: noop,
  getElementById: () => null,
  querySelector: () => null,
  querySelectorAll: () => [],
};
require(${jsonEncode(page.path)});
require(${jsonEncode(records.path)});
const cart = window.vinabikeCart;
const R = window.vinabikeCheckoutRecords('$_tenant', cart);
(async () => {
  let out = null;
  $steps
  process.stdout.write(JSON.stringify({
    session: sessionStorage.values, local: localStorage.values, out,
  }));
})().catch((e) => { console.error(e && e.stack || e); process.exit(1); });
''');
  final result = await Process.run('node', [harness.path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return (
    session: Map<String, String>.from(decoded['session'] as Map),
    local: Map<String, String>.from(decoded['local'] as Map),
    out: decoded['out'],
  );
}

/// The Flutter cart the visitor arrives with.
String _savedCart({String revision = 'flutter-revision'}) => jsonEncode(
      jsonEncode(
        PersistedCart(
          tenantId: _tenant,
          savedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          lines: const [
            PersistedCartLine(productId: _a, quantity: 2),
            PersistedCartLine(productId: _b, quantity: 1),
          ],
          revision: revision,
        ).toJson(),
      ),
    );

/// The order the page builds (`buildOrder`) for those two lines, by
/// transfer, with home delivery.
String _orderSteps({required String expiresAt}) => '''
  const snap = await cart.ensureRevision();
  R.saveSnapshot({
    v: 1, tenant_id: '$_tenant', saved_at: new Date().toISOString(),
    idempotency_key: '$_attempt',
    order_data: {
      tenant_id: '$_tenant', checkout_idempotency_key: '$_attempt',
      customer_email: 'ana@example.invalid', customer_name: 'Ana Prueba',
      customer_phone: '+56 9 1234 5678',
      customer_address: 'Avenida Libertad 1234, Viña del Mar, Valparaíso, Chile',
      delivery_type: 'shipping', shipping_address_line1: 'Avenida Libertad 1234',
      shipping_address_line2: null, shipping_city: 'Viña del Mar',
      shipping_state: 'Valparaíso', shipping_postal_code: null, shipping_country: 'Chile',
      subtotal: 74790, tax_amount: 14210, shipping_quote_cost: 11990, shipping_cost: 11990,
      discount_amount: 0, total: 100990, status: 'pending', payment_status: 'pending',
      payment_method: 'transfer', customer_notes: null
    },
    order_items: [
      { tenant_id: '$_tenant', product_id: '$_a', product_name: 'Cassette', product_sku: 'C1', quantity: 2, unit_price: 35000, subtotal: 70000 },
      { tenant_id: '$_tenant', product_id: '$_b', product_name: 'Maza', product_sku: 'M1', quantity: 1, unit_price: 19000, subtotal: 19000 }
    ],
    handoff: { payment_method: 'transfer', delivery_type: 'shipping' },
    cart_revision: snap.revision
  });
  // The RPC's answer, as PostgREST returns it.
  const receipt = R.parseReceipt({ order_id: '$_order', access_token: '$_token', expires_at: '$expiresAt', replay: false });
  const current = R.readSnapshot();
  current.receipt = receipt;
  R.saveSnapshot(current);
  R.saveOrderAccess(receipt);
''';

/// A transfer attempt Flutter's checkout saved with its order's receipt.
CheckoutSessionSnapshot _flutterTransferAttempt() =>
    CheckoutSessionSnapshot.create(
      tenantId: _tenant,
      savedAt: DateTime.now().toUtc(),
      idempotencyKey: _attempt,
      orderData: {
        'tenant_id': _tenant,
        'checkout_idempotency_key': _attempt,
        'customer_email': 'ana@example.invalid',
        'customer_name': 'Ana Prueba',
        'customer_address': 'Retiro en tienda: Alvarez 32',
        'delivery_type': 'pickup',
        'subtotal': 74790.0,
        'tax_amount': 14210.0,
        'shipping_quote_cost': 0,
        'shipping_cost': 0,
        'discount_amount': 0,
        'total': 89000.0,
        'status': 'pending',
        'payment_status': 'pending',
        'payment_method': 'transfer',
      },
      orderItems: [
        {
          'tenant_id': _tenant,
          'product_id': _a,
          'product_name': 'Cassette',
          'quantity': 2,
          'unit_price': 35000.0,
          'subtotal': 70000.0,
        },
        {
          'tenant_id': _tenant,
          'product_id': _b,
          'product_name': 'Maza',
          'quantity': 1,
          'unit_price': 19000.0,
          'subtotal': 19000.0,
        },
      ],
      handoff: const CheckoutHandoffSnapshot(
        paymentMethod: 'transfer',
        deliveryType: 'pickup',
      ),
      cartRevision: 'flutter-revision',
    ).withReceipt(
      PublicOrderCheckoutAccess(
        orderId: _order,
        accessToken: _token,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
        isReplay: false,
      ),
    );

/// The keys Flutter wrote: [MemoryCheckoutSessionStorage] has no listing,
/// so the outcome key is rebuilt the way the store names it.
Future<List<String>> _keysOf(MemoryCheckoutSessionStorage storage) async {
  String b64(String value) => base64Url.encode(utf8.encode(value));
  final key =
      'vinabike.public-cart-preserved.v1.${b64(_tenant)}.${b64(_order)}';
  return [if (await storage.read(key) != null) key];
}

String _checkoutKey() => 'vinabike.public-checkout.v1.$_tenant';

Future<CheckoutSessionStore> _flutterStoreOver(
  Map<String, String> session,
) async {
  final storage = MemoryCheckoutSessionStorage();
  for (final MapEntry(:key, :value) in session.entries) {
    await storage.write(key, value);
  }
  return CheckoutSessionStore(storage: storage);
}

String _postgresTimestamp(DateTime value) {
  // `2026-11-05 07:25:03.349099+00`, what a timestamptz becomes in JSON.
  final iso = value.toUtc().toIso8601String().replaceFirst('T', ' ');
  return '${iso.substring(0, iso.length - 1)}+00:00';
}

void main() {
  final hasNode = Process.runSync('which', ['node']).exitCode == 0;
  final skip = hasNode ? false : 'node is not installed';

  test(
    'an HTML transfer order leaves what Flutter\'s order page reads',
    () async {
      final expires = DateTime.now().toUtc().add(const Duration(days: 30));
      final exact = DateTime.utc(
        expires.year,
        expires.month,
        expires.day,
        expires.hour,
        expires.minute,
        expires.second,
        349,
        99,
      );
      final run = await _run(
        local: {_cartKey(): _savedCart()},
        steps: '${_orderSteps(expiresAt: _postgresTimestamp(exact))}\n'
            "  out = await R.consumeCartOnce('$_order');",
      );
      final store = await _flutterStoreOver(run.session);

      final snapshot = await store.read(_tenant);
      expect(snapshot, isNotNull, reason: run.session.toString());
      expect(snapshot!.idempotencyKey, _attempt);
      expect(snapshot.handoff.paymentMethod, 'transfer');
      expect(snapshot.cartRevision, 'flutter-revision');
      expect(snapshot.receipt!.orderId, _order);
      expect(snapshot.receipt!.expiresAt, exact);
      expect(
        snapshot.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.applied,
      );

      final access = await store.readOrderAccess(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(access?.accessToken, _token);

      final outcome = await store.settleCartOutcomeForPresentation(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(outcome?.state, CheckoutCartOutcomeState.applied);
      expect(outcome?.showsWarning, isFalse);

      // What the order page does on entry for a transfer.
      final taken = await store.takeTransferReceiptIfMatches(
        tenantId: _tenant,
        orderId: _order,
        requireTerminalCartOutcome: true,
      );
      expect(taken?.receipt?.orderId, _order);
      expect(await store.read(_tenant), isNull);

      final cart = PersistedCart.fromJson(
        jsonDecode(jsonDecode(run.local[_cartKey()]!) as String),
      );
      expect(cart!.lines, isEmpty);
      expect(cart.revision, isNot('flutter-revision'));
    },
    skip: skip,
  );

  test(
    'a cart changed after the order keeps its lines and the page warns',
    () async {
      final expires = DateTime.now().toUtc().add(const Duration(days: 30));
      final run = await _run(
        local: {_cartKey(): _savedCart()},
        steps: '${_orderSteps(expiresAt: expires.toIso8601String())}\n'
            // Another tab adds a line before the subtraction.
            "  await cart.update((lines) => lines.concat([{ id: 'x-other', q: 1 }]));\n"
            "  out = await R.consumeCartOnce('$_order');",
      );
      final store = await _flutterStoreOver(run.session);
      final outcome = await store.readCartOutcome(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(outcome?.state, CheckoutCartOutcomeState.preserved);
      expect(outcome?.reason, 'cart_unavailable');
      expect(outcome?.showsWarning, isTrue);
      final cart = PersistedCart.fromJson(
        jsonDecode(jsonDecode(run.local[_cartKey()]!) as String),
      );
      expect(cart!.lines, hasLength(3));
    },
    skip: skip,
  );

  test(
    'an attempt Flutter saved is one the HTML checkout restores',
    () async {
      final saved = CheckoutSessionSnapshot.create(
        tenantId: _tenant,
        savedAt: DateTime.now().toUtc(),
        idempotencyKey: _attempt,
        orderData: {
          'tenant_id': _tenant,
          'checkout_idempotency_key': _attempt,
          'customer_email': 'ana@example.invalid',
          'customer_name': 'Ana Prueba',
          'customer_address': 'Retiro en tienda: Alvarez 32',
          'delivery_type': 'pickup',
          'subtotal': 29412.0,
          'tax_amount': 5588.0,
          'shipping_quote_cost': 0,
          'shipping_cost': 0,
          'discount_amount': 0,
          'total': 35000.0,
          'status': 'pending',
          'payment_status': 'pending',
          'payment_method': 'mercadopago',
        },
        orderItems: [
          {
            'tenant_id': _tenant,
            'product_id': _a,
            'product_name': 'Cassette',
            'quantity': 1,
            'unit_price': 35000.0,
            'subtotal': 35000.0,
          },
        ],
        handoff: const CheckoutHandoffSnapshot(
          paymentMethod: 'mercadopago',
          deliveryType: 'pickup',
        ),
        cartRevision: 'flutter-revision',
      ).withReceipt(
        PublicOrderCheckoutAccess(
          orderId: _order,
          accessToken: _token,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
          isReplay: false,
        ),
      );
      final run = await _run(
        session: {
          'vinabike.public-checkout.v1.$_tenant': jsonEncode(saved.toJson()),
        },
        steps: '  const s = R.readSnapshot();\n'
            '  out = s && { attempt: s.idempotency_key, order: s.receipt.order_id, method: s.handoff.payment_method };',
      );
      expect(run.out, {
        'attempt': _attempt,
        'order': _order,
        'method': 'mercadopago',
      });
    },
    skip: skip,
  );

  test(
    'an expired attempt is retired, as Flutter retires it',
    () async {
      final stale = {
        'v': 1,
        'tenant_id': _tenant,
        'saved_at': DateTime.now()
            .toUtc()
            .subtract(CheckoutSessionStore.maxAge + const Duration(minutes: 1))
            .toIso8601String(),
        'idempotency_key': _attempt,
      };
      final run = await _run(
        session: {'vinabike.public-checkout.v1.$_tenant': jsonEncode(stale)},
        steps: '  out = R.readSnapshot();',
      );
      expect(run.out, isNull);
      expect(run.session['vinabike.public-checkout.v1.$_tenant'], '');
    },
    skip: skip,
  );

  test(
    'a transfer Flutter\'s checkout placed is closed by the HTML order page '
    'as Flutter closes it',
    () async {
      final attempt = _flutterTransferAttempt();
      final run = await _run(
        session: {_checkoutKey(): jsonEncode(attempt.toJson())},
        local: {_cartKey(): _savedCart()},
        steps:
            // What the order page does on entry (`start`).
            "  const access = R.readOrderAccess('$_order');\n"
            '  const snap = R.readSnapshot();\n'
            '  R.saveOrderAccess(snap.receipt);\n'
            "  const settled = await R.settleOutcome('$_order');\n"
            "  const outcome = await R.consumeCartOnce('$_order');\n"
            "  const taken = R.takeTransferReceipt('$_order');\n"
            '  out = { before: access, settled, state: outcome.state, '
            'warning: R.showsWarning(outcome), taken: !!taken };',
      );
      final out = run.out as Map<String, dynamic>;
      expect(out['before'], isNull);
      expect(out['settled'], isNull);
      expect(out['state'], 'applied');
      expect(out['warning'], isFalse);
      expect(out['taken'], isTrue);

      final store = await _flutterStoreOver(run.session);
      expect(await store.read(_tenant), isNull);
      final access = await store.readOrderAccess(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(access?.accessToken, _token);
      final outcome = await store.readCartOutcome(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(outcome?.state, CheckoutCartOutcomeState.applied);
      final cart = PersistedCart.fromJson(
        jsonDecode(jsonDecode(run.local[_cartKey()]!) as String),
      );
      expect(cart!.lines, isEmpty);
    },
    skip: skip,
  );

  test(
    'a warning Flutter left is acknowledged by the HTML page for both',
    () async {
      final flutter = MemoryCheckoutSessionStorage();
      final store = CheckoutSessionStore(storage: flutter);
      await store.markCartPreservationWarning(
        tenantId: _tenant,
        orderId: _order,
      );
      final key = (await _keysOf(flutter)).single;
      final run = await _run(
        session: {key: (await flutter.read(key))!},
        steps: "  const before = R.showsWarning(R.readOutcome('$_order'));\n"
            "  const done = R.acknowledge('$_order');\n"
            "  const again = R.acknowledge('$_order');\n"
            "  out = { before, done, again, after: R.showsWarning(R.readOutcome('$_order')) };",
      );
      expect(run.out, {
        'before': true,
        'done': true,
        'again': false,
        'after': false,
      });
      final read = await _flutterStoreOver(run.session);
      final outcome = await read.readCartOutcome(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(outcome?.state, CheckoutCartOutcomeState.preserved);
      expect(outcome?.acknowledgedAt, isNotNull);
      expect(outcome?.reason, 'explicit_warning');
      expect(
        await read.hasCartPreservationWarning(
          tenantId: _tenant,
          orderId: _order,
        ),
        isFalse,
      );
    },
    skip: skip,
  );

  test(
    'a claim nobody finished is settled as preserved, as Flutter settles it',
    () async {
      final claimed = _flutterTransferAttempt().claimCartConsumption(
        claimId: 'claim-of-a-closed-tab',
        startedAt: DateTime.now().toUtc(),
      );
      final run = await _run(
        session: {_checkoutKey(): jsonEncode(claimed.toJson())},
        local: {_cartKey(): _savedCart()},
        steps: "  const o = await R.settleOutcome('$_order');\n"
            '  out = { state: o.state, reason: o.reason, warning: R.showsWarning(o) };',
      );
      expect(run.out, {
        'state': 'preserved',
        'reason': 'interrupted',
        'warning': true,
      });
      final store = await _flutterStoreOver(run.session);
      final snapshot = await store.read(_tenant);
      expect(
        snapshot?.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.preserved,
      );
      final outcome = await store.readCartOutcome(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(outcome?.reason, 'interrupted');
      // Nothing was subtracted.
      final cart = PersistedCart.fromJson(
        jsonDecode(jsonDecode(run.local[_cartKey()]!) as String),
      );
      expect(cart!.lines, hasLength(2));
    },
    skip: skip,
  );

  test(
    'an order token saved the old way is migrated as Flutter migrates it',
    () async {
      final run = await _run(
        session: {'vinabike.public-order-access.v1.$_order': _token},
        steps: "  out = R.readOrderAccess('$_order');",
      );
      expect((run.out as Map)['access_token'], _token);
      expect(run.session['vinabike.public-order-access.v1.$_order'], '');
      final store = await _flutterStoreOver(run.session);
      final access = await store.readOrderAccess(
        tenantId: _tenant,
        orderId: _order,
      );
      expect(access?.accessToken, _token);
      expect(
        access!.expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(days: 29)),
        ),
        isTrue,
      );
    },
    skip: skip,
  );
}
