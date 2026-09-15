import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_number.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_spec_inference_utils.dart';
import 'package:vinabike_erp/modules/inventory/utils/spec_rule_evaluator.dart';

// Independent boundary regressions. These values exercise serialization and
// validation; they are not measurements or manufacturer compatibility claims.
SpecTemplate _numericTemplate({
  Map<String, dynamic> validation = const {},
}) =>
    SpecTemplate(
      id: 'numeric-transport-template',
      key: 'numeric-transport-template',
      name: 'Numeric transport fixture',
      technicalFamily: 'fixture',
      formContract: const {'rules_version': 2},
      fields: [
        SpecTemplateField(
          specDefinitionId: 'numeric-definition',
          sectionKey: 'dimensions',
          sortOrder: 0,
          isRequired: false,
          visibilityRules: const [],
          definition: SpecDefinition(
            id: 'numeric-definition',
            key: 'magnitude',
            label: 'Magnitude',
            dataType: 'number',
            options: const [],
            sortOrder: 0,
            validationRules: validation,
          ),
        ),
      ],
    );

List<ProductSpecIssue> _issues(Object? value,
        {Map<String, dynamic> validation = const {}}) =>
    validateProductSpecDraft(
      template: _numericTemplate(validation: validation),
      values: {'magnitude': value},
    );

Object? _wireValue(Object? value) {
  final payload = SpecEngineService.buildFactPayload(
      _numericTemplate(), {'magnitude': value});
  // Exercise the JSON boundary as used by the RPC client, not just a Dart map.
  final decoded = jsonDecode(jsonEncode(payload)) as Map;
  return (decoded['numeric-definition'] as Map?)?['number'];
}

SpecTemplate _dependentTemplate() {
  const whenMagnitude = {
    'kind': 'when',
    'rows': [
      [
        {
          'field': 'magnitude',
          'value_type': 'decimal',
          'operator': 'eq',
          'value': '28.6',
        },
      ],
    ],
  };
  return SpecTemplate(
    id: 'dependent-numeric-template',
    key: 'dependent-numeric-template',
    name: 'Numeric condition fixture',
    technicalFamily: 'fixture',
    formContract: const {
      'rules_version': 2,
      'allowed_when': {'dependent': whenMagnitude},
      'required_when': {'dependent': whenMagnitude},
    },
    fields: [
      ..._numericTemplate().fields,
      SpecTemplateField(
        specDefinitionId: 'dependent-definition',
        sectionKey: 'dimensions',
        sortOrder: 1,
        isRequired: false,
        visibilityRules: const [],
        definition: const SpecDefinition(
          id: 'dependent-definition',
          key: 'dependent',
          label: 'Dependent answer',
          dataType: 'text',
          options: [],
          sortOrder: 1,
        ),
      ),
    ],
  );
}

Map<String, dynamic> _editorReadFixture() => _readJson({
      'read_schema_version': 2,
      'product_id': 'numeric-transport-product',
      'template_id': 'numeric-read-template',
      'template_key': 'numeric-read-template',
      'technical_family': 'fixture',
      'contract_version': 7,
      'revision': 11,
      'binding_source': 'explicit',
      'values': {
        'magnitude': '9007199254740993.125',
        'model_code': '01',
        'included': false,
      },
      'template': {
        'id': 'numeric-read-template',
        'key': 'numeric-read-template',
        'name': 'Atomic numeric read fixture',
        'technical_family': 'fixture',
        'tenant_id': null,
        'contract_version': 7,
        'form_contract': {'rules_version': 2},
        'fields': [
          {
            'spec_definition_id': 'numeric-definition',
            'section_key': 'dimensions',
            'sort_order': 20,
            'is_required': false,
            'visibility_rules': [],
            'option_rules': [],
            'constraint_rules': [],
            'default_value_json': '9007199254740993.120',
            'spec_definitions': {
              'id': 'numeric-definition',
              'key': 'magnitude',
              'label': 'Magnitude',
              'data_type': 'number',
              'allowed_values': [],
              'validation_rules': {
                'min': '9007199254740993.12',
                'max': '9007199254740993.13',
              },
              'unit': 'mm',
              'sort_order': 20,
            },
          },
          {
            'spec_definition_id': 'code-definition',
            'section_key': 'identity',
            'sort_order': 10,
            'is_required': false,
            'visibility_rules': [],
            'option_rules': [],
            'constraint_rules': [],
            'spec_definitions': {
              'id': 'code-definition',
              'key': 'model_code',
              'label': 'Model code',
              'data_type': 'single_select',
              'allowed_values': ['01', '1'],
              'validation_rules': {},
              'sort_order': 10,
              'spec_definition_values': [
                {'id': 'code-01', 'label': '01'},
                {'id': 'code-1', 'label': '1'},
              ],
            },
          },
          {
            'spec_definition_id': 'boolean-definition',
            'section_key': 'contents',
            'sort_order': 30,
            'is_required': false,
            'visibility_rules': [],
            'option_rules': [],
            'constraint_rules': [],
            'spec_definitions': {
              'id': 'boolean-definition',
              'key': 'included',
              'label': 'Included',
              'data_type': 'boolean',
              'allowed_values': [],
              'validation_rules': {},
              'sort_order': 30,
            },
          },
        ],
      },
    });

Map<String, dynamic> _readJson(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Map<String, dynamic> _numericReadField(Map<String, dynamic> snapshot) =>
    ((snapshot['template'] as Map)['fields'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere(
            (field) => field['spec_definition_id'] == 'numeric-definition');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('scalar transport preserves the decimal observation', () {
    for (final entry in {
      '28,60': '28.6',
      ' -6.50 ': '-6.5',
      '0.12345678901234567890123456789': '0.12345678901234567890123456789',
      '9007199254740993': '9007199254740993',
      '9007199254740993.125': '9007199254740993.125',
      '1e-400': '0.${'0' * 399}1',
      '1e309': '1${'0' * 309}',
    }.entries) {
      test('JSON round trip of ${entry.key}', () {
        expect(_wireValue(entry.key), entry.value);
      });
    }

    test('empty is omitted while known zero is serialized as decimal text', () {
      expect(_wireValue(null), isNull);
      expect(_wireValue(''), isNull);
      expect(_wireValue(0), '0');
    });

    test('legacy num beyond the shared safe integer bound is rejected', () {
      // Parsing avoids a large integer literal being rounded by a web compiler.
      final inherited = num.parse('9007199254740992');
      expect(_issues(inherited).any((issue) => issue.blocking), isTrue);
      expect(() => _wireValue(inherited), throwsFormatException);
    });
  });

  group('validation compares exact decimal values before serialization', () {
    test('a fractional tail cannot satisfy an integer constraint', () {
      expect(
        _issues('1.00000000000000001', validation: {'integer': true})
            .any((issue) => issue.code == 'integer' && issue.blocking),
        isTrue,
      );
    });

    test('binary rounding cannot hide an excess over an ordinary maximum', () {
      expect(
        _issues('0.100000000000000001', validation: {'max': 0.1})
            .any((issue) => issue.blocking),
        isTrue,
      );
    });

    test('a tiny positive decimal cannot underflow into a nonpositive value',
        () {
      expect(_issues('1e-400', validation: {'positive': true}), isEmpty);
    });

    test('finite PostgreSQL numeric need not fit a double', () {
      expect(_issues('1e309'), isEmpty);
    });

    test('exact metadata limits can be decimal text', () {
      expect(
        _issues('9007199254740993.125',
            validation: {'min': '9007199254740993.126'}),
        contains(isA<ProductSpecIssue>()
            .having((issue) => issue.blocking, 'blocking', isTrue)),
      );
    });

    for (final value in ['0e-16384', '0e1073741824']) {
      test('zero cannot conceal a PostgreSQL input bound: $value', () {
        expect(_issues(value).any((issue) => issue.blocking), isTrue);
        expect(() => _wireValue(value), throwsFormatException);
      });
    }
  });

  group('invalid and incomplete values are retained and cannot be saved', () {
    for (final value in ['-', '.', '1e-', '1,2.3', 'NaN', 'Infinity']) {
      test(value, () {
        expect(isMeaningfulProductSpecValue(value), isTrue);
        final draft = pruneStaleAutoDerivedProductSpecValues(
          baseValues: {'magnitude': value},
          manualKeys: {'magnitude'},
          previousAutoValues: {'magnitude': '28.6'},
        );
        final issues = validateProductSpecDraft(
            template: _numericTemplate(), values: draft);
        expect(issues.any((issue) => issue.blocking), isTrue);
        expect(draft['magnitude'], value);
        final persisted = omitAutoDerivedProductSpecValues(
            values: draft, autoDerivedValues: {'magnitude': '28.6'});
        expect(persisted['magnitude'], value);
        expect(
            () => SpecEngineService.buildFactPayload(
                _numericTemplate(), persisted),
            throwsFormatException);
        expect(draft['magnitude'], value);
      });
    }
  });

  group('shared scalar number API has explicit input and PostgreSQL bounds',
      () {
    test('local decimal input is canonicalized without guessing grouping', () {
      expect(productSpecNumberWireValue(' +2,860e1 '), '28.6');
      expect(productSpecNumberWireValue('1,234'), '1.234');
      expect(productSpecNumberWireValue('-.500'), '-0.5');
      expect(productSpecNumberWireValue('1.'), '1');
      for (final invalid in ['1,234.5', '1 234', '1e2,5']) {
        expect(productSpecNumber(invalid), isNull);
        expect(
            () => productSpecNumberWireValue(invalid), throwsFormatException);
      }
    });

    test('the inherited num policy is symmetric and does not coerce types', () {
      expect(productSpecNumberWireValue(0.1), '0.1');
      expect(productSpecNumberWireValue(num.parse('9007199254740991')),
          '9007199254740991');
      expect(productSpecNumberWireValue(num.parse('-9007199254740991')),
          '-9007199254740991');
      for (final invalid in <Object?>[
        num.parse('9007199254740992'),
        num.parse('-9007199254740992'),
        double.nan,
        double.infinity,
        double.negativeInfinity,
        true,
        ['1'],
        {'number': '1'},
      ]) {
        expect(productSpecNumber(invalid), isNull);
        expect(productSpecNumberErrorCode(invalid, const {}), 'type');
        expect(
            () => productSpecNumberWireValue(invalid), throwsFormatException);
      }
    });

    test('scale bounds apply to zero and to the original input scale', () {
      expect(productSpecNumberWireValue('0e-16383'), '0');
      expect(productSpecNumberWireValue('1e-16383'), '0.${'0' * 16382}1');
      for (final invalid in ['0e-16384', '1e-16384', '0.0e-16383']) {
        expect(productSpecNumberErrorCode(invalid, const {}), 'type');
        expect(
            () => productSpecNumberWireValue(invalid), throwsFormatException);
      }
    });

    test('integer digit and exponent limits do not require a machine number',
        () {
      expect(productSpecNumberWireValue('1e131071'), '1${'0' * 131071}');
      expect(productSpecNumberWireValue('0e1073741823'), '0');
      for (final invalid in ['1e131072', '0e1073741824']) {
        expect(productSpecNumberErrorCode(invalid, const {}), 'type');
        expect(
            () => productSpecNumberWireValue(invalid), throwsFormatException);
      }
    });

    test('a very negative exponent cannot wrap while subtracting its scale',
        () {
      for (final invalid in [
        '0.0e-9223372036854775808',
        '0.00e-9223372036854775807',
        '1.1e-9223372036854775808',
      ]) {
        // Do not render a wrongly accepted extreme decimal: this assertion
        // targets parser rejection before canonical string allocation.
        expect(productSpecNumber(invalid), isNull, reason: invalid);
      }
    });

    test('integer validation distinguishes magnitude from decimal notation',
        () {
      expect(productSpecNumberErrorCode('1.00', {'integer': true}), isNull);
      expect(productSpecNumberErrorCode('1.01e2', {'integer': true}), isNull);
      expect(productSpecNumberErrorCode('-0.00', {'integer': true}), isNull);
      expect(
          productSpecNumberErrorCode('1.00000000000000001', {'integer': true}),
          'integer');
      expect(productSpecNumberErrorCode('-0', {'positive': true}), 'positive');
    });

    for (final rules in <Map<String, dynamic>>[
      {'min': 'not-a-limit'},
      {'max': num.parse('9007199254740992')},
    ]) {
      test('an unreadable present limit is not silently ignored: $rules', () {
        expect(productSpecNumberErrorCode('1', rules), 'invalid_rules');
        expect(_issues('1', validation: rules).any((issue) => issue.blocking),
            isTrue);
        expect(
            () => SpecEngineService.buildFactPayload(
                _numericTemplate(validation: rules), {'magnitude': '1'}),
            throwsFormatException);
      });
    }

    test('null limits preserve SQL semantics of an unbounded side', () {
      const rules = <String, dynamic>{'min': null, 'max': null};
      expect(productSpecNumberErrorCode('1', rules), isNull);
      expect(_issues('1', validation: rules), isEmpty);
    });
  });

  group('raw local decimal input keeps template conditions coherent', () {
    for (final raw in ['28,6', ' 28.6 ', '+2,86e1']) {
      test(raw, () {
        final template = _dependentTemplate();
        final dependent = template.fields.last;
        final draft = <String, dynamic>{'magnitude': raw};
        expect(template.applicabilityFor(dependent, draft), SpecTruth.yes);
        expect(template.requiredFor(dependent, draft), SpecTruth.yes);
        expect(
          validateProductSpecDraft(template: template, values: draft),
          contains(isA<ProductSpecIssue>()
              .having((issue) => issue.fieldKey, 'field', 'dependent')
              .having((issue) => issue.code, 'code', 'required_missing')
              .having((issue) => issue.blocking, 'blocking', isFalse)),
        );
        expect(draft['magnitude'], raw);
      });
    }

    test('incomplete numeric text remains unknown for its dependent field', () {
      final template = _dependentTemplate();
      for (final raw in ['-', '1e-']) {
        final draft = {'magnitude': raw};
        expect(template.applicabilityFor(template.fields.last, draft),
            SpecTruth.unknown);
        expect(_issues(raw).any((issue) => issue.blocking), isTrue);
        expect(draft['magnitude'], raw);
      }
    });
  });

  group('atomic editor read decoder preserves its numeric transport contract',
      () {
    test('JSON fixture reaches draft and outgoing payload without rounding',
        () {
      final wire = _readJson(_editorReadFixture());
      final context = SpecEngineService.decodeProductSpecEditorContext(wire);
      final template = context.template!;
      expect(template.id, wire['template_id']);
      expect(template.contractVersion, 7);
      expect(template.fields.map((field) => field.definition!.key),
          ['model_code', 'magnitude', 'included']);
      final numeric = template.fields[1];
      expect(numeric.defaultValue, '9007199254740993.120');
      expect(numeric.definition!.validationRules['min'], '9007199254740993.12');
      expect(numeric.definition!.validationRules['max'], '9007199254740993.13');

      final draft =
          Map<String, dynamic>.from(context.snapshot['values'] as Map);
      expect(draft['magnitude'], '9007199254740993.125');
      expect(draft['model_code'], '01');
      expect(draft['included'], isFalse);
      expect(
          validateProductSpecDraft(template: template, values: draft), isEmpty);
      final payload =
          _readJson(SpecEngineService.buildFactPayload(template, draft));
      expect(payload, {
        'numeric-definition': {'number': '9007199254740993.125'},
        'code-definition': {
          'value_ids': ['code-01']
        },
        'boolean-definition': {'boolean': false},
      });
      // The second fixture exercises the decoder after the outgoing JSON
      // boundary. It does not stand in for an executed database read-back.
      final second = _editorReadFixture();
      (second['values'] as Map)['magnitude'] =
          (payload['numeric-definition'] as Map)['number'];
      final readAgain =
          SpecEngineService.decodeProductSpecEditorContext(_readJson(second));
      expect((readAgain.snapshot['values'] as Map)['magnitude'],
          '9007199254740993.125');
    });

    test('decoding an exact out-of-range value does not bless the draft', () {
      final wire = _editorReadFixture();
      (wire['values'] as Map)['magnitude'] = '9007199254740993.131';
      final context =
          SpecEngineService.decodeProductSpecEditorContext(_readJson(wire));
      final draft =
          Map<String, dynamic>.from(context.snapshot['values'] as Map);
      expect(
          validateProductSpecDraft(template: context.template!, values: draft)
              .any((issue) => issue.blocking && issue.code == 'range'),
          isTrue);
      expect(() => SpecEngineService.buildFactPayload(context.template!, draft),
          throwsFormatException);
    });

    for (final location in ['observation', 'default', 'min', 'max']) {
      test('$location must arrive as exact wire text, not local editor text',
          () {
        for (final invalid in <Object>[28.6, '28,6', ' 28.6 ', '0e-16384']) {
          final wire = _editorReadFixture();
          final field = _numericReadField(wire);
          if (location == 'observation') {
            (wire['values'] as Map)['magnitude'] = invalid;
          } else if (location == 'default') {
            field['default_value_json'] = invalid;
          } else {
            ((field['spec_definitions'] as Map)['validation_rules']
                as Map)[location] = invalid;
          }
          expect(
              () => SpecEngineService.decodeProductSpecEditorContext(
                  _readJson(wire)),
              throwsFormatException,
              reason: '$location: $invalid');
        }
      });
    }

    for (final identity in [
      'template_id',
      'template_key',
      'technical_family',
      'contract_version',
    ]) {
      test('the snapshot cannot disagree with template $identity', () {
        final wire = _editorReadFixture();
        wire[identity] = identity == 'contract_version' ? 8 : 'other';
        expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
            throwsFormatException);
      });
    }

    test('field and joined definition must identify the same object', () {
      final wire = _editorReadFixture();
      _numericReadField(wire)['spec_definition_id'] = 'other-definition';
      expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
          throwsFormatException);
    });

    for (final duplicate in ['id', 'key']) {
      test('two fields cannot collapse onto the same definition $duplicate',
          () {
        final wire = _editorReadFixture();
        final copied = _readJson(_numericReadField(wire));
        if (duplicate == 'id') {
          (copied['spec_definitions'] as Map)['key'] = 'other_magnitude';
        } else {
          copied['spec_definition_id'] = 'other-definition';
          (copied['spec_definitions'] as Map)['id'] = 'other-definition';
        }
        ((wire['template'] as Map)['fields'] as List).add(copied);
        expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
            throwsFormatException);
      });
    }

    test('revision must be a nonnegative exactly transportable integer', () {
      for (final revision in <Object>[
        -1,
        '11',
        11.5,
        num.parse('9007199254740992'),
      ]) {
        final wire = _editorReadFixture()..['revision'] = revision;
        expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
            throwsFormatException,
            reason: '$revision');
      }
    });

    test('read schema version must have the supported integer type', () {
      for (final version in [null, '2', 2.0, 3]) {
        final wire = _editorReadFixture()..['read_schema_version'] = version;
        expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
            throwsFormatException,
            reason: '$version (${version.runtimeType})');
      }
    });

    test('contract versions cannot agree only through numeric coercion', () {
      final wire = _editorReadFixture()..['contract_version'] = 7.0;
      expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
          throwsFormatException);
    });

    test('malformed numeric validation metadata cannot become an empty map',
        () {
      for (final invalid in <Object>['invalid-rules', [], true, 42]) {
        final wire = _editorReadFixture();
        (_numericReadField(wire)['spec_definitions']
            as Map)['validation_rules'] = invalid;
        expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
            throwsFormatException,
            reason: '$invalid');
      }
    });

    test('a missing v2 definition type cannot silently become text', () {
      final wire = _editorReadFixture();
      (_numericReadField(wire)['spec_definitions'] as Map).remove('data_type');
      expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
          throwsFormatException);
    });

    test('a missing v2 form contract cannot silently erase field conditions',
        () {
      final wire = _editorReadFixture();
      (wire['template'] as Map).remove('form_contract');
      expect(() => SpecEngineService.decodeProductSpecEditorContext(wire),
          throwsFormatException);
    });

    test('an unassigned product can still load with no template or values', () {
      final context = SpecEngineService.decodeProductSpecEditorContext({
        'read_schema_version': 2,
        'revision': 0,
        'template_id': null,
        'template': null,
        'values': <String, dynamic>{},
      });
      expect(context.template, isNull);
      expect(context.snapshot['values'], isEmpty);
    });
  });

  group('service selects the exact v2 read without a second metadata request',
      () {
    final requests = <http.Request>[];
    late Map<String, dynamic> editorReply;
    late List<Map<String, dynamic>> referenceReply;
    var unavailable = false;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      await Supabase.initialize(
        url: 'https://numeric-fixture.invalid',
        anonKey: 'numeric-fixture-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (unavailable) {
            return http.Response(
                '{"code":"PGRST202","message":"V2 fixture unavailable"}', 404,
                request: request,
                headers: {'content-type': 'application/json'});
          }
          final path = request.url.path;
          final Object response;
          if (path.endsWith('/rpc/get_product_spec_editor_context_v2')) {
            response = editorReply;
          } else if (path.endsWith('/rpc/get_product_spec_references_v2')) {
            response = referenceReply;
          } else {
            throw StateError('Unexpected read or fallback: $path');
          }
          return http.Response(jsonEncode(response), 200,
              request: request,
              headers: {'content-type': 'application/json'});
        }),
      );
    });

    tearDownAll(() async => Supabase.instance.dispose());

    setUp(() {
      requests.clear();
      unavailable = false;
      editorReply = _editorReadFixture()
        ..['draft_category_id'] = 'numeric-category';
      referenceReply = [
        {
          'read_schema_version': 2,
          'id': 'numeric-reference',
          'technical_family': 'fixture',
          'brand': 'Synthetic',
          'model': 'Example',
          'label': 'Numeric boundary fixture',
          'facts': {'magnitude': '9007199254740993.125'},
          'sources': ['https://example.test/fixture'],
        },
      ];
    });

    test('product read includes the matching category in one atomic request',
        () async {
      final context = await SpecEngineService.instance.getProductEditorContext(
          productId: 'numeric-transport-product',
          categoryId: 'numeric-category');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path,
          '/rest/v1/rpc/get_product_spec_editor_context_v2');
      expect(jsonDecode(requests.single.body), {
        'p_product_id': 'numeric-transport-product',
        'p_category_id': 'numeric-category',
      });
      expect((context.snapshot['values'] as Map)['magnitude'],
          '9007199254740993.125');
      expect(context.template!.fields[1].definition!.validationRules['min'],
          '9007199254740993.12');
    });

    test('category consumer also receives exact metadata through v2', () async {
      editorReply
        ..['product_id'] = null
        ..['revision'] = 0
        ..['values'] = <String, dynamic>{};
      final template = await SpecEngineService.instance
          .getTemplateForCategory('numeric-category');
      expect(requests, hasLength(1));
      expect(requests.single.url.path,
          '/rest/v1/rpc/get_product_spec_editor_context_v2');
      expect(jsonDecode(requests.single.body), {
        'p_product_id': null,
        'p_category_id': 'numeric-category',
      });
      expect(template!.fields[1].definition!.validationRules['max'],
          '9007199254740993.13');
    });

    for (final mismatch in ['product_id', 'draft_category_id']) {
      test('a different $mismatch is rejected without retry or fallback',
          () async {
        editorReply[mismatch] = 'other';
        await expectLater(
            SpecEngineService.instance.getProductEditorContext(
                productId: 'numeric-transport-product',
                categoryId: 'numeric-category'),
            throwsFormatException);
        expect(requests, hasLength(1));
      });
    }

    test('manufacturer reference is read through v2 before DTO decoding',
        () async {
      final rows = await SpecEngineService.instance.getReferences('fixture');
      final reference = ProductSpecReference.fromJson(rows.single);
      expect(requests, hasLength(1));
      expect(requests.single.url.path,
          '/rest/v1/rpc/get_product_spec_references_v2');
      expect(jsonDecode(requests.single.body), {'p_family': 'fixture'});
      expect(reference.facts['magnitude'], '9007199254740993.125');
    });

    test('an old reference reply is rejected without trying v1', () async {
      referenceReply.single['read_schema_version'] = 1;
      await expectLater(SpecEngineService.instance.getReferences('fixture'),
          throwsFormatException);
      expect(requests, hasLength(1));
    });

    test('missing v2 RPC fails instead of loading an imprecise v1 snapshot',
        () async {
      unavailable = true;
      await expectLater(
          SpecEngineService.instance.getProductEditorContext(
              productId: 'numeric-transport-product',
              categoryId: 'numeric-category'),
          throwsA(isA<PostgrestException>()));
      expect(requests, hasLength(1));
    });
  });
}
