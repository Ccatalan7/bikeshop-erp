import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fast inbox keeps the canonical task context', () {
    final source = File(
      'lib/modules/messaging/services/messaging_service.dart',
    ).readAsStringSync();
    expect('conversation_contexts('.allMatches(source).length,
        greaterThanOrEqualTo(2));
    expect(source, contains('thread_root_message_id'));
  });

  test('task channels keep roots in the feed and replies in a side thread', () {
    final source = File(
      'lib/modules/messaging/widgets/chat_window.dart',
    ).readAsStringSync();

    expect(source, contains('TaskThreadRootCard('));
    expect(source, contains('_buildTaskThreadReply('));
    expect(source, contains('_activeThreadRootMessageId'));
    expect(source, contains('task-thread-replies-header'));
    expect(source, contains('task-thread-close-replies'));
    expect(source, contains('message-thread-pane'));
    expect(source, contains('_channelTimelineMessages'));
    expect(source, contains('also_send_to_channel'));
    expect(source, contains('También mostrar esta respuesta en el canal'));
    expect(source, contains('Agregar una respuesta…'));
    expect(source, contains('Inicio del canal'));
    expect(source, contains('message.threadRootMessageId =='));
    expect(
      source,
      isNot(contains('_didResolveInitialTaskThread')),
      reason:
          'Selecting the conversation must show the root post first; opening '
          'its replies is an explicit user action.',
    );
    expect(
      source,
      contains('message.isTopLevelMessage ||'),
      reason: 'Replies stay out of the channel unless explicitly surfaced.',
    );
  });

  test('conversation preview copies preserve every task root context', () {
    final source = File(
      'lib/modules/messaging/providers/chat_provider.dart',
    ).readAsStringSync();

    expect(
      'taskThreadContexts: old.taskThreadContexts'.allMatches(source).length,
      4,
      reason:
          'Realtime, incoming, outgoing, and unread preview copies must not '
          'turn a task channel back into an ordinary internal chat.',
    );
    expect(
      source,
      contains(
        'taskThreadContexts: conversation.taskThreadContexts',
      ),
      reason: 'Context-hint enrichment must preserve the channel roots too.',
    );
  });

  test('quick inbox opens the exact thread inside the active workspace', () {
    final source = File(
      'lib/shared/widgets/quick_messages_panel.dart',
    ).readAsStringSync();

    expect(source, contains("'thread_root': threadRootMessageId"));
    expect(
      source,
      contains('workspaceManager.pushActiveWorkspace<void>(route)'),
      reason:
          'The global right toolbar is outside the workspace router subtree.',
    );
    expect(source, isNot(contains('context.go(route)')));
  });
}
