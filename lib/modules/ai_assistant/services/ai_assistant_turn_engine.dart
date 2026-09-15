import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/services/sales_service.dart';
import '../../tasks/services/task_service.dart';
import '../models/ai_assistant_turn_contracts.dart';

/// Provider-independent boundary owned by the assistant session.
///
/// Implementations may coordinate deterministic read models, a model provider
/// and authorized tools. The session does not depend on any of those details.
abstract interface class AIAssistantTurnEngine {
  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    PurchaseService? purchaseService,
    SalesService? salesService,
    bool allowJobCacheFallback = true,
    bool visibleJobsSourceUnavailable = false,
    TaskService? taskService,
    required AIAssistantTurnAuthority authority,
  });

  void resetChat();
}

/// Optional direct-command capability implemented only by the governed
/// gateway runtime. The legacy model engine remains source-compatible and can
/// never receive an approval by accident.
abstract interface class AIAssistantApprovalTurnEngine {
  Future<AIAssistantApprovalResolution> resolveApproval(
    AIAssistantApprovalRef approval,
    AIAssistantApprovalDecision decision, {
    required AIAssistantTurnAuthority authority,
  });
}
