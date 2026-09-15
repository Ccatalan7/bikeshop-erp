import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_activity.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/widgets/conversation_inbox_host.dart';
import 'package:vinabike_erp/shared/widgets/quick_supplier_messages_panel.dart';

/// Cerrar el toolbar desmonta el panel a propósito: su `dispose()` cancela la
/// suscripción realtime y suelta el historial, de modo que un panel cerrado no
/// siga marcando como leídos mensajes que nadie vio. Lo que no debe perderse es
/// el estado de vista — antes de este contrato, reabrir el panel se sentía un
/// arranque en frío: buscador vacío, lista en blanco con indicador de carga y
/// el lugar donde ibas, perdido.
void main() {
  setUpAll(() async {
    // «Activos» esconde los proveedores que aún no tienen conversación, y el
    // harness no tiene ninguna. Se parte en Historial para que la fila exista y
    // la prueba mida la retención de estado y no el filtro.
    SharedPreferences.setMockInitialValues({
      ConversationActivity.activeOnlyPreferenceKey: false,
    });
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() => ConversationActivity.showOnlyActiveChats.value = false);

  Widget host({
    required RightToolbarService toolbarService,
    required PurchaseService purchaseService,
    required bool panelOpen,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider<PurchaseService>.value(value: purchaseService),
        ChangeNotifierProvider<RightToolbarService>.value(
          value: toolbarService,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // Mismo ancho que el test responsive. La fuente de los widget tests
            // mide el doble, así que la variante regular desborda; lo que se
            // ejercita aquí es la retención de estado, no el layout.
            width: 272,
            height: 720,
            // Abrir y cerrar el toolbar monta y desmonta el panel; el servicio
            // sobrevive, igual que en la app.
            child: panelOpen
                ? const QuickSupplierMessagesPanel()
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'reabrir el panel conserva la búsqueda en vez de partir de cero',
    (tester) async {
      final toolbarService = RightToolbarService();
      addTearDown(toolbarService.dispose);
      final purchaseService = _WarmPurchaseService();
      addTearDown(purchaseService.dispose);

      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Droppbike');
      await tester.pump();
      expect(find.text('Droppbike'), findsWidgets);

      // Cerrar el toolbar: el panel se desmonta de verdad.
      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: false,
        ),
      );
      await tester.pump();
      expect(find.byType(QuickSupplierMessagesPanel), findsNothing);

      // Volver a abrirlo.
      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: true,
        ),
      );
      await tester.pump();

      final searchField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(
        searchField.controller?.text,
        'Droppbike',
        reason: 'La búsqueda es estado de vista y debe sobrevivir al cierre.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'con la caché tibia, reabrir no muestra indicador de carga',
    (tester) async {
      final toolbarService = RightToolbarService();
      addTearDown(toolbarService.dispose);
      final purchaseService = _WarmPurchaseService();
      addTearDown(purchaseService.dispose);

      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: false,
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: true,
        ),
      );
      // Sin pump() adicional a propósito: `pumpWidget` ya renderizó la primera
      // trama, que es la que el usuario ve al reabrir. Bombear de nuevo dejaría
      // que la recarga asíncrona terminara y la prueba pasaría igual sin el
      // arreglo, midiendo nada.
      expect(
        find.text('Droppbike'),
        findsWidgets,
        reason: 'La caché ya estaba tibia: la lista debe venir pintada.',
      );
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'Releer en silencio es lo que separa actualizar de reiniciar.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'una sesión de otro usuario o inquilino se descarta, no se restaura',
    (tester) async {
      final toolbarService = RightToolbarService();
      addTearDown(toolbarService.dispose);
      final purchaseService = _WarmPurchaseService();
      addTearDown(purchaseService.dispose);

      // `RightToolbarService` vive en la raíz de la app y sobrevive al cierre
      // de sesión, así que puede quedar guardada la sesión de quien usó la app
      // antes. Se siembra una de otro alcance y se exige que el panel la tire:
      // el buscador de otra persona no puede aparecer en esta bandeja.
      toolbarService.savePanelSession(
        ToolbarTool.supplierMessages,
        const InboxPanelSession(
          searchText: 'búsqueda de otro inquilino',
          selectedConversationId: null,
          showOnlyActiveChats: false,
          scope: ErpAuthorityScopeKey(
            userId: 'otro-usuario',
            tenantId: 'otro-inquilino',
          ),
        ),
      );

      await tester.pumpWidget(
        host(
          toolbarService: toolbarService,
          purchaseService: purchaseService,
          panelOpen: true,
        ),
      );
      await tester.pump();

      final searchField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(
        searchField.controller?.text,
        isEmpty,
        reason: 'El estado de vista no puede cruzar el límite de tenant.',
      );
      expect(
        toolbarService.panelSession<InboxPanelSession>(
          ToolbarTool.supplierMessages,
        ),
        isNull,
        reason: 'La sesión ajena se descarta, no se deja para el próximo.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

/// Servicio con caché ya poblada, que es el estado normal cuando el usuario
/// vuelve a abrir el panel dentro de la misma sesión.
class _WarmPurchaseService extends PurchaseService {
  _WarmPurchaseService({this.tenantId = 'tenant-a'})
      : super(DatabaseService(), TenantService());

  final String tenantId;

  late final List<Supplier> _suppliers = [
    Supplier(
      id: 'supplier-droppbike',
      tenantId: tenantId,
      name: 'Droppbike',
      phone: '+56 9 5510 7441',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];

  @override
  ErpAuthorityScopeKey? get supplierAuthorityScope => ErpAuthorityScopeKey(
        userId: 'user-a',
        tenantId: tenantId,
      );

  @override
  bool get hasSuppliersCache => true;

  @override
  List<Supplier> get cachedSuppliers => List.unmodifiable(_suppliers);

  @override
  bool get hasListInvoicesCache => true;

  @override
  List<PurchaseInvoice> get cachedListInvoices => const [];

  @override
  Future<List<Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async {
    return _suppliers;
  }

  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList({
    bool forceRefresh = false,
  }) async {
    return const [];
  }
}
