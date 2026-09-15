import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_coherence.dart';
import 'package:vinabike_erp/shared/widgets/vb_searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_row_conditions.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_spec_rows_field.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_spec_boolean_field.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

final schema = ProductSpecRowSchema.fromJson({
  'version': 1,
  'columns': [
    {'key': 'bsd', 'label': 'Asiento nominal', 'type': 'integer', 'unit': 'mm'},
    {'key': 'min', 'label': 'Ancho mínimo', 'type': 'decimal', 'unit': 'mm'},
    {'key': 'max', 'label': 'Ancho máximo', 'type': 'decimal', 'unit': 'mm'},
    {'key': 'adapter', 'label': 'Incluye adaptador', 'type': 'boolean'},
  ],
  'ordered_pairs': [
    ['min', 'max']
  ],
});
Map<String, dynamic> observations() => {
      'schema_version': 1,
      'rows': [
        {
          'id': 'a',
          'values': {'bsd': '622', 'min': '28', 'max': '47', 'adapter': false},
          'sources': ['https://example.test/a']
        },
        {
          'id': 'b',
          'values': {'bsd': '584', 'min': '40', 'max': '62'},
          'sources': ['https://example.test/b']
        },
      ]
    };

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: AppTheme.resolve(
          preset: AppearancePresets.pacific, brightness: brightness),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child))),
    );

void main() {
  for (final width in [390.0, 768.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'conditional values stay local and never fill at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final rowSchema = ProductSpecRowSchema.fromJson({
          'version': 1,
          'columns': [
            {
              'key': 'state',
              'label': 'Presentación',
              'type': 'token',
              'allowed_values': ['Con kit incluido', 'Con kit opcional']
            },
            {
              'key': 'included',
              'label': 'Incluye abrazadera',
              'type': 'boolean'
            },
            {
              'key': 'standard',
              'label': 'Interfaz',
              'type': 'token',
              'allowed_values': ['Directa', 'Adaptada']
            },
            {
              'key': 'torque',
              'label': 'Torque de prueba',
              'type': 'decimal',
              'unit': 'Nm'
            },
          ]
        });
        Map<String, dynamic> rule(String type, Object value) => {
              'when': {
                'kind': 'when',
                'rows': [
                  [
                    {
                      'field': 'state',
                      'operator': 'eq',
                      'value_type': 'token',
                      'value': 'Con kit incluido'
                    }
                  ]
                ]
              },
              'expected': {'value_type': type, 'value': value}
            };
        final conditions = ProductSpecRowConditions.fromContract({
          'rules_version': 2,
          'row_conditions': {
            'version': 1,
            'fields': {
              'config': {
                'value_when': {
                  'included': [rule('boolean', true)],
                  'standard': [rule('token', 'Adaptada')],
                  'torque': [rule('decimal', '5')],
                }
              }
            }
          }
        }, {
          'config': rowSchema
        });
        Map<String, dynamic>? value = {
          'schema_version': 1,
          'rows': [
            {
              'id': 'a',
              'values': {
                'state': 'Con kit incluido',
                'included': false,
                'standard': 'Directa',
                'torque': '4'
              },
              'sources': ['https://example.test/a']
            },
            {
              'id': 'b',
              'values': {'state': 'Con kit opcional', 'included': false},
              'sources': ['https://example.test/b']
            }
          ]
        };
        final second = jsonEncode(value['rows'][1]);
        var changes = 0;
        await tester.pumpWidget(host(
            StatefulBuilder(
                builder: (context, setState) => ProductSpecRowsField(
                    fieldKey: 'config',
                    label: 'Configuraciones',
                    schema: rowSchema,
                    conditions: conditions.fields['config'],
                    value: value,
                    onChanged: (next) => setState(() {
                          changes++;
                          value = next;
                        }))),
            brightness: brightness));
        final included = find.byKey(const ValueKey('config-a-included'));
        ProductSpecBooleanField boolean() =>
            tester.widget<ProductSpecBooleanField>(included);
        expect(boolean().value, false);
        expect(boolean().allowedValues, {true});
        expect(boolean().errorText, isNotNull);
        expect(changes, 0);
        final standard = tester.widget<VbSearchableSelect<String>>(
            find.byKey(const ValueKey('config-a-standard')));
        expect(standard.options.map((o) => o.value), ['Adaptada']);
        expect(standard.value, 'Directa');
        expect(standard.errorText, isNotNull);
        final torque = tester.widget<TextField>(find.descendant(
            of: find.byKey(const ValueKey('config-a-torque')),
            matching: find.byType(TextField)));
        expect(torque.decoration!.errorText, isNotNull);
        await tester.ensureVisible(included);
        await tester
            .tap(find.descendant(of: included, matching: find.text('Sí')));
        await tester.pumpAndSettle();
        expect(value!['rows'][0]['values']['included'], true);
        expect(boolean().errorText, isNull);
        await tester.tap(
            find.descendant(of: included, matching: find.text('Sin dato')));
        await tester.pumpAndSettle();
        expect(value!['rows'][0]['values'].containsKey('included'), false);
        expect(boolean().helperText, isNotNull);
        // Use the shared select's domain callback; its popup behaviour is
        // covered by the canonical S-06 tests, independently of these rules.
        tester
            .widget<VbSearchableSelect<String>>(
                find.byKey(const ValueKey('config-a-state')))
            .onChanged!('Con kit opcional');
        await tester.pumpAndSettle();
        expect(boolean().allowedValues, isNull);
        expect(boolean().value, isNull);
        expect(boolean().helperText, isNull);
        await tester
            .tap(find.descendant(of: included, matching: find.text('No')));
        await tester.pumpAndSettle();
        expect(value!['rows'][0]['values']['included'], false);
        expect(jsonEncode(value!['rows'][1]), second);
        expect(value!['rows'][0]['sources'], ['https://example.test/a']);
        value!['rows'][0]['values']['state'] = 'Con kit incluido';
        final changesBeforeReadOnly = changes;
        await tester.pumpWidget(host(
            ProductSpecRowsField(
                fieldKey: 'config',
                label: 'Configuraciones',
                schema: rowSchema,
                conditions: conditions.fields['config'],
                value: value,
                onChanged: null),
            brightness: brightness));
        expect(boolean().value, false);
        expect(boolean().onChanged, isNull);
        expect(boolean().errorText, isNotNull);
        expect(changes, changesBeforeReadOnly);
        expect(jsonEncode(value!['rows'][1]), second);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [390.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'same-row upstream preserves conflicting data at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = jsonDecode(
            File('test/fixtures/product_spec_row_conditions.json')
                .readAsStringSync()) as Map;
        final rowSchema = ProductSpecRowSchema.fromJson(
            Map<String, dynamic>.from(
                fixture['fields']['configurations']['schema'] as Map));
        final conditions = ProductSpecRowConditions.fromContract(
            Map<String, dynamic>.from(fixture['contract'] as Map),
            {'configurations': rowSchema});
        Map<String, dynamic>? value = Map<String, dynamic>.from(
            (fixture['cases'] as List).firstWhere((c) =>
                    c['id'] == 'two_rows_own_different_answers')['values']
                ['configurations'] as Map);
        final otherRow = jsonEncode(value['rows'][1]);
        await tester.pumpWidget(host(
            StatefulBuilder(
                builder: (context, setState) => ProductSpecRowsField(
                    fieldKey: 'configurations',
                    label: 'Configuraciones',
                    schema: rowSchema,
                    conditions: conditions.fields['configurations'],
                    value: value,
                    onChanged: (next) => setState(() => value = next))),
            brightness: brightness));
        final boolean =
            find.byKey(const ValueKey('configurations-a-adapter_required'));
        final model =
            find.byKey(const ValueKey('configurations-a-adapter_model'));
        await tester.ensureVisible(boolean);
        await tester
            .tap(find.descendant(of: boolean, matching: find.text('No')));
        await tester.pumpAndSettle();
        expect(value!['rows'][0]['values']['adapter_model'], 'Adapter A');
        expect(tester.widget<TextFormField>(model).enabled, false);
        expect(
            conditions.validate({'configurations': value}).any(
                (i) => i.code == 'row_field_applicability'),
            true);
        final clear =
            find.byKey(const ValueKey('configurations-a-adapter_model-clear'));
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(value!['rows'][0]['values'].containsKey('adapter_model'), false);
        expect(model, findsNothing);
        await tester.ensureVisible(boolean);
        await tester
            .tap(find.descendant(of: boolean, matching: find.text('Sin dato')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(model).enabled, false);
        expect(find.textContaining('Define primero Requiere adaptador'),
            findsOneWidget);
        await tester
            .tap(find.descendant(of: boolean, matching: find.text('Sí')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(model).enabled, true);
        await tester.enterText(model, 'Adapter C');
        await tester.pumpAndSettle();
        expect(value!['rows'][0]['values']['adapter_model'], 'Adapter C');
        expect(jsonEncode(value!['rows'][1]), otherRow);
        final role = tester.widget<VbSearchableSelect<String>>(
            find.byKey(const ValueKey('configurations-a-member_role')));
        expect(
            role.options.map((option) => option.value), ['soporte', 'cable']);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [390.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'linked row preserves ID and exposes removed target at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = jsonDecode(
            File('test/fixtures/product_spec_coherence.json')
                .readAsStringSync()) as Map;
        final values =
            Map<String, dynamic>.from(fixture['cases'][0]['values'] as Map);
        final schemas = {
          for (final e in (fixture['schemas'] as Map).entries)
            e.key as String: ProductSpecRowSchema.fromJson(
                Map<String, dynamic>.from(e.value as Map))
        };
        final coherence = ProductSpecCoherence.fromContract(
            Map<String, dynamic>.from(fixture['contract'] as Map),
            Map<String, String>.from(fixture['types'] as Map),
            schemas, {});
        late StateSetter redraw;
        var changes = 0;
        await tester
            .pumpWidget(host(StatefulBuilder(builder: (context, setState) {
          redraw = setState;
          return ProductSpecRowsField(
              fieldKey: 'allocations',
              label: 'Asignaciones',
              schema: schemas['allocations']!,
              value: values['allocations'],
              referenceOptions:
                  coherence.optionsFor('allocations', values, (_) => 'Puertos'),
              onChanged: (next) => setState(() {
                    values['allocations'] = next;
                    changes++;
                  }));
        }), brightness: brightness));
        final select = find.byKey(const ValueKey('allocations-c1-port_row_id'));
        expect(tester.widget<VbSearchableSelect<String>>(select).value, 'p1');
        expect(find.text('USB-C 1'), findsWidgets);
        final before = jsonEncode(values['allocations']);
        redraw(() =>
            values['ports']['rows'][0]['values']['name'] = 'Puerto frontal');
        await tester.pumpAndSettle();
        expect(find.text('Puerto frontal'), findsWidgets);
        expect(jsonEncode(values['allocations']), before);
        expect(changes, 0);
        redraw(() => values['ports']['rows'].removeAt(0));
        await tester.pumpAndSettle();
        expect(find.text('Vínculo sin resolver'), findsWidgets);
        expect(find.text('La configuración vinculada no existe en esta ficha.'),
            findsWidgets);
        expect(jsonEncode(values['allocations']), before);
        expect(coherence.validate(values).any((i) => i.blocking), true);
        await tester.tap(select);
        await tester.pumpAndSettle();
        await tester.tap(find.text('USB-C 2').last);
        await tester.pumpAndSettle();
        expect(values['allocations']['rows'][0]['values']['port_row_id'], 'p2');
        expect(coherence.validate(values).any((i) => i.blocking), false);
        expect(changes, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('editing a row preserves its paired values and other row sources',
      (tester) async {
    Map<String, dynamic>? value = observations();
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => ProductSpecRowsField(
            fieldKey: 'fits',
            label: 'Medidas admitidas',
            schema: schema,
            value: value,
            onChanged: (next) => setState(() => value = next)))));
    await tester.enterText(find.byKey(const ValueKey('fits-a-min')), '28,5');
    await tester.pumpAndSettle();
    final rows = schema.parse(value).rows;
    expect(rows[0].values['min'], '28.5');
    expect(rows[0].values['bsd'], '622');
    expect(rows[0].values['max'], '47');
    expect(rows[0].values['adapter'], false);
    expect(rows[0].sources, ['https://example.test/a']);
    expect(rows[1].values, {'bsd': '584', 'min': '40', 'max': '62'});
    expect(rows[1].sources, ['https://example.test/b']);
    await tester.tap(find.byKey(const ValueKey('fits-row-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración 2').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fits-b-min')), findsOneWidget);
    expect(find.text('Sin dato'), findsOneWidget,
        reason: 'an absent boolean in the second row does not inherit false');
    expect(value!['rows'][1]['values'].containsKey('adapter'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'adding and removing a configuration preserves existing identities',
      (tester) async {
    Map<String, dynamic>? value = observations();
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => ProductSpecRowsField(
            fieldKey: 'fits',
            label: 'Medidas admitidas',
            schema: schema,
            value: value,
            onChanged: (next) => setState(() => value = next)))));
    await tester.ensureVisible(find.byKey(const ValueKey('fits-add-row')));
    await tester.tap(find.byKey(const ValueKey('fits-add-row')));
    await tester.pumpAndSettle();
    expect(value!['rows'], hasLength(3));
    expect(value!['rows'][2]['values'], isEmpty);
    expect(value!['rows'][2]['sources'], isEmpty);
    expect(value!['rows'][0]['id'], 'a');
    expect(value!['rows'][1]['id'], 'b');
    await tester.ensureVisible(find.byKey(const ValueKey('fits-remove-row')));
    await tester.tap(find.byKey(const ValueKey('fits-remove-row')));
    await tester.pumpAndSettle();
    expect(value, observations());
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'reference rows are readable without mutation at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final value = observations();
        await tester.pumpWidget(host(
            ProductSpecRowsField(
                fieldKey: 'reference',
                label: 'Medidas documentadas',
                schema: schema,
                value: value,
                onChanged: null),
            brightness: brightness));
        expect(find.byKey(const ValueKey('reference-add-row')), findsNothing);
        expect(
            find.byKey(const ValueKey('reference-remove-row')), findsNothing);
        expect(
            tester
                .widget<TextFormField>(
                    find.byKey(const ValueKey('reference-a-min')))
                .enabled,
            false);
        await tester.tap(find.byKey(const ValueKey('reference-row-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Configuración 2').last);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('reference-b-min')), findsOneWidget);
        expect(value, observations());
        expect(find.textContaining('schema_version'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
