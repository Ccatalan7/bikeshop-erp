import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The chat feels like WhatsApp only if three things hold: media the operator
/// has seen stays on the device, a file being sent is a bubble before it is
/// uploaded, and a chat opens on what the device already has. These guard
/// the seams; the widgets themselves are exercised by their own tests.
void main() {
  final window =
      File('lib/modules/messaging/widgets/chat_window.dart').readAsStringSync();
  final provider = File('lib/modules/messaging/providers/chat_provider.dart')
      .readAsStringSync();
  final cache = File('lib/modules/messaging/services/chat_media_cache.dart')
      .readAsStringSync();

  group('media stays on the device', () {
    test('the cache is keyed by attachment identity, never by URL', () {
      final keyFor = cache.substring(
        cache.indexOf('static String? keyFor(Message message)'),
        cache.indexOf('static String? localKeyFor(Message message)'),
      );
      expect(keyFor, contains("'path:\$path'"));
      expect(keyFor, contains("'attachment:\$attachmentId'"));
      expect(keyFor, contains("'wa:\$value'"));
      expect(keyFor, isNot(contains('signedUrl')));
      expect(
        cache,
        contains('getApplicationSupportDirectory()'),
        reason: 'The temp directory is purged; support is not.',
      );
      expect(cache, contains('stalePeriod: _stalePeriod'));
    });

    test('no chat image is drawn straight from a network URL any more', () {
      final rendering = window.substring(
        window.indexOf('Widget _buildMediaTile('),
        window.indexOf('Widget _buildImageLoadingMessage()'),
      );
      expect(rendering, isNot(contains('Image.network(')));
      expect(rendering, contains('ChatMediaThumbnail('));
    });

    test('the viewer takes bytes from the cache before touching the network',
        () {
      final viewer =
          File('lib/modules/messaging/widgets/chat_attachment_viewer.dart')
              .readAsStringSync();
      expect(viewer,
          contains('final cachedBytes = await widget.loadBytes?.call();'));
      expect(window, contains('loadBytes: () async {'));
      expect(
        window,
        contains("'cache://\${Uri.encodeComponent(key!)}'"),
        reason: 'A cached file needs no signed URL to be opened.',
      );
    });
  });

  group('a file is a bubble before it is uploaded', () {
    test('the composer clears at once and each file seeds its bubble', () {
      final send = window.substring(
        window.indexOf('Future<void> _sendPendingAttachments() async {'),
        window.indexOf('String? _seedOptimisticAttachment('),
      );
      final clearIndex = send.indexOf('_pendingAttachments.clear();');
      final seedIndex = send.indexOf('_seedOptimisticAttachment(');
      final uploadIndex = send.indexOf('await _sendAttachmentBytes(');
      expect(clearIndex, greaterThan(-1));
      expect(seedIndex, greaterThan(clearIndex));
      expect(uploadIndex, greaterThan(seedIndex),
          reason: 'Bubble first, upload second.');
      expect(send, isNot(contains("'Subiendo adjunto...'")),
          reason: 'The bubble carries the progress; no 60 s snackbar.');
    });

    test(
        'the just-chosen bytes are cached under the composer key and the '
        'server path', () {
      expect(window, contains("'local:\${attachment.id}'"));
      expect(window, contains("'path:\${reservation.path}'"));
      expect(cache, contains("'local:\$local'"));
    });

    test('a published attachment reconciles by attachment id', () {
      final merge =
          File('lib/modules/messaging/utils/message_timeline_merge.dart')
              .readAsStringSync();
      expect(merge, contains("optimistic.metadata['attachment_id']"));
    });
  });

  group('a chat opens on what the device already has', () {
    test(
        'the provider restores from disk when memory is empty and writes '
        'every timeline change', () {
      expect(
          provider, contains('final ConversationHistoryStore _historyStore'));
      expect(provider,
          contains('unawaited(_restoreConversationHistory(conversationId));'));
      expect(provider,
          contains('_historyStore.scheduleWrite(conversationId, bounded);'));
      expect(
        provider,
        contains(
            'if (mustClearBeforeResolution) unawaited(_historyStore.clear());'),
        reason: 'Another user on the device never sees the previous chats.',
      );
    });
  });

  group('reactions land at once', () {
    test(
        'the provider paints my reaction before the write and reverts on '
        'failure', () {
      final toggle = provider.substring(
        provider.indexOf('Future<void> toggleMyReaction({'),
        provider.indexOf('void _applyMyReactionLocally({'),
      );
      final paint = toggle.indexOf('_applyMyReactionLocally(');
      final write = toggle.indexOf('_service.setMyReaction(');
      expect(paint, greaterThan(-1));
      expect(write, greaterThan(paint),
          reason: 'The chip is on screen before the server is asked.');
      expect(toggle, contains('rethrow;'));
      expect(toggle, contains('_reactionsByMessageId = restored;'));
      expect(
        provider,
        contains('final grouped = _overlayPendingReactions(snapshot);'),
        reason: 'A stale server snapshot must not erase what I just tapped.',
      );
    });
  });

  group('a template message is a bubble before Meta answers', () {
    test('the reviewed text goes up first and the dispatch runs behind it', () {
      final send = window.substring(
        window.indexOf('Future<void> _sendSelectedWhatsAppTemplate('),
        window.indexOf('Future<void> _dispatchWhatsAppTemplate('),
      );
      expect(send, contains('chatProvider.addOptimisticMessage('));
      expect(send, contains("'template_purpose': option.key"));
      expect(send, contains('unawaited(\n      _dispatchWhatsAppTemplate('));
      final dispatch = window.substring(
        window.indexOf('Future<void> _dispatchWhatsAppTemplate('),
        window.indexOf('Widget _buildComposer(BuildContext context) {'),
      );
      expect(dispatch, contains('await Future.wait<Object?>(['),
          reason: 'Contact, agent and review status are fetched together.');
      expect(dispatch, contains('clientMessageId: optimisticMessageId,'));
      expect(dispatch,
          contains('chatProvider.removeMessageById(optimisticMessageId);'));
      final service =
          File('lib/shared/services/whatsapp_service.dart').readAsStringSync();
      expect(service,
          contains('final businessNameFuture = _resolveBusinessName();'));
      expect(
          service, contains('_cachedTemplateSettings[cacheKey] = settings;'));
    });
  });

  group('the first check mark arrives fast', () {
    test('every messaging function call is pinned to the database region', () {
      final region = File('lib/shared/services/supabase_functions_region.dart')
          .readAsStringSync();
      expect(region,
          contains("const String kSupabaseFunctionsRegion = 'sa-east-1';"));
      for (final path in [
        'lib/shared/services/whatsapp_service.dart',
        'lib/modules/messaging/services/whatsapp_cloud_service.dart',
        'lib/modules/messaging/services/meta_messaging_service.dart',
        'lib/modules/messaging/widgets/chat_window.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final invokes = 'functions.invoke('.allMatches(source).length;
        final pinned = 'headers: kSupabaseFunctionsRegionHeaders,'
            .allMatches(source)
            .length;
        expect(pinned, invokes, reason: '$path: every invoke pinned');
      }
    });

    test(
        'the send function overlaps auth with the tenant lookup and defers '
        'the post-insert stamps', () {
      final send =
          File('supabase/functions/whatsapp-send/index.ts').readAsStringSync();
      expect(
          send,
          contains(
              'const claimedUserId = outbox ? null : decodeJwtSubject(authHeader!);'));
      expect(send, contains('claimedUserId === userId'));
      expect(send,
          contains('deferAfterResponse(cleanupStaleMessagingAttachments('));
      expect(send, contains('deferAfterResponse(\n      Promise.all(['));
      expect(send, contains('timings,'));
    });

    test('a receipt the bubble learns locally reaches the inbox tile at once',
        () {
      // The tile is projected from `_outgoingConversationPreviews`; a bubble
      // update that skipped it left the clock in the inbox for 1–2 s until
      // the next server reload (owner report, 2026-09-03).
      for (final method in ['updateMessageMetadataById', 'updateMessageById']) {
        final body = provider.substring(
          provider.indexOf('  void $method('),
          provider.indexOf('  void $method(') + 2200,
        );
        expect(
          '_syncOutgoingPreviewWithMessage('.allMatches(body).length,
          2,
          reason: '$method syncs the tile on both the optimistic and the '
              'cached branch',
        );
      }
      final sync = provider.substring(
        provider.indexOf('bool _syncOutgoingPreviewWithMessage('),
        provider.indexOf('void removeMessageById('),
      );
      expect(sync, contains('_conversationWithOutgoingPreview(current, next)'));
      expect(sync, contains("metadata['external_status']?.toString()"));
      expect(
        sync,
        contains("current.lastMessageMetadata['client_message_id']"),
        reason: 'a newer row that already owns the tile is never overwritten',
      );
    });
  });

  group('the second check mark arrives fast and never goes backwards', () {
    test('a realtime receipt is painted from the row before any re-read', () {
      final service =
          File('lib/modules/messaging/services/messaging_service.dart')
              .readAsStringSync();
      expect(service, contains('record: Map<String, dynamic>.from(record)'));
      final listener = provider.substring(
        provider.indexOf('onMessageReceiptUpdate: (update) {'),
        provider.indexOf('_messageReceiptRefreshCoalescer.schedule('),
      );
      expect(listener, contains('_applyRealtimeReceipt(update);'),
          reason: 'the 1.0–1.25 s coalesced fetch stays authoritative, but '
              'the double check must not wait for it');
      final apply = provider.substring(
        provider.indexOf('void _applyRealtimeReceipt('),
        provider.indexOf('Future<void> _refreshMessageReceipts('),
      );
      expect(apply, contains('projectLatestMessageReceipt(old, message)'));
      expect(apply, contains('_activeMessages = List<Message>.of('));
    });

    test('a conversation reload cannot move a tile backwards', () {
      expect(
        provider,
        contains('_keepFresherLocalLastMessage(newConversations)'),
      );
      final projection =
          File('lib/modules/messaging/utils/message_receipt_projection.dart')
              .readAsStringSync();
      expect(projection,
          contains('receiptRank(conversation.lastMessageExternalStatus) >'));
      expect(projection, contains('nextSequence < currentSequence'));
    });

    test('the webhook works next to the database, not next to Meta', () {
      final webhook = File('supabase/functions/whatsapp-webhook/index.ts')
          .readAsStringSync();
      final verify =
          webhook.indexOf('if (!await verifyMetaSignature(req, rawBody))');
      final forward = webhook.indexOf(
          'const forwarded = await forwardToDatabaseRegion(req, rawBody);');
      expect(verify, greaterThan(-1));
      expect(forward, greaterThan(verify),
          reason:
              'the signature is verified on the raw bytes before forwarding');
      expect(webhook, contains('"x-region": DATABASE_REGION'));
      expect(webhook, contains('req.headers.get(REGION_HOP_HEADER)'),
          reason: 'a forwarded call is never forwarded again');
    });

    test('the worker overlaps the binding upkeep with the Meta call', () {
      final send =
          File('supabase/functions/whatsapp-send/index.ts').readAsStringSync();
      expect(send, contains('if (!outbox || requestedJobTarget) {'));
      expect(send, contains('const binding = await resolveBinding();'));
      expect(send, isNot(contains('bindingResult as JsonRecord')));
    });
  });

  group('the inbox reload decides access once per conversation', () {
    test('previews come from one RPC, never a cross-conversation sort', () {
      final service =
          File('lib/modules/messaging/services/messaging_service.dart')
              .readAsStringSync();
      expect("'inbox_latest_messages_v1'".allMatches(service).length, 2,
          reason: 'the inbox load and the receipt coalescer share the read');
      final previews = service.substring(
        service.indexOf('_fetchLatestMessagesForConversations(\n'),
        service.indexOf('bool _currentUserParticipates('),
      );
      expect(previews, isNot(contains(".from('messages')")));
      final migration = File(
              'supabase/migrations/20260904000500_inbox_reads_check_access_once_per_conversation.sql')
          .readAsStringSync();
      expect(
          migration,
          contains(
              'create or replace view public.conversation_unread_counts as'));
      expect(migration, contains('from public.inbox_unread_counts_v1();'),
          reason: 'installed clients keep the view and still get the speed');
      expect(migration,
          contains('messaging_can_read_conversation_messages(c.id)'));
    });

    test('the list and the context chips are one read each', () {
      final service =
          File('lib/modules/messaging/services/messaging_service.dart')
              .readAsStringSync();
      expect(service, contains("'inbox_conversations_v1'"));
      expect(service, contains("'inbox_context_hint_rows_v1'"));
      final hints = service.substring(
        service.indexOf(
            '_fetchContextHintsForConversations(List<dynamic> rawConversations)'),
        service.indexOf('/// Refreshes only the derived business context'),
      );
      expect(hints, isNot(contains('_client.from(')),
          reason: 'the chip rules select from one bundle, never from '
              'fifteen dependent round trips');
      final list = service.substring(
        service.indexOf('Future<List<Conversation>> getConversations('),
        service.indexOf("'getConversations:baseRows'"),
      );
      expect(list, isNot(contains(".from('conversations')")));
    });
  });

  group('voice notes', () {
    test('the composer records AAC, the pipeline sends type audio', () {
      final recorder =
          File('lib/modules/messaging/widgets/chat_voice_recorder.dart')
              .readAsStringSync();
      expect(recorder, contains('AudioEncoder.aacLc'));
      expect(
          window, contains("key: const ValueKey<String>('chat-voice-record')"));
      expect(window, contains('ChatVoiceRecordingBar('));
      expect(window, contains("? 'audio'"));
      final whatsapp =
          File('lib/shared/services/whatsapp_service.dart').readAsStringSync();
      expect(whatsapp, contains("final isAudio = messageType == 'audio';"));
      final send =
          File('supabase/functions/whatsapp-send/index.ts').readAsStringSync();
      expect(send, contains('payload.audio = { id: mediaId };'));
      expect(
          send,
          contains(
              'requestBody.type === "audio" && !requestBody.attachmentId'));
    });

    test('an inbound voice note gets a WAV twin for Apple players', () {
      final media =
          File('supabase/functions/whatsapp-media/index.ts').readAsStringSync();
      expect(media, contains('transcodeOpusToWav(bytes)'));
      expect(media,
          contains('metadataUpdates.playback_storage_path = playbackPath;'));
      expect(
          media,
          contains(
              'const wantsPlayback = stringValue((body as JsonRecord).variant) === "playback";'));
      expect(window, contains("_resolveWhatsAppMediaUrl(msg, playback: true)"));
      final bubble =
          File('lib/modules/messaging/widgets/chat_audio_message.dart')
              .readAsStringSync();
      expect(
          bubble, contains("widget.message.metadata['playback_storage_path']"));
    });
  });
}
