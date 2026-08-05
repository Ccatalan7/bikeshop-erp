import '../models/ai_agent_tool.dart';
import 'ai_tool_registry.dart';

/// One authority-bound search request passed to an injected ERP reader.
class AIBusinessReadRequest {
  factory AIBusinessReadRequest({
    required String query,
    required int? limit,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || normalizedQuery.length > 240) {
      throw ArgumentError.value(
        query,
        'query',
        'Must contain between 1 and 240 characters.',
      );
    }
    if (limit != null && (limit < 1 || limit > maxLimit)) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Must be between 1 and $maxLimit.',
      );
    }
    return AIBusinessReadRequest._(
      query: normalizedQuery,
      limit: limit ?? maxLimit,
    );
  }

  const AIBusinessReadRequest._({
    required this.query,
    required this.limit,
  });

  static const int maxLimit = 10;

  final String query;
  final int limit;
}

enum AIBusinessReadStatus {
  success,
  verifiedEmpty,
  unavailable,
}

/// Provider-neutral result vocabulary shared by every business reader.
class AIBusinessReadToolResult {
  factory AIBusinessReadToolResult.success(
    List<Map<String, Object?>> items,
  ) {
    if (items.isEmpty) {
      throw ArgumentError.value(
        items,
        'items',
        'Use verifiedEmpty when the read completed with no matches.',
      );
    }
    return AIBusinessReadToolResult._(
      status: AIBusinessReadStatus.success,
      items: items,
    );
  }

  const AIBusinessReadToolResult.verifiedEmpty()
      : this._(
          status: AIBusinessReadStatus.verifiedEmpty,
          items: const <Map<String, Object?>>[],
        );

  const AIBusinessReadToolResult.unavailable()
      : this._(
          status: AIBusinessReadStatus.unavailable,
          items: const <Map<String, Object?>>[],
        );

  const AIBusinessReadToolResult._({
    required this.status,
    required this.items,
  });

  final AIBusinessReadStatus status;
  final List<Map<String, Object?>> items;

  Map<String, Object?> toJson({required Set<String> allowedItemFields}) {
    final safeItems = <Map<String, Object?>>[];
    for (final item in items) {
      if (item.keys.any((key) => !allowedItemFields.contains(key)) ||
          item.values.any(
            (value) =>
                value != null &&
                value is! String &&
                value is! num &&
                value is! bool,
          )) {
        throw const AIToolExecutorOutputException();
      }
      safeItems.add(Map<String, Object?>.unmodifiable(item));
    }
    return <String, Object?>{
      'status': status.name,
      'items': List<Map<String, Object?>>.unmodifiable(safeItems),
    };
  }
}

typedef AIBusinessReadTool = Future<AIBusinessReadToolResult> Function(
  AIBusinessReadRequest request,
  AIToolAuthority authority,
);

/// Stable ERP read names. Providers only receive these advertisements.
abstract final class AIBusinessReadToolNames {
  static const String searchWorkshopJobs = 'search_workshop_jobs';
  static const String searchTasks = 'search_tasks';
  static const String searchCustomers = 'search_customers';
  static const String searchSuppliers = 'search_suppliers';
  static const String searchSalesInvoices = 'search_sales_invoices';
  static const String searchPurchaseInvoices = 'search_purchase_invoices';
}

/// Builds a bounded, read-only ERP catalog around authority-bound callbacks.
///
/// The callbacks are deliberately injected: this catalog has no Supabase or
/// domain-service dependency. Discovery still requires a runtime-owned ERP
/// capability, and the exact authority is passed to every callback.
AIToolRegistry buildAIBusinessReadToolRegistry({
  required AIBusinessReadTool searchWorkshopJobs,
  required AIBusinessReadTool searchTasks,
  required AIBusinessReadTool searchCustomers,
  required AIBusinessReadTool searchSuppliers,
  required AIBusinessReadTool searchSalesInvoices,
  required AIBusinessReadTool searchPurchaseInvoices,
  required AIToolPolicy policy,
}) {
  return AIToolRegistry(
    policy: policy,
    registrations: buildAIBusinessReadToolRegistrations(
      searchWorkshopJobs: searchWorkshopJobs,
      searchTasks: searchTasks,
      searchCustomers: searchCustomers,
      searchSuppliers: searchSuppliers,
      searchSalesInvoices: searchSalesInvoices,
      searchPurchaseInvoices: searchPurchaseInvoices,
    ),
  );
}

/// Returns registrations for composition with the assistant's other catalogs.
List<AIToolRegistration> buildAIBusinessReadToolRegistrations({
  required AIBusinessReadTool searchWorkshopJobs,
  required AIBusinessReadTool searchTasks,
  required AIBusinessReadTool searchCustomers,
  required AIBusinessReadTool searchSuppliers,
  required AIBusinessReadTool searchSalesInvoices,
  required AIBusinessReadTool searchPurchaseInvoices,
}) {
  return <AIToolRegistration>[
    _registration(
      name: AIBusinessReadToolNames.searchWorkshopJobs,
      description: 'Busca trabajos de taller autorizados por folio, cliente, '
          'bicicleta o estado.',
      reader: searchWorkshopJobs,
      requiredPermission: AIToolPermission.operationalRead,
      allowedItemFields: const <String>{
        'jobNumber',
        'customerName',
        'status',
        'priority',
        'arrivalDate',
        'deliveryDeadline',
        'clientRequest',
        'assignedTechnicianName',
      },
    ),
    _registration(
      name: AIBusinessReadToolNames.searchTasks,
      description: 'Busca tareas autorizadas por texto, responsable o estado.',
      reader: searchTasks,
      requiredPermission: AIToolPermission.operationalRead,
      allowedItemFields: const <String>{
        'title',
        'status',
        'priority',
        'dueDate',
        'assigneeName',
        'linkedContext',
      },
    ),
    _registration(
      name: AIBusinessReadToolNames.searchCustomers,
      description: 'Busca clientes autorizados por nombre o identificador.',
      reader: searchCustomers,
      requiredPermission: AIToolPermission.operationalRead,
      allowedItemFields: const <String>{
        'name',
        'isActive',
        'updatedAt',
      },
    ),
    _registration(
      name: AIBusinessReadToolNames.searchSuppliers,
      description: 'Busca proveedores autorizados por nombre o identificador.',
      reader: searchSuppliers,
      requiredPermission: AIToolPermission.purchasesRead,
      allowedItemFields: const <String>{
        'name',
        'isActive',
        'updatedAt',
      },
    ),
    _registration(
      name: AIBusinessReadToolNames.searchSalesInvoices,
      description: 'Busca facturas de venta autorizadas por folio, cliente o '
          'estado.',
      reader: searchSalesInvoices,
      requiredPermission: AIToolPermission.salesRead,
      allowedItemFields: const <String>{
        'invoiceNumber',
        'customerName',
        'status',
        'date',
        'dueDate',
        'total',
        'balance',
      },
    ),
    _registration(
      name: AIBusinessReadToolNames.searchPurchaseInvoices,
      description: 'Busca facturas de compra autorizadas por folio, proveedor '
          'o estado.',
      reader: searchPurchaseInvoices,
      requiredPermission: AIToolPermission.purchasesRead,
      allowedItemFields: const <String>{
        'invoiceNumber',
        'supplierName',
        'status',
        'date',
        'dueDate',
        'total',
        'balance',
      },
    ),
  ];
}

AIToolRegistration _registration({
  required String name,
  required String description,
  required AIBusinessReadTool reader,
  required String requiredPermission,
  required Set<String> allowedItemFields,
}) {
  return AIToolRegistration(
    definition: AIToolDefinition(
      name: name,
      version: 'v1',
      description: description,
      inputSchema: _searchSchema(),
      requiredPermissions: <String>{requiredPermission},
      risk: AIToolRiskLevel.read,
      requiresApproval: false,
      timeout: const Duration(seconds: 15),
      maxResults: AIBusinessReadRequest.maxLimit,
      maxOutputBytes: 48 * 1024,
      allowsParallelExecution: true,
      idempotency: AIToolIdempotencyPolicy.notApplicable,
    ),
    executor: (context) async {
      final request = AIBusinessReadRequest(
        query: context.arguments['query']! as String,
        limit: context.arguments['limit'] as int?,
      );
      final result = await reader(request, context.authority);
      if (result.items.length > request.limit) {
        throw const AIToolExecutorOutputException();
      }
      return AIToolExecutorResult(
        data: result.toJson(allowedItemFields: allowedItemFields),
        resultCount: result.items.length,
      );
    },
  );
}

AIToolInputSchema _searchSchema() => AIToolInputSchema.closedObject(
      properties: const <String, Object?>{
        'query': <String, Object?>{
          'type': 'string',
          'minLength': 1,
          'maxLength': 240,
          'description': 'Texto breve para filtrar registros autorizados.',
        },
        'limit': <String, Object?>{
          'type': <Object?>['integer', 'null'],
          'minimum': 1,
          'maximum': AIBusinessReadRequest.maxLimit,
          'description': 'Máximo de resultados; null usa 10.',
        },
      },
      required: const <String>['query', 'limit'],
    );
