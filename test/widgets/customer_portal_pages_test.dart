import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
import 'package:vinabike_erp/public_store/pages/customer_bikes_page.dart';
import 'package:vinabike_erp/public_store/pages/customer_profile_page.dart';
import 'package:vinabike_erp/public_store/pages/customer_service_history_page.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:vinabike_erp/public_store/theme/public_store_theme.dart';
import 'package:vinabike_erp/public_store/widgets/customer_portal_layout.dart';

/// Portal de clientes, etapa 2: Perfil, Taller, Bicicletas y la puerta de
/// entrada sin sesión, montados con sus páginas reales en teléfono y
/// escritorio, sin Supabase detrás.
class _FakeAccount extends CustomerAccountService {
  _FakeAccount({this.authenticated = true});

  final bool authenticated;

  @override
  bool get isAuthenticated => authenticated;

  @override
  bool get hasAuthSession => false;

  @override
  bool get isCustomerMembershipLoading => false;

  @override
  bool get isLoading => false;

  @override
  bool get hasPendingOtherSessionsRevocation => false;

  @override
  Map<String, dynamic>? get customerProfile => const {
        'id': 'c-1',
        'tenant_id': 't-1',
        'name': 'Usuario',
        'email': 'cliente@example.com',
        'phone': '+56 9 1234 5678',
      };

  @override
  List<Map<String, dynamic>> get serviceHistory => _jobs;

  @override
  List<Map<String, dynamic>> get bikes => _bikes;

  @override
  Future<void> loadServiceHistory() async {}

  @override
  Future<void> loadBikes() async {}
}

final _jobs = <Map<String, dynamic>>[
  {
    'id': 'j-1',
    'job_number': 'PG-00575',
    'bike_id': 'b-1',
    'bike_brand': 'Trek',
    'bike_model': 'Marlin 7',
    'status': 'ESPERANDO_APROBACION',
    'client_request': 'Cambio de maneta izquierda +DIAGNÓSTICO',
    'arrival_date': '2026-09-24T13:00:00Z',
    'total_cost': 10000,
  },
  {
    'id': 'j-2',
    'job_number': 'PG-00574',
    'bike_id': 'b-2',
    'bike_brand': 'Oxford',
    'bike_model': 'Cyclotour',
    'status': 'ENTREGADO',
    'client_request': '+Enrayado rueda delantera.\n+Mantención maza trasera.',
    'arrival_date': '2026-09-23T13:00:00Z',
    'total_cost': 32000,
  },
];

final _bikes = <Map<String, dynamic>>[
  {
    'id': 'b-1',
    'brand': 'Trek',
    'model': 'Marlin 7',
    'color': 'negra',
    'wheel_size': "29''",
    'bike_type': 'mountain_hardtail',
    'service_count': 1,
    'last_service_date': '2026-09-24T13:00:00Z',
  },
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  for (final width in [375.0, 1280.0]) {
    testWidgets('perfil a $width px: pide el nombre en vez de «Usuario»',
        (tester) async {
      await _pumpPage(
          tester, width, '/cuenta/perfil', const CustomerProfilePage());
      expect(tester.takeException(), isNull);
      expect(find.text('PERFIL Y SEGURIDAD'), findsOneWidget);
      expect(find.text('Usuario'), findsNothing);
      expect(find.text('Agregar'), findsWidgets);
      expect(find.text('Contraseña'), findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar cambios'), findsOneWidget);
      final name = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Nombre completo'),
          matching: find.byType(TextField),
        ),
      );
      expect(name.controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('taller a $width px: en el taller, historial y ficha',
        (tester) async {
      await _pumpPage(tester, width, '/cuenta/servicios',
          const CustomerServiceHistoryPage());
      expect(tester.takeException(), isNull);
      expect(find.text('EN EL TALLER'), findsOneWidget);
      expect(find.text('HISTORIAL'), findsOneWidget);
      expect(find.text('Todas'), findsOneWidget);
      expect(find.text('Espera tu aprobación'), findsOneWidget);
      expect(find.text('Entregada'), findsOneWidget);
      expect(find.textContaining('ESPERANDO_'), findsNothing);
      expect(
        find.textContaining('Cambio de maneta izquierda · Diagnóstico'),
        findsOneWidget,
      );

      // La primera coincidencia es el filtro por bici; la última, la fila.
      await tester.tap(find.text('Oxford Cyclotour').last);
      await tester.pumpAndSettle();
      expect(find.text('LO QUE PEDISTE'), findsOneWidget);
      expect(
        // En teléfono también está en la fila, detrás de la hoja.
        find.text('Enrayado rueda delantera · Mantención maza trasera'),
        findsWidgets,
      );
      expect(find.text('Servicio PG-00574'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bicicletas a $width px: tipo, color y aro', (tester) async {
      await _pumpPage(
          tester, width, '/cuenta/bicicletas', const CustomerBikesPage());
      expect(tester.takeException(), isNull);
      expect(find.text('Trek Marlin 7'), findsOneWidget);
      expect(
          find.textContaining('MTB hardtail · Negra · aro 29'), findsOneWidget);
      expect(find.textContaining('mountain'), findsNothing);

      await tester.tap(find.text('Trek Marlin 7'));
      await tester.pumpAndSettle();
      expect(find.text('Ver sus trabajos de taller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat abierto a $width px: recibe un alto acotado',
        (tester) async {
      // Antes el chat adivinaba «alto de pantalla − 200» porque el portal lo
      // metía en un scroll; ahora ocupa exactamente lo que queda.
      BoxConstraints? received;
      await _pumpPage(
        tester,
        width,
        '/cuenta/chats/c-1',
        CustomerPortalLayout(
          title: 'Consulta',
          backPath: '/cuenta/chats',
          enableContentScrolling: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              received = constraints;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(received!.hasBoundedHeight, isTrue);
      expect(received!.maxHeight, greaterThan(600));
      expect(find.text('Volver'), findsOneWidget);
    });

    testWidgets('sin sesión a $width px: la puerta del portal', (tester) async {
      await _pumpPage(
        tester,
        width,
        '/cuenta',
        const CustomerPortalLayout(title: 'Resumen', child: SizedBox()),
        account: _FakeAccount(authenticated: false),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ENTRA A TU CUENTA'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  double width,
  String path,
  Widget page, {
  CustomerAccountService? account,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final service = account ?? _FakeAccount();
  addTearDown(service.dispose);
  final router = GoRouter(
    initialLocation: path,
    overridePlatformDefaultLocation: true,
    routes: [
      GoRoute(path: path, builder: (_, __) => Scaffold(body: page)),
    ],
  );
  addTearDown(router.dispose);
  final theme = WebsiteThemeBuilder.build(
    base: PublicStoreTheme.theme,
    resolved: WebsiteResolvedTheme.resolve((key, fallback) => fallback),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<CustomerAccountService>.value(
      value: service,
      child: MaterialApp.router(theme: theme, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
