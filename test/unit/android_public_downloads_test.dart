import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/utils/android_public_downloads.dart';
import 'package:vinabike_erp/shared/utils/file_download_result.dart';

/// Una descarga en Android tiene que quedar en «Descargas», la carpeta que abre
/// «Archivos» (dueño, 2026-11-13: bajó una etiqueta de despacho y quedó en
/// `Android/data/com.vinabike.erp/files/downloads`, donde nadie entra).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/public_downloads');
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('public_downloads_test');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  AndroidPublicDownloads downloads() => AndroidPublicDownloads(
        channel: channel,
        temporaryDirectory: () async => temp,
      );

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  test('hands the file to Android and says where it ended up', () async {
    MethodCall? received;
    List<int>? staged;
    answer((call) async {
      received = call;
      final arguments = call.arguments as Map<Object?, Object?>;
      staged = File(arguments['path']! as String).readAsBytesSync();
      return '/storage/emulated/0/Download/Etiqueta WEB-26-00022 (1).pdf';
    });

    final saved = await downloads().save(
      bytes: const [37, 80, 68, 70],
      fileName: 'Etiqueta WEB-26-00022.pdf',
      mimeType: 'application/pdf',
    );

    // Android renombra un duplicado: la ruta que cuenta es la suya.
    expect(saved, '/storage/emulated/0/Download/Etiqueta WEB-26-00022 (1).pdf');
    expect(received!.method, 'save');
    final arguments = received!.arguments as Map<Object?, Object?>;
    expect(arguments['fileName'], 'Etiqueta WEB-26-00022.pdf');
    expect(arguments['mimeType'], 'application/pdf');
    // El archivo viaja por la caché de la app, que es de donde el lado nativo
    // acepta leer, y con el contenido completo.
    expect(arguments['path']! as String, startsWith(temp.path));
    expect(
        arguments['path']! as String, endsWith('/Etiqueta WEB-26-00022.pdf'));
    expect(staged, const [37, 80, 68, 70]);
  });

  test('leaves no copy behind in the cache', () async {
    answer((call) async => '/storage/emulated/0/Download/respaldo.zip');

    await downloads().save(
      bytes: List<int>.filled(4096, 7),
      fileName: 'respaldo.zip',
      mimeType: 'application/zip',
    );

    final leftovers = Directory('${temp.path}/public_downloads')
        .listSync(recursive: true)
        .whereType<File>();
    expect(leftovers, isEmpty);
  });

  test('an Android without the public folder answers nothing', () async {
    answer((call) async => null);

    final saved = await downloads().save(
      bytes: const [1, 2, 3],
      fileName: 'informe.pdf',
      mimeType: 'application/pdf',
    );

    expect(saved, isNull);
  });

  test('a refusal reaches the caller and still cleans the cache', () async {
    answer(
      (call) async => throw PlatformException(
        code: 'save_failed',
        message: 'Android no pudo crear el archivo en Descargas.',
      ),
    );

    await expectLater(
      downloads().save(
        bytes: const [1, 2, 3],
        fileName: 'informe.pdf',
        mimeType: 'application/pdf',
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'save_failed'),
      ),
    );
    final leftovers = Directory('${temp.path}/public_downloads')
        .listSync(recursive: true)
        .whereType<File>();
    expect(leftovers, isEmpty);
  });

  group('where the notice says the file is', () {
    test('the phone\'s public folder is called Descargas', () {
      const result = FileDownloadResult.saved(
        '/storage/emulated/0/Download/Etiqueta WEB-26-00022.pdf',
      );
      expect(result.readablePath, 'Descargas/Etiqueta WEB-26-00022.pdf');
    });

    test('a second profile on the phone reads the same', () {
      const result =
          FileDownloadResult.saved('/storage/emulated/10/Download/a.pdf');
      expect(result.readablePath, 'Descargas/a.pdf');
    });

    test('any other place is said as it is', () {
      const mac = FileDownloadResult.saved('/Users/taller/Downloads/a.pdf');
      const private = FileDownloadResult.saved(
        '/storage/emulated/0/Android/data/com.vinabike.erp/files/downloads/a.pdf',
      );
      expect(mac.readablePath, '/Users/taller/Downloads/a.pdf');
      expect(private.readablePath, private.path);
    });

    test('no path, nothing to say', () {
      expect(const FileDownloadResult.handedToBrowser().readablePath, isNull);
      expect(const FileDownloadResult.cancelled().readablePath, isNull);
    });
  });
}
