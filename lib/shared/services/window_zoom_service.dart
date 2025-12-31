import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralizes zoom handling - works on all platforms
/// Desktop: keyboard shortcuts (Cmd/Ctrl +/-), Mobile: manual controls only
class WindowZoomService extends ChangeNotifier {
  WindowZoomService() {
    _registerGlobalZoomShortcuts();
  }

  bool _shortcutsRegistered = false;
  bool Function(KeyEvent event)? _keyHandler;

  // User requested default zoom to be 0.8 (equivalent to pressing Cmd- twice)
  static const double _defaultScale = 0.8;
  static const double _minScale = 0.5;
  static const double _maxScale = 3.0;
  static const double _step = 0.05;

  double _scale = _defaultScale;

  double get scale => _scale;
  bool get isZoomed => _scale != _defaultScale;

  /// Zoom is now supported on all platforms
  static bool get isSupportedPlatform => true;

  /// Check if running on desktop (for keyboard shortcut support)
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Check if running on macOS (for keyboard shortcut modifier)
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  void _registerGlobalZoomShortcuts() {
    // Only register keyboard shortcuts on desktop platforms
    if (!isDesktop) return;
    if (_shortcutsRegistered) return;

    // Shortcuts/Actions can be overridden by focused widgets (like EditableText).
    // We register a global handler so Cmd/Ctrl +/- works consistently.
    _keyHandler = (event) {
      if (event is! KeyDownEvent) return false;

      final wantsCmdOrCtrl = isMacOS
          ? HardwareKeyboard.instance.isMetaPressed
          : HardwareKeyboard.instance.isControlPressed;
      if (!wantsCmdOrCtrl) return false;

      final key = event.logicalKey;

      // Zoom In: Cmd/Ctrl + (+) which is typically '=' with Shift
      if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd) {
        zoomIn();
        return true;
      }

      // Zoom Out
      if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        zoomOut();
        return true;
      }

      // Reset
      if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        reset();
        return true;
      }

      return false;
    };

    HardwareKeyboard.instance.addHandler(_keyHandler!);
    _shortcutsRegistered = true;
  }

  void zoomIn() {
    _updateScale(_scale + _step);
  }

  void zoomOut() {
    _updateScale(_scale - _step);
  }

  void reset() {
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

  @override
  void dispose() {
    final handler = _keyHandler;
    if (_shortcutsRegistered && handler != null && isSupportedPlatform) {
      HardwareKeyboard.instance.removeHandler(handler);
    }
    super.dispose();
  }
}
