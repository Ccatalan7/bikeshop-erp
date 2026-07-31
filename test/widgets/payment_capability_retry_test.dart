import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/services/public_checkout_capability_service.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

/// Behavioural contract of the footer payment-capability state machine.
///
/// Two neutral reproductions motivated it, both real on the previous code:
/// tenant A exhausting its three attempts locked tenant B out forever
/// (the budget reset keyed on the in-flight marker that every failure nulls),
/// and the 2 s / 8 s deadlines were passive gates that only an unrelated
/// rebuild could observe. These tests drive the real widget with the fake
/// test clock — source greps alone are explicitly not accepted as proof.
void main() {
  const tenantAId = '00000000-0000-4000-8000-0000000000aa';
  const tenantBId = '00000000-0000-4000-8000-0000000000bb';

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      null,
    );
  });

  PublicCheckoutCapabilities capabilities({
    required bool mercadopago,
    required bool transfer,
  }) {
    return PublicCheckoutCapabilities.fromRpc({
      'schemaVersion': 1,
      'methods': [
        {
          'code': 'mercadopago',
          'available': mercadopago,
          'reasonCode': mercadopago ? 'available' : 'configuration_incomplete',
        },
        {
          'code': 'transfer',
          'available': transfer,
          'reasonCode': transfer ? 'available' : 'configuration_incomplete',
        },
      ],
    });
  }

  Tenant tenant(String id, String name) => Tenant(
        id: id,
        shopName: name,
        subdomain: name.toLowerCase(),
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
      );

  /// Pumps the full storefront layout at a desktop width tall enough for the
  /// footer — where the payment claims live — to be laid out.
  Future<PublicStoreTenantProvider> pumpLayout(
    WidgetTester tester, {
    required PublicCheckoutCapabilityLoader loader,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1300, 4200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'website_public_v2_settings_$tenantAId': jsonEncode({
        'store_name': 'TIENDA A',
        'show_top_banner': 'false',
      }),
      'website_public_v2_blocks_$tenantAId': '[]',
      'website_public_v2_last_refresh_$tenantAId':
          DateTime.now().millisecondsSinceEpoch,
    });
    final preferences = await SharedPreferences.getInstance();
    WebsiteService.setSharedPreferences(preferences);

    final website = WebsiteService();
    website.loadSettingsFromSynchronousCache(tenantAId);
    final editMode = WebsiteEditModeProvider();
    final tenantProvider = PublicStoreTenantProvider(TenantDetectionService())
      ..setTenant(tenant(tenantAId, 'TIENDA-A'));
    final cart = CartProvider();
    final inventory = PublicInventoryService();
    final scrollState = PublicStoreScrollState();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: website),
              ChangeNotifierProvider.value(value: editMode),
              ChangeNotifierProvider.value(value: tenantProvider),
              ChangeNotifierProvider.value(value: cart),
              ChangeNotifierProvider.value(value: inventory),
              Provider.value(value: scrollState),
            ],
            child: PublicStoreLayout(
              checkoutCapabilityLoader: loader,
              child: const SizedBox(height: 40),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(website.dispose);
    addTearDown(editMode.dispose);
    addTearDown(tenantProvider.dispose);
    addTearDown(cart.dispose);
    addTearDown(inventory.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    // Two extra frames: one for the initial layout, one so the footer's
    // post-frame scheduling and the loader's microtasks run.
    await tester.pump();
    await tester.pump();
    return tenantProvider;
  }

  testWidgets(
      'retries fire from the timer at exactly 2 s and 8 s, cap at three '
      'requests, and a new tenant starts with a fresh budget', (tester) async {
    final calls = <String>[];
    Future<PublicCheckoutCapabilities> loader(String tenantId) async {
      calls.add(tenantId);
      throw StateError('transient backend failure');
    }

    final tenantProvider = await pumpLayout(tester, loader: loader);

    // Initial attempt for A, scheduled by the footer build itself.
    expect(calls, [tenantAId]);

    // Nothing fires early: the deadline belongs to the timer, and no
    // external setState happens between these pumps.
    await tester.pump(const Duration(milliseconds: 1999));
    expect(calls.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls.length, 2, reason: 'first retry fires at exactly +2 s');

    await tester.pump(const Duration(milliseconds: 7999));
    expect(calls.length, 2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls.length, 3, reason: 'second retry fires at exactly +8 s');

    // Budget exhausted for A: no fourth request, no matter how long we wait
    // or how many rebuilds happen.
    await tester.pump(const Duration(minutes: 2));
    expect(calls.length, 3);
    expect(calls.toSet(), {tenantAId});

    // Tenant B is not punished for A's failures: it starts immediately.
    tenantProvider.setTenant(tenant(tenantBId, 'TIENDA-B'));
    await tester.pump();
    await tester.pump();
    expect(calls.length, 4, reason: 'B must request despite A\'s exhaustion');
    expect(calls.last, tenantBId);

    // Fail-closed throughout: no claim was ever rendered.
    expect(find.text('Medios de Pago'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a late response for tenant A never paints tenant B',
      (tester) async {
    final completers = <String, Completer<PublicCheckoutCapabilities>>{};
    Future<PublicCheckoutCapabilities> loader(String tenantId) {
      final completer = Completer<PublicCheckoutCapabilities>();
      completers[tenantId] = completer;
      return completer.future;
    }

    final tenantProvider = await pumpLayout(tester, loader: loader);
    expect(completers.keys, contains(tenantAId));

    // Switch to B while A's request is still in flight.
    tenantProvider.setTenant(tenant(tenantBId, 'TIENDA-B'));
    await tester.pump();
    await tester.pump();
    expect(completers.keys, contains(tenantBId));

    // A's answer arrives late, claiming MercadoPago. It must be discarded by
    // the generation guard: painting it would attribute A's payment methods
    // to B's storefront.
    completers[tenantAId]!.complete(
      capabilities(mercadopago: true, transfer: false),
    );
    await tester.pump();
    expect(find.text('Medios de Pago'), findsNothing);
    expect(find.text('MercadoPago'), findsNothing);

    // B's own answer paints B's truth: transfer only.
    completers[tenantBId]!.complete(
      capabilities(mercadopago: false, transfer: true),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Medios de Pago'), findsOneWidget);
    expect(find.text('Transferencia bancaria'), findsOneWidget);
    expect(find.text('MercadoPago'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dispose cancels the pending retry timer', (tester) async {
    final calls = <String>[];
    Future<PublicCheckoutCapabilities> loader(String tenantId) async {
      calls.add(tenantId);
      throw StateError('transient backend failure');
    }

    await pumpLayout(tester, loader: loader);
    expect(calls.length, 1);

    // The first failure has armed the 2 s timer. Dispose before it fires.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // If dispose had not cancelled it, this pump would fire the timer against
    // a defunct element — the loader would record a second call and the
    // framework would surface the leaked-timer failure.
    await tester.pump(const Duration(seconds: 10));
    expect(calls.length, 1);
    expect(tester.takeException(), isNull);
  });
}
