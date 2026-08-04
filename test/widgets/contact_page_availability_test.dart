import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
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
    ThemeData? theme,
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
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(
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

  testWidgets(
      'a dark custom theme drives the REAL rendered surfaces and text, '
      'not the old hardcoded light palette', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Custom dark storefront: explicit background and text, distinctive
    // primary. The page must consume the PROJECTED ThemeData roles, so every
    // asserted value below is the exact rendered color, not token presence.
    const customBackground = Color(0xFF10141C);
    const customText = Color(0xFFE6EDF3);
    const customPrimary = Color(0xFF7BD1FF);
    final resolved = WebsiteResolvedTheme.fallback.copyWith(
      backgroundColor: customBackground,
      textColor: customText,
      primaryColor: customPrimary,
    );
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(),
      resolved: resolved,
    );
    final colorScheme = theme.colorScheme;
    expect(colorScheme.surface, customBackground,
        reason: 'harness sanity: the builder projects the custom background');
    expect(colorScheme.onSurface, customText,
        reason: 'harness sanity: the builder projects the custom text color');

    await pumpContact(tester, isEditMode: true, theme: theme);

    Container containerWithColorAround(String text) {
      final candidates = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text(text),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.color != null || c.decoration is BoxDecoration);
      expect(candidates, isNotEmpty,
          reason: 'no painted Container found around "$text"');
      return candidates.first;
    }

    Color? containerFill(Container container) =>
        container.color ?? (container.decoration as BoxDecoration?)?.color;

    // Hero: themed surface with the custom text color, never white-on-light.
    final hero = containerWithColorAround('Contáctanos');
    expect(containerFill(hero), colorScheme.surface);
    final heroTitle = tester.widget<Text>(find.text('Contáctanos'));
    expect(heroTitle.style?.color, customText);

    // Main content band: themed container tone derived from the dark
    // background, not Colors.grey.shade50.
    final mainBand = containerWithColorAround('Envíanos un mensaje');
    final mainBandFill = containerFill(mainBand);
    expect(mainBandFill, isNotNull);
    expect(mainBandFill, isNot(Colors.white));
    expect(
      mainBandFill == colorScheme.surface ||
          mainBandFill == colorScheme.surfaceContainerLow,
      isTrue,
      reason: 'the form region paints projected surface roles, got '
          '$mainBandFill',
    );

    // Form card: themed surface plus themed outline border.
    final formCard = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('Envíanos un mensaje'),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).border != null);
    final formDecoration = formCard.decoration as BoxDecoration;
    expect(formDecoration.color, colorScheme.surface);
    expect(
      (formDecoration.border as Border).top.color,
      colorScheme.outlineVariant,
    );
    final formTitle = tester.widget<Text>(find.text('Envíanos un mensaje'));
    expect(formTitle.style?.color, customText);

    // Inputs: themed fill and themed muted hint, readable over dark.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.decoration?.fillColor, colorScheme.surfaceContainerLow);
    expect(
      field.decoration?.hintStyle?.color,
      colorScheme.onSurfaceVariant,
    );

    // Info panel card and its heading follow the same projected roles.
    final infoCard = containerWithColorAround('Información de Contacto');
    expect(containerFill(infoCard), colorScheme.surfaceContainerLow,
        reason: 'the info card paints the themed container tone');
    final infoTitle = tester.widget<Text>(find.text('Información de Contacto'));
    expect(infoTitle.style?.color, customText);

    expect(tester.takeException(), isNull);
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
