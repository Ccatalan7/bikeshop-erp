import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/services/tenant_service.dart';
import 'presence_models.dart';
import 'presence_service.dart';

/// What the chart draws.
enum PresenceMetric {
  clicks('Clics'),
  impressions('Vistas'),
  position('Posición'),
  visits('Visitas desde Google');

  const PresenceMetric(this.label);

  final String label;
}

/// A channel's visits in the period next to the period before.
class ChannelTotals {
  const ChannelTotals({
    required this.channel,
    required this.sessions,
    required this.previousSessions,
    required this.engagedSessions,
    required this.keyEvents,
  });

  final String channel;
  final int sessions;
  final int previousSessions;
  final int engagedSessions;
  final double keyEvents;

  double? get engagement => sessions == 0 ? null : engagedSessions / sessions;
}

/// The whole «Presencia en internet» page reads one controller: the period
/// and the scope change every block at once.
class PresenceController extends ChangeNotifier {
  PresenceController({PresenceService? service, TenantService? tenantService})
      : _service = service ?? PresenceService(),
        _tenantService = tenantService ?? TenantService();

  final PresenceService _service;
  final TenantService _tenantService;

  String? _tenantId;
  PresencePeriod _period = PresencePeriod.month;
  PresenceScope _scope = PresenceScope.chile;
  PresenceMetric _metric = PresenceMetric.clicks;
  List<SearchDay> _searchDays = const [];
  List<IndexDay> _indexDays = const [];
  List<TrafficRow> _traffic = const [];
  List<EventRow> _events = const [];
  List<PresenceTerm> _queries = const [];
  List<PresenceTerm> _pages = const [];
  List<PresenceNote> _notes = const [];
  List<PresenceRun> _runs = const [];
  PresenceSettings _settings = const PresenceSettings();
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  String? _refreshMessage;
  int _generation = 0;
  bool _disposed = false;

  String? get tenantId => _tenantId;
  PresencePeriod get period => _period;
  PresenceScope get scope => _scope;
  PresenceMetric get metric => _metric;
  List<SearchDay> get searchDays => _searchDays;
  List<IndexDay> get indexDays => _indexDays;
  List<PresenceTerm> get queries => _queries;
  List<PresenceTerm> get pages => _pages;
  List<PresenceNote> get notes => _notes;
  List<PresenceRun> get runs => _runs;
  PresenceSettings get settings => _settings;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  String? get error => _error;
  String? get refreshMessage => _refreshMessage;
  bool get hasData => _searchDays.isNotEmpty;

  /// Search Console publishes with two or three days of delay: the period
  /// ends on the last day it has, so both halves of a comparison are whole.
  DateTime? get searchEnd => _searchDays.isEmpty ? null : _searchDays.last.day;

  DateTime? get trafficEnd {
    DateTime? last;
    for (final row in _traffic) {
      if (last == null || row.day.isAfter(last)) last = row.day;
    }
    return last;
  }

  ({DateTime from, DateTime to})? _range(DateTime? end, {int back = 0}) {
    if (end == null) return null;
    final to = end.subtract(Duration(days: _period.days * back));
    return (from: to.subtract(Duration(days: _period.days - 1)), to: to);
  }

  ({DateTime from, DateTime to})? get currentRange => _range(searchEnd);
  ({DateTime from, DateTime to})? get previousRange =>
      _range(searchEnd, back: 1);

  static bool _within(DateTime day, ({DateTime from, DateTime to})? range) =>
      range != null && !day.isBefore(range.from) && !day.isAfter(range.to);

  List<SearchDay> get currentDays => [
        for (final day in _searchDays)
          if (_within(day.day, currentRange)) day
      ];

  SearchTotals get current => SearchTotals.of(currentDays);
  SearchTotals get previous => SearchTotals.of([
        for (final day in _searchDays)
          if (_within(day.day, previousRange)) day
      ]);

  /// The newest indexation photo, and the one closest to the period start.
  IndexDay? get latestIndex => _indexDays.isEmpty ? null : _indexDays.last;
  IndexDay? get indexAtStart {
    final range = currentRange;
    if (range == null || _indexDays.isEmpty) return null;
    IndexDay? found;
    for (final day in _indexDays) {
      if (day.day.isAfter(range.from)) break;
      found = day;
    }
    return found;
  }

  ({DateTime from, DateTime to})? get trafficRange => _range(trafficEnd);
  ({DateTime from, DateTime to})? get trafficPreviousRange =>
      _range(trafficEnd, back: 1);

  bool get hasTraffic => _traffic.isNotEmpty;

  List<ChannelTotals> get channels {
    final current = trafficRange;
    final previous = trafficPreviousRange;
    final byChannel = <String, List<num>>{};
    for (final row in _traffic) {
      final totals = byChannel.putIfAbsent(row.channel, () => [0, 0, 0, 0]);
      if (_within(row.day, current)) {
        totals[0] += row.sessions;
        totals[2] += row.engagedSessions;
        totals[3] += row.keyEvents;
      } else if (_within(row.day, previous)) {
        totals[1] += row.sessions;
      }
    }
    final list = [
      for (final entry in byChannel.entries)
        ChannelTotals(
          channel: entry.key,
          sessions: entry.value[0].toInt(),
          previousSessions: entry.value[1].toInt(),
          engagedSessions: entry.value[2].toInt(),
          keyEvents: entry.value[3].toDouble(),
        ),
    ]..removeWhere((c) => c.sessions == 0 && c.previousSessions == 0);
    list.sort((a, b) => b.sessions.compareTo(a.sessions));
    return list;
  }

  ChannelTotals? get organic {
    for (final channel in channels) {
      if (channel.channel == 'Organic Search') return channel;
    }
    return null;
  }

  /// Funnel counts of the period and the one before, by event name.
  Map<String, (int, int)> get funnel {
    final current = trafficRange;
    final previous = trafficPreviousRange;
    final totals = <String, (int, int)>{};
    for (final row in _events) {
      final (now, before) = totals[row.name] ?? (0, 0);
      if (_within(row.day, current)) {
        totals[row.name] = (now + row.count, before);
      } else if (_within(row.day, previous)) {
        totals[row.name] = (now, before + row.count);
      }
    }
    return totals;
  }

  /// One value per day of the period for the chart; null where there is
  /// nothing to draw (no impressions for the position, no Analytics).
  List<(DateTime, double?)> get series => seriesFor(_metric);

  List<(DateTime, double?)> seriesFor(PresenceMetric metric) {
    final range = currentRange;
    if (range == null) return const [];
    if (metric == PresenceMetric.visits) {
      final byDay = <DateTime, int>{};
      for (final row in _traffic) {
        if (row.channel == 'Organic Search') {
          byDay[row.day] = (byDay[row.day] ?? 0) + row.sessions;
        }
      }
      return [
        for (var d = range.from;
            !d.isAfter(range.to);
            d = d.add(const Duration(days: 1)))
          (d, _traffic.isEmpty ? null : (byDay[d] ?? 0).toDouble()),
      ];
    }
    final byDay = {for (final day in _searchDays) day.day: day};
    return [
      for (var d = range.from;
          !d.isAfter(range.to);
          d = d.add(const Duration(days: 1)))
        (
          d,
          switch (metric) {
            PresenceMetric.clicks => (byDay[d]?.clicks ?? 0).toDouble(),
            PresenceMetric.impressions =>
              (byDay[d]?.impressions ?? 0).toDouble(),
            PresenceMetric.position => byDay[d]?.position,
            PresenceMetric.visits => null,
          },
        ),
    ];
  }

  /// What we changed and what each analysis concluded, inside the period.
  List<PresenceNote> get periodNotes {
    final range = currentRange;
    if (range == null) return const [];
    final end = DateTime.now();
    return [
      for (final note in _notes)
        if (!note.day.isBefore(range.from) && !note.day.isAfter(end)) note,
    ];
  }

  PresenceRun? get lastCollect {
    for (final run in _runs) {
      if (run.task == 'collect') return run;
    }
    return null;
  }

  PresenceRun? get lastFinished {
    for (final run in _runs) {
      if (run.status != PresenceRunStatus.running) return run;
    }
    return null;
  }

  /// The store's own host: from the Search Console property when it is
  /// set, otherwise the host most of its https pages carry.
  String? get storeHost {
    final site = _settings.gscSite;
    if (site != null && site.startsWith('sc-domain:')) {
      return site.substring('sc-domain:'.length);
    }
    final counts = <String, int>{};
    for (final page in _pages) {
      final uri = Uri.tryParse(page.term);
      if (uri != null && uri.scheme == 'https') {
        counts[uri.host] = (counts[uri.host] ?? 0) + page.impressions + 1;
      }
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  /// What the last collection said about Analytics.
  Map<String, dynamic>? get analyticsState {
    for (final run in _runs) {
      if (run.task == 'collect' && run.traffic != null) return run.traffic;
    }
    return null;
  }

  bool get analyticsNoAccess => analyticsState?['noAccess'] == true;

  void setPeriod(PresencePeriod value) {
    if (value == _period) return;
    _period = value;
    notifyListeners();
    unawaited(_loadTerms());
  }

  void setMetric(PresenceMetric value) {
    if (value == _metric) return;
    _metric = value;
    notifyListeners();
  }

  void setScope(PresenceScope value) {
    if (value == _scope) return;
    _scope = value;
    notifyListeners();
    unawaited(_loadTraffic());
  }

  /// One read with a limit and one more try: in the debug app a request
  /// sometimes never answered or came back «Project not specified» (400)
  /// from the gateway (2026-10-14), and a page must not spin forever.
  static Future<T> _read<T>(Future<T> Function() run) async {
    try {
      return await run().timeout(const Duration(seconds: 15));
    } catch (_) {
      return run().timeout(const Duration(seconds: 20));
    }
  }

  Future<void> load() async {
    final generation = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final tenantId = _tenantId ?? await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('No se encontró la tienda de esta cuenta.');
      }
      _tenantId = tenantId;
      final results = await Future.wait<Object>([
        _read(() => _service.searchDays(tenantId)),
        _read(() => _service.indexDays(tenantId)),
        _read(() => _service.notes(tenantId)),
        _read(() => _service.runs(tenantId)),
        _read(() => _service.settings(tenantId)),
      ]);
      if (generation != _generation || _disposed) return;
      // Oldest first whatever order the read returned: the period ends on
      // the last day (a descending read once showed July 2025 as «now»).
      _searchDays = [...results[0] as List<SearchDay>]
        ..sort((a, b) => a.day.compareTo(b.day));
      _indexDays = [...results[1] as List<IndexDay>]
        ..sort((a, b) => a.day.compareTo(b.day));
      _notes = results[2] as List<PresenceNote>;
      _runs = results[3] as List<PresenceRun>;
      _settings = results[4] as PresenceSettings;
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _error = '$error';
    }
    if (generation != _generation || _disposed) return;
    _loading = false;
    notifyListeners();
    // Queries, pages and visits load on their own: one slow read leaves its
    // block waiting, not the page.
    unawaited(_loadTerms());
    unawaited(_loadTraffic());
  }

  bool _termsLoading = false;
  bool _trafficLoading = false;
  String? _termsError;
  String? _trafficError;

  bool get termsLoading => _termsLoading;
  bool get trafficLoading => _trafficLoading;
  String? get termsError => _termsError;
  String? get trafficError => _trafficError;

  Future<void> _loadTerms() async {
    final tenantId = _tenantId;
    final range = currentRange;
    if (tenantId == null || range == null) return;
    final period = _period;
    _termsLoading = true;
    _termsError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _read(() => _service.terms(tenantId,
            kind: 'query', from: range.from, to: range.to)),
        _read(() => _service.terms(tenantId,
            kind: 'page', from: range.from, to: range.to)),
      ]);
      if (_disposed || period != _period) return;
      _queries = results[0];
      _pages = results[1];
    } catch (error) {
      if (_disposed || period != _period) return;
      _termsError = '$error';
    }
    _termsLoading = false;
    notifyListeners();
  }

  Future<void> _loadTraffic() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    final scope = _scope;
    _trafficLoading = true;
    _trafficError = null;
    notifyListeners();
    // Two of the longest periods, so any choice has its comparison.
    final from = DateTime.now()
        .subtract(Duration(days: PresencePeriod.year.days * 2 + 7));
    try {
      final results = await Future.wait<Object>([
        _read(() => _service.traffic(tenantId, scope, from)),
        _read(() => _service.events(tenantId, scope, from)),
      ]);
      if (_disposed || scope != _scope) return;
      _traffic = results[0] as List<TrafficRow>;
      _events = results[1] as List<EventRow>;
    } catch (error) {
      if (_disposed || scope != _scope) return;
      _trafficError = '$error';
    }
    _trafficLoading = false;
    notifyListeners();
  }

  void retryTerms() => unawaited(_loadTerms());
  void retryTraffic() => unawaited(_loadTraffic());

  Future<List<PresenceUrl>> urlsInState(String state) async {
    final tenantId = _tenantId;
    if (tenantId == null) return const [];
    return _service.urlsInState(tenantId, state);
  }

  Future<void> saveAnalyticsProperty(String? propertyId) async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    await _service.saveAnalyticsProperty(tenantId, propertyId);
    _settings = await _service.settings(tenantId);
    notifyListeners();
  }

  /// Runs the collector now and waits (up to three minutes) for its row.
  Future<void> refresh() async {
    final tenantId = _tenantId;
    if (tenantId == null || _refreshing) return;
    _refreshing = true;
    _refreshMessage = 'Pidiendo las cifras a Google…';
    notifyListeners();
    final askedAt = DateTime.now().subtract(const Duration(seconds: 5));
    try {
      await _service.collectNow(tenantId);
      PresenceRun? run;
      for (var i = 0; i < 36 && !_disposed; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final runs = await _service.runs(tenantId, limit: 3);
        run = runs
            .where((r) => r.task == 'collect' && r.startedAt.isAfter(askedAt))
            .firstOrNull;
        if (run != null && run.status != PresenceRunStatus.running) break;
      }
      if (_disposed) return;
      _refreshMessage = switch (run?.status) {
        PresenceRunStatus.ok => 'Cifras al día.',
        PresenceRunStatus.partial =>
          'Cifras al día, con avisos: revisa el estado.',
        PresenceRunStatus.error =>
          'Google no respondió: ${run!.errors.firstOrNull ?? 'sin detalle'}',
        _ => 'Sigue trabajando en segundo plano; vuelve en unos minutos.',
      };
    } catch (error) {
      _refreshMessage = 'No se pudo pedir la actualización: $error';
    }
    _refreshing = false;
    if (_disposed) return;
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
