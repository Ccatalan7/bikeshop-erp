import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_public_core/public_store/documents/delivery_warranty_pdf.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/store_document_logo.dart';

/// El comprobante de entrega y garantía de un trabajo, como lo ve el equipo:
/// la proyección que también lee el cliente en su cuenta
/// (`job_delivery_document_projection_internal`) más lo que sólo el equipo
/// necesita para mandarlo — si el cliente ya tiene cuenta y por dónde
/// escribirle.
@immutable
class DeliveryDocument {
  const DeliveryDocument({
    required this.projection,
    required this.jobId,
    required this.jobNumber,
    required this.customerName,
    required this.customerHasAccount,
    required this.customerPhone,
    required this.customerEmail,
    required this.serviceWarrantyDays,
    required this.serviceWarrantyExpiresAt,
    required this.serviceDaysRemaining,
    required this.partsWarrantyMonths,
    required this.partsWarrantyExpiresAt,
    required this.partsDaysRemaining,
    required this.showsPartsWarranty,
    required this.storeOrigin,
  });

  static DeliveryDocument? fromRpc(Object? raw) {
    if (raw is! Map) return null;
    final projection = Map<String, dynamic>.from(raw);
    final input = DeliveryWarrantyPdfInput.fromProjection(projection);
    final jobId = _text(projection['job_id']);
    if (input == null || jobId == null) return null;
    return DeliveryDocument(
      projection: projection,
      jobId: jobId,
      jobNumber: input.jobNumber,
      customerName: input.customerName,
      customerHasAccount: projection['customer_has_account'] == true,
      customerPhone: _text(projection['customer_phone']),
      customerEmail: _text(projection['customer_email']),
      serviceWarrantyDays: input.serviceWarrantyDays,
      serviceWarrantyExpiresAt: input.serviceWarrantyExpiresAt,
      serviceDaysRemaining:
          (projection['service_warranty_days_remaining'] as num?)?.toInt() ?? 0,
      partsWarrantyMonths: input.partsWarrantyMonths,
      partsWarrantyExpiresAt: input.partsWarrantyExpiresAt,
      partsDaysRemaining:
          (projection['parts_warranty_days_remaining'] as num?)?.toInt() ?? 0,
      showsPartsWarranty: input.showsPartsWarranty,
      storeOrigin: input.storeOrigin,
    );
  }

  final Map<String, dynamic> projection;
  final String jobId;
  final String jobNumber;
  final String? customerName;
  final bool customerHasAccount;
  final String? customerPhone;
  final String? customerEmail;
  final int serviceWarrantyDays;
  final DateTime serviceWarrantyExpiresAt;
  final int serviceDaysRemaining;
  final int partsWarrantyMonths;
  final DateTime partsWarrantyExpiresAt;
  final int partsDaysRemaining;

  /// Sin repuestos instalados no hay garantía de repuestos que mostrar.
  final bool showsPartsWarranty;

  /// La dirección de la tienda (`store_url` del editor del sitio): adonde
  /// lleva el QR. Sin ella no hay QR.
  final String? storeOrigin;

  /// El documento que se dibuja, con el QR para crear la cuenta si se pasa
  /// [claimUrl].
  DeliveryWarrantyPdfInput pdfInput({String? claimUrl}) =>
      DeliveryWarrantyPdfInput.fromProjection(
        projection,
        claimUrl: customerHasAccount ? null : claimUrl,
        hasAccount: customerHasAccount,
      )!;
}

/// Lo que devuelve sacar un código para ligar la cuenta del cliente.
@immutable
class CustomerClaimCode {
  const CustomerClaimCode({
    required this.status,
    this.code,
    this.expiresAt,
    this.storeOrigin,
    this.customerFirstName,
  });

  static CustomerClaimCode fromRpc(Object? raw) {
    if (raw is! Map) return const CustomerClaimCode(status: 'unknown');
    final origin = _text(raw['store_url']);
    return CustomerClaimCode(
      status: _text(raw['status']) ?? 'unknown',
      code: _text(raw['code']),
      expiresAt: DateTime.tryParse('${raw['expires_at'] ?? ''}'),
      storeOrigin: origin,
      customerFirstName: _text(raw['customer_first_name']),
    );
  }

  /// `issued`, `already_linked` (el cliente ya tiene cuenta) o `no_customer`.
  final String status;
  final String? code;
  final DateTime? expiresAt;

  /// `store_url` del editor del sitio: adonde lleva el QR.
  final String? storeOrigin;
  final String? customerFirstName;

  bool get issued => status == 'issued' && code != null;
  bool get alreadyLinked => status == 'already_linked';

  /// El enlace del QR, o null si la tienda no tiene dirección.
  String? get claimUrl {
    final origin = storeOrigin;
    final value = code;
    if (!issued || origin == null || value == null) return null;
    return customerPortalClaimUrl(origin, value);
  }
}

/// Por qué no se pudo armar el comprobante, en palabras del taller.
class DeliveryDocumentFailure implements Exception {
  const DeliveryDocumentFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Para qué se saca el código: el QR que se muestra en la recepción o el que
/// va en el comprobante de entrega.
enum CustomerClaimPurpose {
  reception('reception'),
  delivery('delivery');

  const CustomerClaimPurpose(this.dbValue);
  final String dbValue;
}

typedef DeliveryDocumentRpc = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
);

class DeliveryDocumentService {
  DeliveryDocumentService({DeliveryDocumentRpc? rpc}) : _rpc = rpc;

  final DeliveryDocumentRpc? _rpc;

  Future<Object?> _call(String name, Map<String, dynamic> params) {
    final rpc = _rpc;
    if (rpc != null) return rpc(name, params);
    return Supabase.instance.client.rpc(name, params: params);
  }

  /// El comprobante del trabajo [jobId]. Si el trabajo se entregó antes de
  /// que existiera el comprobante (o armarlo falló al entregar), la base lo
  /// arma ahora con la primera entrega (`ensure_job_delivery_document_v1`).
  Future<DeliveryDocument> ensure(String jobId) async {
    final Object? raw;
    try {
      raw = await _call('ensure_job_delivery_document_v1', {
        'p_job_id': jobId,
      });
    } on PostgrestException catch (error) {
      throw DeliveryDocumentFailure(describeRpcError(error.message));
    }
    final document = DeliveryDocument.fromRpc(raw);
    if (document == null) {
      throw const DeliveryDocumentFailure(
        'La base no devolvió un comprobante que se pueda dibujar.',
      );
    }
    return document;
  }

  /// Un código nuevo para que el cliente de [jobId] ligue su cuenta. Sólo se
  /// guarda su huella: el código vive en el QR que se dibuja ahora.
  Future<CustomerClaimCode> issueClaimCode(
    String jobId, {
    required CustomerClaimPurpose purpose,
  }) async {
    try {
      return CustomerClaimCode.fromRpc(
        await _call('issue_customer_portal_claim_code_v1', {
          'p_job_id': jobId,
          'p_purpose': purpose.dbValue,
        }),
      );
    } on PostgrestException catch (error) {
      throw DeliveryDocumentFailure(describeRpcError(error.message));
    }
  }

  /// Las palabras del taller para lo que responde la base.
  static String describeRpcError(String message) {
    if (message.contains('job_not_delivered')) {
      return 'El trabajo todavía no tiene una entrega registrada. Márcalo '
          'como entregado y vuelve a abrir el comprobante.';
    }
    if (message.contains('job_without_warranty')) {
      return 'Esta entrega no abre garantía (una venta o una garantía de '
          'otro trabajo): no lleva comprobante.';
    }
    if (message.contains('not found or not accessible')) {
      return 'No encontramos el trabajo en esta tienda.';
    }
    return 'No se pudo armar el comprobante. Revisa la conexión e intenta '
        'de nuevo.';
  }
}

/// El PDF del comprobante, dibujado por el núcleo compartido
/// ([buildDeliveryWarrantyPdf]) para que sea el mismo que el cliente
/// descarga de su cuenta, con el logo de la tienda
/// ([loadStoreDocumentLogo]).
Future<Uint8List> buildDeliveryWarrantyPdfBytes(
  DeliveryWarrantyPdfInput document,
) async {
  final regularFont = await rootBundle.load('assets/fonts/Barlow-Regular.ttf');
  final boldFont = await rootBundle.load('assets/fonts/Barlow-Bold.ttf');
  final logo = await loadStoreDocumentLogo(
    identityLogoUrl: document.logoUrl,
    tenantId: await _tenantId(),
  );
  return buildDeliveryWarrantyPdf(
    document,
    regularFont: regularFont,
    boldFont: boldFont,
    logo: logo,
  );
}

Future<String?> _tenantId() async {
  try {
    return await TenantService().getTenantId();
  } catch (_) {
    return null;
  }
}

String? _text(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
