import 'package:flutter/foundation.dart';

class GlobalErrorNotifier extends ChangeNotifier {
  String? error;
  String? stackTrace;

  void setError(String error, [String? stackTrace]) {
    this.error = error;
    this.stackTrace = stackTrace;
    notifyListeners();
  }

  void clear() {
    error = null;
    stackTrace = null;
    notifyListeners();
  }
}

class ErrorReportingService {
  static final GlobalErrorNotifier notifier = GlobalErrorNotifier();

  /// List of error patterns to suppress (Flutter Web-specific issues)
  static const List<String> _suppressedErrorPatterns = [
    'disposed',
    'EngineFlutterView',
    'LegacyJavaScriptObject',
    'isDisposed',
    'RenderFlex overflowed', // Layout overflow (non-critical visual issue)
    'overflowed by', // Generic overflow pattern
    'BindingError', // CanvasKit WebGL issues
    'ColorSpace',
    'Picture',
    'Typeface',
    'Shader',
  ];

  /// Check if an error should be suppressed (web-specific errors)
  static bool _shouldSuppressError(String message) {
    // Check if error matches any suppressed patterns (on all platforms)
    for (final pattern in _suppressedErrorPatterns) {
      if (message.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  static void report(dynamic error, [StackTrace? stackTrace]) {
    final message = error is String ? error : error.toString();

    // Suppress known Flutter Web-specific errors that don't affect functionality
    if (_shouldSuppressError(message)) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ [ErrorReportingService] Suppressed web-specific error: ${message.substring(0, message.length.clamp(0, 80))}...');
      }
      return;
    }

    notifier.setError(message, stackTrace?.toString());

    // Always log to console for debugging
    print('🔴 [GLOBAL ERROR CAUGHT] $message');
    if (stackTrace != null) {
      print('🔴 [STACK TRACE] $stackTrace');
    }

    if (kDebugMode) {
      debugPrint('[GlobalError] $message');
      if (stackTrace != null) {
        debugPrint('[GlobalError] Stack: $stackTrace');
      }
    }
  }

  static void clear() {
    notifier.clear();
  }
}
