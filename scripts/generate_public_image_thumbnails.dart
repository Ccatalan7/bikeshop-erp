// Makes the 400 px and 800 px copies of the photo each public product card
// shows, and records them in `public.public_image_thumbnails`
// (20261005130000), which the HTML storefront reads to give each card a
// `srcset` (services/storefront_html/lib/src/product_card.dart).
//
// One owner for every card photo: the ERP uploads product photos from about a
// dozen places and some are hosted elsewhere (AliExpress), so the copies are
// made here, from what the card links, not at upload. The store build runs it
// (.github/workflows/firebase-hosting-store.yml); by hand, for a backfill:
//
//   SUPABASE_SECRET_KEY=… SUPABASE_URL=https://xzdvtzdqjeyqxnkqprtf.supabase.co \
//   dart run scripts/generate_public_image_thumbnails.dart \
//     --tenant-id 5443b130-cc28-45af-a420-cd500b288890 [--limit N] [--dry-run]
//
// A photo is made again when its signature (ETag, or length and date)
// changes; its new copies get new names, so they can be cached for a year.
// A photo that cannot be read or decoded is reported and skipped: its card
// keeps the large photo. The run fails when the record or the storage cannot
// be written, or when more than a third of the photos it tried failed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';

const _bucket = 'vinabike-assets';
const _maxPhotoBytes = 25 * 1024 * 1024;
const _jpegQuality = 80;

/// The photos public cards show for these product rows: the first photo as
/// the catalog listing returns it (no website columns) and as the product
/// page completes it (with them). Usually the same one.
Set<String> publicCardPhotos(Iterable<Map<String, dynamic>> products) {
  const websiteOnly = {
    'website_image_url',
    'website_image_url_optimized',
    'website_image_urls',
  };
  return {
    for (final row in products)
      for (final candidate in [
        {
          for (final entry in row.entries)
            if (!websiteOnly.contains(entry.key)) entry.key: entry.value,
        },
        row,
      ])
        ...PublicCommerceProductProjection.fromJson(candidate).imageUrls.take(1),
  };
}

/// Where a copy is stored: named by the photo and its signature, so a
/// replaced photo gets new names and an old copy is never served for it.
String publicThumbnailPath({
  required String tenantId,
  required String sourceUrl,
  required String signature,
  required int width,
}) {
  final key = sha256
      .convert(utf8.encode('$sourceUrl\n$signature'))
      .toString()
      .substring(0, 24);
  return 'public/thumbs/$tenantId/$key-$width.jpg';
}

/// The photo's size and its JPEG copies narrower than it, on a white ground
/// (a transparent PNG would turn black), with the camera's rotation applied.
({int width, int height, List<({int width, int height, Uint8List bytes})> copies})?
makePublicThumbnails(Uint8List bytes, List<int> widths) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // A cut or corrupt file throws inside the decoder instead of saying null.
    decoded = null;
  }
  if (decoded == null) return null;
  var photo = img.bakeOrientation(decoded);
  if (photo.hasAlpha) {
    final ground = img.Image(
      width: photo.width,
      height: photo.height,
      numChannels: 3,
    )..clear(img.ColorRgb8(255, 255, 255));
    photo = img.compositeImage(ground, photo);
  }
  return (
    width: photo.width,
    height: photo.height,
    copies: [
      for (final width in widths)
        if (width < photo.width)
          (() {
            final copy = img.copyResize(
              photo,
              width: width,
              interpolation: img.Interpolation.average,
            );
            return (
              width: copy.width,
              height: copy.height,
              bytes: img.encodeJpg(copy, quality: _jpegQuality),
            );
          })(),
    ],
  );
}

/// Decoding and resizing run on another core; the closure must carry only
/// the bytes (an HTTP client cannot cross isolates).
Future<
  ({int width, int height, List<({int width, int height, Uint8List bytes})> copies})?
>
_makeInIsolate(Uint8List bytes) =>
    Isolate.run(() => makePublicThumbnails(bytes, publicImageThumbnailWidths));

Future<void> main(List<String> args) async {
  final options = _options(args);
  final tenantId = options['tenant-id'] ?? '';
  final supabaseUrl = (Platform.environment['SUPABASE_URL'] ?? '').trim();
  final key = (Platform.environment['SUPABASE_SECRET_KEY'] ?? '').trim();
  if (tenantId.isEmpty || supabaseUrl.isEmpty || key.isEmpty) {
    stderr.writeln(
      'Uso: SUPABASE_URL=… SUPABASE_SECRET_KEY=… dart run '
      'scripts/generate_public_image_thumbnails.dart --tenant-id <uuid> '
      '[--limit N] [--dry-run]',
    );
    exitCode = 2;
    return;
  }
  final limit = int.tryParse(options['limit'] ?? '');
  final dryRun = options.containsKey('dry-run');
  final api = _Supabase(supabaseUrl, key);
  try {
    final products = await api.selectAll('products', {
      'select':
          'id,image_url,image_url_optimized,image_urls,website_image_url,'
          'website_image_url_optimized,website_image_urls',
      'tenant_id': 'eq.$tenantId',
      'is_active': 'is.true',
      'is_published': 'is.true',
      'show_on_website': 'is.true',
      'order': 'id.asc',
    });
    final photos = publicCardPhotos(products).toList()..sort();
    final known = {
      for (final row in await api.selectAll('public_image_thumbnails', {
        'select': 'source_url,source_signature',
        'tenant_id': 'eq.$tenantId',
        'order': 'source_url.asc',
      }))
        row['source_url'].toString(): row['source_signature'].toString(),
    };
    stdout.writeln(
      '${products.length} productos publicados, ${photos.length} fotos de '
      'tarjeta, ${known.length} con copias registradas',
    );

    var made = 0;
    var current = 0;
    var attempted = 0;
    final failures = <String>[];
    var next = 0;
    Future<void> worker() async {
      while (next < photos.length) {
        if (limit != null && attempted >= limit) return;
        final url = photos[next++];
        try {
          final signature = await api.signature(url);
          if (signature != null && known[url] == signature) {
            current++;
            continue;
          }
          attempted++;
          final bytes = await api.download(url);
          final finalSignature =
              signature ?? 'sha256:${sha256.convert(bytes)}';
          if (known[url] == finalSignature) {
            current++;
            continue;
          }
          final result = await _makeInIsolate(bytes);
          if (result == null) {
            failures.add('$url: no se pudo leer la imagen');
            continue;
          }
          final variants = <PublicImageVariant>[];
          for (final copy in result.copies) {
            final path = publicThumbnailPath(
              tenantId: tenantId,
              sourceUrl: url,
              signature: finalSignature,
              width: copy.width,
            );
            if (!dryRun) await api.upload(path, copy.bytes);
            variants.add((
              width: copy.width,
              height: copy.height,
              url: '$supabaseUrl/storage/v1/object/public/$_bucket/$path',
            ));
          }
          if (!dryRun) {
            await api.upsert('public_image_thumbnails', {
              'tenant_id': tenantId,
              'source_url': url,
              'source_signature': finalSignature,
              'source_width': result.width,
              'source_height': result.height,
              'variants': PublicImageThumbnail.variantsJson(variants),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
          made++;
          if (made % 50 == 0) stdout.writeln('… $made fotos con copias');
        } on _WriteFailed {
          rethrow;
        } on Object catch (error) {
          failures.add('$url: $error');
        }
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
    stdout.writeln(
      '${dryRun ? '(prueba, sin escribir) ' : ''}$made fotos con copias '
      'nuevas, $current al día, ${failures.length} fallidas',
    );
    for (final failure in failures.take(20)) {
      stdout.writeln('  - $failure');
    }
    if (attempted > 0 && failures.length * 3 > attempted) {
      stderr.writeln('Más de un tercio de las fotos falló.');
      exitCode = 1;
    }
  } on _WriteFailed catch (error) {
    stderr.writeln('No se pudo escribir: ${error.message}');
    exitCode = 1;
  } finally {
    api.close();
  }
}

Map<String, String> _options(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2);
    if (name == 'dry-run') {
      out[name] = 'true';
    } else if (i + 1 < args.length) {
      out[name] = args[++i];
    }
  }
  return out;
}

class _WriteFailed implements Exception {
  _WriteFailed(this.message);
  final String message;
}

class _Supabase {
  _Supabase(this.url, this.key);

  final String url;
  final String key;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30)
    ..userAgent = 'vinabike-thumbnails';

  void close() => _client.close(force: true);

  void _auth(HttpClientRequest request) => request.headers
    ..set('apikey', key)
    ..set('authorization', 'Bearer $key');

  Future<List<Map<String, dynamic>>> selectAll(
    String table,
    Map<String, String> query,
  ) async {
    const page = 1000;
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += page) {
      final request = await _client.getUrl(
        Uri.parse('$url/rest/v1/$table').replace(
          queryParameters: {
            ...query,
            'limit': '$page',
            'offset': '$offset',
          },
        ),
      );
      _auth(request);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw _WriteFailed('leer $table → ${response.statusCode}: $text');
      }
      final batch = (jsonDecode(text) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      rows.addAll(batch);
      if (batch.length < page) return rows;
    }
  }

  /// The photo's ETag, or its length and date; `null` when the host gives
  /// neither (the bytes' hash is used then).
  Future<String?> signature(String photo) async {
    final request = await _client
        .openUrl('HEAD', Uri.parse(photo))
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 30));
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw HttpException('HEAD ${response.statusCode}');
    }
    final etag = response.headers.value('etag');
    if (etag != null && etag.isNotEmpty) return etag;
    final length = response.headers.value('content-length');
    final modified = response.headers.value('last-modified');
    return length != null && modified != null ? '$length|$modified' : null;
  }

  Future<Uint8List> download(String photo) async {
    final request = await _client
        .getUrl(Uri.parse(photo))
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('GET ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      builder.add(chunk);
      if (builder.length > _maxPhotoBytes) {
        throw const HttpException('más de 25 MB');
      }
    }
    return builder.takeBytes();
  }

  Future<void> upload(String path, Uint8List bytes) async {
    final request = await _client.postUrl(
      Uri.parse('$url/storage/v1/object/$_bucket/$path'),
    );
    _auth(request);
    request.headers
      ..set('content-type', 'image/jpeg')
      ..set('cache-control', 'max-age=31536000')
      ..set('x-upsert', 'true');
    request.add(bytes);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw _WriteFailed('subir $path → ${response.statusCode}: $text');
    }
  }

  Future<void> upsert(String table, Map<String, Object?> row) async {
    final request = await _client.postUrl(
      Uri.parse('$url/rest/v1/$table?on_conflict=tenant_id,source_url'),
    );
    _auth(request);
    request.headers
      ..set('content-type', 'application/json')
      ..set('prefer', 'resolution=merge-duplicates,return=minimal');
    request.write(jsonEncode(row));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 300) {
      throw _WriteFailed('guardar $table → ${response.statusCode}: $text');
    }
  }
}
