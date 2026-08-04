import '../../../shared/services/authority_scoped_cache.dart';

/// "Latest request wins" for the Gestión de Trabajos table.
///
/// The jobs table is reloaded from many real triggers — first build, app
/// resume, returning from a route, pull to refresh, realtime and service
/// notifications — and until now none of them owned the others. Two
/// consequences reached the operator:
///
/// * an older response could finish last and paint over a newer one, and
/// * an older load that had been superseded on purpose surfaced its internal
///   cancellation as a red banner: *"Error: ERP authority scope changed during
///   load"*.
///
/// [AuthorityScopeChangedException] is not a failure. It is the typed way
/// `AuthorityScopedLoad` says "this read belongs to an authority that is no
/// longer current, so it may not publish" — exactly the contract that keeps a
/// tenant's rows from landing in another tenant's table. The defect was never
/// that guard; it was a page-level `catch (e)` that predated it and turned an
/// internal cancellation into a user-facing error.
///
/// This coordinator is that missing owner, and nothing more. It holds no data,
/// performs no read and knows no repository: it hands out a monotonic ticket
/// and answers one question — *is this still the load allowed to speak?*
///
/// It deliberately does NOT retry, and it never relaxes the authority scope.
/// A superseded load is dropped; the load that superseded it is already
/// running with the current authority.
class WorkshopJobsLoadCoordinator {
  int _generation = 0;
  bool _disposed = false;

  /// Whether a ticket handed out earlier is still the current one.
  bool get hasCurrentLoad => !_disposed && _generation > 0;

  /// Begins a load and supersedes every ticket handed out before it.
  WorkshopJobsLoadTicket start() {
    _generation++;
    return WorkshopJobsLoadTicket._(this, _generation);
  }

  /// Invalidates every live ticket. Called from `State.dispose`: a response
  /// that arrives after the page is gone owns nothing.
  void dispose() {
    _disposed = true;
    _generation++;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  /// Whether [error] is the typed "this load was superseded" result rather
  /// than a real failure.
  ///
  /// One place decides it, so the page cannot drift into showing the internal
  /// sentence again.
  static bool isSupersededError(Object error) =>
      error is AuthorityScopeChangedException;
}

/// One load's permission to publish. Obtained from
/// [WorkshopJobsLoadCoordinator.start] and checked after every await.
class WorkshopJobsLoadTicket {
  WorkshopJobsLoadTicket._(this._coordinator, this._generation);

  final WorkshopJobsLoadCoordinator _coordinator;
  final int _generation;

  /// Whether this load may still write state or surface an error.
  bool get isCurrent => _coordinator._isCurrent(_generation);

  /// The inverse, for the guard clauses that read better as an early return.
  bool get isSuperseded => !isCurrent;
}
