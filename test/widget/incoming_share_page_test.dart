import 'dart:io';

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
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/messaging/widgets/incoming_share_page.dart';
import 'package:vinabike_erp/shared/services/incoming_share_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

Conversation _chat(
  String id, {
  String channel = 'whatsapp',
  String counterparty = 'customer',
  String status = 'active',
  required String title,
  required DateTime last,
}) =>
    Conversation(
      id: id,
      type: 'support',
      channel: channel,
      counterpartyType: counterparty,
      status: status,
      title: title,
      updatedAt: last,
      lastMessageAt: last,
      participantIds: const [],
    );

class _Chats extends ChatProvider {
  final List<Conversation> chats = [
    _chat('cliente', title: 'José Pérez', last: DateTime(2026, 9, 29, 10)),
    _chat('proveedor',
        counterparty: 'supplier',
        title: 'Derman',
        last: DateTime(2026, 9, 28, 9)),
    _chat('instagram',
        channel: 'instagram', title: 'Instagram', last: DateTime(2026, 9, 29)),
  ];

  @override
  List<Conversation> get conversations => chats;

  @override
  Future<void> loadConversations({
    String? type,
    bool refreshContextHints = true,
  }) async {}

  @override
  List<Message> messagesForConversation(String id) => const [];

  @override
  void updateConversationView({
    required Object owner,
    required String conversationId,
    required bool visible,
  }) {}
}

void main() {
  const channel = MethodChannel('test/incoming_share_page');
  late Directory temp;
  late List<MethodCall> calls;

  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      // Sin esto, el listener de enlaces de Supabase (app_links) no tiene
      // plugin en `flutter test` y su error asíncrono cae en el test que esté
      // corriendo: pasaba solo y fallaba en la corrida conjunta.
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<IncomingShareBatch> writeBatch(WidgetTester tester) async {
    final files = <IncomingSharedFile>[];
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('incoming_share_test');
      Future<void> add(String name, String mime, List<int> bytes) async {
        final file = File('${temp.path}/$name');
        await file.writeAsBytes(bytes);
        files.add(IncomingSharedFile(
          path: file.path,
          name: name,
          mimeType: mime,
          sizeBytes: bytes.length,
        ));
      }

      // Un PNG de 1×1 real, para que la miniatura decodifique.
      await add('foto.png', 'image/png', base64Png);
      await add('presupuesto.pdf', 'application/pdf', '%PDF-1.4'.codeUnits);
      await add('camara.heic', 'image/heic', [0, 1, 2, 3]);
    });
    addTearDown(() => temp.deleteSync(recursive: true));
    return IncomingShareBatch(
      id: 'batch-1',
      files: files,
      skipped: const [
        IncomingShareSkip(name: 'video.mp4', reason: 'too_large'),
      ],
    );
  }

  Future<({_Chats chats, RightToolbarService toolbar})> open(
    WidgetTester tester,
    IncomingShareBatch batch, {
    double width = 390,
    Brightness brightness = Brightness.light,
    bool empty = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chats = _Chats();
    if (empty) chats.chats.clear();
    final toolbar = RightToolbarService();
    final service = IncomingShareService(channel: channel, enabled: true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: chats),
          ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: brightness,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          IncomingSharePage(batch: batch, service: service),
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    // Sin chats hay un indicador girando: pumpAndSettle no asentaría.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return (chats: chats, toolbar: toolbar);
  }

  testWidgets(
      'elegir un chat deja los archivos en su compositor y abre el hilo, sin enviar',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(tester, batch);

    expect(find.text('Compartir en el ERP'), findsOneWidget);
    expect(find.text('Algunos archivos no van por WhatsApp'), findsOneWidget);
    // Instagram no acepta adjuntos del ERP: no se ofrece.
    expect(find.text('Instagram'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('José Pérez'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Compartir en el ERP'), findsNothing);
    final offered = chats.takeOfferedComposerAttachments('cliente');
    expect(offered.map((a) => a.fileName), ['foto.png', 'presupuesto.pdf']);
    expect(offered.first.isImage, isTrue);
    expect(offered.first.bytes, Uint8List.fromList(base64Png));
    expect(offered.last.extension, 'pdf');
    expect(toolbar.activeTool, ToolbarTool.messages);
    expect(
      toolbar.takePendingConversation(ToolbarTool.messages)?.conversationId,
      'cliente',
    );
    // Cerrar la pantalla libera la copia del teléfono.
    expect(
      calls.where((c) => c.method == 'releaseShare').single.arguments,
      {'id': 'batch-1'},
    );
    chats.dispose();
  });

  testWidgets('un chat de proveedor se abre en la bandeja de proveedores',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(tester, batch);
    await tester.runAsync(() async {
      await tester.tap(find.text('Derman'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(toolbar.activeTool, ToolbarTool.supplierMessages);
    chats.dispose();
  });

  testWidgets('la búsqueda filtra y cerrar descarta sin tocar ningún chat',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(tester, batch);
    await tester.enterText(
      find.byKey(const ValueKey('incoming-share-search')),
      'derm',
    );
    await tester.pump();
    expect(find.text('José Pérez'), findsNothing);
    expect(find.text('Derman'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('incoming-share-close')));
    await tester.pumpAndSettle();
    expect(chats.hasOfferedComposerAttachments('cliente'), isFalse);
    expect(chats.hasOfferedComposerAttachments('proveedor'), isFalse);
    expect(toolbar.activeTool, isNull);
    expect(calls.where((c) => c.method == 'releaseShare'), hasLength(1));
    chats.dispose();
  });

  testWidgets(
      'con la bandeja aún cargando espera antes de decir que no hay chats',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, toolbar: _) = await open(tester, batch, empty: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No hay chats de WhatsApp abiertos.'), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('No hay chats de WhatsApp abiertos.'), findsOneWidget);
    // Guardar en Archivos sigue disponible sin chats.
    expect(
      find.byKey(const ValueKey('incoming-share-save-files')),
      findsOneWidget,
    );
    chats.dispose();
  });

  for (final brightness in Brightness.values) {
    for (final width in [360.0, 390.0, 1280.0]) {
      testWidgets('cabe a $width px en ${brightness.name}', (tester) async {
        final batch = await writeBatch(tester);
        final (:chats, toolbar: _) =
            await open(tester, batch, width: width, brightness: brightness);
        expect(tester.takeException(), isNull);
        // Toque de 48 como mínimo en cada destino.
        final row = tester.getSize(
          find.byKey(const ValueKey('incoming-share-chat-cliente')),
        );
        expect(row.height, greaterThanOrEqualTo(48));
        chats.dispose();
      });
    }
  }

  testWidgets(
      'el chat que ya estaba abierto suma los archivos ofrecidos a su compositor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chats = _Chats();
    final conversation = chats.chats.first;
    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>.value(
        value: chats,
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.light,
          ),
          home: Scaffold(body: ChatWindow(conversation: conversation)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('foto.png'), findsNothing);

    chats.offerComposerAttachments(conversation.id, [
      PendingChatAttachment(
        id: 'shared-1',
        fileName: 'foto.png',
        bytes: Uint8List.fromList(base64Png),
        extension: 'png',
        isImage: true,
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('foto.png'), findsOneWidget);
    expect(chats.hasOfferedComposerAttachments(conversation.id), isFalse);
    // Nada se envió: el operador todavía tiene que apretar enviar.
    expect(find.byKey(const ValueKey('chat-message-send')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    chats.dispose();
  });
}

/// PNG transparente de 1×1.
const List<int> base64Png = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
