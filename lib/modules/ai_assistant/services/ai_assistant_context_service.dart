import 'package:flutter/foundation.dart';

import '../../bikeshop/models/bikeshop_models.dart';

String _debugJobNumbers(List<MechanicJob> jobs) {
  final numbers = jobs
      .take(12)
      .map((job) => job.jobNumber ?? job.id ?? 'sin-numero')
      .join(', ');
  if (jobs.length <= 12) {
    return numbers;
  }
  return '$numbers, ... +${jobs.length - 12}';
}

/// Current app context that the global AI assistant should answer from.
///
/// The right toolbar lives outside individual module pages, so pages can publish
/// the records currently visible to the user here before opening the assistant.
class AIAssistantContextService extends ChangeNotifier {
  List<MechanicJob> _visibleJobs = const [];
  bool _hasVisibleJobsContext = false;
  String? _visibleJobsScopeLabel;
  DateTime? _updatedAt;

  AIAssistantContextService() {
    debugPrint(
      '[AI_CTX][ContextService.init] created id=${identityHashCode(this)}',
    );
  }

  List<MechanicJob> get visibleJobs => _visibleJobs;
  bool get hasVisibleJobsContext => _hasVisibleJobsContext;
  String? get visibleJobsScopeLabel => _visibleJobsScopeLabel;
  DateTime? get updatedAt => _updatedAt;

  void setVisibleJobsContext({
    required List<MechanicJob> jobs,
    required String scopeLabel,
  }) {
    debugPrint(
      '[AI_CTX][ContextService.set] id=${identityHashCode(this)} '
      'count=${jobs.length} scope="$scopeLabel" '
      'jobs=[${_debugJobNumbers(jobs)}]',
    );
    _visibleJobs = List<MechanicJob>.unmodifiable(jobs);
    _visibleJobsScopeLabel = scopeLabel;
    _hasVisibleJobsContext = true;
    _updatedAt = DateTime.now();
    notifyListeners();
  }

  void clearVisibleJobsContext() {
    if (!_hasVisibleJobsContext && _visibleJobs.isEmpty) {
      return;
    }

    debugPrint(
      '[AI_CTX][ContextService.clear] id=${identityHashCode(this)} '
      'previousCount=${_visibleJobs.length} '
      'previousScope="$_visibleJobsScopeLabel" '
      'jobs=[${_debugJobNumbers(_visibleJobs)}]',
    );
    _visibleJobs = const [];
    _visibleJobsScopeLabel = null;
    _hasVisibleJobsContext = false;
    _updatedAt = DateTime.now();
    notifyListeners();
  }
}
