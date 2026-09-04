import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('es_CL');
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpSupplierChat(
    WidgetTester tester, {
    required Future<String?> Function(WhatsAppTemplateOption option)
        previewLoader,
    double width = 900,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          ChangeNotifierProvider<PurchaseService>(
            create: (_) => PurchaseService(DatabaseService(), TenantService()),
          ),
          ChangeNotifierProvider(create: (_) => AppearanceService()),
          ChangeNotifierProvider(create: (_) => InventoryService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatWindow(
              conversation: Conversation(
                id: 'supplier-whatsapp-preview',
                type: 'support',
                channel: 'whatsapp',
                counterpartyType: 'supplier',
                title: 'Derman',
                updatedAt: DateTime(2026, 9, 4),
                participantIds: const [],
                contextHint: const ConversationContextHint(
                  supplierId: 'supplier-derman',
                  supplierName: 'Derman',
                ),
              ),
              whatsAppTemplatePreviewLoader: previewLoader,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Agregar al mensaje'));
    await settle(tester);
    await tester.tap(find.text('Mensaje WhatsApp'));
    await settle(tester);
    await tester.tap(find.text('Hola, buen día'));
    await tester.pump();
  }

  testWidgets(
    'missing supplier contact replaces the spinner and retry can recover',
    (tester) async {
      final firstRead = Completer<String?>();
      var calls = 0;

      await pumpSupplierChat(
        tester,
        width: 430,
        previewLoader: (_) {
          calls += 1;
          return calls == 1
              ? firstRead.future
              : Future<String?>.value('Hola Felipe, buen día.');
        },
      );

      expect(
        find.byKey(const Key('whatsapp-template-preview-loading')),
        findsOneWidget,
      );

      firstRead.complete(null);
      await tester.pump();

      expect(
        find.text(
          'Falta el nombre del contacto o vendedor en el perfil del proveedor.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('whatsapp-template-preview-loading')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('whatsapp-template-preview-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('whatsapp-template-open-supplier')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(const Key('whatsapp-template-preview-retry')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(
        find.byKey(const Key('whatsapp-template-preview-retry')),
      );
      await tester.pump();

      expect(calls, 2);
      expect(
        find.byKey(const Key('whatsapp-template-preview')),
        findsOneWidget,
      );
      expect(find.text('Hola Felipe, buen día.'), findsOneWidget);
      expect(
        find.byKey(const Key('whatsapp-template-preview-error')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a hung preview becomes an explicit bounded failure',
      (tester) async {
    final neverCompletes = Completer<String?>();

    await pumpSupplierChat(
      tester,
      previewLoader: (_) => neverCompletes.future,
    );
    expect(
      find.byKey(const Key('whatsapp-template-preview-loading')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 8));

    expect(
      find.text(
        'La vista previa tardó demasiado en cargar. Vuelve a intentarlo.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('whatsapp-template-preview-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('whatsapp-template-preview-retry')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed lookup is not presented as missing profile data',
      (tester) async {
    await pumpSupplierChat(
      tester,
      previewLoader: (_) => Future<String?>.error(StateError('offline')),
    );

    await tester.pump();

    expect(
      find.text('No se pudo cargar la vista previa. Vuelve a intentarlo.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Falta el nombre del contacto'),
      findsNothing,
    );
    expect(
      find.byKey(const Key('whatsapp-template-preview-loading')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late previous selection cannot replace the current preview',
      (tester) async {
    final greeting = Completer<String?>();

    await pumpSupplierChat(
      tester,
      previewLoader: (option) => option.key == 'supplier_greeting'
          ? greeting.future
          : Future<String?>.value('Vista previa vigente.'),
    );

    await tester.tap(find.text('Retomar contacto'));
    await tester.pump();
    expect(find.text('Vista previa vigente.'), findsOneWidget);

    greeting.complete(null);
    await tester.pump();

    expect(find.text('Vista previa vigente.'), findsOneWidget);
    expect(
      find.byKey(const Key('whatsapp-template-preview-error')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
