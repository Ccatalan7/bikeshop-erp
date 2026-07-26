import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/pega_detail_view.dart';

void main() {
  testWidgets(
    'mobile detail exposes canonical workshop actions without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var canonicalStatusPresses = 0;
      var legacyStatusChanges = 0;
      var itemsPresses = 0;
      var invoicePresses = 0;
      var paymentPresses = 0;
      var bikePresses = 0;
      var customerPresses = 0;

      final job = MechanicJob(
        id: 'job-mobile',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        bikeId: 'bike-1',
        jobNumber: 'PG-MOBILE',
        arrivalDate: DateTime(2026, 7, 25),
        clientRequest: 'Revisión general',
        totalCost: 90000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PegaDetailView(
              job: job,
              onClose: () {},
              onEdit: () {},
              onStatusChange: (_) => legacyStatusChanges++,
              onStatusPressed: () => canonicalStatusPresses++,
              onProductsAndServicesPressed: () => itemsPresses++,
              onInvoicePressed: () => invoicePresses++,
              onPaymentPressed: () => paymentPresses++,
              onBikePressed: () => bikePresses++,
              onCustomerPressed: () => customerPresses++,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('workshop-detail-quick-actions-scroll')),
        findsOneWidget,
      );

      final actionExpectations = <String, void Function()>{
        'workshop-detail-action-status': () {
          expect(canonicalStatusPresses, 1);
          expect(legacyStatusChanges, 0);
        },
        'workshop-detail-action-items': () => expect(itemsPresses, 1),
        'workshop-detail-action-invoice': () => expect(invoicePresses, 1),
        'workshop-detail-action-payment': () => expect(paymentPresses, 1),
        'workshop-detail-action-bike': () => expect(bikePresses, 1),
        'workshop-detail-action-customer': () => expect(customerPresses, 1),
      };

      for (final entry in actionExpectations.entries) {
        final finder = find.byKey(ValueKey(entry.key));
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
        entry.value();
      }

      expect(tester.takeException(), isNull);
    },
  );
}
