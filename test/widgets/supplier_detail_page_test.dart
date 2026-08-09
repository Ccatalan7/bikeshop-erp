import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/modules/purchases/pages/supplier_detail_page.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_reveal_controller.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_service.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_relationship_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
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
        'code': 'digital_platform',
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
