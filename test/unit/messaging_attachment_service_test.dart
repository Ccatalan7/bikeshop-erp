import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_attachment_service.dart';

void main() {
  const attachmentId = '33333333-3333-4333-8333-333333333333';
  const messageId = '44444444-4444-4444-8444-444444444444';

  Message message(Map<String, dynamic> metadata) => Message(
        id: 'message-1',
        conversationId: '22222222-2222-4222-8222-222222222222',
        content: 'archivo',
        type: 'file',
        metadata: metadata,
        createdAt: DateTime.utc(2026, 7, 19),
      );

  group('attachment preflight', () {
    test('accepts bounded canonical image and document pairs', () {
      final image = MessagingAttachmentService.validateBeforeRead(
        fileName: 'foto.JPEG',
        sizeBytes: 1024,
      );
      final document = MessagingAttachmentService.validateBeforeRead(
        fileName: 'presupuesto.pdf',
        sizeBytes: 2048,
      );

      expect(image.extension, 'jpeg');
      expect(image.contentType, 'image/jpeg');
      expect(document.contentType, 'application/pdf');
    });

    test('keeps inbound-compatible audio and video bounded', () {
      expect(
        MessagingAttachmentService.validateBeforeRead(
          fileName: 'nota.ogg',
          sizeBytes: 10 * 1024 * 1024,
        ).contentType,
        'audio/ogg',
      );
      expect(
        MessagingAttachmentService.validateBeforeRead(
          fileName: 'avance.mp4',
          sizeBytes: 10 * 1024 * 1024,
        ).maxBytes,
        MessagingAttachmentService.maxAudioVideoBytes,
      );
    });

    test('rejects unknown, empty and oversized files before reading', () {
      expect(
        () => MessagingAttachmentService.validateBeforeRead(
          fileName: 'payload.html',
          sizeBytes: 100,
        ),
        throwsFormatException,
      );
      expect(
        () => MessagingAttachmentService.validateBeforeRead(
          fileName: 'foto.jpg',
          sizeBytes: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => MessagingAttachmentService.validateBeforeRead(
          fileName: 'foto.jpg',
          sizeBytes: MessagingAttachmentService.maxImageBytes + 1,
        ),
        throwsFormatException,
      );
    });
  });

  test('private references require the canonical bucket and object path', () {
    expect(
      MessagingAttachmentService.hasPrivateReference(message({
        'attachment_id': '33333333-3333-4333-8333-333333333333',
        'storage_bucket': MessagingAttachmentService.bucketName,
        'storage_path':
            '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.pdf',
      })),
      isTrue,
    );
    expect(
      MessagingAttachmentService.hasPrivateReference(message({
        'attachment_id': '33333333-3333-4333-8333-333333333333',
        'storage_bucket': 'vinabike-assets',
        'storage_path': 'chat/legacy.pdf',
      })),
      isFalse,
    );
    expect(
      MessagingAttachmentService.hasPrivateReference(message({
        'attachment_id': '33333333-3333-4333-8333-333333333333',
        'storage_bucket': MessagingAttachmentService.bucketName,
        'storage_path':
            '11111111-1111-4111-8111-111111111111/another-conversation/33333333-3333-4333-8333-333333333333.pdf',
      })),
      isFalse,
    );
    expect(
      MessagingAttachmentService.hasPrivateReference(message({
        'attachment_id': '33333333-3333-4333-8333-333333333333',
        'storage_bucket': MessagingAttachmentService.bucketName,
        'storage_path':
            '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/44444444-4444-4444-8444-444444444444.pdf',
      })),
      isFalse,
    );
  });

  test('legacy dual-read rejects third-party and unrelated storage URLs', () {
    const host = 'project.supabase.co';
    expect(
      MessagingAttachmentService.isTrustedLegacyPublicUrl(
        'https://project.supabase.co/storage/v1/object/public/vinabike-assets/chat/old.jpg',
        expectedStorageHost: host,
      ),
      isTrue,
    );
    expect(
      MessagingAttachmentService.isTrustedLegacyPublicUrl(
        'https://tracker.example/pixel.jpg',
        expectedStorageHost: host,
      ),
      isFalse,
    );
    expect(
      MessagingAttachmentService.isTrustedLegacyPublicUrl(
        'https://project.supabase.co/storage/v1/object/public/another-bucket/file.pdf',
        expectedStorageHost: host,
      ),
      isFalse,
    );
  });

  test('new reservation metadata contains references but no URL', () {
    const reservation = ReservedMessagingAttachment(
      id: '33333333-3333-4333-8333-333333333333',
      conversationId: '22222222-2222-4222-8222-222222222222',
      bucket: MessagingAttachmentService.bucketName,
      path:
          '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.pdf',
      originalFilename: 'presupuesto.pdf',
      extension: 'pdf',
      contentType: 'application/pdf',
      sizeBytes: 1024,
    );

    expect(reservation.messageMetadata['attachment_id'], reservation.id);
    expect(
      reservation.messageMetadata.keys.where(
        (key) => key.toLowerCase().contains('url'),
      ),
      isEmpty,
    );
  });

  group('replay-safe attachment publish', () {
    final request = MessagingAttachmentPublishRequest(
      attachmentId: attachmentId,
      caption: '  Diagnóstico listo  ',
    );

    test('accepts an exact durable acknowledgement', () async {
      var reads = 0;
      final coordinator = MessagingAttachmentPublishCoordinator(
        send: (_) async => {
          'attachment_id': attachmentId,
          'message_id': messageId,
          'changed': true,
        },
        readback: (_) async {
          reads++;
          return null;
        },
        isOutcomeAmbiguous: (error) => error is _NetworkError,
      );

      final result = await coordinator.execute(request);

      expect(result.messageId, messageId);
      expect(
        result.confirmation,
        MessagingAttachmentPublishConfirmation.acknowledged,
      );
      expect(result.replayAttempted, isFalse);
      expect(reads, 0);
    });

    test('lost ACK is reconciled from attached row without replay', () async {
      var sends = 0;
      final coordinator = MessagingAttachmentPublishCoordinator(
        send: (_) async {
          sends++;
          throw const _NetworkError('ACK lost after commit');
        },
        readback: (_) async => {
          'id': attachmentId,
          'status': 'attached',
          'message_id': messageId,
          'failure_code': null,
        },
        isOutcomeAmbiguous: (error) => error is _NetworkError,
      );

      final result = await coordinator.execute(request);

      expect(sends, 1);
      expect(result.messageId, messageId);
      expect(result.reconciledFromReadback, isTrue);
      expect(result.replayAttempted, isFalse);
    });

    test('replay uses the exact attachment id and normalized caption',
        () async {
      final sentParams = <Map<String, dynamic>>[];
      var reads = 0;
      final coordinator = MessagingAttachmentPublishCoordinator(
        send: (params) async {
          sentParams.add(Map<String, dynamic>.from(params));
          if (sentParams.length == 1) {
            throw const _NetworkError('request outcome unknown');
          }
          return {
            'attachment_id': attachmentId,
            'message_id': messageId,
            'changed': false,
          };
        },
        readback: (_) async {
          reads++;
          return {
            'id': attachmentId,
            'status': 'reserved',
            'message_id': null,
            'failure_code': null,
          };
        },
        isOutcomeAmbiguous: (error) => error is _NetworkError,
      );

      final result = await coordinator.execute(request);

      expect(sentParams, hasLength(2));
      expect(sentParams[1], sentParams[0]);
      expect(sentParams.first['p_attachment_id'], attachmentId);
      expect(sentParams.first['p_caption'], 'Diagnóstico listo');
      expect(reads, 1);
      expect(result.replayAttempted, isTrue);
    });

    test('double ambiguity exposes outcome unknown with reservation identity',
        () async {
      var sends = 0;
      var reads = 0;
      final coordinator = MessagingAttachmentPublishCoordinator(
        send: (_) async {
          sends++;
          throw const _NetworkError('offline');
        },
        readback: (_) async {
          reads++;
          throw const _NetworkError('readback offline');
        },
        isOutcomeAmbiguous: (error) => error is _NetworkError,
      );

      await expectLater(
        coordinator.execute(request),
        throwsA(
          isA<MessagingAttachmentPublishOutcomeUnknown>().having(
            (error) => error.request.attachmentId,
            'attachment id',
            attachmentId,
          ),
        ),
      );
      expect(sends, 2);
      expect(reads, 2);
    });

    test('definitive rejection is not replayed or read back', () async {
      const rejection = _ServerRejection('conversation closed');
      var sends = 0;
      var reads = 0;
      final coordinator = MessagingAttachmentPublishCoordinator(
        send: (_) async {
          sends++;
          throw rejection;
        },
        readback: (_) async {
          reads++;
          return null;
        },
        isOutcomeAmbiguous: (error) => error is _NetworkError,
      );

      await expectLater(
        coordinator.execute(request),
        throwsA(
          isA<MessagingAttachmentPublishRejected>().having(
            (error) => error.cause,
            'cause',
            same(rejection),
          ),
        ),
      );
      expect(sends, 1);
      expect(reads, 0);
    });

    test('terminal readback is a confirmed rejection', () async {
      final coordinator = MessagingAttachmentPublishCoordinator(
        send: (_) async => throw const _NetworkError('ACK lost'),
        readback: (_) async => {
          'id': attachmentId,
          'status': 'quarantined',
          'message_id': null,
          'failure_code': 'stored_object_contract_mismatch',
        },
        isOutcomeAmbiguous: (error) => error is _NetworkError,
      );

      await expectLater(
        coordinator.execute(request),
        throwsA(
          isA<MessagingAttachmentPublishRejected>().having(
            (error) => error.failureCode,
            'failure code',
            'stored_object_contract_mismatch',
          ),
        ),
      );
    });
  });

  group('replay-safe storage upload', () {
    test('recognizes an existing reserved object as a safe replay conflict',
        () {
      const conflict = StorageException(
        'The resource already exists',
        statusCode: '409',
      );

      expect(
        MessagingAttachmentService.isExistingObjectConflict(conflict),
        isTrue,
      );
      expect(
        MessagingAttachmentService.isUploadOutcomeAmbiguous(conflict),
        isTrue,
      );
    });

    test('separates network/server ambiguity from definitive client rejection',
        () {
      const unavailable = StorageException(
        'upstream unavailable',
        statusCode: '503',
      );
      const tooLarge = StorageException(
        'payload too large',
        statusCode: '413',
      );

      expect(
        MessagingAttachmentService.isUploadOutcomeAmbiguous(unavailable),
        isTrue,
      );
      expect(
        MessagingAttachmentService.isUploadOutcomeAmbiguous(tooLarge),
        isFalse,
      );
    });
  });
}

class _NetworkError implements Exception {
  const _NetworkError(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ServerRejection implements Exception {
  const _ServerRejection(this.message);

  final String message;

  @override
  String toString() => message;
}
