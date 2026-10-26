import 'package:vinabike_public_core/public_store/models/storefront_logo_source.dart';

/// Where the storefront reads from and which store it renders.
///
/// Only the publishable key is needed: every read is a public function that
/// runs as `anon`, so the server can read nothing a visitor's browser cannot.
class StorefrontConfig {
  const StorefrontConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    this.tenantId = VinabikeCanonicalTenant.id,
    this.storeOrigin = 'https://vinabike.cl',
    this.assetsDir,
    this.source,
    this.searchOrigin = '',
  });

  factory StorefrontConfig.fromEnvironment(Map<String, String> env) {
    final key = env['SUPABASE_PUBLISHABLE_KEY']?.trim() ?? '';
    if (key.isEmpty) {
      throw StateError('SUPABASE_PUBLISHABLE_KEY is required');
    }
    String value(String name, String fallback) {
      final raw = env[name]?.trim() ?? '';
      return raw.isEmpty ? fallback : raw;
    }

    final assets = env['STOREFRONT_ASSETS_DIR']?.trim() ?? '';
    final source = env['STOREFRONT_SOURCE']?.trim() ?? '';
    return StorefrontConfig(
      supabaseUrl: value(
        'SUPABASE_URL',
        'https://xzdvtzdqjeyqxnkqprtf.supabase.co',
      ),
      publishableKey: key,
      tenantId: value('STOREFRONT_TENANT_ID', VinabikeCanonicalTenant.id),
      storeOrigin: value('STOREFRONT_ORIGIN', 'https://vinabike.cl'),
      assetsDir: assets.isEmpty ? null : assets,
      source: source.isEmpty ? null : source,
      searchOrigin: env['STOREFRONT_SEARCH_ORIGIN']?.trim() ?? '',
    );
  }

  final String supabaseUrl;
  final String publishableKey;
  final String tenantId;

  /// The public origin canonical URLs and structured data point to.
  final String storeOrigin;

  /// Local development only: the repository root, so `/assets/...` (fonts,
  /// logo) can be served the way Firebase Hosting serves them in production.
  final String? assetsDir;

  /// Which source this build was made from, as `tool/source_id.sh` prints
  /// it; `deploy_cloud_run.sh` sets it. Every response carries it in
  /// `x-storefront-source` so a store publication can tell a server that
  /// lags behind the shared core.
  final String? source;

  /// Where the header's search box asks for its suggestions (the service's
  /// own Cloud Run URL, set by `deploy_cloud_run.sh`), or empty for the
  /// page's origin. Through Firebase Hosting every suggestion took ~200 ms
  /// more (2026-10-25): Hosting relays the request to Cloud Run.
  final String searchOrigin;

  /// The pages that may read the suggestions from [searchOrigin]: the store
  /// and its `www.` twin.
  bool allowsSearchFrom(String origin) {
    final store = Uri.tryParse(storeOrigin);
    final from = Uri.tryParse(origin);
    if (store == null || from == null || from.scheme != store.scheme) {
      return false;
    }
    final host = store.host.startsWith('www.')
        ? store.host.substring(4)
        : store.host;
    return from.host == host || from.host == 'www.$host';
  }
}
