import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:vinabike_public_core/public_store/documents/order_summary_pdf.dart';

import 'public_reads.dart';
import 'storefront_config.dart';

/// The store's Barlow faces for the order summary, read once: from the
/// repository when the server runs locally (`assetsDir`), otherwise from
/// Hosting, which serves the same files Flutter bundles
/// (`/assets/assets/fonts/<face>.ttf`).
class OrderSummaryFonts {
  OrderSummaryFonts(this._load);

  factory OrderSummaryFonts.forConfig(StorefrontConfig config) {
    final assets = config.assetsDir;
    if (assets != null) {
      return OrderSummaryFonts(
        (face) async => ByteData.sublistView(
          await File('$assets/assets/fonts/$face.ttf').readAsBytes(),
        ),
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    return OrderSummaryFonts((face) async {
      final uri = Uri.parse(
        '${config.storeOrigin}/assets/assets/fonts/$face.ttf',
      );
      final request = await client.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        throw HttpException('$face → ${response.statusCode}', uri: uri);
      }
      final bytes = BytesBuilder(copy: false);
      await response.forEach(bytes.add).timeout(_timeout);
      return ByteData.sublistView(bytes.takeBytes());
    });
  }

  static const _timeout = Duration(seconds: 10);
  final Future<ByteData> Function(String face) _load;
  final _faces = <String, Future<ByteData>>{};

  Future<ByteData> face(String name) {
    final pending = _faces.putIfAbsent(name, () => _load(name));
    // A failed read is tried again by the next visitor.
    pending.catchError((Object _) {
      if (identical(_faces[name], pending)) _faces.remove(name);
      return ByteData(0);
    });
    return pending;
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
  Map<String, Object?> body;
  try {
    final raw = await request
        .read()
        .fold<List<int>>([], (all, chunk) {
          if (all.length + chunk.length > 4096) throw const FormatException();
          return all..addAll(chunk);
        })
        .timeout(const Duration(seconds: 10));
    final decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map) throw const FormatException();
    body = Map<String, Object?>.from(decoded);
  } on Object {
    return _plain(400, 'Solicitud inválida.');
  }
  final orderId = body['order_id']?.toString().trim() ?? '';
  final token = body['access_token']?.toString().trim() ?? '';
  if (!RegExp(r'^[0-9A-Za-z-]{1,64}$').hasMatch(orderId) ||
      token.length < 40 ||
      token.length > 128) {
    return _plain(400, 'Solicitud inválida.');
  }
  final Object? envelope;
  try {
    envelope = await reads.publicOrder(token);
  } on Object catch (error) {
    stderr.writeln('order summary read failed: $error');
    return _plain(503, 'No pudimos leer el pedido.');
  }
  final input = OrderSummaryPdfInput.fromPublicAccess(
    envelope,
    expectedOrderId: orderId,
  );
  if (input == null) return _plain(404, 'Pedido no encontrado.');
  final Uint8List bytes;
  try {
    bytes = await buildOrderSummaryPdf(
      input,
      regularFont: await fonts.face('Barlow-Regular'),
      boldFont: await fonts.face('Barlow-Bold'),
    );
  } on Object catch (error) {
    stderr.writeln('order summary failed: $error');
    return _plain(503, 'No pudimos generar el resumen.');
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

Response _plain(int status, String message) => Response(
  status,
  body: message,
  headers: {
    'content-type': 'text/plain; charset=utf-8',
    'cache-control': 'no-store',
    'x-robots-tag': 'noindex',
  },
);
