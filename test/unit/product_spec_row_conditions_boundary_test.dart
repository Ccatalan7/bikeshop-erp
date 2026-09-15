import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_coherence.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_row_conditions.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/inventory/utils/spec_rule_evaluator.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_spec_rows_field.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_searchable_select.dart';

// Independent synthetic boundary fixtures; none are manufacturer claims.
Map<String, dynamic> _schemaJson() => {
      'version': 1,
      'columns': [
        {
          'key': 'fixed',
          'label': 'Static required',
          'type': 'token',
          'required': true,
          'allowed_values': ['record']
        },
        {'key': 'kind', 'label': 'Open kind', 'type': 'token'},
        {'key': 'flag', 'label': 'Prerequisite', 'type': 'boolean'},
        {
          'key': 'code',
          'label': 'Literal code',
          'type': 'token',
          'allowed_values': ['01', '1']
        },
        {'key': 'quantity', 'label': 'Exact quantity', 'type': 'decimal'},
        {'key': 'detail', 'label': 'Dependent detail', 'type': 'text'},
        {'key': 'ref_id', 'label': 'Member reference', 'type': 'token'},
      ],
    };

Map<String, dynamic> _when(String field, String type, Object value,
        {String operator = 'eq'}) =>
    {
      'kind': 'when',
      'rows': [
        [
          {
            'field': field,
            'operator': operator,
            'value_type': type,
            'value': value,
          }
        ],
      ],
    };

Map<String, dynamic> _contract(Map<String, dynamic> rules) => {
      'rules_version': 2,
      'allowed_when': <String, dynamic>{},
      'required_when': <String, dynamic>{},
      'allowed_options': <String, dynamic>{},
      'prerequisites': <String, dynamic>{},
      'roles': {'configurations': 'measurement'},
      'row_conditions': {
        'version': 1,
        'fields': {'configurations': rules},
      },
    };

Map<String, dynamic> _document(Map<String, dynamic> cells) => {
      'schema_version': 1,
      'rows': [
        {
          'id': 'a',
          'values': cells,
          'sources': ['https://example.test/row-a']
        },
      ],
    };

SpecTemplate _template(Map<String, dynamic> contract) => SpecTemplate(
      id: 'row-boundary-template',
      key: 'row_boundary_template',
      name: 'Synthetic row boundary',
      technicalFamily: 'row_boundary',
      formContract: contract,
      fields: [
        SpecTemplateField(
          specDefinitionId: 'row-boundary-definition',
          sectionKey: 'measurement',
          sortOrder: 0,
          isRequired: false,
          visibilityRules: const [],
          definition: SpecDefinition(
            id: 'row-boundary-definition',
            key: 'configurations',
            label: 'Configurations',
            dataType: 'json',
            options: const [],
            sortOrder: 0,
            validationRules: {'rows_schema': _schemaJson()},
          ),
        ),
      ],
    );

ProductSpecRowConditions _conditions(Map<String, dynamic> rules) =>
    ProductSpecRowConditions.fromContract(_contract(rules),
        {'configurations': ProductSpecRowSchema.fromJson(_schemaJson())});

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.resolve(
          preset: AppearancePresets.pacific, brightness: Brightness.light),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child))),
    );

void main() {
  test('required_when never cannot remove static schema completeness', () {
    final contract = _contract({
      'required_when': {
        'fixed': {'kind': 'never'},
      },
    });
    final template = _template(contract);
    final values = {
      'configurations': _document({'kind': 'unrestricted'})
    };
    expect(
        template.rowConditions.fields['configurations']!
            .requiredFor('fixed', {'kind': 'unrestricted'}),
        SpecTruth.yes);
    expect(
        validateProductSpecDraft(template: template, values: values)
            .where((issue) => issue.code == 'row_incomplete')
            .map((issue) => issue.blocking),
        [false]);
  });

  test('literal row codes 01 and 1 are distinct through central validation',
      () {
    final template = _template(_contract({
      'allowed_when': {'detail': _when('code', 'token', '01')},
    }));
    for (final code in ['01', '1']) {
      final values = {
        'configurations':
            _document({'fixed': 'record', 'code': code, 'detail': 'Observed'})
      };
      final before = jsonEncode(values);
      expect(
          validateProductSpecDraft(template: template, values: values)
              .where((issue) => issue.code == 'row_field_applicability')
              .length,
          code == '01' ? 0 : 1);
      expect(jsonEncode(values), before);
    }
  });

  test('exact decimal predicate handles a fractional value beyond 2^53', () {
    final conditions = _conditions({
      'allowed_when': {
        'detail': _when('quantity', 'decimal', '9007199254740993.125'),
      },
    }).fields['configurations']!;
    expect(
        conditions
            .applicabilityFor('detail', {'quantity': '9007199254740993.125'}),
        SpecTruth.yes);
    expect(
        conditions.applicabilityFor(
            'detail', {'quantity': '9007199254740993.1249999999999999'}),
        SpecTruth.no);
  });

  for (final value in <Object>[9007199254740992, '-', '1,5', '1e131072']) {
    test('invalid row decimal $value is blocked by central shape owner', () {
      final template = _template(_contract({
        'allowed_when': {'detail': _when('quantity', 'decimal', '1.5')},
      }));
      final values = {
        'configurations':
            _document({'fixed': 'record', 'quantity': value, 'detail': 'Kept'})
      };
      expect(
          validateProductSpecDraft(template: template, values: values)
              .where((issue) => issue.code == 'row_shape')
              .any((issue) => issue.blocking),
          true);
      expect(() => SpecEngineService.buildFactPayload(template, values),
          throwsFormatException);
    });
  }

  test('numeric JSON predicate cannot bypass exact textual operands', () {
    expect(
        () => _conditions({
              'allowed_when': {'detail': _when('quantity', 'decimal', 1.5)},
            }),
        throwsFormatException);
  });

  test('a cycle through allowed and required buckets is rejected', () {
    expect(
        () => _conditions({
              'allowed_when': {'detail': _when('kind', 'token', 'x')},
              'required_when': {'kind': _when('detail', 'token', 'y')},
            }),
        throwsFormatException);
  });

  test('a same named top-level value cannot satisfy a missing row input', () {
    final template = _template(_contract({
      'allowed_when': {'detail': _when('flag', 'boolean', true)},
    }));
    final values = {
      'flag': true,
      'configurations': _document({'fixed': 'record', 'detail': 'Preserved'}),
    };
    final before = jsonEncode(values);
    final issues = validateProductSpecDraft(template: template, values: values);
    expect(issues.where((issue) => issue.code == 'row_prerequisite').length, 1);
    expect(issues.any((issue) => issue.blocking), false);
    final wire = jsonDecode(
            jsonEncode(SpecEngineService.buildFactPayload(template, values)))
        as Map;
    expect(wire['row-boundary-definition']['rows'], values['configurations']);
    expect(wire.containsKey('flag'), false);
    expect(jsonEncode(values), before);
  });

  test('invalid condition metadata becomes a blocking central issue', () {
    final template = _template(_contract({
      'allowed_when': {'detail': _when('another_row.flag', 'boolean', true)},
    }));
    final issues = validateProductSpecDraft(template: template, values: {
      'configurations': _document({'fixed': 'record'})
    });
    expect(issues.any((issue) => issue.blocking), true);
  });

  testWidgets(
      'retiring a value while prerequisite is unknown clears its control',
      (tester) async {
    final schema = ProductSpecRowSchema.fromJson(_schemaJson());
    final conditions = _conditions({
      'allowed_when': {'detail': _when('flag', 'boolean', true)},
    });
    Map<String, dynamic>? value =
        _document({'fixed': 'record', 'detail': 'Retained original'});
    await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => ProductSpecRowsField(
            fieldKey: 'configurations',
            label: 'Configurations',
            schema: schema,
            conditions: conditions.fields['configurations'],
            value: value,
            onChanged: (next) => setState(() => value = next)))));
    final detail = find.byKey(const ValueKey('configurations-a-detail'));
    final clear = find.byKey(const ValueKey('configurations-a-detail-clear'));
    expect(tester.widget<TextFormField>(detail).enabled, false);
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(value!['rows'][0]['values'].containsKey('detail'), false);
    expect(value!['rows'][0]['sources'], ['https://example.test/row-a']);
    expect(clear, findsNothing);
    expect(tester.widget<TextFormField>(detail).enabled, false);
    final editable = tester.widget<EditableText>(
        find.descendant(of: detail, matching: find.byType(EditableText)));
    expect(editable.controller.text, isEmpty,
        reason: 'A removed observation must not remain displayed as a value.');
  });

  testWidgets('allowed_options narrows an otherwise open token to a picker',
      (tester) async {
    final schema = ProductSpecRowSchema.fromJson(_schemaJson());
    final conditions = _conditions({
      'allowed_options': {
        'kind': ['A', 'B'],
      },
    });
    await tester.pumpWidget(_host(ProductSpecRowsField(
        fieldKey: 'configurations',
        label: 'Configurations',
        schema: schema,
        conditions: conditions.fields['configurations'],
        value: _document({'fixed': 'record'}),
        onChanged: (_) {})));
    final picker = find.byWidgetPredicate((widget) =>
        widget is VbSearchableSelect<String> &&
        widget.key == const ValueKey('configurations-a-kind'));
    expect(picker, findsOneWidget,
        reason: 'Published narrowing must be offered in the editor.');
    expect(
        tester
            .widget<VbSearchableSelect<String>>(picker)
            .options
            .map((option) => option.value),
        ['A', 'B']);
  });

  testWidgets('reference choices respect allowed_options of an open token',
      (tester) async {
    final schema = ProductSpecRowSchema.fromJson(_schemaJson());
    final conditions = _conditions({
      'allowed_options': {
        'ref_id': ['member_a'],
      },
    });
    await tester.pumpWidget(_host(ProductSpecRowsField(
        fieldKey: 'configurations',
        label: 'Configurations',
        schema: schema,
        conditions: conditions.fields['configurations'],
        referenceOptions: const {
          'ref_id': ProductSpecRowLinkOptions('Members', {
            'member_a': 'Model A',
            'member_b': 'Model B',
          }),
        },
        value: _document({'fixed': 'record'}),
        onChanged: (_) {})));
    final picker = tester.widget<VbSearchableSelect<String>>(
        find.byKey(const ValueKey('configurations-a-ref_id')));
    expect(picker.options.map((option) => option.value), ['member_a']);
  });
}
