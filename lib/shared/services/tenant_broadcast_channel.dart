import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'realtime_health.dart';

/// Connection state of a tenant-private Broadcast topic.
enum TenantBroadcastStatus { subscribed, degraded, closed }

/// A listener on one private Broadcast topic fed by a database trigger through
/// `realtime.send(...)` and authorized once at join time by the
/// `realtime.messages` policies of migration `20260916010000`.
///
/// Several consumers may listen to the same topic (the desktop toast and the
/// chat inbox both follow `messaging:<tenant>`); the hub keeps one channel
/// per topic and removes it when the last listener cancels. This replaces
/// `postgres_changes` subscriptions for signals the database can emit
/// itself: a Broadcast row is never re-evaluated per WAL change by
/// `realtime.apply_rls`, which made `list_changes` the largest consumer of
/// database time on 2026-09-15.
class TenantBroadcastListener {
  TenantBroadcastListener._(this._entry, this.onEvent, this.onStatus);

  final _TopicEntry _entry;
  final ValueChanged<Map<String, dynamic>> onEvent;
  final void Function(TenantBroadcastStatus status, Object? error)? onStatus;
  bool _cancelled = false;

  String get topic => _entry.topic;
  bool get isCancelled => _cancelled;

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _entry.remove(this);
  }
}

class _TopicEntry {
  _TopicEntry(this.hub, this.client, this.topic);

  final TenantBroadcastHub hub;
  final SupabaseClient client;
  final String topic;
  final List<TenantBroadcastListener> listeners = [];
  RealtimeChannel? channel;
  TenantBroadcastStatus? lastStatus;
  Object? lastError;
  Timer? rejoinTimer;
  int rejoinAttempt = 0;
  DateTime? degradedSince;
  bool removed = false;

  /// Events and statuses reach listeners on a later turn of the event loop,
  /// never inside the SDK callback.
  ///
  /// **Por qué (2026-10-08).** Cuando el socket se cae, `RealtimeClient`
  /// recorre su lista de canales avisando el error. Un oyente que en ese
  /// mismo instante quitaba un canal (la bandeja caía a `postgres_changes`) o
  /// creaba otro modificaba esa lista durante el recorrido: el SDK lanzaba
  /// «Concurrent modification during iteration» ANTES de programar la
  /// reconexión y el socket quedaba muerto hasta cerrar la app. En el Mac del
  /// dueño fueron 3 201 reintentos fallidos seguidos y los mensajes nuevos
  /// sólo aparecían en el teléfono.
  void dispatch(Map<String, dynamic> payload) {
    Timer.run(() {
      for (final listener in List.of(listeners)) {
        if (listener.isCancelled) continue;
        try {
          listener.onEvent(payload);
        } catch (error) {
          debugPrint('⚠️ [TenantBroadcast] $topic listener failed: $error');
        }
      }
    });
  }

  void status(TenantBroadcastStatus status, Object? error) {
    lastStatus = status;
    lastError = error;
    Timer.run(() {
      for (final listener in List.of(listeners)) {
        if (listener.isCancelled) continue;
        listener.onStatus?.call(status, error);
      }
    });
  }

  Future<void> remove(TenantBroadcastListener listener) async {
    listeners.remove(listener);
    if (listeners.isNotEmpty) return;
    removed = true;
    rejoinTimer?.cancel();
    rejoinTimer = null;
    if (identical(hub._entries[topic], this)) hub._entries.remove(topic);
    final current = channel;
    channel = null;
    if (current != null) await client.removeChannel(current);
  }
}

class TenantBroadcastHub {
  TenantBroadcastHub._();

  static final TenantBroadcastHub instance = TenantBroadcastHub._();

  final Map<String, _TopicEntry> _entries = {};

  /// Backoff for a topic the server closed. A channel error or timeout is
  /// retried by the SDK itself; a `closed` channel is gone from the socket and
  /// only a new join brings it back.
  static const List<Duration> _rejoinDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  /// A topic that stays degraded this long is joined again from scratch.
  static const Duration _degradedRejoinAfter = Duration(seconds: 45);

  /// Joins [topic] (once per topic) and delivers every `changed` payload to
  /// [onEvent]. [onStatus] receives join success, transient degradation
  /// (channel error or timeout — the SDK and this hub retry on their own) and
  /// closure; a listener added after the join receives the last known status
  /// too. A `subscribed` that follows any other status means the topic came
  /// back after a gap: listeners re-read what they show, because Broadcast
  /// does not replay what was sent while they were away. The current session
  /// token is pushed to Realtime before a join so the topic policy can read
  /// `auth.uid()` and `user_tenant_id()`.
  Future<TenantBroadcastListener> listen({
    required SupabaseClient client,
    required String topic,
    required ValueChanged<Map<String, dynamic>> onEvent,
    void Function(TenantBroadcastStatus status, Object? error)? onStatus,
  }) async {
    RealtimeHealth.instance.attach(client);
    var entry = _entries[topic];
    final isNew = entry == null;
    entry ??= _entries[topic] = _TopicEntry(this, client, topic);
    final listener = TenantBroadcastListener._(entry, onEvent, onStatus);
    entry.listeners.add(listener);
    if (isNew) {
      await _join(entry);
    } else if (entry.lastStatus != null) {
      // Replayed on the event queue, once the caller holds the listener: a
      // synchronous replay reaches status callbacks that still refer to a
      // `late` handle (the desktop toast joins the messaging topic after the
      // chat inbox already did).
      final replayStatus = entry.lastStatus!;
      final replayError = entry.lastError;
      Future<void>(() {
        if (listener.isCancelled) return;
        listener.onStatus?.call(replayStatus, replayError);
      });
    }
    return listener;
  }

  Future<void> _join(_TopicEntry entry) async {
    if (entry.removed || entry.listeners.isEmpty) return;
    final client = entry.client;
    await client.realtime.setAuth(client.auth.currentSession?.accessToken);
    if (entry.removed || entry.listeners.isEmpty) return;
    final joined = client.channel(
      entry.topic,
      opts: const RealtimeChannelConfig(private: true),
    );
    entry.channel = joined;
    joined
        .onBroadcast(event: 'changed', callback: entry.dispatch)
        .subscribe((status, error) {
      // A callback of a channel this entry already replaced or removed must
      // not touch the current one.
      if (!identical(entry.channel, joined)) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          entry.rejoinAttempt = 0;
          entry.degradedSince = null;
          entry.rejoinTimer?.cancel();
          entry.rejoinTimer = null;
          entry.status(TenantBroadcastStatus.subscribed, null);
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          entry.degradedSince ??= DateTime.now();
          entry.status(TenantBroadcastStatus.degraded, error);
          if (DateTime.now().difference(entry.degradedSince!) >=
              _degradedRejoinAfter) {
            _scheduleRejoin(entry, reason: 'degraded for too long');
          }
        case RealtimeSubscribeStatus.closed:
          entry.status(TenantBroadcastStatus.closed, error);
          _scheduleRejoin(entry, reason: 'closed by the server');
      }
    });
  }

  void _scheduleRejoin(_TopicEntry entry, {required String reason}) {
    if (entry.removed || entry.listeners.isEmpty) return;
    if (entry.rejoinTimer?.isActive ?? false) return;
    final delay = _rejoinDelays[
        entry.rejoinAttempt.clamp(0, _rejoinDelays.length - 1).toInt()];
    entry.rejoinAttempt += 1;
    debugPrint(
      '🔁 [TenantBroadcast] ${entry.topic} joins again in '
      '${delay.inSeconds}s ($reason)',
    );
    entry.rejoinTimer = Timer(delay, () {
      entry.rejoinTimer = null;
      unawaited(_rejoin(entry));
    });
  }

  Future<void> _rejoin(_TopicEntry entry) async {
    if (entry.removed || entry.listeners.isEmpty) return;
    final previous = entry.channel;
    entry.channel = null;
    entry.degradedSince = null;
    if (previous != null) {
      try {
        await entry.client.removeChannel(previous);
      } catch (error) {
        debugPrint('⚠️ [TenantBroadcast] ${entry.topic} leave failed: $error');
      }
    }
    await _join(entry);
  }

  /// Joins every topic again. [RealtimeHealth] calls it after it revived a
  /// dead socket; a stale join would otherwise wait for the next error.
  Future<void> rejoinAll() async {
    for (final entry in List.of(_entries.values)) {
      entry.rejoinTimer?.cancel();
      entry.rejoinTimer = null;
      entry.rejoinAttempt = 0;
      await _rejoin(entry);
    }
  }

  /// Drops every topic regardless of its listeners. Owners cancel their own
  /// listeners on user change; this exists for test hygiene.
  @visibleForTesting
  Future<void> reset() async {
    final entries = List.of(_entries.values);
    _entries.clear();
    for (final entry in entries) {
      entry.removed = true;
      entry.rejoinTimer?.cancel();
      entry.listeners.clear();
      final current = entry.channel;
      entry.channel = null;
      if (current != null) await entry.client.removeChannel(current);
    }
  }

  @visibleForTesting
  int get openTopics => _entries.length;
}

/// Topic names are derived on the database side from committed rows; the
/// client only mirrors the same derivation.
String erpNotificationsTopic({
  required String tenantId,
  required String recipient,
}) =>
    'erp-notifications:$tenantId:$recipient';

String messagingTopic(String tenantId) => 'messaging:$tenantId';
