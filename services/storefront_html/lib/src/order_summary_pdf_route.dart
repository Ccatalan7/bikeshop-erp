import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:vinabike_public_core/public_store/documents/order_summary_pdf.dart';
import 'package:vinabike_public_core/public_store/documents/store_document_style.dart';

import 'public_reads.dart';
import 'storefront_config.dart';

/// The store's Barlow faces and its logo for the customer documents, read
/// once: from the repository when the server runs locally (`assetsDir`),
/// otherwise from Hosting, which serves the same files Flutter bundles
/// (`/assets/assets/fonts/<face>.ttf`, `/assets/assets/images/…`). A logo the
/// site keeps elsewhere (`https://…`) is read from there.
class OrderSummaryFonts {
  OrderSummaryFonts(
    this._load, {
    Future<Uint8List> Function(String source)? loadLogo,
    this.tenantId,
  }) : _loadLogo = loadLogo;

  factory OrderSummaryFonts.forConfig(StorefrontConfig config) {
    final assets = config.assetsDir;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    Future<Uint8List> fetch(Uri uri) async {
      final request = await client.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        throw HttpException('${response.statusCode}', uri: uri);
      }
      final bytes = BytesBuilder(copy: false);
      await response.forEach(bytes.add).timeout(_timeout);
      return bytes.takeBytes();
    }

    // `assets/assets/images/…` is a web path of the bundle; `assetsDir` is
    // its `assets/` folder.
    Future<Uint8List> logo(String source) async {
      if (!source.startsWith('assets/')) return fetch(Uri.parse(source));
      if (assets != null) {
        return File(
          '$assets/${source.substring('assets/'.length)}',
        ).readAsBytes();
      }
      return fetch(Uri.parse('${config.storeOrigin}/$source'));
    }

    if (assets != null) {
      return OrderSummaryFonts(
        (face) async => ByteData.sublistView(
          await File('$assets/assets/fonts/$face.ttf').readAsBytes(),
        ),
        loadLogo: logo,
        tenantId: config.tenantId,
      );
    }
    return OrderSummaryFonts(
      (face) async => ByteData.sublistView(
        await fetch(
          Uri.parse('${config.storeOrigin}/assets/assets/fonts/$face.ttf'),
        ),
      ),
      loadLogo: logo,
      tenantId: config.tenantId,
    );
  }

  static const _timeout = Duration(seconds: 10);
  final Future<ByteData> Function(String face) _load;
  final Future<Uint8List> Function(String source)? _loadLogo;

  /// The store this server answers for: whether the bundled logo is its own.
  final String? tenantId;
  final _faces = <String, Future<ByteData>>{};
  final _logos = <String, Future<Uint8List>>{};

  Future<ByteData> face(String name) {
    final pending = _faces.putIfAbsent(name, () => _load(name));
    // A failed read is tried again by the next visitor.
    pending.catchError((Object _) {
      if (identical(_faces[name], pending)) _faces.remove(name);
      return ByteData(0);
    });
    return pending;
  }

  /// The store's logo by the documents' rule ([storeDocumentLogoSource]), or
  /// null: then the letterhead writes the name, and the document still goes.
  Future<Uint8List?> storeLogo(String? identityLogoUrl) async {
    final load = _loadLogo;
    final source = storeDocumentLogoSource(
      identityLogoUrl: identityLogoUrl,
      tenantId: tenantId,
    );
    if (load == null || source == null) return null;
    final pending = _logos.putIfAbsent(source, () => load(source));
    try {
      return await pending;
    } on Object catch (error) {
      if (identical(_logos[source], pending)) _logos.remove(source);
      stderr.writeln('store logo read failed: $error');
      return null;
    }
  }
}

/// `POST /pedido/resumen.pdf` with `{order_id, access_token}`: the order's
/// summary as Flutter's «DESCARGAR RESUMEN DEL PEDIDO» draws it
/// ([buildOrderSummaryPdf], shared). The access travels in the body, never
/// in the address; without it nothing is read.
Future<Response> orderSummaryPdf(
  Request request, {
  required PublicReads reads,
  required OrderSummaryFonts fonts,
}) async {
  final body = await readDocumentRequest(request);
  if (body == null) return documentTextResponse(400, 'Solicitud inválida.');
  final orderId = body['order_id']?.toString().trim() ?? '';
  final token = body['access_token']?.toString().trim() ?? '';
  if (!RegExp(r'^[0-9A-Za-z-]{1,64}$').hasMatch(orderId) ||
      token.length < 40 ||
      token.length > 128) {
    return documentTextResponse(400, 'Solicitud inválida.');
  }
  final Object? envelope;
  try {
    envelope = await reads.publicOrder(token);
  } on Object catch (error) {
    stderr.writeln('order summary read failed: $error');
    return documentTextResponse(503, 'No pudimos leer el pedido.');
  }
  final input = OrderSummaryPdfInput.fromPublicAccess(
    envelope,
    expectedOrderId: orderId,
  );
  if (input == null) return documentTextResponse(404, 'Pedido no encontrado.');
  final Uint8List bytes;
  try {
    bytes = await buildOrderSummaryPdf(
      input,
      regularFont: await fonts.face('Barlow-Regular'),
      boldFont: await fonts.face('Barlow-Bold'),
      logo: await fonts.storeLogo(input.logoUrl),
    );
  } on Object catch (error) {
    stderr.writeln('order summary failed: $error');
    return documentTextResponse(503, 'No pudimos generar el resumen.');
  }
  final file = input.fileName.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
  return Response.ok(
    bytes,
    headers: {
      'content-type': 'application/pdf',
      'content-disposition': 'attachment; filename="$file"',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
    },
  );
}

/// A document request's small JSON body (`{order_id, access_token}`,
/// `{access_token}`); null when it is not one.
Future<Map<String, Object?>?> readDocumentRequest(Request request) async {
  try {
    final raw = await request
        .read()
        .fold<List<int>>([], (all, chunk) {
          if (all.length + chunk.length > 4096) throw const FormatException();
          return all..addAll(chunk);
        })
        .timeout(const Duration(seconds: 10));
    final decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map) return null;
    return Map<String, Object?>.from(decoded);
  } on Object {
    return null;
  }
}

/// A document route's plain answer: never kept, never indexed.
Response documentTextResponse(int status, String message) => Response(
  status,
  body: message,
  headers: {
    'content-type': 'text/plain; charset=utf-8',
    'cache-control': 'no-store',
    'x-robots-tag': 'noindex',
  },
);
