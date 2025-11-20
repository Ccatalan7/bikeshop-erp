import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralizes desktop zoom handling so we can mirror browser-style shortcuts
/// on Windows builds without affecting other platforms.
class WindowZoomService extends ChangeNotifier {
  WindowZoomService();

  static const double _defaultScale = 1.0;
  static const double _minScale = 0.5;
  static const double _maxScale = 3.0;
  static const double _step = 0.1;

  double _scale = _defaultScale;

  double get scale => _scale;
  bool get isZoomed => _scale != _defaultScale;

  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  void zoomIn() {
    if (!isSupportedPlatform) return;
    _updateScale(_scale + _step);
  }

  void zoomOut() {
    if (!isSupportedPlatform) return;
    _updateScale(_scale - _step);
  }

  void reset() {
    if (!isSupportedPlatform) return;
    _updateScale(_defaultScale);
  }

  void _updateScale(double value) {
    final clamped = value.clamp(_minScale, _maxScale);
    if ((clamped - _scale).abs() < 0.0001) {
      return;
    }
    _scale = clamped;
    notifyListeners();
  }
}
