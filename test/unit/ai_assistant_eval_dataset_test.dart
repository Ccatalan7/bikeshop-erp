import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const plannedTools = <String>{
    'get_business_snapshot',
    'list_attention_items',
    'search_workshop_jobs',
    'search_tasks',
    'search_inventory',
    'find_inventory_risks',
    'search_customers',
    'search_suppliers',
    'search_sales_invoices',
    'search_purchase_invoices',
    'analyze_cash_and_receivables',
    'list_recent_expenses',
    'search_conversations',
    'research_public_web',
    'draft_customer_followup',
    'draft_quote',
    'prepare_purchase_order',
    'prepare_task',
    'create_task',
    'update_job_status',
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

  test('agent evaluation dataset is fixed, closed and representative', () {
    final file = File('test/fixtures/ai_assistant_agent_eval_cases.json');
    final decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<List<Object?>>());
    final cases = (decoded as List<Object?>).cast<Map<String, Object?>>();

    expect(cases, hasLength(50));
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
      expect(
        tools.where((tool) => !plannedTools.contains(tool)),
        isEmpty,
        reason: '$id references an undeclared tool',
      );
      expect(outcomes, contains(contract['outcome']), reason: '$id outcome');
      expect(
        contract['modelAllowed'],
        isA<bool>(),
        reason: '$id model policy',
      );
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
}
