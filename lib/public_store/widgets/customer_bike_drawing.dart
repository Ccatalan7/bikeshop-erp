import 'package:flutter/material.dart';

import '../models/customer_portal_presentation.dart';

/// El dibujo de una bici en trazo, por tipo: rígida, doble suspensión, ruta o
/// ciudad. El taller no les saca foto, así que las tarjetas del portal las
/// muestran como un catálogo muestra un producto, sobre el gris.
///
/// Las coordenadas son de un lienzo de 220×132 y se escalan al ancho.
class CustomerBikeDrawing extends StatelessWidget {
  const CustomerBikeDrawing({
    super.key,
    required this.silhouette,
    required this.width,
    this.color,
  });

  final CustomerBikeSilhouette silhouette;
  final double width;
  final Color? color;

  static const double aspectRatio = 220 / 132;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width / aspectRatio,
        child: CustomPaint(
          painter: _BikePainter(
            silhouette: silhouette,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _BikePainter extends CustomPainter {
  _BikePainter({required this.silhouette, required this.color});

  final CustomerBikeSilhouette silhouette;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 220;
    canvas.scale(s);

    Paint pen(double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(List<Offset> points, double width) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, pen(width));
    }

    void wheel(Offset center, {required double tire, double radius = 36}) {
      canvas.drawCircle(center, radius, pen(tire));
      canvas.drawCircle(center, radius - 6, pen(1.2));
      canvas.drawCircle(center, 2.5, pen(2));
    }

    switch (silhouette) {
      case CustomerBikeSilhouette.hardtail:
      case CustomerBikeSilhouette.fullSuspension:
        const rear = Offset(46, 92);
        const front = Offset(174, 92);
        const bb = Offset(104, 94);
        wheel(rear, tire: 5);
        wheel(front, tire: 5);
        // Cuadro: tubo de asiento, superior, dirección e inferior.
        line(const [bb, Offset(92, 44), Offset(152, 42), Offset(157, 56), bb],
            3.2);
        line(const [bb, rear], 2.6);
        if (silhouette == CustomerBikeSilhouette.fullSuspension) {
          // Vainas al balancín y el amortiguador contra el tubo inferior.
          line(const [rear, Offset(95, 58)], 2.6);
          line(const [Offset(95, 58), Offset(101, 52)], 3.2);
          line(const [Offset(101, 54), Offset(125, 68)], 6);
        } else {
          line(const [Offset(92, 49), rear], 2.6);
        }
        // Horquilla de suspensión: la barra gruesa arriba.
        line(const [Offset(157, 56), Offset(165, 74)], 5.5);
        line(const [Offset(165, 74), front], 2.6);
        line(const [Offset(152, 42), Offset(150, 33)], 2.8);
        line(const [Offset(139, 31), Offset(166, 29)], 2.8);
        line(const [Offset(92, 44), Offset(89, 33)], 2.8);
        line(const [Offset(76, 30.5), Offset(102, 30.5)], 4);
        canvas.drawCircle(bb, 9, pen(2.2));
        line(const [bb, Offset(111, 110)], 2.6);
        line(const [Offset(105, 110), Offset(118, 110)], 2.6);
      case CustomerBikeSilhouette.road:
        const rear = Offset(46, 92);
        const front = Offset(174, 92);
        const bb = Offset(104, 94);
        wheel(rear, tire: 3);
        wheel(front, tire: 3);
        line(const [bb, Offset(92, 42), Offset(152, 40), Offset(156, 54), bb],
            3);
        line(const [bb, rear], 2.4);
        line(const [Offset(92, 46), rear], 2.4);
        final fork = Path()
          ..moveTo(156, 54)
          ..quadraticBezierTo(164, 78, 174, 92);
        canvas.drawPath(fork, pen(2.8));
        line(const [Offset(152, 40), Offset(157, 35)], 2.8);
        // Manubrio de ruta, curvo hacia abajo.
        final bar = Path()
          ..moveTo(155, 35)
          ..lineTo(167, 35)
          ..cubicTo(176, 35, 176, 49, 167, 51);
        canvas.drawPath(bar, pen(2.8));
        line(const [Offset(92, 42), Offset(89, 30)], 2.8);
        line(const [Offset(77, 28.5), Offset(100, 28.5)], 4);
        canvas.drawCircle(bb, 9, pen(2.2));
        line(const [bb, Offset(111, 110)], 2.6);
        line(const [Offset(105, 110), Offset(118, 110)], 2.6);
      case CustomerBikeSilhouette.city:
        const rear = Offset(48, 94);
        const front = Offset(172, 94);
        const bb = Offset(104, 96);
        wheel(rear, tire: 3.5, radius: 35);
        wheel(front, tire: 3.5, radius: 35);
        // Tapabarros.
        canvas.drawArc(
          Rect.fromCircle(center: rear, radius: 41),
          -2.88,
          2.09,
          false,
          pen(2.4),
        );
        canvas.drawArc(
          Rect.fromCircle(center: front, radius: 41),
          -2.36,
          2.1,
          false,
          pen(2.4),
        );
        line(const [bb, Offset(90, 50), Offset(148, 50), Offset(152, 62), bb],
            3.2);
        line(const [bb, rear], 2.6);
        line(const [Offset(90, 54), rear], 2.6);
        final fork = Path()
          ..moveTo(152, 62)
          ..quadraticBezierTo(158, 84, 172, 94);
        canvas.drawPath(fork, pen(2.8));
        // Parrilla.
        line(const [Offset(22, 56), Offset(80, 56)], 2.4);
        line(const [Offset(30, 56), Offset(46, 91)], 2.4);
        line(const [Offset(148, 50), Offset(146, 38)], 2.8);
        final bar = Path()
          ..moveTo(136, 38)
          ..cubicTo(146, 34, 158, 34, 162, 44);
        canvas.drawPath(bar, pen(2.8));
        line(const [Offset(90, 50), Offset(88, 40)], 2.8);
        line(const [Offset(76, 38.5), Offset(100, 38.5)], 4);
        canvas.drawCircle(bb, 8, pen(2.2));
        line(const [bb, Offset(98, 112)], 2.6);
        line(const [Offset(92, 112), Offset(104, 112)], 2.6);
    }
  }

  @override
  bool shouldRepaint(_BikePainter oldDelegate) =>
      oldDelegate.silhouette != silhouette || oldDelegate.color != color;
}
