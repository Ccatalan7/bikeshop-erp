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
}
