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

  static void report(dynamic error, [StackTrace? stackTrace]) {
    final message = error is String ? error : error.toString();
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
