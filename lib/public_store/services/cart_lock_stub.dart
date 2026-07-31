import 'dart:async';

import 'cart_lock_base.dart';

CartLockCoordinator createCartLockCoordinator() {
  return const _ProcessCartLockCoordinator();
}

class _ProcessCartLockCoordinator implements CartLockCoordinator {
  const _ProcessCartLockCoordinator();

  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  @override
  Future<void> synchronized(
    String resourceName,
    Future<void> Function() action,
  ) {
    final preceding = _tails[resourceName] ?? Future<void>.value();
    final operation = preceding.catchError((Object _) {}).then((_) => action());
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    late final Future<void> tail;
    tail = settled.whenComplete(() {
      if (identical(_tails[resourceName], tail)) {
        _tails.remove(resourceName);
      }
    });
    _tails[resourceName] = tail;
    return operation;
  }
}
