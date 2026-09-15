import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_profile.dart';

// Synthetic contexts exported from the local SQL cases. Their values exercise
// the reader contract; they are not component measurements or OEM claims.
const _product = '99e10000-0000-4000-8000-000000000020';
const _otherId = '99e10000-0000-4000-8000-000000000099';
const _collection = '99e10000-0000-4000-8000-000000000051';
const _length = '99e10000-0000-4000-8000-000000000052';
const _details = '99e10000-0000-4000-8000-000000000054';
const _first = '99e10000-0000-4000-8000-000000000081';
const _second = '99e10000-0000-4000-8000-000000000082';

Map<String, dynamic> _context(String name) =>
    (jsonDecode(File('test/fixtures/product_spec_member_profiles.json')
            .readAsStringSync()) as Map<String, dynamic>)[name]
        as Map<String, dynamic>;

Map<String, dynamic> _block(Map<String, dynamic> context) =>
    context['member_profiles'] as Map<String, dynamic>;

Map<String, dynamic> _profile(Map<String, dynamic> context, int index,
        {bool archived = false}) =>
    (_block(context)[archived ? 'archived_profiles' : 'profiles']
        as List)[index] as Map<String, dynamic>;

Map<String, dynamic> _row(Map<String, dynamic> context, int index) =>
    (((context['values'] as Map)['member_test_collection'] as Map)['rows']
        as List)[index]['values'] as Map<String, dynamic>;

Map<String, dynamic> _copy(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, dynamic> _reference() =>
    _copy(_profile(_context('archived'), 0, archived: true)['reference']);

Matcher _rejects(String fragment) => throwsA(isA<FormatException>()
    .having((error) => error.message, 'message', contains(fragment)));

Iterable<String> _codes(Iterable issues) =>
    issues.map((issue) => '${issue.code}:${issue.fieldKey}');

void main() {
  test(
      'save receipt supplies the confirmed context and rejects another revision',
      () {
    final context = _context('active');
    final receipt = <String, dynamic>{
      'product': {
        'id': context['product_id'],
        'spec_revision': context['revision'],
        'updated_at': context['product_updated_at'],
      },
      'revision': context['revision'],
      'editor_context': context,
    };
    final saved =
        decodeProductSpecSavedEditorContext(receipt, withMembers: true)!;
    expect(decodeProductSpecMemberProfiles(saved).profiles, hasLength(2));
    context['revision'] = (context['revision'] as int) + 1;
    expect(
        () => decodeProductSpecSavedEditorContext(receipt, withMembers: true),
        _rejects('otra revisión'));
    expect(decodeProductSpecSavedEditorContext({}, withMembers: false), isNull);
  });
  test('category preview retains the persisted owner for explicit archival',
      () {
    final context = _context('active');
    context['member_parent_context'] = _copy(context);
    context['template_id'] = null;
    context['template'] = null;
    context['values'] = <String, dynamic>{};
    final decoded = decodeProductSpecMemberProfiles(context);
    expect(decoded.collections, isEmpty);
    expect(decoded.profiles, hasLength(2));
    expect(decoded.profiles.first.collection.definitionId, _collection);
    expect(decoded.profiles.first.values['member_test_length'], '7.1');
    (context['member_parent_context'] as Map)['revision'] =
        (context['revision'] as int) + 1;
    expect(() => decodeProductSpecMemberProfiles(context),
        _rejects('dueño guardado pertenece a otro producto o revisión'));
  });
  test('empty collections still declare canonical brand and model columns', () {
    final context = _context('active');
    _block(context)['profiles'] = [];
    final collection = (context['template']['form_contract']['member_profiles']
            ['collections'] as List)
        .single as Map;
    collection['identity_columns'] = [
      'member_role',
      'position',
      'identity_brand'
    ];
    expect(() => decodeProductSpecMemberProfiles(context),
        _rejects('columna de identidad inválida'));
  });
  group('active context', () {
    test('option ids must belong to the displayed labels of this definition',
        () {
      final context = _context('active');
      const finishId = '99e10000-0000-4000-8000-000000000055';
      const silverId = '99e10000-0000-4000-8000-000000000056';
      const goldId = '99e10000-0000-4000-8000-000000000057';
      for (final profile in _block(context)['profiles'] as List) {
        final fields = profile['template']['fields'] as List;
        final field = _copy(fields[1]);
        field['spec_definition_id'] = finishId;
        field['spec_definitions'] = {
          ...field['spec_definitions'] as Map,
          'id': finishId,
          'key': 'member_test_finish',
          'label': 'Finish',
          'data_type': 'single_select',
          'validation_rules': {},
          'allowed_values': ['Silver', 'Gold'],
          'spec_definition_values': [
            {'id': silverId, 'label': 'Silver'},
            {'id': goldId, 'label': 'Gold'}
          ],
        };
        fields.add(field);
      }
      final profile = _profile(context, 0);
      (profile['values'] as Map)['member_test_finish'] = 'Silver';
      (profile['fact_payload'] as Map)[finishId] = {
        'value_ids': [silverId]
      };
      expect(
          decodeProductSpecMemberProfiles(context)
              .profiles
              .first
              .values['member_test_finish'],
          'Silver');
      (profile['fact_payload'] as Map)[finishId] = {
        'value_ids': [goldId]
      };
      expect(() => decodeProductSpecMemberProfiles(context),
          _rejects('opciones de otro campo'));
      (profile['fact_payload'] as Map)[finishId] = {
        'value_ids': [_otherId]
      };
      expect(() => decodeProductSpecMemberProfiles(context),
          _rejects('opciones de otro campo'));
      (profile['fact_payload'] as Map)[finishId] = {
        'value_ids': [silverId, silverId]
      };
      expect(() => decodeProductSpecMemberProfiles(context),
          _rejects('sin transporte exacto'));
    });

    test('two components of one family keep their own exact measures', () {
      final decoded = decodeProductSpecMemberProfiles(_context('active'),
          expectedProductId: _product, expectedRevision: 7);
      expect(decoded.productId, _product);
      expect(decoded.revision, 7);
      expect(decoded.productUpdatedAt, isNotEmpty);
      expect(decoded.archivedProfiles, isEmpty);
      final collection = decoded.collections.single;
      expect(collection.fieldKey, 'member_test_collection');
      expect(collection.familyColumn, 'family');
      expect(collection.identityColumns,
          ['member_role', 'position', 'identity_brand', 'identity_model']);

      final first = decoded.activeFor(_collection, 'r1')!;
      final second = decoded.activeFor(_collection, 'r2')!;
      expect([first.id, second.id], [_first, _second]);
      expect(decoded.editable(_second), same(second));
      // The row names the template key; the technical family is another word.
      expect(first.template.key, 'member_part_test');
      expect(first.template.technicalFamily, 'complete_brake');
      expect(identical(first.template, second.template), isFalse);
      expect(first.isStale, isFalse);

      expect(first.values['member_test_length'], '7.1');
      expect(second.values['member_test_length'], '9007199254740993.2');
      expect(
          second.record.factPayload[_length], {'number': '9007199254740993.2'});
      expect(first.record.scope, 'member:$_first');
      expect(first.record.memberIdentity, {
        'family': 'member_part_test',
        'position': 'front',
        'member_role': 'caliper',
        'identity_brand': 'Fixture',
        'identity_model': 'Model A',
      });
      expect(
          second.record.memberIdentity.containsKey('identity_model'), isFalse);
      expect(first.record.identitySources, ['https://example.test/pack']);
      expect(first.record.catalogKeys, isEmpty);
      expect(first.record.reference, isNull);
      expect(first.record.manufacturerSku, isNull);

      final issues = decoded.validateAll();
      expect(issues.keys, [_first, _second]);
      expect(issues.values.every((list) => list.isEmpty), isTrue);
      expect(() => first.values['member_test_length'] = '1',
          throwsUnsupportedError);
      expect(() => first.record.identitySources.add('https://example.test/x'),
          throwsUnsupportedError);
      expect(() => second.record.factPayload.remove(_length),
          throwsUnsupportedError);
    });

    test('a draft is validated against its own component only', () {
      final decoded = decodeProductSpecMemberProfiles(_context('active'));
      final first = decoded.profiles[0];
      final second = decoded.profiles[1];
      expect(
          _codes(
              second.validate({...second.values, 'member_test_length': '0'})),
          contains('range:member_test_length'));
      expect(
          _codes(second.validate({
            'member_test_length': '9007199254740993.2',
            'member_test_included': false,
          })),
          contains('field_applicability:member_test_length'));
      expect(first.validate(), isEmpty);
      expect(first.values['member_test_length'], '7.1');
    });

    test('intrinsic contents rows are conserved and validated', () {
      final context = _context('active');
      final rows = {
        'schema_version': 2,
        'rows': [
          {
            'id': 'd1',
            'values': {'inner': '10.5', 'outer': '12'},
            'sources': ['https://example.test/member-manual'],
          }
        ],
      };
      _profile(context, 0)['values']['member_test_details'] = _copy(rows);
      _profile(context, 0)['fact_payload'][_details] = {'rows': _copy(rows)};
      final decoded = decodeProductSpecMemberProfiles(context);
      final first = decoded.profiles[0];
      expect(first.values['member_test_details'], rows);
      expect(first.record.factPayload[_details], {'rows': rows});
      expect(first.validate(), isEmpty);

      final inverted = _copy(first.values);
      inverted['member_test_details']['rows'][0]['values']['inner'] = '12';
      final issues = first.validate(inverted);
      expect(_codes(issues), ['row_shape:member_test_details']);
      expect(issues.single.blocking, isTrue);
      expect(decoded.profiles[1].validate(), isEmpty);
    });

    test('a reference is read by identity and judged per component', () {
      final context = _context('active');
      for (final index in [0, 1]) {
        _profile(context, index)['reference_id'] = 'member-test-reference';
        _profile(context, index)['reference'] = _reference();
      }
      final decoded = decodeProductSpecMemberProfiles(context);
      final first = decoded.profiles[0];
      final second = decoded.profiles[1];
      expect(first.record.reference!.id, 'member-test-reference');
      expect(first.record.reference!.facts,
          {'member_test_length': '7.1', 'member_test_included': true});
      expect(first.validate(), isEmpty);
      // The rear member confirmed no model and measured something else.
      expect(
          _codes(second.validate()),
          containsAll([
            'reference_identity:',
            'reference_conflict:member_test_length'
          ]));

      final crossFamily = _context('active');
      _profile(crossFamily, 0)['reference_id'] = 'member-test-reference';
      _profile(crossFamily, 0)['reference'] = _reference()
        ..['technical_family'] = 'drivetrain_kit';
      expect(
          _codes(decodeProductSpecMemberProfiles(crossFamily)
              .profiles[0]
              .validate()),
          contains('reference_identity:'));
    });

    test('server issues attached to the profile are kept', () {
      final context = _context('active');
      _profile(context, 0)['issues'] = [
        {
          'code': 'required_missing',
          'field': 'member_test_length',
          'message': 'Length: falta confirmar este dato.',
          'blocking': false,
          'profile_id': _first,
          'member_row_id': 'r1',
          'collection_definition_id': _collection,
        }
      ];
      final issue = decodeProductSpecMemberProfiles(context)
          .profiles[0]
          .serverIssues
          .single;
      expect(issue.code, 'required_missing');
      expect(issue.fieldKey, 'member_test_length');
      expect(issue.blocking, isFalse);
    });
  });

  group('archived context', () {
    test('archived evidence is preserved and never editable', () {
      final decoded = decodeProductSpecMemberProfiles(_context('archived'),
          expectedProductId: _product, expectedRevision: 21);
      expect(decoded.profiles, isEmpty);
      expect(decoded.archivedProfiles.map((p) => p.id), [_first, _second]);
      final first = decoded.archivedProfiles[0];
      final second = decoded.archivedProfiles[1];
      expect(first.archivedAt, isNotEmpty);
      expect(first.record.referenceId, 'member-test-reference');
      expect(first.record.reference!.family, 'complete_brake');
      expect(first.record.reference!.sources,
          ['https://example.test/member-manual']);
      expect(first.record.catalogKeys,
          ['member_test_included', 'member_test_length']);
      expect(second.record.memberRowId, 'r3');
      expect(second.record.memberIdentity['identity_model'], 'Model B');
      expect(second.values['member_test_length'], '9007199254740993.2');
      expect(decoded.activeFor(_collection, 'r1'), isNull);
      expect(() => decoded.editable(_first), throwsStateError);
      expect(() => decoded.editable(_otherId), throwsStateError);
    });

    test('a new product keeps its component collections and empty history', () {
      final context = _context('active')
        ..['product_id'] = null
        ..['revision'] = 0
        ..['member_profiles'] = {
          'read_schema_version': 1,
          'product_id': null,
          'revision': 0,
          'product_updated_at': null,
          'profiles': [],
          'archived_profiles': [],
        };
      final decoded = decodeProductSpecMemberProfiles(context);
      expect(decoded.productId, isNull);
      expect(decoded.collections.single.definitionId, _collection);
      expect(decoded.profiles, isEmpty);
      expect(decoded.archivedProfiles, isEmpty);
    });
  });

  group('rejects', () {
    test('a read of another product or revision', () {
      expect(
          () => decodeProductSpecMemberProfiles(_context('active'),
              expectedProductId: _otherId),
          _rejects('la lectura pertenece a otro producto'));
      expect(
          () => decodeProductSpecMemberProfiles(_context('active'),
              expectedRevision: 6),
          _rejects('otra revisión'));
    });

    Map<String, dynamic> archivedCopyOfFirst(Map<String, dynamic> context) =>
        _copy(_profile(context, 0))
          ..remove('template')
          ..['archived_at'] = '2026-09-14T20:10:00+00:00'
          ..['active_template_guard'] = null;

    final cases =
        <(String, String, void Function(Map<String, dynamic>), String)>[
      (
        'block of another product',
        'active',
        (c) => _block(c)['product_id'] = _otherId,
        'no corresponde al producto y revisión raíz'
      ),
      (
        'block of another revision',
        'active',
        (c) => _block(c)['revision'] = 6,
        'no corresponde al producto y revisión raíz'
      ),
      (
        'short block for a saved product',
        'active',
        (c) => _block(c)
          ..remove('archived_profiles')
          ..remove('product_updated_at'),
        'no corresponde al producto y revisión raíz'
      ),
      (
        'profiles without a product',
        'active',
        (c) {
          c['product_id'] = null;
          _block(c)['product_id'] = null;
        },
        'un contexto sin producto no tiene perfiles'
      ),
      (
        'profile of another product',
        'active',
        (c) => _profile(c, 0)['product_id'] = _otherId,
        'el perfil pertenece a otro producto'
      ),
      (
        'scope of another profile',
        'active',
        (c) => _profile(c, 1)['scope'] = 'member:$_first',
        'alcance'
      ),
      (
        'product-level scope',
        'active',
        (c) => _profile(c, 0)['scope'] = null,
        'alcance'
      ),
      (
        'same id active and archived',
        'active',
        (c) => (_block(c)['archived_profiles'] as List)
            .add(archivedCopyOfFirst(c)),
        'repetido'
      ),
      (
        'row absent from the parent',
        'active',
        (c) => _profile(c, 0)['member_row_id'] = 'r9',
        'falta la fila r9'
      ),
      (
        'collection not declared by the parent',
        'active',
        (c) => _profile(c, 0)['collection_definition_id'] = _length,
        'no está declarada'
      ),
      (
        'two active profiles for one row',
        'active',
        (c) {
          _profile(c, 1)['member_row_id'] = 'r1';
          _profile(c, 1)['member_identity'] =
              _copy(_profile(c, 0)['member_identity']);
        },
        'misma fila'
      ),
      (
        'identity of another row',
        'active',
        (c) => _profile(c, 0)['member_identity']['identity_model'] = 'Model B',
        'la identidad no corresponde a la fila r1'
      ),
      (
        'row family of another template',
        'active',
        (c) {
          _row(c, 0)['family'] = 'member_other_test';
          _profile(c, 0)['member_identity']['family'] = 'member_other_test';
        },
        'la familia de la fila no es la de su plantilla'
      ),
      (
        'technical family used as row family',
        'active',
        (c) {
          _row(c, 0)['family'] = 'complete_brake';
          _profile(c, 0)['member_identity']['family'] = 'complete_brake';
        },
        'no declara una familia de la colección'
      ),
      (
        'template of the parent',
        'active',
        (c) => _profile(c, 0)['template_id'] =
            '99e10000-0000-4000-8000-000000000050',
        'la plantilla no corresponde al perfil'
      ),
      (
        'rounded value',
        'active',
        (c) => _profile(c, 0)['values']['member_test_length'] = 7.1,
        'número redondeado'
      ),
      (
        'rounded stored number',
        'active',
        (c) => _profile(c, 1)['fact_payload']
            [_length] = {'number': 9007199254740993.2},
        'número redondeado'
      ),
      (
        'stored text of a rounded number',
        'active',
        (c) => _profile(c, 1)['fact_payload']
            [_length] = {'number': '9007199254740992'},
        'member_test_length difiere de su valor almacenado'
      ),
      (
        'fact outside the member template',
        'active',
        (c) {
          _profile(c, 0)['values']['member_test_collection'] = 'x';
          _profile(c, 0)['fact_payload'][_otherId] = {'text': 'x'};
        },
        'no pertenece a la plantilla del componente'
      ),
      (
        'archived profile among active ones',
        'active',
        (c) => _profile(c, 0)['archived_at'] = '2026-09-14T20:10:00+00:00',
        'estado de archivo inconsistente'
      ),
      (
        'archived profile still guarding a row',
        'archived',
        (c) => _profile(c, 0, archived: true)['active_template_guard'] = true,
        'estado de archivo inconsistente'
      ),
      (
        'archived profile with an editable template',
        'archived',
        (c) => _profile(c, 0, archived: true)['template'] =
            _profile(_context('active'), 0)['template'],
        'campos de perfil inesperados'
      ),
      (
        'reference of another id',
        'active',
        (c) {
          _profile(c, 0)['reference_id'] = 'member-test-reference';
          _profile(c, 0)['reference'] = _reference()
            ..['id'] = 'other-reference';
        },
        'la referencia no corresponde al perfil'
      ),
      (
        'reference without identifier',
        'active',
        (c) => _profile(c, 0)['reference'] = _reference(),
        'referencia sin identificador'
      ),
      (
        'issue of another component',
        'active',
        (c) => _profile(c, 0)['issues'] = [
              {
                'code': 'required_missing',
                'field': 'member_test_length',
                'message': 'x',
                'profile_id': _second,
                'member_row_id': 'r1',
                'collection_definition_id': _collection,
              }
            ],
        'otro componente'
      ),
      (
        'catalog key without a fact',
        'active',
        (c) => _profile(c, 0)['catalog_keys'] = ['member_test_details'],
        'claves de catálogo'
      ),
      (
        'unknown profile key',
        'active',
        (c) => _profile(c, 0)['member_parent_id'] = _otherId,
        'campos de perfil inesperados'
      ),
    ];
    for (final (name, fixture, mutate, fragment) in cases) {
      test(name, () {
        final context = _context(fixture);
        mutate(context);
        expect(
            () => decodeProductSpecMemberProfiles(context), _rejects(fragment));
      });
    }
  });
}
