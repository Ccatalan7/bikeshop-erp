import 'package:flutter/services.dart';
import 'package:vinabike_public_core/public_store/documents/purchase_order_pdf.dart';

import '../../modules/settings/services/appearance_service.dart';
import '../services/tenant_service.dart';
import 'store_document_logo.dart';

/// **El pedido que se le manda al proveedor.**
///
/// No es `PurchaseDocumentPdfGenerator`. Ése imprime el documento que el
/// proveedor **nos** emitió —tiene «saldo adeudado» y habla de una deuda ya
/// contraída—; esto es lo contrario: lo que le pedimos antes de que exista
/// factura alguna. Mandarle su propia plantilla de deuda a un proveedor es
/// pedirle plata en vez de mercadería.
///
/// Lo dibuja el núcleo compartido ([buildPurchaseOrderPdf]) con el membrete de
/// la tienda, el mismo que dibuja el servidor cuando el pedido abierto sale
/// solo en la mañana (20261122030000): el proveedor recibe el mismo papel lo
/// mande el operador o lo mande la base.
class PurchaseOrderPdfGenerator {
  const PurchaseOrderPdfGenerator._();

  static String fileNameFor(PurchaseOrderDocument document) =>
      document.fileName;

  /// [appearanceService] aporta el logo de la empresa sólo si el sitio no
  /// tiene uno: el membrete sigue la regla de los documentos de la tienda
  /// ([loadStoreDocumentLogo]).
  static Future<Uint8List> generateBytes(
    PurchaseOrderDocument document, {
    required AppearanceService appearanceService,
  }) async {
    final regularFont =
        await rootBundle.load('assets/fonts/Barlow-Regular.ttf');
    final boldFont = await rootBundle.load('assets/fonts/Barlow-Bold.ttf');
    String? tenantId;
    try {
      tenantId = await TenantService().getTenantId();
    } catch (_) {
      tenantId = null;
    }
    // Un logo que no baja no puede impedir que salga el pedido: sin él, el
    // membrete escribe el nombre.
    final logo = await loadStoreDocumentLogo(
      identityLogoUrl: document.logoUrl,
      tenantId: tenantId,
      fallbackUrl: appearanceService.companyLogoUrl,
    );
    return buildPurchaseOrderPdf(
      document,
      regularFont: regularFont,
      boldFont: boldFont,
      logo: logo,
    );
  }
}
