// The customer portal's line drawing of a bike, by type, as strokes on a
// 220×132 canvas. Flutter's `CustomerBikeDrawing` paints them and the HTML
// store writes them as SVG, so both draw the same bike (moved from the
// Flutter painter on 2026-10-06).
import 'customer_portal_presentation.dart';

/// The canvas the strokes are drawn on; a drawing scales it to its width.
const customerBikeDrawingWidth = 220.0;
const customerBikeDrawingHeight = 132.0;

typedef BikePoint = (double x, double y);

/// One stroke, with round caps and joins.
sealed class BikeStroke {
  const BikeStroke(this.width);
  final double width;
}

/// Straight segments through [points].
class BikePolyline extends BikeStroke {
  const BikePolyline(this.points, double width) : super(width);
  final List<BikePoint> points;
}

class BikeCircle extends BikeStroke {
  const BikeCircle(this.center, this.radius, double width) : super(width);
  final BikePoint center;
  final double radius;
}

/// A quadratic curve from [from] to [to] bent toward [control].
class BikeQuad extends BikeStroke {
  const BikeQuad(this.from, this.control, this.to, double width) : super(width);
  final BikePoint from;
  final BikePoint control;
  final BikePoint to;
}

/// Segments to [lineTo] (none or more), then a cubic curve to [to].
class BikeCubic extends BikeStroke {
  const BikeCubic(
    this.from,
    this.lineTo,
    this.control1,
    this.control2,
    this.to,
    double width,
  ) : super(width);
  final BikePoint from;
  final List<BikePoint> lineTo;
  final BikePoint control1;
  final BikePoint control2;
  final BikePoint to;
}

/// An arc of the circle around [center], from [start] radians clockwise
/// (the canvas' y grows downward) through [sweep] radians.
class BikeArc extends BikeStroke {
  const BikeArc(this.center, this.radius, this.start, this.sweep, double width)
    : super(width);
  final BikePoint center;
  final double radius;
  final double start;
  final double sweep;
}

/// The strokes of [silhouette], in painting order.
List<BikeStroke> customerBikeStrokes(CustomerBikeSilhouette silhouette) {
  final strokes = <BikeStroke>[];
  void line(List<BikePoint> points, double width) =>
      strokes.add(BikePolyline(points, width));
  void wheel(BikePoint center, {required double tire, double radius = 36}) {
    strokes
      ..add(BikeCircle(center, radius, tire))
      ..add(BikeCircle(center, radius - 6, 1.2))
      ..add(BikeCircle(center, 2.5, 2));
  }

  switch (silhouette) {
    case CustomerBikeSilhouette.hardtail:
    case CustomerBikeSilhouette.fullSuspension:
      const rear = (46.0, 92.0);
      const front = (174.0, 92.0);
      const bb = (104.0, 94.0);
      wheel(rear, tire: 5);
      wheel(front, tire: 5);
      // Cuadro: tubo de asiento, superior, dirección e inferior.
      line(const [bb, (92, 44), (152, 42), (157, 56), bb], 3.2);
      line(const [bb, rear], 2.6);
      if (silhouette == CustomerBikeSilhouette.fullSuspension) {
        // Vainas al balancín y el amortiguador contra el tubo inferior.
        line(const [rear, (95, 58)], 2.6);
        line(const [(95, 58), (101, 52)], 3.2);
        line(const [(101, 54), (125, 68)], 6);
      } else {
        line(const [(92, 49), rear], 2.6);
      }
      // Horquilla de suspensión: la barra gruesa arriba.
      line(const [(157, 56), (165, 74)], 5.5);
      line(const [(165, 74), front], 2.6);
      line(const [(152, 42), (150, 33)], 2.8);
      line(const [(139, 31), (166, 29)], 2.8);
      line(const [(92, 44), (89, 33)], 2.8);
      line(const [(76, 30.5), (102, 30.5)], 4);
      strokes.add(const BikeCircle(bb, 9, 2.2));
      line(const [bb, (111, 110)], 2.6);
      line(const [(105, 110), (118, 110)], 2.6);
    case CustomerBikeSilhouette.road:
      const rear = (46.0, 92.0);
      const front = (174.0, 92.0);
      const bb = (104.0, 94.0);
      wheel(rear, tire: 3);
      wheel(front, tire: 3);
      line(const [bb, (92, 42), (152, 40), (156, 54), bb], 3);
      line(const [bb, rear], 2.4);
      line(const [(92, 46), rear], 2.4);
      strokes.add(const BikeQuad((156, 54), (164, 78), front, 2.8));
      line(const [(152, 40), (157, 35)], 2.8);
      // Manubrio de ruta, curvo hacia abajo.
      strokes.add(
        const BikeCubic((155, 35), [(167, 35)], (176, 35), (176, 49), (
          167,
          51,
        ), 2.8),
      );
      line(const [(92, 42), (89, 30)], 2.8);
      line(const [(77, 28.5), (100, 28.5)], 4);
      strokes.add(const BikeCircle(bb, 9, 2.2));
      line(const [bb, (111, 110)], 2.6);
      line(const [(105, 110), (118, 110)], 2.6);
    case CustomerBikeSilhouette.city:
      const rear = (48.0, 94.0);
      const front = (172.0, 94.0);
      const bb = (104.0, 96.0);
      wheel(rear, tire: 3.5, radius: 35);
      wheel(front, tire: 3.5, radius: 35);
      // Tapabarros.
      strokes
        ..add(const BikeArc(rear, 41, -2.88, 2.09, 2.4))
        ..add(const BikeArc(front, 41, -2.36, 2.1, 2.4));
      line(const [bb, (90, 50), (148, 50), (152, 62), bb], 3.2);
      line(const [bb, rear], 2.6);
      line(const [(90, 54), rear], 2.6);
      strokes.add(const BikeQuad((152, 62), (158, 84), front, 2.8));
      // Parrilla.
      line(const [(22, 56), (80, 56)], 2.4);
      line(const [(30, 56), (46, 91)], 2.4);
      line(const [(148, 50), (146, 38)], 2.8);
      strokes.add(
        const BikeCubic((136, 38), [], (146, 34), (158, 34), (162, 44), 2.8),
      );
      line(const [(90, 50), (88, 40)], 2.8);
      line(const [(76, 38.5), (100, 38.5)], 4);
      strokes.add(const BikeCircle(bb, 8, 2.2));
      line(const [bb, (98, 112)], 2.6);
      line(const [(92, 112), (104, 112)], 2.6);
  }
  return strokes;
}
