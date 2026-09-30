import 'dart:typed_data';
import '../services/messaging_attachment_service.dart';
import 'message_reply.dart';

class PendingChatAttachment {
  final String id;
  final String fileName;
  final Uint8List bytes;
  final String extension;
  final bool isImage;
  final bool outcomeUnknown;
  final ReservedMessagingAttachment? reservation;
  final bool retryUpload;
  final bool canRetrySafely;
  final String? replayCaption;
  final MessageReply? reply;

  /// Purchase document this attachment carries. A confirmed send moves a
  /// draft to «Enviada» and leaves an already-sent document there, so the
  /// identity has to survive every retry the composer allows.
  final String? purchaseInvoiceId;
  final String? purchaseInvoiceNumber;

  /// Length of a voice note, shown on its bubble before the player knows it.
  final int? durationSeconds;

  /// La leyenda propia de este archivo —la de una foto reenviada entre
  /// varias—. Sin ella, el texto del compositor va sólo en el primer archivo.
  final String? caption;

  const PendingChatAttachment({
    required this.id,
    required this.fileName,
    required this.bytes,
    required this.extension,
    required this.isImage,
    this.outcomeUnknown = false,
    this.reservation,
    this.retryUpload = false,
    this.canRetrySafely = false,
    this.replayCaption,
    this.reply,
    this.purchaseInvoiceId,
    this.purchaseInvoiceNumber,
    this.durationSeconds,
    this.caption,
  });

  PendingChatAttachment withReply(MessageReply? value) => PendingChatAttachment(
        id: id,
        fileName: fileName,
        bytes: bytes,
        extension: extension,
        isImage: isImage,
        outcomeUnknown: outcomeUnknown,
        reservation: reservation,
        retryUpload: retryUpload,
        canRetrySafely: canRetrySafely,
        replayCaption: replayCaption,
        reply: value,
        purchaseInvoiceId: purchaseInvoiceId,
        purchaseInvoiceNumber: purchaseInvoiceNumber,
        durationSeconds: durationSeconds,
        caption: caption,
      );

  PendingChatAttachment markOutcomeUnknown(
    AttachmentDispatchResult result,
  ) =>
      PendingChatAttachment(
        id: id,
        reply: reply,
        fileName: fileName,
        bytes: bytes,
        extension: extension,
        isImage: isImage,
        outcomeUnknown: true,
        reservation: result.reservation,
        retryUpload: result.retryUpload,
        canRetrySafely: result.canRetrySafely,
        replayCaption: result.replayCaption,
        purchaseInvoiceId: purchaseInvoiceId,
        purchaseInvoiceNumber: purchaseInvoiceNumber,
        durationSeconds: durationSeconds,
        caption: caption,
      );

  /// Replace the file with the freshly saved document, keeping the row's place
  /// in the composer. Only a row without a reservation can take a revision: a
  /// reserved upload is bound to the exact bytes it announced.
  PendingChatAttachment withRevision({
    required Uint8List bytes,
    required String fileName,
    required String invoiceNumber,
  }) =>
      PendingChatAttachment(
        id: id,
        reply: reply,
        fileName: fileName,
        bytes: bytes,
        extension: extension,
        isImage: isImage,
        purchaseInvoiceId: purchaseInvoiceId,
        purchaseInvoiceNumber: invoiceNumber,
        caption: caption,
      );

  PendingChatAttachment withCaption(String? value) => PendingChatAttachment(
        id: id,
        fileName: fileName,
        bytes: bytes,
        extension: extension,
        isImage: isImage,
        outcomeUnknown: outcomeUnknown,
        reservation: reservation,
        retryUpload: retryUpload,
        canRetrySafely: canRetrySafely,
        replayCaption: replayCaption,
        reply: reply,
        purchaseInvoiceId: purchaseInvoiceId,
        purchaseInvoiceNumber: purchaseInvoiceNumber,
        durationSeconds: durationSeconds,
        caption: value,
      );

  PendingChatAttachment resetForNewAttempt() => PendingChatAttachment(
        id: id,
        reply: reply,
        fileName: fileName,
        bytes: bytes,
        extension: extension,
        isImage: isImage,
        purchaseInvoiceId: purchaseInvoiceId,
        purchaseInvoiceNumber: purchaseInvoiceNumber,
        durationSeconds: durationSeconds,
        caption: caption,
      );
}

enum AttachmentDispatchOutcome { confirmed, rejected, outcomeUnknown }

class AttachmentDispatchResult {
  const AttachmentDispatchResult._({
    required this.outcome,
    this.reservation,
    this.retryUpload = false,
    this.canRetrySafely = false,
    this.replayCaption,
  });

  const AttachmentDispatchResult.confirmed()
      : this._(outcome: AttachmentDispatchOutcome.confirmed);

  const AttachmentDispatchResult.rejected()
      : this._(outcome: AttachmentDispatchOutcome.rejected);

  const AttachmentDispatchResult.outcomeUnknown({
    required ReservedMessagingAttachment reservation,
    required bool retryUpload,
    required bool canRetrySafely,
    String? replayCaption,
  }) : this._(
          outcome: AttachmentDispatchOutcome.outcomeUnknown,
          reservation: reservation,
          retryUpload: retryUpload,
          canRetrySafely: canRetrySafely,
          replayCaption: replayCaption,
        );

  final AttachmentDispatchOutcome outcome;
  final ReservedMessagingAttachment? reservation;
  final bool retryUpload;
  final bool canRetrySafely;
  final String? replayCaption;
}

/// La leyenda con que sale el archivo [index] de un envío: la suya, si la
/// trae (una foto reenviada), y en el primero además el texto del compositor.
String? pendingAttachmentCaption({
  required int index,
  required PendingChatAttachment attachment,
  required String composerText,
}) {
  final own = attachment.caption?.trim() ?? '';
  final composer = index == 0 ? composerText.trim() : '';
  if (own.isEmpty) return composer.isEmpty ? null : composer;
  return composer.isEmpty ? own : '$own\n\n$composer';
}
