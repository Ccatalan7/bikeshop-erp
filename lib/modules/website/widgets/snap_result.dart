class SnapResult {
  final double x;
  final double y;
  final double? guideX;
  final double? guideY;

  SnapResult({
    required this.x,
    required this.y,
    this.guideX,
    this.guideY,
  });
}
