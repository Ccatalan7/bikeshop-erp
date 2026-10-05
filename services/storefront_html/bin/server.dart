// The public storefront rendered as HTML, one page per visit.
//
// Phases 0 and 1 of docs/architecture/storefront-html-migration-plan.md:
// product pages, `/productos` and its categories, on a hidden route
// (`/_html/...`) next to the Flutter store they mirror until the public routes
// point here. Run it locally with services/storefront_html/run_local.sh;
// deploy with deploy_cloud_run.sh.
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:shelf/shelf.dart' show Pipeline, logRequests;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:vinabike_storefront_html/storefront_html.dart';

Future<void> main() async {
  Jaspr.initializeApp();
  final config = StorefrontConfig.fromEnvironment(Platform.environment);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        storefrontHandler(config: config, reads: SupabasePublicReads(config)),
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
