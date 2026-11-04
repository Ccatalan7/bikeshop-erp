import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/modules/accounting/models/expense.dart';
import 'package:vinabike_erp/modules/accounting/models/expense_line.dart';
import 'package:vinabike_erp/modules/accounting/models/expense_payment.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_credit_note.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_payment.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_brand.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/modules/purchases/pages/supplier_detail_page.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_reveal_controller.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_service.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_relationship_service.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_movement_peek.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  group('Contactos', _contactsTests);
  group('Marcas', _brandsTests);
  group('Movimientos', _movementsTests);
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  const partyId = '30000000-0000-0000-0000-000000000003';

  Future<void> pumpDetail(
    WidgetTester tester, {
    required SupplierDetailDataSource source,
    SupplierCredentialRevealController? revealController,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: SupplierDetailPage(
          supplierId: supplierId,
          dataSource: source,
          credentialRevealController: revealController,
          includeWorkspaceShell: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
      'status is secret-free until exact explicit reveal, hide and leave',
      (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final profileService = _MutableProfileService(
      _currentUserProfile(tenantId),
    );
    final credentialGateway = _TrackingCredentialGateway(
      response: const {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'credential_kind': 'portal_password',
        'credential_key': 'admin',
        'engagement_id': '40000000-0000-0000-0000-000000000004',
        'origin_url': 'https://admin.correo.ejemplo.cl',
        'label': 'Consola de administración',
        'username': 'taller@',
        'updated_at': '2026-08-08T00:00:00.000Z',
        'secret': 'clave-auditada',
      },
    );
    final credentialService = SupplierCredentialService(
      profileService: profileService,
      gateway: credentialGateway,
      currentAuthUserId: () => 'user-a',
    );
    final revealController = SupplierCredentialRevealController(
      credentialService: credentialService,
      profileService: profileService,
    );
    addTearDown(revealController.dispose);
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Suite de correo',
        hasCredential: true,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      credentialStatus: SupplierCredentialStatus(
        tenantId: tenantId,
        supplierId: supplierId,
        hasPortalCredential: true,
        credentials: [
          SupplierCredentialMetadata(
            tenantId: tenantId,
            supplierId: supplierId,
            kind: SupplierCredentialKind.portalPassword,
            credentialKey: 'admin',
            engagementId: '40000000-0000-0000-0000-000000000004',
            originUrl: 'https://admin.correo.ejemplo.cl',
            label: 'Consola de administración',
            username: 'taller@',
            updatedAt: DateTime.utc(2026, 8, 8),
          ),
        ],
      ),
      canReadCredentialMetadata: true,
    );

    await pumpDetail(
      tester,
      source: source,
      revealController: revealController,
    );

    expect(find.text('Sección · 1 de 5'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(source.credentialStatusCalls, 1);
    expect(credentialGateway.calls, 0);
    expect(find.text('clave-auditada'), findsNothing);

    final select = find.byKey(
      const ValueKey('supplier-detail-section-select'),
    );
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pumpAndSettle();

    expect(find.text('Accesos'), findsOneWidget);
    expect(find.text('Movimientos'), findsNothing);

    await tester.tap(find.text('Accesos'));
    await tester.pumpAndSettle();

    expect(find.text('https://admin.correo.ejemplo.cl'), findsOneWidget);
    expect(find.text('taller@'), findsOneWidget);
    expect(find.text('Ver la clave'), findsOneWidget);
    expect(credentialGateway.calls, 0);

    await tester.tap(
      find.byKey(
        const ValueKey('supplier-credential-reveal-portal_password-admin'),
      ),
    );
    await tester.pumpAndSettle();

    expect(credentialGateway.calls, 1);
    expect(credentialGateway.lastFunctionName, 'get_supplier_credential_v2');
    expect(credentialGateway.lastParams, {
      'p_tenant_id': tenantId,
      'p_supplier_id': supplierId,
      'p_credential_kind': 'portal_password',
      'p_credential_key': 'admin',
    });
    expect(find.text('clave-auditada'), findsOneWidget);
    expect(find.text('se oculta sola'), findsOneWidget);
    expect(find.text('Copiar'), findsOneWidget);
    expect(find.text('Ocultar'), findsOneWidget);
    expect(
      find.text('Queda registrado quién lo vio y cuándo.'),
      findsOneWidget,
    );

    final copyButton = find.byKey(
      const ValueKey('supplier-credential-copy-portal_password-admin'),
    );
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pump();
    expect(copiedText, 'clave-auditada');

    final hideButton = find.byKey(
      const ValueKey('supplier-credential-hide-portal_password-admin'),
    );
    await tester.ensureVisible(hideButton);
    await tester.tap(hideButton);
    await tester.pump();
    expect(find.text('clave-auditada'), findsNothing);
    expect(find.text('Ver la clave'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('supplier-credential-reveal-portal_password-admin'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('clave-auditada'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('supplier-detail-section-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resumen').last);
    await tester.pumpAndSettle();
    expect(revealController.revealedSecret, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(revealController.revealedSecret, isNull);
  });

  testWidgets(
    'classification reads as one operational relationship, not three axes',
    (tester) async {
      final source = _FakeSupplierDetailDataSource(
        profile: _profile(
          tenantId: tenantId,
          supplierId: supplierId,
          partyId: partyId,
          name: 'Servicio digital',
          hasCredential: false,
          accountingPolicyStatus: 'not_applicable',
          recognizedDocumentCount: 0,
          freeEngagement: true,
        ),
        canReadCredentialMetadata: false,
      );

      await pumpDetail(tester, source: source);
      final sectionSelect =
          find.byKey(const ValueKey('supplier-detail-section-select'));
      await tester.tap(sectionSelect);
      await tester.pumpAndSettle();
      // «Para qué lo usamos» vive dentro de Datos desde el rediseño.
      await tester.tap(find.text('Datos').last);
      await tester.pumpAndSettle();

      expect(find.text('Para qué lo usamos'), findsWidgets);
      // En la cabecera del registro y en el panel de clasificación.
      expect(find.text('Servicios digitales'), findsWidgets);
      expect(find.text('Qué puede hacer'), findsNothing);
      expect(find.text('Etiquetas'), findsNothing);
    },
  );

  testWidgets(
      'credential permission denial loads no metadata and offers no reveal',
      (tester) async {
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Suite sin permiso',
        hasCredential: true,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      canReadCredentialMetadata: false,
    );

    await pumpDetail(tester, source: source);

    expect(source.credentialStatusCalls, 0);
    await tester.tap(
      find.byKey(const ValueKey('supplier-detail-section-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accesos'));
    await tester.pumpAndSettle();

    expect(find.text('No tienes permiso para ver los accesos'), findsOneWidget);
    expect(find.text('Ver la clave'), findsNothing);
    expect(find.text('Copiar'), findsNothing);
  });

  testWidgets('API-only credential remains visible without a portal password',
      (tester) async {
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Integración API',
        hasCredential: false,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      credentialStatus: SupplierCredentialStatus(
        tenantId: tenantId,
        supplierId: supplierId,
        hasPortalCredential: false,
        credentials: [
          SupplierCredentialMetadata(
            tenantId: tenantId,
            supplierId: supplierId,
            kind: SupplierCredentialKind.apiToken,
            credentialKey: 'integration',
            label: 'API de integración',
            username: 'service-account',
            updatedAt: DateTime.utc(2026, 8, 8),
          ),
        ],
      ),
      canReadCredentialMetadata: true,
    );

    await pumpDetail(tester, source: source);

    expect(source.credentialStatusCalls, 1);
    await tester.tap(
      find.byKey(const ValueKey('supplier-detail-section-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accesos'));
    await tester.pumpAndSettle();

    expect(find.text('API de integración'), findsOneWidget);
    expect(find.text('service-account'), findsOneWidget);
  });

  testWidgets(
      'username-only access stays visible and never offers a secret reveal',
      (tester) async {
    final profileService = _MutableProfileService(
      _currentUserProfile(tenantId),
    );
    final credentialGateway = _TrackingCredentialGateway(response: const {});
    final credentialService = SupplierCredentialService(
      profileService: profileService,
      gateway: credentialGateway,
      currentAuthUserId: () => 'user-a',
    );
    final revealController = SupplierCredentialRevealController(
      credentialService: credentialService,
      profileService: profileService,
    );
    addTearDown(revealController.dispose);
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Portal legado',
        hasCredential: false,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      credentialStatus: SupplierCredentialStatus(
        tenantId: tenantId,
        supplierId: supplierId,
        hasPortalCredential: false,
        credentials: [
          SupplierCredentialMetadata(
            tenantId: tenantId,
            supplierId: supplierId,
            kind: SupplierCredentialKind.portalPassword,
            credentialKey: 'admin',
            originUrl: 'https://admin.correo.ejemplo.cl',
            label: 'Cuenta administrativa',
            username: 'cuenta-heredada',
            updatedAt: DateTime.utc(2026, 8, 8),
            secretAvailable: false,
          ),
        ],
      ),
      canReadCredentialMetadata: true,
    );

    await pumpDetail(
      tester,
      source: source,
      revealController: revealController,
    );

    expect(
      find.text(
        'Estos accesos conservan la cuenta, pero no tienen una clave guardada.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('supplier-detail-section-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accesos'));
    await tester.pumpAndSettle();

    expect(find.text('Cuenta administrativa'), findsOneWidget);
    expect(find.text('cuenta-heredada'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'supplier-credential-no-secret-portal_password-admin',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Ver la clave'), findsNothing);
    expect(find.text('Origen HTTPS exacto'), findsNothing);
    expect(credentialGateway.calls, 0);
  });

  testWidgets(
      'stale credential metadata fails closed after a concurrent rebind',
      (tester) async {
    final profileService = _MutableProfileService(
      _currentUserProfile(tenantId),
    );
    final credentialGateway = _TrackingCredentialGateway(
      response: const {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'credential_kind': 'portal_password',
        'credential_key': 'admin',
        'engagement_id': '90000000-0000-0000-0000-000000000009',
        'origin_url': 'https://admin.correo.ejemplo.cl',
        'label': 'Consola de administración',
        'username': 'taller@',
        'updated_at': '2026-08-09T00:00:00.000Z',
        'secret': 'clave-rotada-no-visible',
      },
    );
    final credentialService = SupplierCredentialService(
      profileService: profileService,
      gateway: credentialGateway,
      currentAuthUserId: () => 'user-a',
    );
    final revealController = SupplierCredentialRevealController(
      credentialService: credentialService,
      profileService: profileService,
    );
    addTearDown(revealController.dispose);
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Suite con rotación concurrente',
        hasCredential: true,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      credentialStatus: SupplierCredentialStatus(
        tenantId: tenantId,
        supplierId: supplierId,
        hasPortalCredential: true,
        credentials: [
          SupplierCredentialMetadata(
            tenantId: tenantId,
            supplierId: supplierId,
            kind: SupplierCredentialKind.portalPassword,
            credentialKey: 'admin',
            engagementId: '40000000-0000-0000-0000-000000000004',
            originUrl: 'https://admin.correo.ejemplo.cl',
            label: 'Consola de administración',
            username: 'taller@',
            updatedAt: DateTime.utc(2026, 8, 8),
          ),
        ],
      ),
      canReadCredentialMetadata: true,
    );

    await pumpDetail(
      tester,
      source: source,
      revealController: revealController,
    );
    await tester.tap(
      find.byKey(const ValueKey('supplier-detail-section-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accesos'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('supplier-credential-reveal-portal_password-admin'),
      ),
    );
    await tester.pumpAndSettle();

    expect(credentialGateway.calls, 1);
    expect(find.text('clave-rotada-no-visible'), findsNothing);
    expect(revealController.revealedSecret, isNull);
    expect(
      find.text(
        'Este acceso cambió mientras lo abrías. Recarga antes de volver a intentarlo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Suite con rotación concurrente'), findsOneWidget);
    expect(find.text('Ver la clave'), findsOneWidget);
  });

  testWidgets(
      'recognized activity adds Movimientos without combining purchases and expenses',
      (tester) async {
    final summaries = [
      SupplierEconomicSummaryReadModel.fromJson(const {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'currency_code': 'CLP',
        'purchase_document_count': 1,
        'purchase_payment_count': 1,
        'purchase_gross_amount': 120000,
        'purchase_paid_amount': 100000,
        'purchase_balance_amount': 20000,
        'expense_document_count': 1,
        'expense_payment_count': 0,
        'expense_gross_amount': 15000,
        'expense_paid_amount': 0,
        'expense_balance_amount': 15000,
        'total_document_count': 2,
        'payment_count': 1,
        'traced_document_count': 2,
        'untraced_document_count': 0,
        'unclassified_line_count': 0,
        'payment_state_anomaly_count': 0,
        'expense_payment_ledger_gap_document_count': 0,
        'excluded_lifecycle_document_count': 0,
        'provenance_status': 'complete',
        'data_quality_status': 'complete',
      }),
    ];
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Repuestos Cordillera',
        hasCredential: false,
        accountingPolicyStatus: 'configured',
        recognizedDocumentCount: 1,
        freeEngagement: false,
      ),
      summaries: summaries,
      timeline: _timeline(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
      ),
      canReadCredentialMetadata: true,
    );

    await pumpDetail(tester, source: source);

    expect(find.text('Sección · 1 de 6'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);

    final select = find.byKey(
      const ValueKey('supplier-detail-section-select'),
    );
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimientos'));
    await tester.pumpAndSettle();

    expect(find.text('Actividad reconocida'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Compras'), findsWidgets);
    expect(find.textContaining('Gastos'), findsWidgets);
    expect(
      find.text('compras y gastos no se suman entre sí'),
      findsOneWidget,
    );
    expect(find.text('Documento de compra'), findsOneWidget);
  });

  testWidgets(
      'desktop summary lays out the metric strip and the rail without exceptions',
      (tester) async {
    final summaries = [
      SupplierEconomicSummaryReadModel.fromJson(const {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'currency_code': 'CLP',
        'purchase_document_count': 8,
        'purchase_payment_count': 8,
        'purchase_gross_amount': 562757,
        'purchase_paid_amount': 562757,
        'purchase_balance_amount': 0,
        'expense_document_count': 0,
        'expense_payment_count': 0,
        'total_document_count': 8,
        'payment_count': 8,
        'traced_document_count': 8,
        'untraced_document_count': 0,
        'unclassified_line_count': 0,
        'payment_state_anomaly_count': 0,
        'expense_payment_ledger_gap_document_count': 0,
        'excluded_lifecycle_document_count': 0,
        'provenance_status': 'complete',
        'data_quality_status': 'complete',
      }),
    ];
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Comercial Ciclo',
        hasCredential: false,
        accountingPolicyStatus: 'configured',
        recognizedDocumentCount: 8,
        freeEngagement: false,
      ),
      summaries: summaries,
      timeline: _timeline(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
      ),
      canReadCredentialMetadata: true,
    )..contacts = [
        SupplierContact(
          id: 'c-victor',
          tenantId: tenantId,
          supplierId: supplierId,
          name: 'Victor',
          role: 'Vendedor',
          phone: '+56934867574',
          isPrimary: true,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ];

    await pumpDetail(tester, source: source, size: const Size(1440, 900));

    // Cabecera: nombre, estado y las dos acciones.
    expect(find.text('Comercial Ciclo'), findsWidgets);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Escribir a Victor'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    // Pestañas T-04 bajo la cabecera, con clave por sección.
    expect(
      find.byKey(const Key('vb-sub-tab-_SupplierDetailSection.movements')),
      findsOneWidget,
    );
    expect(find.text('8 documentos'), findsWidgets);
    // Cifras del resumen, en fila.
    expect(find.text('REGISTRADO'), findsOneWidget);
    expect(find.text(r'$562.757'), findsWidgets);
    expect(find.text('al día'), findsOneWidget);
    expect(find.text('Contacto principal'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // La tabla de movimientos en escritorio.
    await tester.tap(
      find.byKey(const Key('vb-sub-tab-_SupplierDetailSection.movements')),
    );
    await tester.pumpAndSettle();
    expect(find.text('FECHA'), findsOneWidget);
    expect(find.text('FV-100'), findsOneWidget);
    expect(find.text('Documento de compra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back uses ReturnNavigation fallback on a direct detail link',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'Proveedor directo',
        hasCredential: false,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      canReadCredentialMetadata: true,
    );
    final router = GoRouter(
      initialLocation: '/purchases/suppliers/$supplierId',
      routes: [
        GoRoute(
          path: '/purchases/suppliers',
          builder: (_, __) => const Scaffold(body: Text('Directorio')),
        ),
        GoRoute(
          path: '/purchases/suppliers/:id',
          builder: (_, state) => SupplierDetailPage(
            supplierId: state.pathParameters['id']!,
            dataSource: source,
            includeWorkspaceShell: false,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('supplier-detail-back')));
    await tester.pumpAndSettle();

    expect(find.text('Directorio'), findsOneWidget);
  });
}

class _FakeSupplierDetailDataSource implements SupplierDetailDataSource {
  _FakeSupplierDetailDataSource({
    required this.profile,
    this.summaries = const [],
    SupplierEconomicTimelinePage? timeline,
    this.credentialStatus,
    required this.canReadCredentialMetadata,
  }) : timeline = timeline ??
            SupplierEconomicTimelinePage(
              timeline: SupplierEconomicReadModel(
                tenantId: profile.relationship.tenantId,
                supplierId: profile.relationship.id,
              ),
              offset: 0,
              limit: 50,
              hasMore: false,
            );

  final SupplierProfile profile;
  final List<SupplierEconomicSummaryReadModel> summaries;
  final SupplierEconomicTimelinePage timeline;
  final SupplierCredentialStatus? credentialStatus;
  @override
  final bool canReadCredentialMetadata;
  int credentialStatusCalls = 0;

  @override
  SupplierMovementPeekSource? movementPeek;

  @override
  Stream<Object?>? get authAuthorityChanges => null;

  @override
  String get authorityFingerprint => 'test-authority';

  @override
  Listenable? get profileAuthorityChanges => null;

  @override
  Future<SupplierCredentialStatus> getCredentialStatus(
    String supplierId,
  ) async {
    credentialStatusCalls++;
    return credentialStatus!;
  }

  @override
  Future<List<SupplierEconomicSummaryReadModel>> getEconomicSummary(
    String supplierId,
  ) async =>
      summaries;

  @override
  Future<SupplierEconomicTimelinePage> getEconomicTimeline(
    String supplierId,
  ) async =>
      timeline;

  @override
  Future<SupplierProfile?> getProfile(String supplierId) async => profile;

  List<SupplierContact> contacts = const [];
  final List<Object> contactCommands = [];
  String? imageUrl;

  @override
  Future<void> updateImage(String supplierId, String? imageUrl) async {
    this.imageUrl = imageUrl;
  }

  List<SupplierBrand> brands = const [];
  List<SupplierBrandOption> brandCatalog = const [];
  Object? brandsError;
  final List<String> brandCommands = [];
  final Map<String, SupplierBrand> _removedBrands = {};

  List<SupplierBrand> _sortedBrands(Iterable<SupplierBrand> rows) =>
      rows.toList()
        ..sort((a, b) {
          if (a.official != b.official) return a.official ? -1 : 1;
          final byLines = b.purchases.compareTo(a.purchases);
          if (byLines != 0) return byLines;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

  @override
  Future<List<SupplierBrand>> listBrands(String supplierId) async {
    if (brandsError case final error?) throw error;
    return brands;
  }

  @override
  Future<List<SupplierBrand>> saveBrand(
    String supplierId,
    String brandId, {
    bool? official,
  }) async {
    brandCommands.add('save:$brandId:$official');
    final current = brands.where((b) => b.brandId == brandId).firstOrNull ??
        _removedBrands.remove(brandId);
    final name = current?.name ??
        brandCatalog.firstWhere((option) => option.id == brandId).name;
    final saved = SupplierBrand(
      brandId: brandId,
      name: name,
      official: official ?? current?.official ?? false,
      source: current?.source ?? SupplierBrandSource.manual,
      catalogUrl: current?.catalogUrl,
      catalogCheckedOn: current?.catalogCheckedOn,
      addedFromPurchases: current?.addedFromPurchases ?? false,
      products: current?.products ?? 0,
      purchases: current?.purchases ?? 0,
      purchaseLines: current?.purchaseLines ?? 0,
      lastPurchase: current?.lastPurchase,
    );
    brands = _sortedBrands([
      for (final brand in brands)
        if (brand.brandId != brandId) brand,
      saved,
    ]);
    return brands;
  }

  @override
  Future<List<SupplierBrand>> removeBrand(
    String supplierId,
    String brandId,
  ) async {
    brandCommands.add('remove:$brandId');
    for (final brand in brands) {
      if (brand.brandId == brandId) _removedBrands[brandId] = brand;
    }
    brands = [
      for (final brand in brands)
        if (brand.brandId != brandId) brand,
    ];
    return brands;
  }

  @override
  Future<List<SupplierBrandOption>> brandOptions() async => brandCatalog;

  @override
  Future<SupplierBrandOption> createBrand(String name) async {
    brandCommands.add('create:$name');
    final created = SupplierBrandOption(id: 'new-$name', name: name);
    brandCatalog = [...brandCatalog, created];
    return created;
  }

  @override
  Future<List<SupplierContact>> listContacts(String supplierId) async =>
      contacts;

  @override
  Future<SupplierContactCommandResult> saveContact(
    SaveSupplierContactCommand command,
  ) async {
    contactCommands.add(command);
    final saved = SupplierContact(
      id: command.contactId ?? 'contact-${contactCommands.length}',
      tenantId: profile.relationship.tenantId,
      supplierId: command.supplierId,
      name: command.name,
      role: command.role,
      phone: command.phone,
      email: command.email,
      isPrimary: command.isPrimary ?? false,
      updatedAt: DateTime.utc(2026, 9, 3),
    );
    contacts = [
      for (final contact in contacts)
        if (contact.id != saved.id)
          (saved.isPrimary && contact.isPrimary
              ? SupplierContact(
                  id: contact.id,
                  tenantId: contact.tenantId,
                  supplierId: contact.supplierId,
                  name: contact.name,
                  role: contact.role,
                  phone: contact.phone,
                  email: contact.email,
                  isPrimary: false,
                  isActive: contact.isActive,
                  deactivatedAt: contact.deactivatedAt,
                  updatedAt: contact.updatedAt,
                )
              : contact),
      saved,
    ];
    return SupplierContactCommandResult(
      operationId: command.operationId,
      tenantId: profile.relationship.tenantId,
      supplierId: command.supplierId,
      contact: saved,
      idempotentReplay: false,
    );
  }

  @override
  Future<SupplierContactCommandResult> setContactStatus(
    SetSupplierContactStatusCommand command,
  ) async {
    contactCommands.add(command);
    final current = contacts.firstWhere((c) => c.id == command.contactId);
    final saved = SupplierContact(
      id: current.id,
      tenantId: current.tenantId,
      supplierId: current.supplierId,
      name: current.name,
      role: current.role,
      phone: current.phone,
      email: current.email,
      isPrimary: command.isActive && current.isPrimary,
      isActive: command.isActive,
      deactivatedAt: command.isActive ? null : DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3, 1),
    );
    contacts = [
      for (final contact in contacts)
        if (contact.id == saved.id) saved else contact,
    ];
    return SupplierContactCommandResult(
      operationId: command.operationId,
      tenantId: profile.relationship.tenantId,
      supplierId: command.supplierId,
      contact: saved,
      idempotentReplay: false,
    );
  }
}

SupplierProfile _profile({
  required String tenantId,
  required String supplierId,
  required String partyId,
  required String name,
  required bool hasCredential,
  required String accountingPolicyStatus,
  required int recognizedDocumentCount,
  required bool freeEngagement,
  String roleCode = 'digital_platform',
}) {
  const engagementId = '40000000-0000-0000-0000-000000000004';
  return SupplierProfile.fromJson({
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'party_id': partyId,
    'party_kind': 'organization',
    'display_name': name,
    'is_active': true,
    'has_portal_credential': hasCredential,
    'relationship_roles': [
      {
        'id': '50000000-0000-0000-0000-000000000005',
        'definition_id': '60000000-0000-0000-0000-000000000006',
        'code': roleCode,
        'label': freeEngagement ? 'Plataforma digital' : 'Proveedor de bienes',
        'valid_from': '2026-01-01',
        'source': 'manual',
        'metadata': const {},
      },
    ],
    'relationship_capabilities': const [],
    'relationship_tags': const [],
    'active_engagement_count': 1,
    'active_policy_count': accountingPolicyStatus == 'configured' ? 1 : 0,
    'service_relationship_summary':
        freeEngagement ? 'Plan del taller · Sin costo' : 'Cuenta comercial',
    'recognized_document_count': recognizedDocumentCount,
    'validation_issue_count': 0,
    'validation_incidents': const [],
    'data_completeness_status': 'known',
    'classification_status': 'classified',
    'accounting_policy_status': accountingPolicyStatus,
    'engagements': [
      {
        'id': engagementId,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'engagement_kind': freeEngagement ? 'subscription' : 'contract',
        'code': freeEngagement ? 'workshop-plan' : 'trade-account',
        'name': freeEngagement ? 'Plan del taller' : 'Cuenta comercial',
        'status': 'active',
        'starts_on': '2026-01-01',
        'metadata': const {},
        'versions': [
          {
            'id': '70000000-0000-0000-0000-000000000007',
            'tenant_id': tenantId,
            'engagement_id': engagementId,
            'version_number': 1,
            'effective_from': '2026-01-01',
            'billing_cycle': freeEngagement ? 'free' : 'monthly',
            'currency_code': 'CLP',
            'terms': const {},
          },
        ],
      },
    ],
    'accounting': const {
      'policies': [],
      'rules': [],
      'recent_evidence': [],
      'observed_account_ids': [],
    },
  });
}

SupplierEconomicTimelinePage _timeline({
  required String tenantId,
  required String supplierId,
  required String partyId,
}) {
  return SupplierEconomicTimelinePage(
    timeline: SupplierEconomicReadModel(
      tenantId: tenantId,
      supplierId: supplierId,
      activities: [
        SupplierEconomicActivity.fromJson({
          'tenant_id': tenantId,
          'supplier_id': supplierId,
          'party_id': partyId,
          'event_id': '80000000-0000-0000-0000-000000000008',
          'event_type': 'purchase_invoice',
          'event_date': '2026-08-08',
          'document_number': 'FV-100',
          'currency_code': 'CLP',
          'gross_amount': 120000,
          'paid_amount': 100000,
          'balance_amount': 20000,
          'payment_count': 1,
          'is_recognized': true,
          'data_quality_status': 'complete',
          'metadata': const {},
        }),
      ],
    ),
    offset: 0,
    limit: 50,
    hasMore: false,
  );
}

CurrentUserProfile _currentUserProfile(
  String tenantId, {
  bool canManageCredentials = true,
}) {
  return CurrentUserProfile(
    userId: 'user-a',
    email: 'user-a@example.com',
    emailVerified: true,
    displayName: 'User A',
    tenantId: tenantId,
    tenantName: 'Tenant',
    tenantSubdomain: null,
    role: 'owner',
    permissions: {
      'can_manage_supplier_credentials': canManageCredentials,
    },
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}

class _MutableProfileService extends CurrentUserProfileService {
  _MutableProfileService(CurrentUserProfile? current)
      : _current = current,
        super(gateway: _UnusedProfileGateway());

  final CurrentUserProfile? _current;

  @override
  CurrentUserProfile? get profile => _current;
}

class _UnusedProfileGateway implements CurrentUserProfileGateway {
  @override
  Future<Map<String, dynamic>> getMyErpProfile() => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId) =>
      throw UnimplementedError();

  @override
  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) =>
      throw UnimplementedError();
}

class _TrackingCredentialGateway implements SupplierCredentialGateway {
  _TrackingCredentialGateway({required this.response});

  final dynamic response;
  int calls = 0;
  String? lastFunctionName;
  Map<String, dynamic>? lastParams;

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    calls++;
    lastFunctionName = functionName;
    lastParams = Map<String, dynamic>.from(params);
    return response;
  }
}

/// Contactos: las personas del proveedor con una principal. Desactivar
/// conserva a la persona y sus chats; agregar la primera la vuelve principal.
void _contactsTests() {
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  const partyId = '30000000-0000-0000-0000-000000000003';

  SupplierContact contact({
    required String id,
    required String name,
    String? role,
    String? phone,
    bool isPrimary = false,
    String source = 'manual',
  }) =>
      SupplierContact(
        id: id,
        tenantId: tenantId,
        supplierId: supplierId,
        name: name,
        role: role,
        phone: phone,
        isPrimary: isPrimary,
        source: source,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

  Future<void> pumpContacts(
    WidgetTester tester,
    _FakeSupplierDetailDataSource source,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        // Fuera del shell no hay Scaffold: el que pone el snackbar de cada
        // comando lo aporta el harness.
        home: Scaffold(
          body: SupplierDetailPage(
            supplierId: supplierId,
            dataSource: source,
            includeWorkspaceShell: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Contactos').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  _FakeSupplierDetailDataSource source() => _FakeSupplierDetailDataSource(
        profile: _profile(
          tenantId: tenantId,
          supplierId: supplierId,
          partyId: partyId,
          name: 'Comercial Ciclo',
          hasCredential: false,
          accountingPolicyStatus: 'not_applicable',
          recognizedDocumentCount: 0,
          freeEngagement: true,
        ),
        canReadCredentialMetadata: false,
      );

  testWidgets('la lista muestra a la principal y a quien llegó por WhatsApp',
      (tester) async {
    final data = source()
      ..contacts = [
        contact(
          id: 'c-victor',
          name: 'Victor',
          role: 'Vendedor',
          phone: '+56934867574',
          isPrimary: true,
        ),
        contact(
          id: 'c-fabiola',
          name: 'Fabiola',
          phone: '+56988155152',
          source: 'whatsapp_backfill',
        ),
      ];
    await pumpContacts(tester, data);

    expect(find.text('Victor'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget);
    expect(find.text('Vendedor · +56934867574'), findsOneWidget);
    expect(find.text('Fabiola'), findsOneWidget);
    expect(find.text('Conocido por un chat de WhatsApp'), findsOneWidget);
    // El vendedor ya no se repite en Identidad: vive aquí.
    expect(find.text('WhatsApp del vendedor'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desactivar conserva a la persona y lo dice', (tester) async {
    final data = source()
      ..contacts = [
        contact(id: 'c-victor', name: 'Victor', isPrimary: true),
        contact(id: 'c-fabiola', name: 'Fabiola', phone: '+56988155152'),
      ];
    await pumpContacts(tester, data);

    await tester.tap(
      find.byKey(const ValueKey('supplier-contact-menu-c-fabiola')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();

    final command = data.contactCommands.single;
    expect(command, isA<SetSupplierContactStatusCommand>());
    expect((command as SetSupplierContactStatusCommand).isActive, isFalse);
    expect(command.contactId, 'c-fabiola');
    expect(find.text('Fabiola'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
    expect(find.textContaining('sus chats se conservan'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la primera persona que se agrega es la principal',
      (tester) async {
    final data = source();
    await pumpContacts(tester, data);

    expect(find.text('Sin contactos todavía'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('supplier-contacts-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supplier-contact-name')),
      'Macarena',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supplier-contact-phone')),
      '+56 22 510 4634',
    );
    await tester.tap(find.byKey(const ValueKey('supplier-contact-save')));
    await tester.pumpAndSettle();

    final command = data.contactCommands.single as SaveSupplierContactCommand;
    expect(command.name, 'Macarena');
    expect(command.phone, '+56 22 510 4634');
    expect(command.isPrimary, isTrue);
    expect(command.contactId, isNull);
    expect(find.text('Macarena'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un número corto no se guarda', (tester) async {
    final data = source();
    await pumpContacts(tester, data);

    await tester.tap(find.byKey(const ValueKey('supplier-contacts-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supplier-contact-name')),
      'Isabel',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supplier-contact-phone')),
      '1234',
    );
    await tester.tap(find.byKey(const ValueKey('supplier-contact-save')));
    await tester.pumpAndSettle();

    expect(find.text('Un número necesita al menos 8 dígitos'), findsOneWidget);
    expect(data.contactCommands, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

void _brandsTests() {
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  const partyId = '30000000-0000-0000-0000-000000000003';

  _FakeSupplierDetailDataSource goodsVendor() => _FakeSupplierDetailDataSource(
        profile: _profile(
          tenantId: tenantId,
          supplierId: supplierId,
          partyId: partyId,
          name: 'Andes Industrial',
          hasCredential: false,
          accountingPolicyStatus: 'not_applicable',
          recognizedDocumentCount: 0,
          freeEngagement: false,
          roleCode: 'goods_vendor',
        ),
        canReadCredentialMetadata: false,
      )
        ..brands = [
          SupplierBrand(
            brandId: 'b-shimano',
            name: 'Shimano',
            official: true,
            source: SupplierBrandSource.records,
            catalogUrl: 'https://www.andesindustrial.cl/',
            catalogCheckedOn: DateTime(2026, 11, 3),
            addedFromPurchases: true,
            products: 124,
            purchases: 6,
            purchaseLines: 6,
            lastPurchase: DateTime(2026, 10, 2),
          ),
          SupplierBrand(
            brandId: 'b-kmc',
            name: 'KMC',
            source: SupplierBrandSource.records,
            addedFromPurchases: true,
            products: 30,
            purchases: 4,
            purchaseLines: 11,
            lastPurchase: DateTime(2026, 10, 12),
          ),
          const SupplierBrand(
            brandId: 'b-arisun',
            name: 'Arisun',
            source: SupplierBrandSource.records,
            products: 26,
          ),
        ]
        ..brandCatalog = const [
          SupplierBrandOption(id: 'b-maxxis', name: 'Maxxis'),
          SupplierBrandOption(id: 'b-schwalbe', name: 'Schwalbe'),
          SupplierBrandOption(id: 'b-kmc', name: 'KMC'),
        ];

  Future<void> pumpBrands(
    WidgetTester tester,
    _FakeSupplierDetailDataSource source, {
    Size size = const Size(1100, 900),
    Brightness brightness = Brightness.light,
    bool openTab = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: brightness,
        ),
        home: Scaffold(
          body: SupplierDetailPage(
            supplierId: supplierId,
            dataSource: source,
            includeWorkspaceShell: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    if (openTab) {
      await tester.tap(find.byKey(const ValueKey('supplier-summary-brands')));
      await tester.pumpAndSettle();
    }
  }

  // The select's column also holds its helper line: tap the field itself.
  Finder addBrandField() => find.descendant(
        of: find.byKey(const ValueKey('supplier-brand-add')),
        matching: find.text('Agregar marca'),
      );

  testWidgets(
      'the Summary lists the brands, the official one first, and leads to '
      'the Brands tab', (tester) async {
    await pumpBrands(tester, goodsVendor(), openTab: false);

    expect(find.text('Shimano'), findsOneWidget);
    expect(find.bySemanticsLabel('Shimano, representante oficial'),
        findsOneWidget);
    expect(find.text('KMC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('supplier-summary-brands')));
    await tester.pumpAndSettle();
    expect(find.text('Marcas que trae'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'on desktop the Brands tab is one table per group: the official one, '
      'what we buy from them and what else they bring', (tester) async {
    await pumpBrands(tester, goodsVendor());

    expect(find.text('3 marcas'), findsOneWidget);
    // The group says it; its row does not repeat it in a badge.
    expect(find.text('Representante oficial'), findsOneWidget);
    expect(find.text('Le compramos'), findsOneWidget);
    expect(find.text('También trae'), findsOneWidget);
    expect(find.text('1 marca · sin compras en el ERP'), findsOneWidget);
    expect(find.text('COMPRAS'), findsNWidgets(3));
    expect(find.text('ÚLTIMA COMPRA'), findsNWidgets(3));
    // Purchases are documents (4), not invoice lines (11).
    expect(find.text('4'), findsOneWidget);
    expect(find.text('12/10/2026'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(
      find.text('De nuestras compras · Vista en andesindustrial.cl el '
          '03/11/2026'),
      findsOneWidget,
    );
    expect(
        find.text('De productos que lo tienen como proveedor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone each brand is a row that reads in words',
      (tester) async {
    await pumpBrands(
      tester,
      goodsVendor(),
      size: const Size(390, 844),
      openTab: false,
    );
    await tester.tap(find.byKey(const ValueKey('supplier-summary-brands')));
    await tester.pumpAndSettle();

    // Two short lines that do not break: what we buy, then the catalog and
    // where it was seen (without the date, which the desktop table keeps).
    expect(find.text('4 compras · última 12/10/2026'), findsOneWidget);
    expect(find.text('30 en el catálogo'), findsOneWidget);
    expect(find.text('124 en el catálogo · Vista en andesindustrial.cl'),
        findsOneWidget);
    expect(
      find.text(
          '26 en el catálogo · De productos que lo tienen como proveedor'),
      findsOneWidget,
    );
    expect(find.text('COMPRAS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long group shows the first ten and the rest on request',
      (tester) async {
    final data = goodsVendor()
      ..brands = [
        for (var index = 1; index <= 15; index++)
          SupplierBrand(
            brandId: 'b-$index',
            name: 'Marca ${index.toString().padLeft(2, '0')}',
            source: SupplierBrandSource.records,
            products: 20 - index,
          ),
      ];
    await pumpBrands(tester, data);

    expect(find.text('Marca 10'), findsOneWidget);
    expect(find.text('Marca 11'), findsNothing);
    await tester.ensureVisible(find.text('Ver las 5 restantes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver las 5 restantes'));
    await tester.pumpAndSettle();
    expect(find.text('Ver las 5 restantes'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Marca 15'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Marca 15'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a brand from the catalog is added from the tab', (tester) async {
    final data = goodsVendor();
    await pumpBrands(tester, data);

    await tester.tap(addBrandField());
    await tester.pumpAndSettle();
    expect(find.text('KMC'), findsOneWidget,
        reason: 'a brand the supplier already has is not offered again');
    // The test host is Android: the focused search field draws its caret
    // handle over the first result, so the brand is picked by typing.
    await tester.enterText(find.byType(TextField).last, 'schw');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(data.brandCommands, ['save:b-schwalbe:null']);
    expect(find.text('Schwalbe'), findsOneWidget);
    expect(find.text('Schwalbe agregada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a brand the catalog does not have is created and added',
      (tester) async {
    final data = goodsVendor();
    await pumpBrands(tester, data);

    await tester.tap(addBrandField());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Galfer');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear la marca «Galfer»'));
    await tester.pumpAndSettle();

    expect(data.brandCommands, ['create:Galfer', 'save:new-Galfer:null']);
    expect(find.text('Galfer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'removing a brand can be undone and it comes back as it was, and a '
      'supplier is marked as the official one from its menu', (tester) async {
    final data = goodsVendor();
    await pumpBrands(tester, data);

    await tester
        .tap(find.byKey(const ValueKey('supplier-brand-menu-b-shimano')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar de Andes Industrial'));
    await tester.pumpAndSettle();
    expect(find.text('Shimano quitada'), findsOneWidget);
    expect(find.text('Representante oficial'), findsNothing);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(data.brandCommands, ['remove:b-shimano', 'save:b-shimano:true']);
    expect(
        find.text('De nuestras compras · Vista en andesindustrial.cl el '
            '03/11/2026'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('supplier-brand-menu-b-kmc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar como representante oficial'));
    await tester.pumpAndSettle();
    expect(data.brandCommands.last, 'save:b-kmc:true');
    expect(
      find.text('Andes Industrial figura como representante oficial de KMC'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a supplier that is not a goods vendor and has no brands has '
      'no Brands tab', (tester) async {
    final data = _FakeSupplierDetailDataSource(
      profile: _profile(
        tenantId: tenantId,
        supplierId: supplierId,
        partyId: partyId,
        name: 'NIC Chile',
        hasCredential: false,
        accountingPolicyStatus: 'not_applicable',
        recognizedDocumentCount: 0,
        freeEngagement: true,
      ),
      canReadCredentialMetadata: false,
    );
    await pumpBrands(tester, data, openTab: false);

    expect(
      find.byKey(const Key('vb-sub-tab-_SupplierDetailSection.brands')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('supplier-summary-brands')), findsNothing);
  });

  testWidgets('when the brands cannot be read the profile still opens',
      (tester) async {
    final data = goodsVendor()..brandsError = StateError('sin conexión');
    await pumpBrands(tester, data);

    expect(find.text('No pudimos cargar las marcas'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1288, 900), Size(390, 844)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'the Brands tab fits at ${size.width.toInt()} ${brightness.name}',
          (tester) async {
        await pumpBrands(
          tester,
          goodsVendor(),
          size: size,
          brightness: brightness,
          openTab: size.width > 900,
        );
        if (size.width <= 900) {
          await tester
              .tap(find.byKey(const ValueKey('supplier-summary-brands')));
          await tester.pumpAndSettle();
        }
        expect(find.text('Marcas que trae'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

/// Las lecturas de un movimiento abierto encima de la ficha, con lo que trae
/// TeknoBike: una factura con su pago, la nota de crédito que la corrige y
/// un gasto con su pago.
class _FakeMovementPeekSource implements SupplierMovementPeekSource {
  _FakeMovementPeekSource({
    this.documents = const {},
    this.documentPayments = const {},
    this.creditNotes = const {},
    this.creditNoteLines = const {},
    this.expenses = const {},
    this.expensePaymentsByExpense = const {},
    this.methods = const {},
    this.images = const {},
  });

  final Map<String, PurchaseInvoice> documents;
  final Map<String, List<PurchasePayment>> documentPayments;
  final Map<String, PurchaseCreditNoteRecord> creditNotes;
  final Map<String, List<PurchaseCreditNoteLineRecord>> creditNoteLines;
  final Map<String, Expense> expenses;
  final Map<String, List<ExpensePayment>> expensePaymentsByExpense;
  final Map<String, String> methods;
  final Map<String, String> images;
  final Map<String, int> documentReads = {};

  @override
  Future<PurchaseInvoice?> purchaseDocument(String id) async {
    documentReads[id] = (documentReads[id] ?? 0) + 1;
    return documents[id];
  }

  @override
  Future<List<PurchasePayment>> purchaseDocumentPayments(
    String invoiceId,
  ) async =>
      documentPayments[invoiceId] ?? const [];

  @override
  Future<PurchasePayment?> purchasePayment(String id) async {
    for (final payments in documentPayments.values) {
      for (final payment in payments) {
        if (payment.id == id) return payment;
      }
    }
    return null;
  }

  @override
  Future<PurchaseCreditNoteRecord?> purchaseCreditNote({
    required String invoiceId,
    required String noteId,
  }) async =>
      creditNotes[noteId];

  @override
  Future<List<PurchaseCreditNoteLineRecord>> purchaseCreditNoteLines(
    String noteId,
  ) async =>
      creditNoteLines[noteId] ?? const [];

  @override
  Future<Expense?> expense(String id) async => expenses[id];

  @override
  Future<List<ExpensePayment>> expensePayments(String expenseId) async =>
      expensePaymentsByExpense[expenseId] ?? const [];

  @override
  Future<String?> paymentMethodName(String? methodId) async =>
      methods[methodId];

  @override
  Future<Map<String, String>> productImages(
    Iterable<String> productIds,
  ) async =>
      {
        for (final id in productIds)
          if (images[id] case final url?) id: url,
      };
}

void _movementsTests() {
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  const partyId = '30000000-0000-0000-0000-000000000003';
  const invoiceId = '81000000-0000-0000-0000-000000000001';
  const paymentId = '82000000-0000-0000-0000-000000000002';
  const creditNoteId = '83000000-0000-0000-0000-000000000003';
  const expenseId = '84000000-0000-0000-0000-000000000004';
  const expensePaymentId = '85000000-0000-0000-0000-000000000005';

  SupplierEconomicActivity event(
    String id,
    String type,
    String date, {
    required String source,
    String? number,
    double gross = 0,
    double paid = 0,
  }) =>
      SupplierEconomicActivity.fromJson({
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'event_id': id,
        'event_type': type,
        'event_date': date,
        'document_number': number,
        'currency_code': 'CLP',
        'gross_amount': gross,
        'paid_amount': paid,
        'balance_amount': gross - paid,
        'payment_count': paid > 0 ? 1 : 0,
        'is_recognized': true,
        'data_quality_status': 'complete',
        'source_document_id': source,
        'metadata': const {},
      });

  _FakeMovementPeekSource teknoBike() => _FakeMovementPeekSource(
        documents: {
          invoiceId: PurchaseInvoice.fromJson({
            'id': invoiceId,
            'tenant_id': tenantId,
            'invoice_number': 'FC-00031',
            'supplier_id': supplierId,
            'supplier_name': 'TeknoBike',
            'date': '2026-10-27',
            'due_date': '2026-11-26',
            'status': 'paid',
            'subtotal': 118109,
            'tax': 22440,
            'total': 140549,
            'paid_amount': 140549,
            'balance': 0,
            'supplier_invoice_number': '145172',
            'source_document_kind_label': 'Factura electrónica',
            'created_at': '2026-10-27T12:00:00Z',
            'updated_at': '2026-10-27T12:00:00Z',
            'items': [
              {
                'product_id': 'p-chain',
                'product_name': 'Cadena KMC X11 126L',
                'product_sku': '4715575895086',
                'quantity': 2,
                'unit_cost': 22990,
                'discount': 0,
                'iva_rate': 19,
                'created_at': '2026-10-27T12:00:00Z',
              },
              {
                'product_id': 'p-tire',
                'product_name': 'Neumático Maxxis Rekon Race 29x2.25',
                'quantity': 4,
                'unit_cost': 18032,
                'discount': 0,
                'iva_rate': 19,
                'created_at': '2026-10-27T12:00:00Z',
              },
            ],
          }),
        },
        documentPayments: {
          invoiceId: [
            PurchasePayment.fromJson({
              'id': paymentId,
              'tenant_id': tenantId,
              'invoice_id': invoiceId,
              'payment_method_id': 'm-transfer',
              'amount': 140549,
              'date': '2026-10-08',
              'reference': '5521',
              'created_at': '2026-10-08T12:00:00Z',
              'updated_at': '2026-10-08T12:00:00Z',
            }),
          ],
        },
        creditNotes: {
          creditNoteId: PurchaseCreditNoteRecord(
            id: creditNoteId,
            number: 'NCC-00001',
            status: 'posted',
            officialStatus: 'internal',
            issueDate: DateTime(2026, 10, 27),
            reason: 'Una cadena llegó con un eslabón abierto',
            totalAmount: 6427,
            remainingRefundable: 6427,
            invoiceCreditBalance: 6427,
          ),
        },
        creditNoteLines: {
          creditNoteId: const [
            PurchaseCreditNoteLineRecord(
              id: 'cnl-1',
              productName: 'Cadena KMC X11 126L',
              quantity: 1,
              netAmount: 5401,
              taxAmount: 1026,
              totalAmount: 6427,
              disposition: 'returned',
            ),
          ],
        },
        expenses: {
          expenseId: Expense(
            id: expenseId,
            tenantId: tenantId,
            expenseNumber: 'GA-00012',
            documentType: ExpenseDocumentType.receipt,
            documentNumber: 'B-9981',
            issueDate: DateTime(2026, 9, 30),
            postingStatus: ExpensePostingStatus.posted,
            paymentStatus: ExpensePaymentStatus.paid,
            subtotal: 12605,
            taxAmount: 2395,
            totalAmount: 15000,
            amountPaid: 15000,
            lines: [
              ExpenseLine(
                accountId: 'acc-web',
                accountCode: '6101',
                accountName: 'Servicios web',
                description: 'Despacho a regiones',
                unitPrice: 12605,
                taxAmount: 2395,
                total: 15000,
              ),
            ],
          ),
        },
        expensePaymentsByExpense: {
          expenseId: [
            ExpensePayment(
              id: expensePaymentId,
              expenseId: expenseId,
              paymentMethodId: 'm-card',
              amount: 15000,
              paymentDate: DateTime(2026, 9, 30),
              reference: 'TX-77',
            ),
          ],
        },
        methods: const {
          'm-transfer': 'Transferencia',
          'm-card': 'Tarjeta de débito',
        },
        images: const {'p-chain': 'https://example.com/cadena.jpg'},
      );

  _FakeSupplierDetailDataSource data({SupplierMovementPeekSource? peek}) =>
      _FakeSupplierDetailDataSource(
        profile: _profile(
          tenantId: tenantId,
          supplierId: supplierId,
          partyId: partyId,
          name: 'TeknoBike',
          hasCredential: false,
          accountingPolicyStatus: 'configured',
          recognizedDocumentCount: 2,
          freeEngagement: false,
        ),
        summaries: [
          SupplierEconomicSummaryReadModel.fromJson(const {
            'tenant_id': tenantId,
            'supplier_id': supplierId,
            'party_id': partyId,
            'currency_code': 'CLP',
            'purchase_document_count': 1,
            'purchase_payment_count': 1,
            'purchase_gross_amount': 140549,
            'purchase_paid_amount': 140549,
            'purchase_balance_amount': 0,
            'expense_document_count': 1,
            'expense_payment_count': 1,
            'expense_gross_amount': 15000,
            'expense_paid_amount': 15000,
            'expense_balance_amount': 0,
            'total_document_count': 2,
            'payment_count': 2,
            'traced_document_count': 2,
            'untraced_document_count': 0,
            'unclassified_line_count': 0,
            'payment_state_anomaly_count': 0,
            'expense_payment_ledger_gap_document_count': 0,
            'excluded_lifecycle_document_count': 0,
            'provenance_status': 'complete',
            'data_quality_status': 'complete',
          }),
        ],
        timeline: SupplierEconomicTimelinePage(
          timeline: SupplierEconomicReadModel(
            tenantId: tenantId,
            supplierId: supplierId,
            activities: [
              event(
                creditNoteId,
                'purchase_credit_note',
                '2026-10-28',
                source: invoiceId,
                number: 'NCC-00001',
                gross: -6427,
              ),
              event(
                invoiceId,
                'purchase_invoice',
                '2026-10-27',
                source: invoiceId,
                number: '145172',
                gross: 140549,
                paid: 140549,
              ),
              event(
                paymentId,
                'purchase_payment',
                '2026-10-08',
                source: invoiceId,
                number: '145172',
                paid: 140549,
              ),
              event(
                expenseId,
                'expense',
                '2026-09-30',
                source: expenseId,
                number: 'B-9981',
                gross: 15000,
                paid: 15000,
              ),
              event(
                expensePaymentId,
                'expense_payment',
                '2026-09-30',
                source: expenseId,
                number: 'B-9981',
                paid: 15000,
              ),
            ],
          ),
          offset: 0,
          limit: 50,
          hasMore: false,
        ),
        canReadCredentialMetadata: false,
      )..movementPeek = peek;

  Future<GoRouter> pumpMovements(
    WidgetTester tester,
    _FakeSupplierDetailDataSource source, {
    Size size = const Size(1288, 900),
    Brightness brightness = Brightness.light,
    bool openTab = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page(String text) => Scaffold(body: Center(child: Text(text)));
    final router = GoRouter(
      initialLocation: '/purchases/suppliers/$supplierId',
      routes: [
        GoRoute(
          path: '/purchases/suppliers/:id',
          builder: (_, __) => Scaffold(
            body: SupplierDetailPage(
              supplierId: supplierId,
              dataSource: source,
              includeWorkspaceShell: false,
            ),
          ),
        ),
        GoRoute(
          path: '/purchases/payments/:id',
          builder: (_, state) =>
              page('Página del pago ${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/purchases/:id',
          builder: (_, state) =>
              page('Página del documento ${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/accounting/expenses/:id',
          builder: (_, state) =>
              page('Página del gasto ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: brightness,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    if (openTab) {
      await tester.tap(
        find.byKey(
          const ValueKey('vb-sub-tab-_SupplierDetailSection.movements'),
        ),
      );
      await tester.pumpAndSettle();
    }
    return router;
  }

  Future<void> openRow(WidgetTester tester, String id) async {
    final row = find.byKey(ValueKey('supplier-activity-$id'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  Finder inPeek(Finder finder) => find.descendant(
        of: find.byKey(const ValueKey('supplier-movement-peek')),
        matching: finder,
      );

  testWidgets(
      'a purchase opens on top of the profile with its lines, and its '
      'payment opens in the same view and comes back', (tester) async {
    final peek = teknoBike();
    await pumpMovements(tester, data(peek: peek));

    await openRow(tester, invoiceId);
    expect(
        find.byKey(const ValueKey('supplier-movement-peek')), findsOneWidget);
    expect(inPeek(find.text('DOCUMENTO DE COMPRA')), findsOneWidget);
    expect(inPeek(find.text('145172')), findsOneWidget);
    expect(
      inPeek(find.text('27/10/2026 · vence 26/11/2026 · FC-00031 · '
          'Factura electrónica')),
      findsOneWidget,
    );
    expect(inPeek(find.text('Pagada')), findsOneWidget);
    expect(inPeek(find.text('Cadena KMC X11 126L')), findsOneWidget);
    expect(
      inPeek(find.text('2 × \$22.990 · SKU 4715575895086')),
      findsOneWidget,
    );
    // Each product line carries its photo; one without photo keeps its place.
    expect(
        find.bySemanticsLabel('Foto de Cadena KMC X11 126L'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Foto de Neumático Maxxis Rekon Race 29x2.25'),
      findsNothing,
    );
    expect(inPeek(find.text('Abrir documento')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('supplier-movement-peek-related-$paymentId')),
    );
    await tester.pumpAndSettle();
    expect(inPeek(find.text('PAGO DE COMPRA')), findsOneWidget);
    expect(
      inPeek(find.text('08/10/2026 · Transferencia · ref. 5521')),
      findsOneWidget,
    );
    expect(inPeek(find.text('Documento de compra 145172')), findsOneWidget);
    expect(inPeek(find.text('Abrir pago')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('supplier-movement-peek-back')));
    await tester.pumpAndSettle();
    expect(inPeek(find.text('Cadena KMC X11 126L')), findsOneWidget);
    expect(peek.documentReads[invoiceId], 2,
        reason: 'the payment read its document once; going back reuses it');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a screen reader can open a movement and what it relates to: each row '
      'is a named button with its own tap', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMovements(tester, data(peek: teknoBike()));

    final row = find.bySemanticsLabel('Ver Documento de compra 145172');
    expect(row, findsOneWidget);
    expect(
      tester.getSemantics(row),
      matchesSemantics(
        label: 'Ver Documento de compra 145172',
        isButton: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(
      find.semantics.byLabel('Ver Documento de compra 145172'),
    );
    await tester.pumpAndSettle();
    final payment = find.bySemanticsLabel('Ver Transferencia');
    expect(
      tester.getSemantics(payment),
      matchesSemantics(
        label: 'Ver Transferencia',
        isButton: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Ver Transferencia'));
    await tester.pumpAndSettle();
    expect(inPeek(find.text('PAGO DE COMPRA')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
      '«Abrir …» closes the view and pushes the record page, which returns '
      'to the profile', (tester) async {
    final router = await pumpMovements(tester, data(peek: teknoBike()));

    await openRow(tester, paymentId);
    await tester.tap(find.byKey(const ValueKey('supplier-movement-peek-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('supplier-movement-peek')), findsNothing);
    expect(find.text('Página del pago $paymentId'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Página del pago $paymentId'), findsNothing);
    expect(find.byKey(const ValueKey('supplier-activity-$paymentId')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a credit note says what it credits and why, and opens that purchase '
      'in the same view', (tester) async {
    await pumpMovements(tester, data(peek: teknoBike()));

    await openRow(tester, creditNoteId);
    expect(inPeek(find.text('NOTA DE CRÉDITO DE COMPRA')), findsOneWidget);
    expect(inPeek(find.text('NCC-00001')), findsOneWidget);
    expect(inPeek(find.text('Contabilizada')), findsOneWidget);
    expect(
      inPeek(find.text('Una cadena llegó con un eslabón abierto')),
      findsOneWidget,
    );
    expect(inPeek(find.text('Abrir la compra que corrige')), findsOneWidget);

    final related =
        find.byKey(const ValueKey('supplier-movement-peek-related-$invoiceId'));
    await tester.ensureVisible(related);
    await tester.pumpAndSettle();
    await tester.tap(related);
    await tester.pumpAndSettle();
    expect(inPeek(find.text('145172')), findsOneWidget);
    expect(inPeek(find.text('Neumático Maxxis Rekon Race 29x2.25')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expense opens with its lines and its payment',
      (tester) async {
    await pumpMovements(tester, data(peek: teknoBike()));

    await openRow(tester, expenseId);
    expect(inPeek(find.text('GASTO')), findsOneWidget);
    expect(inPeek(find.text('B-9981')), findsOneWidget);
    expect(inPeek(find.text('30/09/2026 · Boleta · GA-00012')), findsOneWidget);
    expect(inPeek(find.text('Pagado')), findsWidgets);
    expect(inPeek(find.text('Despacho a regiones')), findsOneWidget);

    final payment = find.byKey(
      const ValueKey('supplier-movement-peek-related-$expensePaymentId'),
    );
    await tester.ensureVisible(payment);
    await tester.pumpAndSettle();
    await tester.tap(payment);
    await tester.pumpAndSettle();
    expect(inPeek(find.text('PAGO DE GASTO')), findsOneWidget);
    expect(
      inPeek(find.text('30/09/2026 · Tarjeta de débito · ref. TX-77')),
      findsOneWidget,
    );
    expect(inPeek(find.text('Abrir gasto')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "on a phone the Summary's latest movements open in a sheet that "
      'closes without leaving', (tester) async {
    await pumpMovements(
      tester,
      data(peek: teknoBike()),
      size: const Size(390, 844),
      openTab: false,
    );

    await openRow(tester, invoiceId);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(inPeek(find.text('145172')), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('supplier-movement-peek-close')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('supplier-activity-$invoiceId')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a record that is no longer there says so, and without readings the '
      'rows only read', (tester) async {
    await pumpMovements(tester, data(peek: _FakeMovementPeekSource()));
    await openRow(tester, invoiceId);
    expect(
      inPeek(find.text('Este documento ya no está en el ERP.')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('supplier-movement-peek-open')),
        findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('supplier-movement-peek-close')));
    await tester.pumpAndSettle();

    await pumpMovements(tester, data());
    expect(find.byKey(const ValueKey('supplier-activity-$invoiceId')),
        findsNothing);
    expect(find.text('Documento de compra'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1288, 900), Size(390, 844)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'the open movement fits at ${size.width.toInt()} '
          '${brightness.name}', (tester) async {
        await pumpMovements(
          tester,
          data(peek: teknoBike()),
          size: size,
          brightness: brightness,
          openTab: size.width >= 900,
        );
        await openRow(tester, invoiceId);
        expect(inPeek(find.text('145172')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
