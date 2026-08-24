import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_order_document.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_order_draft.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_order_message.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_catalog.dart';

/// El pedido que ve el operador y el que recibe el proveedor son el mismo.
///
/// La vista previa en pantalla y el PDF salen del mismo [PurchaseOrderDocument]
/// justamente para que no puedan divergir. Estas pruebas afirman lo que ese
/// documento decide: los totales, la marca del costo no pagado y las palabras
/// del mensaje.
SupplierProfile _supplier({
  String? phone = '+56900000000',
  String? rut = '76.543.210-9',
}) {
  return SupplierProfile(
    id: 's1',
    name: 'RBX',
    legalName: 'Rafael Burgos S.A.',
    rut: rut,
    city: 'Santiago',
    website: 'https://rbx.cl',
    imageUrl: null,
    paymentTerms: 'prepaid',
    purchaseInstructions: null,
    salesRepName: 'Paul Calderón',
    salesRepPhone: phone,
    salesRepEmail: 'paul@rbx.cl',
    hasPortalAccount: true,
  );
}

SupplierCatalogItem _item({
  required String id,
  required String name,
  double? landed,
  double? catalogCost,
}) {
  return SupplierCatalogItem(
    productId: id,
    name: name,
    sku: 'SKU-$id',
    brand: 'RBX',
    categoryPath: null,
    origin: landed == null
        ? SupplierCatalogOrigin.catalogued
        : SupplierCatalogOrigin.purchased,
    timesPurchased: landed == null ? 0 : 2,
    totalQuantity: landed == null ? null : 4,
    lastPurchaseAt: landed == null ? null : DateTime(2026, 6, 1),
    lastInvoiceNumber: landed == null ? null : '754591',
    lastLandedUnitCostNet: landed,
    lastBaseUnitCostNet: landed,
    catalogCostNet: catalogCost,
    available: 2,
    imageUrl: null,
    matchesNeed: false,
  );
}

PurchaseOrderDraft _draft(List<SupplierCatalogItem> items, {SupplierProfile? supplier}) {
  return PurchaseOrderDraft(
    supplier: supplier ?? _supplier(),
    lines: {
      for (final item in items)
        item.productId: PurchaseOrderDraftLine.fromCatalog(item),
    },
  );
}

void main() {
  group('el pedido calcula lo que se va a firmar', () {
    test('neto, IVA y total salen de las líneas', () {
      final draft = _draft([
        _item(id: 'a', name: 'Cámara 26', landed: 2791),
        _item(id: 'b', name: 'Cámara 27,5', landed: 3983),
      ]);

      expect(draft.netTotal, 6774);
      expect(draft.ivaAmount, closeTo(1287.06, 0.01));
      expect(draft.total, closeTo(8061.06, 0.01));
      expect(draft.unitCount, 2);
    });

    test('lo pagado manda sobre el costo de ficha', () {
      final item = _item(
        id: 'a',
        name: 'Cámara 26',
        landed: 2791,
        catalogCost: 9999,
      );
      final line = PurchaseOrderDraftLine.fromCatalog(item);

      expect(line.unitCostNet, 2791);
      expect(line.costIsFromCatalog, isFalse);
    });

    test('sin compras, el costo de ficha viaja MARCADO', () {
      // Un costo que nadie pagó, presentado como precio pactado, es cómo se
      // llega a una factura que no cuadra.
      final draft = _draft([
        _item(id: 'a', name: 'Nunca comprada', catalogCost: 1500),
      ]);

      expect(draft.lines['a']!.costIsFromCatalog, isTrue);
      expect(draft.unverifiedCostLines, 1);

      final document = PurchaseOrderDocument.fromDraft(draft);
      expect(document.unverifiedCostLines, 1);
      expect(document.lines.single.costIsFromCatalog, isTrue);
    });

    test('editar el costo a mano deja de ser «de ficha»', () {
      final line = PurchaseOrderDraftLine.fromCatalog(
        _item(id: 'a', name: 'Nunca comprada', catalogCost: 1500),
      ).copyWith(unitCostNet: 1200);

      expect(line.costIsFromCatalog, isFalse);
    });

    test('sin guardar no hay folio: se dice «sin número», no se inventa uno',
        () {
      final document = PurchaseOrderDocument.fromDraft(
        _draft([_item(id: 'a', name: 'Cámara', landed: 1000)]),
      );

      expect(document.isDraft, isTrue);
      expect(document.orderNumber, 'Sin número');
    });

    test('con folio guardado, el documento lo cita', () {
      final document = PurchaseOrderDocument.fromDraft(
        _draft([_item(id: 'a', name: 'Cámara', landed: 1000)]),
        orderNumber: 'PED-202608-0001',
      );

      expect(document.isDraft, isFalse);
      expect(document.orderNumber, 'PED-202608-0001');
    });

    test('el orden del documento es el orden en que se armó', () {
      final draft = _draft([
        _item(id: 'a', name: 'Primera', landed: 1000),
        _item(id: 'b', name: 'Segunda', landed: 2000),
      ]);

      expect(
        draft.orderedLines.map((line) => line.name),
        ['Primera', 'Segunda'],
      );
    });
  });

  group('el mensaje dice lo que lleva', () {
    test('nombra el folio, el total y las primeras líneas', () {
      final document = PurchaseOrderDocument.fromDraft(
        _draft([
          _item(id: 'a', name: 'Cámara 26', landed: 2791),
          _item(id: 'b', name: 'Cámara 27,5', landed: 3983),
        ]),
        orderNumber: 'PED-202608-0001',
      );
      final message = PurchaseOrderMessage.forDocument(
        document,
        recipientName: 'Paul Calderón',
        recipientPhone: '+56900000000',
        attachmentName: 'pedido_PED-202608-0001.pdf',
        windowIsOpen: true,
      );

      expect(message.body, contains('Hola Paul'));
      expect(message.body, contains('PED-202608-0001'));
      expect(message.body, contains('Cámara 26'));
      expect(message.body, contains(document.total));
    });

    test('con muchas líneas dice cuántas quedaron en el archivo', () {
      final document = PurchaseOrderDocument.fromDraft(
        _draft([
          for (var i = 0; i < 6; i++)
            _item(id: '$i', name: 'Producto $i', landed: 1000),
        ]),
        orderNumber: 'PED-202608-0002',
      );
      final message = PurchaseOrderMessage.forDocument(
        document,
        recipientName: 'Paul',
        recipientPhone: '+56900000000',
        attachmentName: 'x.pdf',
        windowIsOpen: true,
      );

      expect(message.body, contains('3 productos más'));
    });

    test('fuera de las 24 horas lo dice, en vez de prometer el texto', () {
      // Dibujar la burbuja como si fuera a salir tal cual, cuando WhatsApp sólo
      // deja una plantilla, es mentir sobre lo que el proveedor va a leer.
      final document = PurchaseOrderDocument.fromDraft(
        _draft([_item(id: 'a', name: 'Cámara', landed: 1000)]),
        orderNumber: 'PED-1',
      );
      final cerrada = PurchaseOrderMessage.forDocument(
        document,
        recipientName: 'Paul',
        recipientPhone: '+56900000000',
        attachmentName: 'x.pdf',
        windowIsOpen: false,
      );

      expect(cerrada.deliveryCaveat, contains('plantilla'));
      expect(cerrada.deliveryCaveat, contains('24 horas'));
    });
  });

  group('sin teléfono no hay envío', () {
    test('el perfil lo dice antes del último paso', () {
      // 25 de 91 proveedores tienen teléfono. Descubrirlo al apretar «enviar»
      // es descubrirlo tarde.
      expect(_supplier().canReceiveMessage, isTrue);
      expect(_supplier(phone: null).canReceiveMessage, isFalse);
      expect(_supplier(phone: '   ').canReceiveMessage, isFalse);
    });
  });
}
