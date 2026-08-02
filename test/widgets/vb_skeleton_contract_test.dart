import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_skeleton.dart';

/// **X-01 · `VbSurfaceState`, rama `loading`** — contrato del esqueleto.
///
/// Cada regla existe porque romperla devuelve el defecto que `X-01` viene a
/// cerrar: un esqueleto que no ocupa el sitio del contenido deja que el control
/// de decisión salte, uno cuyo par de colores resuelve igual se queda quieto
/// sin que nadie lo note en claro/escritorio, y uno que anuncia por celda
/// convierte un aviso de carga en cuarenta.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppearancePreset? preset,
  Brightness brightness = Brightness.light,
  bool reduceMotion = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.resolve(
        preset: preset ?? AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
}

/// Píxel central del primer `RepaintBoundary` del árbol.
Future<Color> _centerPixel(WidgetTester tester) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary),
  );
  late Color color;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    final offset = ((height ~/ 2) * width + (width ~/ 2)) * 4;
    color = Color.fromARGB(
      data!.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
    image.dispose();
  });
  return color;
}

void main() {
  test('la geometría publicada es la del archivo de Design, no una estimación',
      () {
    // Leídas con `DesignSync` de `GUÍA GENERAL Viñabike · Componentes`, bloque
    // `X-01`, panel «LOADING — esqueleto de la forma real».
    expect(VbSkeleton.barHeight, 11, reason: 'guía: height:11px en fila');
    expect(VbSkeleton.labelHeight, 8, reason: 'guía: height:8px en cabecera');
    expect(VbSkeleton.barRadius, 4, reason: 'guía: border-radius:4px');
    expect(VbSkeleton.blockSize, 26, reason: 'guía: avatar 26×26');
    expect(VbSkeleton.blockRadius, 7, reason: 'guía: border-radius:7px');
    expect(VbSkeleton.sweepTile, 300, reason: 'guía: background-size:300px');
    expect(
      VbSkeleton.sweepPeriod,
      const Duration(milliseconds: 1100),
      reason: 'guía: animation vbShim 1.1s linear infinite',
    );
  });

  testWidgets('una barra ocupa exactamente el alto que publica',
      (tester) async {
    await _pump(
      tester,
      const SizedBox(width: 120, child: VbSkeleton.bar()),
    );
    expect(
        tester.getSize(find.byType(VbSkeleton)).height, VbSkeleton.barHeight);

    await _pump(
      tester,
      const SizedBox(width: 120, child: VbSkeleton.bar(height: 8)),
    );
    expect(tester.getSize(find.byType(VbSkeleton)).height, 8);

    await _pump(
      tester,
      const VbSkeleton.block(size: VbSkeleton.blockSize),
    );
    expect(
      tester.getSize(find.byType(VbSkeleton)),
      const Size(VbSkeleton.blockSize, VbSkeleton.blockSize),
    );
  });

  testWidgets(
      'el par del barrido sale de los roles y es DISTINTO en 6 presets × 2 brillos',
      (tester) async {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        final cell = '${preset.code}/${brightness.name}';
        await _pump(
          tester,
          const SizedBox(width: 120, child: VbSkeleton.bar()),
          preset: preset,
          brightness: brightness,
        );
        final element = tester.element(find.byType(VbSkeleton));
        final colors = VbSkeleton.resolveColors(element);
        final roles = VinabikeThemeRoles.of(element);

        expect(
          colors.base,
          roles.neutral.container,
          reason:
              '$cell: la base del esqueleto es neutral.container, no un hex',
        );
        expect(
          colors.highlight,
          Theme.of(element).colorScheme.surfaceContainerLow,
          reason: '$cell: el alto del barrido es surfaceContainerLow',
        );
        // Sin diferencia no hay barrido: el esqueleto queda inmóvil y el
        // defecto sólo se ve en el preset que resuelve igual.
        expect(
          colors.base,
          isNot(colors.highlight),
          reason: '$cell: base y alto iguales dejan el esqueleto sin barrido',
        );
      }
    }
  });

  testWidgets('lo que se pinta ES el rol, no un color parecido',
      (tester) async {
    // Cierra la tautología del contrato anterior: comprobar el accesor no
    // prueba que `build` lo use. Con movimiento reducido el relleno es plano,
    // así que el píxel central tiene que ser exactamente la base.
    await _pump(
      tester,
      const RepaintBoundary(
        child:
            SizedBox(width: 120, height: 40, child: VbSkeleton.bar(height: 40)),
      ),
    );
    final element = tester.element(find.byType(VbSkeleton));
    final expected = VbSkeleton.resolveColors(element).base;
    expect(await _centerPixel(tester), expected);
  });

  testWidgets('el movimiento reducido apaga el barrido, no lo hace lento',
      (tester) async {
    await _pump(
      tester,
      const SizedBox(width: 120, child: VbSkeleton.bar()),
    );
    expect(
      tester.hasRunningAnimations,
      isFalse,
      reason: 'con disableAnimations no queda ningún ticker vivo',
    );
    // Si quedara un `repeat()` corriendo, esto no volvería nunca.
    await tester.pumpAndSettle();

    await _pump(
      tester,
      const SizedBox(width: 120, child: VbSkeleton.bar()),
      reduceMotion: false,
    );
    expect(
      tester.hasRunningAnimations,
      isTrue,
      reason: 'sin reducción de movimiento el barrido corre',
    );
  });

  testWidgets('el barrido se mueve de verdad', (tester) async {
    await _pump(
      tester,
      const RepaintBoundary(
        child:
            SizedBox(width: 300, height: 40, child: VbSkeleton.bar(height: 40)),
      ),
      reduceMotion: false,
    );
    final first = await _centerPixel(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final second = await _centerPixel(tester);
    expect(
      first,
      isNot(second),
      reason: 'a 400 ms de un ciclo de 1100 ms el degradado ya se desplazó',
    );
    // Deja el ticker detenido para no arrastrar animaciones a la prueba siguiente.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('un grupo comparte UN reloj; una hoja suelta se lo hace propio',
      (tester) async {
    // Una silueta de Nóminas insinúa decenas de celdas. Con un
    // `AnimationController` por celda serían decenas de tickers pidiendo frame
    // y —peor que el costo— decenas de fases sueltas: el barrido dejaría de
    // leerse como UNA superficie cargando.
    Widget cells(int count) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < count; i++)
              const SizedBox(width: 120, child: VbSkeleton.bar()),
          ],
        );

    await _pump(
      tester,
      VbSkeletonGroup(child: cells(12)),
      reduceMotion: false,
    );
    expect(find.byType(VbSkeleton), findsNWidgets(12));
    expect(
      tester.binding.transientCallbackCount,
      1,
      reason: '12 celdas dentro de un grupo comparten un solo reloj',
    );

    await _pump(tester, cells(3), reduceMotion: false);
    expect(
      tester.binding.transientCallbackCount,
      3,
      reason: 'sin grupo, cada hoja suelta mantiene su propio reloj',
    );

    // Y el grupo respeta la reducción de movimiento igual que la hoja.
    await _pump(tester, VbSkeletonGroup(child: cells(12)));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('el esqueleto es mudo: anuncia la superficie, no cada celda',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      Semantics(
        label: 'Cargando la semana',
        liveRegion: true,
        container: true,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(width: 120, child: VbSkeleton.bar()),
            SizedBox(width: 120, child: VbSkeleton.bar()),
            VbSkeleton.block(size: VbSkeleton.blockSize),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Cargando la semana'), findsOneWidget);
    // Tres esqueletos, un solo anuncio: el nodo de semántica no crece con ellos.
    final node =
        tester.getSemantics(find.bySemanticsLabel('Cargando la semana'));
    expect(node.childrenCount, 0,
        reason: 'un esqueleto no aporta nodos de semántica');
    handle.dispose();
  });
}
