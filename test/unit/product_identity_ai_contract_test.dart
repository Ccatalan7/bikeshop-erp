import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

const String _leafId = 'leaf-active';
const String _modelId = AIAssistantService.productIdentityVisionModel;
final Uint8List _image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  group('provider-native product identity contract', () {
    test('strict request uses JSON mode and the client validates the contract',
        () async {
      final proxy = _ContractInspectingProxy(
        jsonEncode(_validPayload(leafId: 'L001')),
      );
      final diagnostics = <Map<String, Object?>>[];
      final service = AIAssistantService(
        geminiProxy: proxy,
        productIdentityDiagnosticSink: diagnostics.add,
      );

      final result = await _strictCall(service);

      expect(result, isNotNull);
      expect(proxy.calls, 1);
      expect(proxy.jsonModeValidated, isTrue);
      expect(
          proxy.lastGenerationConfig?['responseMimeType'], 'application/json');
      expect(proxy.lastGenerationConfig?['temperature'], 0);
      expect(
        proxy.lastGenerationConfig?.containsKey('responseSchema'),
        isFalse,
      );
      expect(
        proxy.lastGenerationConfig?.containsKey('responseJsonSchema'),
        isFalse,
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single['finish_reason'], 'STOP');
      expect(diagnostics.single['failure_stage'], isNull);
      service.dispose();
    });

    test('schema shares structure while client owns grounded leaf validation',
        () {
      final schema = ProductIdentityAIContract.responseSchema(
        promptVersion: ProductIdentityAIContract.promptVersion,
        modelId: _modelId,
        offeredLeafIds: const <String>{_leafId, 'leaf-second'},
      );
      final properties = schema['properties'] as Map<String, dynamic>;
      final identity = properties['identity'] as Map<String, dynamic>;
      final identityProperties = identity['properties'] as Map<String, dynamic>;
      final proposals =
          identityProperties['leaf_proposals'] as Map<String, dynamic>;
      final proposal = proposals['items'] as Map<String, dynamic>;
      final proposalProperties = proposal['properties'] as Map<String, dynamic>;
      final categoryId =
          proposalProperties['category_id'] as Map<String, dynamic>;

      expect(schema['type'], 'OBJECT');
      expect(
        (schema['required'] as List).toSet(),
        ProductIdentityAIContract.rootKeys,
      );
      expect(
        (identity['required'] as List).toSet(),
        ProductIdentityAIContract.identityKeys,
      );
      expect(categoryId['type'], 'STRING');
      expect(categoryId.containsKey('enum'), isFalse);
      expect(jsonEncode(schema), isNot(contains('leaf-second')));
      expect(schema.containsKey('minLength'), isFalse);
      expect(jsonEncode(schema).length, lessThan(14000));
    });
  });

  group('typed validator', () {
    AIProductIdentityValidationResult validate(Map<String, Object?> payload) =>
        ProductIdentityAIContract.parseAndValidate(
          responseText: jsonEncode(payload),
          expectedPromptVersion: ProductIdentityAIContract.promptVersion,
          expectedModelId: _modelId,
          offeredLeafIds: const <String>{_leafId},
        );

    test('accepts a complete response and real nullable fields', () {
      final payload = _validPayload();
      final identity = payload['identity'] as Map<String, Object?>;
      identity['manufacturer'] = <String, Object?>{
        'value': null,
        'asserted': false,
        'evidence': 'none',
      };
      identity['packaging'] = <String, Object?>{
        'count': null,
        'unit_token': null,
        'source': null,
      };
      final specs = identity['specs'] as List<Map<String, Object?>>;
      specs.first['unit'] = null;
      final vision = payload['vision'] as Map<String, Object?>;
      vision['visual_summary'] = null;

      final result = validate(payload);

      expect(result.isValid, isTrue);
      expect(result.failure, isNull);
    });

    test('keeps an included accessory inside one primary product identity', () {
      final payload = _validPayload();
      final identity = payload['identity'] as Map<String, Object?>;
      identity['composition'] = <String, Object?>{
        'kind': 'single',
        'components': <Map<String, Object?>>[
          <String, Object?>{
            'label': 'maza trasera',
            'role': 'primary',
            'qty': 1,
          },
          <String, Object?>{
            'label': 'cierre rápido incluido',
            'role': 'included_accessory',
            'qty': 1,
          },
        ],
      };

      final result = validate(payload);

      expect(result.isValid, isTrue);
      expect(result.failure, isNull);
    });

    test('does not let an included accessory manufacture a composite', () {
      final payload = _validPayload();
      final identity = payload['identity'] as Map<String, Object?>;
      identity['composition'] = <String, Object?>{
        'kind': 'composite',
        'components': <Map<String, Object?>>[
          <String, Object?>{
            'label': 'maza trasera',
            'role': 'primary',
            'qty': 1,
          },
          <String, Object?>{
            'label': 'cierre rápido incluido',
            'role': 'included_accessory',
            'qty': 1,
          },
        ],
      };

      final result = validate(payload);

      expect(result.isValid, isFalse);
      expect(result.failure?.jsonPointer, 'identity.composition.components');
      expect(result.failure?.code, 'composite_cardinality');
    });

    test('ignores innocent extra fields without granting them authority',
        () async {
      final payload = _validPayload();
      payload['provider_annotation'] = 'ignored';
      final identity = payload['identity'] as Map<String, Object?>;
      identity['future_field'] = <String, Object?>{'decision': 'same'};
      final manufacturer = identity['manufacturer'] as Map<String, Object?>;
      manufacturer['display_hint'] = 'ignored';
      final result = validate(payload);
      expect(result.isValid, isTrue);

      final servicePayload = _validPayload(leafId: 'L001');
      servicePayload['provider_annotation'] = 'ignored';
      final serviceIdentity =
          servicePayload['identity'] as Map<String, Object?>;
      serviceIdentity['future_field'] = <String, Object?>{
        'decision': 'same',
      };
      final serviceManufacturer =
          serviceIdentity['manufacturer'] as Map<String, Object?>;
      serviceManufacturer['display_hint'] = 'ignored';
      final proxy = _ContractInspectingProxy(jsonEncode(servicePayload));
      final service = AIAssistantService(geminiProxy: proxy);
      final cleaned = await _strictCall(service);
      expect(cleaned?.identityInvestigation?.leafProposals.single.categoryId,
          _leafId);
      service.dispose();
    });

    test('reports the exact pointer for a missing required field', () {
      final payload = _validPayload();
      final identity = payload['identity'] as Map<String, Object?>;
      identity.remove('reason');

      final result = validate(payload);

      expect(result.isValid, isFalse);
      expect(result.failure?.failureStage, 'validation');
      expect(result.failure?.jsonPointer, 'identity.reason');
      expect(result.failure?.code, 'missing_required');
    });

    test('reports the exact pointer for a wrong type', () {
      final payload = _validPayload();
      final identity = payload['identity'] as Map<String, Object?>;
      final specs = identity['specs'] as List<Map<String, Object?>>;
      specs.first['exclusive'] = 'true';

      final result = validate(payload);

      expect(result.isValid, isFalse);
      expect(result.failure?.jsonPointer, 'identity.specs[0].exclusive');
      expect(result.failure?.code, 'expected_boolean');
    });

    test('rejects invalid enums and reports the nested pointer', () {
      final payload = _validPayload();
      final identity = payload['identity'] as Map<String, Object?>;
      final manufacturer = identity['manufacturer'] as Map<String, Object?>;
      manufacturer['evidence'] = 'logo_guess';

      final result = validate(payload);

      expect(result.isValid, isFalse);
      expect(result.failure?.jsonPointer, 'identity.manufacturer.evidence');
      expect(result.failure?.code, 'invalid_enum');
    });

    test('rejects an invented leaf even if the rest is valid', () {
      final payload = _validPayload(leafId: 'invented');
      final result = validate(payload);

      expect(result.isValid, isFalse);
      expect(
        result.failure?.jsonPointer,
        'identity.leaf_proposals[0].category_id',
      );
      expect(result.failure?.code, 'unoffered_leaf_id');
    });

    test('rejects schema, prompt, and model version mismatches separately', () {
      for (final entry in <MapEntry<String, String>>[
        const MapEntry<String, String>('schema_version', 'old'),
        const MapEntry<String, String>('prompt_version', 'old'),
        const MapEntry<String, String>('model_id', 'other-model'),
      ]) {
        final payload = _validPayload()..[entry.key] = entry.value;
        final result = validate(payload);
        expect(result.isValid, isFalse, reason: entry.key);
        expect(result.failure?.jsonPointer, 'root.${entry.key}');
        expect(result.failure?.code, 'version_mismatch');
      }
    });

    test('truncated JSON fails at json_parse without a compatibility repair',
        () {
      final result = ProductIdentityAIContract.parseAndValidate(
        responseText: '{"schema_version":"3","identity":',
        expectedPromptVersion: ProductIdentityAIContract.promptVersion,
        expectedModelId: _modelId,
        offeredLeafIds: const <String>{_leafId},
      );

      expect(result.isValid, isFalse);
      expect(result.failure?.failureStage, 'json_parse');
      expect(result.failure?.jsonPointer, 'root');
    });
  });

  group('fail-closed diagnostics', () {
    test('provider error remains typed and contains no source response',
        () async {
      final diagnostics = <Map<String, Object?>>[];
      final proxy = _ContractInspectingProxy(
        jsonEncode(_validPayload()),
        error: const GeminiProxyException(
          message: 'AI provider rejected the request',
          statusCode: 400,
          apiStatus: 'INVALID_ARGUMENT',
          proxyCode: 'provider_rejected_request',
          providerFieldPaths: <String>[
            'generationConfig.responseSchema.properties.identity',
          ],
        ),
      );
      final service = AIAssistantService(
        geminiProxy: proxy,
        productIdentityDiagnosticSink: diagnostics.add,
      );
      AIProductIdentityFailure? failure;

      final result = await _strictCall(service, onFailure: (value) {
        failure = value;
      });

      expect(result, isNull);
      expect(proxy.calls, 1);
      expect(failure?.failureStage, 'provider');
      expect(failure?.providerCode, 'INVALID_ARGUMENT');
      expect(
        failure?.jsonPointer,
        'generationConfig.responseSchema.properties.identity',
      );
      expect(jsonEncode(diagnostics), isNot(contains('Objeto ZX-77')));
      service.dispose();
    });

    test('timeout is retryable and never yields a heuristic result', () async {
      final proxy = _ContractInspectingProxy(
        jsonEncode(_validPayload()),
        error: TimeoutException('provider timeout'),
      );
      final service = AIAssistantService(geminiProxy: proxy);
      AIProductIdentityFailure? failure;

      final result = await _strictCall(service, onFailure: (value) {
        failure = value;
      });

      expect(result, isNull);
      expect(proxy.calls, 2);
      expect(failure?.failureStage, 'timeout');
      expect(failure?.retryable, isTrue);
      expect(failure?.operatorMessage, contains('sin recomendación'));
      service.dispose();
    });

    test('malformed response diagnostic contains shapes, never values',
        () async {
      const secret = 'SUPPLIER_SECRET_SHOULD_NOT_BE_LOGGED';
      final payload = _validPayload(leafId: 'L001');
      payload['cleaned_name'] = secret;
      final identity = payload['identity'] as Map<String, Object?>;
      identity.remove('reason');
      final diagnostics = <Map<String, Object?>>[];
      final proxy = _ContractInspectingProxy(jsonEncode(payload));
      final service = AIAssistantService(
        geminiProxy: proxy,
        productIdentityDiagnosticSink: diagnostics.add,
      );
      AIProductIdentityFailure? failure;

      final result = await _strictCall(service, onFailure: (value) {
        failure = value;
      });

      expect(result, isNull);
      expect(failure?.jsonPointer, 'identity.reason');
      expect(diagnostics, hasLength(2));
      final encoded = jsonEncode(diagnostics.last);
      expect(encoded, contains('identity_keys'));
      expect(encoded, contains('missing_required'));
      expect(encoded, isNot(contains(secret)));
      service.dispose();
    });
  });
}

Future<AICleanedProductName?> _strictCall(
  AIAssistantService service, {
  void Function(AIProductIdentityFailure failure)? onFailure,
}) {
  return service.cleanProductTitleFromImage(
    rawTitle: 'Objeto ZX-77',
    imageBytes: _image,
    rowRevision: '1',
    categoryTreeKey: 'tree-v1',
    catalogKey: 'catalog-v1',
    activeLeafCategories: const <AIProductCategoryLeaf>[
      AIProductCategoryLeaf(id: _leafId, path: 'Componentes / Objetos'),
    ],
    requireLeafAuthority: true,
    onFailure: onFailure,
  );
}

Map<String, Object?> _validPayload({String leafId = _leafId}) =>
    <String, Object?>{
      'schema_version': ProductIdentityAIContract.schemaVersion,
      'prompt_version': ProductIdentityAIContract.promptVersion,
      'model_id': _modelId,
      'cleaned_name': 'Objeto ZX-77',
      'identity': <String, Object?>{
        'object': <String, Object?>{
          'label': 'objeto',
          'confidence': 0.9,
        },
        'manufacturer': <String, Object?>{
          'value': null,
          'asserted': false,
          'evidence': 'none',
        },
        'models': <Map<String, Object?>>[
          <String, Object?>{'code': 'ZX-77', 'role': 'identity'},
        ],
        'specs': <Map<String, Object?>>[
          <String, Object?>{
            'key': 'interfaz',
            'value': 'A',
            'unit': null,
            'source': 'option',
            'exclusive': true,
          },
        ],
        'fitment': const <String>[],
        'composition': <String, Object?>{
          'kind': 'single',
          'components': <Map<String, Object?>>[
            <String, Object?>{
              'label': 'objeto',
              'role': 'primary',
              'qty': 1,
            },
          ],
        },
        'packaging': <String, Object?>{
          'count': 1,
          'unit_token': 'pieza',
          'source': 'name',
        },
        'leaf_proposals': <Map<String, Object?>>[
          <String, Object?>{
            'category_id': leafId,
            'confidence': 0.9,
            'basis': <String>['object', 'image', 'tree'],
          },
        ],
        'evidence_used': <String>['photo', 'selected_variant'],
        'abstain_reason': null,
        'reason': 'El objeto y el modelo sostienen la identidad.',
      },
      'vision': <String, Object?>{
        'primary_type': 'objeto',
        'catalog_terms': <String>['objeto'],
        'excluded_terms': const <String>[],
        'confidence': 0.8,
        'visual_summary': 'Objeto visible',
      },
    };

class _ContractInspectingProxy extends GeminiProxyService {
  _ContractInspectingProxy(this.reply, {this.error})
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
          ),
        );

  final String reply;
  final Object? error;
  int calls = 0;
  bool jsonModeValidated = false;
  Map<String, dynamic>? lastGenerationConfig;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Map<String, dynamic>? generationConfig,
  }) async {
    calls++;
    lastGenerationConfig = generationConfig;
    _validateGenerationConfig(generationConfig);
    final failure = error;
    if (failure != null) throw failure;
    return GeminiProxyGenerateResult(
      text: reply,
      functionCalls: const <GeminiProxyFunctionCall>[],
      finishReason: 'STOP',
    );
  }

  void _validateGenerationConfig(Map<String, dynamic>? config) {
    if (config?['responseMimeType'] !=
        ProductIdentityAIContract.responseMimeType) {
      throw StateError('missing responseMimeType');
    }
    if (config?.containsKey('responseSchema') == true ||
        config?.containsKey('responseJsonSchema') == true) {
      throw StateError('provider schema must stay client-owned');
    }
    if (config?['temperature'] != 0) {
      throw StateError('identity investigation must be deterministic');
    }
    jsonModeValidated = true;
  }
}
