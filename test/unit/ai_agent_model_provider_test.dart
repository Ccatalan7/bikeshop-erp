import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_contracts.dart';
import 'package:vinabike_erp/modules/ai_assistant/providers/gemini_ai_agent_model_provider.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

void main() {
  group('GeminiAIAgentModelProvider', () {
    late _FakeGeminiTransport transport;
    late GeminiAIAgentModelProvider provider;

    setUp(() {
      transport = _FakeGeminiTransport();
      provider = GeminiAIAgentModelProvider(transport: transport);
    });

    test('maps the logical fast role without exposing a model to callers',
        () async {
      await provider.complete(
        const AIAgentProviderRequest(
          turnId: 'turn-1',
          modelRole: AIAgentModelRole.fast,
          instructions: 'Ayuda con el ERP.',
          messages: <AIAgentMessage>[
            AIAgentMessage.user('Busca una cámara 29'),
          ],
        ),
      );

      expect(transport.model, 'gemini-2.5-flash-lite');
      expect(
        transport.systemInstruction,
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': 'Ayuda con el ERP.'},
          ],
        },
      );
      expect(transport.contents.single['role'], 'user');
    });

    test('maps deep and vision roles to the allowed capable model', () async {
      for (final role in <AIAgentModelRole>[
        AIAgentModelRole.deep,
        AIAgentModelRole.vision,
      ]) {
        await provider.complete(
          AIAgentProviderRequest(
            turnId: 'turn-${role.name}',
            modelRole: role,
            instructions: '',
            messages: const <AIAgentMessage>[
              AIAgentMessage.user('Analiza esto'),
            ],
          ),
        );
        expect(transport.model, 'gemini-2.5-flash');
      }
    });

    test('publishes standard tool schemas and normalizes provider calls',
        () async {
      transport.nextResult = const GeminiProxyGenerateResult(
        text: 'Voy a revisar.',
        functionCalls: <GeminiProxyFunctionCall>[
          GeminiProxyFunctionCall(
            name: 'erp.inventory.search',
            args: <String, dynamic>{'query': 'cadena 12v'},
          ),
        ],
      );

      final turn = await provider.complete(
        const AIAgentProviderRequest(
          turnId: 'turn-tools',
          modelRole: AIAgentModelRole.fast,
          instructions: 'Usa herramientas.',
          messages: <AIAgentMessage>[
            AIAgentMessage.user('¿Hay cadenas de 12 velocidades?'),
          ],
          tools: <AIAgentModelTool>[
            AIAgentModelTool(
              name: 'erp.inventory.search',
              description: 'Busca inventario autorizado.',
              inputSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'query': <String, Object?>{'type': 'string'},
                },
                'required': <String>['query'],
                'additionalProperties': false,
              },
            ),
          ],
        ),
      );

      final declarations = transport.tools.single['functionDeclarations']
          as List<Map<String, dynamic>>;
      expect(declarations.single['name'], 'erp.inventory.search');
      expect(
        (declarations.single['parameters'] as Map)['additionalProperties'],
        isFalse,
      );
      expect(turn.provider, 'gemini');
      expect(turn.model, 'gemini-2.5-flash-lite');
      expect(turn.text, 'Voy a revisar.');
      expect(turn.toolCalls.single.id, 'turn-tools:gemini:0');
      expect(turn.toolCalls.single.name, 'erp.inventory.search');
      expect(turn.toolCalls.single.arguments, <String, Object?>{
        'query': 'cadena 12v',
      });
    });

    test('closes calls with normalized tool outputs on the next request',
        () async {
      await provider.complete(
        const AIAgentProviderRequest(
          turnId: 'turn-output',
          modelRole: AIAgentModelRole.fast,
          instructions: '',
          messages: <AIAgentMessage>[
            AIAgentMessage.user('Busca stock'),
            AIAgentMessage.assistant(
              toolCalls: <AIAgentToolCall>[
                AIAgentToolCall(
                  id: 'call-1',
                  name: 'erp.inventory.search',
                  arguments: <String, Object?>{'query': 'cassette'},
                ),
              ],
            ),
            AIAgentMessage.tool(<AIAgentToolOutput>[
              AIAgentToolOutput(
                callId: 'call-1',
                name: 'erp.inventory.search',
                output: <String, Object?>{
                  'status': 'success',
                  'items': <Object?>[],
                },
              ),
            ]),
          ],
        ),
      );

      expect(transport.contents[1]['role'], 'model');
      expect(transport.contents[2]['role'], 'user');
      final parts = transport.contents[2]['parts'] as List;
      final response = (parts.single as Map)['functionResponse'] as Map;
      expect(response['name'], 'erp.inventory.search');
      expect(response['response'], <String, Object?>{
        'status': 'success',
        'items': <Object?>[],
      });
    });

    test('does not persist provider-specific state in the canonical request',
        () async {
      transport.nextResult = const GeminiProxyGenerateResult(
        text: 'Listo',
        functionCalls: <GeminiProxyFunctionCall>[],
      );

      final turn = await provider.complete(
        const AIAgentProviderRequest(
          turnId: 'turn-clean',
          modelRole: AIAgentModelRole.fast,
          instructions: '',
          messages: <AIAgentMessage>[
            AIAgentMessage.user('hola'),
          ],
        ),
      );

      expect(turn.providerCursor, isNull);
      expect(turn.toolCalls, isEmpty);
      expect(turn.text, 'Listo');
    });
  });
}

class _FakeGeminiTransport implements GeminiAgentTransport {
  String? model;
  List<Map<String, dynamic>> contents = <Map<String, dynamic>>[];
  Map<String, dynamic>? systemInstruction;
  List<Map<String, dynamic>> tools = <Map<String, dynamic>>[];
  Map<String, dynamic>? generationConfig;
  GeminiProxyGenerateResult nextResult = const GeminiProxyGenerateResult(
    text: 'ok',
    functionCalls: <GeminiProxyFunctionCall>[],
  );

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Map<String, dynamic>? generationConfig,
  }) async {
    this.model = model;
    this.contents = contents;
    this.systemInstruction = systemInstruction;
    this.tools = tools;
    this.generationConfig = generationConfig;
    return nextResult;
  }
}
