import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_channel_presentation.dart';

void main() {
  Conversation conversation(String channel) => Conversation(
        id: 'conversation-$channel',
        type: 'support',
        channel: channel,
        updatedAt: DateTime.utc(2026, 7, 21),
        participantIds: const [],
      );

  group('Meta conversation channels', () {
    test('normalizes both supported Meta transports', () {
      expect(
        Conversation.normalizeChannel('instagram', 'support'),
        'instagram',
      );
      expect(
        Conversation.normalizeChannel('facebook_messenger', 'support'),
        'facebook_messenger',
      );
    });

    test('exposes stable provider capabilities and labels', () {
      final instagram = conversation('instagram');
      final messenger = conversation('facebook_messenger');

      expect(instagram.isInstagram, isTrue);
      expect(instagram.isMetaMessaging, isTrue);
      expect(instagram.usesExternalMessagingTransport, isTrue);
      expect(instagram.channelLabel, 'Cliente Instagram');
      expect(instagram.shortChannelLabel, 'Instagram');

      expect(messenger.isFacebookMessenger, isTrue);
      expect(messenger.isMetaMessaging, isTrue);
      expect(messenger.usesExternalMessagingTransport, isTrue);
      expect(messenger.channelLabel, 'Cliente Facebook Messenger');
      expect(messenger.shortChannelLabel, 'Messenger');
    });

    test('shared presentation distinguishes Instagram and Messenger', () {
      expect(
        ConversationChannelPresentation.icon(conversation('instagram')),
        Icons.photo_camera_outlined,
      );
      expect(
        ConversationChannelPresentation.icon(
          conversation('facebook_messenger'),
        ),
        Icons.forum_outlined,
      );
      expect(
        ConversationChannelPresentation.instagramAccent,
        isNot(ConversationChannelPresentation.facebookMessengerAccent),
      );
    });
  });

  group('task thread presentation', () {
    test('recovers a historical single task root from the inbox projection',
        () {
      final taskThread = Conversation.fromJson({
        'id': 'task-conversation',
        'type': 'internal',
        'channel': 'internal',
        'title': 'Prueba de comentarios · PG-00527',
        'updated_at': '2026-08-27T19:13:00.000Z',
        'conversation_participants': const [],
        'conversation_contexts': const [
          {
            'context_type': 'task',
            'context_id': 'task-527',
            'is_primary': true,
            'thread_root_message_id': 'message-root-527',
          },
        ],
      });

      expect(taskThread.effectiveContextType, 'task');
      expect(taskThread.effectiveContextId, 'task-527');
      expect(taskThread.taskThreadRootMessageId, 'message-root-527');
      expect(taskThread.isTaskThread, isTrue);
      expect(taskThread.channelLabel, 'Prueba de comentarios · PG-00527');
      expect(taskThread.shortChannelLabel, 'Tareas');
      expect(
        ConversationChannelPresentation.icon(taskThread),
        Icons.task_alt_outlined,
      );
    });

    test('a shared channel keeps every task root without choosing one task',
        () {
      final channel = Conversation.fromJson({
        'id': 'team-task-channel',
        'type': 'internal',
        'channel': 'internal',
        'title': 'Tareas del equipo',
        'context_type': null,
        'context_id': null,
        'context_hint': const {
          'primary_context_type': 'task',
          'primary_context_id': 'task-b',
        },
        'updated_at': '2026-08-28T00:00:00.000Z',
        'conversation_participants': const [],
        'conversation_contexts': const [
          {
            'context_type': 'task',
            'context_id': 'task-a',
            'is_primary': false,
            'thread_root_message_id': 'root-a',
          },
          {
            'context_type': 'task',
            'context_id': 'task-b',
            'is_primary': false,
            'thread_root_message_id': 'root-b',
          },
        ],
      });

      expect(channel.isTaskChannel, isTrue);
      expect(channel.effectiveContextType, isNull);
      expect(channel.effectiveContextId, isNull);
      expect(channel.taskThreadRootMessageId, isNull);
      expect(channel.taskIdForRoot('root-a'), 'task-a');
      expect(channel.taskIdForRoot('root-b'), 'task-b');
      expect(channel.channelLabel, 'Tareas del equipo');
    });

    test('an ordinary internal conversation remains a team chat', () {
      final internal = Conversation(
        id: 'internal',
        type: 'internal',
        channel: 'internal',
        updatedAt: DateTime.utc(2026, 8, 27),
        participantIds: const [],
      );

      expect(internal.isTaskThread, isFalse);
      expect(internal.channelLabel, 'Chat interno');
      expect(
        ConversationChannelPresentation.icon(internal),
        Icons.groups_outlined,
      );
    });
  });
}
