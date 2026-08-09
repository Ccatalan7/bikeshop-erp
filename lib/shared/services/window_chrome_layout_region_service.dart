import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Geometry UIKit reserves for adaptive window chrome on iPadOS.
///
/// This is deliberately separate from Flutter's [MediaQueryData.padding].
/// Flutter 3.38 publishes `UIView.safeAreaInsets`, while iPadOS 26 window
/// controls are described by a different UIKit layout region. Treating the
/// latter as a global safe area would over-inset every routed surface.
@immutable
class WindowChromeLayoutSnapshot {
  const WindowChromeLayoutSnapshot({
    required this.viewSize,
    required this.margins,
    required this.revision,
  });

  static const zero = WindowChromeLayoutSnapshot(
    viewSize: Size.zero,
    margins: EdgeInsets.zero,
    revision: -1,
  );

  final Size viewSize;
  final EdgeInsets margins;
  final int revision;

  static WindowChromeLayoutSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final width = _finiteNonNegative(raw['width']);
    final height = _finiteNonNegative(raw['height']);
    final left = _finiteNonNegative(raw['left']);
    final right = _finiteNonNegative(raw['right']);
    final revision = _nonNegativeInt(raw['revision']);
    if (width == null ||
        height == null ||
        left == null ||
        right == null ||
        revision == null) {
      return null;
    }
    return WindowChromeLayoutSnapshot(
      viewSize: Size(width, height),
      margins: EdgeInsets.only(left: left, right: right),
      revision: revision,
    );
  }

  static double? _finiteNonNegative(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite && value >= 0 ? value : null;
  }

  static int? _nonNegativeInt(Object? raw) {
    if (raw is! num || !raw.toDouble().isFinite) return null;
    final value = raw.toInt();
    return value >= 0 && raw.toDouble() == value.toDouble() ? value : null;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowChromeLayoutSnapshot &&
      other.viewSize == viewSize &&
      other.margins == margins &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(viewSize, margins, revision);
}

/// Single Dart owner of the iPadOS adaptive-window layout channel.
class WindowChromeLayoutRegionService extends ChangeNotifier {
  WindowChromeLayoutRegionService({
    MethodChannel? channel,
    bool? supportedOverride,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _supportedOverride = supportedOverride;

  static const channelName = 'com.vinabike.erp/window_chrome_layout_region';
  static const getCurrentMetricsMethod = 'getCurrentMetrics';
  static const metricsChangedMethod = 'metricsChanged';

  final MethodChannel _channel;
  final bool? _supportedOverride;
  WindowChromeLayoutSnapshot _snapshot = WindowChromeLayoutSnapshot.zero;
  bool _started = false;

  WindowChromeLayoutSnapshot get snapshot => _snapshot;

  bool get _isSupported =>
      _supportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!_isSupported) return;

    _channel.setMethodCallHandler(handlePlatformCall);
    try {
      _accept(
        await _channel.invokeMethod<Object?>(getCurrentMetricsMethod),
      );
    } on MissingPluginException {
      // The Dart code may hot-restart against an older native host. Zero is a
      // valid fail-closed value until that host is rebuilt.
    } on PlatformException {
      // Geometry is an enhancement, never a reason to prevent app startup.
    }
  }

  @visibleForTesting
  Future<Object?> handlePlatformCall(MethodCall call) async {
    if (call.method == metricsChangedMethod) {
      _accept(call.arguments);
    }
    return null;
  }

  void _accept(Object? raw) {
    final next = WindowChromeLayoutSnapshot.tryParse(raw);
    if (next == null || next.revision <= _snapshot.revision) return;
    _snapshot = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isSupported && _started) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
