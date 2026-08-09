import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const persistedConstructors = <String, List<String>>{
    'lib/modules/website/widgets/editor_panel/schema_controls.dart': [
      'ResponsiveMediaField',
      'WebsiteActionEditor',
      'WebsiteColorPickerField',
      'WebsiteLinkValueEditor',
      '_VideoPicker',
    ],
    'lib/modules/website/widgets/editor_panel/carousel_controls.dart': [
      'ResponsiveMediaField',
      'WebsiteActionEditor',
      '_ImagePicker',
    ],
    'lib/modules/website/widgets/editor_panel/canvas_controls.dart': [
      'WebsiteActionEditor',
      'WebsiteColorPickerField',
      '_ImagePicker',
      '_VideoPicker',
    ],
    'lib/modules/website/widgets/editor_panel/products_controls.dart': [
      'WebsiteActionEditor',
    ],
    'lib/modules/website/widgets/editable_block_renderer.dart': [
      'InlineEditableImage',
      'WebsiteInlineActionEditor',
    ],
  };

  test('every persisted async field callsite supplies its exact binding', () {
    for (final fileEntry in persistedConstructors.entries) {
      final source = File(fileEntry.key).readAsStringSync();
      for (final constructor in fileEntry.value) {
        final calls = _constructorCalls(source, constructor);
        expect(
          calls,
          isNotEmpty,
          reason: '$constructor must remain visible to this ownership guard',
        );
        for (final call in calls) {
          expect(
            call,
            contains('asyncBinding:'),
            reason: '$constructor in ${fileEntry.key} must be armed',
          );
        }
      }
    }
  });

  test('every persisted editor text field supplies its exact binding', () {
    const files = <String>[
      'lib/modules/website/widgets/editor_panel/schema_controls.dart',
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
      'lib/modules/website/widgets/editor_panel/canvas_controls.dart',
      'lib/modules/website/widgets/editor_panel/products_controls.dart',
    ];

    for (final path in files) {
      final calls = _constructorCalls(
        File(path).readAsStringSync(),
        '_EditorTextField',
      );
      expect(calls, isNotEmpty, reason: '$path must contain persisted text');
      for (final call in calls) {
        expect(
          call,
          contains('asyncBinding:'),
          reason: '_EditorTextField in $path must arm its exact owner',
        );
      }
    }
  });

  test('every persisted editor slider supplies identity and exact binding', () {
    const constructorsByFile = <String, String>{
      'lib/modules/website/widgets/editor_panel/schema_controls.dart':
          '_EditorSlider',
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart':
          '_EditorSlider',
      'lib/modules/website/widgets/editor_panel/canvas_controls.dart':
          '_EditorSlider',
      'lib/modules/website/widgets/editor_panel/edit_block_tab.dart':
          'WebsiteTransactionalSlider',
      'lib/modules/website/widgets/editor_panel/theme_tab.dart':
          'WebsiteTransactionalSlider',
    };

    for (final entry in constructorsByFile.entries) {
      final path = entry.key;
      final constructor = entry.value;
      final calls = _constructorCalls(
        File(path).readAsStringSync(),
        constructor,
      );
      expect(calls, isNotEmpty, reason: '$path must contain an active slider');
      for (final call in calls) {
        expect(
          call,
          contains('transactionIdentity:'),
          reason: '$constructor in $path must name its semantic owner',
        );
        expect(
          call,
          contains('asyncBinding:'),
          reason: '$constructor in $path must arm its exact persisted owner',
        );
      }
    }
  });

  test('every text formatting toolbar names its transactional owner', () {
    const files = <String>[
      'lib/modules/website/widgets/editor_panel/schema_controls.dart',
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
      'lib/modules/website/widgets/inline_editable_text_v2.dart',
    ];

    for (final path in files) {
      final calls = _constructorCalls(
        File(path).readAsStringSync(),
        'TextFormattingToolbar',
      );
      expect(calls, isNotEmpty, reason: '$path must mount text formatting');
      for (final call in calls) {
        expect(
          call,
          contains('transactionIdentity:'),
          reason: 'TextFormattingToolbar in $path must name its semantic owner',
        );
        if (!path.endsWith('inline_editable_text_v2.dart')) {
          expect(
            call,
            contains('asyncBinding:'),
            reason: 'persisted TextFormattingToolbar in $path must be armed',
          );
        }
      }
    }

    final toolbar = File(
      'lib/modules/website/widgets/text_formatting_toolbar.dart',
    ).readAsStringSync();
    expect(toolbar, contains('WebsiteTransactionalSlider('));
    expect(
      RegExp(r'\bSlider\s*\(').hasMatch(toolbar),
      isFalse,
      reason: 'text-formatting sliders must not persist raw pointer ticks',
    );
  });

  test('every persisted focal gesture supplies its exact binding', () {
    const mediaHosts = <String>[
      'lib/modules/website/widgets/editor_panel/schema_controls.dart',
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
    ];
    for (final path in mediaHosts) {
      final calls = _constructorCalls(
        File(path).readAsStringSync(),
        'ResponsiveMediaField',
      );
      expect(calls, isNotEmpty);
      for (final call in calls) {
        expect(call, contains('focalAsyncBinding:'), reason: path);
      }
    }

    const focalHosts = <String>[
      'lib/modules/website/widgets/responsive_media_field.dart',
      'lib/modules/website/widgets/editor_panel/canvas_controls.dart',
    ];
    for (final path in focalHosts) {
      final calls = _constructorCalls(
        File(path).readAsStringSync(),
        'FocalPointPicker',
      );
      expect(calls, isNotEmpty);
      for (final call in calls) {
        expect(call, contains('asyncBinding:'), reason: path);
      }
    }
  });
}

List<String> _constructorCalls(String source, String constructor) {
  final calls = <String>[];
  var searchFrom = 0;
  final needle = '$constructor(';

  while (true) {
    final start = source.indexOf(needle, searchFrom);
    if (start < 0) return calls;
    final preceding = start == 0 ? '' : source[start - 1];
    if (RegExp(r'[A-Za-z0-9_]').hasMatch(preceding)) {
      searchFrom = start + needle.length;
      continue;
    }

    var depth = 0;
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    var end = -1;

    for (var index = start + constructor.length;
        index < source.length;
        index++) {
      final char = source[index];
      final next = index + 1 < source.length ? source[index + 1] : '';

      if (lineComment) {
        if (char == '\n') lineComment = false;
        continue;
      }
      if (blockComment) {
        if (char == '*' && next == '/') {
          blockComment = false;
          index++;
        }
        continue;
      }
      if (quote.isNotEmpty) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '/' && next == '/') {
        lineComment = true;
        index++;
        continue;
      }
      if (char == '/' && next == '*') {
        blockComment = true;
        index++;
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        continue;
      }
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          end = index + 1;
          break;
        }
      }
    }

    expect(end, greaterThan(start), reason: 'Unclosed $constructor call');
    calls.add(source.substring(start, end));
    searchFrom = end;
  }
}
