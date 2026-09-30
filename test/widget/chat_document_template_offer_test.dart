import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/chat_attachment_draft.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_attachment_service.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

final _cliente = Conversation(
  id: 'cliente',
  type: 'support',
  channel: 'whatsapp',
  counterpartyType: 'customer',
  status: 'active',
  title: 'Marcelo Silva',
  updatedAt: DateTime(2026, 9, 20),
  lastMessageAt: DateTime(2026, 9, 20),
  participantIds: const [],
);

/// Un chat de WhatsApp en que nadie escribió: la ventana de 24 h está cerrada.
class _Chats extends ChatProvider {
  final List<Message> added = [];

  @override
  List<Conversation> get conversations => [_cliente];

  @override
  Future<void> loadConversations({
    String? type,
    bool refreshContextHints = true,
  }) async {}

  @override
  List<Message> messagesForConversation(String id) =>
      added.where((message) => message.conversationId == id).toList();

  @override
  Conversation? addOptimisticMessage(Message message) {
    added.add(message);
    notifyListeners();
    return null;
  }

  @override
  void updateConversationView({
    required Object owner,
    required String conversationId,
    required bool visible,
  }) {}

  @override
  Future<Map<String, ({String? phone, DateTime? lastInboundAt})>>
      whatsAppBindingSummaries(Iterable<String> conversationIds) async =>
          const {};
}

/// La subida queda en espera: basta con ver lo que salió del compositor.
class _Attachments extends MessagingAttachmentService {
  final uploading = Completer<void>();
  final reserved = <String>[];

  @override
  Future<ReservedMessagingAttachment> reserve({
    required String conversationId,
    required String fileName,
    required int sizeBytes,
  }) async {
    reserved.add(fileName);
    return ReservedMessagingAttachment(
      id: fileName,
      conversationId: conversationId,
      bucket: 'chat-attachments',
      path: 'synthetic/$fileName',
      originalFilename: fileName,
      extension: 'pdf',
      contentType: 'application/pdf',
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<void> upload(
    ReservedMessagingAttachment reservation,
    Uint8List bytes, {
    bool acceptExistingObject = false,
  }) =>
      uploading.future;
}

PendingChatAttachment _pdf(String name) => PendingChatAttachment(
      id: name,
      fileName: name,
      bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
      extension: 'pdf',
      isImage: false,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });

  test('la plantilla sigue al PDF en un reintento y no tras un rechazo', () {
    final marked = _pdf('presupuesto.pdf').withDocumentTemplate('Marcelo');
    expect(marked.withCaption('x').documentTemplateGreetingName, 'Marcelo');
    expect(marked.withReply(null).documentTemplateGreetingName, 'Marcelo');
    expect(
      marked
          .markOutcomeUnknown(AttachmentDispatchResult.outcomeUnknown(
            reservation: const ReservedMessagingAttachment(
              id: 'r',
              conversationId: 'cliente',
              bucket: 'chat-attachments',
              path: 'synthetic/r.pdf',
              originalFilename: 'presupuesto.pdf',
              extension: 'pdf',
              contentType: 'application/pdf',
              sizeBytes: 15,
            ),
            retryUpload: false,
            canRetrySafely: false,
          ))
          .documentTemplateGreetingName,
      'Marcelo',
      reason: 'Un reintento tiene que mandar exactamente el mismo pedido.',
    );
    expect(marked.resetForNewAttempt().documentTemplateGreetingName, isNull,
        reason: 'Rechazado, la ventana se vuelve a revisar al enviar.');
  });

  Future<_Chats> pumpChat(
    WidgetTester tester, {
    required WhatsAppDocumentTemplateOffer offer,
    required List<PendingChatAttachment> files,
    MessagingAttachmentService? attachments,
    Future<WhatsAppTemplateReviewStatus> Function()? creator,
    Size size = const Size(420, 900),
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chats = _Chats();
    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>.value(
        value: chats,
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: brightness,
          ),
          home: Scaffold(
            body: ChatWindow(
              conversation: _cliente,
              attachmentService: attachments,
              whatsAppDocumentTemplateLoader: () async => offer,
              whatsAppDocumentTemplateCreator: creator,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    chats.offerComposerAttachments(_cliente.id, files);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    return chats;
  }

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('chat-message-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  ButtonStyleButton sendButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('chat-document-template-send')));

  Future<void> close(WidgetTester tester, _Chats chats) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
    chats.dispose();
  }

  testWidgets(
      'sin respuesta en 24 h, un PDF ofrece la plantilla con el texto exacto',
      (tester) async {
    final chats = await pumpChat(
      tester,
      offer: const WhatsAppDocumentTemplateOffer(
        greetingName: 'Marcelo Silva',
        status: WhatsAppTemplateReviewStatus(status: 'APPROVED'),
      ),
      files: [_pdf('presupuesto.pdf')],
    );
    await tapSend(tester);

    expect(find.byKey(const ValueKey('chat-document-template-offer')),
        findsOneWidget);
    expect(
      find.text(WhatsAppService.documentTemplatePreview('Marcelo Silva')),
      findsOneWidget,
    );
    expect(find.textContaining('Hola Marcelo, te enviamos'), findsOneWidget,
        reason: 'Saluda por el nombre de pila, como lo manda el envío.');
    expect(find.text('Aprobada por Meta.'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-document-template-offer')),
        findsNothing);
    expect(find.text('presupuesto.pdf'), findsOneWidget,
        reason: 'Cancelar deja el PDF en el compositor sin subirlo.');
    await close(tester, chats);
  });

  testWidgets('mientras Meta la revisa, el PDF no se puede enviar',
      (tester) async {
    final chats = await pumpChat(
      tester,
      offer: const WhatsAppDocumentTemplateOffer(
        greetingName: 'Marcelo Silva',
        status: WhatsAppTemplateReviewStatus(status: 'PENDING'),
      ),
      files: [_pdf('presupuesto.pdf')],
    );
    await tapSend(tester);

    expect(find.textContaining('Meta la está revisando'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
    await tester
        .tap(find.byKey(const ValueKey('chat-document-template-greeting')));
    // El panel de saludos queda cargando su estado en Meta: no se asienta.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('chat-document-template-offer')),
        findsNothing);
    expect(find.text('presupuesto.pdf'), findsOneWidget);
    await close(tester, chats);
  });

  testWidgets(
      'si no existe en Meta, se crea desde el aviso y queda en revisión',
      (tester) async {
    var created = 0;
    final chats = await pumpChat(
      tester,
      offer: const WhatsAppDocumentTemplateOffer(greetingName: 'Marcelo Silva'),
      files: [_pdf('presupuesto.pdf')],
      creator: () async {
        created += 1;
        return const WhatsAppTemplateReviewStatus(status: 'PENDING');
      },
    );
    await tapSend(tester);

    expect(find.text('Todavía no está creada en Meta.'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
    await tester
        .tap(find.byKey(const ValueKey('chat-document-template-create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(created, 1);
    expect(find.textContaining('Meta la está revisando'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-document-template-create')),
        findsNothing);
    expect(sendButton(tester).onPressed, isNull,
        reason: 'Recién creada, Meta todavía no la aprueba.');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await close(tester, chats);
  });

  testWidgets('sin nombre del contacto no hay a quién saludar', (tester) async {
    final chats = await pumpChat(
      tester,
      offer: const WhatsAppDocumentTemplateOffer(
        status: WhatsAppTemplateReviewStatus(status: 'APPROVED'),
      ),
      files: [_pdf('presupuesto.pdf')],
    );
    await tapSend(tester);

    expect(
        find.textContaining('no tiene el nombre del cliente'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await close(tester, chats);
  });

  testWidgets(
      'enviar con la plantilla saca los PDF con su texto y deja el del '
      'compositor', (tester) async {
    final attachments = _Attachments();
    final chats = await pumpChat(
      tester,
      offer: const WhatsAppDocumentTemplateOffer(
        greetingName: 'Marcelo Silva',
        status: WhatsAppTemplateReviewStatus(status: 'APPROVED'),
      ),
      files: [_pdf('presupuesto.pdf'), _pdf('boleta.pdf')],
      attachments: attachments,
    );
    await tester.enterText(
        find.byKey(const ValueKey<String>('chat-message-composer')),
        'Te llamo mañana');
    await tapSend(tester);

    expect(find.text('Enviar 2 PDF'), findsOneWidget);
    expect(find.textContaining('Tu texto se queda en el compositor'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-document-template-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final preview = WhatsAppService.documentTemplatePreview('Marcelo Silva');
    expect(
      chats.added.map((message) => message.content),
      [preview, preview],
      reason: 'Cada PDF es su propio mensaje con el texto de la plantilla.',
    );
    expect(attachments.reserved, ['presupuesto.pdf']);
    final input = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('chat-message-composer')));
    expect(input.controller?.text, 'Te llamo mañana',
        reason: 'El texto libre no puede salir fuera de las 24 h.');
    await close(tester, chats);
  });

  testWidgets('otro archivo con el PDF sigue pidiendo el saludo',
      (tester) async {
    final chats = await pumpChat(
      tester,
      offer: const WhatsAppDocumentTemplateOffer(
        greetingName: 'Marcelo Silva',
        status: WhatsAppTemplateReviewStatus(status: 'APPROVED'),
      ),
      files: [
        _pdf('presupuesto.pdf'),
        PendingChatAttachment(
          id: 'nota',
          fileName: 'nota.txt',
          bytes: Uint8List.fromList('Retiro el viernes'.codeUnits),
          extension: 'txt',
          isImage: false,
        ),
      ],
    );
    await tapSend(tester);

    expect(find.byKey(const ValueKey('chat-document-template-offer')),
        findsNothing);
    expect(
        find.textContaining('Un PDF solo sí puede ir ahora'), findsOneWidget);
    await close(tester, chats);
  });

  for (final brightness in Brightness.values) {
    testWidgets('el aviso cabe a 360 px en ${brightness.name}', (tester) async {
      final chats = await pumpChat(
        tester,
        size: const Size(360, 780),
        brightness: brightness,
        offer: const WhatsAppDocumentTemplateOffer(
          greetingName: 'Marcelo Silva',
          status: WhatsAppTemplateReviewStatus(status: 'APPROVED'),
        ),
        files: [_pdf('presupuesto_cambio_de_cassette_y_cadena.pdf')],
      );
      await tapSend(tester);
      expect(tester.takeException(), isNull);
      final button = tester
          .getSize(find.byKey(const ValueKey('chat-document-template-send')));
      expect(button.height, greaterThanOrEqualTo(40));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await close(tester, chats);
    });
  }
}
