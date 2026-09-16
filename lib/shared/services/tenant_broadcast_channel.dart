import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  void dispatch(Map<String, dynamic> payload) {
    for (final listener in List.of(listeners)) {
      if (listener.isCancelled) continue;
      try {
        listener.onEvent(payload);
      } catch (error) {
        debugPrint('⚠️ [TenantBroadcast] $topic listener failed: $error');
      }
    }
  }

  void status(TenantBroadcastStatus status, Object? error) {
    lastStatus = status;
    lastError = error;
    for (final listener in List.of(listeners)) {
      if (listener.isCancelled) continue;
      listener.onStatus?.call(status, error);
    }
  }

  Future<void> remove(TenantBroadcastListener listener) async {
    listeners.remove(listener);
    if (listeners.isNotEmpty) return;
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

  /// Joins [topic] (once per topic) and delivers every `changed` payload to
  /// [onEvent]. [onStatus] receives join success, transient degradation
  /// (channel error or timeout — the caller decides whether to retry or fall
  /// back) and closure; a listener added after the join receives the last
  /// known status immediately. The current session token is pushed to
  /// Realtime before a join so the topic policy can read `auth.uid()` and
  /// `user_tenant_id()`.
  Future<TenantBroadcastListener> listen({
    required SupabaseClient client,
    required String topic,
    required ValueChanged<Map<String, dynamic>> onEvent,
    void Function(TenantBroadcastStatus status, Object? error)? onStatus,
  }) async {
    var entry = _entries[topic];
    final isNew = entry == null;
    entry ??= _entries[topic] = _TopicEntry(this, client, topic);
    final listener = TenantBroadcastListener._(entry, onEvent, onStatus);
    entry.listeners.add(listener);
    if (isNew) {
      await client.realtime.setAuth(client.auth.currentSession?.accessToken);
      if (listener.isCancelled || entry.listeners.isEmpty) return listener;
      final joined = entry;
      joined.channel = client
          .channel(topic, opts: const RealtimeChannelConfig(private: true))
          .onBroadcast(event: 'changed', callback: joined.dispatch)
          .subscribe((status, error) {
        switch (status) {
          case RealtimeSubscribeStatus.subscribed:
            joined.status(TenantBroadcastStatus.subscribed, null);
          case RealtimeSubscribeStatus.channelError:
          case RealtimeSubscribeStatus.timedOut:
            joined.status(TenantBroadcastStatus.degraded, error);
          case RealtimeSubscribeStatus.closed:
            joined.status(TenantBroadcastStatus.closed, error);
        }
      });
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

  /// Drops every topic regardless of its listeners. Owners cancel their own
  /// listeners on user change; this exists for test hygiene.
  @visibleForTesting
  Future<void> reset() async {
    final entries = List.of(_entries.values);
    _entries.clear();
    for (final entry in entries) {
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
