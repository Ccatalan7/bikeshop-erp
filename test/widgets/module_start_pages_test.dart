import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/settings/models/company_profile.dart';
import 'package:vinabike_erp/modules/settings/pages/settings_page.dart';
import 'package:vinabike_erp/modules/settings/services/meta_settings_service.dart';
import 'package:vinabike_erp/modules/settings/services/settings_overview_service.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/pages/website_management_page.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

const _tenantId = '7e141014-0000-4000-8000-000000000001';

// The app's own theme: the band and the groups read the theme's roles.
final _theme = AppTheme.resolve(
  preset: AppearancePresets.vinabike,
  brightness: Brightness.light,
);

SupabaseClient _offlineClient() => SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode([]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

class _Profiles extends CurrentUserProfileService {
  _Profiles(this._value);

  final CurrentUserProfile _value;

  @override
  CurrentUserProfile? get profile => _value;

  @override
  bool get isLoading => false;
}

CurrentUserProfile _admin() => const CurrentUserProfile(
      userId: 'user-1',
      email: 'taller@example.cl',
      emailVerified: true,
      displayName: 'Taller',
      tenantId: _tenantId,
      tenantName: 'Viñabike',
      tenantSubdomain: 'vinabike',
      role: 'admin',
      permissions: {},
      employeeLinkState: EmployeeLinkState.unlinked,
      employee: null,
    );

class _Overview extends SettingsOverviewService {
  _Overview(this._value) : super(client: _offlineClient());

  final SettingsOverview _value;
  final requested = <String>[];

  @override
  Future<SettingsOverview> load(String tenantId) async {
    requested.add(tenantId);
    return _value;
  }
}

MetaChannelStatus _meta(MetaChannelProvider provider, DateTime expiresAt) =>
    MetaChannelStatus(
      id: provider.name,
      provider: provider,
      externalAccountId: '1',
      displayName: null,
      username: null,
      grantedPermissions: const [],
      authorizationExpiresAt: expiresAt,
      subscribedAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
      isActive: true,
    );

SettingsOverview _realisticOverview() => SettingsOverview(
      company: CompanyProfile.fromMap(const {
        'name': 'Viñabike',
        'legal_name': 'Taller Ejemplo SpA',
        'tax_id': '76.000.000-0',
        'comuna': 'Viña del Mar',
      }),
      users: const SettingsUsersOverview(active: 3, roles: {'admin'}),
      backup: SettingsBackupOverview(
        lastBackupAt: DateTime.utc(2025, 12, 9, 8, 20),
        scheduled: false,
      ),
      channels: SettingsChannelsOverview(
        whatsappConnected: true,
        meta: [
          _meta(MetaChannelProvider.instagram, DateTime.utc(2026, 9, 20)),
          _meta(
            MetaChannelProvider.facebookMessenger,
            DateTime.utc(2026, 9, 20),
          ),
        ],
      ),
    );

class _HubWebsiteService extends WebsiteService {
  _HubWebsiteService()
      : super(
          supabase: _offlineClient(),
          tenantService: TenantService.testing(
            currentUserId: () => 'user-1',
            profileLookup: (_) async => const [
              {'tenant_id': _tenantId, 'role': 'admin', 'permissions': null},
            ],
          ),
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

  @override
  Future<void> initialize() async {}

  @override
  Future<void> initializeOrders() async {}

  @override
  List<Map<String, dynamic>> get blocks => [
        {'block_type': 'carousel', 'is_visible': true, 'block_data': {}},
        {
          'block_type': 'products',
          'is_visible': true,
          'block_data': {'productSource': 'featured', 'maxProducts': 6},
        },
        {'block_type': 'faq', 'is_visible': false, 'block_data': {}},
      ];

  @override
  List<FeaturedProduct> get featuredProducts => [
        for (var i = 0; i < 16; i++)
          FeaturedProduct(
            id: 'f$i',
            tenantId: _tenantId,
            productId: 'p$i',
            active: true,
            orderIndex: i,
            createdAt: DateTime.utc(2026, 10, 1),
          ),
      ];
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  // The pages choose their layout from MediaQuery, which follows the view,
  // not the render surface.
  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {required CurrentUserProfile profile}) =>
      ChangeNotifierProvider<CurrentUserProfileService>.value(
        value: _Profiles(profile),
        child: MaterialApp(theme: _theme, home: child),
      );

  group('Configuración', () {
    testWidgets('the band says the real state and the installed version',
        (tester) async {
      await setSize(tester, const Size(1600, 1000));
      final overview = _Overview(_realisticOverview());
      await tester.pumpWidget(
        host(
          SettingsPage(
            overviewService: overview,
            readVersion: () async => '1.0.36+62',
          ),
          profile: _admin(),
        ),
      );
      await tester.pumpAndSettle();

      expect(overview.requested, [_tenantId]);
      expect(find.text('taller@example.cl'), findsOneWidget);
      expect(find.text('Administrador · Viñabike'), findsOneWidget);
      expect(find.text('Taller Ejemplo SpA'), findsOneWidget);
      expect(find.text('RUT 76.000.000-0 · Viña del Mar'), findsOneWidget);
      expect(find.text('todos administradores'), findsOneWidget);
      expect(find.text('9 dic 2025'), findsOneWidget);
      expect(
        find.textContaining('sin respaldo automático'),
        findsOneWidget,
      );
      expect(find.text('1 de 3'), findsOneWidget);
      expect(
        find.text('Instagram y Messenger: autorización vencida'),
        findsOneWidget,
      );
      // The version is the build's, never a number typed in the source.
      expect(find.text('Viñabike ERP 1.0.36'), findsOneWidget);
      expect(find.text('Versión 1.0.36 · compilación 62'), findsOneWidget);
      expect(find.textContaining('1.0.1'), findsNothing);
      // No slogan and no area/entry counters.
      expect(find.textContaining('Centro de control'), findsNothing);
      expect(find.textContaining('Accesos'), findsNothing);
      // Every settings page is still one tap away, with accents.
      for (final title in const [
        'Datos de la empresa',
        'Horario de atención',
        'Usuarios y roles',
        'Apariencia',
        'WhatsApp',
        'Instagram y Messenger',
        'Notificaciones',
        'Lector USB o teclado',
        'Lector Bluetooth',
        'Escáner móvil',
        'Impresora de etiquetas',
        'Métodos de pago',
        'Terminales y abonos',
        'Plan de cuentas',
        'Respaldo y restauración',
        'Reinicio de datos',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone keeps the band short and says what needs attention',
        (tester) async {
      await setSize(tester, const Size(390, 900));
      await tester.pumpWidget(
        host(
          SettingsPage(
            overviewService: _Overview(_realisticOverview()),
            readVersion: () async => '1.0.36+62',
          ),
          profile: _admin(),
        ),
      );
      await tester.pumpAndSettle();

      // Three figures on the phone; the company lives in its own row.
      expect(find.text('Taller Ejemplo SpA'), findsNothing);
      expect(find.text('Usuarios'), findsOneWidget);
      expect(find.text('Último respaldo'), findsOneWidget);
      // The Chilean clock: 2026-09-20 00:00 UTC is still the 19th there.
      expect(find.text('Autorización vencida el 19 sep'), findsOneWidget);
      expect(find.text('Último hace 10 meses · sin agenda'), findsOneWidget);
      final firstGroup = tester.getTopLeft(find.text('Empresa y acceso'));
      expect(firstGroup.dy, lessThan(240));
      expect(tester.takeException(), isNull);
    });
  });

  group('Sitio web', () {
    testWidgets(
        'the band dates the live site on the shop clock and counts '
        'the featured products the home really shows', (tester) async {
      await setSize(tester, const Size(1600, 1000));
      final service = _HubWebsiteService();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteService>.value(
          value: service,
          child: MaterialApp(
            theme: _theme,
            home: WebsiteManagementPage(
              embedded: true,
              readPublication: (_) async => WebsiteHubPublication(
                host: 'vinabike.cl',
                builtAt: DateTime.utc(2026, 10, 13, 18, 59, 39),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('vinabike.cl en línea'), findsOneWidget);
      expect(
        find.text('Última publicación: 13 oct, 15:59'),
        findsOneWidget,
      );
      expect(find.text('en portada · 16 elegidos'), findsOneWidget);
      expect(find.text('aún no hay pedidos'), findsOneWidget);
      expect(find.text('todo al día'), findsOneWidget);
      expect(find.textContaining('vitrina'), findsNothing);
      expect(find.text('Presencia en internet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a store without its address says so', (tester) async {
      await setSize(tester, const Size(390, 900));
      final service = _HubWebsiteService();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteService>.value(
          value: service,
          child: MaterialApp(
            theme: _theme,
            home: WebsiteManagementPage(
              embedded: true,
              readPublication: (_) async =>
                  const WebsiteHubPublication(host: null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Falta la dirección de la tienda'), findsOneWidget);
      expect(find.text('Abrir editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
