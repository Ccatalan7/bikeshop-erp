// The public storefront rendered as HTML, one page per visit.
//
// Phases 0 and 1 of docs/architecture/storefront-html-migration-plan.md:
// product pages, `/productos` and its categories, on the public routes that
// `firebase.json` rewrites here and on the hidden copy (`/_html/...`). Run it
// locally with services/storefront_html/run_local.sh; deploy with
// deploy_cloud_run.sh.
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:shelf/shelf.dart' show Pipeline, logRequests;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:vinabike_public_core/public_store/models/portal_time_zone.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

Future<void> main() async {
  Jaspr.initializeApp();
  // The portal's dates in the store's time zone: Cloud Run runs in UTC.
  usePortalTimeZone();
  final config = StorefrontConfig.fromEnvironment(Platform.environment);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(storefrontSourceHeader(config.source))
      .addHandler(
        storefrontHandler(
          config: config,
          reads: SupabasePublicReads(config),
          flutterShell: HostedFlutterShell(),
        ),
      );
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    port,
    shared: true,
  );
  server.autoCompress = true;
  stdout.writeln('Storefront HTML on http://localhost:${server.port}/');
}
