import '../../../shared/services/right_toolbar_service.dart';

/// The closed set of surfaces the assistant may send an operator to.
///
/// The model never supplies a route, a [ToolbarTool] or an entity id. It can
/// only pick one of these identifiers, and [AIAssistantDestinationResolver]
/// turns it into an effect against a registry that lives in this file. An
/// identifier without a registered effect fails closed: the card renders
/// without an action instead of navigating somewhere nobody registered.
///
/// Every destination is an aggregate surface. None of them opens an editor,
/// because a card the assistant produced is a reading affordance and this
/// application runs against production.
enum AIAssistantDestination {
  customers,
  suppliers,
  workshopJobs,
  salesInvoices,
  purchases,
  inventoryProducts,
  tasks,
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
  AIAssistantDestination.tasks: 'Abrir Tareas',
};

extension AIAssistantDestinationCopy on AIAssistantDestination {
  /// Label for the card's action. Falls back to a neutral verb rather than to
  /// an invented surface name.
  String get ctaLabel => _ctaLabels[this] ?? 'Abrir';

  /// Whether this destination currently resolves to any effect at all.
  bool get isRegistered =>
      _workspaceRoutes.containsKey(this) || _toolbarTools.containsKey(this);
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
  bool dispatch(AIAssistantDestination destination) {
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
