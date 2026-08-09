import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

const _blockId = 'continuous-block';
const _scopeKey = 'root.title';

WebsiteEditModeProvider _provider() {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _blockId,
          'block_type': 'hero',
          'block_data': <String, dynamic>{'title': 'Uno'},
          'is_visible': true,
          'sort_order': 0,
        },
      ],
      const <String, dynamic>{},
      pageId: 'page-continuous',
      pageSlug: '/continuous',
    )
    ..selectBlock(_blockId);
}

String _title(WebsiteEditModeProvider provider) =>
    provider.getBlockData(_blockId)['title'] as String;

WebsiteInlineMutationResult _writeTitle(
  WebsiteEditModeProvider provider,
  String value,
) {
  provider.updateBlockData(_blockId, 'title', value);
  return WebsiteInlineMutationResult.committed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('many live ticks become one undo and one redo operation', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final edit = provider.beginContinuousFieldEdit(
      blockId: _blockId,
      scopeKey: _scopeKey,
      baselineValue: 'Uno',
    );
    expect(edit, isNotNull);

    for (final value in <String>['D', 'Do', 'Dos', 'Dos final']) {
      expect(
        provider.commitContinuousFieldEdit(
          edit!,
          _scopeKey,
          value,
          () => _writeTitle(provider, value),
        ),
        WebsiteInlineMutationResult.committed,
      );
      expect(_title(provider), value, reason: 'preview stays live per tick');
    }
    expect(
      provider.finishContinuousFieldEdit(edit!, _scopeKey),
      WebsiteInlineMutationResult.unchanged,
    );
    expect(provider.canUndo, isTrue);

    provider.undo();
    expect(_title(provider), 'Uno');
    expect(provider.canUndo, isFalse);
    expect(provider.canRedo, isTrue);

    provider.redo();
    expect(_title(provider), 'Dos final');
    expect(provider.canUndo, isTrue);
    expect(provider.canRedo, isFalse);
  });

  test('returning to the baseline restores history and dirty state', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final initialDocument = jsonDecode(jsonEncode(provider.blocks));
    final edit = provider.beginContinuousFieldEdit(
      blockId: _blockId,
      scopeKey: _scopeKey,
      baselineValue: 'Uno',
    )!;

    expect(
      provider.commitContinuousFieldEdit(
        edit,
        _scopeKey,
        'Dos',
        () => _writeTitle(provider, 'Dos'),
      ),
      WebsiteInlineMutationResult.committed,
    );
    expect(
      provider.commitContinuousFieldEdit(
        edit,
        _scopeKey,
        'Uno',
        () => _writeTitle(provider, 'Uno'),
      ),
      WebsiteInlineMutationResult.committed,
    );
    expect(
      provider.finishContinuousFieldEdit(edit, _scopeKey),
      WebsiteInlineMutationResult.unchanged,
    );
    expect(_title(provider), 'Uno');
    expect(provider.blocks, initialDocument);
    expect(provider.canUndo, isFalse);
    expect(provider.canRedo, isFalse);
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('baseline round-trip keeps the same focus session alive', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final edit = provider.beginContinuousFieldEdit(
      blockId: _blockId,
      scopeKey: _scopeKey,
      baselineValue: 'Uno',
    )!;

    for (final value in <String>['Un', 'Uno', 'Unox']) {
      expect(
        provider
            .commitContinuousFieldEdit(
              edit,
              _scopeKey,
              value,
              () => _writeTitle(provider, value),
            )
            .accepted,
        isTrue,
      );
    }
    expect(
      provider.finishContinuousFieldEdit(edit, _scopeKey).accepted,
      isTrue,
    );
    expect(_title(provider), 'Unox');
    expect(provider.canUndo, isTrue);
    provider.undo();
    expect(_title(provider), 'Uno');
    expect(provider.canUndo, isFalse);
  });

  test('cancel restores the exact pre-focus document and history', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final edit = provider.beginContinuousFieldEdit(
      blockId: _blockId,
      scopeKey: _scopeKey,
      baselineValue: 'Uno',
    )!;

    expect(
      provider.commitContinuousFieldEdit(
        edit,
        _scopeKey,
        'Borrador',
        () => _writeTitle(provider, 'Borrador'),
      ),
      WebsiteInlineMutationResult.committed,
    );
    expect(
      provider.cancelContinuousFieldEdit(edit, _scopeKey),
      WebsiteInlineMutationResult.committed,
    );

    expect(_title(provider), 'Uno');
    expect(provider.canUndo, isFalse);
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('field target mismatch and rejected inner writer fail closed', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final edit = provider.beginContinuousFieldEdit(
      blockId: _blockId,
      scopeKey: _scopeKey,
      baselineValue: 'Uno',
    )!;

    expect(
      provider.commitContinuousFieldEdit(
        edit,
        'root.subtitle',
        'No debe escribirse',
        () => _writeTitle(provider, 'No debe escribirse'),
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(_title(provider), 'Uno');

    expect(
      provider.commitContinuousFieldEdit(
        edit,
        _scopeKey,
        'Dos',
        () => WebsiteInlineMutationResult.rejected,
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(_title(provider), 'Uno');
    expect(provider.canUndo, isFalse);
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('external mutation invalidates edit without rolling it back on blur',
      () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final edit = provider.beginContinuousFieldEdit(
      blockId: _blockId,
      scopeKey: _scopeKey,
      baselineValue: 'Uno',
    )!;

    provider.updateBlockData(_blockId, 'title', 'Cambio externo');

    expect(
      provider.finishContinuousFieldEdit(edit, _scopeKey),
      WebsiteInlineMutationResult.rejected,
    );
    expect(_title(provider), 'Cambio externo');
    expect(provider.canUndo, isTrue);
    provider.undo();
    expect(_title(provider), 'Uno');
  });
}
