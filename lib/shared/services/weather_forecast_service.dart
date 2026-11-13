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

/// A place the person added to the weather tab, besides the shop.
@immutable
class WeatherSavedPlace {
  const WeatherSavedPlace({required this.id, required this.name, this.region});

  final String id;
  final String name;
  final String? region;
}

/// A place found by name, not yet added.
@immutable
class WeatherPlaceMatch {
  const WeatherPlaceMatch({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region,
  });

  final String name;
  final String? region;
  final double latitude;
  final double longitude;
}

/// What adding a place came to.
enum WeatherPlaceAdded { added, tooMany, failed }

/// Reads a forecast from the `weather-forecast` function; throws when the
/// server could not be reached or refused.
typedef WeatherFetcher = Future<Object?> Function();

/// Calls the `weather-forecast` function with [body]; throws when the server
/// could not be reached or refused.
typedef WeatherInvoker = Future<Object?> Function(Map<String, dynamic> body);

/// The weather of the signed-in shop and of the places that person added,
/// for the daily briefing.
///
/// A forecast belongs to a place, not to the device: the `weather-forecast`
/// Edge Function reads the shop's place from its settings and each person's
/// places from their list, and keeps the provider's last answer per place, so
/// every device shows the same one and the provider is asked once. Here each
/// is held for the session and asked again only when the server's own expiry
/// has passed, and only while someone looks: [ensureFresh] is called by the
/// surface that shows it.
class WeatherForecastService extends ChangeNotifier {
  WeatherForecastService({
    WeatherFetcher? fetcher,
    WeatherInvoker? invoke,
    String? Function()? currentUserId,
    DateTime Function()? clock,
  })  : _invoke =
            invoke ?? (fetcher == null ? _invokeFunction : (_) => fetcher()),
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

  final WeatherInvoker _invoke;
  final String? Function() _currentUserId;
  final DateTime Function() _clock;

  String? _ownerUserId;

  /// Null is the shop's own place.
  String? _selectedPlaceId;
  List<WeatherSavedPlace> _places = const [];
  String? _shopName;
  final Map<String, _PlaceState> _states = {};

  bool get _forCurrentUser => _ownerUserId == _currentUserId();

  _PlaceState? get _selected =>
      _forCurrentUser ? _states[_selectedPlaceId ?? ''] : null;

  /// The place on screen; null is the shop's own.
  String? get selectedPlaceId => _forCurrentUser ? _selectedPlaceId : null;

  /// The places this person added, in the order they added them.
  List<WeatherSavedPlace> get places => _forCurrentUser ? _places : const [];

  /// The shop's city, to name it in the list of places.
  String? get shopName => _forCurrentUser ? _shopName : null;

  /// The forecast in hand for the selected place, also while a newer one is
  /// being read or after a failed read: an hour-old forecast is still the
  /// forecast.
  WeatherSnapshot? get snapshot => _selected?.snapshot;

  /// The shop has no place on the map yet.
  bool get locationMissing => _selected?.locationMissing ?? false;

  /// The last read of the selected place failed.
  bool get failed => _selected?.failed ?? false;

  bool get loading => _selected?.inFlight != null;

  /// Shows another place; null is the shop's own.
  void select(String? placeId) {
    final userId = _currentUserId();
    if (userId == null) return;
    _adopt(userId);
    if (_selectedPlaceId == placeId) return;
    _selectedPlaceId = placeId;
    notifyListeners();
    unawaited(ensureFresh());
  }

  void _adopt(String userId) {
    if (_ownerUserId == userId) return;
    // Another account signed in: its shop and its places may be others.
    _ownerUserId = userId;
    _selectedPlaceId = null;
    _places = const [];
    _shopName = null;
    _states.clear();
  }

  /// Reads the selected place's forecast when there is none or the server's
  /// expiry has passed. [force] is the person asking again after a failure.
  Future<void> ensureFresh({bool force = false}) {
    final userId = _currentUserId();
    if (userId == null) return Future.value();
    _adopt(userId);
    final placeId = _selectedPlaceId;
    final state = _states.putIfAbsent(placeId ?? '', _PlaceState.new);
    final running = state.inFlight;
    if (running != null) return running;
    final now = _clock();
    if (!force) {
      final retryNotBefore = state.retryNotBefore;
      if (retryNotBefore != null && now.isBefore(retryNotBefore)) {
        return Future.value();
      }
      final snapshot = state.snapshot;
      if (snapshot != null && now.isBefore(snapshot.refreshAfter)) {
        return Future.value();
      }
    }
    final read = _read(userId, placeId, state);
    state.inFlight = read;
    notifyListeners();
    return read;
  }

  Future<void> _read(String userId, String? placeId, _PlaceState state) async {
    var gone = false;
    try {
      final answer = await _invoke({
        'action': 'forecast',
        if (placeId != null) 'place_id': placeId,
      });
      if (_ownerUserId != userId) return;
      gone = _apply(answer, state);
    } catch (error) {
      if (_ownerUserId != userId) return;
      debugPrint('[WeatherForecastService] read failed: $error');
      state.failed = true;
      state.retryNotBefore = _clock().add(retryAfterFailure);
    } finally {
      if (_ownerUserId == userId) {
        state.inFlight = null;
        if (gone && _selectedPlaceId == placeId) {
          // The place was removed on another device: back to the shop.
          _states.remove(placeId ?? '');
          _selectedPlaceId = null;
          unawaited(ensureFresh());
        }
        notifyListeners();
      }
    }
  }

  /// True when the server no longer knows the place that was asked for.
  bool _apply(Object? answer, _PlaceState state) {
    if (answer is! Map) throw const FormatException('weather: not an object');
    _readPlaces(answer);
    final status = answer['status']?.toString();
    if (status == 'place_missing') return true;
    if (status == 'location_missing') {
      state.snapshot = null;
      state.locationMissing = true;
      state.failed = false;
      // The place is set in another screen; an hour is soon enough to notice.
      state.retryNotBefore = _clock().add(const Duration(hours: 1));
      return false;
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
    state.snapshot = WeatherSnapshot(
      forecast: forecast,
      confirmedAt: (confirmedAt ?? now).toUtc(),
      refreshAfter: expiresAt == null || expiresAt.isBefore(earliest)
          ? earliest
          : expiresAt,
    );
    state.locationMissing = false;
    state.failed = false;
    state.retryNotBefore = null;
    return false;
  }

  /// Every answer of the function carries the person's places.
  void _readPlaces(Map<dynamic, dynamic> answer) {
    final shop = answer['shop_place'];
    if (shop is Map) {
      final name = shop['name']?.toString().trim() ?? '';
      _shopName = name.isEmpty ? null : name;
    }
    final raw = answer['places'];
    if (raw is! List) return;
    final places = <WeatherSavedPlace>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString() ?? '';
      final name = entry['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final region = entry['region']?.toString().trim() ?? '';
      places.add(
        WeatherSavedPlace(
          id: id,
          name: name,
          region: region.isEmpty ? null : region,
        ),
      );
    }
    _places = List.unmodifiable(places);
  }

  /// Towns and cities called [query]. Throws when the search could not be
  /// done.
  Future<List<WeatherPlaceMatch>> search(String query) async {
    final Object? answer;
    try {
      answer = await _invoke({'action': 'search', 'query': query.trim()});
    } catch (error) {
      debugPrint('[WeatherForecastService] search failed: $error');
      rethrow;
    }
    final raw = answer is Map ? answer['matches'] : null;
    if (answer is! Map || answer['status'] != 'ok' || raw is! List) {
      throw const FormatException('weather: search without matches');
    }
    final matches = <WeatherPlaceMatch>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString().trim() ?? '';
      final latitude = entry['latitude'];
      final longitude = entry['longitude'];
      if (name.isEmpty || latitude is! num || longitude is! num) continue;
      final region = entry['region']?.toString().trim() ?? '';
      matches.add(
        WeatherPlaceMatch(
          name: name,
          region: region.isEmpty ? null : region,
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
        ),
      );
    }
    return matches;
  }

  /// Adds [match] to the person's places and shows it.
  Future<WeatherPlaceAdded> addPlace(WeatherPlaceMatch match) async {
    final userId = _currentUserId();
    if (userId == null) return WeatherPlaceAdded.failed;
    _adopt(userId);
    try {
      final answer = await _invoke({
        'action': 'add_place',
        'name': match.name,
        'region': match.region,
        'latitude': match.latitude,
        'longitude': match.longitude,
      });
      if (_ownerUserId != userId || answer is! Map) {
        return WeatherPlaceAdded.failed;
      }
      _readPlaces(answer);
      if (answer['status'] == 'too_many_places') {
        notifyListeners();
        return WeatherPlaceAdded.tooMany;
      }
      final place = answer['place'];
      final id = place is Map ? place['id']?.toString() ?? '' : '';
      if (answer['status'] != 'ok' || id.isEmpty) {
        return WeatherPlaceAdded.failed;
      }
      _selectedPlaceId = id;
      notifyListeners();
      unawaited(ensureFresh());
      return WeatherPlaceAdded.added;
    } catch (error) {
      debugPrint('[WeatherForecastService] add place failed: $error');
      return WeatherPlaceAdded.failed;
    }
  }

  /// Takes a place off the person's list; the shop's own cannot be removed.
  /// False when the server could not be reached.
  Future<bool> removePlace(String placeId) async {
    final userId = _currentUserId();
    if (userId == null) return false;
    _adopt(userId);
    try {
      final answer = await _invoke({
        'action': 'remove_place',
        'place_id': placeId,
      });
      if (_ownerUserId != userId || answer is! Map) return false;
      if (answer['status'] != 'ok') return false;
      _readPlaces(answer);
      _states.remove(placeId);
      if (_selectedPlaceId == placeId) {
        _selectedPlaceId = null;
        unawaited(ensureFresh());
      }
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('[WeatherForecastService] remove place failed: $error');
      return false;
    }
  }

  static String? _sessionUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // No client yet: nobody is signed in.
      return null;
    }
  }

  static Future<Object?> _invokeFunction(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke(
      'weather-forecast',
      headers: kSupabaseFunctionsRegionHeaders,
      body: body,
    );
    if (response.status >= 300) {
      // «Too many places» is an answer the app explains, not a failure.
      if (response.status == 409 && response.data is Map) return response.data;
      throw StateError('weather-forecast answered ${response.status}');
    }
    return response.data;
  }
}

class _PlaceState {
  WeatherSnapshot? snapshot;
  bool locationMissing = false;
  bool failed = false;
  DateTime? retryNotBefore;
  Future<void>? inFlight;
}
