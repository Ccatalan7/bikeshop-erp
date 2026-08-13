import 'dart:convert';

/// Versioned provider and validation contract for the primary product identity
/// investigation.
///
/// This is the only owner of the JSON field set, enums, native Gemini schema,
/// and structural/semantic validation rules. Prompts refer to this contract;
/// they do not carry a second hand-written response example.
class ProductIdentityAIContract {
  const ProductIdentityAIContract._();

  static const String schemaVersion = '4';
  static const String promptVersion = 'ai-product-identity-investigation-v4';
  static const String responseMimeType = 'application/json';

  static const Set<String> rootKeys = <String>{
    'schema_version',
    'prompt_version',
    'model_id',
    'cleaned_name',
    'identity',
    'vision',
  };
  static const Set<String> identityKeys = <String>{
    'object',
    'manufacturer',
    'models',
    'specs',
    'fitment',
    'composition',
    'packaging',
    'leaf_proposals',
    'evidence_used',
    'abstain_reason',
    'reason',
  };
  static const Set<String> objectKeys = <String>{'label', 'confidence'};
  static const Set<String> manufacturerKeys = <String>{
    'value',
    'asserted',
    'evidence',
  };
  static const Set<String> modelKeys = <String>{'code', 'role'};
  static const Set<String> specKeys = <String>{
    'key',
    'value',
    'unit',
    'source',
    'exclusive',
  };
  static const Set<String> compositionKeys = <String>{'kind', 'components'};
  static const Set<String> componentKeys = <String>{'label', 'role', 'qty'};
  static const Set<String> packagingKeys = <String>{
    'count',
    'unit_token',
    'source',
  };
  static const Set<String> leafProposalKeys = <String>{
    'category_id',
    'confidence',
    'basis',
  };
  static const Set<String> visionKeys = <String>{
    'primary_type',
    'catalog_terms',
    'excluded_terms',
    'confidence',
    'visual_summary',
  };

  static const Set<String> manufacturerEvidence = <String>{
    'identity',
    'compatibility',
    'none',
  };
  static const Set<String> modelRoles = <String>{'identity', 'fitment'};
  static const Set<String> specSources = <String>{
    'option',
    'name',
    'body',
    'photo',
  };
  static const Set<String> compositionKinds = <String>{
    'single',
    'composite',
    'insufficient',
  };
  static const Set<String> componentRoles = <String>{
    'primary',
    'component',
    'included_accessory',
  };
  static const Set<String> leafBasis = <String>{
    'object',
    'image',
    'name',
    'option',
    'fitment',
    'tree',
  };

  /// Gemini REST `GenerationConfig` for the existing v1beta proxy endpoint.
  ///
  /// The first production canary sent the complete tenant leaf-id enum inside
  /// a deeply nested `responseJsonSchema`. Gemini rejected that request with
  /// `INVALID_ARGUMENT` before running the model. The provider now receives the
  /// compact OpenAPI [responseSchema] it documents for `generateContent`.
  /// Tenant ids and every cross-field invariant remain authoritative in
  /// [parseAndValidate], so simplifying the provider grammar does not relax the
  /// application contract or permit a hallucinated category.
  static Map<String, dynamic> generationConfig({
    required String promptVersion,
    required String modelId,
    required Set<String> offeredLeafIds,
  }) {
    if (promptVersion.trim().isEmpty ||
        modelId.trim().isEmpty ||
        offeredLeafIds.isEmpty) {
      throw ArgumentError('A complete investigation contract is required.');
    }

    // Gemini 2.5 rejected the complete nested identity schema twice in the
    // real macOS canary, first as responseJsonSchema and then as
    // responseSchema. Keep JSON mode at the provider boundary and enforce the
    // complete versioned shape plus every semantic invariant in
    // parseAndValidate. A malformed or hallucinated result still fails closed;
    // this only prevents provider schema compilation from blocking the model
    // before it sees the source image.
    return const <String, dynamic>{
      'responseMimeType': responseMimeType,
      'temperature': 0,
    };
  }

  static Map<String, dynamic> responseSchema({
    required String promptVersion,
    required String modelId,
    required Set<String> offeredLeafIds,
  }) {
    if (offeredLeafIds.isEmpty) {
      throw ArgumentError.value(
        offeredLeafIds,
        'offeredLeafIds',
        'At least one active leaf is required.',
      );
    }
    return <String, dynamic>{
      'type': 'OBJECT',
      'required': rootKeys.toList(growable: false),
      'properties': <String, dynamic>{
        'schema_version': _constantString(schemaVersion),
        'prompt_version': _constantString(promptVersion),
        'model_id': _constantString(modelId),
        'cleaned_name': _string(minLength: 1, maxLength: 80),
        'identity': <String, dynamic>{
          'type': 'OBJECT',
          'required': identityKeys.toList(growable: false),
          'properties': <String, dynamic>{
            'object': <String, dynamic>{
              'type': 'OBJECT',
              'required': objectKeys.toList(growable: false),
              'properties': <String, dynamic>{
                'label': _nullableString(maxLength: 100),
                'confidence': _confidence(),
              },
            },
            'manufacturer': <String, dynamic>{
              'type': 'OBJECT',
              'required': manufacturerKeys.toList(growable: false),
              'properties': <String, dynamic>{
                'value': _nullableString(maxLength: 80),
                'asserted': <String, dynamic>{'type': 'BOOLEAN'},
                'evidence': _enumString(manufacturerEvidence),
              },
            },
            'models': _array(
              maxItems: 16,
              items: <String, dynamic>{
                'type': 'OBJECT',
                'required': modelKeys.toList(growable: false),
                'properties': <String, dynamic>{
                  'code': _string(minLength: 1, maxLength: 60),
                  'role': _enumString(modelRoles),
                },
              },
            ),
            'specs': _array(
              maxItems: 32,
              items: <String, dynamic>{
                'type': 'OBJECT',
                'required': specKeys.toList(growable: false),
                'properties': <String, dynamic>{
                  'key': _string(minLength: 1, maxLength: 60),
                  'value': _string(minLength: 1, maxLength: 120),
                  'unit': _nullableString(maxLength: 24),
                  'source': _enumString(specSources),
                  'exclusive': <String, dynamic>{'type': 'BOOLEAN'},
                },
              },
            ),
            'fitment': _stringArray(maxItems: 24, maxLength: 240),
            'composition': <String, dynamic>{
              'type': 'OBJECT',
              'required': compositionKeys.toList(growable: false),
              'properties': <String, dynamic>{
                'kind': _enumString(compositionKinds),
                'components': _array(
                  maxItems: 16,
                  items: <String, dynamic>{
                    'type': 'OBJECT',
                    'required': componentKeys.toList(growable: false),
                    'properties': <String, dynamic>{
                      'label': _string(minLength: 1, maxLength: 100),
                      'role': _enumString(componentRoles),
                      'qty': <String, dynamic>{
                        'type': 'INTEGER',
                        'minimum': 1,
                        'maximum': 1000000,
                      },
                    },
                  },
                ),
              },
            },
            'packaging': <String, dynamic>{
              'type': 'OBJECT',
              'required': packagingKeys.toList(growable: false),
              'properties': <String, dynamic>{
                'count': <String, dynamic>{
                  'type': 'INTEGER',
                  'nullable': true,
                  'minimum': 1,
                  'maximum': 1000000,
                },
                'unit_token': _nullableString(maxLength: 40),
                'source': <String, dynamic>{
                  ..._enumString(specSources),
                  'nullable': true,
                },
              },
            },
            'leaf_proposals': _array(
              maxItems: 5,
              items: <String, dynamic>{
                'type': 'OBJECT',
                'required': leafProposalKeys.toList(growable: false),
                'properties': <String, dynamic>{
                  'category_id': <String, dynamic>{
                    'type': 'STRING',
                    'description': 'Must echo one category_id from the active '
                        'leaf list in the prompt. The client validates it.',
                  },
                  'confidence': _confidence(),
                  'basis': <String, dynamic>{
                    'type': 'ARRAY',
                    'minItems': 1,
                    'maxItems': leafBasis.length,
                    'items': _enumString(leafBasis),
                  },
                },
              },
            ),
            'evidence_used': _stringArray(maxItems: 24, maxLength: 2000),
            'abstain_reason': _nullableString(maxLength: 2000),
            'reason': _string(minLength: 1, maxLength: 2000),
          },
        },
        'vision': <String, dynamic>{
          'type': 'OBJECT',
          'required': visionKeys.toList(growable: false),
          'properties': <String, dynamic>{
            'primary_type': _string(maxLength: 100),
            'catalog_terms': _stringArray(maxItems: 16, maxLength: 100),
            'excluded_terms': _stringArray(maxItems: 16, maxLength: 100),
            'confidence': _confidence(),
            'visual_summary': _nullableString(maxLength: 500),
          },
        },
      },
    };
  }

  static AIProductIdentityValidationResult parseAndValidate({
    required String responseText,
    required String expectedPromptVersion,
    required String expectedModelId,
    required Set<String> offeredLeafIds,
  }) {
    final trimmed = responseText.trim();
    if (trimmed.isEmpty) {
      return const AIProductIdentityValidationResult.failed(
        AIProductIdentityFailure(
          failureStage: 'empty_response',
          jsonPointer: 'root',
          code: 'empty_response',
          retryable: true,
        ),
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(_extractJsonObjectText(trimmed) ?? trimmed);
    } on FormatException {
      return const AIProductIdentityValidationResult.failed(
        AIProductIdentityFailure(
          failureStage: 'json_parse',
          jsonPointer: 'root',
          code: 'invalid_json',
          retryable: true,
        ),
      );
    }
    if (decoded is! Map) {
      return const AIProductIdentityValidationResult.failed(
        AIProductIdentityFailure(
          failureStage: 'validation',
          jsonPointer: 'root',
          code: 'expected_object',
          retryable: true,
        ),
      );
    }

    final payload = Map<String, dynamic>.from(decoded);
    final normalizations = <Map<String, String>>[
      ..._normalizeLegacyInvestigationShape(payload),
      ..._normalizeManufacturerEvidence(payload),
      ..._normalizeEvidenceSources(payload),
      ..._normalizeDuplicateSpecs(payload),
    ];
    try {
      _validatePayload(
        payload,
        expectedPromptVersion: expectedPromptVersion,
        expectedModelId: expectedModelId,
        offeredLeafIds: offeredLeafIds,
      );
      return AIProductIdentityValidationResult.valid(
        payload,
        normalizations: normalizations,
      );
    } on _ContractViolation catch (failure) {
      return AIProductIdentityValidationResult.failed(
        AIProductIdentityFailure(
          failureStage: 'validation',
          jsonPointer: failure.pointer,
          code: failure.code,
          retryable: true,
        ),
      );
    }
  }

  static String? _extractJsonObjectText(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  /// Canonicalizes the two response layouts observed from the same Gemini
  /// model after its native response schema was rejected by the provider.
  ///
  /// The legacy layout puts the object card in `identity` and the remaining
  /// identity fields at the root. Moving existing values and supplying only
  /// neutral empty/null containers is a transport repair; it never invents a
  /// category, maker, model, specification, component or product id. The
  /// strict semantic validator still owns every invariant after this step.
  static List<Map<String, String>> _normalizeLegacyInvestigationShape(
    Map<String, dynamic> payload,
  ) {
    final rawIdentity = payload['identity'];
    if (rawIdentity is! Map) return const <Map<String, String>>[];
    final identity = Map<String, dynamic>.from(rawIdentity);
    if (identity['object'] is Map) return const <Map<String, String>>[];
    if (!identity.containsKey('label') && !identity.containsKey('confidence')) {
      return const <Map<String, String>>[];
    }

    final changes = <Map<String, String>>[];
    final canonical = <String, dynamic>{
      'object': <String, dynamic>{
        'label': identity['label'],
        'confidence': identity['confidence'],
      },
    };
    for (final key in identityKeys.where((key) => key != 'object')) {
      if (payload.containsKey(key)) {
        canonical[key] = payload.remove(key);
        changes.add(<String, String>{
          'pointer': 'identity.$key',
          'action': 'root_identity_field_nested',
        });
      }
    }

    // Neutral defaults preserve the absence of evidence. Affirmative identity
    // fields (composition and leaf proposals) are intentionally not invented.
    canonical.putIfAbsent(
      'manufacturer',
      () => <String, dynamic>{
        'value': null,
        'asserted': false,
        'evidence': 'none',
      },
    );
    canonical.putIfAbsent('models', () => <Object?>[]);
    canonical.putIfAbsent('specs', () => <Object?>[]);
    canonical.putIfAbsent('fitment', () => <Object?>[]);
    canonical.putIfAbsent(
      'packaging',
      () => <String, dynamic>{
        'count': null,
        'unit_token': null,
        'source': null,
      },
    );
    canonical.putIfAbsent('evidence_used', () => <Object?>[]);
    canonical.putIfAbsent('abstain_reason', () => null);
    payload['identity'] = canonical;
    changes.insert(0, <String, String>{
      'pointer': 'identity.object',
      'action': 'legacy_object_card_nested',
    });

    final rawVision = payload['vision'];
    if (rawVision is Map) {
      final vision = Map<String, dynamic>.from(rawVision);
      if (!vision.containsKey('catalog_terms')) {
        final terms = <String>[];
        for (final key in const <String>['sub_types', 'features']) {
          final values = vision[key];
          if (values is List) {
            for (final value in values.whereType<String>()) {
              final normalized = value.trim();
              if (normalized.isNotEmpty && !terms.contains(normalized)) {
                terms.add(normalized);
              }
            }
          }
        }
        vision['catalog_terms'] = terms.take(16).toList(growable: false);
      }
      vision.putIfAbsent('excluded_terms', () => <Object?>[]);
      vision.putIfAbsent('visual_summary', () => null);
      payload['vision'] = vision;
      changes.add(<String, String>{
        'pointer': 'vision',
        'action': 'legacy_vision_shape_normalized',
      });
    }

    return List<Map<String, String>>.unmodifiable(changes);
  }

  /// Normalizes provider vocabulary at the JSON transport boundary.
  ///
  /// Gemini is intentionally not trusted to reproduce internal enum spelling:
  /// it commonly says `image` for `photo`, `title` for `name`, or cites more
  /// than one source. Those are equivalent provenance labels, not identity
  /// contradictions. Unknown evidence still reaches the strict validator and
  /// fails closed. Product ids, category ids, quantities and all semantic
  /// invariants are untouched.
  static List<Map<String, String>> _normalizeEvidenceSources(
    Map<String, dynamic> payload,
  ) {
    final changes = <Map<String, String>>[];
    final identity = payload['identity'];
    if (identity is! Map) return changes;

    final specs = identity['specs'];
    if (specs is List) {
      for (var index = 0; index < specs.length; index++) {
        final spec = specs[index];
        if (spec is! Map) continue;
        _normalizeEvidenceSourceField(
          spec,
          'source',
          'identity.specs[$index].source',
          changes,
        );
      }
    }

    final packaging = identity['packaging'];
    if (packaging is Map && packaging['source'] != null) {
      _normalizeEvidenceSourceField(
        packaging,
        'source',
        'identity.packaging.source',
        changes,
      );
    }
    return List<Map<String, String>>.unmodifiable(changes);
  }

  /// Manufacturer evidence describes the semantic role of the maker mention,
  /// not the media channel where it was read. Providers often return `photo`
  /// or `name` here even though both mean a direct identity assertion. Convert
  /// only known equivalent vocabulary; assertion contradictions remain for
  /// the strict validator to reject.
  static List<Map<String, String>> _normalizeManufacturerEvidence(
    Map<String, dynamic> payload,
  ) {
    final identity = payload['identity'];
    if (identity is! Map) return const <Map<String, String>>[];
    final manufacturer = identity['manufacturer'];
    if (manufacturer is! Map) return const <Map<String, String>>[];
    final raw = manufacturer['evidence'];
    if (raw is! String) return const <Map<String, String>>[];
    final token = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    final canonical = switch (token) {
      'identity' => 'identity',
      'direct' ||
      'manufacturer' ||
      'maker' ||
      'brand' ||
      'logo' ||
      'name' ||
      'title' ||
      'option' ||
      'photo' ||
      'image' ||
      'visual' ||
      'text' ||
      'source' =>
        'identity',
      'compatibility' ||
      'compatible' ||
      'fitment' ||
      'mentioned' ||
      'reference' =>
        'compatibility',
      'none' ||
      'unknown' ||
      'insufficient' ||
      'absent' ||
      'not_found' ||
      'null' =>
        'none',
      _ => null,
    };
    if (canonical == null || canonical == raw) {
      return const <Map<String, String>>[];
    }
    manufacturer['evidence'] = canonical;
    return <Map<String, String>>[
      <String, String>{
        'pointer': 'identity.manufacturer.evidence',
        'action': 'manufacturer_evidence_role_normalized',
        'from': raw,
        'to': canonical,
      },
    ];
  }

  static void _normalizeEvidenceSourceField(
    Map<dynamic, dynamic> owner,
    String key,
    String pointer,
    List<Map<String, String>> changes,
  ) {
    final raw = owner[key];
    final canonical = _canonicalEvidenceSource(raw);
    if (canonical == null || raw == canonical) return;
    owner[key] = canonical;
    changes.add(<String, String>{
      'pointer': pointer,
      'from': raw is List ? raw.join('|') : '$raw',
      'to': canonical,
    });
  }

  static String? _canonicalEvidenceSource(Object? value) {
    final rawValues = switch (value) {
      String text => text.split(RegExp(r'\s*(?:\+|/|,|&|\||\band\b|\by\b)\s*')),
      List values => values.whereType<String>().toList(growable: false),
      _ => const <String>[],
    };
    if (rawValues.isEmpty) return null;

    final found = <String>{};
    for (final raw in rawValues) {
      final token = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
      final canonical = switch (token) {
        'option' ||
        'variant' ||
        'selected_option' ||
        'selected_variant' ||
        'purchased_option' =>
          'option',
        'photo' || 'image' || 'visual' || 'picture' => 'photo',
        'name' ||
        'title' ||
        'supplier_title' ||
        'original_title' ||
        'original_supplier_title' ||
        'line_title' =>
          'name',
        'body' ||
        'context' ||
        'description' ||
        'listing_body' ||
        'line_context' =>
          'body',
        _ => null,
      };
      if (canonical != null) found.add(canonical);
    }
    if (found.isEmpty) return null;
    // Preserve the strongest direct source when the provider cites several.
    for (final candidate in const <String>['option', 'name', 'body', 'photo']) {
      if (found.contains(candidate)) return candidate;
    }
    return null;
  }

  /// Reconciles a provider response that repeats a specification key.
  ///
  /// A duplicate key is a transport-shape defect, not enough reason to throw
  /// away an otherwise grounded multimodal reading. Evidence authority is
  /// deterministic: selected option > supplier name > listing body > photo.
  /// Lower-authority contradictions are discarded. Distinct values asserted
  /// by the same strongest source are retained under stable detail keys, but
  /// made non-exclusive because the current schema cannot prove whether they
  /// describe different sub-parts (for example frame and lens colour). This
  /// keeps all useful evidence for the adjudicator without manufacturing a
  /// hard catalog gate.
  static List<Map<String, String>> _normalizeDuplicateSpecs(
    Map<String, dynamic> payload,
  ) {
    final changes = <Map<String, String>>[];
    final identity = payload['identity'];
    if (identity is! Map) return changes;
    final rawSpecs = identity['specs'];
    if (rawSpecs is! List || rawSpecs.length < 2) return changes;

    String canonicalKey(Object? value) => value is String
        ? value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '_')
        : '';
    String canonicalValue(Object? value) => value is String
        ? value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')
        : '';
    int sourceRank(Object? value) => switch (value) {
          'option' => 4,
          'name' => 3,
          'body' => 2,
          'photo' => 1,
          _ => 0,
        };

    final rebuilt = <Object?>[];
    final handledKeys = <String>{};
    for (final rawSpec in rawSpecs) {
      if (rawSpec is! Map) {
        rebuilt.add(rawSpec);
        continue;
      }
      final key = canonicalKey(rawSpec['key']);
      if (key.isEmpty) {
        rebuilt.add(rawSpec);
        continue;
      }
      if (!handledKeys.add(key)) continue;

      final group = <Map<dynamic, dynamic>>[
        for (final candidate in rawSpecs)
          if (candidate is Map && canonicalKey(candidate['key']) == key)
            candidate,
      ];
      if (group.length == 1) {
        rebuilt.add(rawSpec);
        continue;
      }

      final strongestRank = group
          .map((item) => sourceRank(item['source']))
          .reduce((left, right) => left > right ? left : right);
      final strongest = group
          .where((item) => sourceRank(item['source']) == strongestRank)
          .toList(growable: false);
      final uniqueStrongest = <String, Map<dynamic, dynamic>>{};
      for (final item in strongest) {
        final signature = '${canonicalValue(item['value'])}|'
            '${canonicalValue(item['unit'])}';
        uniqueStrongest.putIfAbsent(signature, () => item);
      }

      final normalized = <Map<String, dynamic>>[];
      var detailIndex = 0;
      for (final item in uniqueStrongest.values) {
        detailIndex += 1;
        final copy = Map<String, dynamic>.from(item);
        if (uniqueStrongest.length == 1) {
          copy['exclusive'] = strongest.any(
            (candidate) => candidate['exclusive'] == true,
          );
        } else {
          final originalKey = '${item['key']}'.trim();
          final suffix = detailIndex == 1 ? '' : '_detail_$detailIndex';
          final maxBaseLength = 60 - suffix.length;
          final safeBase = originalKey.length <= maxBaseLength
              ? originalKey
              : originalKey.substring(0, maxBaseLength);
          copy['key'] = '$safeBase$suffix';
          copy['exclusive'] = false;
        }
        normalized.add(copy);
        rebuilt.add(copy);
      }

      changes.add(<String, String>{
        'pointer': 'identity.specs',
        'action': uniqueStrongest.length == 1
            ? 'duplicate_spec_merged'
            : 'same_authority_specs_preserved_non_exclusive',
        'from': jsonEncode(<Map<String, Object?>>[
          for (final item in group)
            <String, Object?>{
              'key': item['key'],
              'value': item['value'],
              'unit': item['unit'],
              'source': item['source'],
              'exclusive': item['exclusive'],
            },
        ]),
        'to': jsonEncode(normalized),
      });
    }
    identity['specs'] = rebuilt;
    return List<Map<String, String>>.unmodifiable(changes);
  }

  static void _validatePayload(
    Map<String, dynamic> root, {
    required String expectedPromptVersion,
    required String expectedModelId,
    required Set<String> offeredLeafIds,
  }) {
    _required(root, rootKeys, 'root');
    _exactString(root, 'schema_version', schemaVersion, 'root');
    _exactString(root, 'prompt_version', expectedPromptVersion, 'root');
    _exactString(root, 'model_id', expectedModelId, 'root');
    _text(root['cleaned_name'], 'root.cleaned_name', maxLength: 80);

    final identity = _map(root['identity'], 'root.identity');
    _required(identity, identityKeys, 'identity');

    final object = _map(identity['object'], 'identity.object');
    _required(object, objectKeys, 'identity.object');
    _nullableText(object['label'], 'identity.object.label', maxLength: 100);
    _unitConfidence(object['confidence'], 'identity.object.confidence');

    final manufacturer =
        _map(identity['manufacturer'], 'identity.manufacturer');
    _required(manufacturer, manufacturerKeys, 'identity.manufacturer');
    final manufacturerValue = _nullableText(
      manufacturer['value'],
      'identity.manufacturer.value',
      maxLength: 80,
    );
    final asserted = _boolean(
      manufacturer['asserted'],
      'identity.manufacturer.asserted',
    );
    final evidence = _enum(
      manufacturer['evidence'],
      manufacturerEvidence,
      'identity.manufacturer.evidence',
    );
    if (asserted && (manufacturerValue == null || evidence != 'identity')) {
      _violate('identity.manufacturer.evidence', 'assertion_contradiction');
    }
    if (!asserted && evidence == 'identity') {
      _violate('identity.manufacturer.asserted', 'assertion_contradiction');
    }
    if (evidence == 'none' && manufacturerValue != null) {
      _violate('identity.manufacturer.value', 'evidence_contradiction');
    }

    final models = _list(identity['models'], 'identity.models', maxItems: 16);
    final seenModels = <String>{};
    for (var index = 0; index < models.length; index++) {
      final path = 'identity.models[$index]';
      final model = _map(models[index], path);
      _required(model, modelKeys, path);
      final code = _text(model['code'], '$path.code', maxLength: 60);
      final role = _enum(model['role'], modelRoles, '$path.role');
      if (!seenModels.add('$role:${code.toLowerCase()}')) {
        _violate('$path.code', 'duplicate_value');
      }
    }

    final specs = _list(identity['specs'], 'identity.specs', maxItems: 32);
    final seenSpecs = <String>{};
    for (var index = 0; index < specs.length; index++) {
      final path = 'identity.specs[$index]';
      final spec = _map(specs[index], path);
      _required(spec, specKeys, path);
      final key = _text(spec['key'], '$path.key', maxLength: 60);
      _text(spec['value'], '$path.value', maxLength: 120);
      _nullableText(spec['unit'], '$path.unit', maxLength: 24);
      _enum(spec['source'], specSources, '$path.source');
      _boolean(spec['exclusive'], '$path.exclusive');
      if (!seenSpecs.add(key.toLowerCase())) {
        _violate('$path.key', 'duplicate_value');
      }
    }

    _uniqueTextList(
      identity['fitment'],
      'identity.fitment',
      maxItems: 24,
      maxLength: 240,
      allowNewlines: true,
    );
    _uniqueTextList(
      identity['evidence_used'],
      'identity.evidence_used',
      maxItems: 24,
      maxLength: 2000,
      allowNewlines: true,
    );

    final composition = _map(identity['composition'], 'identity.composition');
    _required(composition, compositionKeys, 'identity.composition');
    final kind = _enum(
      composition['kind'],
      compositionKinds,
      'identity.composition.kind',
    );
    final components = _list(
      composition['components'],
      'identity.composition.components',
      maxItems: 16,
    );
    final quantities = <int>[];
    final roles = <String>[];
    for (var index = 0; index < components.length; index++) {
      final path = 'identity.composition.components[$index]';
      final component = _map(components[index], path);
      _required(component, componentKeys, path);
      _text(component['label'], '$path.label', maxLength: 100);
      roles.add(_enum(
        component['role'],
        componentRoles,
        '$path.role',
      ));
      quantities.add(_integer(
        component['qty'],
        '$path.qty',
        minimum: 1,
        maximum: 1000000,
      ));
    }
    final inventoryIndexes = <int>[
      for (var index = 0; index < roles.length; index++)
        if (roles[index] != 'included_accessory') index,
    ];
    final inventoryQuantity = inventoryIndexes.fold<int>(
      0,
      (total, index) => total + quantities[index],
    );
    // Included subordinate hardware is preserved as evidence but never turns
    // a single catalog identity into a composite resolution.
    if (kind == 'single' &&
        (inventoryIndexes.length > 1 ||
            (inventoryIndexes.length == 1 &&
                (roles[inventoryIndexes.single] != 'primary' ||
                    quantities[inventoryIndexes.single] != 1)))) {
      _violate('identity.composition.components', 'single_cardinality');
    }
    if (kind == 'composite' && inventoryQuantity < 2) {
      _violate('identity.composition.components', 'composite_cardinality');
    }
    if (kind == 'insufficient' && components.isNotEmpty) {
      _violate('identity.composition.components', 'insufficient_cardinality');
    }

    final packaging = _map(identity['packaging'], 'identity.packaging');
    _required(packaging, packagingKeys, 'identity.packaging');
    final count = packaging['count'] == null
        ? null
        : _integer(
            packaging['count'],
            'identity.packaging.count',
            minimum: 1,
            maximum: 1000000,
          );
    final unitToken = _nullableText(
      packaging['unit_token'],
      'identity.packaging.unit_token',
      maxLength: 40,
    );
    final source = packaging['source'] == null
        ? null
        : _enum(
            packaging['source'],
            specSources,
            'identity.packaging.source',
          );
    if ((count == null) != (unitToken == null) ||
        (count != null && source == null) ||
        (count == null && source != null)) {
      _violate('identity.packaging', 'packaging_contradiction');
    }

    final proposals = _list(
      identity['leaf_proposals'],
      'identity.leaf_proposals',
      maxItems: 5,
    );
    final seenLeafIds = <String>{};
    for (var index = 0; index < proposals.length; index++) {
      final path = 'identity.leaf_proposals[$index]';
      final proposal = _map(proposals[index], path);
      _required(proposal, leafProposalKeys, path);
      final categoryId =
          _text(proposal['category_id'], '$path.category_id', maxLength: 160);
      if (!offeredLeafIds.contains(categoryId)) {
        _violate('$path.category_id', 'unoffered_leaf_id');
      }
      if (!seenLeafIds.add(categoryId)) {
        _violate('$path.category_id', 'duplicate_value');
      }
      _unitConfidence(proposal['confidence'], '$path.confidence');
      final basis = _list(
        proposal['basis'],
        '$path.basis',
        minItems: 1,
        maxItems: leafBasis.length,
      );
      final seenBasis = <String>{};
      for (var basisIndex = 0; basisIndex < basis.length; basisIndex++) {
        final value = _enum(
          basis[basisIndex],
          leafBasis,
          '$path.basis[$basisIndex]',
        );
        if (!seenBasis.add(value)) {
          _violate('$path.basis[$basisIndex]', 'duplicate_value');
        }
      }
    }

    final abstainReason = _nullableText(
      identity['abstain_reason'],
      'identity.abstain_reason',
      maxLength: 2000,
      allowNewlines: true,
    );
    _text(
      identity['reason'],
      'identity.reason',
      maxLength: 2000,
      allowNewlines: true,
    );
    final objectLabel = object['label'] as String?;
    if (kind == 'insufficient' && abstainReason == null) {
      _violate('identity.abstain_reason', 'missing_abstain_reason');
    }
    if (kind != 'insufficient' &&
        (abstainReason != null || objectLabel == null || proposals.isEmpty)) {
      _violate('identity', 'sufficient_identity_contradiction');
    }

    final vision = _map(root['vision'], 'root.vision');
    _required(vision, visionKeys, 'vision');
    _text(
      vision['primary_type'],
      'vision.primary_type',
      maxLength: 100,
      allowEmpty: true,
    );
    _uniqueTextList(
      vision['catalog_terms'],
      'vision.catalog_terms',
      maxItems: 16,
      maxLength: 100,
    );
    _uniqueTextList(
      vision['excluded_terms'],
      'vision.excluded_terms',
      maxItems: 16,
      maxLength: 100,
    );
    _unitConfidence(vision['confidence'], 'vision.confidence');
    _nullableText(
      vision['visual_summary'],
      'vision.visual_summary',
      maxLength: 500,
      allowNewlines: true,
    );
  }

  /// A value-free description safe for logs. It contains only recognized key
  /// names, safe extra key names, JSON types, and collection sizes.
  static Map<String, Object?> redactedShape(Object? decoded) {
    final result = <String, Object?>{'root_type': _typeName(decoded)};
    if (decoded is! Map) return result;
    final root = Map<Object?, Object?>.from(decoded);
    result['root_keys'] = _keyTypes(root);
    final identity = root['identity'];
    if (identity is Map) {
      result['identity_keys'] = _keyTypes(identity);
      for (final key in <String>['reason', 'abstain_reason']) {
        final value = identity[key];
        if (value is String) {
          result['identity.$key.length'] = value.length;
        }
      }
      for (final key in <String>[
        'object',
        'manufacturer',
        'composition',
        'packaging',
      ]) {
        final nested = identity[key];
        if (nested is Map) result['identity.$key.keys'] = _keyTypes(nested);
      }
      for (final key in <String>[
        'models',
        'specs',
        'leaf_proposals',
      ]) {
        final nested = identity[key];
        if (nested is List) {
          result['identity.$key.length'] = nested.length;
          if (nested.isNotEmpty && nested.first is Map) {
            result['identity.$key.item_keys'] = _keyTypes(nested.first as Map);
          }
        }
      }
      final composition = identity['composition'];
      if (composition is Map && composition['components'] is List) {
        final components = composition['components'] as List;
        result['identity.composition.components.length'] = components.length;
        if (components.isNotEmpty && components.first is Map) {
          result['identity.composition.components.item_keys'] =
              _keyTypes(components.first as Map);
        }
      }
    }
    final vision = root['vision'];
    if (vision is Map) result['vision_keys'] = _keyTypes(vision);
    return result;
  }

  static Map<String, String> _keyTypes(Map values) {
    final entries = <String, String>{};
    for (final entry in values.entries) {
      final rawKey = entry.key.toString();
      final safeKey = RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(rawKey)
          ? rawKey
          : '<redacted-key>';
      entries[safeKey] = _typeName(entry.value);
    }
    return entries;
  }

  static String _typeName(Object? value) => switch (value) {
        null => 'null',
        bool _ => 'boolean',
        int _ => 'integer',
        num _ => 'number',
        String _ => 'string',
        List _ => 'array',
        Map _ => 'object',
        _ => 'unknown',
      };

  static Map<String, dynamic> _constantString(String value) =>
      <String, dynamic>{
        'type': 'STRING',
        'enum': <String>[value]
      };

  static Map<String, dynamic> _enumString(Iterable<String> values) =>
      <String, dynamic>{
        'type': 'STRING',
        'enum': values.toList(growable: false)..sort(),
      };

  static Map<String, dynamic> _string({
    int? minLength,
    required int maxLength,
  }) =>
      <String, dynamic>{
        'type': 'STRING',
        'description': minLength == null
            ? 'Client validated string, maximum $maxLength characters.'
            : 'Client validated string, $minLength-$maxLength characters.',
      };

  static Map<String, dynamic> _nullableString({required int maxLength}) =>
      <String, dynamic>{
        'type': 'STRING',
        'nullable': true,
        'description':
            'Null or client validated string, maximum $maxLength characters.',
      };

  static Map<String, dynamic> _confidence() => <String, dynamic>{
        'type': 'NUMBER',
        'minimum': 0,
        'maximum': 1,
      };

  static Map<String, dynamic> _array({
    int minItems = 0,
    required int maxItems,
    required Map<String, dynamic> items,
  }) =>
      <String, dynamic>{
        'type': 'ARRAY',
        // Gemini's legacy OpenAPI Schema wire contract represents int64
        // bounds as JSON strings. Sending Dart integers makes the provider
        // reject the complete responseSchema before model generation.
        'minItems': '$minItems',
        'maxItems': '$maxItems',
        'items': items,
      };

  static Map<String, dynamic> _stringArray({
    required int maxItems,
    required int maxLength,
  }) =>
      _array(
        maxItems: maxItems,
        items: _string(minLength: 1, maxLength: maxLength),
      );

  static void _required(Map map, Set<String> keys, String path) {
    for (final key in keys) {
      if (!map.containsKey(key)) _violate('$path.$key', 'missing_required');
    }
  }

  static Map<String, dynamic> _map(Object? value, String path) {
    if (value is! Map) _violate(path, 'expected_object');
    return Map<String, dynamic>.from(value);
  }

  static List<Object?> _list(
    Object? value,
    String path, {
    int minItems = 0,
    required int maxItems,
  }) {
    if (value is! List) _violate(path, 'expected_array');
    final list = value;
    if (list.length < minItems || list.length > maxItems) {
      _violate(path, 'invalid_array_length');
    }
    return List<Object?>.from(list);
  }

  static String _text(
    Object? value,
    String path, {
    required int maxLength,
    bool allowEmpty = false,
    bool allowNewlines = false,
  }) {
    if (value is! String) _violate(path, 'expected_string');
    final text = value.trim();
    if ((!allowEmpty && text.isEmpty) ||
        text.length > maxLength ||
        (!allowNewlines && (text.contains('\n') || text.contains('\r')))) {
      _violate(path, 'invalid_string');
    }
    return text;
  }

  static String? _nullableText(
    Object? value,
    String path, {
    required int maxLength,
    bool allowNewlines = false,
  }) {
    if (value == null) return null;
    return _text(
      value,
      path,
      maxLength: maxLength,
      allowNewlines: allowNewlines,
    );
  }

  static bool _boolean(Object? value, String path) {
    if (value is! bool) _violate(path, 'expected_boolean');
    return value;
  }

  static String _enum(Object? value, Set<String> allowed, String path) {
    if (value is! String || !allowed.contains(value)) {
      _violate(path, 'invalid_enum');
    }
    return value;
  }

  static double _unitConfidence(Object? value, String path) {
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      _violate(path, 'invalid_confidence');
    }
    return value.toDouble();
  }

  static int _integer(
    Object? value,
    String path, {
    required int minimum,
    required int maximum,
  }) {
    if (value is! num ||
        !value.isFinite ||
        value != value.toInt() ||
        value < minimum ||
        value > maximum) {
      _violate(path, 'invalid_integer');
    }
    return value.toInt();
  }

  static List<String> _uniqueTextList(
    Object? value,
    String path, {
    required int maxItems,
    required int maxLength,
    bool allowNewlines = false,
  }) {
    final list = _list(value, path, maxItems: maxItems);
    final result = <String>[];
    final seen = <String>{};
    for (var index = 0; index < list.length; index++) {
      final text = _text(
        list[index],
        '$path[$index]',
        maxLength: maxLength,
        allowNewlines: allowNewlines,
      );
      if (!seen.add(text)) _violate('$path[$index]', 'duplicate_value');
      result.add(text);
    }
    return result;
  }

  static void _exactString(
    Map<String, dynamic> map,
    String key,
    String expected,
    String path,
  ) {
    if (map[key] is! String || map[key] != expected) {
      _violate('$path.$key', 'version_mismatch');
    }
  }

  static Never _violate(String pointer, String code) {
    throw _ContractViolation(pointer, code);
  }
}

class AIProductIdentityValidationResult {
  const AIProductIdentityValidationResult._({
    this.payload,
    this.failure,
    this.normalizations = const <Map<String, String>>[],
  });

  factory AIProductIdentityValidationResult.valid(Map<String, dynamic> payload,
          {List<Map<String, String>> normalizations =
              const <Map<String, String>>[]}) =>
      AIProductIdentityValidationResult._(
        payload: Map<String, dynamic>.unmodifiable(payload),
        normalizations: List<Map<String, String>>.unmodifiable(
          normalizations.map(Map<String, String>.unmodifiable),
        ),
      );

  const factory AIProductIdentityValidationResult.failed(
    AIProductIdentityFailure failure,
  ) = _FailedAIProductIdentityValidationResult;

  final Map<String, dynamic>? payload;
  final AIProductIdentityFailure? failure;
  final List<Map<String, String>> normalizations;

  bool get isValid => payload != null && failure == null;
}

class _FailedAIProductIdentityValidationResult
    extends AIProductIdentityValidationResult {
  const _FailedAIProductIdentityValidationResult(
    AIProductIdentityFailure failure,
  ) : super._(failure: failure);
}

class AIProductIdentityFailure {
  const AIProductIdentityFailure({
    required this.failureStage,
    required this.jsonPointer,
    required this.code,
    required this.retryable,
    this.providerStatus,
    this.providerCode,
  });

  final String failureStage;
  final String jsonPointer;
  final String code;
  final bool retryable;
  final int? providerStatus;
  final String? providerCode;

  String get operatorMessage =>
      'Falló la investigación IA ($failureStage: $jsonPointer). '
      'La fila se mantuvo sin recomendación y se puede reintentar.';

  Map<String, Object?> toRedactedJson() => <String, Object?>{
        'failure_stage': failureStage,
        'json_pointer': jsonPointer,
        'code': code,
        'retryable': retryable,
        if (providerStatus != null) 'provider_status': providerStatus,
        if (providerCode != null) 'provider_code': providerCode,
      };
}

class _ContractViolation implements Exception {
  const _ContractViolation(this.pointer, this.code);

  final String pointer;
  final String code;
}
