import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum FinancialProjectionRealtimeStatus {
  subscribed,
  degraded,
  closed,
}

abstract class FinancialProjectionRealtimeSubscription {
  Future<void> cancel();
}

abstract class FinancialProjectionRealtimeTransport {
  Future<FinancialProjectionRealtimeSubscription> subscribe({
    required String tenantId,
    required ValueChanged<Map<String, dynamic>> onEvent,
    required void Function(
      FinancialProjectionRealtimeStatus status,
      Object? error,
    ) onStatus,
  });
}

/// Supabase private-Broadcast transport for financial projection invalidations.
///
/// The database publishes only event metadata to a tenant-derived private
/// topic. No invoice, payment, expense, payroll, or journal row is transported
/// through this channel.
class SupabaseFinancialProjectionRealtimeTransport
    implements FinancialProjectionRealtimeTransport {
  SupabaseFinancialProjectionRealtimeTransport(this._client);

  final SupabaseClient _client;

  @override
  Future<FinancialProjectionRealtimeSubscription> subscribe({
    required String tenantId,
    required ValueChanged<Map<String, dynamic>> onEvent,
    required void Function(
      FinancialProjectionRealtimeStatus status,
      Object? error,
    ) onStatus,
  }) async {
    await _client.realtime.setAuth(
      _client.auth.currentSession?.accessToken,
    );

    final channel = _client
        .channel(
          'financial-projections:$tenantId',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(
          event: 'changed',
          callback: onEvent,
        )
        .subscribe((status, error) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          onStatus(FinancialProjectionRealtimeStatus.subscribed, null);
          return;
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          onStatus(FinancialProjectionRealtimeStatus.degraded, error);
          return;
        case RealtimeSubscribeStatus.closed:
          onStatus(FinancialProjectionRealtimeStatus.closed, error);
          return;
      }
    });

    return _SupabaseFinancialProjectionRealtimeSubscription(
      _client,
      channel,
    );
  }
}

class _SupabaseFinancialProjectionRealtimeSubscription
    implements FinancialProjectionRealtimeSubscription {
  _SupabaseFinancialProjectionRealtimeSubscription(
    this._client,
    this._channel,
  );

  final SupabaseClient _client;
  final RealtimeChannel _channel;
  bool _cancelled = false;

  @override
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _client.removeChannel(_channel);
  }
}
