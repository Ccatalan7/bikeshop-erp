import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_draft.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_profile.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_spec_member_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_searchable_select.dart';

const firstId = '99e10000-0000-4000-8000-000000000081';
const secondId = '99e10000-0000-4000-8000-000000000082';
const collectionId = '99e10000-0000-4000-8000-000000000051';

Map<String, dynamic> fixture([String name = 'active']) =>
    (jsonDecode(File('test/fixtures/product_spec_member_profiles.json')
        .readAsStringSync()) as Map)[name] as Map<String, dynamic>;

Future<void> tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late Map<String, dynamic> source;
  late Map<String, dynamic> values;
  late SpecTemplate? parent;
  late SpecTemplate child;
  late ProductSpecMemberProfiles read;
  late ProductSpecMemberDrafts drafts;
  late StateSetter rebuild;
  late Future<SpecTemplate> Function() fetch;
  late Future<List<ProductSpecReference>> Function(String) fetchReferences;
  var authorityChanges = 0;
  var editableFields = false;
  var loads = 0;

  setUp(() {
    source = fixture();
    values = source['values'] as Map<String, dynamic>;
    parent = SpecEngineService.decodeProductSpecEditorContext(source).template!;
    read = decodeProductSpecMemberProfiles(source);
    child = read.profiles.first.template;
    drafts = ProductSpecMemberDrafts(read);
    loads = 0;
    fetch = () async => child;
    fetchReferences = (_) async => [];
    authorityChanges = 0;
    editableFields = false;
  });

  Future<void> pump(WidgetTester tester,
      {Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.resolve(
            preset: AppearancePresets.pacific, brightness: brightness),
        home: Scaffold(body: SingleChildScrollView(
            child: StatefulBuilder(builder: (context, update) {
          rebuild = update;
          return ProductSpecMemberEditor(
              drafts: drafts,
              parentTemplate: parent,
              parentValues: values,
              collections: parent == null ? [] : read.collections,
              loadTemplate: (
                  {required parentTemplateId,
                  required collectionDefinitionId,
                  required familyKey}) {
                expect(parentTemplateId, parent!.id);
                expect(collectionDefinitionId, collectionId);
                expect(familyKey, child.key);
                loads++;
                return fetch();
              },
              loadReferences: fetchReferences,
              onChanged: () => update(() {}),
              onAuthorityChanged: () => authorityChanges++,
              buildFields: (draft, generation) => [
                    if (editableFields)
                      TextFormField(
                        key: ValueKey('editor-${draft.id}-$generation'),
                        initialValue:
                            draft.values['member_test_length']?.toString(),
                        onChanged: (value) =>
                            draft.setValue('member_test_length', value),
                      ),
                    Text('${draft.id}: ${draft.values['member_test_length']}',
                        key: ValueKey('observation-${draft.id}')),
                  ]);
        })))));
    await tester.pumpAndSettle();
  }

  List<dynamic> rows() =>
      (values['member_test_collection'] as Map)['rows'] as List;

  Future<void> select(WidgetTester tester, String key) async {
    final widget = tester.widget<VbSearchableSelect<String>>(
        find.byKey(const ValueKey('member-selection')));
    final option = widget.options.singleWhere((o) => o.value == key);
    await tapVisible(tester, const ValueKey('member-selection'));
    await tester.tap(find.text(option.label).last);
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'component identity and archive survive category removal $width $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pump(tester, brightness: brightness);
        drafts.active.first
            .setValue('member_test_length', '8.0000000000000001');
        rebuild(() {
          parent = null;
          values = {};
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('La ficha del producto cambió'),
            findsOneWidget);
        expect(drafts.active.first.values['member_test_length'],
            '8.0000000000000001');
        await tapVisible(tester, const ValueKey('member-archive-$firstId'));
        expect(drafts.archiving.single.id, firstId);
        expect(drafts.archiving.single.values['member_test_length'],
            '8.0000000000000001');
        await tapVisible(tester, const ValueKey('member-archive-$secondId'));
        final command =
            drafts.buildCommand(parentTemplate: null, parentValues: {});
        expect(command['upserts'], isEmpty);
        expect(command['archive_ids'], [firstId, secondId]);
        await tapVisible(tester, const ValueKey('member-undo-$firstId'));
        expect(drafts.active.single.id, firstId);
        expect(
            () => drafts.buildCommand(parentTemplate: null, parentValues: {}),
            throwsFormatException);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'a known replacement cannot inherit observations by identifying it',
      (tester) async {
    await pump(tester);
    rebuild(() {
      rows()[0]['values']['identity_model'] = 'Replacement';
    });
    await tester.pumpAndSettle();
    await tapVisible(tester, const ValueKey('member-identify-$firstId'));
    expect(find.textContaining('conservar los datos ya confirmados'),
        findsOneWidget);
    expect(
        drafts.active.first.identity['identity_model'], isNot('Replacement'));
    await tapVisible(tester, const ValueKey('member-archive-$firstId'));
    await select(tester, 'row:$collectionId:r1');
    await tapVisible(
        tester, const ValueKey('member-create-row:$collectionId:r1'));
    final replacement = drafts.forRow(collectionId, 'r1')!;
    expect(replacement.id, isNot(firstId));
    expect(replacement.identity['identity_model'], 'Replacement');
    expect(replacement.values, isEmpty);
    expect(replacement.persisted, isFalse);
    expect(drafts.archiving.single.values['member_test_length'], '7.1');
    expect(drafts.forRow(collectionId, 'r2')!.values['member_test_length'],
        '9007199254740993.2');
    expect(loads, 1);
  });

  testWidgets(
      'unknown identity requires its row source, then keeps the same profile',
      (tester) async {
    await pump(tester);
    await select(tester, 'profile:$secondId');
    rebuild(() {
      rows()[1]['values']['identity_model'] = 'Confirmed B';
      rows()[1]['sources'] = [];
    });
    await tester.pumpAndSettle();
    await tapVisible(tester, const ValueKey('member-identify-$secondId'));
    expect(
        drafts.forRow(collectionId, 'r2')!.identity['identity_model'], isNull);
    rebuild(() {
      rows()[1]['sources'] = ['https://example.test/label'];
    });
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('member-mpn-$secondId')), 'B-21');
    await tapVisible(tester, const ValueKey('member-identify-$secondId'));
    final confirmed = drafts.forRow(collectionId, 'r2')!;
    expect(confirmed.identity['identity_model'], 'Confirmed B');
    expect(confirmed.manufacturerSku, 'B-21');
    expect(confirmed.id, secondId);
    expect(
        (drafts.buildCommand(
            parentTemplate: parent,
            parentValues: values)['upserts'] as List)[1]['binding_action'],
        'identify');
  });

  testWidgets('unknown family cannot load or create a component profile',
      (tester) async {
    drafts.archive(firstId);
    rows()[0]['values'].remove('family');
    await pump(tester);
    await select(tester, 'row:$collectionId:r1');
    final create = tester.widget<TextButton>(
        find.byKey(const ValueKey('member-create-row:$collectionId:r1')));
    expect(create.onPressed, isNull);
    expect(loads, 0);
    expect(find.textContaining('Confirma la familia de esta pieza'),
        findsOneWidget);
  });

  testWidgets('a late family read cannot create a profile for a replaced row',
      (tester) async {
    drafts.archive(firstId);
    final pending = Completer<SpecTemplate>();
    fetch = () => pending.future;
    await pump(tester);
    await select(tester, 'row:$collectionId:r1');
    await tapVisible(
        tester, const ValueKey('member-create-row:$collectionId:r1'));
    rebuild(() {
      rows()[0]['values']['identity_model'] = 'Changed while loading';
    });
    await tester.pump();
    pending.complete(child);
    await tester.pumpAndSettle();
    expect(drafts.forRow(collectionId, 'r1'), isNull);
    expect(find.textContaining('cambió durante la carga'), findsOneWidget);
    expect(drafts.archiving.single.id, firstId);
  });

  testWidgets('failed read can retry without losing the archived original',
      (tester) async {
    drafts.archive(firstId);
    fetch = () async => throw StateError('network');
    await pump(tester);
    await select(tester, 'row:$collectionId:r1');
    await tapVisible(
        tester, const ValueKey('member-create-row:$collectionId:r1'));
    expect(drafts.forRow(collectionId, 'r1'), isNull);
    expect(find.textContaining('No se pudo cargar la ficha de esta pieza'),
        findsOneWidget);
    fetch = () async => child;
    await tapVisible(
        tester, const ValueKey('member-create-row:$collectionId:r1'));
    expect(loads, 2);
    expect(drafts.forRow(collectionId, 'r1')!.values, isEmpty);
    expect(drafts.archiving.single.id, firstId);
  });

  testWidgets(
      'committed read-back replaces pending archive and stale MPN input',
      (tester) async {
    await pump(tester);
    await select(tester, 'profile:$secondId');
    await tester.enterText(
        find.byKey(const ValueKey('member-mpn-$secondId')), 'UNCONFIRMED');
    await tapVisible(tester, const ValueKey('member-archive-$secondId'));
    final committed = fixture('archived');
    rebuild(() {
      drafts =
          ProductSpecMemberDrafts(decodeProductSpecMemberProfiles(committed));
      parent =
          SpecEngineService.decodeProductSpecEditorContext(committed).template;
      values = committed['values'] as Map<String, dynamic>;
    });
    await tester.pumpAndSettle();
    expect(drafts.archiving, isEmpty);
    expect(find.textContaining('Se archivará al guardar'), findsNothing);
    expect(find.text('Fichas archivadas'), findsOneWidget);
    expect(find.text('UNCONFIRMED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authority changes stop component reads and explain reopening',
      (tester) async {
    drafts.archive(firstId);
    fetch = () async => throw const AuthorityScopeChangedException();
    await pump(tester);
    await select(tester, 'row:$collectionId:r1');
    await tapVisible(
        tester, const ValueKey('member-create-row:$collectionId:r1'));
    expect(authorityChanges, 1);
    expect(find.text('La sesión cambió. Vuelve a abrir el producto.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find
                .byKey(const ValueKey('member-create-row:$collectionId:r1')))
            .onPressed,
        isNull);
    expect(drafts.forRow(collectionId, 'r1'), isNull);
    expect(drafts.archiving.single.values['member_test_length'], '7.1');
  });

  testWidgets('authority changes during reference reads disable editing',
      (tester) async {
    fetchReferences = (_) async => throw const AuthorityScopeChangedException();
    await pump(tester);
    await tapVisible(tester, const ValueKey('member-load-references-$firstId'));
    expect(authorityChanges, 1);
    expect(find.text('La sesión cambió. Vuelve a abrir el producto.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('member-identify-$firstId')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<VbSearchableSelect<String>>(
                find.byKey(const ValueKey('member-reference-$firstId')))
            .onChanged,
        isNull);
  });

  testWidgets('reference variants require the confirmed MPN and display it',
      (tester) async {
    ProductSpecReference reference(String id, String? mpn) =>
        ProductSpecReference(
          id: id,
          family: child.technicalFamily,
          brand: 'Fixture',
          model: 'Model A',
          label: 'Same model',
          manufacturerSku: mpn,
          facts: {},
          sources: [],
          claims: [],
        );
    fetchReferences = (_) async => [
          reference('generic', null),
          reference('a1', 'A-1'),
          reference('a2', 'A-2')
        ];
    await pump(tester);
    await tapVisible(tester, const ValueKey('member-load-references-$firstId'));
    VbSearchableSelect<String> selectReference() =>
        tester.widget(find.byKey(const ValueKey('member-reference-$firstId')));
    expect(selectReference().options.map((o) => o.value), ['generic']);
    await tester
        .ensureVisible(find.byKey(const ValueKey('member-mpn-$firstId')));
    await tester.enterText(
        find.byKey(const ValueKey('member-mpn-$firstId')), 'A-1');
    await tapVisible(tester, const ValueKey('member-identify-$firstId'));
    expect(selectReference().options.map((o) => o.value), ['generic', 'a1']);
    expect(selectReference().options.last.context, 'MPN: A-1');
    selectReference().onChanged!('a1');
    await tester.pumpAndSettle();
    expect(drafts.active.first.reference!.id, 'a1');
    expect(
        drafts.active.first
            .validate()
            .where((i) => i.code == 'reference_identity'),
        isEmpty);
  });

  testWidgets('identical pieces expose separate positions in their collection',
      (tester) async {
    rows().add({
      'id': 'r3',
      'values': Map<String, dynamic>.from(rows()[0]['values'] as Map),
      'sources': ['https://example.test/pack']
    });
    await pump(tester);
    final selector = tester.widget<VbSearchableSelect<String>>(
        find.byKey(const ValueKey('member-selection')));
    final first =
        selector.options.singleWhere((o) => o.value == 'profile:$firstId');
    final third =
        selector.options.singleWhere((o) => o.value == 'row:$collectionId:r3');
    expect(first.label, third.label);
    expect(first.context, contains('configuración 1'));
    expect(third.context, contains('configuración 3'));
    expect(
        selector.options
            .singleWhere((o) => o.value == 'profile:$secondId')
            .label,
        contains('modelo sin confirmar'));
  });

  testWidgets('archive history uses known field identity labels and date',
      (tester) async {
    await pump(tester);
    final committed = fixture('archived');
    rebuild(() {
      drafts =
          ProductSpecMemberDrafts(decodeProductSpecMemberProfiles(committed));
      parent =
          SpecEngineService.decodeProductSpecEditorContext(committed).template;
      values = committed['values'] as Map<String, dynamic>;
    });
    await tester.pumpAndSettle();
    await tapVisible(tester, const ValueKey('member-history-$firstId'));
    expect(find.text('Length'), findsOneWidget);
    expect(find.text('Included axle'), findsOneWidget);
    expect(find.text('member_test_length'), findsNothing);
    expect(find.textContaining('Archivada el'), findsNWidgets(2));
    expect(find.textContaining('2026'), findsNWidgets(2));
  });

  testWidgets('archive without available template labels stays explicit',
      (tester) async {
    final committed = fixture('archived');
    drafts =
        ProductSpecMemberDrafts(decodeProductSpecMemberProfiles(committed));
    parent =
        SpecEngineService.decodeProductSpecEditorContext(committed).template;
    values = committed['values'] as Map<String, dynamic>;
    await pump(tester);
    await tapVisible(tester, const ValueKey('member-history-$firstId'));
    expect(
        find.text('Dato anterior sin etiqueta disponible'), findsNWidgets(2));
    expect(find.text('member_test_length'), findsNothing);
  });

  testWidgets('receipt replaces the text field state even at generation zero',
      (tester) async {
    editableFields = true;
    await pump(tester);
    final input = find.byKey(const ValueKey('editor-$firstId-0'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '8.100');
    expect(drafts.active.first.values['member_test_length'], '8.100');
    final committed = fixture();
    committed['member_profiles']['profiles'][0]['values']
        ['member_test_length'] = '8.1';
    committed['member_profiles']['profiles'][0]['fact_payload']
        ['99e10000-0000-4000-8000-000000000052']['number'] = '8.1';
    rebuild(() => drafts =
        ProductSpecMemberDrafts(decodeProductSpecMemberProfiles(committed)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-$firstId-1')), findsOneWidget);
    expect(find.text('8.100'), findsNothing);
    expect(find.text('8.1'), findsOneWidget);
  });
}
