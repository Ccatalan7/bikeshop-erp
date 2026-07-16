import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bikeshop_models.dart';

class BikeMeasurementTimeline extends StatefulWidget {
  final String title;
  final String? unit;
  final List<BikeObservation> points;
  final Color accentColor;
  final VoidCallback? onTapNode;

  const BikeMeasurementTimeline({
    super.key,
    required this.title,
    this.unit,
    required this.points,
    required this.accentColor,
    this.onTapNode,
  });

  @override
  State<BikeMeasurementTimeline> createState() =>
      _BikeMeasurementTimelineState();
}

class _BikeMeasurementTimelineState extends State<BikeMeasurementTimeline> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 180, // Taller to allow beautiful gradients and floating text
          padding:
              const EdgeInsets.only(top: 40, bottom: 20, left: 10, right: 10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TimelineSplinePainter(
                    points: widget.points,
                    accentColor: widget.accentColor,
                    hoveredIndex: _hoveredIndex,
                  ),
                ),
              ),
              ...List.generate(widget.points.length, (index) {
                final normalizedX = widget.points.length > 1
                    ? index / (widget.points.length - 1)
                    : 0.5;

                return Positioned(
                  left: (constraints.maxWidth - 20) * normalizedX - 15,
                  top: 0,
                  bottom: 0,
                  width: 30, // Hover area
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hoveredIndex = index),
                    onExit: (_) => setState(() => _hoveredIndex = null),
                    child: GestureDetector(
                      onTap: widget.onTapNode,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineSplinePainter extends CustomPainter {
  final List<BikeObservation> points;
  final Color accentColor;
  final int? hoveredIndex;

  _TimelineSplinePainter({
    required this.points,
    required this.accentColor,
    required this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final values = points.map((p) => p.valueNumeric ?? 0.0).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    final width = size.width;
    final height = size.height;

    final yPad = height * 0.25;
    final drawableHeight = height - (yPad * 2);

    List<Offset> paintPoints = [];
    for (int i = 0; i < points.length; i++) {
      final normalizedX = points.length == 1 ? 0.5 : i / (points.length - 1);
      final val = points[i].valueNumeric ?? 0.0;
      final normalizedY = (val - minVal) / range;
      
      final x = normalizedX * width;
      final y = height - yPad - (normalizedY * drawableHeight);
      paintPoints.add(Offset(x, y));
    }

    final path = Path();
    if (paintPoints.length == 1) {
      path.moveTo(0, paintPoints[0].dy);
      path.lineTo(width, paintPoints[0].dy);
    } else {
      path.moveTo(paintPoints[0].dx, paintPoints[0].dy);
      for (int i = 0; i < paintPoints.length - 1; i++) {
        final p0 = paintPoints[i];
        final p1 = paintPoints[i + 1];
        final controlPointX = p0.dx + ((p1.dx - p0.dx) / 2);
        path.cubicTo(
          controlPointX,
          p0.dy,
          controlPointX,
          p1.dy,
          p1.dx,
          p1.dy,
        );
      }
    }

    // Gradient fill under curve
    final fillPath = Path.from(path)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, height - drawableHeight - yPad),
        Offset(0, height),
        [
          accentColor.withValues(alpha: 0.15),
          accentColor.withValues(alpha: 0.0),
        ],
      )
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(fillPath, fillPaint);

    // Glowing main stroke
    final strokePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(path, strokePaint);

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);

    for (int i = 0; i < paintPoints.length; i++) {
      final point = points[i];
      final pos = paintPoints[i];
      final isHovered = hoveredIndex == i;

      // Tag bounding box above curve (like mockup)
      if (point.title.isNotEmpty || point.summary != null) {
        final tagText =
            point.summary?.isNotEmpty == true ? point.summary! : point.title;
        // Draw little connecting line
        canvas.drawLine(
          pos, 
          Offset(pos.dx, pos.dy - 20), 
            Paint()
              ..color = Colors.grey.shade300
              ..strokeWidth = 1.5);
        
        textPainter.text = TextSpan(
          text: tagText,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: isHovered ? 13 : 11,
            fontWeight: isHovered ? FontWeight.w600 : FontWeight.w500,
          ),
        );
        textPainter.layout();
        
        final rectWidth = textPainter.width + 16;
        final rectHeight = textPainter.height + 10;
        final rectLeft = pos.dx - (rectWidth / 2);
        final rectTop = pos.dy - 20 - rectHeight;
        
        final tagRRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(rectLeft, rectTop, rectWidth, rectHeight),
          const Radius.circular(8),
        );
        
        canvas.drawRRect(
          tagRRect, 
          Paint()
            ..color = isHovered ? Colors.white : Colors.grey.shade50
              ..style = PaintingStyle.fill);
        canvas.drawRRect(
          tagRRect, 
          Paint()
            ..color = isHovered ? Colors.grey.shade400 : Colors.grey.shade200
            ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
        
        textPainter.paint(canvas, Offset(rectLeft + 8, rectTop + 5));
      }

      // Draw node circle
      canvas.drawCircle(pos, isHovered ? 7 : 5, Paint()..color = accentColor);
      canvas.drawCircle(pos, isHovered ? 4 : 2, Paint()..color = Colors.white);

      if (isHovered) {
        canvas.drawCircle(
            pos,
            14,
            Paint()
              ..color = accentColor.withValues(alpha: 0.2)
              ..style = PaintingStyle.fill);
      }

      // Draw Value text below
      final valStr =
          _formatObservationValue(point.valueNumeric) + (point.unit ?? '');
      textPainter.text = TextSpan(
        text: valStr,
        style: TextStyle(
          color: Colors.black87,
          fontWeight: isHovered ? FontWeight.bold : FontWeight.w600,
          fontSize: isHovered ? 14 : 12,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(pos.dx - (textPainter.width / 2), pos.dy + 12));

      // Draw Date text
      final dateStr = DateFormat('MMM dd').format(point.observedAt);
      textPainter.text = TextSpan(
        text: dateStr,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 10,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(pos.dx - (textPainter.width / 2), pos.dy + 30));
    }
  }

  String _formatObservationValue(double? value) {
    if (value == null) return '--';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    if (value.abs() >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _TimelineSplinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}
