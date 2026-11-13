import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// La carpeta pública «Descargas» de Android, la que abre «Archivos».
///
/// `getDownloadsDirectory()` devuelve en Android una carpeta propia de la app
/// (`Android/data/com.vinabike.erp/files/downloads`) que «Archivos» no muestra
/// desde Android 11: el aviso decía «guardada en…» con una ruta cierta y nadie
/// podía llegar a ella (el dueño con una etiqueta de despacho, 2026-11-13). A la
/// carpeta pública sólo se entra por `MediaStore`, así que la copia la hace el
/// lado nativo (`PublicDownloads.kt`).
///
/// Los bytes no viajan por el canal: se escriben en la caché de la app y el
/// lado nativo copia el archivo, que es lo que aguanta un respaldo de decenas
/// de MB sin duplicarlo en memoria.
class AndroidPublicDownloads {
  const AndroidPublicDownloads({
    this.channel = const MethodChannel('com.vinabike.erp/public_downloads'),
    this.temporaryDirectory = getTemporaryDirectory,
  });

  final MethodChannel channel;
  final Future<Directory> Function() temporaryDirectory;

  /// Deja [bytes] en «Descargas» como [fileName] y devuelve la ruta donde
  /// quedó. Devuelve `null` cuando este Android no tiene la colección pública
  /// (antes de Android 10): quien llama conserva su carpeta de siempre.
  ///
  /// El nombre que queda puede no ser el pedido: si ya existía, Android le
  /// agrega «(1)», y la ruta devuelta es la real.
  Future<String?> save({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final root = Directory(
      '${(await temporaryDirectory()).path}/public_downloads',
    );
    await root.create(recursive: true);
    // Una carpeta por descarga: dos descargas simultáneas del mismo nombre no
    // se pisan mientras el lado nativo copia.
    final staging = await root.createTemp('d');
    try {
      final file = File('${staging.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return await channel.invokeMethod<String>('save', <String, Object?>{
        'path': file.path,
        'fileName': fileName,
        'mimeType': mimeType,
      });
    } finally {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // La caché la limpia el sistema; no vale la pena fallar una descarga
        // que ya quedó guardada por no poder borrar su copia de paso.
      }
    }
  }
}
