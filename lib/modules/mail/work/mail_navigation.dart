import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/workspace_manager.dart';

/// Ir a una pantalla desde algo que se abrió encima (un panel, una hoja, el
/// pedido web): navega el espacio de trabajo activo, como la búsqueda global,
/// para que el destino no quede debajo de la ventana desde donde se pidió.
void openMailRoute(BuildContext context, String route) {
  try {
    context.read<WorkspaceManager>().navigateActiveWorkspace(route);
  } catch (_) {
    GoRouter.maybeOf(context)?.go(route);
  }
}

/// Cómo navega un correo según dónde se lee. En la pantalla de Correo, una
/// ruta se empuja en su espacio de trabajo (y al volver se relee el estado).
/// Encima de un registro (`showMailPeek`), el panel se cierra y se navega el
/// espacio de trabajo: empujar desde la ventana del panel usaría el
/// enrutador de la aplicación, no el del espacio.
class MailNavigation extends InheritedWidget {
  const MailNavigation({super.key, required this.go, required super.child});

  final Future<void> Function(String route) go;

  static Future<void> to(BuildContext context, String route) {
    final scope = context.getInheritedWidgetOfExactType<MailNavigation>();
    if (scope != null) return scope.go(route);
    return GoRouter.of(context).push<void>(route);
  }

  /// Ir sin volver (abrir una compra nueva tras pasarle la factura).
  static void replace(BuildContext context, String route) {
    final scope = context.getInheritedWidgetOfExactType<MailNavigation>();
    if (scope != null) {
      scope.go(route);
      return;
    }
    openMailRoute(context, route);
  }

  @override
  bool updateShouldNotify(MailNavigation oldWidget) => false;
}
