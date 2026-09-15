import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

/// Guards the narrowing half of the guided ficha cascade.
///
/// `visibility_rules` answers whether a field exists given the sibling
/// answers. It cannot answer which of its options are still possible, which is
/// the other half: a BSA shell admits 68/73/83/100 mm, a Pressfit shell admits
/// 86.5/89.5/92/121. That is `option_rules`, and these tests pin the semantics
/// the migration writes against.
SpecTemplateField field({
  List<Map<String, dynamic>> visibility = const [],
  List<Map<String, dynamic>> options = const [],
}) {
  return SpecTemplateField(
    specDefinitionId: 'definition',
    sectionKey: 'compatibility',
    sortOrder: 10,
    isRequired: false,
    visibilityRules: visibility,
    optionRules: options,
  );
}

void main() {
  group('option rules narrow the offerable set', () {
    test('a field with no rules is left unconstrained', () {
      expect(field().allowedOptionsFor({'bb_shell_standard': 'BSA 1.37x24'}),
          isNull);
    });

    test('a rule that does not match leaves the field unconstrained', () {
      final width = field(options: [
        {
          'field': 'bb_shell_standard',
          'operator': 'eq',
          'value': 'Italiano 36x24',
          'allow': [70],
        },
      ]);

      expect(
        width.allowedOptionsFor({'bb_shell_standard': 'BSA 1.37x24'}),
        isNull,
        reason: 'an unmatched rule must not narrow the field to nothing',
      );
    });

    test('the matching rule decides which widths exist', () {
      final width = field(options: [
        {
          'field': 'bb_shell_standard',
          'operator': 'in',
          'value': ['BSA 1.37x24', 'BB30 42mm'],
          'allow': [68, 73, 83, 100],
        },
        {
          'field': 'bb_shell_standard',
          'operator': 'eq',
          'value': 'Italiano 36x24',
          'allow': [70],
        },
      ]);

      expect(
        width.allowedOptionsFor({'bb_shell_standard': 'BSA 1.37x24'}),
        {'68', '73', '83', '100'},
      );
      expect(
        width.allowedOptionsFor({'bb_shell_standard': 'Italiano 36x24'}),
        {'70'},
        reason: 'a single surviving option is what lets the form stop asking',
      );
    });

    test('several matching rules intersect rather than accumulate', () {
      final spindle = field(options: [
        {
          'field': 'bb_construction',
          'operator': 'eq',
          'value': 'Copas externas',
          'allow': ['Hollowtech / 24mm', 'SRAM GXP 24/22', 'SRAM DUB 28.99mm'],
        },
        {
          'field': 'bb_shell_standard',
          'operator': 'eq',
          'value': 'BSA 1.37x24',
          'allow': ['Hollowtech / 24mm', 'SRAM GXP 24/22', 'Cuadrado JIS'],
        },
      ]);

      expect(
        spindle.allowedOptionsFor({
          'bb_construction': 'Copas externas',
          'bb_shell_standard': 'BSA 1.37x24',
        }),
        {'Hollowtech / 24mm', 'SRAM GXP 24/22'},
        reason: 'both conditions hold, so only what both admit survives',
      );
    });
  });

  group('rule values compare across the JSON/stored type boundary', () {
    test('a numeric rule matches a value stored as a decimal string', () {
      // Live bike profiles hold `"73.0"` beside `"73"` for the same shell.
      final width = field(options: [
        {
          'field': 'bb_shell_width_mm',
          'operator': 'eq',
          'value': 73,
          'allow': ['Hollowtech / 24mm'],
        },
      ]);

      expect(
        width.allowedOptionsFor({'bb_shell_width_mm': '73.0'}),
        {'Hollowtech / 24mm'},
      );
    });

    test('allowed numeric options normalize to their stored spelling', () {
      final length = field(options: [
        {
          'field': 'includes_spindle',
          'operator': 'eq',
          'value': true,
          'allow': [103, 122.5, 124.5],
        },
      ]);

      expect(
        length.allowedOptionsFor({'includes_spindle': true}),
        {'103', '122.5', '124.5'},
        reason: '124.5 is a real catalog value; it must survive normalization',
      );
    });
  });

  group('visibility keeps its own semantics', () {
    test('a boolean condition gates the spindle measurements', () {
      final spindleLength = field(visibility: [
        {'field': 'includes_spindle', 'operator': 'eq', 'value': true},
      ]);

      expect(spindleLength.isVisible({'includes_spindle': true}), isTrue);
      expect(spindleLength.isVisible({'includes_spindle': false}), isFalse);
      expect(
        spindleLength.isVisible(const {}),
        isFalse,
        reason: 'an unanswered gate must not expose the field it guards',
      );
    });

    test('threaded shells hide the bore diameter', () {
      final bore = field(visibility: [
        {
          'field': 'bb_shell_standard',
          'operator': 'in',
          'value': ['BB86 / BB92 41mm', 'PF30 46mm', 'BB30 42mm'],
        },
      ]);

      expect(bore.isVisible({'bb_shell_standard': 'PF30 46mm'}), isTrue);
      expect(bore.isVisible({'bb_shell_standard': 'BSA 1.37x24'}), isFalse);
    });
  });

  test('rules survive a round trip through the row shape', () {
    final parsed = SpecTemplateField.fromJson({
      'spec_definition_id': 'definition',
      'section_key': 'dimensions',
      'sort_order': 50,
      'is_required': true,
      'visibility_rules': [
        {'field': 'includes_spindle', 'operator': 'eq', 'value': true},
      ],
      'option_rules': [
        {
          'field': 'bb_shell_standard',
          'operator': 'eq',
          'value': 'BSA 1.37x24',
          'allow': [68, 73, 83, 100],
        },
      ],
    });

    expect(parsed.visibilityRules, hasLength(1));
    expect(parsed.optionRules, hasLength(1));
    expect(
      parsed.allowedOptionsFor({
        'includes_spindle': true,
        'bb_shell_standard': 'BSA 1.37x24',
      }),
      {'68', '73', '83', '100'},
    );
  });

  test('a row without option_rules parses as unconstrained', () {
    final parsed = SpecTemplateField.fromJson({
      'spec_definition_id': 'definition',
      'section_key': 'general',
      'sort_order': 0,
      'is_required': false,
      'visibility_rules': [],
    });

    expect(parsed.optionRules, isEmpty);
    expect(parsed.allowedOptionsFor(const {}), isNull);
  });
}
