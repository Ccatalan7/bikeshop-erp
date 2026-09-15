import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_draft.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_profile.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

const collectionId = '99e10000-0000-4000-8000-000000000051';
const firstId = '99e10000-0000-4000-8000-000000000081';
const secondId = '99e10000-0000-4000-8000-000000000082';
const newId = '99e10000-0000-4000-8000-000000000083';
const lengthId = '99e10000-0000-4000-8000-000000000052';

/// The synthetic reference of the archived fixture, with other documented facts.
ProductSpecReference referenceWith(Map<String, dynamic> facts) {
  final fixtures = jsonDecode(
      File('test/fixtures/product_spec_member_profiles.json')
          .readAsStringSync()) as Map;
  final historical =
      (fixtures['archived']['member_profiles']['archived_profiles'] as List)
          .first as Map;
  return ProductSpecReference.fromJson({
    ...Map<String, dynamic>.from(historical['reference'] as Map),
    'facts': facts,
  });
}

Iterable<String> scopeIssues(ProductSpecMemberDraft draft) => draft
    .validate()
    .where((issue) => issue.code == 'reference_scope' && issue.blocking)
    .map((issue) => issue.fieldKey);

void main() {
  late Map<String, dynamic> context;
  late Map<String, dynamic> values;
  late SpecTemplate parent;
  late ProductSpecMemberProfiles loaded;
  late ProductSpecMemberDrafts drafts;
  List<dynamic> rows() =>
      (values['member_test_collection'] as Map)['rows'] as List;
  Map<String, dynamic> cells(int index) =>
      rows()[index]['values'] as Map<String, dynamic>;
  Map<String, dynamic> command() =>
      drafts.buildCommand(parentTemplate: parent, parentValues: values);
  ProductSpecMemberDraft first() => drafts.forRow(collectionId, 'r1')!;
  ProductSpecMemberDraft second() => drafts.forRow(collectionId, 'r2')!;

  setUp(() {
    context = (jsonDecode(
        File('test/fixtures/product_spec_member_profiles.json')
            .readAsStringSync()) as Map)['active'] as Map<String, dynamic>;
    parent =
        SpecEngineService.decodeProductSpecEditorContext(context).template!;
    values = context['values'] as Map<String, dynamic>;
    loaded = decodeProductSpecMemberProfiles(context);
    drafts = ProductSpecMemberDrafts(loaded);
  });

  test('two same-family observations round trip independently and exactly', () {
    final upserts = command()['upserts'] as List;
    expect(upserts.map((p) => p['id']), [firstId, secondId]);
    expect(upserts[0]['values'][lengthId], {'number': '7.1'});
    expect(upserts[1]['values'][lengthId], {'number': '9007199254740993.2'});
    expect(first().identitySources, ['https://example.test/pack']);
    first().setValue('member_test_length', '8.0000000000000001');
    expect(second().values['member_test_length'], '9007199254740993.2');
    expect(loaded.profiles.first.values['member_test_length'], '7.1');
    final detached = first().values..['member_test_length'] = '-1';
    expect(detached['member_test_length'], '-1');
    expect((command()['upserts'] as List)[0]['values'][lengthId],
        {'number': '8.0000000000000001'});
  });

  test(
      'parent row removal cannot orphan facts; explicit archive retains history',
      () {
    rows().removeAt(0);
    expect(command, throwsFormatException);
    drafts.archive(firstId);
    expect(command()['archive_ids'], [firstId]);
    expect((command()['upserts'] as List).single['id'], secondId);
    expect(drafts.archiving.single.values['member_test_length'], '7.1');
    drafts.undoArchive(firstId);
    expect(command, throwsFormatException);
  });

  test('replacing a known identity needs a new profile with empty observations',
      () {
    cells(0)['identity_model'] = 'Replacement';
    expect(command, throwsFormatException);
    expect(() => first().identify(parentTemplate: parent, parentValues: values),
        throwsFormatException);
    drafts.archive(firstId);
    drafts.add(ProductSpecMemberDraft.forRow(
        id: newId,
        collection: loaded.collections.single,
        parentTemplate: parent,
        template: loaded.profiles.first.template,
        parentValues: values,
        rowId: 'r1'));
    final next = command();
    expect(next['archive_ids'], [firstId]);
    expect((next['upserts'] as List).last['values'], isEmpty);
    expect(() => drafts.undoArchive(firstId), throwsFormatException);
    drafts.archive(newId);
    // A discarded, unsaved profile never becomes a server archive request.
    expect(command()['archive_ids'], [firstId]);
  });

  test('catalog round trip and detach preserve the origin of each observation',
      () {
    final fixtures = jsonDecode(
        File('test/fixtures/product_spec_member_profiles.json')
            .readAsStringSync()) as Map;
    final historical =
        (fixtures['archived']['member_profiles']['archived_profiles'] as List)
            .first as Map;
    final profile =
        ((context['member_profiles'] as Map)['profiles'] as List).first as Map;
    profile['reference_id'] = historical['reference_id'];
    profile['reference'] = historical['reference'];
    profile['catalog_keys'] = ['member_test_length'];
    loaded = decodeProductSpecMemberProfiles(context);
    drafts = ProductSpecMemberDrafts(loaded);
    expect(first().isCatalogValue('member_test_length'), isTrue);
    expect((command()['upserts'] as List).first['values'].containsKey(lengthId),
        isFalse);
    first().selectReference(null);
    expect(first().values, {'member_test_included': true});
    first().selectReference(loaded.profiles.first.record.reference);
    expect(first().values['member_test_length'], '7.1');
    first().setValue('member_test_length', '7.1');
    expect(first().isCatalogValue('member_test_length'), isFalse);
    first().selectReference(null);
    expect(first().values,
        {'member_test_length': '7.1', 'member_test_included': true});
    expect((command()['upserts'] as List).first['values'][lengthId],
        {'number': '7.1'});
    expect(second().values['member_test_length'], '9007199254740993.2');
  });

  test('unknown model can be explicitly identified with its row evidence', () {
    cells(1)['identity_model'] = 'Model B';
    expect(command, throwsFormatException);
    second().identify(
        parentTemplate: parent,
        parentValues: values,
        manufacturerSku: ' SKU-B ');
    final saved = (command()['upserts'] as List)[1];
    expect(saved['binding_action'], 'identify');
    expect(saved['manufacturer_sku'], 'SKU-B');
    expect(saved['values'][lengthId], {'number': '9007199254740993.2'});
  });

  test('identification without evidence does not bless a changed identity', () {
    cells(1)['identity_model'] = 'Model B';
    rows()[1]['sources'] = [];
    expect(
        () => second().identify(parentTemplate: parent, parentValues: values),
        throwsFormatException);
    expect(second().identity.containsKey('identity_model'), isFalse);
  });

  test('rebind requires a chosen row of exactly the same confirmed identity',
      () {
    final draft = first();
    rows()[0]['id'] = 'r3';
    expect(command, throwsFormatException);
    draft.rebind(parentTemplate: parent, parentValues: values, rowId: 'r3');
    final rebound = (command()['upserts'] as List)[0];
    expect(rebound['id'], firstId);
    expect(rebound['member_row_id'], 'r3');
    expect(rebound['binding_action'], 'rebind');
    expect(
        () => draft.rebind(
            parentTemplate: parent, parentValues: values, rowId: 'r2'),
        throwsFormatException);
  });

  test('two profiles cannot claim the same identical row', () {
    rows()[1]['values'] = Map<String, dynamic>.from(cells(0));
    // Each draft is loaded before an edit, with matching identities.
    final duplicateContext =
        jsonDecode(jsonEncode(context)) as Map<String, dynamic>;
    ((duplicateContext['member_profiles'] as Map)['profiles'] as List)[1]
            ['member_identity'] =
        Map<String, dynamic>.from(loaded.profiles.first.record.memberIdentity);
    drafts = ProductSpecMemberDrafts(
        decodeProductSpecMemberProfiles(duplicateContext));
    second().rebind(parentTemplate: parent, parentValues: values, rowId: 'r1');
    expect(command, throwsFormatException);
  });

  test(
      'confirming unchanged identity preserves its evidence and a later rebind',
      () {
    rows().add({
      'id': 'r3',
      'values': Map<String, dynamic>.from(cells(0)),
      'sources': ['https://example.test/pack'],
    });
    rows()[0]['sources'] = [];
    first().identify(parentTemplate: parent, parentValues: values);
    expect((command()['upserts'] as List)[0].containsKey('binding_action'),
        isFalse);
    expect(first().identitySources, ['https://example.test/pack']);
    first().rebind(parentTemplate: parent, parentValues: values, rowId: 'r3');
    final rebound = drafts.forRow(collectionId, 'r3')!;
    rebound.identify(parentTemplate: parent, parentValues: values);
    expect((command()['upserts'] as List)[0]['binding_action'], 'rebind');
    expect(rebound.values['member_test_length'], '7.1');
  });

  test(
      'actual identification and rebind explain why they require separate saves',
      () {
    rows().add({
      'id': 'r3',
      'values': Map<String, dynamic>.from(cells(0)),
      'sources': ['https://example.test/pack'],
    });
    first().identify(
        parentTemplate: parent, parentValues: values, manufacturerSku: 'A-1');
    expect(
        () => first()
            .rebind(parentTemplate: parent, parentValues: values, rowId: 'r3'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'reason', contains('Guarda antes de vincular'))));
    final fresh = ProductSpecMemberDraft.fromProfile(loaded.profiles.first);
    fresh.rebind(parentTemplate: parent, parentValues: values, rowId: 'r3');
    expect(
        () => fresh.identify(
            parentTemplate: parent,
            parentValues: values,
            manufacturerSku: 'A-1'),
        throwsA(isA<FormatException>().having((e) => e.message, 'reason',
            contains('Guarda antes de confirmar'))));
    expect(fresh.manufacturerSku, isNull);
  });

  test('a missing answer is pending; impossible measurements block the save',
      () {
    first().setValue('member_test_length', '-1');
    expect(command, throwsFormatException);
    first().setValue('member_test_length', null);
    expect(first().validate().any((i) => !i.blocking), isTrue);
    expect((command()['upserts'] as List)[0]['values'].containsKey(lengthId),
        isFalse);
    expect(() => first().setValue('another_family_key', '8'),
        throwsFormatException);
  });

  test('family changes never redirect the saved observations to a new template',
      () {
    cells(0)['family'] = 'member_other_test';
    expect(command, throwsFormatException);
    expect(
        () => ProductSpecMemberDraft.forRow(
            id: newId,
            collection: loaded.collections.single,
            parentTemplate: parent,
            template: loaded.profiles.first.template,
            parentValues: values,
            rowId: 'r1'),
        throwsFormatException);
  });

  test(
      'removing the parent template requires explicit archival of its components',
      () {
    expect(() => drafts.buildCommand(parentTemplate: null, parentValues: {}),
        throwsFormatException);
    drafts.archive(firstId);
    drafts.archive(secondId);
    expect(drafts.buildCommand(parentTemplate: null, parentValues: {}), {
      'schema_version': 1,
      'upserts': [],
      'archive_ids': [firstId, secondId]
    });
  });

  test(
      'draft-template reader checks collection ownership before any field renders',
      () {
    final template = ((context['member_profiles'] as Map)['profiles']
        as List)[0]['template'] as Map;
    final draftContext = <String, dynamic>{
      'read_schema_version': 2,
      'revision': 0,
      'values': {},
      'parent_template_id': parent.id,
      'collection_definition_id': collectionId,
      'template_id': template['id'],
      'template_key': template['key'],
      'technical_family': template['technical_family'],
      'contract_version': template['contract_version'],
      'template': template
    };
    SpecTemplate decode() =>
        SpecEngineService.decodeProductMemberTemplate(draftContext,
            parentTemplateId: parent.id,
            collectionDefinitionId: collectionId,
            familyKey: 'member_part_test');
    expect(decode().technicalFamily, 'complete_brake');
    draftContext['collection_definition_id'] = lengthId;
    expect(decode, throwsFormatException);
    draftContext['collection_definition_id'] = collectionId;
    draftContext['template_key'] = 'member_other_test';
    expect(decode, throwsFormatException);
  });

  test(
      'a reference documenting a fact this template lacks blocks the save without deriving it',
      () {
    // A sibling template key of the same technical family may document a
    // definition that this component's template does not carry. The server
    // rederives every reference fact into the scope and refuses that one.
    first().selectReference(
        referenceWith({'member_test_length': '7.1', 'member_test_other': 'x'}));
    expect(first().values.containsKey('member_test_other'), isFalse);
    expect(first().isCatalogValue('member_test_other'), isFalse);
    expect(scopeIssues(first()), ['member_test_other']);
    expect(scopeIssues(second()), isEmpty);
    expect(
        command,
        throwsA(isA<FormatException>().having((error) => error.message,
            'message', contains('member_test_other'))));
    first().selectReference(null);
    expect(scopeIssues(first()), isEmpty);
    expect((command()['upserts'] as List)[0]['reference_id'], isNull);
  });

  test('a reference documenting a retired field needs the conserved value', () {
    for (final profile
        in (context['member_profiles'] as Map)['profiles'] as List) {
      ((profile['template'] as Map)['form_contract'] as Map)['roles']
          ['member_test_included'] = 'legacy';
    }
    loaded = decodeProductSpecMemberProfiles(context);
    drafts = ProductSpecMemberDrafts(loaded);
    final documented = referenceWith(
        {'member_test_length': '7.1', 'member_test_included': true});
    first().selectReference(documented);
    expect(scopeIssues(first()), isEmpty);
    expect(first().isCatalogValue('member_test_included'), isFalse);
    expect(() => first().setValue('member_test_included', false),
        throwsFormatException);
    first().selectReference(referenceWith(
        {'member_test_length': '7.1', 'member_test_included': false}));
    expect(scopeIssues(first()), ['member_test_included']);
    expect(first().values['member_test_included'], isTrue);
    // A new profile conserves nothing: the retired fact is neither derived
    // nor accepted, whatever the reference documents.
    drafts.archive(firstId);
    final fresh = ProductSpecMemberDraft.forRow(
        id: newId,
        collection: loaded.collections.single,
        parentTemplate: parent,
        template: loaded.profiles.first.template,
        parentValues: values,
        rowId: 'r1');
    drafts.add(fresh);
    fresh.selectReference(documented);
    expect(fresh.values['member_test_length'], '7.1');
    expect(fresh.values.containsKey('member_test_included'), isFalse);
    expect(scopeIssues(fresh), ['member_test_included']);
  });

  test(
      'a parent declaring other identity columns for the collection demands explicit archive',
      () {
    final draftContext =
        jsonDecode(jsonEncode(context)) as Map<String, dynamic>;
    final declaration = ((((draftContext['template'] as Map)['form_contract']
        as Map)['member_profiles'] as Map)['collections'] as List)[0] as Map;
    declaration['identity_columns'] = [
      'member_role',
      'identity_brand',
      'identity_model'
    ];
    final narrower =
        SpecEngineService.decodeProductSpecEditorContext(draftContext)
            .template!;
    expect(
        () =>
            drafts.buildCommand(parentTemplate: narrower, parentValues: values),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('archiva'))));
    expect(
        () => ProductSpecMemberDraft.forRow(
            id: newId,
            collection: loaded.collections.single,
            parentTemplate: narrower,
            template: loaded.profiles.first.template,
            parentValues: values,
            rowId: 'r1'),
        throwsFormatException);
    // The same columns in another order still name the same identity.
    declaration['identity_columns'] = [
      'identity_model',
      'identity_brand',
      'position',
      'member_role'
    ];
    final reordered =
        SpecEngineService.decodeProductSpecEditorContext(draftContext)
            .template!;
    expect(
        (drafts.buildCommand(
                parentTemplate: reordered,
                parentValues: values)['upserts'] as List)
            .length,
        2);
  });
}
