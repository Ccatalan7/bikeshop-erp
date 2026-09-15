import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_activity.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/widgets/conversation_inbox_host.dart';
import 'package:vinabike_erp/shared/widgets/quick_messages_panel.dart';

/// La bandeja de Clientes **no tenía** retención de estado: el arreglo del
/// arranque en frío se hizo sólo en Proveedores porque las dos bandejas eran
/// dos archivos independientes con el mismo código copiado. Ese es exactamente
/// el defecto que `ConversationInboxHost` elimina, y esta prueba existe para
/// que la deriva no vuelva: lo que se afirma acá se afirma también en el test
/// hermano de Proveedores, sobre el mismo código común.
void main() {
  setUpAll(() async {
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
    required bool panelOpen,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        // La bandeja de clientes ofrece contactos de WhatsApp que aún no tienen
        // conversación; sin este servicio esa carga falla y ensucia la salida.
        ChangeNotifierProvider<CustomerService>(
          create: (_) => CustomerService(DatabaseService(), TenantService()),
        ),
        ChangeNotifierProvider<RightToolbarService>.value(
          value: toolbarService,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // La fuente de los widget tests mide el doble; se usa el ancho
            // compacto para que lo medido sea el estado, no el layout.
            width: 272,
            height: 720,
            child: panelOpen
                ? const QuickMessagesPanel()
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'reabrir Clientes conserva la búsqueda, igual que Proveedores',
    (tester) async {
      final toolbarService = RightToolbarService();
      addTearDown(toolbarService.dispose);

      await tester.pumpWidget(
        host(toolbarService: toolbarService, panelOpen: true),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Fernanda');
      await tester.pump();

      // Cerrar el toolbar desmonta el panel de verdad.
      await tester.pumpWidget(
        host(toolbarService: toolbarService, panelOpen: false),
      );
      await tester.pump();
      expect(find.byType(QuickMessagesPanel), findsNothing);

      await tester.pumpWidget(
        host(toolbarService: toolbarService, panelOpen: true),
      );
      await tester.pump();

      final searchField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(
        searchField.controller?.text,
        'Fernanda',
        reason: 'Antes del común esto se perdía sólo en esta bandeja.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'una sesión de otro usuario o inquilino se descarta también en Clientes',
    (tester) async {
      final toolbarService = RightToolbarService();
      addTearDown(toolbarService.dispose);

      toolbarService.savePanelSession(
        ToolbarTool.messages,
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
        host(toolbarService: toolbarService, panelOpen: true),
      );
      await tester.pump();

      final searchField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(searchField.controller?.text, isEmpty);
      expect(
        toolbarService.panelSession<InboxPanelSession>(ToolbarTool.messages),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'las dos bandejas guardan bajo su propia llave y no se pisan',
    (tester) async {
      final toolbarService = RightToolbarService();
      addTearDown(toolbarService.dispose);

      await tester.pumpWidget(
        host(toolbarService: toolbarService, panelOpen: true),
      );
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Fernanda');
      await tester.pump();
      await tester.pumpWidget(
        host(toolbarService: toolbarService, panelOpen: false),
      );
      await tester.pump();

      expect(
        toolbarService.panelSession<InboxPanelSession>(ToolbarTool.messages),
        isNotNull,
      );
      expect(
        toolbarService.panelSession<InboxPanelSession>(
          ToolbarTool.supplierMessages,
        ),
        isNull,
        reason: 'Compartir el ciclo de vida no es compartir el estado: cada '
            'bandeja recuerda lo suyo.',
      );
    },
  );
}
