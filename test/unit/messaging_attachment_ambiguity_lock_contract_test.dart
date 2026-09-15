import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String chatWindowSource;
  late String canonicalRegistry;

  setUpAll(() {
    chatWindowSource = File(
      'lib/modules/messaging/widgets/chat_window.dart',
    ).readAsStringSync();
    canonicalRegistry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
  });

  String methodBody(String start, String end) {
    final startIndex = chatWindowSource.indexOf(start);
    final endIndex = chatWindowSource.indexOf(end, startIndex + start.length);
    expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
    expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
    return chatWindowSource.substring(startIndex, endIndex);
  }

  String withoutWhitespace(String source) =>
      source.replaceAll(RegExp(r'\s+'), '');

  test('unsafe WhatsApp outcome blocks every fresh-attachment path', () {
    expect(
      methodBody(
        'Future<void> _pickAndSendFile(',
        'Future<void> _queueDroppedFiles(',
      ),
      contains('if (_guardPendingAttachmentMutation()) return;'),
    );
    expect(
      methodBody(
        'Future<void> _queueDroppedFiles(',
        'Future<void> _queueXFiles(',
      ),
      contains('if (_guardPendingAttachmentMutation()) return;'),
    );
    expect(
      methodBody(
        'Future<void> _queueXFiles(',
        'void _addPendingAttachments(',
      ),
      contains('if (_guardPendingAttachmentMutation()) return;'),
    );
    expect(
      methodBody(
        'void _addPendingAttachments(',
        'PendingChatAttachment _buildPendingAttachment(',
      ),
      contains('if (_guardPendingAttachmentMutation()) return;'),
    );
  });

  test('unsafe reservation cannot be removed, cleared or blindly sent', () {
    final removeBody = methodBody(
      'void _removePendingAttachment(',
      'void _clearPendingAttachments(',
    );
    expect(removeBody, contains('attachment?.outcomeUnknown == true'));
    expect(removeBody, contains('attachment?.canRetrySafely == false'));
    expect(removeBody, contains('_showPendingAttachmentMutationBlocked();'));

    expect(
      methodBody(
        'void _clearPendingAttachments(',
        'Future<void> _sendComposer(',
      ),
      contains('if (_guardPendingAttachmentMutation()) return;'),
    );
    expect(
      methodBody(
        'Future<void> _sendComposer(',
        'Future<void> _sendPendingAttachments(',
      ),
      contains('if (_hasBlockingOutcomeUnknownAttachment)'),
    );
    expect(
      methodBody(
        'Future<void> _sendPendingAttachments(',
        'String _droppedFileName(',
      ),
      contains('if (_guardPendingAttachmentMutation()) return;'),
    );
  });

  test('composer explains and disables mutation while reservation is locked',
      () {
    expect(
      chatWindowSource,
      contains('WhatsApp aún no confirma este adjunto.'),
    );
    expect(chatWindowSource, contains('Esperando confirmación de WhatsApp'));
    expect(
      chatWindowSource,
      contains('conservada para evitar duplicados.'),
    );
    expect(
      chatWindowSource,
      contains('_isSendingPendingAttachments || hasBlockingOutcome'),
    );
    expect(
      chatWindowSource,
      contains('_isSendingPendingAttachments || removalBlocked'),
    );
    final composerBody = methodBody(
      'Widget _buildComposer(',
      'Widget _buildPendingAttachmentTray(',
    );
    expect(
      withoutWhitespace(composerBody),
      contains(
        'onPressed:hasBlockingOutcomeUnknownAttachment||!composerEnabled?null:',
      ),
      reason:
          'The add-action button must remain disabled while an unsafe attachment reservation is locked.',
    );
  });

  test('only the same attachment id on a durable message releases the lock',
      () {
    expect(chatWindowSource, contains('_durableMessageIdPattern'));
    expect(
      chatWindowSource,
      contains(
        'MessagingAttachmentService.attachmentId(message) == attachmentId',
      ),
    );
    expect(
      chatWindowSource,
      contains('resolvedReservationIds.contains(attachment.reservation!.id)'),
    );
    expect(
      chatWindowSource,
      contains('_schedulePendingAttachmentReconciliation(messages);'),
    );
    expect(
      canonicalRegistry,
      contains(
        'the lock is released only when the timeline receives a durable message carrying that same `attachment_id`',
      ),
    );
  });
}
