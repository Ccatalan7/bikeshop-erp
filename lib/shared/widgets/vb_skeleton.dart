import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// **X-01 · `VbSurfaceState`, rama `loading`** — el esqueleto del kit
/// compartido (`GUÍA GENERAL Viñabike · Componentes`, sección *09 Estados de
/// superficie*: «Seis estados obligatorios por superficie. Una pantalla sin
/// ellos no está terminada»).
///
/// **Qué resuelve.** Un `CircularProgressIndicator` centrado no ocupa el sitio
/// de nada, así que al llegar los datos la pantalla se reconstruye entera y el
/// control de decisión **salta**. `X-01` dibuja la silueta de lo que viene, en
/// su posición final.
///
/// **Geometría y movimiento leídos del archivo de Design con `DesignSync`, no
/// estimados:** barra de texto `h 11` (fila) y `h 8` (rótulo de cabecera),
/// `radius 4`; bloque de avatar `26×26` con `radius 7`; barrido de
/// `linear-gradient(90deg, base, alto, base)` con tile de `300 px` y
/// `1,1 s linear infinite`.
///
/// **El color no se escribe acá.** El par `#EEF1F4 / #F7F8FA` de la guía son
/// los roles `neutral.container` y `surfaceContainerLow`; pegarlos literales
/// congelaría el modo claro dentro del widget, que es lo que la primera regla
/// de la guía prohíbe (`PROHIBIDO EL HEX LITERAL EN CUALQUIER WIDGET`).
///
/// **Lo que este archivo NO trae, y por qué.** `X-01` define seis estados. La
/// respuesta de `get_file` sobre la guía llega cortada en **262.144 B exactos
/// (256 KiB)** justo dentro de `X-01`: sólo el panel *LOADING* es legible.
/// `empty`, `error`, `no-results`, `read-only` y `sin permiso` quedan pasado el
/// corte y **no se inventan** — se implementan cuando se puedan leer.
///
/// **El marco lo pone el host, a propósito.** La guía dibuja su ejemplo con
/// `radius 8` y una divisoria `#F0F3F6` que no tiene rol semántico en este ERP.
/// El frame `5k` exige «la silueta **real** de la tabla», así que el contenedor,
/// el radio, el borde y la divisoria son los de la superficie que está
/// cargando; de `X-01` sale el relleno.
class VbSkeleton extends StatefulWidget {
  /// Barra de texto. `width` nulo = ocupa el ancho disponible.
  const VbSkeleton.bar({
    super.key,
    this.width,
    this.height = barHeight,
  })  : _radius = barRadius,
        assert(height > 0);

  /// Bloque cuadrado — el avatar de la fila en el ejemplo de la guía.
  const VbSkeleton.block({
    super.key,
    required double size,
    double radius = blockRadius,
  })  : width = size,
        height = size,
        _radius = radius;

  /// Alto de una barra de texto de fila. Guía: `height:11px`.
  static const double barHeight = 11;

  /// Alto de un rótulo de cabecera. Guía: `height:8px`.
  static const double labelHeight = 8;

  /// Guía: `border-radius:4px` en toda barra de texto.
  static const double barRadius = 4;

  /// Guía: el bloque de avatar es `26×26` con `border-radius:7px`.
  static const double blockSize = 26;
  static const double blockRadius = 7;

  /// Guía: `background-size:300px 100%` con `@keyframes vbShim` de `-300px` a
  /// `300px`. El tile es fijo, así que el barrido cruza igual de rápido una
  /// celda angosta y una ancha.
  static const double sweepTile = 300;

  /// Guía: `animation: vbShim 1.1s linear infinite`.
  ///
  /// El frame `5k` anota «sin pulso agresivo: 1,4 s de fundido suave». Los dos
  /// valores se leyeron con `DesignSync` y **no coinciden**. Manda el dueño del
  /// componente compartido —la guía— porque `5k` lo compone, no lo define; la
  /// divergencia queda declarada en el handoff en vez de resolverse en
  /// silencio. Lo que sí cumplen los dos: es un barrido, nunca un pulso.
  static const Duration sweepPeriod = Duration(milliseconds: 1100);

  final double? width;
  final double height;
  final double _radius;

  /// El par del barrido, resuelto por rol.
  ///
  /// Público porque el contrato tiene que poder comprobar **dos** cosas que no
  /// se ven en el árbol: que salen de `VinabikeThemeRoles` y no de un hex, y
  /// que en cada preset × brillo son **distintos** — si resuelven al mismo
  /// color el esqueleto queda inmóvil y nadie lo nota mirando claro/escritorio.
  static ({Color base, Color highlight}) resolveColors(BuildContext context) {
    return (
      base: VinabikeThemeRoles.of(context).neutral.container,
      highlight: Theme.of(context).colorScheme.surfaceContainerLow,
    );
  }

  @override
  State<VbSkeleton> createState() => _VbSkeletonState();
}

/// Reloj compartido del barrido para todo un host que carga.
///
/// Una superficie de Nóminas insinúa ~40 celdas; con un `AnimationController`
/// por celda serían 40 tickers pidiendo frame, y —peor que el costo— **40 fases
/// independientes**: el barrido dejaría de leerse como una sola superficie
/// cargando y pasaría a parpadear por partes.
///
/// El host envuelve su silueta en [VbSkeletonGroup] y cada [VbSkeleton] de
/// adentro lee **su** fase. Una hoja suelta (una celda en una lista, un
/// catálogo) sigue funcionando sin grupo: se crea su propio reloj. El contrato
/// comprueba las dos cosas, y que el grupo deje **un solo** ticker vivo.
class VbSkeletonGroup extends StatefulWidget {
  const VbSkeletonGroup({super.key, required this.child});

  final Widget child;

  @override
  State<VbSkeletonGroup> createState() => _VbSkeletonGroupState();
}

class _VbSkeletonGroupState extends State<VbSkeletonGroup>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = _syncSweep(
      current: _controller,
      context: context,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VbSkeletonClock(sweep: _controller, child: widget.child);
  }
}

class _VbSkeletonClock extends InheritedWidget {
  const _VbSkeletonClock({required this.sweep, required super.child});

  final Animation<double>? sweep;

  static _VbSkeletonClock? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VbSkeletonClock>();

  @override
  bool updateShouldNotify(_VbSkeletonClock old) => old.sweep != sweep;
}

/// La guía declara `@media (prefers-reduced-motion:reduce)` sobre todo el
/// canvas. Acá eso es `disableAnimations`: **sin barrido**, no un barrido lento.
AnimationController? _syncSweep({
  required AnimationController? current,
  required BuildContext context,
  required TickerProvider vsync,
}) {
  final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (reduced) {
    current?.dispose();
    return null;
  }
  return current ??
      (AnimationController(vsync: vsync, duration: VbSkeleton.sweepPeriod)
        ..repeat());
}

class _VbSkeletonState extends State<VbSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;
  Animation<double>? _sweep;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = _VbSkeletonClock.maybeOf(context)?.sweep;
    if (shared != null) {
      _own?.dispose();
      _own = null;
      _sweep = shared;
      return;
    }
    // Sin grupo alrededor —una hoja suelta— el reloj es propio. Es el caso de
    // una celda aislada, no el de una pantalla entera.
    _own = _syncSweep(current: _own, context: context, vsync: this);
    _sweep = _own;
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (:base, :highlight) = VbSkeleton.resolveColors(context);
    final controller = _sweep;

    final box = SizedBox(
      width: widget.width,
      height: widget.height,
      child: controller == null
          ? _VbSkeletonSurface(
              base: base,
              highlight: highlight,
              radius: widget._radius,
              phase: 0,
              animated: false,
            )
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _VbSkeletonSurface(
                base: base,
                highlight: highlight,
                radius: widget._radius,
                phase: controller.value,
                animated: true,
              ),
            ),
    );

    // Un esqueleto no se lee: no tiene contenido que anunciar. La superficie
    // que carga publica UNA etiqueta viva; repetirla por celda convertiría un
    // aviso en cuarenta.
    return ExcludeSemantics(child: box);
  }
}

class _VbSkeletonSurface extends StatelessWidget {
  const _VbSkeletonSurface({
    required this.base,
    required this.highlight,
    required this.radius,
    required this.phase,
    required this.animated,
  });

  final Color base;
  final Color highlight;
  final double radius;
  final double phase;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VbSkeletonPainter(
        base: base,
        highlight: highlight,
        radius: radius,
        phase: phase,
        animated: animated,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _VbSkeletonPainter extends CustomPainter {
  const _VbSkeletonPainter({
    required this.base,
    required this.highlight,
    required this.radius,
    required this.phase,
    required this.animated,
  });

  final Color base;
  final Color highlight;
  final double radius;
  final double phase;
  final bool animated;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(radius, size.shortestSide / 2)),
    );
    final paint = Paint();
    if (!animated) {
      paint.color = base;
    } else {
      // CSS: `background-size:300px 100%` + `background-position` de -300px a
      // 300px. Un tile de 300 desplazado 300 vuelve a coincidir consigo mismo,
      // así que el ciclo cierra sin salto.
      final dx = (phase * VbSkeleton.sweepTile) - VbSkeleton.sweepTile;
      paint.shader = ui.Gradient.linear(
        Offset(dx, 0),
        Offset(dx + VbSkeleton.sweepTile, 0),
        <Color>[base, highlight, base],
        // `linear-gradient(90deg, base 0%, alto 40%, base 80%)`.
        <double>[0, 0.4, 0.8],
        TileMode.repeated,
      );
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_VbSkeletonPainter old) =>
      old.phase != phase ||
      old.base != base ||
      old.highlight != highlight ||
      old.radius != radius ||
      old.animated != animated;
}
