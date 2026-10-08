import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/widgets/compact_chat_route.dart';
import '../services/right_toolbar_service.dart';
import '../utils/responsive_viewport.dart';
import 'compact_sheet_parts.dart';
import 'quick_messages_panel.dart';
import 'quick_supplier_messages_panel.dart';

/// La única pantalla de Mensajes del teléfono.
///
/// **Por qué es una sola (2026-10-08).** Había dos: la del botón de mensajes
/// del encabezado (un diálogo a pantalla completa) y la del panel de
/// herramientas (una capa del shell). Una notificación o el menú «Compartir»
/// abrían el chat en la capa, pero si el operador había dejado abierto el
/// diálogo —lo normal, porque estaba conversando— éste quedaba encima
/// mostrando la bandeja: había que apretar «atrás» para ver el mensaje o el
/// archivo por adjuntar. Ahora todo pedido de una bandeja de mensajes en
/// compacto —el botón, una notificación, Compartir, el buscador, la ficha de un
/// proveedor— llega a esta misma ruta, y como es una ruta del navegador raíz
/// queda arriba de cualquier hoja abierta.
///
/// La bandeja que muestra es la herramienta activa de [RightToolbarService]:
/// una sola fuente para la pestaña, para el hilo pedido y para el contador.
class CompactMessagesHost {
  CompactMessagesHost._();

  static const String routeName = 'compact-messages';

  static Route<void>? _route;

  /// Set while the screen closes because the window left the phone layout:
  /// the inbox stays open in the desktop rail instead of closing with it.
  static bool _leavingCompact = false;

  /// La pestaña sobrevive al cierre: quien sigue una conversación con un
  /// proveedor vuelve a ella, no a la bandeja de clientes.
  static ToolbarTool lastTool = ToolbarTool.supplierMessages;

  static bool isMessagingTool(ToolbarTool? tool) =>
      tool == ToolbarTool.messages || tool == ToolbarTool.supplierMessages;

  static bool get isOpen => _route?.isActive ?? false;

  /// Opens the screen on [tool] (or the last inbox used).
  static void open(BuildContext context, {ToolbarTool? tool}) {
    context.read<RightToolbarService>().openTool(tool ?? lastTool);
    ensureOpen(context);
  }

  /// Pushes the screen if a messaging inbox was requested and it is not up.
  ///
  /// Only in the phone layout: on a wider window the same request is served by
  /// the right rail, so callers ask unconditionally and this decides.
  static void ensureOpen(BuildContext context) {
    if (isOpen || !ResponsiveViewport.usesCompactShell(context)) return;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return;
    final toolbar = context.read<RightToolbarService>();
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      settings: const RouteSettings(name: routeName),
      builder: (_) => const CompactMessagingViewport(
        child: CompactMessagesSurface(),
      ),
    );
    _route = route;
    navigator.push(route).whenComplete(() {
      if (identical(_route, route)) _route = null;
      final keepRailOpen = _leavingCompact;
      _leavingCompact = false;
      if (!keepRailOpen && isMessagingTool(toolbar.activeTool)) {
        toolbar.close();
      }
    });
  }

  /// Closes the phone screen when the window grows past the phone layout (a
  /// tablet turned, a desktop window widened): the same inbox and thread
  /// continue in the right rail.
  static void leaveCompact(NavigatorState navigator) {
    final route = _route;
    if (route == null || !route.isActive) return;
    _leavingCompact = true;
    navigator.removeRoute(route);
  }

  @visibleForTesting
  static void resetForTest() {
    _route = null;
    lastTool = ToolbarTool.supplierMessages;
  }
}

/// Proveedores y Clientes con una pestaña cada uno.
///
/// Cada bandeja lleva su propio contador de no leídos: mezclarlas en un solo
/// número escondía cuál de las dos estaba esperando respuesta.
class CompactMessagesSurface extends StatefulWidget {
  const CompactMessagesSurface({super.key});

  @override
  State<CompactMessagesSurface> createState() => _CompactMessagesSurfaceState();
}

class _CompactMessagesSurfaceState extends State<CompactMessagesSurface> {
  /// Con un chat abierto la pantalla cede TODA su cabecera: el título y las
  /// pestañas no aportan ahí y en un teléfono le quitaban al mensaje casi un
  /// tercio de la pantalla.
  ///
  /// Es un `ValueNotifier` y NO un `setState` a propósito: reconstruir la
  /// pantalla entera reconstruye el subárbol del panel, y dos intentos de esta
  /// función murieron por eso — el panel se remontaba y el chat recién abierto
  /// se cerraba solo. Con el notifier sólo la cabecera escucha.
  final ValueNotifier<bool> _conversationOpen = ValueNotifier(false);

  @override
  void dispose() {
    _conversationOpen.dispose();
    super.dispose();
  }

  void _handleConversationVisibility(bool visible) {
    if (!mounted) return;
    _conversationOpen.value = visible;
  }

  static int _countFor(ChatProvider chat, {required bool suppliers}) =>
      chat.conversations.fold(0, (sum, c) {
        if (c.isSupplierConversation != suppliers) return sum;
        if (c.type == 'support' && c.status == 'pending') {
          return sum + (c.unreadCount > 0 ? c.unreadCount : 1);
        }
        return sum + c.unreadCount;
      });

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveViewport.usesCompactShell(context)) {
      final navigator = Navigator.of(context, rootNavigator: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        CompactMessagesHost.leaveCompact(navigator);
      });
    }
    final toolbar = context.watch<RightToolbarService>();
    final chat = context.watch<ChatProvider>();
    final active = toolbar.activeTool;
    final tool = CompactMessagesHost.isMessagingTool(active)
        ? active!
        : CompactMessagesHost.lastTool;
    CompactMessagesHost.lastTool = tool;
    final counts = <ToolbarTool, int>{
      ToolbarTool.supplierMessages: _countFor(chat, suppliers: true),
      ToolbarTool.messages: _countFor(chat, suppliers: false),
    };

    final inbox = Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _conversationOpen,
          builder: (context, open, child) =>
              Visibility(visible: !open, child: child!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CompactTabBar<ToolbarTool>(
              selected: tool,
              values: const [
                ToolbarTool.supplierMessages,
                ToolbarTool.messages
              ],
              counts: counts,
              keyPrefix: 'compact-messages-tab',
              labelOf: (tab) => tab == ToolbarTool.supplierMessages
                  ? 'Proveedores'
                  : 'Clientes',
              iconOf: (tab) => tab == ToolbarTool.supplierMessages
                  ? Icons.local_shipping_outlined
                  : Icons.person_outline_rounded,
              nameOf: (tab) => tab == ToolbarTool.supplierMessages
                  ? 'suppliers'
                  : 'customers',
              onChanged: (tab) =>
                  context.read<RightToolbarService>().openTool(tab),
            ),
          ),
        ),
        Expanded(
          child: tool == ToolbarTool.supplierMessages
              ? QuickSupplierMessagesPanel(
                  key: const ValueKey('compact-messages-suppliers'),
                  showTitle: false,
                  onConversationVisibilityChanged:
                      _handleConversationVisibility,
                )
              : QuickMessagesPanel(
                  key: const ValueKey('compact-messages-customers'),
                  showTitle: false,
                  onConversationVisibilityChanged:
                      _handleConversationVisibility,
                ),
        ),
      ],
    );

    // Mismo árbol siempre; con chat abierto la cabecera sólo se esconde, y el
    // título escucha el notifier sin reconstruir la pantalla.
    return ValueListenableBuilder<bool>(
      valueListenable: _conversationOpen,
      builder: (context, open, child) => CompactSheetFrame(
        title: 'Mensajes',
        showHeader: !open,
        onClose: () => Navigator.of(context).maybePop(),
        child: child!,
      ),
      child: inbox,
    );
  }
}
