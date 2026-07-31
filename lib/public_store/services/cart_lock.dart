import 'cart_lock_base.dart';
import 'cart_lock_stub.dart' if (dart.library.js_interop) 'cart_lock_web.dart'
    as platform;

export 'cart_lock_base.dart';

CartLockCoordinator createCartLockCoordinator() {
  return platform.createCartLockCoordinator();
}
