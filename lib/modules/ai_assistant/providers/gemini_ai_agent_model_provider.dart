import '../../../shared/services/gemini_proxy_service.dart';
import '../models/ai_agent_contracts.dart';
import 'ai_agent_model_provider.dart';

/// Narrow transport boundary so the provider adapter can be proven without an
/// API key, Supabase singleton or network call.
abstract interface class GeminiAgentTransport {
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools,
    Map<String, dynamic>? generationConfig,
  });
}

class GeminiProxyAgentTransport implements GeminiAgentTransport {
  GeminiProxyAgentTransport({GeminiProxyService? proxy})
      : _proxyInstance = proxy;

  GeminiProxyService? _proxyInstance;
  GeminiProxyService get _proxy => _proxyInstance ??= GeminiProxyService();

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Map<String, dynamic>? generationConfig,
  }) {
    return _proxy.generateContent(
      model: model,
      contents: contents,
      systemInstruction: systemInstruction,
      tools: tools,
      generationConfig: generationConfig,
    );
  }
}

/// Compatibility adapter for the current secured Gemini proxy.
///
/// Model literals live only here while the legacy Edge Function remains the
/// active backend. The future `ai-runtime` gateway will replace this mapping
/// with server-owned routing; callers already depend only on logical roles.
class GeminiAIAgentModelProvider implements AIAgentModelProvider {
  GeminiAIAgentModelProvider({GeminiAgentTransport? transport})
      : _transport = transport ?? GeminiProxyAgentTransport();

  final GeminiAgentTransport _transport;

  @override
  String get providerId => 'gemini';

  @override
  Future<AIAgentProviderTurn> complete(AIAgentProviderRequest request) async {
    final model = _modelFor(request.modelRole);
    final result = await _transport.generateContent(
      model: model,
      systemInstruction: request.instructions.trim().isEmpty
          ? null
          : <String, dynamic>{
              'parts': <Map<String, dynamic>>[
                <String, dynamic>{'text': request.instructions},
              ],
            },
      contents: request.messages.map(_messageToGemini).toList(growable: false),
      tools: request.tools.isEmpty
          ? const <Map<String, dynamic>>[]
          : <Map<String, dynamic>>[
              <String, dynamic>{
                'functionDeclarations': request.tools
                    .map(
                      (tool) => <String, dynamic>{
                        'name': tool.name,
                        'description': tool.description,
                        'parameters': tool.inputSchema,
                      },
                    )
                    .toList(growable: false),
              },
            ],
    );

    return AIAgentProviderTurn(
      provider: providerId,
      model: model,
      text: result.text.trim(),
      toolCalls: <AIAgentToolCall>[
        for (var index = 0; index < result.functionCalls.length; index++)
          AIAgentToolCall(
            id: '${request.turnId}:gemini:$index',
            name: result.functionCalls[index].name,
            arguments: Map<String, Object?>.from(
              result.functionCalls[index].args,
            ),
          ),
      ],
    );
  }

  String _modelFor(AIAgentModelRole role) => switch (role) {
        AIAgentModelRole.fast => 'gemini-2.5-flash-lite',
        AIAgentModelRole.deep || AIAgentModelRole.vision => 'gemini-2.5-flash',
      };

  Map<String, dynamic> _messageToGemini(AIAgentMessage message) {
    switch (message.role) {
      case AIAgentMessageRole.user:
        return <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': message.text},
          ],
        };
      case AIAgentMessageRole.assistant:
        return <String, dynamic>{
          'role': 'model',
          'parts': <Map<String, dynamic>>[
            for (final call in message.toolCalls)
              <String, dynamic>{
                'functionCall': <String, dynamic>{
                  'name': call.name,
                  'args': call.arguments,
                },
              },
            if (message.text.trim().isNotEmpty)
              <String, dynamic>{'text': message.text.trim()},
          ],
        };
      case AIAgentMessageRole.tool:
        return <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, dynamic>>[
            for (final output in message.toolOutputs)
              <String, dynamic>{
                'functionResponse': <String, dynamic>{
                  'name': output.name,
                  'response': output.output,
                },
              },
          ],
        };
    }
  }
}
