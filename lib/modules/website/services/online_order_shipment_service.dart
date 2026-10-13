import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/gemini_proxy_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/online_order_shipment.dart';
import '../models/website_models.dart';

/// A receipt photo ready to read and upload: big photos are brought down to
/// what the AI and a person need (1600 px, JPEG), a PDF goes as it is.
class ShipmentReceiptFile {
  const ShipmentReceiptFile({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;

  bool get isImage => mimeType.startsWith('image/');

  static const maxBytes = 12 * 1024 * 1024;

  static String? mimeTypeFor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'pdf' => 'application/pdf',
      _ => null,
    };
  }

  static Future<ShipmentReceiptFile> prepare(
    Uint8List bytes,
    String fileName,
  ) async {
    final mimeType = mimeTypeFor(fileName);
    if (mimeType == null) {
      throw const ShipmentReceiptException(
        'Sube una foto (JPG, PNG, HEIC o WebP) o un PDF de la boleta.',
      );
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const ShipmentReceiptException(
        'El archivo está vacío o pesa más de 12 MB.',
      );
    }
    if (mimeType == 'application/pdf') {
      return ShipmentReceiptFile(
        bytes: bytes,
        mimeType: mimeType,
        extension: 'pdf',
      );
    }
    final jpeg = await compute(_downscaleToJpeg, bytes);
    if (jpeg != null) {
      return ShipmentReceiptFile(
        bytes: jpeg,
        mimeType: 'image/jpeg',
        extension: 'jpg',
      );
    }
    // A format the image package cannot decode (HEIC) goes as taken.
    return ShipmentReceiptFile(
      bytes: bytes,
      mimeType: mimeType,
      extension: fileName.split('.').last.toLowerCase(),
    );
  }
}

Uint8List? _downscaleToJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  const longest = 1600;
  final resized = oriented.width >= oriented.height
      ? (oriented.width > longest
          ? img.copyResize(oriented, width: longest)
          : oriented)
      : (oriented.height > longest
          ? img.copyResize(oriented, height: longest)
          : oriented);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 84));
}

class ShipmentReceiptException implements Exception {
  const ShipmentReceiptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the dialog registers: the reading as the person confirmed it.
class ShipmentDraft {
  const ShipmentDraft({
    required this.carrier,
    required this.trackingNumber,
    this.carrierName,
    this.service,
    this.admittedAt,
    this.branch,
    this.cost,
  });

  final ShippingCarrier carrier;

  /// The name typed for a carrier outside the list.
  final String? carrierName;
  final String trackingNumber;
  final String? service;
  final DateTime? admittedAt;
  final String? branch;
  final double? cost;

  String get carrierLabel {
    final typed = carrierName?.trim() ?? '';
    return carrier == ShippingCarrier.other && typed.isNotEmpty
        ? typed
        : carrier.label;
  }
}

abstract interface class OnlineOrderShipmentReader {
  Future<List<OnlineOrderShipment>> loadForOrder(String orderId);
  Future<String?> receiptUrl(String path);
}

abstract interface class OnlineOrderShipmentRecorder {
  Future<ShipmentReceiptReading> readReceipt(ShipmentReceiptFile file);
  Future<String> uploadReceipt({
    required String orderId,
    required ShipmentReceiptFile file,
  });
  Future<OnlineOrderShipment> record({
    required OnlineOrder order,
    required String operationKey,
    required ShipmentDraft draft,
    String? receiptPath,
    ShipmentReceiptReading? reading,
    List<ShipmentReceiptCheck> checks,
  });
}

/// The shipping receipt of an online order: read with AI, stored next to the
/// order and registered with `record_online_order_shipment`, which moves the
/// order to «Despachado» and queues the customer's email in one transaction.
class OnlineOrderShipmentService
    implements OnlineOrderShipmentReader, OnlineOrderShipmentRecorder {
  OnlineOrderShipmentService({
    SupabaseClient? client,
    TenantService? tenantService,
    GeminiProxyService? gemini,
  })  : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService(),
        _gemini = gemini ?? GeminiProxyService(client: client);

  final SupabaseClient _client;
  final TenantService _tenantService;
  final GeminiProxyService _gemini;

  static const bucket = 'vinabike-files';
  // The vision model the app uses for photos (product identity): with
  // gemini-2.5-flash a printed «770000000099» came back with a zero missing.
  static const model = 'gemini-3.6-flash';

  Future<String> _tenantId() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw const ShipmentReceiptException('No hay un taller activo.');
    }
    return tenantId;
  }

  /// Reads the receipt, then reads the tracking code a second time from a
  /// close-up of it. A vision model miscounts runs of the same digit — on
  /// 2026-10-13 a printed «770000000099» came back as «77000000099» from the
  /// whole photo, twice, both models, even spelled out — and the customer
  /// would get that code. The close-up is cropped from the box the first
  /// reading points at; the code is verified only when every reading agrees.
  @override
  Future<ShipmentReceiptReading> readReceipt(ShipmentReceiptFile file) async {
    final json = await _generateJson(
      instruction: receiptReadingInstruction,
      schema: receiptReadingSchema,
      parts: [
        _inline(file.mimeType, file.bytes),
        {'text': 'Lee este comprobante de envío.'},
      ],
    );
    final reading = ShipmentReceiptReading.fromJson(json);
    if (!file.isImage || reading.trackingNumber == null) {
      return reading.withCloseUp(votes: const [], closeUp: null);
    }

    final box = json['tracking_number_box'];
    Uint8List? closeUp;
    try {
      closeUp = await compute(
        cropTrackingCode,
        (
          bytes: file.bytes,
          box: box is List ? box.whereType<num>().toList() : const <num>[]
        ),
      );
    } catch (_) {
      closeUp = null;
    }
    if (closeUp == null) {
      return reading.withCloseUp(votes: const [], closeUp: null);
    }

    // Three readings of the close-up, from two models and two settings: a
    // single one sometimes failed its own spelling check (2026-10-13).
    final votes = await Future.wait([
      _readCloseUp(closeUp, model: model, temperature: 0),
      _readCloseUp(closeUp, model: model, temperature: 0.4),
      _readCloseUp(closeUp, model: 'gemini-2.5-flash', temperature: 0),
    ]);
    return reading.withCloseUp(votes: votes, closeUp: closeUp);
  }

  Future<String?> _readCloseUp(
    Uint8List closeUp, {
    required String model,
    required double temperature,
  }) async {
    try {
      return focusedTrackingCode(await _generateJson(
        model: model,
        temperature: temperature,
        instruction: trackingCloseUpInstruction,
        schema: trackingCloseUpSchema,
        parts: [
          _inline('image/png', closeUp),
          {'text': 'Transcribe el código de este recorte.'},
        ],
      ));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _inline(String mimeType, Uint8List bytes) => {
        'inlineData': {'mimeType': mimeType, 'data': base64Encode(bytes)},
      };

  Future<Map<String, dynamic>> _generateJson({
    String model = OnlineOrderShipmentService.model,
    double temperature = 0,
    required String instruction,
    required Map<String, dynamic> schema,
    required List<Map<String, dynamic>> parts,
  }) async {
    final result = await _gemini.generateContent(
      model: model,
      systemInstruction: {
        'parts': [
          {'text': instruction},
        ],
      },
      contents: [
        {'role': 'user', 'parts': parts},
      ],
      generationConfig: {
        'temperature': temperature,
        'responseMimeType': 'application/json',
        'responseSchema': schema,
      },
    );
    final text = result.text.trim();
    final decoded = text.isEmpty ? null : jsonDecode(_stripFence(text));
    if (decoded is! Map) {
      throw const ShipmentReceiptException(
        'La IA no pudo leer la boleta. Escribe los datos a mano.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<String> uploadReceipt({
    required String orderId,
    required ShipmentReceiptFile file,
  }) async {
    final tenantId = await _tenantId();
    final path = '$tenantId/evidence/online_order_shipment/$orderId/'
        '${const Uuid().v4()}.${file.extension}';
    await _client.storage.from(bucket).uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );
    return path;
  }

  @override
  Future<OnlineOrderShipment> record({
    required OnlineOrder order,
    required String operationKey,
    required ShipmentDraft draft,
    String? receiptPath,
    ShipmentReceiptReading? reading,
    List<ShipmentReceiptCheck> checks = const [],
  }) async {
    final response = await _client.rpc(
      'record_online_order_shipment',
      params: {
        'p_order_id': order.id,
        'p_expected_version': order.version,
        'p_operation_key': operationKey,
        'p_shipment': {
          'carrier': draft.carrierLabel,
          'carrier_code': draft.carrier.code,
          if (draft.service?.trim().isNotEmpty == true)
            'service': draft.service!.trim(),
          'tracking_number': draft.trackingNumber,
          if (draft.carrier.trackingUrl != null)
            'tracking_url': draft.carrier.trackingUrl,
          if (draft.admittedAt != null)
            'admitted_at': draft.admittedAt!.toUtc().toIso8601String(),
          if (draft.branch?.trim().isNotEmpty == true)
            'branch': draft.branch!.trim(),
          if (draft.cost != null) 'cost': draft.cost,
          if (receiptPath != null) 'receipt_path': receiptPath,
          if (reading != null) 'extracted': reading.toExtracted(),
          'checks': {for (final check in checks) check.key: check.toJson()},
        },
      },
    );
    return OnlineOrderShipment.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<List<OnlineOrderShipment>> loadForOrder(String orderId) async {
    final tenantId = await _tenantId();
    final rows = await _client
        .from('online_order_shipments')
        .select(
          'id,order_id,carrier,carrier_code,service,tracking_number,'
          'tracking_url,admitted_at,branch,cost,receipt_path,checks,created_at',
        )
        .eq('tenant_id', tenantId)
        .eq('order_id', orderId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map(OnlineOrderShipment.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String?> receiptUrl(String path) async {
    final tenantId = await _tenantId();
    if (!path.startsWith('$tenantId/')) return null;
    return _client.storage.from(bucket).createSignedUrl(path, 10 * 60);
  }
}

String _stripFence(String text) => text
    .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
    .replaceFirst(RegExp(r'\s*```$'), '');

/// What the AI is told. It reads only what is printed and never the sender:
/// the receipt carries the employee's name and RUT, which the shop does not
/// need to keep.
const receiptReadingInstruction = '''
Lees la foto o el PDF de un comprobante de admisión de un envío en Chile
(Correos de Chile, Chilexpress, Starken, Blue Express, Pullman Cargo u otro
transportista). Devuelve todos los campos. Escribe sólo lo que está impreso; si un dato no
aparece o no se lee con seguridad, devuélvelo como null. No inventes ni
completes.

- is_shipping_receipt: false si la imagen no es un comprobante de envío.
- carrier_code: el transportista; "other" si no es uno de la lista.
- service: el servicio contratado tal como aparece (por ejemplo "PAQUETE EXPRESS AM").
- tracking_number: el código de seguimiento o de envío del paquete, sin
  espacios. No es el número de boleta, folio, caja, ticket ni transacción.
- tracking_number_characters: el mismo código, un carácter por elemento y en
  orden, leído de nuevo carácter por carácter. Cuenta bien las series de
  ceros o de dígitos repetidos.
- tracking_number_box: dónde está impreso ese código en la imagen, como
  [ymin, xmin, ymax, xmax] en escala de 0 a 1000.
- admitted_at: fecha y hora de admisión impresas, como AAAA-MM-DDTHH:MM.
- branch: la sucursal u oficina donde se admitió.
- total_paid: el total pagado en pesos, sólo dígitos.
- recipient_*: los datos de quien RECIBE el envío (destinatario). Nunca
  devuelvas datos del remitente.
- order_reference: una referencia o número de pedido escrito en el
  comprobante, si lo hay (por ejemplo "WEB-26-00021").
- confidence: de 0 a 1, cuán seguro estás del código de seguimiento.
''';

/// Every field is required and may be null: with optional fields the model
/// sometimes answered only the required ones (2026-10-13: the code alone, no
/// recipient, service or amount).
const receiptReadingSchema = <String, dynamic>{
  'type': 'OBJECT',
  'properties': {
    'is_shipping_receipt': {'type': 'BOOLEAN'},
    'carrier_code': {
      'type': 'STRING',
      'enum': [
        'correos_chile',
        'chilexpress',
        'starken',
        'blue_express',
        'pullman_cargo',
        'other',
      ],
    },
    'carrier_name': {'type': 'STRING', 'nullable': true},
    'service': {'type': 'STRING', 'nullable': true},
    'tracking_number': {'type': 'STRING', 'nullable': true},
    'tracking_number_characters': {
      'type': 'ARRAY',
      'items': {'type': 'STRING'},
    },
    'tracking_number_box': {
      'type': 'ARRAY',
      'items': {'type': 'INTEGER'},
    },
    'admitted_at': {'type': 'STRING', 'nullable': true},
    'branch': {'type': 'STRING', 'nullable': true},
    'total_paid': {'type': 'NUMBER', 'nullable': true},
    'recipient_name': {'type': 'STRING', 'nullable': true},
    'recipient_rut': {'type': 'STRING', 'nullable': true},
    'recipient_address': {'type': 'STRING', 'nullable': true},
    'recipient_comuna': {'type': 'STRING', 'nullable': true},
    'order_reference': {'type': 'STRING', 'nullable': true},
    'confidence': {'type': 'NUMBER'},
  },
  'required': [
    'is_shipping_receipt',
    'carrier_code',
    'carrier_name',
    'service',
    'tracking_number',
    'tracking_number_characters',
    'tracking_number_box',
    'admitted_at',
    'branch',
    'total_paid',
    'recipient_name',
    'recipient_rut',
    'recipient_address',
    'recipient_comuna',
    'order_reference',
    'confidence',
  ],
  'propertyOrdering': [
    'is_shipping_receipt',
    'carrier_code',
    'carrier_name',
    'service',
    'tracking_number',
    'tracking_number_characters',
    'tracking_number_box',
    'admitted_at',
    'branch',
    'total_paid',
    'recipient_name',
    'recipient_rut',
    'recipient_address',
    'recipient_comuna',
    'order_reference',
    'confidence',
  ],
};

/// The close-up of the tracking code: the box the first reading points at
/// ([ymin, xmin, ymax, xmax], 0–1000), with room around it, enlarged so the
/// characters are big. Null when the box is missing or makes no sense.
Uint8List? cropTrackingCode(({Uint8List bytes, List<num> box}) input) {
  final box = input.box;
  if (box.length != 4) return null;
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) return null;
  final width = decoded.width;
  final height = decoded.height;
  final top = box[0] / 1000 * height;
  final left = box[1] / 1000 * width;
  final bottom = box[2] / 1000 * height;
  final right = box[3] / 1000 * width;
  if (bottom <= top || right <= left) return null;
  // A generous margin: the box can be tight or a little off.
  final padY = (bottom - top) * 0.8 + 6;
  final padX = (right - left) * 0.15 + 12;
  final x = (left - padX).clamp(0, width - 1).round();
  final y = (top - padY).clamp(0, height - 1).round();
  final w = ((right + padX).clamp(0, width) - x).round();
  final h = ((bottom + padY).clamp(0, height) - y).round();
  if (w < 8 || h < 8) return null;
  var crop = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  if (crop.width < 900) {
    crop = img.copyResize(
      crop,
      width: 900,
      interpolation: img.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(img.encodePng(crop));
}

/// The code of the close-up, only when its two spellings agree: one
/// character at a time and in groups of three. The count the model gives is
/// only a help to it: a list of twelve characters with «length: 11» was the
/// right code (2026-10-13), the count was the slip.
String? focusedTrackingCode(Map<String, dynamic> json) {
  final characters = json['characters'];
  if (characters is! List || characters.isEmpty) return null;
  final spelled = normalizeTrackingNumber(characters.join());
  final grouped = normalizeTrackingNumber(json['groups_of_three']?.toString());
  if (spelled == null || spelled != grouped) return null;
  return spelled;
}

const trackingCloseUpInstruction = '''
La imagen es un recorte ampliado de un comprobante de envío y muestra un
código de seguimiento. Transcríbelo exactamente como está impreso, sin
agregar ni quitar caracteres. Las series del mismo dígito (por ejemplo varios
ceros seguidos) se cuentan uno por uno.

- characters: el código, un carácter por elemento y en orden.
- length: cuántos caracteres tiene.
- groups_of_three: el código separado en grupos de tres desde la izquierda
  (por ejemplo "123 456 789 0").
''';

const trackingCloseUpSchema = <String, dynamic>{
  'type': 'OBJECT',
  'properties': {
    'characters': {
      'type': 'ARRAY',
      'items': {'type': 'STRING'},
    },
    'length': {'type': 'INTEGER'},
    'groups_of_three': {'type': 'STRING'},
  },
  'required': ['characters', 'length', 'groups_of_three'],
};
