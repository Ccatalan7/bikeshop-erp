import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/weather_forecast.dart';
import 'supabase_functions_region.dart';

/// A forecast and what the server said about its age.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.forecast,
    required this.confirmedAt,
    required this.refreshAfter,
  });

  final WeatherForecast forecast;

  /// Last time the provider confirmed this forecast.
  final DateTime confirmedAt;

  /// The server keeps answering the same forecast until then.
  final DateTime refreshAfter;
}

/// Reads the answer of the `weather-forecast` function; throws when the
/// server could not be reached or refused.
typedef WeatherFetcher = Future<Object?> Function();

/// The weather of the signed-in shop, for the daily briefing.
///
/// The forecast is the shop's, not the device's: the `weather-forecast` Edge
/// Function reads the place from the shop's settings and keeps the
/// provider's last answer, so every device shows the same one and the
/// provider is asked once. Here it is held for the session and asked again
/// only when the server's own expiry has passed, and only while someone
/// looks: [ensureFresh] is called by the surface that shows it.
class WeatherForecastService extends ChangeNotifier {
  WeatherForecastService({
    WeatherFetcher? fetcher,
    String? Function()? currentUserId,
    DateTime Function()? clock,
  })  : _fetcher = fetcher ?? _invokeFunction,
        _currentUserId = currentUserId ?? _sessionUserId,
        _clock = clock ?? DateTime.now;

  static WeatherForecastService _instance = WeatherForecastService();

  static WeatherForecastService get instance => _instance;

  /// Replaces the shared service in a test and returns the previous one.
  @visibleForTesting
  static WeatherForecastService debugReplaceInstance(
    WeatherForecastService replacement,
  ) {
    final previous = _instance;
    _instance = replacement;
    return previous;
  }

  /// After a failed read the server is left alone for this long, unless the
  /// person asks again.
  static const Duration retryAfterFailure = Duration(minutes: 5);

  final WeatherFetcher _fetcher;
  final String? Function() _currentUserId;
  final DateTime Function() _clock;

  WeatherSnapshot? _snapshot;
  String? _ownerUserId;
  bool _locationMissing = false;
  bool _failed = false;
  DateTime? _retryNotBefore;
  Future<void>? _inFlight;

  /// The forecast in hand, also while a newer one is being read or after a
  /// failed read: an hour-old forecast is still the forecast.
  WeatherSnapshot? get snapshot => _forCurrentUser ? _snapshot : null;

  /// The shop has no place on the map yet.
  bool get locationMissing => _forCurrentUser && _locationMissing;

  /// The last read failed.
  bool get failed => _forCurrentUser && _failed;

  bool get loading => _inFlight != null;

  bool get _forCurrentUser => _ownerUserId == _currentUserId();

  /// Reads the forecast when there is none or the server's expiry has
  /// passed. [force] is the person asking again after a failure.
  Future<void> ensureFresh({bool force = false}) {
    final userId = _currentUserId();
    if (userId == null) return Future.value();
    if (_ownerUserId != userId) {
      // Another account signed in: its shop may be another shop.
      _ownerUserId = userId;
      _snapshot = null;
      _locationMissing = false;
      _failed = false;
      _retryNotBefore = null;
      _inFlight = null;
    }
    final running = _inFlight;
    if (running != null) return running;
    final now = _clock();
    if (!force) {
      final retryNotBefore = _retryNotBefore;
      if (retryNotBefore != null && now.isBefore(retryNotBefore)) {
        return Future.value();
      }
      final snapshot = _snapshot;
      if (snapshot != null && now.isBefore(snapshot.refreshAfter)) {
        return Future.value();
      }
    }
    final read = _read(userId);
    _inFlight = read;
    notifyListeners();
    return read;
  }

  Future<void> _read(String userId) async {
    try {
      final answer = await _fetcher();
      if (_ownerUserId != userId) return;
      _apply(answer);
    } catch (error) {
      if (_ownerUserId != userId) return;
      debugPrint('[WeatherForecastService] read failed: $error');
      _failed = true;
      _retryNotBefore = _clock().add(retryAfterFailure);
    } finally {
      if (_ownerUserId == userId) {
        _inFlight = null;
        notifyListeners();
      }
    }
  }

  void _apply(Object? answer) {
    if (answer is! Map) throw const FormatException('weather: not an object');
    final status = answer['status']?.toString();
    if (status == 'location_missing') {
      _snapshot = null;
      _locationMissing = true;
      _failed = false;
      // The place is set in another screen; an hour is soon enough to notice.
      _retryNotBefore = _clock().add(const Duration(hours: 1));
      return;
    }
    final source = answer['source'];
    if (status != 'ok' || source is! Map) {
      throw FormatException('weather: unexpected answer ($status)');
    }
    final forecast = WeatherForecast.tryParse(answer);
    if (forecast == null) {
      throw const FormatException('weather: answer without a series');
    }
    final now = _clock();
    final confirmedAt = DateTime.tryParse(
      source['checked_at']?.toString() ?? '',
    );
    final expiresAt = DateTime.tryParse(source['expires_at']?.toString() ?? '');
    // Never sooner than a minute: a server clock ahead of this one must not
    // turn every tick into a request.
    final earliest = now.add(const Duration(minutes: 1));
    _snapshot = WeatherSnapshot(
      forecast: forecast,
      confirmedAt: (confirmedAt ?? now).toUtc(),
      refreshAfter: expiresAt == null || expiresAt.isBefore(earliest)
          ? earliest
          : expiresAt,
    );
    _locationMissing = false;
    _failed = false;
    _retryNotBefore = null;
  }

  static String? _sessionUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // No client yet: nobody is signed in.
      return null;
    }
  }

  static Future<Object?> _invokeFunction() async {
    final response = await Supabase.instance.client.functions.invoke(
      'weather-forecast',
      headers: kSupabaseFunctionsRegionHeaders,
      body: const <String, dynamic>{},
    );
    if (response.status >= 300) {
      throw StateError('weather-forecast answered ${response.status}');
    }
    return response.data;
  }
}
