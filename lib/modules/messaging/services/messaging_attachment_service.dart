import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message.dart';

class MessagingAttachmentValidation {
  final String extension;
  final String contentType;
  final int maxBytes;

  const MessagingAttachmentValidation({
    required this.extension,
    required this.contentType,
    required this.maxBytes,
  });
}

class ReservedMessagingAttachment {
  final String id;
  final String conversationId;
  final String bucket;
  final String path;
  final String originalFilename;
  final String extension;
  final String contentType;
  final int sizeBytes;

  const ReservedMessagingAttachment({
    required this.id,
    required this.conversationId,
    required this.bucket,
    required this.path,
    required this.originalFilename,
    required this.extension,
    required this.contentType,
    required this.sizeBytes,
  });

  factory ReservedMessagingAttachment.fromJson(Map<String, dynamic> json) {
    return ReservedMessagingAttachment(
      id: json['attachment_id'].toString(),
      conversationId: json['conversation_id'].toString(),
      bucket: json['storage_bucket'].toString(),
      path: json['storage_path'].toString(),
      originalFilename: json['original_filename'].toString(),
      extension: json['extension'].toString(),
      contentType: json['content_type'].toString(),
      sizeBytes: (json['size_bytes'] as num).toInt(),
    );
  }

  Map<String, dynamic> get messageMetadata => {
        'attachment_id': id,
        'storage_bucket': bucket,
        'storage_path': path,
        'filename': originalFilename,
        'extension': extension,
        'content_type': contentType,
        'size_bytes': sizeBytes,
        'attachment_access': 'private_signed_runtime',
      };
}

typedef MessagingAttachmentPublishSender = Future<Object?> Function(
  Map<String, dynamic> params,
);
typedef MessagingAttachmentPublishReadback = Future<Object?> Function(
  String attachmentId,
);
typedef MessagingAttachmentPublishAmbiguityTest = bool Function(Object error);

enum MessagingAttachmentPublishConfirmation {
  acknowledged,
  reconciledFromReadback,
}

class MessagingAttachmentPublishRequest {
  MessagingAttachmentPublishRequest({
    required String attachmentId,
    String? caption,
  })  : attachmentId = _requiredValue(attachmentId, 'attachmentId'),
        caption = _optionalValue(caption);

  final String attachmentId;
  final String? caption;

  Map<String, dynamic> toRpcParams() => {
        'p_attachment_id': attachmentId,
        'p_caption': caption,
      };

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty');
    }
    return normalized;
  }

  static String? _optionalValue(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class MessagingAttachmentPublishSnapshot {
  const MessagingAttachmentPublishSnapshot({
    required this.attachmentId,
    required this.status,
    this.messageId,
    this.failureCode,
  });

  factory MessagingAttachmentPublishSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    return MessagingAttachmentPublishSnapshot(
      attachmentId: json['id']?.toString() ?? '',
      status: json['status']?.toString().trim().toLowerCase() ?? '',
      messageId: _nonEmptyValue(json['message_id']),
      failureCode: _nonEmptyValue(json['failure_code']),
    );
  }

  final String attachmentId;
  final String status;
  final String? messageId;
  final String? failureCode;

  bool matches(String expectedAttachmentId) =>
      attachmentId == expectedAttachmentId;
  bool get isAttached => status == 'attached' && messageId != null;
  bool get isTerminalFailure => status == 'failed' || status == 'quarantined';

  static String? _nonEmptyValue(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class MessagingAttachmentPublishResult {
  const MessagingAttachmentPublishResult({
    required this.request,
    required this.messageId,
    required this.confirmation,
    required this.replayAttempted,
  });

  final MessagingAttachmentPublishRequest request;
  final String messageId;
  final MessagingAttachmentPublishConfirmation confirmation;
  final bool replayAttempted;

  bool get reconciledFromReadback =>
      confirmation ==
      MessagingAttachmentPublishConfirmation.reconciledFromReadback;
}

class MessagingAttachmentPublishRejected implements Exception {
  const MessagingAttachmentPublishRejected({
    required this.request,
    required this.cause,
    this.snapshot,
  });

  final MessagingAttachmentPublishRequest request;
  final Object cause;
  final MessagingAttachmentPublishSnapshot? snapshot;

  String get failureCode =>
      snapshot?.failureCode ?? 'messaging_attachment_publish_rejected';

  @override
  String toString() =>
      'La publicación del adjunto ${request.attachmentId} fue rechazada: '
      '$cause';
}

class MessagingAttachmentPublishOutcomeUnknown implements Exception {
  const MessagingAttachmentPublishOutcomeUnknown({
    required this.request,
    required this.firstCommandError,
    required this.replayError,
    required this.readbackError,
  });

  final MessagingAttachmentPublishRequest request;
  final Object firstCommandError;
  final Object replayError;
  final Object readbackError;

  @override
  String toString() => 'No se pudo confirmar la publicación del adjunto '
      '${request.attachmentId}. El mismo attachment_id debe reutilizarse.';
}

/// Reconciles a replay-safe attachment publish command.
///
/// `publish_messaging_attachment` owns idempotency: replaying the exact same
/// attachment id can only return the already-created message. This coordinator
/// first checks the durable attachment row, then performs one exact replay, and
/// never turns missing evidence into a rejection.
class MessagingAttachmentPublishCoordinator {
  const MessagingAttachmentPublishCoordinator({
    required this.send,
    required this.readback,
    required this.isOutcomeAmbiguous,
  });

  final MessagingAttachmentPublishSender send;
  final MessagingAttachmentPublishReadback readback;
  final MessagingAttachmentPublishAmbiguityTest isOutcomeAmbiguous;

  Future<MessagingAttachmentPublishResult> execute(
    MessagingAttachmentPublishRequest request,
  ) async {
    final params = request.toRpcParams();
    Object? firstError;
    Object? firstResponse;
    try {
      firstResponse = await send(params);
    } catch (error) {
      if (!isOutcomeAmbiguous(error)) {
        throw MessagingAttachmentPublishRejected(
          request: request,
          cause: error,
        );
      }
      firstError = error;
    }

    final firstAcknowledgement = _acknowledgement(request, firstResponse);
    if (firstAcknowledgement != null) {
      return MessagingAttachmentPublishResult(
        request: request,
        messageId: firstAcknowledgement,
        confirmation: MessagingAttachmentPublishConfirmation.acknowledged,
        replayAttempted: false,
      );
    }
    firstError ??= const FormatException(
      'Attachment publish returned an invalid acknowledgement',
    );

    final firstReadback = await _read(request);
    final reconciled = _reconcile(request, firstReadback.snapshot);
    if (reconciled != null) return reconciled;
    if (firstReadback.snapshot?.isTerminalFailure == true) {
      throw MessagingAttachmentPublishRejected(
        request: request,
        cause: StateError('The attachment has a terminal failure status.'),
        snapshot: firstReadback.snapshot,
      );
    }

    // The first response may have been lost before reaching the client. The
    // RPC is idempotent by attachment_id, so only this exact replay is safe.
    Object? replayError;
    Object? replayResponse;
    var replayWasDeterministicRejection = false;
    try {
      replayResponse = await send(params);
    } catch (error) {
      replayError = error;
      replayWasDeterministicRejection = !isOutcomeAmbiguous(error);
    }

    final replayAcknowledgement = _acknowledgement(request, replayResponse);
    if (replayAcknowledgement != null) {
      return MessagingAttachmentPublishResult(
        request: request,
        messageId: replayAcknowledgement,
        confirmation: MessagingAttachmentPublishConfirmation.acknowledged,
        replayAttempted: true,
      );
    }
    replayError ??= const FormatException(
      'Attachment publish replay returned an invalid acknowledgement',
    );

    final finalReadback = await _read(request);
    final finalReconciled = _reconcile(request, finalReadback.snapshot);
    if (finalReconciled != null) {
      return MessagingAttachmentPublishResult(
        request: finalReconciled.request,
        messageId: finalReconciled.messageId,
        confirmation: finalReconciled.confirmation,
        replayAttempted: true,
      );
    }
    if (finalReadback.snapshot?.isTerminalFailure == true) {
      throw MessagingAttachmentPublishRejected(
        request: request,
        cause: StateError('The attachment has a terminal failure status.'),
        snapshot: finalReadback.snapshot,
      );
    }

    final firstSnapshot = firstReadback.snapshot;
    final finalSnapshot = finalReadback.snapshot;
    if (replayWasDeterministicRejection &&
        firstSnapshot?.status == 'reserved' &&
        finalSnapshot?.status == 'reserved') {
      throw MessagingAttachmentPublishRejected(
        request: request,
        cause: replayError,
        snapshot: finalSnapshot,
      );
    }

    throw MessagingAttachmentPublishOutcomeUnknown(
      request: request,
      firstCommandError: firstError,
      replayError: replayError,
      readbackError: finalReadback.error ??
          firstReadback.error ??
          StateError('No durable attachment publish evidence was readable.'),
    );
  }

  Future<_MessagingAttachmentPublishReadbackResult> _read(
    MessagingAttachmentPublishRequest request,
  ) async {
    try {
      final raw = await readback(request.attachmentId);
      if (raw is! Map) {
        return const _MessagingAttachmentPublishReadbackResult();
      }
      final snapshot = MessagingAttachmentPublishSnapshot.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (!snapshot.matches(request.attachmentId)) {
        return const _MessagingAttachmentPublishReadbackResult();
      }
      return _MessagingAttachmentPublishReadbackResult(snapshot: snapshot);
    } catch (error) {
      return _MessagingAttachmentPublishReadbackResult(error: error);
    }
  }

  MessagingAttachmentPublishResult? _reconcile(
    MessagingAttachmentPublishRequest request,
    MessagingAttachmentPublishSnapshot? snapshot,
  ) {
    if (snapshot == null || !snapshot.isAttached) return null;
    return MessagingAttachmentPublishResult(
      request: request,
      messageId: snapshot.messageId!,
      confirmation:
          MessagingAttachmentPublishConfirmation.reconciledFromReadback,
      replayAttempted: false,
    );
  }

  String? _acknowledgement(
    MessagingAttachmentPublishRequest request,
    Object? response,
  ) {
    if (response is! Map) return null;
    final result = Map<String, dynamic>.from(response);
    if (result['attachment_id']?.toString() != request.attachmentId) {
      return null;
    }
    final messageId = result['message_id']?.toString().trim();
    return messageId == null || messageId.isEmpty ? null : messageId;
  }
}

class _MessagingAttachmentPublishReadbackResult {
  const _MessagingAttachmentPublishReadbackResult({
    this.snapshot,
    this.error,
  });

  final MessagingAttachmentPublishSnapshot? snapshot;
  final Object? error;
}

/// Canonical client boundary for private messaging attachments.
///
/// New attachment messages store only an immutable object reference. Public or
/// signed URLs are never written to message content/metadata; signed URLs live
/// only in widget memory for the short time required to preview/download.
class MessagingAttachmentService {
  MessagingAttachmentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String bucketName = 'chat-attachments';
  static const int maxAttachmentsPerBatch = 8;
  static const int _mib = 1024 * 1024;
  static const int maxImageBytes = 5 * _mib;
  static const int maxDocumentBytes = 20 * _mib;
  static const int maxTextBytes = 2 * _mib;
  static const int maxAudioVideoBytes = 16 * _mib;
  static const int signedUrlLifetimeSeconds = 300;

  static const Map<String, String> _contentTypeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'mp4': 'video/mp4',
    '3gp': 'video/3gpp',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
  };

  final SupabaseClient _client;
  bool _cleanupAttempted = false;

  static String extensionForFileName(String fileName) {
    final basename = fileName.trim().split(RegExp(r'[\\/]')).last;
    final dot = basename.lastIndexOf('.');
    if (dot <= 0 || dot == basename.length - 1) return '';
    return basename.substring(dot + 1).toLowerCase();
  }

  static MessagingAttachmentValidation validateBeforeRead({
    required String fileName,
    required int sizeBytes,
  }) {
    final extension = extensionForFileName(fileName);
    final contentType = _contentTypeByExtension[extension];
    if (contentType == null) {
      throw const FormatException(
        'Formato no permitido. Usa imagen, PDF, Word, Excel o TXT.',
      );
    }
    if (sizeBytes <= 0) {
      throw const FormatException('El archivo está vacío.');
    }

    final maxBytes = contentType.startsWith('image/')
        ? maxImageBytes
        : contentType.startsWith('audio/') || contentType.startsWith('video/')
            ? maxAudioVideoBytes
            : contentType == 'text/plain'
                ? maxTextBytes
                : maxDocumentBytes;
    if (sizeBytes > maxBytes) {
      final maxMb = maxBytes ~/ _mib;
      throw FormatException('El archivo supera el máximo de $maxMb MB.');
    }

    return MessagingAttachmentValidation(
      extension: extension,
      contentType: contentType,
      maxBytes: maxBytes,
    );
  }

  Future<ReservedMessagingAttachment> reserve({
    required String conversationId,
    required String fileName,
    required int sizeBytes,
  }) async {
    if (!_cleanupAttempted) {
      _cleanupAttempted = true;
      await cleanupOwnStaleReservations();
    }
    final validation = validateBeforeRead(
      fileName: fileName,
      sizeBytes: sizeBytes,
    );
    final response = await _client.rpc(
      'reserve_messaging_attachment',
      params: {
        'p_conversation_id': conversationId,
        'p_original_filename': fileName,
        'p_declared_mime_type': validation.contentType,
        'p_size_bytes': sizeBytes,
      },
    );
    return ReservedMessagingAttachment.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<void> cleanupOwnStaleReservations() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String();
      final rows = await _client
          .from('messaging_attachments')
          .select(
            'id, conversation_id, storage_bucket, storage_path, original_filename, extension, declared_mime_type, size_bytes',
          )
          .eq('created_by', userId)
          .eq('status', 'reserved')
          .lt('created_at', cutoff)
          .limit(20);
      for (final row in rows as List) {
        await fail(
          ReservedMessagingAttachment(
            id: row['id'].toString(),
            conversationId: row['conversation_id'].toString(),
            bucket: row['storage_bucket'].toString(),
            path: row['storage_path'].toString(),
            originalFilename: row['original_filename'].toString(),
            extension: row['extension'].toString(),
            contentType: row['declared_mime_type'].toString(),
            sizeBytes: (row['size_bytes'] as num).toInt(),
          ),
          code: 'stale_client_reservation',
        );
      }
    } catch (_) {
      // Opportunistic cleanup must never block a new user upload. Every new
      // reservation remains bounded and the service-role cleanup can reclaim
      // any rows left by clients that never return.
    }
  }

  Future<void> upload(
    ReservedMessagingAttachment reservation,
    Uint8List bytes, {
    bool acceptExistingObject = false,
  }) async {
    if (bytes.length != reservation.sizeBytes) {
      throw StateError('El archivo cambió después de ser seleccionado.');
    }
    try {
      await _client.storage.from(reservation.bucket).uploadBinary(
            reservation.path,
            bytes,
            fileOptions: FileOptions(
              contentType: reservation.contentType,
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      if (acceptExistingObject && isExistingObjectConflict(error)) return;
      rethrow;
    }
  }

  Future<MessagingAttachmentPublishResult> publish({
    required ReservedMessagingAttachment reservation,
    String? caption,
  }) async {
    final request = MessagingAttachmentPublishRequest(
      attachmentId: reservation.id,
      caption: caption,
    );
    final coordinator = MessagingAttachmentPublishCoordinator(
      send: (params) => _client.rpc(
        'publish_messaging_attachment',
        params: params,
      ),
      readback: (attachmentId) => _client
          .from('messaging_attachments')
          .select('id, status, message_id, failure_code')
          .eq('id', attachmentId)
          .maybeSingle(),
      isOutcomeAmbiguous: isPublishOutcomeAmbiguous,
    );
    return coordinator.execute(request);
  }

  static bool isPublishOutcomeAmbiguous(Object error) {
    return error is! PostgrestException ||
        error.code == null ||
        error.code!.trim().isEmpty;
  }

  static bool isExistingObjectConflict(Object error) {
    if (error is! StorageException) return false;
    if (error.statusCode == '409') return true;
    final normalized = '${error.error ?? ''} ${error.message}'.toLowerCase();
    return normalized.contains('already exists') ||
        normalized.contains('duplicate');
  }

  static bool isUploadOutcomeAmbiguous(Object error) {
    if (error is! StorageException) return true;
    if (isExistingObjectConflict(error)) return true;
    final status = int.tryParse(error.statusCode ?? '');
    if (status == null) return true;
    return status == 408 || status == 425 || status == 429 || status >= 500;
  }

  Future<void> fail(
    ReservedMessagingAttachment reservation, {
    required String code,
  }) async {
    String? terminalStatus;
    try {
      final response = await _client.rpc(
        'fail_messaging_attachment',
        params: {
          'p_attachment_id': reservation.id,
          'p_failure_code': code,
        },
      );
      if (response is! Map) return;
      final result = Map<String, dynamic>.from(response);
      terminalStatus = result['status']?.toString();
    } catch (_) {
      // The fail command may have committed before its acknowledgement was
      // lost. Read the durable row; never infer rollback from a transport
      // exception and never delete while its state remains unknown.
      try {
        final row = await _client
            .from('messaging_attachments')
            .select('id, status')
            .eq('id', reservation.id)
            .maybeSingle();
        if (row != null) {
          terminalStatus = row['status']?.toString();
        }
      } catch (_) {
        return;
      }
    }

    if (terminalStatus != 'failed' && terminalStatus != 'quarantined') return;
    try {
      await _client.storage.from(reservation.bucket).remove([
        reservation.path,
      ]);
    } catch (_) {
      // A terminal registry row remains safe even if physical cleanup needs
      // the bounded server-side reclaim worker later.
    }
  }

  Future<String?> createRuntimeSignedUrl(Message message) async {
    if (!hasPrivateReference(message)) return null;
    final path = storagePath(message)!;

    return _client.storage.from(bucketName).createSignedUrl(
          path,
          signedUrlLifetimeSeconds,
        );
  }

  static String? attachmentId(Message message) =>
      _nonEmpty(message.metadata['attachment_id']);

  static String? storageBucket(Message message) =>
      _nonEmpty(message.metadata['storageBucket']) ??
      _nonEmpty(message.metadata['storage_bucket']);

  static String? storagePath(Message message) =>
      _nonEmpty(message.metadata['storagePath']) ??
      _nonEmpty(message.metadata['storage_path']);

  static bool hasPrivateReference(Message message) {
    final id = attachmentId(message);
    final path = storagePath(message);
    if (id == null || storageBucket(message) != bucketName || path == null) {
      return false;
    }

    final parts = path.split('/');
    if (parts.length != 3 ||
        !_uuidPattern.hasMatch(parts[0]) ||
        parts[1] != message.conversationId ||
        !_uuidPattern.hasMatch(parts[1]) ||
        !_uuidPattern.hasMatch(id)) {
      return false;
    }
    final extension = extensionForFileName(parts[2]);
    return _contentTypeByExtension.containsKey(extension) &&
        parts[2] == '$id.$extension';
  }

  String? trustedLegacyPublicUrl(Message message) {
    for (final candidate in _urlCandidates(message)) {
      if (isTrustedLegacyPublicUrl(
        candidate,
        expectedStorageHost: Uri.tryParse(_client.storage.url)?.host,
      )) {
        return candidate;
      }
    }
    return null;
  }

  String? externalUrlCandidate(Message message) {
    for (final candidate in _urlCandidates(message)) {
      final uri = Uri.tryParse(candidate);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        continue;
      }
      if (!isTrustedLegacyPublicUrl(
        candidate,
        expectedStorageHost: Uri.tryParse(_client.storage.url)?.host,
      )) {
        return candidate;
      }
    }
    return null;
  }

  static bool isTrustedLegacyPublicUrl(
    String? value, {
    String? expectedStorageHost,
  }) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    if (expectedStorageHost != null &&
        expectedStorageHost.isNotEmpty &&
        uri.host != expectedStorageHost) {
      return false;
    }

    final segments = uri.pathSegments;
    if (segments.length < 7 ||
        segments[0] != 'storage' ||
        segments[1] != 'v1' ||
        segments[2] != 'object' ||
        segments[3] != 'public' ||
        segments[4] != 'vinabike-assets') {
      return false;
    }
    return segments[5] == 'chat' || segments[5] == 'whatsapp-media';
  }

  static Iterable<String> _urlCandidates(Message message) sync* {
    const keys = [
      'url',
      'media_url',
      'image_url',
      'file_url',
      'documentUrl',
      'document_url',
      'storage_url',
      'public_url',
      'whatsapp_media_url',
      'download_url',
    ];
    for (final key in keys) {
      final value = _nonEmpty(message.metadata[key]);
      if (value != null) yield value;
    }
    final content = message.content.trim();
    if (content.startsWith('http://') || content.startsWith('https://')) {
      yield content;
    }
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
}
