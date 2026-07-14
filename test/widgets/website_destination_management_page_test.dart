import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import 'package:vinabike_erp/modules/website/pages/website_destination_management_page.dart';
import 'package:vinabike_erp/modules/website/services/website_destination_audit_service.dart';

void main() {
  Future<WebsiteDestinationAudit> loadAudit() async {
    return const WebsiteDestinationAudit(
      items: [
        WebsiteDestinationAuditItem(
          href: '/productos?category=cat-1',
          kind: WebsiteDestinationKind.category,
          title: 'Componentes > Transmisión',
          health: WebsiteDestinationHealth.warning,
          message: 'La categoría está visible, pero no tiene productos web.',
          owner: WebsiteDestinationOwner.catalogCategories,
          usageCount: 2,
          pageNames: ['Inicio'],
          sourceLabels: ['carousel · slides[0].ctaLink'],
          navigationLocations: [],
        ),
      ],
    );
  }

  testWidgets('shows destination ownership and explicit menu placement',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebsiteDestinationManagementPage(
            embedded: true,
            loadAudit: loadAudit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Destinos y enlaces'), findsOneWidget);
    expect(find.text('Componentes > Transmisión'), findsOneWidget);
    expect(find.text('Solo campaña'), findsOneWidget);
    expect(find.text('Categorías'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps filters usable at compact management width',
      (tester) async {
    tester.view.physicalSize = const Size(820, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebsiteDestinationManagementPage(
            embedded: true,
            loadAudit: loadAudit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Requieren atención'), findsOneWidget);
    expect(find.text('Componentes > Transmisión'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
