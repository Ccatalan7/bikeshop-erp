import 'package:flutter/material.dart';
import 'package:vinabike_public_core/public_store/models/customer_bike_drawing_geometry.dart';

import '../models/customer_portal_presentation.dart';

/// El dibujo de una bici en trazo, por tipo: rígida, doble suspensión, ruta o
/// ciudad. El taller no les saca foto, así que las tarjetas del portal las
/// muestran como un catálogo muestra un producto, sobre el gris.
///
/// Los trazos son de `customerBikeStrokes` (el núcleo, el mismo dibujo que
/// la tienda HTML escribe en SVG), en un lienzo de 220×132 que se escala al
/// ancho.
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

  static const double aspectRatio =
      customerBikeDrawingWidth / customerBikeDrawingHeight;

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
    canvas.scale(size.width / customerBikeDrawingWidth);
    Offset at(BikePoint point) => Offset(point.$1, point.$2);
    for (final stroke in customerBikeStrokes(silhouette)) {
      final pen = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      switch (stroke) {
        case BikePolyline(:final points):
          final path = Path()..moveTo(points.first.$1, points.first.$2);
          for (final point in points.skip(1)) {
            path.lineTo(point.$1, point.$2);
          }
          canvas.drawPath(path, pen);
        case BikeCircle(:final center, :final radius):
          canvas.drawCircle(at(center), radius, pen);
        case BikeQuad(:final from, :final control, :final to):
          canvas.drawPath(
            Path()
              ..moveTo(from.$1, from.$2)
              ..quadraticBezierTo(control.$1, control.$2, to.$1, to.$2),
            pen,
          );
        case BikeCubic(
            :final from,
            :final lineTo,
            :final control1,
            :final control2,
            :final to,
          ):
          final path = Path()..moveTo(from.$1, from.$2);
          for (final point in lineTo) {
            path.lineTo(point.$1, point.$2);
          }
          path.cubicTo(
            control1.$1,
            control1.$2,
            control2.$1,
            control2.$2,
            to.$1,
            to.$2,
          );
          canvas.drawPath(path, pen);
        case BikeArc(:final center, :final radius, :final start, :final sweep):
          canvas.drawArc(
            Rect.fromCircle(center: at(center), radius: radius),
            start,
            sweep,
            false,
            pen,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_BikePainter oldDelegate) =>
      oldDelegate.silhouette != silhouette || oldDelegate.color != color;
}
