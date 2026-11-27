import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/chat_attachment_draft.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';

import '../support/silent_realtime.dart';

/// An Instagram conversation inside its 24-hour window, without the network:
/// the composer is open exactly as when Meta's transport says it may reply.
class _OpenInstagramWindow extends ChatProvider {
  @override
  bool hasCompleteMetaConversationStateSnapshot(String conversationId) => true;

  @override
  bool canReplyToMetaConversation(String conversationId) => true;

  @override
  DateTime? metaReplyWindowExpiresAt(String conversationId) =>
      DateTime.now().add(const Duration(hours: 20));

  @override
  Future<void> refreshMetaConversationState(String conversationId) async {}
}

/// Photos to Instagram and Messenger (2026-11-26): the composer offers photos
/// only, says the text goes apart, and keeps everything else out.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'test-anon-key',
      realtimeClientOptions: silentRealtimeOptions,
    );
  });

  // The chat keeps a live indicator running, so the tree never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  final instagram = Conversation(
    id: 'conv-instagram-1',
    type: 'support',
    channel: 'instagram',
    counterpartyType: 'customer',
    title: 'Cliente Instagram',
    updatedAt: DateTime.now(),
    participantIds: const [],
  );

  // A real 1×1 PNG: the tray draws the photo it is about to send.
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  PendingChatAttachment file(String name, String extension) =>
      PendingChatAttachment(
        id: 'offered-$name',
        fileName: name,
        bytes: onePixelPng,
        extension: extension,
        isImage: const {'jpg', 'png', 'gif', 'webp'}.contains(extension),
      );

  Future<ChatProvider> pumpInstagramChat(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chat = _OpenInstagramWindow();
    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>.value(
        value: chat,
        child: MaterialApp(
          home: Scaffold(body: ChatWindow(conversation: instagram)),
        ),
      ),
    );
    await tester.pump();
    await settle(tester);
    return chat;
  }

  testWidgets('the + menu offers a photo, never a file or a voice note',
      (tester) async {
    await pumpInstagramChat(tester);

    // Empty composer: on WhatsApp this is where the microphone shows.
    expect(find.byKey(const ValueKey('chat-voice-record')), findsNothing);

    await tester.tap(find.byTooltip('Agregar al mensaje'));
    await settle(tester);
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Instagram recibe fotos, no documentos'), findsOneWidget);
    expect(find.text('Foto o archivo'), findsNothing);
    expect(find.text('Documento de compra'), findsNothing);

    await tester.tap(find.text('Foto'));
    await settle(tester);
    expect(find.text('Galería'), findsOneWidget);
    expect(find.text('Foto desde Archivos'), findsOneWidget);
    expect(find.text('JPG, PNG o GIF guardado en una carpeta'), findsOneWidget);
    expect(find.text('PDF, documento, planilla o imagen'), findsNothing);
  });

  testWidgets(
      'a forwarded PDF stays out; the photo waits with the text-apart note',
      (tester) async {
    final chat = await pumpInstagramChat(tester);

    chat.offerComposerAttachments(instagram.id, [
      file('cassette.png', 'png'),
      file('cotizacion.pdf', 'pdf'),
    ]);
    await settle(tester);

    expect(find.text('Adjunto listo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('meta-photo-text-apart-hint')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Instagram sólo recibe fotos JPG, PNG o GIF. Quedó fuera: '
        'cotizacion.pdf.',
      ),
      findsOneWidget,
    );
  });
}
