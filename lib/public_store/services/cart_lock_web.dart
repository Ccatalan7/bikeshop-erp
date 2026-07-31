import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'cart_lock_base.dart';

CartLockCoordinator createCartLockCoordinator() {
  return const _WebCartLockCoordinator();
}

class _WebCartLockCoordinator implements CartLockCoordinator {
  const _WebCartLockCoordinator();

  @override
  Future<void> synchronized(
    String resourceName,
    Future<void> Function() action,
  ) async {
    final navigator = web.window.navigator as JSObject;
    final rawLocks = navigator.getProperty<JSAny?>('locks'.toJS);
    if (rawLocks == null || rawLocks.isUndefinedOrNull) {
      throw UnsupportedError(
        'El navegador no permite coordinar el carrito entre pestañas.',
      );
    }

    Object? actionError;
    StackTrace? actionStackTrace;
    final callback = ((JSAny? _) {
      return (() async {
        try {
          await action();
        } catch (error, stackTrace) {
          // Let the JavaScript callback resolve so the lock is always released,
          // then rethrow the original Dart error below with its real stack.
          actionError = error;
          actionStackTrace = stackTrace;
        }
      }())
          .toJS;
    }).toJS;

    await web.window.navigator.locks.request(resourceName, callback).toDart;

    final error = actionError;
    if (error != null) {
      Error.throwWithStackTrace(error, actionStackTrace!);
    }
  }
}
