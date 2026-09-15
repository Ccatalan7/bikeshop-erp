import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';

/// Tocar una notificación de mensaje llevaba al módulo `/chat`. Es la bandeja
/// completa y sirve para trabajar, pero para «vengo de una notificación y quiero
/// contestar esto» es un rodeo — y en teléfono además pelea con la barra de
/// estado del sistema. Ahora abre la bandeja del rail derecho, que se monta
/// igual en escritorio y en compacto.
void main() {
  // `RightToolbarService` lee sus preferencias al construirse.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('una petición de conversación se entrega una sola vez', () {
    final service = RightToolbarService();
    addTearDown(service.dispose);

    service.openConversation(
      tool: ToolbarTool.supplierMessages,
      conversationId: 'conv-1',
    );

    expect(
      service.activeTool,
      ToolbarTool.supplierMessages,
      reason: 'la notificación abre la bandeja que le corresponde al hilo',
    );
    expect(
      service.takePendingConversation(ToolbarTool.supplierMessages),
      (conversationId: 'conv-1', threadRootMessageId: null),
    );
    expect(
      service.takePendingConversation(ToolbarTool.supplierMessages),
      isNull,
      reason: 'atendida una vez: reconstruir el panel no reabre el hilo',
    );
  });

  test('la petición no la recoge la bandeja equivocada', () {
    final service = RightToolbarService();
    addTearDown(service.dispose);

    service.openConversation(
      tool: ToolbarTool.supplierMessages,
      conversationId: 'conv-1',
    );

    expect(
      service.takePendingConversation(ToolbarTool.messages),
      isNull,
      reason: 'un hilo de proveedor no puede abrirse en la bandeja de clientes',
    );
    expect(
      service.takePendingConversation(ToolbarTool.supplierMessages),
      (conversationId: 'conv-1', threadRootMessageId: null),
      reason: 'y sigue disponible para la suya',
    );
  });

  test('una tarea entrega también la raíz exacta que debe abrir', () {
    final service = RightToolbarService();
    addTearDown(service.dispose);

    service.openConversation(
      tool: ToolbarTool.messages,
      conversationId: 'tasks-channel',
      threadRootMessageId: 'task-root-527',
    );

    expect(
      service.takePendingConversation(ToolbarTool.messages),
      (
        conversationId: 'tasks-channel',
        threadRootMessageId: 'task-root-527',
      ),
    );
  });

  test('el desvío existe y distingue proveedor de cliente', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(
      mainSource,
      contains('bool _openChatNotificationInToolbar(String route)'),
    );
    expect(
      mainSource,
      contains('if (_openChatNotificationInToolbar(route)) return;'),
      reason: 'el desvío corre ANTES del enrutado al módulo',
    );
    expect(mainSource, contains('isSupplierConversation'));
    expect(
      mainSource,
      contains(
          'isSupplier ? ToolbarTool.supplierMessages : ToolbarTool.messages'),
    );
    // Una notificación sin hilo sólo dice «tienes mensajes».
    expect(mainSource, contains('toolbar.openTool(ToolbarTool.messages)'));

    final hostSource = File(
      'lib/shared/widgets/conversation_inbox_host.dart',
    ).readAsStringSync();
    expect(hostSource, contains('void _consumePendingConversation()'));
    expect(
      hostSource,
      contains('toolbarService?.removeListener(_consumePendingConversation)'),
      reason: 'el panel desmontado no puede seguir escuchando peticiones',
    );
  });
}
