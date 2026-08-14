import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const runtimeTools = <String>{
    'get_business_snapshot',
    'list_attention_items',
    'search_workshop_jobs',
    'get_workshop_job_context',
    'inspect_diagnosis_schema',
    'search_tasks',
    'inspect_inventory_schema',
    'search_inventory',
    'report_capability_gap',
    'find_inventory_risks',
    'search_customers',
    'search_suppliers',
    'search_sales_invoices',
    'search_purchase_invoices',
    'analyze_cash_and_receivables',
    'analyze_sales_period',
    'list_recent_expenses',
    'search_conversations',
    'research_public_web',
    'prepare_task',
    'prepare_diagnosis_update',
    'prepare_workshop_item',
  };
  const outcomes = <String>{
    'answer',
    'partial',
    'verifiedEmpty',
    'capabilityLimit',
    'approvalRequired',
    'denied',
    'timeout',
    'cancelled',
  };
  const mutations = <String>{'none', 'draft', 'reversible', 'sensitive'};
  const navigation = <String>{'none', 'cardOnly'};
  const dispatches = <String>{'model', 'approvalEndpoint'};

  test('agent evaluation dataset is fixed, closed and representative', () {
    final file = File('test/fixtures/ai_assistant_agent_eval_cases.json');
    final decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<List<Object?>>());
    final cases = (decoded as List<Object?>).cast<Map<String, Object?>>();

    expect(cases, hasLength(65));
    expect(cases.map((item) => item['id']).toSet(), hasLength(cases.length));

    final categories = <String>{};
    final scenarios = <String>{};
    final observedOutcomes = <String>{};
    final observedMutations = <String>{};

    for (final item in cases) {
      final id = item['id'];
      final category = item['category'];
      final prompt = item['prompt'];
      final scenario = item['scenario'];
      final expected = item['expected'];

      expect(id, isA<String>().having((value) => value, 'id', isNotEmpty));
      expect(
        category,
        isA<String>().having((value) => value, 'category', isNotEmpty),
        reason: '$id must declare a category',
      );
      expect(
        prompt,
        isA<String>()
            .having((value) => value.trim(), 'prompt', isNotEmpty)
            .having((value) => utf8.encode(value).length, 'UTF-8 bytes',
                lessThanOrEqualTo(8192)),
        reason: '$id must stay inside the runtime input budget',
      );
      expect(
        scenario,
        isA<String>().having((value) => value, 'scenario', isNotEmpty),
        reason: '$id must name its fixture scenario',
      );
      expect(expected, isA<Map<String, Object?>>(), reason: '$id expected');

      final contract = expected! as Map<String, Object?>;
      final tools = (contract['tools']! as List<Object?>).cast<String>();
      final dispatch = contract['dispatch'] ?? 'model';
      expect(
        tools.where((tool) => !runtimeTools.contains(tool)),
        isEmpty,
        reason: '$id references a tool absent from the runtime registry',
      );
      expect(outcomes, contains(contract['outcome']), reason: '$id outcome');
      expect(dispatches, contains(dispatch), reason: '$id dispatch');
      if (dispatch == 'model') {
        expect(
          contract['modelAllowed'],
          isTrue,
          reason:
              '$id must stay model-first; deterministic intent handlers are not production dispatch',
        );
      } else {
        expect(id, 'reliability-004', reason: '$id direct dispatch is closed');
        expect(contract['modelAllowed'], isFalse,
            reason: '$id post-click action must bypass the model');
        expect(tools, isEmpty,
            reason: '$id direct approval replay cannot invoke provider tools');
      }
      expect(
        mutations,
        contains(contract['mutation']),
        reason: '$id mutation contract',
      );
      expect(
        navigation,
        contains(contract['navigation']),
        reason: '$id navigation contract',
      );
      expect(contract['citations'], isA<bool>(), reason: '$id citations');

      categories.add(category! as String);
      scenarios.add(scenario! as String);
      observedOutcomes.add(contract['outcome']! as String);
      observedMutations.add(contract['mutation']! as String);
    }

    expect(
      categories,
      containsAll(<String>{
        'briefing',
        'workshop',
        'tasks',
        'inventory',
        'capability',
        'crm',
        'purchases',
        'sales',
        'finance',
        'messaging',
        'browser',
        'authority',
        'reliability',
      }),
    );
    expect(observedOutcomes, containsAll(outcomes));
    expect(observedMutations, containsAll(mutations));
    expect(
      scenarios.where(
        (scenario) =>
            scenario.contains('tenant') ||
            scenario.contains('permission') ||
            scenario.contains('injection') ||
            scenario.contains('fabricated'),
      ),
      hasLength(greaterThanOrEqualTo(6)),
    );
  });

  test('inventory evals cover the basic typed query algebra', () {
    final decoded = jsonDecode(
      File('test/fixtures/ai_assistant_agent_eval_cases.json')
          .readAsStringSync(),
    ) as List<Object?>;
    final cases = <String, Map<String, Object?>>{
      for (final value in decoded)
        (value as Map<String, Object?>)['id']! as String: value,
    };
    expect(cases['inventory-009']!['scenario'], 'typed_operational_threshold');
    expect(cases['inventory-010']!['scenario'], 'typed_operational_range');
    expect(cases['inventory-011']!['scenario'], 'typed_sort_top_n');
    expect(cases['inventory-012']!['scenario'], 'verified_full_set_metrics');
    expect(
      (cases['inventory-013']!['expected']! as Map<String, Object?>)['tools'],
      <String>['report_capability_gap'],
      reason: 'unsupported grouped aggregation must be declared, not simulated',
    );
  });

  test('general named-source web research stays model-first', () {
    final decoded = jsonDecode(
      File('test/fixtures/ai_assistant_agent_eval_cases.json')
          .readAsStringSync(),
    ) as List<Object?>;
    final reddit = decoded.cast<Map<String, Object?>>().singleWhere(
          (item) => item['id'] == 'browser-007',
        );
    expect(
      reddit['prompt'],
      'segun reddit, cual es la mejor forma de evitar pinchazos de rueda?',
    );
    final expected = reddit['expected']! as Map<String, Object?>;
    expect(expected['tools'], <String>['research_public_web']);
    expect(expected['citations'], isTrue);
    expect(expected['modelAllowed'], isTrue);
    expect(expected.containsKey('dispatch'), isFalse,
        reason: 'natural forum research cannot introduce phrase dispatch');
  });

  test('task commit stays outside the model tool surface', () {
    final decoded = jsonDecode(
      File('test/fixtures/ai_assistant_agent_eval_cases.json')
          .readAsStringSync(),
    ) as List<Object?>;
    final cases = <String, Map<String, Object?>>{
      for (final value in decoded)
        (value as Map<String, Object?>)['id']! as String: value,
    };
    final task = cases['tasks-004']!['expected']! as Map<String, Object?>;
    expect(task['tools'], <String>['prepare_task']);
    expect(task['outcome'], 'approvalRequired');
    expect(task['mutation'], 'draft');
    expect(task['navigation'], 'cardOnly');

    final retry =
        cases['reliability-004']!['expected']! as Map<String, Object?>;
    expect(retry['dispatch'], 'approvalEndpoint');
    expect(retry['modelAllowed'], isFalse);
    expect(retry['tools'], isEmpty);
    expect(retry['outcome'], 'answer');
    expect(retry['mutation'], 'reversible');
    expect(retry['navigation'], 'cardOnly');

    for (final value in decoded) {
      final expected =
          (value as Map<String, Object?>)['expected']! as Map<String, Object?>;
      expect(expected['tools'], isNot(contains('create_task')),
          reason: '${value['id']} must not expose create_task to the model');
    }
  });

  test('action evals resolve entities and schemas before preparing writes', () {
    final decoded = jsonDecode(
      File('test/fixtures/ai_assistant_agent_eval_cases.json')
          .readAsStringSync(),
    ) as List<Object?>;
    final cases = <String, Map<String, Object?>>{
      for (final value in decoded)
        (value as Map<String, Object?>)['id']! as String: value,
    };

    final diagnosis =
        cases['workshop-006']!['expected']! as Map<String, Object?>;
    expect(diagnosis['tools'], <String>[
      'search_workshop_jobs',
      'get_workshop_job_context',
      'inspect_diagnosis_schema',
      'prepare_diagnosis_update',
    ]);
    expect(diagnosis['outcome'], 'approvalRequired');
    expect(diagnosis['mutation'], 'draft');

    final workshopItem =
        cases['workshop-007']!['expected']! as Map<String, Object?>;
    expect(workshopItem['tools'], <String>[
      'search_workshop_jobs',
      'get_workshop_job_context',
      'search_inventory',
      'prepare_workshop_item',
    ]);
    expect(workshopItem['outcome'], 'approvalRequired');
    expect(workshopItem['mutation'], 'draft');

    final salesPeriod =
        cases['sales-003']!['expected']! as Map<String, Object?>;
    expect(salesPeriod['tools'], <String>['analyze_sales_period']);
    expect(salesPeriod['mutation'], 'none');
  });
}
