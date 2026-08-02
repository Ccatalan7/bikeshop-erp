import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/shared/services/window_zoom_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/widgets/vb_anchored_popover.dart';
import 'package:vinabike_erp/shared/widgets/vb_shell_icon_button.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';
import 'package:vinabike_erp/shared/widgets/window_zoom_scope.dart';
import 'package:vinabike_erp/shared/widgets/workspace_tab_bar.dart';

/// Chrome del workspace: el grupo `A-02` y el popover `O-02` del `+`.
///
/// **La causa real del menú roto**, reproducida por Codex y no por mí:
/// `PopupMenuButton.constraints` dimensiona **el menú**, no el botón, y acá
/// venía `tightFor(28, 28)` — cada opción quedaba aplastada a 28 px. El clic y
/// `addWorkspace` sí funcionaban. Por eso lo que se vigila es **ancho útil de
/// la opción**, además de que quepa en pantalla a los dos zooms.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<WorkspaceManager> pumpChrome(
    WidgetTester tester, {
    required Size size,
    required double zoom,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // `WorkspaceManager` ya nace con un espacio; agregar otro acá haría que el
    // contador arrancara en 2 y la prueba mediría su propio andamiaje.
    final manager = WorkspaceManager(sessionIdentity: 'chrome-actions-test');
    // El servicio REAL, llevado a la escala por su propia API pública — sin
    // setters de prueba en un archivo que no me toca. Arranca en 0,8 (el
    // default que pidió el dueño) y sube de a 0,05.
    final zoomService = WindowZoomService();
    var guard = 0;
    while ((zoomService.scale - zoom).abs() > 0.001 && guard++ < 64) {
      if (zoomService.scale < zoom) {
        zoomService.zoomIn();
      } else {
        zoomService.zoomOut();
      }
    }
    expect(
      zoomService.scale,
      closeTo(zoom, 0.001),
      reason: 'la escala real quedó en ${zoomService.scale}',
    );
    addTearDown(zoomService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkspaceManager>.value(value: manager),
          ChangeNotifierProvider<WindowZoomService>.value(value: zoomService),
        ],
        child: const MaterialApp(
          home: Scaffold(
            // Producción envuelve el chrome en `WorkspaceChromeStyle`; es lo
            // que las acciones usan para saber que están SOBRE EL SHELL. Sin
            // esto la prueba ejercitaba su rama de otros hosts, que es
            // precisamente la que no queremos medir acá.
            body: WindowZoomScope(
              child: WorkspaceChromeStyle(
                data: WorkspaceChromeStyleData.vinabike,
                child: Column(children: <Widget>[WorkspaceTabBar()]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  for (final zoom in <double>[1.0, 0.8]) {
    final pct = (zoom * 100).round();
    testWidgets('el menú del + es legible y cabe en pantalla al $pct %',
        (tester) async {
      const viewport = Size(1631, 838);
      await pumpChrome(tester, size: viewport, zoom: zoom);

      final plus = find.byKey(const ValueKey<String>('workspace-new-tab'));
      expect(plus, findsOneWidget);
      final triggerRect = tester.getRect(plus);
      await tester.tap(plus);
      await tester.pumpAndSettle();

      final item = find.byKey(
        const ValueKey<String>('workspace-new-/dashboard'),
      );
      expect(item, findsOneWidget, reason: 'el menú abrió');
      expect(
        find.byType(VbPopoverSurface),
        findsOneWidget,
        reason: 'el menú debe consumir el owner visual O-02',
      );

      final rect = tester.getRect(item);
      final popoverRect = tester.getRect(find.byType(VbPopoverSurface));
      // 1. Ancho ÚTIL, acotado por ARRIBA y por abajo. El defecto original
      // dejaba cada opción en 28 px; la primera corrección se fue al otro
      // extremo y el menú ocupaba TODA la ventana (medido en la app real:
      // 2023 px de ancho). Un menú de ancho completo tampoco es un menú.
      expect(
        rect.width,
        greaterThan(120),
        reason: 'la opción volvió a quedar aplastada',
      );
      expect(
        rect.width,
        lessThan(320),
        reason: 'el menú se estiró a todo el ancho',
      );
      // 2. Y sigue dentro de la pantalla a los dos zooms.
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.top, greaterThanOrEqualTo(-0.5));
      expect(rect.right, lessThanOrEqualTo(viewport.width + 0.5));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height + 0.5));
      expect(
        popoverRect.top - triggerRect.bottom,
        closeTo(4, 0.01),
        reason: 'el gap O-02 debe seguir siendo exacto bajo zoom',
      );
      expect(
        popoverRect.right,
        closeTo(triggerRect.right, 0.01),
        reason: 'si no cabe a la derecha, O-02 alinea los bordes finales',
      );
      expect(popoverRect.left, greaterThanOrEqualTo(8));
      expect(popoverRect.right, lessThanOrEqualTo(viewport.width - 8));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('O-02 acota y desplaza los nueve comandos en un host bajo',
      (tester) async {
    const viewport = Size(1631, 220);
    final manager = await pumpChrome(tester, size: viewport, zoom: 1);

    await tester.tap(find.byKey(const ValueKey<String>('workspace-new-tab')));
    await tester.pumpAndSettle();

    final surface = find.byType(VbPopoverSurface);
    expect(surface, findsOneWidget);
    final surfaceRect = tester.getRect(surface);
    expect(surfaceRect.top, greaterThanOrEqualTo(8));
    expect(surfaceRect.bottom, lessThanOrEqualTo(viewport.height - 8));

    final last = find.byKey(
      const ValueKey<String>('workspace-new-/accounting/accounts'),
    );
    expect(last, findsOneWidget);
    expect(
      tester.getRect(last).bottom,
      greaterThan(surfaceRect.bottom),
      reason: 'el último comando comienza fuera del recorte visible',
    );

    final scroller = find.descendant(
      of: surface,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scroller, findsOneWidget);
    await tester.drag(scroller, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(last).bottom,
      lessThanOrEqualTo(surfaceRect.bottom + 0.01),
      reason: 'los nueve comandos siguen alcanzables sin escapar del viewport',
    );

    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(manager.workspaces.length, 2);
  });

  testWidgets('elegir Dashboard crea y activa el segundo espacio',
      (tester) async {
    final manager =
        await pumpChrome(tester, size: const Size(1631, 838), zoom: 0.8);
    expect(manager.workspaces.length, 1);
    expect(find.text('1/10'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('workspace-new-tab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('workspace-new-/dashboard')),
    );
    await tester.pumpAndSettle();

    expect(manager.workspaces.length, 2, reason: 'se creó el espacio');
    expect(find.text('2/10'), findsOneWidget, reason: 'el contador lo dice');
  });

  testWidgets('el grupo conserva sus capacidades, con etiqueta y caja A-02',
      (tester) async {
    await pumpChrome(tester, size: const Size(1631, 838), zoom: 1.0);
    final handle = tester.ensureSemantics();

    expect(
      find.byKey(const ValueKey<String>('workspace-chrome-actions')),
      findsOneWidget,
    );
    // `A-02`, regla dura: «Siempre tooltip + semanticLabel». LAS SEIS, no
    // tres: la revisión encontró que compartir, capturas y ajustes seguían con
    // su propia caja de 28 y glifos de 18/20, que es justo la mezcla de
    // alturas que el dueño reportó.
    for (final label in <String>[
      'Atrás',
      'Adelante',
      'Copiar enlace de página',
      'Capturas',
      'Nuevo espacio de trabajo',
      'Configuración rápida',
    ]) {
      expect(
        find.bySemanticsLabel(label),
        findsOneWidget,
        reason: '$label perdió su etiqueta accesible',
      );
    }
    // Y el contador N/10 sigue ahí.
    expect(find.text('1/10'), findsOneWidget);

    for (final key in <String>[
      'workspace-nav-back',
      'workspace-nav-forward',
      'workspace-share-link',
      'workspace-smart-screenshot',
      'workspace-new-tab',
      'workspace-quick-settings',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey<String>(key)));
      // `A-02` sobre shell: caja 32.
      // Contra la constante del owner, no contra un 32 copiado: si la ficha
      // `A-02` cambia, cambia en un solo lugar y la prueba lo sigue.
      expect(
        size.width,
        VbShellIconButton.box,
        reason: '$key no usa el owner A-02 sobre shell',
      );
      expect(size.height, VbShellIconButton.box, reason: '$key no mide 32');
    }
    handle.dispose();
  });
}
