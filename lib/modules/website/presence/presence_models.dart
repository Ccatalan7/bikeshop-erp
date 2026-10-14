/// What `web-presence-collect` stores (20261014150000) as the ERP reads it.
library;

/// The period the page compares with the one before it, of the same length.
enum PresencePeriod {
  week(7, '7 días'),
  month(28, '28 días'),
  quarter(91, '3 meses'),
  half(182, '6 meses'),
  year(365, '12 meses');

  const PresencePeriod(this.days, this.label);

  final int days;
  final String label;
}

/// Visits from Analytics: the whole store domain, or only from Chile (GA4
/// places the owner's Mac in Seattle, so «sitio» counts our own visits).
enum PresenceScope {
  chile('chile', 'Sólo Chile'),
  site('sitio', 'Todo el sitio');

  const PresenceScope(this.key, this.label);

  final String key;
  final String label;
}

DateTime _day(Object? value) =>
    DateTime.parse(value.toString().substring(0, 10));
DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
int _int(Object? value) =>
    (value is num) ? value.round() : int.tryParse('${value ?? ''}') ?? 0;
double? _double(Object? value) => value == null
    ? null
    : (value is num ? value.toDouble() : double.tryParse('$value'));

class SearchDay {
  const SearchDay({
    required this.day,
    required this.clicks,
    required this.impressions,
    required this.position,
  });

  factory SearchDay.fromRow(Map<String, dynamic> row) => SearchDay(
        day: _day(row['day']),
        clicks: _int(row['clicks']),
        impressions: _int(row['impressions']),
        position: _double(row['position']),
      );

  final DateTime day;
  final int clicks;
  final int impressions;
  final double? position;
}

/// Clicks, impressions, CTR and the impression-weighted position of a set
/// of days.
class SearchTotals {
  const SearchTotals({
    required this.clicks,
    required this.impressions,
    required this.position,
    required this.days,
  });

  factory SearchTotals.of(Iterable<SearchDay> days) {
    var clicks = 0;
    var impressions = 0;
    var weighted = 0.0;
    var weight = 0;
    var count = 0;
    for (final day in days) {
      count++;
      clicks += day.clicks;
      impressions += day.impressions;
      if (day.position != null && day.impressions > 0) {
        weighted += day.position! * day.impressions;
        weight += day.impressions;
      }
    }
    return SearchTotals(
      clicks: clicks,
      impressions: impressions,
      position: weight == 0 ? null : weighted / weight,
      days: count,
    );
  }

  final int clicks;
  final int impressions;
  final double? position;
  final int days;

  double? get ctr => impressions == 0 ? null : clicks / impressions;
}

class IndexDay {
  const IndexDay({
    required this.day,
    required this.sitemapUrls,
    required this.inspected,
    required this.indexed,
    required this.byState,
    required this.sitemapSubmitted,
    required this.sitemapLastRead,
  });

  factory IndexDay.fromRow(Map<String, dynamic> row) => IndexDay(
        day: _day(row['day']),
        sitemapUrls: _int(row['sitemap_urls']),
        inspected: _int(row['inspected']),
        indexed: _int(row['indexed']),
        byState: {
          for (final entry in Map<String, dynamic>.from(
                  (row['by_state'] as Map?) ?? const {})
              .entries)
            entry.key: _int(entry.value),
        },
        sitemapSubmitted: row['sitemap_submitted'] == null
            ? null
            : _int(row['sitemap_submitted']),
        sitemapLastRead: _time(row['sitemap_last_read']),
      );

  final DateTime day;
  final int sitemapUrls;
  final int inspected;
  final int indexed;
  final Map<String, int> byState;
  final int? sitemapSubmitted;
  final DateTime? sitemapLastRead;

  /// Indexed share of what Google has been asked about so far.
  double? get indexedShare => inspected == 0 ? null : indexed / inspected;
}

class TrafficRow {
  const TrafficRow({
    required this.day,
    required this.channel,
    required this.sessions,
    required this.engagedSessions,
    required this.users,
    required this.keyEvents,
  });

  factory TrafficRow.fromRow(Map<String, dynamic> row) => TrafficRow(
        day: _day(row['day']),
        channel: '${row['channel'] ?? ''}',
        sessions: _int(row['sessions']),
        engagedSessions: _int(row['engaged_sessions']),
        users: _int(row['users']),
        keyEvents: _double(row['key_events']) ?? 0,
      );

  final DateTime day;
  final String channel;
  final int sessions;
  final int engagedSessions;
  final int users;
  final double keyEvents;
}

class EventRow {
  const EventRow({required this.day, required this.name, required this.count});

  factory EventRow.fromRow(Map<String, dynamic> row) => EventRow(
        day: _day(row['day']),
        name: '${row['event_name'] ?? ''}',
        count: _int(row['event_count']),
      );

  final DateTime day;
  final String name;
  final int count;
}

/// A query or a page of the period next to the period before it.
class PresenceTerm {
  const PresenceTerm({
    required this.term,
    required this.clicks,
    required this.impressions,
    required this.position,
    required this.previousClicks,
    required this.previousImpressions,
    required this.previousPosition,
  });

  factory PresenceTerm.fromRow(Map<String, dynamic> row) => PresenceTerm(
        term: '${row['term'] ?? ''}',
        clicks: _int(row['clicks']),
        impressions: _int(row['impressions']),
        position: _double(row['avg_position']),
        previousClicks: _int(row['previous_clicks']),
        previousImpressions: _int(row['previous_impressions']),
        previousPosition: _double(row['previous_avg_position']),
      );

  final String term;
  final int clicks;
  final int impressions;
  final double? position;
  final int previousClicks;
  final int previousImpressions;
  final double? previousPosition;

  bool get isNew => previousImpressions == 0;

  /// Places gained: positive when it climbed (a lower number is better).
  double? get positionGain => position == null || previousPosition == null
      ? null
      : previousPosition! - position!;
}

enum PresenceNoteKind { change, analysis }

class PresenceNote {
  const PresenceNote({
    required this.id,
    required this.kind,
    required this.day,
    required this.title,
    required this.body,
    required this.source,
  });

  factory PresenceNote.fromRow(Map<String, dynamic> row) => PresenceNote(
        id: '${row['id']}',
        kind: row['kind'] == 'analisis'
            ? PresenceNoteKind.analysis
            : PresenceNoteKind.change,
        day: _day(row['day']),
        title: '${row['title'] ?? ''}',
        body: '${row['body'] ?? ''}',
        source: '${row['source'] ?? ''}',
      );

  final String id;
  final PresenceNoteKind kind;
  final DateTime day;
  final String title;
  final String body;
  final String source;
}

enum PresenceRunStatus { running, ok, partial, error }

class PresenceRun {
  const PresenceRun({
    required this.task,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.detail,
  });

  factory PresenceRun.fromRow(Map<String, dynamic> row) => PresenceRun(
        task: '${row['task'] ?? ''}',
        status: PresenceRunStatus.values.firstWhere(
          (value) => value.name == row['status'],
          orElse: () => PresenceRunStatus.error,
        ),
        startedAt: _time(row['started_at']) ?? DateTime.now(),
        finishedAt: _time(row['finished_at']),
        detail: Map<String, dynamic>.from((row['detail'] as Map?) ?? const {}),
      );

  final String task;
  final PresenceRunStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Map<String, dynamic> detail;

  /// A run that never closed: the function was cut before writing its end.
  bool get stalled =>
      status == PresenceRunStatus.running &&
      DateTime.now().difference(startedAt) > const Duration(minutes: 10);

  List<String> get errors => [
        for (final error in (detail['errors'] as List?) ?? const []) '$error',
        if (detail['error'] != null) '${detail['error']}',
      ];

  /// What the collector said about Analytics on this run.
  Map<String, dynamic>? get traffic => detail['traffic'] is Map
      ? Map<String, dynamic>.from(detail['traffic'] as Map)
      : null;
}

class PresenceSettings {
  const PresenceSettings(
      {this.enabled = true, this.ga4PropertyId, this.gscSite});

  factory PresenceSettings.fromRow(Map<String, dynamic>? row) => row == null
      ? const PresenceSettings()
      : PresenceSettings(
          enabled: row['enabled'] != false,
          ga4PropertyId: row['ga4_property_id'] as String?,
          gscSite: row['gsc_site'] as String?,
        );

  final bool enabled;
  final String? ga4PropertyId;
  final String? gscSite;
}

/// One address of the sitemap and what Google's inspection said of it.
class PresenceUrl {
  const PresenceUrl({
    required this.url,
    required this.coverageState,
    required this.verdict,
    required this.lastCrawlAt,
    required this.inspectedAt,
    required this.googleCanonical,
  });

  factory PresenceUrl.fromRow(Map<String, dynamic> row) => PresenceUrl(
        url: '${row['url'] ?? ''}',
        coverageState: row['coverage_state'] as String?,
        verdict: row['verdict'] as String?,
        lastCrawlAt: _time(row['last_crawl_at']),
        inspectedAt: _time(row['inspected_at']),
        googleCanonical: row['google_canonical'] as String?,
      );

  final String url;
  final String? coverageState;
  final String? verdict;
  final DateTime? lastCrawlAt;
  final DateTime? inspectedAt;
  final String? googleCanonical;
}

/// Search Console's coverage states in the words of the shop.
String coverageLabel(String state) => switch (state) {
      'Submitted and indexed' => 'Indexada',
      'Indexed, not submitted in sitemap' => 'Indexada, fuera del sitemap',
      'Crawled - currently not indexed' => 'Rastreada, Google no la indexó',
      'Discovered - currently not indexed' => 'Descubierta, aún sin rastrear',
      'URL is unknown to Google' => 'Google aún no la conoce',
      'Page with redirect' => 'Redirige a otra',
      "Excluded by 'noindex' tag" ||
      'Excluded by ‘noindex’ tag' =>
        'Excluida por noindex',
      'Not found (404)' => 'No existe (404)',
      'Soft 404' => 'Parece vacía (404 suave)',
      'Duplicate, Google chose different canonical than user' =>
        'Duplicada: Google eligió otra',
      'Duplicate without user-selected canonical' => 'Duplicada sin canónica',
      'Alternate page with proper canonical tag' =>
        'Alternativa de otra página',
      'Blocked by robots.txt' => 'Bloqueada por robots.txt',
      'Server error (5xx)' => 'Error del servidor',
      'Redirect error' => 'Redirección rota',
      'Sin dato' => 'Sin respuesta de Google',
      _ => state,
    };

/// Whether a coverage state means the page is in Google.
bool coverageIsIndexed(String state) =>
    state.startsWith('Submitted and indexed') || state.startsWith('Indexed');

/// GA4's default channel groups in Spanish.
String channelLabel(String channel) => switch (channel) {
      'Organic Search' => 'Búsqueda orgánica',
      'Direct' => 'Directo',
      'Referral' => 'Otros sitios',
      'Organic Social' => 'Redes sociales',
      'Paid Search' => 'Búsqueda pagada',
      'Paid Social' => 'Redes pagadas',
      'Organic Shopping' => 'Google Shopping',
      'Paid Shopping' => 'Shopping pagado',
      'Email' => 'Correo',
      'Unassigned' => 'Sin asignar',
      'Cross-network' => 'Varias redes',
      'Display' => 'Display',
      'Organic Video' => 'Video',
      'AI Assistant' => 'Asistentes de IA',
      _ => channel,
    };

/// The store funnel, in the order a buyer walks it.
const presenceFunnel = <(String, String)>[
  ('view_item_list', 'Vieron un listado'),
  ('view_item', 'Abrieron un producto'),
  ('add_to_cart', 'Agregaron al carro'),
  ('begin_checkout', 'Empezaron a pagar'),
  ('purchase', 'Compraron'),
];
