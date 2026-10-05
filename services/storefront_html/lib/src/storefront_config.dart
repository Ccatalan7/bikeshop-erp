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
}
