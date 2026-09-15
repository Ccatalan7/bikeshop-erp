import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String serviceSource;
  late String chatWindowSource;

  setUpAll(() {
    serviceSource = File(
      'lib/modules/messaging/services/messaging_attachment_service.dart',
    ).readAsStringSync();
    chatWindowSource = File(
          'lib/modules/messaging/widgets/chat_window.dart',
        ).readAsStringSync() +
        File('lib/modules/messaging/models/chat_attachment_draft.dart')
            .readAsStringSync();
  });

  test('publish loss is reconciled before one exact attachment-id replay', () {
    expect(serviceSource, contains('MessagingAttachmentPublishCoordinator'));
    expect(
      serviceSource,
      contains(".select('id, status, message_id, failure_code')"),
    );
    expect(serviceSource, contains('final params = request.toRpcParams();'));
    expect(
      RegExp(r'await send\(params\)').allMatches(serviceSource),
      hasLength(2),
    );
    expect(serviceSource, contains('MessagingAttachmentPublishOutcomeUnknown'));
  });

  test('chat keeps reservation identity and never fails from a generic catch',
      () {
    expect(chatWindowSource,
        contains('existingReservation: attachment.reservation'));
    expect(chatWindowSource, contains('attachment.markOutcomeUnknown(result)'));
    expect(chatWindowSource, contains('canRetrySafely: true'));
    expect(chatWindowSource, contains('retryUpload: result.retryUpload'));
    expect(chatWindowSource, contains('replayCaption: result.replayCaption'));
    expect(chatWindowSource, contains('? attachment.replayCaption'));
    expect(
      chatWindowSource,
      isNot(contains("code: 'flutter_upload_or_publish_failed'")),
    );
    expect(
      chatWindowSource,
      contains('on MessagingAttachmentPublishRejected catch (error)'),
    );
  });

  test('storage deletion requires an acknowledged terminal fail state', () {
    expect(serviceSource,
        contains("terminalStatus = result['status']?.toString();"));
    expect(
      serviceSource,
      contains(".select('id, status')"),
    );
    expect(
      serviceSource,
      contains(
        "if (terminalStatus != 'failed' && terminalStatus != 'quarantined')",
      ),
    );
    expect(
      serviceSource.indexOf(
        "if (terminalStatus != 'failed' && terminalStatus != 'quarantined')",
      ),
      lessThan(serviceSource.indexOf('.remove([')),
    );
  });
}
