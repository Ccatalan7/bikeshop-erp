import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/widgets/vb_status_badge.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El panel de información del chat tiene cuatro pestañas con un trabajo cada
/// una: Info dice con quién se habla y sobre qué; Archivos lista fotos y
/// documentos; Gestión reúne las acciones; Respaldo descarga la conversación.
/// Lo que era diagnóstico (contadores de mensajes cargados) o redundante (el
/// nombre que ya está en la cabecera, el «cliente» técnico de un chat de
/// proveedor) no aparece.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  // El chat mantiene un indicador vivo, así que el árbol nunca asienta.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpChat(
    WidgetTester tester, {
    required Conversation conversation,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          ChangeNotifierProvider<PurchaseService>(
            create: (_) => _NoInvoicesPurchaseService(),
          ),
          ChangeNotifierProvider(create: (_) => AppearanceService()),
          ChangeNotifierProvider(create: (_) => InventoryService()),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          home: Scaffold(body: ChatWindow(conversation: conversation)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openInfoPanel(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.info_outline));
    await settle(tester);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await settle(tester);
  }

  testWidgets(
    'Info de un chat de proveedor: número del hilo, canal, estado y el proveedor detrás',
    (tester) async {
      await pumpChat(tester, conversation: _supplierConversation());
      await openInfoPanel(tester);

      expect(find.text('CONVERSACIÓN'), findsOneWidget);
      expect(find.text('Número'), findsOneWidget);
      expect(find.text('Contacto'), findsOneWidget);
      // La persona del hilo, su cargo y que ya no es a quien se le escribe.
      expect(find.text('Fabiola · Ventas · contacto anterior'), findsOneWidget);
      // Un número por pestaña: el segundo número y el aviso se fueron.
      expect(find.text('WhatsApp registrado'), findsNothing);
      expect(find.textContaining('no va al número'), findsNothing);
      expect(find.text('Canal'), findsOneWidget);
      expect(find.text('Proveedor WhatsApp'), findsWidgets);
      expect(find.text('Estado'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VbStatusBadge),
          matching: find.text('Activa'),
        ),
        findsOneWidget,
      );
      expect(find.text('Último mensaje'), findsOneWidget);
      expect(find.text('Sin mensajes'), findsOneWidget);

      expect(find.text('VINCULADO A'), findsOneWidget);
      expect(find.text('Proveedor'), findsOneWidget);
      expect(find.text('Abrir ficha del proveedor'), findsOneWidget);

      // Lo que se sacó.
      expect(find.text('Nombre'), findsNothing);
      expect(find.text('Cliente'), findsNothing);
      expect(find.text('Usuario'), findsNothing);
      expect(find.textContaining('mensajes cargados'), findsNothing);
      expect(find.textContaining('ordenadas en Gestión'), findsNothing);
      expect(find.text('Abrir registro'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Gestión de un chat de proveedor: revisar el proveedor y resolver, sin vincular',
    (tester) async {
      await pumpChat(tester, conversation: _supplierConversation());
      await openInfoPanel(tester);
      await openTab(tester, 'Gestión');

      expect(find.text('Acciones sobre esta conversación'), findsOneWidget);
      expect(find.text('Revisar proveedor Comercial Ciclo'), findsOneWidget);
      expect(
        find.text('Ficha, compras y portal del proveedor'),
        findsOneWidget,
      );
      expect(find.text('Marcar como resuelto'), findsOneWidget);
      expect(
        find.text('Cierra la conversación en la bandeja de proveedores'),
        findsOneWidget,
      );
      expect(find.text('Vincular contexto'), findsNothing);
      expect(find.text('Cambiar contexto'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Archivos y Respaldo dicen qué contienen y qué descargan',
      (tester) async {
    await pumpChat(tester, conversation: _supplierConversation());
    await openInfoPanel(tester);
    await openTab(tester, 'Archivos');

    expect(find.text('0 archivos en esta conversación'), findsOneWidget);
    expect(find.text('Sin archivos todavía'), findsOneWidget);
    expect(find.text('Agregar'), findsOneWidget);

    await openTab(tester, 'Respaldo');

    expect(
        find.text('Descarga esta conversación como archivo'), findsOneWidget);
    expect(find.text('Formato'), findsOneWidget);
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('Contenido'), findsOneWidget);
    expect(find.text('Descargar respaldo del chat'), findsOneWidget);
    expect(find.text('Mensajes cargados'), findsNothing);
    expect(find.text('Respaldo general'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Info de un chat de cliente sin contexto ofrece vincularlo, con el teléfono',
    (tester) async {
      await pumpChat(
        tester,
        conversation: Conversation(
          id: 'conv-2',
          type: 'support',
          channel: 'website_portal',
          counterpartyType: 'customer',
          title: 'Cliente web',
          updatedAt: DateTime.now(),
          participantIds: const [],
        ),
      );
      await openInfoPanel(tester);

      expect(find.text('Teléfono'), findsOneWidget);
      expect(find.text('Número'), findsNothing);
      expect(find.text('VINCULADO A'), findsOneWidget);
      expect(find.text('Vincular contexto'), findsOneWidget);
      expect(find.text('WhatsApp registrado'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Conversation _supplierConversation() => Conversation(
      id: 'conv-1',
      type: 'support',
      channel: 'whatsapp',
      counterpartyType: 'supplier',
      title: 'Comercial Ciclo',
      contextType: 'supplier',
      contextId: 'sup-1',
      updatedAt: DateTime.now(),
      participantIds: const [],
      contextHint: const ConversationContextHint(
        customerId: 'cust-1',
        customerName: 'Usuario',
        supplierId: 'sup-1',
        supplierName: 'Comercial Ciclo',
        supplierPhone: '+56934867574',
        contactPersonName: 'Fabiola',
        contactPersonId: 'contact-fabiola',
        contactPersonRole: 'Ventas',
        contactPersonIsActive: false,
        contactPersonIsPrimary: false,
        supplierPrimaryContactName: 'Victor',
      ),
    );

class _NoInvoicesPurchaseService extends PurchaseService {
  _NoInvoicesPurchaseService() : super(DatabaseService(), TenantService());

  @override
  Future<List<PurchaseInvoice>> getInvoicesBySupplier(
          String supplierId) async =>
      const [];
}
