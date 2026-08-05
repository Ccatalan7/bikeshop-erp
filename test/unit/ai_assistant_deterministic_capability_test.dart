import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_contracts.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/providers/ai_agent_model_provider.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

void main() {
  const authority = AIAssistantTurnAuthority(
    ErpAuthorityScopeKey(userId: 'user-no-capability', tenantId: 'tenant-a'),
  );

  for (final prompt in <String>[
    '¿Qué necesita atención hoy?',
    'Dame un resumen de los trabajos activos',
    'Abre el cliente más reciente',
    'Abre el trabajo más reciente',
    'Busca una cámara 29',
    'Muéstrame facturas de venta pendientes',
    'Abre el proveedor más reciente',
    'Muéstrame facturas de compra pendientes',
  ]) {
    test('deterministic reads do not bypass capability for: $prompt', () async {
      final services = _ExplodingDomainServices();
      final purchaseService = _ExplodingPurchaseService();
      final salesService = _ExplodingSalesService();
      final provider = _OneTurnProvider();
      final assistant = AIAssistantService(modelProvider: provider);

      final response = await assistant.sendMessage(
        prompt,
        authority: authority,
        jobs: <MechanicJob>[
          MechanicJob(
            id: 'secret-job',
            tenantId: 'tenant-a',
            jobNumber: 'PG-MUST-NOT-REACH-PROMPT',
            customerId: 'secret-customer',
            status: JobStatus.enCurso,
          ),
        ],
        customerService: services,
        inventoryService: services,
        bikeshopService: services,
        purchaseService: purchaseService,
        salesService: salesService,
        taskService: services,
      );

      expect(services.touches, 0);
      expect(purchaseService.touches, 0);
      expect(salesService.touches, 0);
      expect(
          response.text, 'No hay herramientas autorizadas para esta fuente.');
      expect(response.text.toLowerCase(), isNot(contains('no encontré')));
      expect(provider.request.tools, isEmpty);
      expect(
        provider.request.instructions,
        isNot(contains('PG-MUST-NOT-REACH-PROMPT')),
      );
    });
  }

  test('authorized customer empty without a scope receipt is unavailable',
      () async {
    final assistant =
        AIAssistantService(modelProvider: _FailIfCalledProvider());
    final response = await assistant.sendMessage(
      'Abre el cliente más reciente',
      authority: const AIAssistantTurnAuthority(
        ErpAuthorityScopeKey(userId: 'user-a', tenantId: 'tenant-a'),
        permissions: <String>{AIToolPermission.operationalRead},
      ),
      customerService: _EmptyCustomerService(),
    );

    expect(response.text, contains('no se pudo confirmar'));
    expect(response.text.toLowerCase(), isNot(contains('no encontré')));
  });

  test('authorized sales empty without a scope receipt is unavailable',
      () async {
    final assistant =
        AIAssistantService(modelProvider: _FailIfCalledProvider());
    final response = await assistant.sendMessage(
      'Muéstrame facturas de venta pendientes',
      authority: const AIAssistantTurnAuthority(
        ErpAuthorityScopeKey(userId: 'user-a', tenantId: 'tenant-a'),
        permissions: <String>{AIToolPermission.salesRead},
      ),
      salesService: _EmptySalesService(),
    );

    expect(response.text, contains('no se pudo confirmar'));
    expect(response.text.toLowerCase(), isNot(contains('no encontré')));
  });

  test('authorized purchases empty without a scope receipt is unavailable',
      () async {
    final assistant =
        AIAssistantService(modelProvider: _FailIfCalledProvider());
    final response = await assistant.sendMessage(
      'Muéstrame facturas de compra pendientes',
      authority: const AIAssistantTurnAuthority(
        ErpAuthorityScopeKey(userId: 'user-a', tenantId: 'tenant-a'),
        permissions: <String>{AIToolPermission.purchasesRead},
      ),
      purchaseService: _EmptyPurchaseService(),
    );

    expect(response.text, contains('no se pudo confirmar'));
    expect(response.text.toLowerCase(), isNot(contains('no encontré')));
  });
}

final class _OneTurnProvider implements AIAgentModelProvider {
  late AIAgentProviderRequest request;

  @override
  String get providerId => 'offline-test';

  @override
  Future<AIAgentProviderTurn> complete(AIAgentProviderRequest request) async {
    this.request = request;
    return const AIAgentProviderTurn(
      provider: 'offline-test',
      model: 'offline-test-fast',
      text: 'No hay herramientas autorizadas para esta fuente.',
      toolCalls: <AIAgentToolCall>[],
    );
  }
}

final class _FailIfCalledProvider implements AIAgentModelProvider {
  @override
  String get providerId => 'must-not-run';

  @override
  Future<AIAgentProviderTurn> complete(AIAgentProviderRequest request) async {
    fail('The model ran after an attributable source failure.');
  }
}

final class _EmptyCustomerService implements CustomerService {
  @override
  bool get hasCustomersCache => false;

  @override
  List<Customer> get cachedCustomers => const <Customer>[];

  @override
  Future<List<Customer>> getCustomers({
    String? searchTerm,
    bool forceRefresh = false,
    int limit = 50,
  }) async =>
      const <Customer>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptySalesService implements SalesService {
  @override
  UnmodifiableListView<Invoice> get invoices =>
      UnmodifiableListView<Invoice>(const <Invoice>[]);

  @override
  String? get invoiceError => null;

  @override
  Future<void> loadInvoices({bool forceRefresh = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptyPurchaseService implements PurchaseService {
  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoices({
    bool forceRefresh = false,
  }) async =>
      const <PurchaseInvoice>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Any service access is a regression: authorities without a capability must
/// fall through to the provider before touching a shared cache or datasource.
final class _ExplodingDomainServices
    implements CustomerService, InventoryService, BikeshopService, TaskService {
  int touches = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    touches++;
    throw StateError('Unauthorized domain service access.');
  }
}

final class _ExplodingPurchaseService implements PurchaseService {
  int touches = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    touches++;
    throw StateError('Unauthorized purchase service access.');
  }
}

final class _ExplodingSalesService implements SalesService {
  int touches = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    touches++;
    throw StateError('Unauthorized sales service access.');
  }
}
