import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/utils/incoming_share_intake.dart';
import 'package:vinabike_erp/shared/services/incoming_share_service.dart';
import 'package:vinabike_erp/shared/services/media_compressor.dart';

/// Lo que llega desde el menú «Compartir» del teléfono: el canal con el
/// receptor nativo (`IncomingShareStore.kt`) y las reglas de la pantalla.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> batch(String id, List<Map<String, Object?>> files,
          {List<Map<String, Object?>> skipped = const []}) =>
      {'id': id, 'files': files, 'skipped': skipped};

  Map<String, Object?> file(String name, String mime, int size) => {
        'path': '/data/no_backup/incoming_share/x/0/$name',
        'name': name,
        'mimeType': mime,
        'sizeBytes': size,
      };

  group('IncomingShareBatch.fromChannel', () {
    test('lee archivos y omitidos', () {
      final parsed = IncomingShareBatch.fromChannel(batch(
        'b1',
        [file('foto.jpg', 'image/jpeg', 2000)],
        skipped: [
          {'name': 'video.mp4', 'reason': 'too_large'},
        ],
      ))!;
      expect(parsed.id, 'b1');
      expect(parsed.files.single.isImage, isTrue);
      expect(parsed.skipped.single.explanation,
          'Es demasiado grande para enviarlo.');
    });

    test('un lote vacío o malformado no abre nada', () {
      expect(IncomingShareBatch.fromChannel(null), isNull);
      expect(IncomingShareBatch.fromChannel({'files': []}), isNull);
      expect(IncomingShareBatch.fromChannel(batch('b1', [])), isNull);
      expect(
        IncomingShareBatch.fromChannel(batch('b1', [
          {'path': '', 'name': 'x.jpg'},
        ])),
        isNull,
      );
    });
  });

  group('IncomingShareService', () {
    const channel = MethodChannel('test/incoming_share');
    late List<MethodCall> calls;
    late List<Object?> queue;

    setUp(() {
      calls = [];
      queue = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'takePendingShare') {
          return queue.isEmpty ? null : queue.removeAt(0);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> platformSays(String method) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
    }

    test('toma el envío del arranque y lo entrega una sola vez', () async {
      queue.add(batch('b1', [file('foto.jpg', 'image/jpeg', 10)]));
      final service = IncomingShareService(channel: channel, enabled: true);
      var notified = 0;
      service.addListener(() => notified++);

      await service.initialize();
      await service.initialize(); // idempotente

      expect(notified, 1);
      expect(service.take()?.id, 'b1');
      expect(service.take(), isNull);
      expect(
        calls.where((c) => c.method == 'takePendingShare').length,
        1,
      );
    });

    test('un envío nuevo sin abrir reemplaza al anterior y libera su copia',
        () async {
      final service = IncomingShareService(channel: channel, enabled: true);
      await service.initialize();

      queue.add(batch('b1', [file('a.jpg', 'image/jpeg', 10)]));
      await platformSays('shareReceived');
      queue.add(batch('b2', [file('b.pdf', 'application/pdf', 10)]));
      await platformSays('shareReceived');

      expect(service.pending?.id, 'b2');
      final released = calls.where((c) => c.method == 'releaseShare');
      expect(released.single.arguments, {'id': 'b1'});
    });

    test('fuera de Android no toca el canal', () async {
      final service = IncomingShareService(channel: channel, enabled: false);
      await service.initialize();
      await service.release(
        const IncomingShareBatch(id: 'b1', files: [], skipped: []),
      );
      expect(calls, isEmpty);
    });
  });

  group('IncomingShareIntake.classify', () {
    IncomingSharedFile shared(String name, String mime, int size) =>
        IncomingSharedFile(
          path: '/tmp/$name',
          name: name,
          mimeType: mime,
          sizeBytes: size,
        );

    test('usa la misma validación que un adjunto del chat', () {
      final items = IncomingShareIntake.classify([
        shared('foto.jpg', 'image/jpeg', 2 * 1024 * 1024),
        shared('camara.heic', 'image/heic', 1024),
        shared('enorme.jpg', 'image/jpeg', 6 * 1024 * 1024),
        shared('presupuesto.pdf', 'application/pdf', 4000),
      ]);
      expect(items.map((i) => i.canSendByWhatsApp), [true, false, false, true]);
      expect(items[1].whatsAppProblem, contains('Formato no permitido'));
      expect(items[2].whatsAppProblem, contains('5 MB'));
      expect(items[3].validation?.contentType, 'application/pdf');
    });
  });

  group('IncomingShareIntake.destinations', () {
    Conversation chat(
      String id, {
      String channel = 'whatsapp',
      String status = 'active',
      String? title,
      String? phone,
      DateTime? last,
    }) =>
        Conversation(
          id: id,
          type: 'support',
          channel: channel,
          status: status,
          title: title ?? id,
          updatedAt: DateTime(2026, 9, 1),
          lastMessageAt: last,
          participantIds: const [],
          contextHint:
              phone == null ? null : ConversationContextHint(phone: phone),
        );

    final all = [
      chat('antiguo', title: 'Ana Muñoz', last: DateTime(2026, 9, 20)),
      chat('reciente',
          title: 'José Pérez',
          phone: '+56 9 4188 4520',
          last: DateTime(2026, 9, 29)),
      chat('instagram', channel: 'instagram', last: DateTime(2026, 9, 29)),
      chat('interno', channel: 'internal', last: DateTime(2026, 9, 29)),
      chat('rechazado', status: 'rejected', last: DateTime(2026, 9, 29)),
      chat('pendiente', status: 'pending', last: DateTime(2026, 9, 25)),
    ];

    List<String> ids(String query) => IncomingShareIntake.destinations(
          all,
          query: query,
          titleFor: (c) => c.title ?? '',
        ).map((c) => c.id).toList();

    test('sólo WhatsApp con compositor, el más reciente primero', () {
      expect(ids(''), ['reciente', 'pendiente', 'antiguo']);
    });

    test('busca sin tildes y por dígitos del teléfono', () {
      expect(ids('munoz'), ['antiguo']);
      expect(ids('jose'), ['reciente']);
      expect(ids('41884520'), ['reciente']);
      expect(ids('nadie'), isEmpty);
    });
  });

  group('MediaCompressor', () {
    const channel = MethodChannel('test/media_compressor_unit');
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('un video demasiado largo llega con el mensaje nativo', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'too_long',
          message: 'El video dura demasiado para WhatsApp.',
        );
      });
      final compressor =
          MediaCompressor(channel: channel, videoSupported: true);
      await expectLater(
        compressor.compressVideo(path: '/x.mp4', maxBytes: 16),
        throwsA(isA<MediaCompressionException>()
            .having((e) => e.code, 'code', 'too_long')
            .having((e) => e.message, 'message', contains('demasiado'))),
      );
    });

    test('sin soporte de video no llama al canal', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return null;
      });
      final compressor =
          MediaCompressor(channel: channel, videoSupported: false);
      expect(compressor.canCompressVideo, isFalse);
      await expectLater(
        compressor.compressVideo(path: '/x.mp4', maxBytes: 16),
        throwsA(isA<MediaCompressionException>()),
      );
      await compressor.cancel('x');
      expect(called, isFalse);
    });

    test('nombre comprimido conserva la base', () {
      expect(compressedFileName('IMG_2041.HEIC', 'jpg'), 'IMG_2041.jpg');
      expect(compressedFileName('revision final.mov', 'mp4'),
          'revision final.mp4');
      expect(compressedFileName('.mov', 'mp4'), 'archivo.mp4');
    });
  });
}
