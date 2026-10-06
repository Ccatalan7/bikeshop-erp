import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';

import 'portal_page_view.dart';
import 'public_reads.dart';

/// `POST /cuenta/vista` with `{path, query}` and the customer's session as
/// `authorization: Bearer <token>`: the portal page, read from Supabase as
/// that customer (row security decides what they see; every read filters
/// the tenant too) and drawn by [portalView].
///
/// Answers `{html}`, or `{state}`: `expired` when Supabase refused the token
/// (the page renews it and asks again), `not-customer` when the session is
/// not a customer of this store or the reads failed (Flutter's «No pudimos
/// abrir esta cuenta»). The token is never kept nor written to a log; the
/// answer is `no-store`.
Future<Response> portalViewResponse(
  Request request, {
  required PublicReads reads,
}) async {
  final watch = Stopwatch()..start();
  final token = _bearer(request);
  final body = await _body(request);
  final page = PortalPage.ofPath(body?['path']?.toString() ?? '');
  final query = body?['query']?.toString() ?? '';
  if (token == null || page == null || query.length > 512) {
    return _json(request, 400, {'state': 'invalid'});
  }
  final CustomerPortalReads read;
  try {
    read = await reads.customerPortal(token);
  } on CustomerSessionRefused {
    return _json(request, 200, {'state': 'expired'});
  } on Object catch (error) {
    // A connection error can carry the address (with the customer's ids):
    // only the read that failed, or the kind of error.
    stderr.writeln(
      'portal read failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return _json(request, 200, {'state': 'not-customer'});
  }
  if (read.profile == null) {
    return _json(request, 200, {'state': 'not-customer'});
  }
  final dataMs = watch.elapsedMilliseconds;
  final rendered = await renderComponent(
    portalView(PortalViewData.fromReads(page, query, read)),
    request: request,
    standalone: true,
  );
  return _json(
    request,
    200,
    {'html': utf8.decode(rendered.body)},
    timing:
        'data;dur=$dataMs, render;dur=${watch.elapsedMilliseconds - dataMs}',
  );
}

/// `POST /cuenta/archivo` with `{reference}` and the session: a fresh link
/// to one of a job's files (`WorkshopAssetService.resolve`), `{url}`.
Future<Response> portalFileResponse(
  Request request, {
  required PublicReads reads,
}) async {
  final token = _bearer(request);
  final reference = (await _body(request))?['reference']?.toString() ?? '';
  if (token == null || reference.isEmpty || reference.length > 1024) {
    return _json(request, 400, {'state': 'invalid'});
  }
  try {
    final url = await reads.customerJobFile(token, reference);
    return url == null
        ? _json(request, 404, {'state': 'unavailable'})
        : _json(request, 200, {'url': url});
  } on CustomerSessionRefused {
    return _json(request, 401, {'state': 'expired'});
  } on Object catch (error) {
    stderr.writeln('portal file failed: ${error.runtimeType}');
    return _json(request, 503, {'state': 'unavailable'});
  }
}

String? _bearer(Request request) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  final token = header.substring(7).trim();
  return token.length < 40 || token.length > 4096 ? null : token;
}

Future<Map<String, Object?>?> _body(Request request) async {
  try {
    final raw = await request
        .read()
        .fold<List<int>>([], (all, chunk) {
          if (all.length + chunk.length > 4096) throw const FormatException();
          return all..addAll(chunk);
        })
        .timeout(const Duration(seconds: 10));
    final decoded = jsonDecode(utf8.decode(raw));
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on Object {
    return null;
  }
}

Response _json(
  Request request,
  int status,
  Map<String, Object?> value, {
  String? timing,
}) {
  final body = utf8.encode(jsonEncode(value));
  final accepts = (request.headers['accept-encoding'] ?? '').contains('gzip');
  final gzipped = accepts && body.length > 1024 ? gzip.encode(body) : null;
  return Response(
    status,
    body: gzipped ?? body,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
      'vary': 'accept-encoding',
      'content-encoding': ?(gzipped == null ? null : 'gzip'),
      'server-timing': ?timing,
    },
  );
}
