import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

// Replays two captured model answers, not fresh network calls. The final model
// text and the supplier rows both came from the real app / stored receipt.
class _CapturedProxy extends Fake implements GeminiProxyService {
  _CapturedProxy(this.reading);
  final Map<String, dynamic> reading;

  @override
  Future<String> generateText({
    required String prompt,
    required String model,
  }) async {
    expect(model, reading['model']);
    expect(prompt, contains('Shimano BR-MT200'));
    return reading['text'] as String;
  }
}

Map<String, dynamic> _fixture(String name) => jsonDecode(
      File('test/fixtures/purchasing/$name').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  setUp(() {
    resetSupplyNeedCriteriaSpansCache();
    resetSupplyNeedRequirementDiscoveryCache();
  });

  test('las respuestas reales de IA conservan compatibilidad y refiltrado',
      () async {
    final receipt = _fixture('purchasing-holdout-rbx-original-receipt.json');
    final recorded = _fixture('br_mt200_live_model_readings_20260831.json');
    final readings = (recorded['readings'] as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final request = receipt['request'] as Map<String, dynamic>;
    final fields = (receipt['fields'] as List).map((raw) {
      final field = Map<String, dynamic>.from(raw as Map);
      return SupplierNeedSearchField(
        key: field['key'] as String,
        label: field['label'] as String,
        dataType: field['data_type'] as String,
        unit: field['unit'] as String?,
        description: field['description'] as String?,
        allowedValues: (field['allowed_values'] as List).cast<Object>(),
        validationRules:
            Map<String, Object?>.from(field['validation_rules'] as Map),
        isRequired: field['is_required'] == true,
      );
    }).toList();
    final predicates = (request['predicates'] as List)
        .map((raw) => SupplierNeedSearchPredicate(
              field: raw['field'] as String,
              operator: raw['operator'] as String,
              values: (raw['values'] as List).cast<Object>(),
            ))
        .toList();
    final asked = <String, List<Object>>{
      for (final predicate in predicates) predicate.field: predicate.values,
    };
    final description = request['description'] as String;
    final spans = await readSupplyNeedCriteriaSpansWithModel(
      requestText: description,
      fields: fields,
      askedValues: asked,
      extractor:
          geminiSupplierSpecExtractor(service: _CapturedProxy(readings[0])),
    );
    final discovered = await readSupplyNeedRequirementsWithModel(
      requestText: description,
      fields: fields,
      askedValues: asked,
      extractor:
          geminiSupplierSpecExtractor(service: _CapturedProxy(readings[1])),
    );
    expect(spans.spans, contains('resina'));
    expect(spans.spans, contains('sin aletas de refrigeración'));
    expect(discovered, isEmpty);
    final plan = buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: receipt['source']['needId'] as String,
        description: description,
        categoryId: request['categoryId'] as String,
        categoryPath: request['categoryPath'] as String,
        technicalFamily: request['technicalFamily'] as String,
        fields: fields,
        predicates: predicates,
        criteriaSpans: spans.spans,
        discoveredRequirements: discovered,
      ),
      adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
        'version': 1,
        'generic_family_search': true,
        'result_schema': <String, dynamic>{},
      }),
      maxLength: 40,
    )!;
    final candidates = (receipt['matches'] as List)
        .map((raw) => SupplierPortalCatalogCandidate.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ))
        .toList();
    final matches = matchSupplierNeedCandidates(plan, candidates);
    expect(matches, hasLength(10));
    for (final row in matches) {
      expect(row.state, isNot(SupplierNeedMatchState.exact));
      expect(row.missingFields, contains(kCompatibilityRequirementField),
          reason: '${row.candidate.code} no demuestra BR-MT200; la cita '
              'amplia de Shimano no puede borrar esa compatibilidad');
    }
    List<SupplierNeedMatchVerdict> preview(
            List<SupplierNeedSearchPredicate> criteria) =>
        judgeSupplierNeedMatchesUnder(
          matches: matches,
          predicates: criteria,
          fields: fields,
        );
    final original = preview(predicates);
    final tektro = preview(<SupplierNeedSearchPredicate>[
      for (final predicate in predicates)
        if (predicate.field == 'brake_system')
          const SupplierNeedSearchPredicate(
              field: 'brake_system', operator: 'eq', values: <Object>['Tektro'])
        else
          predicate,
    ]);
    final noSystem = preview(predicates
        .where((predicate) => predicate.field != 'brake_system')
        .toList());
    expect(original, hasLength(9));
    expect(tektro.map((row) => row.match.candidate.code).toSet(), <String>{
      '17977',
      '10587',
      '2005',
      '8479',
      '14176',
      '10679',
      '10684',
      '16403',
    });
    expect(noSystem, hasLength(10));
    for (final view in <List<SupplierNeedMatchVerdict>>[
      original,
      tektro,
      noSystem,
    ]) {
      expect(view.where((row) => row.isConfirmed), isEmpty);
    }
  });
}
