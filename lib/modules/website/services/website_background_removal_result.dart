import 'dart:typed_data';

class WebsiteBackgroundRemovalResult {
  final Uint8List pngBytes;
  final double removedRatio;
  final double borderAgreement;
  final int width;
  final int height;
  final bool alreadyTransparent;

  const WebsiteBackgroundRemovalResult({
    required this.pngBytes,
    required this.removedRatio,
    required this.borderAgreement,
    required this.width,
    required this.height,
    this.alreadyTransparent = false,
  });

  bool get isUseful =>
      !alreadyTransparent && removedRatio >= 0.015 && removedRatio <= 0.97;

  bool get isLikelyUniformBackground =>
      isUseful && borderAgreement >= 0.72 && removedRatio >= 0.04;
}
