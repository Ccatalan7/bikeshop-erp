import 'package:flutter/widgets.dart';

/// Transient route-operation state for Website Builder authoring chrome.
///
/// A contextual sheet leaves the authored page mounted and visible, but the
/// page's inline controls are not actionable while that sheet owns the task.
/// This controller publishes that distinction without changing Edit mode,
/// selection, document geometry, dirty state or history.
///
/// Leases are depth-counted because a contextual task can open another modal.
/// Only the final release re-enables inline chrome; `try/finally` callers can
/// release idempotently even if their route throws or the shell is disposed.
class WebsiteEditorContextualOperationController extends ChangeNotifier {
  int _depth = 0;
  bool _disposed = false;

  bool get isActive => _depth > 0;

  @visibleForTesting
  int get depth => _depth;

  WebsiteEditorContextualOperationLease acquire() {
    if (_disposed) {
      return WebsiteEditorContextualOperationLease._detached();
    }
    _depth += 1;
    if (_depth == 1) notifyListeners();
    return WebsiteEditorContextualOperationLease._(this);
  }

  void _release() {
    if (_depth == 0) return;
    _depth -= 1;
    if (_depth == 0 && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _depth = 0;
    super.dispose();
  }
}

class WebsiteEditorContextualOperationLease {
  WebsiteEditorContextualOperationLease._(this._owner);
  WebsiteEditorContextualOperationLease._detached() : _owner = null;

  WebsiteEditorContextualOperationController? _owner;

  bool get isReleased => _owner == null;

  void release() {
    final owner = _owner;
    if (owner == null) return;
    _owner = null;
    owner._release();
  }
}

/// One controller owned by [PersistentEditorShell] and shared across the
/// routed canvas, dock, root-overlay chrome and contextual routes.
class WebsiteEditorContextualOperationScope
    extends InheritedNotifier<WebsiteEditorContextualOperationController> {
  const WebsiteEditorContextualOperationScope({
    super.key,
    required WebsiteEditorContextualOperationController controller,
    required super.child,
  }) : super(notifier: controller);

  static WebsiteEditorContextualOperationController? maybeControllerOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<
            WebsiteEditorContextualOperationScope>()
        ?.notifier;
  }

  static bool isActiveOf(BuildContext context) =>
      maybeControllerOf(context)?.isActive ?? false;
}
