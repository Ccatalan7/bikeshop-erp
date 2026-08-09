import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/modules/purchases/pages/supplier_list_page.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  const tenantId = '10000000-0000-0000-0000-000000000001';

  Future<void> pumpHub(
    WidgetTester tester, {
    required SupplierHubDataSource source,
  }) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: SupplierListPage(
            dataSource: source,
            includeWorkspaceShell: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'legacy fallback opens the complete directory and exposes no dead category scope',
    (tester) async {
      final source = _FakeSupplierHubDataSource(
        profiles: [
          _profile(
            tenantId: tenantId,
            index: 1,
            name: 'AliExpress',
            dataSource: SupplierProfileDataSource.legacyReadOnly,
          ),
          _profile(
            tenantId: tenantId,
            index: 2,
            name: 'Andes Industrial',
            dataSource: SupplierProfileDataSource.legacyReadOnly,
          ),
        ],
        catalog: SupplierClassificationCatalog(),
      );

      await pumpHub(tester, source: source);

      expect(find.text('Directorio  2'), findsOneWidget);
      expect(find.text('Explorar'), findsNothing);
      expect(find.text('AliExpress'), findsOneWidget);
      expect(find.text('Andes Industrial'), findsOneWidget);
      expect(find.text('2 de 2'), findsOneWidget);
      expect(find.text('Proveedor de bienes'), findsNothing);
      expect(find.text('No hay proveedores que coincidan'), findsNothing);

      await tester.tap(find.byTooltip('Filtros del directorio'));
      await tester.pumpAndSettle();
      expect(find.text('Elegir categoría…'), findsNothing);
    },
  );

  testWidgets(
    'opening Directory directly clears a previously selected category scope',
    (tester) async {
      final goodsDefinition = SupplierClassificationDefinition(
        id: '40000000-0000-0000-0000-000000000004',
        tenantId: tenantId,
        kind: SupplierClassificationDefinitionKind.role,
        code: 'goods_vendor',
        label: 'Proveedor de bienes',
      );
      final source = _FakeSupplierHubDataSource(
        profiles: [
          _profile(
            tenantId: tenantId,
            index: 1,
            name: 'Proveedor clasificado',
            roles: [
              SupplierRole(
                id: '50000000-0000-0000-0000-000000000005',
                tenantId: tenantId,
                supplierId: _supplierId(1),
                definitionId: goodsDefinition.id,
                code: goodsDefinition.code,
                label: goodsDefinition.label,
              ),
            ],
          ),
          _profile(
            tenantId: tenantId,
            index: 2,
            name: 'Proveedor sin categoría',
          ),
        ],
        catalog: SupplierClassificationCatalog(roles: [goodsDefinition]),
      );

      await pumpHub(tester, source: source);

      final categoryCard = find
          .ancestor(
            of: find.text('Proveedor de bienes'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.tap(categoryCard);
      await tester.pumpAndSettle();

      expect(find.text('Proveedor de bienes · 1 proveedor'), findsOneWidget);
      expect(find.text('Proveedor clasificado'), findsOneWidget);
      expect(find.text('Proveedor sin categoría'), findsNothing);

      await tester.tap(find.text('Explorar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Directorio  2'));
      await tester.pumpAndSettle();

      expect(find.text('Proveedor de bienes · 1 proveedor'), findsNothing);
      expect(find.text('Proveedor clasificado'), findsOneWidget);
      expect(find.text('Proveedor sin categoría'), findsOneWidget);
      expect(find.text('2 de 2'), findsOneWidget);
    },
  );

  testWidgets(
    'an empty confirmed category never replaces the populated directory with zero rows',
    (tester) async {
      final goodsDefinition = SupplierClassificationDefinition(
        id: '40000000-0000-0000-0000-000000000004',
        tenantId: tenantId,
        kind: SupplierClassificationDefinitionKind.role,
        code: 'goods_vendor',
        label: 'Proveedor de bienes',
      );
      final source = _FakeSupplierHubDataSource(
        profiles: [
          _profile(
            tenantId: tenantId,
            index: 1,
            name: 'AliExpress',
          ),
          _profile(
            tenantId: tenantId,
            index: 2,
            name: 'Andes Industrial',
          ),
        ],
        catalog: SupplierClassificationCatalog(roles: [goodsDefinition]),
      );

      await pumpHub(tester, source: source);

      final categoryCard = find
          .ancestor(
            of: find.text('Proveedor de bienes'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.tap(categoryCard);
      await tester.pumpAndSettle();

      expect(find.text('Directorio  2'), findsOneWidget);
      expect(find.text('2 de 2'), findsOneWidget);
      expect(find.text('AliExpress'), findsOneWidget);
      expect(find.text('Andes Industrial'), findsOneWidget);
      expect(find.text('Proveedor de bienes · 0 proveedores'), findsNothing);
      expect(
        find.text(
          'Aún no hay proveedores confirmados en Proveedor de bienes. '
          'Se muestra el directorio completo.',
        ),
        findsOneWidget,
      );
    },
  );
}

class _FakeSupplierHubDataSource implements SupplierHubDataSource {
  const _FakeSupplierHubDataSource({
    required this.profiles,
    required this.catalog,
  });

  final List<SupplierProfile> profiles;
  final SupplierClassificationCatalog catalog;

  @override
  Future<SupplierClassificationCatalog> getClassificationCatalog() async =>
      catalog;

  @override
  Future<List<SupplierProfile>> listSupplierProfiles() async => profiles;
}

SupplierProfile _profile({
  required String tenantId,
  required int index,
  required String name,
  List<SupplierRole> roles = const [],
  SupplierProfileDataSource dataSource = SupplierProfileDataSource.foundation,
}) {
  final supplierId = _supplierId(index);
  final partyId =
      '30000000-0000-0000-0000-${index.toString().padLeft(12, '0')}';
  return SupplierProfile(
    party: ExternalParty(
      id: partyId,
      tenantId: tenantId,
      kind: ExternalPartyKind.organization,
      name: name,
    ),
    relationship: SupplierRelationship(
      id: supplierId,
      tenantId: tenantId,
      externalPartyId: partyId,
      name: name,
      status: SupplierRelationshipStatus.active,
      roles: roles,
    ),
    dataSource: dataSource,
  );
}

String _supplierId(int index) =>
    '20000000-0000-0000-0000-${index.toString().padLeft(12, '0')}';
