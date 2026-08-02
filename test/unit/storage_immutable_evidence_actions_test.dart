import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Una evidencia inmutable de anticipo no puede ofrecer acciones que el
/// servicio va a rechazar siempre.
///
/// `AppFileStorageService` rechaza borrar y reescribir estos archivos por
/// contrato. Dejar `Eliminar` y `Recortar` a la vista no es un detalle
/// estético: enseña al operador a ignorar errores, porque el único resultado
/// posible de pulsarlos es un error. La UI de Archivos es privada
/// (`_FileListTile`), así que el contrato se vigila sobre su fuente: es débil
/// como prueba de render, pero muerde exactamente en la regresión que importa
/// —que alguien quite la guarda—.
void main() {
  late String source;
  late String squashed;

  setUpAll(() async {
    source = await File('lib/modules/storage/widgets/app_files_panel.dart')
        .readAsString();
    squashed = source.replaceAll(RegExp(r'\s+'), '');
  });

  test('Eliminar está detrás de la guarda de inmutabilidad', () {
    final deleteIndex = squashed.indexOf("value:'delete'");
    expect(deleteIndex, greaterThan(0), reason: 'la acción sigue existiendo');
    // La guarda tiene que estar ANTES del item, en la misma construcción.
    final guardIndex = squashed.lastIndexOf(
      'isImmutablePayrollAdvanceEvidence(file)',
      deleteIndex,
    );
    expect(
      guardIndex,
      greaterThan(0),
      reason: 'Eliminar quedó sin la guarda de evidencia inmutable',
    );
    // La negación vive justo ANTES del nombre (`if (!AppFileStorage…`), que
    // el formateador puede dejar en la línea anterior.
    expect(
      squashed.substring(guardIndex - 60, guardIndex).contains('if(!'),
      isTrue,
      reason: 'la guarda debe NEGAR la inmutabilidad para mostrar Eliminar',
    );
  });

  test('Recortar está detrás de la guarda de inmutabilidad', () {
    final cropIndex = squashed.indexOf("tooltip:'Recortarimagen'");
    expect(cropIndex, greaterThan(0));
    final guardIndex = squashed.lastIndexOf(
      'isImmutablePayrollAdvanceEvidence(_file)',
      cropIndex,
    );
    expect(
      guardIndex,
      greaterThan(0),
      reason: 'Recortar quedó sin la guarda de evidencia inmutable',
    );
  });

  test('el diálogo abierto por deep link tampoco ofrece Recortar', () {
    final cropIndex = squashed.indexOf("tooltip:'Recortar'");
    expect(cropIndex, greaterThan(0), reason: 'el preview sigue existiendo');
    expect(
      squashed.lastIndexOf(
        'isImmutablePayrollAdvanceEvidence(_file)',
        cropIndex,
      ),
      greaterThan(0),
      reason: 'el callback del diálogo quedó habilitado para evidencia',
    );
    expect(
      squashed.lastIndexOf(
        'file.isImage&&onEditImage!=null',
        cropIndex,
      ),
      greaterThan(0),
      reason: 'el header debe ocultar Recortar, no sólo deshabilitarlo',
    );
  });

  test('Vista previa, Descargar y Abrir origen se conservan', () {
    // Lo que el servicio SÍ permite no se toca: quitarlo dejaría la evidencia
    // registrada y sin forma de mirarla.
    expect(source.contains("tooltip: 'Vista previa'"), isTrue);
    expect(source.contains("label: 'Descargar'"), isTrue);
    expect(source.contains("label: 'Abrir origen'"), isTrue);
  });

  test('nunca se muestra el error crudo al operador', () {
    for (final unsafe in <String>[
      'snapshot.error?.toString()',
      '_error = error.toString()',
      r"Text('No se pudo eliminar: $error')",
      r"Text('No se pudo descargar: $error')",
      r"Text('No se pudo guardar: $error')",
      r"Text('No se pudo imprimir: $error')",
    ]) {
      expect(
        source.contains(unsafe),
        isFalse,
        reason: 'un error crudo puede traer rutas de Storage o ids internos',
      );
    }
  });
}
