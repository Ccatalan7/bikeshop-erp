import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/chat_attachment_draft.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/share_destinations.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/messaging/widgets/incoming_share_page.dart';
import 'package:vinabike_erp/shared/services/incoming_share_service.dart';
import 'package:vinabike_erp/shared/services/media_compressor.dart';
import 'package:vinabike_erp/shared/services/ocr_file_handoff_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
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

  /// Última vez que escribió cada contacto (la ventana de 24 h).
  final Map<String, DateTime> inbound = {};

  @override
  Future<Map<String, ({String? phone, DateTime? lastInboundAt})>>
      whatsAppBindingSummaries(Iterable<String> conversationIds) async => {
            for (final id in conversationIds)
              if (inbound[id] case final at?)
                id: (phone: null, lastInboundAt: at),
          };

  /// Chats abiertos para un cliente, proveedor o número sin chat.
  final List<Map<String, String?>> opened = [];
  Object? openError;

  @override
  Future<String> openWhatsAppConversationForHandoff({
    required String phoneNumber,
    required String contactName,
    String? customerId,
    String? contextType,
    String? contextId,
  }) async {
    if (openError case final error?) throw error;
    opened.add({
      'phone': phoneNumber,
      'name': contactName,
      'customerId': customerId,
      'contextType': contextType,
      'contextId': contextId,
    });
    return 'nuevo-${opened.length}';
  }
}

const _directory = [
  ShareDirectoryContact(
    isSupplier: false,
    id: 'c-ana',
    name: 'Ana Muñoz',
    phone: '+56 9 1111 2222',
    searchTerms: ['12.345.678-5'],
  ),
  ShareDirectoryContact(
    isSupplier: true,
    id: 's-tekno',
    name: 'TeknoBike',
    phone: '+56 9 3333 4444',
    detail: 'Diego Muñoz',
  ),
];

void main() {
  const channel = MethodChannel('test/incoming_share_page');
  const compressorChannel = MethodChannel('test/media_compressor');
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
      // Ni foto ni video: no tiene compresión posible.
      await add('catalogo.zip', 'application/zip', [0x50, 0x4B, 3, 4]);
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

  late OcrFileHandoffService ocr;

  Future<({_Chats chats, RightToolbarService toolbar})> open(
    WidgetTester tester,
    IncomingShareBatch batch, {
    double width = 390,
    Brightness brightness = Brightness.light,
    bool empty = false,
    MediaCompressor? compressor,
    void Function(_Chats chats)? prepare,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chats = _Chats();
    if (empty) chats.chats.clear();
    prepare?.call(chats);
    final toolbar = RightToolbarService();
    ocr = OcrFileHandoffService();
    final service = IncomingShareService(channel: channel, enabled: true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: chats),
          ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
          ChangeNotifierProvider<OcrFileHandoffService>.value(value: ocr),
          ChangeNotifierProvider<WorkspaceManager>(
            create: (_) => WorkspaceManager(),
          ),
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
                      builder: (_) => IncomingSharePage(
                        batch: batch,
                        service: service,
                        compressor: compressor ??
                            MediaCompressor(
                              channel: compressorChannel,
                              videoSupported: false,
                            ),
                        directoryLoader: (_) async => _directory,
                      ),
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

    expect(find.text('Enviar por WhatsApp'), findsOneWidget);
    expect(find.text('Algunos archivos no van por WhatsApp'), findsOneWidget);
    // Instagram no acepta adjuntos del ERP: no se ofrece.
    expect(find.text('Instagram'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('José Pérez'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Enviar por WhatsApp'), findsNothing);
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
      'cualquier cliente con teléfono aparece al buscar y se le abre un chat '
      'sin escribirle', (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(tester, batch);
    // Sin buscar, los cientos de clientes sin chat no llenan la lista.
    expect(find.text('Ana Muñoz'), findsNothing);
    expect(find.text('Busca a tu cliente'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('incoming-share-search')),
      'munoz',
    );
    await tester.pump();
    expect(find.text('Clientes sin chat'), findsOneWidget);
    await tester.runAsync(() async {
      await tester
          .tap(find.byKey(const ValueKey('incoming-share-customer-c-ana')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(chats.opened.single, {
      'phone': '+56 9 1111 2222',
      'name': 'Ana Muñoz',
      'customerId': 'c-ana',
      'contextType': null,
      'contextId': null,
    });
    expect(
      chats.takeOfferedComposerAttachments('nuevo-1').map((a) => a.fileName),
      ['foto.png', 'presupuesto.pdf'],
    );
    expect(
      toolbar.takePendingConversation(ToolbarTool.messages)?.conversationId,
      'nuevo-1',
    );
    chats.dispose();
  });

  testWidgets('«Proveedores» muestra también los que no tienen chat',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(tester, batch);
    await tester.tap(
      find.byKey(const ValueKey('incoming-share-audience-suppliers')),
    );
    await tester.pump();
    expect(find.text('José Pérez'), findsNothing);
    expect(find.text('Derman'), findsOneWidget);
    expect(find.text('Proveedores sin chat'), findsOneWidget);
    expect(find.text('Diego Muñoz · +56 9 3333 4444'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('TeknoBike'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(chats.opened.single['contextType'], 'supplier');
    expect(chats.opened.single['contextId'], 's-tekno');
    expect(toolbar.activeTool, ToolbarTool.supplierMessages);
    chats.dispose();
  });

  testWidgets('un número que no es de nadie se ofrece como chat nuevo',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(tester, batch);
    await tester.enterText(
      find.byKey(const ValueKey('incoming-share-search')),
      '+56 9 5555 6666',
    );
    await tester.pump();
    expect(find.text('Escribir a +56 9 5555 6666'), findsOneWidget);

    // Un número que ya es de una ficha no se ofrece dos veces.
    await tester.enterText(
      find.byKey(const ValueKey('incoming-share-search')),
      '11112222',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('incoming-share-phone')), findsNothing);
    expect(find.text('Ana Muñoz'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('incoming-share-search')),
      '+56 9 5555 6666',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('incoming-share-phone')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(chats.opened.single['phone'], '+56 9 5555 6666');
    expect(chats.opened.single['customerId'], isNull);
    expect(toolbar.activeTool, ToolbarTool.messages);
    chats.dispose();
  });

  testWidgets('si no se puede abrir el chat nuevo, lo dice y deja elegir otro',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, :toolbar) = await open(
      tester,
      batch,
      prepare: (chats) => chats.openError = Exception('sin red'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('incoming-share-search')),
      'ana',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Ana Muñoz'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudo abrir el chat con Ana Muñoz'),
      findsOneWidget,
    );
    expect(toolbar.activeTool, isNull);
    expect(find.text('Enviar por WhatsApp'), findsOneWidget);
    chats.dispose();
  });

  testWidgets('el chat que escribió en las últimas 24 h lleva el punto',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final batch = await writeBatch(tester);
    final (:chats, toolbar: _) = await open(
      tester,
      batch,
      prepare: (chats) => chats.inbound
        ..['cliente'] = DateTime.now().subtract(const Duration(hours: 2))
        ..['proveedor'] = DateTime.now().subtract(const Duration(days: 3)),
    );
    await tester.pump();
    // ListTile funde el rótulo del punto con el de la fila.
    final dot = find.bySemanticsLabel(RegExp('Recibe archivos ahora'));
    expect(dot, findsOneWidget);
    expect(
      tester.getSemantics(dot).label,
      allOf(contains('José Pérez'), isNot(contains('Derman'))),
    );
    semantics.dispose();
    chats.dispose();
  });

  testWidgets(
      'con la bandeja aún cargando espera antes de decir que no hay chats',
      (tester) async {
    final batch = await writeBatch(tester);
    final (:chats, toolbar: _) = await open(tester, batch, empty: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No hay chats abiertos.'), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    // Sin chats igual se puede buscar a cualquier cliente.
    expect(find.text('Busca a tu cliente'), findsOneWidget);
    // Guardar en Archivos sigue disponible sin chats, en el menú ⋮.
    await tester.tap(find.byKey(const ValueKey('incoming-share-more')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('incoming-share-save-files')),
      findsOneWidget,
    );
    chats.dispose();
  });

  testWidgets(
      'un video que no va tal cual se comprime antes de poder elegir el chat',
      (tester) async {
    late String compressedPath;
    final original = <IncomingSharedFile>[];
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('incoming_share_video');
      final mov = File('${temp.path}/revision.mov')
        ..writeAsBytesSync(List.filled(64, 1));
      compressedPath = '${temp.path}/comprimido/revision.mp4';
      File(compressedPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(32, 7));
      original.add(IncomingSharedFile(
        path: mov.path,
        name: 'revision.mov',
        mimeType: 'video/quicktime',
        sizeBytes: 64,
      ));
    });
    addTearDown(() => temp.deleteSync(recursive: true));

    final finish = Completer<Object?>();
    MethodCall? request;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(compressorChannel, (call) async {
      if (call.method != 'compressVideo') return null;
      request = call;
      return finish.future;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(compressorChannel, null));

    final compressor = MediaCompressor(
      channel: compressorChannel,
      videoSupported: true,
    );
    final (:chats, toolbar: _) = await open(
      tester,
      IncomingShareBatch(id: 'batch-video', files: original, skipped: const []),
      compressor: compressor,
    );

    expect(request?.arguments['maxBytes'], 16 * 1024 * 1024);
    expect(find.text('Comprimiendo para WhatsApp'), findsOneWidget);
    // El avance llega del lado nativo.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      compressorChannel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall(
        'compressProgress',
        {'id': 'share-batch-video-0', 'percent': 42},
      )),
      (_) {},
    );
    await tester.pump();
    expect(find.textContaining('comprimiendo… 42 %'), findsOneWidget);

    // Mientras comprime no se puede elegir: iría el original.
    await tester.tap(find.text('José Pérez'));
    await tester.pump();
    expect(chats.hasOfferedComposerAttachments('cliente'), isFalse);

    finish.complete({'path': compressedPath, 'sizeBytes': 32});
    await tester.pump();
    await tester.pump();
    expect(find.text('Comprimidos para WhatsApp'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('José Pérez'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final offered = chats.takeOfferedComposerAttachments('cliente');
    expect(offered.single.fileName, 'revision.mp4');
    expect(offered.single.extension, 'mp4');
    expect(offered.single.bytes, List.filled(32, 7));
    chats.dispose();
  });

  testWidgets('una foto de más de 5 MB se comprime a JPEG y queda enviable',
      (tester) async {
    late IncomingShareBatch batch;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('incoming_share_photo');
      // Ruido: no comprime, así que 1600×1200 RGBA en PNG pasa los 5 MB.
      final random = Random(7);
      final noise = img.Image(width: 1600, height: 1200, numChannels: 4);
      for (final pixel in noise) {
        pixel
          ..r = random.nextInt(256)
          ..g = random.nextInt(256)
          ..b = random.nextInt(256)
          ..a = 255;
      }
      final png = img.encodePng(noise, level: 0);
      final file = File('${temp.path}/plano.png')..writeAsBytesSync(png);
      batch = IncomingShareBatch(
        id: 'batch-photo',
        files: [
          IncomingSharedFile(
            path: file.path,
            name: 'plano.png',
            mimeType: 'image/png',
            sizeBytes: png.length,
          ),
        ],
        skipped: const [],
      );
    });
    addTearDown(() => temp.deleteSync(recursive: true));
    expect(batch.files.single.sizeBytes, greaterThan(5 * 1024 * 1024));

    final (:chats, toolbar: _) = await open(tester, batch);
    expect(find.text('Comprimiendo para WhatsApp'), findsOneWidget);
    // La compresión corre en un isolate de verdad.
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.text('Comprimidos para WhatsApp').evaluate().isNotEmpty) break;
    }
    expect(find.text('Comprimidos para WhatsApp'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('José Pérez'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final offered = chats.takeOfferedComposerAttachments('cliente').single;
    expect(offered.fileName, 'plano.jpg');
    expect(offered.bytes.length, lessThanOrEqualTo(5 * 1024 * 1024));
    expect(offered.bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    chats.dispose();
  });

  IncomingShareBatch hubBatch(IncomingShareBatch batch,
          {bool single = false}) =>
      IncomingShareBatch(
        id: 'batch-hub',
        files: single ? [batch.files.first] : batch.files,
        skipped: const [],
        target: IncomingShareTarget.hub,
      );

  testWidgets('«Viñabike ERP» abre el menú de destinos y la boleta va al OCR',
      (tester) async {
    final batch = hubBatch(await writeBatch(tester), single: true);
    final (:chats, :toolbar) = await open(tester, batch);

    expect(find.text('Viñabike ERP'), findsOneWidget);
    expect(find.text('¿Qué hacemos con esto?'), findsOneWidget);
    for (final key in [
      'incoming-share-hub-whatsapp',
      'incoming-share-hub-files',
      'incoming-share-hub-expense',
      'incoming-share-hub-purchase',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    // Sin destino elegido no hay chats todavía.
    expect(find.text('José Pérez'), findsNothing);

    await tester.runAsync(() async {
      await tester
          .tap(find.byKey(const ValueKey('incoming-share-hub-expense')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Viñabike ERP'), findsNothing);
    final payload = ocr.take(OcrFileHandoffTarget.quickExpense);
    expect(payload?.fileName, 'foto.png');
    expect(payload?.bytes, base64Png);
    expect(payload?.extension, 'png');
    expect(toolbar.activeTool, ToolbarTool.expenses);
    chats.dispose();
  });

  testWidgets('desde el menú, WhatsApp muestra los chats y se puede volver',
      (tester) async {
    final batch = hubBatch(await writeBatch(tester));
    final (:chats, toolbar: _) = await open(tester, batch);

    // Varios archivos: el OCR lee de a uno.
    final expense = tester.widget<ListTile>(find.descendant(
      of: find.byKey(const ValueKey('incoming-share-hub-expense')),
      matching: find.byType(ListTile),
    ));
    expect(expense.enabled, isFalse);
    expect(find.text('Comparte una sola foto o PDF'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('incoming-share-hub-whatsapp')));
    await tester.pumpAndSettle();
    expect(find.text('Enviar por WhatsApp'), findsOneWidget);
    expect(find.text('José Pérez'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('incoming-share-back')));
    await tester.pumpAndSettle();
    expect(find.text('Viñabike ERP'), findsOneWidget);
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

  testWidgets(
      'lo que no cabe en el compositor espera en la oferta, no se pierde',
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
    PendingChatAttachment file(String name) => PendingChatAttachment(
          id: name,
          fileName: name,
          bytes: Uint8List.fromList(base64Png),
          extension: 'png',
          isImage: true,
        );
    chats.offerComposerAttachments(
        conversation.id, [for (var i = 1; i <= 7; i++) file('foto$i.png')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    chats.offerComposerAttachments(
        conversation.id, [file('ocho.png'), file('nueve.png')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    // Lo que no entró vuelve a la oferta y se revisa en el cuadro siguiente.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // El noveno no se pierde: espera en la oferta y entra al liberarse
    // espacio.
    expect(find.textContaining('Uno espera y entra cuando envíes estos'),
        findsOneWidget);
    expect(chats.offeredComposerAttachmentCount(conversation.id), 1);
    expect(
        chats.takeOfferedComposerAttachments(conversation.id).single.fileName,
        'nueve.png');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    chats.dispose();
  });

  testWidgets(
      'sin respuesta en 24 h, enviar archivos ofrece el saludo y los deja en '
      'el compositor', (tester) async {
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

    // Nadie escribió en este chat: Meta rechazaría el archivo.
    await tester.tap(find.byKey(const ValueKey('chat-message-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.textContaining('WhatsApp no deja mandar archivos'),
      findsOneWidget,
    );
    expect(find.text('foto.png'), findsOneWidget,
        reason: 'El archivo espera en el compositor; no se subió.');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
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
