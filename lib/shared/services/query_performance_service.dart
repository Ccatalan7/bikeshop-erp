import 'dart:collection';

import 'package:flutter/foundation.dart';

const bool kShowQueryPerformanceGauge =
    kDebugMode || bool.fromEnvironment('ERP_PERF_GAUGE');

class QueryPerformanceEvent {
  const QueryPerformanceEvent({
    required this.label,
    required this.operation,
    required this.rowCount,
    required this.estimatedBytes,
    required this.durationMs,
    required this.timestamp,
  });

  final String label;
  final String operation;
  final int rowCount;
  final int estimatedBytes;
  final int durationMs;
  final DateTime timestamp;

  double get estimatedMb => estimatedBytes / (1024 * 1024);
}

class QueryPerformanceTableSummary {
  const QueryPerformanceTableSummary({
    required this.label,
    required this.readCount,
    required this.rowCount,
    required this.estimatedBytes,
    required this.totalDurationMs,
  });

  final String label;
  final int readCount;
  final int rowCount;
  final int estimatedBytes;
  final int totalDurationMs;

  double get estimatedMb => estimatedBytes / (1024 * 1024);
  double get averageDurationMs =>
      readCount == 0 ? 0 : totalDurationMs / readCount;
}

class QueryPerformanceService extends ChangeNotifier {
  QueryPerformanceService._();

  static final QueryPerformanceService instance = QueryPerformanceService._();

  static bool get isEnabled => kShowQueryPerformanceGauge;

  static const int _maxEvents = 120;

  final List<QueryPerformanceEvent> _events = [];
  DateTime _sessionStartedAt = DateTime.now();
  int _totalEstimatedBytes = 0;
  int _totalDurationMs = 0;
  int _totalRows = 0;
  int _readCount = 0;

  UnmodifiableListView<QueryPerformanceEvent> get recentEvents =>
      UnmodifiableListView(_events.reversed.toList(growable: false));

  DateTime get sessionStartedAt => _sessionStartedAt;
  int get totalEstimatedBytes => _totalEstimatedBytes;
  int get totalDurationMs => _totalDurationMs;
  int get totalRows => _totalRows;
  int get readCount => _readCount;
  double get totalEstimatedMb => totalEstimatedBytes / (1024 * 1024);
  double get averageDurationMs =>
      _readCount == 0 ? 0 : _totalDurationMs / _readCount;
  QueryPerformanceEvent? get lastEvent => _events.isEmpty ? null : _events.last;

  Duration get sessionAge => DateTime.now().difference(_sessionStartedAt);

  void recordRead({
    required String label,
    required String operation,
    required int rowCount,
    required int estimatedBytes,
    required int durationMs,
  }) {
    if (!isEnabled) return;

    final event = QueryPerformanceEvent(
      label: label,
      operation: operation,
      rowCount: rowCount,
      estimatedBytes: estimatedBytes,
      durationMs: durationMs,
      timestamp: DateTime.now(),
    );

    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeAt(0);
    }

    _totalEstimatedBytes += estimatedBytes;
    _totalDurationMs += durationMs;
    _totalRows += rowCount;
    _readCount += 1;
    notifyListeners();
  }

  void reset() {
    _events.clear();
    _sessionStartedAt = DateTime.now();
    _totalEstimatedBytes = 0;
    _totalDurationMs = 0;
    _totalRows = 0;
    _readCount = 0;
    notifyListeners();
  }

  List<QueryPerformanceTableSummary> get topTablesByBytes {
    final aggregates = <String, _MutableTableSummary>{};
    for (final event in _events) {
      final entry = aggregates.putIfAbsent(
        event.label,
        () => _MutableTableSummary(label: event.label),
      );
      entry.readCount += 1;
      entry.rowCount += event.rowCount;
      entry.estimatedBytes += event.estimatedBytes;
      entry.totalDurationMs += event.durationMs;
    }

    return aggregates.values
        .map(
          (entry) => QueryPerformanceTableSummary(
            label: entry.label,
            readCount: entry.readCount,
            rowCount: entry.rowCount,
            estimatedBytes: entry.estimatedBytes,
            totalDurationMs: entry.totalDurationMs,
          ),
        )
        .toList()
      ..sort((a, b) => b.estimatedBytes.compareTo(a.estimatedBytes));
  }

  String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

class _MutableTableSummary {
  _MutableTableSummary({required this.label});

  final String label;
  int readCount = 0;
  int rowCount = 0;
  int estimatedBytes = 0;
  int totalDurationMs = 0;
}
