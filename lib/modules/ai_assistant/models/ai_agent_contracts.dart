import 'package:flutter/foundation.dart';

/// Logical quality/capability role requested by the agent runtime.
///
/// A client asks for a role, never for a provider model id. The server-side
/// router remains free to change an allowlisted model without shipping a new
/// Flutter build.
enum AIAgentModelRole {
  fast,
  deep,
  vision,
}

enum AIAgentMessageRole {
  user,
  assistant,
  tool,
}

@immutable
class AIAgentToolCall {
  const AIAgentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

@immutable
class AIAgentToolOutput {
  const AIAgentToolOutput({
    required this.callId,
    required this.name,
    required this.output,
  });

  final String callId;
  final String name;
  final Map<String, Object?> output;
}

/// One provider-neutral item in the model conversation.
///
/// Tool calls belong to an assistant item and tool outputs to a tool item.
/// Keeping those shapes explicit prevents provider-specific `parts`,
/// `functionCall` or `previous_response_id` values from leaking into the
/// runtime and transcript owners.
@immutable
class AIAgentMessage {
  const AIAgentMessage.user(this.text)
      : role = AIAgentMessageRole.user,
        toolCalls = const <AIAgentToolCall>[],
        toolOutputs = const <AIAgentToolOutput>[];

  const AIAgentMessage.assistant({
    this.text = '',
    this.toolCalls = const <AIAgentToolCall>[],
  })  : role = AIAgentMessageRole.assistant,
        toolOutputs = const <AIAgentToolOutput>[];

  const AIAgentMessage.tool(this.toolOutputs)
      : role = AIAgentMessageRole.tool,
        text = '',
        toolCalls = const <AIAgentToolCall>[];

  final AIAgentMessageRole role;
  final String text;
  final List<AIAgentToolCall> toolCalls;
  final List<AIAgentToolOutput> toolOutputs;
}

/// A function the selected model may request.
///
/// [inputSchema] is standard JSON Schema. Runtime-owned registries must publish
/// object schemas with `additionalProperties: false`; providers may reject a
/// non-conforming schema rather than silently weakening it.
@immutable
class AIAgentModelTool {
  const AIAgentModelTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
}

@immutable
class AIAgentProviderRequest {
  const AIAgentProviderRequest({
    required this.turnId,
    required this.modelRole,
    required this.instructions,
    required this.messages,
    this.tools = const <AIAgentModelTool>[],
    this.allowParallelToolCalls = false,
  });

  final String turnId;
  final AIAgentModelRole modelRole;
  final String instructions;
  final List<AIAgentMessage> messages;
  final List<AIAgentModelTool> tools;
  final bool allowParallelToolCalls;
}

/// Normalized result returned by any provider adapter.
///
/// [providerCursor] is opaque and optional. Viñabike's own message/run state is
/// canonical; a provider cursor may optimize the next call but can be dropped
/// without losing the business conversation.
@immutable
class AIAgentProviderTurn {
  const AIAgentProviderTurn({
    required this.provider,
    required this.model,
    required this.text,
    required this.toolCalls,
    this.finishReason,
    this.providerCursor,
  });

  final String provider;
  final String model;
  final String text;
  final List<AIAgentToolCall> toolCalls;
  final String? finishReason;
  final String? providerCursor;
}
