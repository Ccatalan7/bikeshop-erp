/// Compile-time rollout switches for the assistant runtime.
///
/// The server gateway remains opt-in until its database migrations, secrets,
/// provider evaluation and authenticated production smoke have all passed.
/// The value is read only when an authority creates its engine; a conversation
/// never changes runtimes mid-session.
abstract final class AIAssistantRuntimeConfig {
  static const bool serverGatewayEnabled = bool.fromEnvironment(
    'AI_AGENT_GATEWAY_ENABLED',
    defaultValue: false,
  );
}
