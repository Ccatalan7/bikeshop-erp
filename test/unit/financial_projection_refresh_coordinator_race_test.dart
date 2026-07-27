import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/accounting/services/financial_projection_refresh_coordinator.dart';

void main() {
  for (final newerScope in <String?>[null, 'tenant-b']) {
    final label = newerScope ?? 'signed-out scope';

    test(
      'a late tenant lookup cannot replace a newer $label',
      () async {
        final coordinator = FinancialProjectionRefreshCoordinator();
        final slowLookup = Completer<String?>();
        addTearDown(coordinator.dispose);

        await coordinator.synchronizeTenant('tenant-seed');
        final staleResolution = coordinator.synchronizeTenantFromResolver(
          () => slowLookup.future,
        );

        await coordinator.synchronizeTenant(newerScope);
        slowLookup.complete('tenant-a');
        await staleResolution;

        expect(coordinator.tenantId, newerScope);
      },
    );
  }

  test(
    'two commits on the same row after a flush produce two revisions',
    () async {
      final coordinator = FinancialProjectionRefreshCoordinator(
        coalesceWindow: const Duration(milliseconds: 5),
        duplicateWindow: const Duration(milliseconds: 400),
      );
      final signals = <FinancialProjectionRefreshSignal>[];
      final subscription = coordinator.signals.listen(signals.add);
      addTearDown(subscription.cancel);
      addTearDown(coordinator.dispose);

      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.salesInvoice,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'invoice-row-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));

      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.salesInvoice,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'invoice-row-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(coordinator.revision, 2);
      expect(signals.map((signal) => signal.revision), <int>[1, 2]);
      expect(
        signals.map((signal) => signal.changes),
        everyElement(
          const {FinancialProjectionChangeKind.salesInvoice},
        ),
      );
    },
  );
}
