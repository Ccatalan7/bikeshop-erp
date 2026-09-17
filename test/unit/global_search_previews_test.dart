import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_previews.dart';

/// Una miniatura es un adorno; la velocidad es el producto.
///
/// Estas pruebas fijan cuándo **no** se pide nada: es la parte que, mal
/// resuelta, convierte una lista que contesta por tecla en una que espera.
void main() {
  GlobalSearchAttachment attachment({
    String name = 'catalogo.pdf',
    String extension = 'pdf',
    int? sizeBytes = 1024,
    String path = 'tenant/chat/catalogo.pdf',
  }) =>
      GlobalSearchAttachment(
        storagePath: path,
        fileName: name,
        extension: extension,
        contentType: 'application/pdf',
        origin: 'TeknoBike · WhatsApp',
        sizeBytes: sizeBytes,
      );

  test('una imagen siempre vale la pena', () {
    expect(
      GlobalSearchPreviews.canPreview(
        attachment(name: 'foto.jpg', extension: 'jpg', sizeBytes: 3400 * 1024),
      ),
      isTrue,
    );
  });

  test('un PDF que cabe en un vistazo se dibuja', () {
    expect(GlobalSearchPreviews.canPreview(attachment()), isTrue);
  });

  test('un PDF grande muestra su icono, no ocho megas de espera', () {
    expect(
      GlobalSearchPreviews.canPreview(
        attachment(sizeBytes: GlobalSearchPreviews.maxPdfBytes + 1),
      ),
      isFalse,
    );
  });

  test('sin tamaño conocido no se arriesga', () {
    expect(
        GlobalSearchPreviews.canPreview(attachment(sizeBytes: null)), isFalse);
    expect(GlobalSearchPreviews.canPreview(attachment(sizeBytes: 0)), isFalse);
  });

  test('un archivo que no es imagen ni PDF no tiene nada que mostrar', () {
    expect(
      GlobalSearchPreviews.canPreview(
        attachment(name: 'notas.txt', extension: 'txt'),
      ),
      isFalse,
    );
  });

  test('cada archivo se baja una sola vez, aunque se pida varias', () async {
    var downloads = 0;
    final previews = GlobalSearchPreviews(
      authorize: (path) async => 'https://example.test/firmada',
      download: (url) async {
        downloads++;
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
    );
    final photo = attachment(name: 'foto.jpg', extension: 'jpg');

    final first = await previews.thumbnail(photo);
    final second = await previews.thumbnail(photo);

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(downloads, 1, reason: 'el segundo pedido sale del caché');
  });

  test('pedir dos veces a la vez tampoco duplica la descarga', () async {
    var downloads = 0;
    final previews = GlobalSearchPreviews(
      authorize: (path) async => 'https://example.test/firmada',
      download: (url) async {
        downloads++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return Uint8List.fromList(<int>[9]);
      },
    );
    final photo = attachment(name: 'foto.jpg', extension: 'jpg');

    await Future.wait(<Future<Uint8List?>>[
      previews.thumbnail(photo),
      previews.thumbnail(photo),
    ]);

    expect(downloads, 1);
  });

  test('una descarga que falla deja el icono y no vuelve a intentarse',
      () async {
    var downloads = 0;
    final previews = GlobalSearchPreviews(
      authorize: (path) async => 'https://example.test/firmada',
      download: (url) async {
        downloads++;
        throw StateError('sin red');
      },
    );
    final photo = attachment(name: 'foto.jpg', extension: 'jpg');

    expect(await previews.thumbnail(photo), isNull);
    expect(await previews.thumbnail(photo), isNull);
    expect(downloads, 1, reason: 'el fracaso también se recuerda');
  });

  test('sin autorización no se baja nada', () async {
    var downloads = 0;
    final previews = GlobalSearchPreviews(
      authorize: (path) async => null,
      download: (url) async {
        downloads++;
        return Uint8List.fromList(<int>[1]);
      },
    );
    expect(
      await previews.thumbnail(attachment(name: 'f.jpg', extension: 'jpg')),
      isNull,
    );
    expect(downloads, 0);
  });
}
