import '../../../shared/services/right_toolbar_service.dart';

/// The closed set of surfaces the assistant may send an operator to.
///
/// The model never supplies a route or a [ToolbarTool]. It can only pick one
/// of these identifiers, and [AIAssistantDestinationResolver] turns it into an
/// effect against a registry that lives in this file. An identifier without a
/// registered effect fails closed: the card renders without an action instead
/// of navigating somewhere nobody registered.
///
/// Every bare destination is an aggregate surface. A verified entity reference
/// may narrow it only to one of the canonical record routes registered below;
/// the model still cannot select an editor suffix or any arbitrary route.
enum AIAssistantDestination {
  customers,
  suppliers,
  workshopJobs,
  salesInvoices,
  purchases,
  inventoryProducts,
  expenses,
  conversations,
  tasks,
}

/// The closed set of server-owned entity references a card may carry.
///
/// These are domain identifiers, not routes. The application verifies the UUID
/// and derives the only canonical route that each kind may open.
enum AIAssistantEntityKind {
  workshopJob,
  customer,
  salesInvoice,
  supplier,
  purchaseInvoice,
  product,
  expense,
  conversation,
}

final RegExp _canonicalEntityUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// A UUID that has crossed the assistant card's closed contract.
class AIAssistantEntityRef {
  factory AIAssistantEntityRef.verified({
    required AIAssistantEntityKind kind,
    required String id,
  }) {
    final normalizedId = id.trim().toLowerCase();
    if (!_canonicalEntityUuid.hasMatch(normalizedId)) {
      throw ArgumentError.value(
          id, 'id', 'A canonical entity UUID is required');
    }
    return AIAssistantEntityRef._(kind: kind, id: normalizedId);
  }

  const AIAssistantEntityRef._({required this.kind, required this.id});

  final AIAssistantEntityKind kind;
  final String id;
}

/// Workspace routes, registered as constants. A destination that is not a key
/// of this map has no workspace effect.
const Map<AIAssistantDestination, String> _workspaceRoutes =
    <AIAssistantDestination, String>{
  AIAssistantDestination.customers: '/clientes',
  AIAssistantDestination.suppliers: '/purchases/suppliers',
  AIAssistantDestination.workshopJobs: '/taller/pegas',
  AIAssistantDestination.salesInvoices: '/sales/invoices',
  AIAssistantDestination.purchases: '/purchases',
  AIAssistantDestination.inventoryProducts: '/inventory/products',
  AIAssistantDestination.expenses: '/accounting/expenses',
  AIAssistantDestination.conversations: '/chat',
};

/// Right-toolbar tools, registered as constants. Tareas is a toolbar tool and
/// not a route, so it cannot be expressed as a workspace navigation.
const Map<AIAssistantDestination, ToolbarTool> _toolbarTools =
    <AIAssistantDestination, ToolbarTool>{
  AIAssistantDestination.tasks: ToolbarTool.tasks,
};

/// Call-to-action copy. Each label names the surface it opens, so an operator
/// reads where the click lands before making it.
const Map<AIAssistantDestination, String> _ctaLabels =
    <AIAssistantDestination, String>{
  AIAssistantDestination.customers: 'Abrir Clientes',
  AIAssistantDestination.suppliers: 'Abrir Proveedores',
  AIAssistantDestination.workshopJobs: 'Abrir Taller',
  AIAssistantDestination.salesInvoices: 'Abrir Facturas de venta',
  AIAssistantDestination.purchases: 'Abrir Compras',
  AIAssistantDestination.inventoryProducts: 'Abrir Inventario',
  AIAssistantDestination.expenses: 'Abrir Gastos',
  AIAssistantDestination.conversations: 'Abrir Conversaciones',
  AIAssistantDestination.tasks: 'Abrir Tareas',
};

const Map<AIAssistantEntityKind, AIAssistantDestination>
    _destinationForEntityKind = <AIAssistantEntityKind, AIAssistantDestination>{
  AIAssistantEntityKind.workshopJob: AIAssistantDestination.workshopJobs,
  AIAssistantEntityKind.customer: AIAssistantDestination.customers,
  AIAssistantEntityKind.salesInvoice: AIAssistantDestination.salesInvoices,
  AIAssistantEntityKind.supplier: AIAssistantDestination.suppliers,
  AIAssistantEntityKind.purchaseInvoice: AIAssistantDestination.purchases,
  AIAssistantEntityKind.product: AIAssistantDestination.inventoryProducts,
  AIAssistantEntityKind.expense: AIAssistantDestination.expenses,
  AIAssistantEntityKind.conversation: AIAssistantDestination.conversations,
};

const Map<AIAssistantEntityKind, String> _detailRouteTemplates =
    <AIAssistantEntityKind, String>{
  AIAssistantEntityKind.workshopJob: '/taller/pegas/{id}',
  AIAssistantEntityKind.customer: '/clientes/{id}',
  AIAssistantEntityKind.salesInvoice: '/sales/invoices/{id}',
  AIAssistantEntityKind.supplier: '/purchases/suppliers/{id}',
  AIAssistantEntityKind.purchaseInvoice: '/purchases/{id}',
  AIAssistantEntityKind.expense: '/accounting/expenses/{id}',
  AIAssistantEntityKind.conversation: '/chat?conversation={id}',
};

const Map<AIAssistantEntityKind, String> _detailCtaLabels =
    <AIAssistantEntityKind, String>{
  AIAssistantEntityKind.workshopJob: 'Abrir trabajo',
  AIAssistantEntityKind.customer: 'Abrir cliente',
  AIAssistantEntityKind.salesInvoice: 'Abrir factura de venta',
  AIAssistantEntityKind.supplier: 'Abrir proveedor',
  AIAssistantEntityKind.purchaseInvoice: 'Abrir factura de compra',
  AIAssistantEntityKind.expense: 'Abrir gasto',
  AIAssistantEntityKind.conversation: 'Abrir conversación',
};

extension AIAssistantDestinationCopy on AIAssistantDestination {
  /// Label for the card's action. Falls back to a neutral verb rather than to
  /// an invented surface name.
  String get ctaLabel => _ctaLabels[this] ?? 'Abrir';

  /// Whether this destination currently resolves to any effect at all.
  bool get isRegistered =>
      _workspaceRoutes.containsKey(this) || _toolbarTools.containsKey(this);
}

extension AIAssistantEntityRefNavigation on AIAssistantEntityRef {
  AIAssistantDestination get destination => _destinationForEntityKind[kind]!;

  /// Products deliberately have no detail route: the ERP only exposes a
  /// writer and a public-store product route, neither of which is a safe
  /// read-only assistant destination.
  String? get detailWorkspaceRoute {
    final template = _detailRouteTemplates[kind];
    if (template == null) return null;
    return template.replaceFirst('{id}', Uri.encodeComponent(id));
  }

  String? get detailCtaLabel => _detailCtaLabels[kind];
}

/// Turns a destination identifier into the one effect registered for it.
///
/// The resolver owns both registries, so no caller — and in particular no
/// model output — can widen the reachable surface.
class AIAssistantDestinationResolver {
  const AIAssistantDestinationResolver({
    required this.navigateWorkspace,
    required this.openToolbarTool,
  });

  final void Function(String route) navigateWorkspace;
  final void Function(ToolbarTool tool) openToolbarTool;

  /// Every workspace route this resolver can ever produce. Exposed so a
  /// regression can assert the registry, not a hand-copied list.
  static Set<String> get registeredWorkspaceRoutes =>
      _workspaceRoutes.values.toSet();

  /// Every toolbar tool this resolver can ever produce.
  static Set<ToolbarTool> get registeredToolbarTools =>
      _toolbarTools.values.toSet();

  /// Performs the destination's effect.
  ///
  /// Returns `false` without producing any effect when the destination has no
  /// registered entry, which is the fail-closed path.
  bool dispatch(
    AIAssistantDestination destination, {
    AIAssistantEntityRef? entityRef,
  }) {
    if (entityRef != null) {
      if (entityRef.destination != destination) return false;
      final detailRoute = entityRef.detailWorkspaceRoute;
      if (detailRoute != null) {
        navigateWorkspace(detailRoute);
        return true;
      }
    }

    final route = _workspaceRoutes[destination];
    if (route != null) {
      navigateWorkspace(route);
      return true;
    }

    final tool = _toolbarTools[destination];
    if (tool != null) {
      openToolbarTool(tool);
      return true;
    }

    return false;
  }
}
