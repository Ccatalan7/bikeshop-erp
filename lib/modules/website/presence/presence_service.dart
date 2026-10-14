import 'package:supabase_flutter/supabase_flutter.dart';

import 'presence_models.dart';

/// Reads what `web-presence-collect` saved. The tables are read-only for the
/// app (RLS by tenant); the only writes are the Analytics property, through
/// `web_presence_save_settings_v1`, and asking the function to run now.
class PresenceService {
  PresenceService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static String _date(DateTime day) => day.toIso8601String().substring(0, 10);

  // supabase-dart orders descending unless told otherwise: every series
  // here is read oldest first (2026-10-14, the first render showed July
  // 2025 as «the last 28 days»).

  /// Every row of a filtered select: PostgREST returns at most 1.000 a time.
  Future<List<Map<String, dynamic>>> _all(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(
            int from, int to)
        page,
  ) async {
    const size = 1000;
    final rows = <Map<String, dynamic>>[];
    for (var from = 0;; from += size) {
      final chunk = await page(from, from + size - 1);
      rows.addAll(chunk);
      if (chunk.length < size) return rows;
    }
  }

  Future<List<SearchDay>> searchDays(String tenantId) async {
    final rows = await _all(
      (from, to) => _client
          .from('web_presence_search_daily')
          .select('day,clicks,impressions,position')
          .eq('tenant_id', tenantId)
          .order('day', ascending: true)
          .range(from, to),
    );
    return [for (final row in rows) SearchDay.fromRow(row)];
  }

  Future<List<IndexDay>> indexDays(String tenantId) async {
    final rows = await _all(
      (from, to) => _client
          .from('web_presence_index_daily')
          .select()
          .eq('tenant_id', tenantId)
          .order('day', ascending: true)
          .range(from, to),
    );
    return [for (final row in rows) IndexDay.fromRow(row)];
  }

  Future<List<TrafficRow>> traffic(
      String tenantId, PresenceScope scope, DateTime from) async {
    final rows = await _all(
      (start, end) => _client
          .from('web_presence_traffic_daily')
          .select('day,channel,sessions,engaged_sessions,users,key_events')
          .eq('tenant_id', tenantId)
          .eq('scope', scope.key)
          .gte('day', _date(from))
          .order('day', ascending: true)
          .range(start, end),
    );
    return [for (final row in rows) TrafficRow.fromRow(row)];
  }

  Future<List<EventRow>> events(
      String tenantId, PresenceScope scope, DateTime from) async {
    final rows = await _all(
      (start, end) => _client
          .from('web_presence_events_daily')
          .select('day,event_name,event_count')
          .eq('tenant_id', tenantId)
          .eq('scope', scope.key)
          .gte('day', _date(from))
          .order('day', ascending: true)
          .range(start, end),
    );
    return [for (final row in rows) EventRow.fromRow(row)];
  }

  Future<List<PresenceTerm>> terms(
    String tenantId, {
    required String kind,
    required DateTime from,
    required DateTime to,
    int limit = 50,
  }) async {
    final rows = await _client.rpc('web_presence_terms_v1', params: {
      'p_tenant_id': tenantId,
      'p_kind': kind,
      'p_from': _date(from),
      'p_to': _date(to),
      'p_limit': limit,
    });
    return [
      for (final row in rows as List)
        PresenceTerm.fromRow(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<PresenceNote>> notes(String tenantId) async {
    final rows = await _all(
      (from, to) => _client
          .from('web_presence_notes')
          .select('id,kind,day,title,body,source')
          .eq('tenant_id', tenantId)
          .order('day', ascending: false)
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return [for (final row in rows) PresenceNote.fromRow(row)];
  }

  Future<List<PresenceRun>> runs(String tenantId, {int limit = 12}) async {
    final rows = await _client
        .from('web_presence_runs')
        .select('task,status,started_at,finished_at,detail')
        .eq('tenant_id', tenantId)
        .order('started_at', ascending: false)
        .limit(limit);
    return [for (final row in rows) PresenceRun.fromRow(row)];
  }

  Future<PresenceSettings> settings(String tenantId) async {
    final row = await _client
        .from('web_presence_settings')
        .select('enabled,ga4_property_id,gsc_site')
        .eq('tenant_id', tenantId)
        .maybeSingle();
    return PresenceSettings.fromRow(row);
  }

  Future<void> saveAnalyticsProperty(
      String tenantId, String? propertyId) async {
    await _client.rpc('web_presence_save_settings_v1', params: {
      'p_tenant_id': tenantId,
      'p_ga4_property_id': propertyId,
      'p_enabled': true,
    });
  }

  /// Addresses of the sitemap in one coverage state, the most recently
  /// crawled first.
  Future<List<PresenceUrl>> urlsInState(String tenantId, String state,
      {int limit = 200}) async {
    var query = _client
        .from('web_presence_urls')
        .select(
            'url,coverage_state,verdict,last_crawl_at,inspected_at,google_canonical')
        .eq('tenant_id', tenantId)
        .eq('in_sitemap', true)
        .not('inspected_at', 'is', null);
    query = state == 'Sin dato'
        ? query.isFilter('coverage_state', null)
        : query.eq('coverage_state', state);
    final rows = await query
        .order('last_crawl_at', ascending: false, nullsFirst: false)
        .limit(limit);
    return [for (final row in rows) PresenceUrl.fromRow(row)];
  }

  /// Asks the collector to run now for this store. It answers at once and
  /// leaves its progress in `web_presence_runs`.
  Future<void> collectNow(String tenantId) async {
    await _client.functions.invoke(
      'web-presence-collect',
      body: {'action': 'collect', 'tenantId': tenantId},
    );
  }
}
