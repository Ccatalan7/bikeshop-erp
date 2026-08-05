import '../models/ai_agent_contracts.dart';

/// Provider-neutral inference boundary used by the assistant run coordinator.
///
/// Implementations translate the canonical request at the last possible
/// boundary. They do not execute ERP tools and do not decide whether a call is
/// authorized.
abstract interface class AIAgentModelProvider {
  String get providerId;

  Future<AIAgentProviderTurn> complete(AIAgentProviderRequest request);
}
