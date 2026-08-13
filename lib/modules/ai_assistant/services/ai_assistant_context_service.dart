import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../bikeshop/models/bikeshop_models.dart';

/// Current app context that the global AI assistant should answer from.
///
/// The right toolbar lives outside individual module pages, so pages can publish
/// the records currently visible to the user here before opening the assistant.
class AIAssistantContextService extends ChangeNotifier {
  List<MechanicJob> _visibleJobs = const [];
  bool _hasVisibleJobsContext = false;
  String? _visibleJobsScopeLabel;
  DateTime? _updatedAt;
  Object? _visibleJobsOwner;
  bool _isDisposed = false;

  AIAssistantContextService() {
    if (kDebugMode) debugPrint('[AI_CTX] Context service created.');
  }

  List<MechanicJob> get visibleJobs => _visibleJobs;
  bool get hasVisibleJobsContext => _hasVisibleJobsContext;
  String? get visibleJobsScopeLabel => _visibleJobsScopeLabel;
  DateTime? get updatedAt => _updatedAt;

  void setVisibleJobsContext({
    required Object owner,
    required List<MechanicJob> jobs,
    required String scopeLabel,
  }) {
    if (kDebugMode) {
      debugPrint('[AI_CTX] Visible jobs context updated.');
    }
    _visibleJobs = List<MechanicJob>.unmodifiable(jobs);
    _visibleJobsScopeLabel = scopeLabel;
    _hasVisibleJobsContext = true;
    _updatedAt = DateTime.now();
    _visibleJobsOwner = owner;
    notifyListeners();
  }

  void clearVisibleJobsContext({required Object owner}) {
    if (!identical(_visibleJobsOwner, owner)) {
      return;
    }
    if (!_hasVisibleJobsContext && _visibleJobs.isEmpty) {
      return;
    }

    if (kDebugMode) debugPrint('[AI_CTX] Visible jobs context cleared.');
    _visibleJobs = const [];
    _visibleJobsScopeLabel = null;
    _hasVisibleJobsContext = false;
    _updatedAt = DateTime.now();
    _visibleJobsOwner = null;
    notifyListeners();
  }

  /// Clears page-owned context after Flutter finishes unmounting the frame.
  ///
  /// A [ChangeNotifier] must not notify its provider dependents synchronously
  /// from a descendant's `dispose`: the element tree is locked during that
  /// phase. Ownership also prevents a departing page from clearing context
  /// that a newer page published before this callback runs.
  void clearVisibleJobsContextAfterFrame({required Object owner}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      clearVisibleJobsContext(owner: owner);
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
