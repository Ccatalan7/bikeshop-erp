import 'dart:async';
import 'dart:collection';

/// How many reads this server has at the database at once. The rest wait
/// their turn here, where waiting costs nothing, instead of inside Postgres.
///
/// The store's database is a small Supabase instance on shared CPU, which
/// does a catalog page's reads in ~0.15 s. Twelve pages at once (a crawler,
/// 2026-10-06 and 2026-10-07) put some eighty queries on it together; each
/// took ten times longer, and the ones past `anon`'s 3 s statement timeout
/// were cancelled and their pages answered 503. Taken a few at a time the
/// same reads stay fast, so every page arrives, only the last ones a little
/// later.
class DatabaseGate {
  DatabaseGate({this.limit = 4, this.maxWait = const Duration(seconds: 10)})
    : assert(limit > 0);

  /// Reads at the database at once. Four leaves a single visitor's page
  /// unhindered: its widest moment is the facets read still running while
  /// the listing's three completions go out.
  final int limit;

  /// A read that has waited this long gives up rather than holding its
  /// visitor longer: past it the server is overloaded, and an honest «try
  /// again» (503 with `retry-after`) beats a page that never comes.
  final Duration maxWait;

  var _running = 0;
  final _waiting = Queue<Completer<void>>();

  /// Reads at the database right now; for tests.
  int get running => _running;

  /// Runs [read] when a place is free, keeping it until [read] completes.
  Future<T> run<T>(Future<T> Function() read) async {
    if (_running < limit) {
      _running++;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      try {
        await turn.future.timeout(maxWait);
      } on TimeoutException {
        // Handed a place in the same instant it gave up: pass it on.
        if (!_waiting.remove(turn)) _release();
        throw const DatabaseBusy();
      }
    }
    try {
      return await read();
    } finally {
      _release();
    }
  }

  /// The next in line takes the place over; with nobody waiting it is free.
  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }
}

/// A read that waited [DatabaseGate.maxWait] for its turn and gave up.
class DatabaseBusy implements Exception {
  const DatabaseBusy();

  @override
  String toString() => 'DatabaseBusy: no turn at the database in time';
}
