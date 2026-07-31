import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/pages/contact_page.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

/// Behavioural guard for the `/contacto` availability gate.
///
/// **This inverts an earlier decision, deliberately.** The first version used
/// `pages.isNotEmpty` as the authority signal and failed *open* so a cold
/// start could not blank a published page. That heuristic was wrong in both
/// directions: a tenant whose authoritative page list is legitimately empty
/// stayed public forever, and a list loaded for another tenant counted as
/// authority for this one.
///
/// With `hasAuthoritativePagePublicationForTenant(tenantId)` the trade-off
/// disappears — the public store bootstrap awaits `loadPagesForTenant` before
/// this route paints, so "unknown" now genuinely means the load failed, and
/// leaking contact data on a failed read is worse than an unavailable page.
/// Public therefore fails **closed**; Edit and Preview stay reachable.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> pumpContact(
    WidgetTester tester, {
    required bool isEditMode,
    String? tenantId = 'tenant-contact-test',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    WebsiteService.setSharedPreferences(preferences);
    final website = WebsiteService();
    final editMode = WebsiteEditModeProvider();
    final tenant = PublicStoreTenantProvider(TenantDetectionService());
    if (tenantId != null) {
      tenant.setTenant(
        Tenant(
          id: tenantId,
          shopName: 'Tienda',
          subdomain: 'tienda',
          createdAt: DateTime.utc(2026, 7, 28),
          updatedAt: DateTime.utc(2026, 7, 28),
        ),
      );
    }
    if (isEditMode) {
      editMode.enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        pageSlug: 'contacto',
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WebsiteService>.value(value: website),
          ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: editMode,
          ),
          ChangeNotifierProvider<PublicStoreTenantProvider>.value(
            value: tenant,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ContactPage()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('public fails closed while page authority is unknown',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpContact(tester, isEditMode: false);

    // No authoritative page load happened, so publication is unknown and the
    // storefront must not serve contact content.
    expect(find.text('Contacto no disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an absent tenant also fails closed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpContact(tester, isEditMode: false, tenantId: null);

    expect(find.text('Contacto no disponible'), findsOneWidget);
  });

  testWidgets('Edit context stays reachable despite unknown authority',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpContact(tester, isEditMode: true);

    // The editor must always be able to open and author this route.
    expect(find.text('Contacto no disponible'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unset contact fields are omitted, never substituted',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Exercised in the editor context so the real content renders; the public
    // path is covered by the fail-closed tests above.
    await pumpContact(tester, isEditMode: true);

    // Form field labels are legitimate visual placeholders and may stay. What
    // must never appear is another tenant's real contact data presented as
    // this store's own.
    expect(find.textContaining('vinabike'), findsNothing);
    expect(find.textContaining('Vinabike'), findsNothing);
    expect(find.textContaining('Viñabike'), findsNothing);
    expect(find.textContaining('Álvarez 32'), findsNothing);
    expect(find.textContaining('+56 9 9835'), findsNothing);

    // The info panel's address row is value-driven, so with no configured
    // address it must not render its label either.
    expect(find.text('Dirección'), findsNothing);
  });

  testWidgets('the send action is disabled without a configured mailbox',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpContact(tester, isEditMode: true);

    final button = tester.widget<FilledButton>(
      find.byType(FilledButton).first,
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'a mailto with no recipient must not be offered',
    );
  });
}
