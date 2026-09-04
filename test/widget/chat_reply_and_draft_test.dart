import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/models/chat_attachment_draft.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_attachment_service.dart';
import 'package:vinabike_erp/modules/messaging/models/message_reply.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

final _original = Message(
    id: 'original',
    conversationId: 'chat-a',
    content: 'Mensaje que vamos a responder',
    type: 'text',
    metadata: const {},
    createdAt: DateTime(2026, 9, 4),
    isMe: false);
Conversation _conversation(String id) => Conversation(
    id: id,
    type: 'internal',
    channel: 'internal',
    title: id,
    status: 'active',
    updatedAt: DateTime(2026, 9, 4),
    participantIds: const []);

class _Chats extends ChatProvider {
  List<Message> history = [_original];
  Completer<void>? sending;
  Map<String, dynamic>? sentMetadata;
  String? sentConversation;
  @override
  List<Message> messagesForConversation(String id) =>
      history.where((m) => m.conversationId == id).toList();
  @override
  void updateConversationView(
      {required Object owner,
      required String conversationId,
      required bool visible}) {}
  @override
  Future<void> sendMessage(String content,
      {String type = 'text',
      Map<String, dynamic>? metadata,
      String? conversationId,
      String? threadRootMessageId}) async {
    sentMetadata = metadata;
    sentConversation = conversationId;
    await sending?.future;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'http://127.0.0.1:54321', anonKey: 'test-anon-key');
  });

  Future<void> pump(
      WidgetTester tester, _Chats chats, ValueNotifier<String> selected,
      {double width = 420,
      Brightness brightness = Brightness.light,
      MessagingAttachmentService? attachments}) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<ChatProvider>.value(
        value: chats,
        child: MaterialApp(
            theme: AppTheme.resolve(
                preset: AppearancePresets.vinabike, brightness: brightness),
            home: Scaffold(
                body: ValueListenableBuilder<String>(
                    valueListenable: selected,
                    builder: (_, id, __) => ChatWindow(
                        conversation: _conversation(id),
                        attachmentService: attachments))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> reply(WidgetTester tester) async {
    await tester.longPress(find.text(_original.content));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Responder'), findsOneWidget);
    expect(find.text('Copiar mensaje'), findsOneWidget);
    await tester.tap(find.text('Responder'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('chat-reply-preview')), findsOneWidget);
  }

  final composer = find.byKey(const ValueKey('chat-message-composer'));

  testWidgets('each quick reaction exposes its own accessible tap action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final chats = _Chats();
    final selected = ValueNotifier('chat-a');
    await pump(tester, chats, selected);
    await tester.longPress(find.text(_original.content));
    await tester.pump(const Duration(milliseconds: 250));
    for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🙏']) {
      final action = find.bySemanticsLabel('Reaccionar con $emoji');
      expect(action, findsOneWidget);
      expect(
          tester.getSemantics(action),
          matchesSemantics(
              label: 'Reaccionar con $emoji',
              isButton: true,
              hasTapAction: true));
    }
    await tester.tap(find.text('Copiar mensaje'));
    await tester.pump(const Duration(milliseconds: 350));
    semantics.dispose();
  });

  testWidgets(
      'text and selected reply are restored only in their originating conversation',
      (tester) async {
    final chats = _Chats();
    final selected = ValueNotifier('chat-a');
    await pump(tester, chats, selected);
    await reply(tester);
    await tester.enterText(composer, 'Borrador A');
    selected.value = 'chat-b';
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller!.text, '');
    expect(find.byKey(const ValueKey('chat-reply-preview')), findsNothing);
    await tester.enterText(composer, 'Borrador B');
    selected.value = 'chat-a';
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller!.text, 'Borrador A');
    expect(find.byKey(const ValueKey('chat-reply-preview')), findsOneWidget);
    expect(chats.getComposerDraft('chat-b')?.text, 'Borrador B');
    await tester.tap(find.byTooltip('Cancelar respuesta'));
    await tester.pump();
    expect(chats.getComposerDraft('chat-a')?.reply, isNull);
    expect(tester.widget<TextField>(composer).controller!.text, 'Borrador A');
    await tester.pumpWidget(const SizedBox());
    chats.dispose();
    selected.dispose();
  });

  testWidgets(
      'late send failure restores original draft without contaminating another editor',
      (tester) async {
    final chats = _Chats()..sending = Completer<void>();
    final selected = ValueNotifier('chat-a');
    await pump(tester, chats, selected);
    await reply(tester);
    await tester.enterText(composer, 'Respuesta fallida');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chats.sentConversation, 'chat-a');
    expect(chats.sentMetadata?['reply_to']['message_id'], 'original');
    selected.value = 'chat-b';
    await tester.pump();
    await tester.enterText(composer, 'Texto nuevo B');
    chats.sending!.completeError(StateError('Synthetic offline'));
    await tester.pump();
    expect(
        tester.widget<TextField>(composer).controller!.text, 'Texto nuevo B');
    expect(chats.getComposerDraft('chat-a')?.text, 'Respuesta fallida');
    expect(chats.getComposerDraft('chat-a')?.reply?.messageId, 'original');
    await tester.pumpWidget(const SizedBox());
    chats.dispose();
    selected.dispose();
  });

  for (final closeWindow in [false, true]) {
    testWidgets(
        'pending file stays in its original chat when ${closeWindow ? 'closed' : 'switched'} during upload',
        (tester) async {
      final chats = _Chats();
      final selected = ValueNotifier('chat-a');
      await pump(tester, chats, selected); // Complete session initialization.
      await tester.pumpWidget(const SizedBox());
      final files = _Attachments();
      chats.saveComposerAttachments(
          'chat-a',
          [
            for (final name in ['first.txt', 'second.txt'])
              PendingChatAttachment(
                  id: name,
                  fileName: name,
                  bytes: Uint8List.fromList([65, 66]),
                  extension: 'txt',
                  isImage: false),
          ],
          session: chats.composerSession);
      await pump(tester, chats, selected, attachments: files);
      expect(find.text('second.txt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-message-send')));
      await tester.pump();
      expect(files.reserved, ['chat-a']);
      if (closeWindow) {
        await tester.pumpWidget(const SizedBox());
      } else {
        selected.value = 'chat-b';
        await tester.pump();
      }
      files.uploading.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(files.published, ['chat-a']);
      expect(files.reserved, ['chat-a']);
      expect(chats.getComposerAttachments('chat-a').map((a) => a.fileName),
          ['second.txt']);
      expect(chats.getComposerAttachments('chat-b'), isEmpty);
      if (!closeWindow) {
        selected.value = 'chat-a';
        await tester.pump();
        expect(find.text('second.txt'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      chats.dispose();
      selected.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [272.0, 420.0]) {
      testWidgets(
          'quote stays bounded at $width in $brightness after source leaves loaded history',
          (tester) async {
        final chats = _Chats();
        final selected = ValueNotifier('chat-a');
        final quoted = MessageReply.fromMessage(_original);
        chats.history = [
          Message(
              id: 'reply',
              conversationId: 'chat-a',
              content: 'Respuesta visible',
              type: 'text',
              metadata: {'reply_to': quoted.toJson()},
              createdAt: DateTime(2026, 9, 4),
              isMe: true)
        ];
        await pump(tester, chats, selected,
            width: width, brightness: brightness);
        expect(find.text(_original.content), findsOneWidget);
        expect(find.text('Respuesta visible'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        chats.dispose();
        selected.dispose();
      });
    }
  }
}

class _Attachments extends MessagingAttachmentService {
  final uploading = Completer<void>();
  final reserved = <String>[];
  final published = <String>[];
  @override
  Future<ReservedMessagingAttachment> reserve(
      {required String conversationId,
      required String fileName,
      required int sizeBytes}) async {
    reserved.add(conversationId);
    return ReservedMessagingAttachment(
        id: fileName,
        conversationId: conversationId,
        bucket: 'chat-attachments',
        path: 'synthetic/$fileName',
        originalFilename: fileName,
        extension: 'txt',
        contentType: 'text/plain',
        sizeBytes: sizeBytes);
  }

  @override
  Future<void> upload(ReservedMessagingAttachment reservation, Uint8List bytes,
          {bool acceptExistingObject = false}) =>
      uploading.future;
  @override
  Future<MessagingAttachmentPublishResult> publish(
      {required ReservedMessagingAttachment reservation,
      String? caption,
      String? threadRootMessageId,
      String? replyToMessageId}) async {
    published.add(reservation.conversationId);
    return MessagingAttachmentPublishResult(
        request: MessagingAttachmentPublishRequest(
            attachmentId: reservation.id, caption: caption),
        messageId: 'published',
        confirmation: MessagingAttachmentPublishConfirmation.acknowledged,
        replayAttempted: false);
  }
}
