import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/desktop_release_notes.dart';

void main() {
  const fromCommit = '1111111111111111111111111111111111111111';
  const toCommit = '2222222222222222222222222222222222222222';

  Map<String, dynamic> validPayload() => {
        'schema_version': 1,
        'locale': 'es-CL',
        'source': 'ai',
        'from_commit': fromCommit,
        'to_commit': toCommit,
        'title': 'Novedades de esta actualización',
        'summary': 'Mejoramos tareas cotidianas del sistema.',
        'modules': [
          {
            'id': 'workshop',
            'label': 'Taller',
            'items': [
              'Ahora es más fácil revisar y descargar presupuestos.',
            ],
            'evidence_paths': [
              'lib/modules/bikeshop/pages/pegas_table_page.dart',
            ],
          },
        ],
      };

  test('accepts a bounded es-CL plain-text payload', () {
    final notes = DesktopReleaseNotes.tryParse(
      validPayload(),
      expectedToCommit: toCommit,
    );

    expect(notes, isNotNull);
    expect(notes!.title, 'Novedades de esta actualización');
    expect(notes.modules.single.label, 'Taller');
    expect(
      notes.modules.single.items.single,
      'Ahora es más fácil revisar y descargar presupuestos.',
    );
  });

  test('returns null when notes are absent or the target commit mismatches',
      () {
    expect(DesktopReleaseNotes.tryParse(null), isNull);
    expect(
      DesktopReleaseNotes.tryParse(
        validPayload(),
        expectedToCommit: fromCommit,
      ),
      isNull,
    );
  });

  test('rejects an unknown module or a noncanonical module label', () {
    final unknownModule = validPayload();
    unknownModule['modules'] = [
      {
        'id': 'surprise',
        'label': 'Sorpresas',
        'items': ['Hay cambios nuevos.'],
        'evidence_paths': ['lib/main.dart'],
      },
    ];
    expect(DesktopReleaseNotes.tryParse(unknownModule), isNull);

    final wrongLabel = validPayload();
    (wrongLabel['modules'] as List).first['label'] = 'Workshop';
    expect(DesktopReleaseNotes.tryParse(wrongLabel), isNull);
  });

  test('rejects oversized, malformed, Markdown, HTML, and URL content', () {
    final oversized = validPayload();
    (oversized['modules'] as List).first['items'] = [
      List.filled(161, 'x').join(),
    ];
    expect(DesktopReleaseNotes.tryParse(oversized), isNull);

    for (final unsafeText in const [
      '**Cambio importante**',
      '<b>Cambio importante</b>',
      'Más detalles en https://example.com',
      'Primera línea\nSegunda línea',
    ]) {
      final unsafe = validPayload();
      (unsafe['modules'] as List).first['items'] = [unsafeText];
      expect(
        DesktopReleaseNotes.tryParse(unsafe),
        isNull,
        reason: unsafeText,
      );
    }
  });

  test('rejects duplicate modules and unsafe evidence paths', () {
    final duplicate = validPayload();
    duplicate['modules'] = [
      (duplicate['modules'] as List).first,
      {
        'id': 'workshop',
        'label': 'Taller',
        'items': ['También mejoramos otra parte.'],
        'evidence_paths': ['lib/main.dart'],
      },
    ];
    expect(DesktopReleaseNotes.tryParse(duplicate), isNull);

    final unsafePath = validPayload();
    (unsafePath['modules'] as List).first['evidence_paths'] = [
      '../outside.dart',
    ];
    expect(DesktopReleaseNotes.tryParse(unsafePath), isNull);
  });

  test('allows empty evidence only for the deterministic fallback', () {
    final fallback = validPayload()..['source'] = 'fallback';
    (fallback['modules'] as List).first['evidence_paths'] = <String>[];
    expect(DesktopReleaseNotes.tryParse(fallback), isNotNull);

    final ai = validPayload();
    (ai['modules'] as List).first['evidence_paths'] = <String>[];
    expect(DesktopReleaseNotes.tryParse(ai), isNull);
  });
}
