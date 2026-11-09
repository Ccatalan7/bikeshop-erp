import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  group('getRouteTitle workshop routes', () {
    test('recognizes the canonical job detail route and ignores its query', () {
      expect(
        getRouteTitle('/taller/pegas/job-123?from=chat'),
        'Detalle Trabajo',
      );
    });

    test('keeps the former singular job detail spelling compatible', () {
      expect(getRouteTitle('/taller/pega/job-123'), 'Detalle Trabajo');
    });

    // 2026-11-02: a new job read «Detalle Trabajo», as if `nueva` were an id.
    test('a new job is not a job detail', () {
      expect(getRouteTitle('/taller/pegas/nueva'), 'Nuevo Trabajo');
      expect(
          getRouteTitle('/taller/pegas/nueva?type=quotation'), 'Nuevo Trabajo');
    });

    test('recognizes canonical and legacy edit spellings', () {
      expect(getRouteTitle('/taller/pegas/job-123/edit'), 'Editar Trabajo');
      expect(getRouteTitle('/taller/pega/job-123/editar'), 'Editar Trabajo');
    });
  });

  // 2026-10-14: the «Envíos» tab read «Shipping», the path's last word.
  group('getRouteTitle website routes', () {
    test('every Sitio Web page has its name, not its path', () {
      expect(getRouteTitle('/website/shipping'), 'Envíos');
      expect(getRouteTitle('/website/destinations'), 'Destinos y enlaces');
      expect(getRouteTitle('/website/settings'), 'Configuración del sitio');
      expect(getRouteTitle('/website/integrations'), 'Integraciones');
      expect(getRouteTitle('/website/seo'), 'SEO');
    });
  });

  // 2026-11-02: a quote opened from a notice read «QUOTES», the path's word.
  group('getRouteTitle sales routes', () {
    test('a quote has its name in the tab, not its path', () {
      expect(getRouteTitle('/sales/quotes'), 'Cotizaciones');
      expect(
        getRouteTitle('/sales/quotes/0b6e3c1a-4d5e-4f60-8a71-000000000001'),
        'Cotización',
      );
    });
  });

  // 2026-11-08: the purchase list tab read «RECEIPTS» and the list itself
  // «Purchases»; the screen is «Facturas de compra».
  group('getRouteTitle purchase routes', () {
    const id = '0b6e3c1a-4d5e-4f60-8a71-000000000002';

    test('the purchase list and its documents have names, not paths', () {
      expect(getRouteTitle('/purchases'), 'Facturas de compra');
      expect(getRouteTitle('/purchases?status=paid'), 'Facturas de compra');
      expect(getRouteTitle('/purchases/new'), 'Nuevo documento');
      expect(getRouteTitle('/purchases/$id'), 'Factura de compra');
      expect(getRouteTitle('/purchases/$id/detail'), 'Factura de compra');
      expect(getRouteTitle('/purchases/$id/edit'), 'Editar factura de compra');
      expect(getRouteTitle('/purchases/receipts/$id'), 'Recepción');
      expect(getRouteTitle('/purchases/payments/$id'), 'Pago a proveedor');
      expect(
        getRouteTitle('/purchases/payments/$id/edit'),
        'Editar pago a proveedor',
      );
    });

    test('the other purchase pages keep their own names', () {
      expect(getRouteTitle('/purchases/payments'), 'Pagos a Proveedores');
      expect(getRouteTitle('/purchases/suppliers'), 'Proveedores');
      expect(getRouteTitle('/purchases/suppliers/$id'), 'Proveedor');
      expect(getRouteTitle('/purchases/assistant'), 'Asistente de Compras');
    });
  });

  group('getRouteTitle payroll routes', () {
    test('keeps the canonical payroll workspace title localized', () {
      expect(getRouteTitle('/hr/payroll'), 'Nóminas');
      expect(getRouteTitle('/hr/payroll?scope=history'), 'Nóminas');
    });

    test('keeps reconciliation distinct from the payroll queue', () {
      expect(
        getRouteTitle('/hr/payroll/reconcile'),
        'Importar cartola',
      );
      expect(
        getRouteTitle('/hr/payroll/reconcile?import=statement-1'),
        'Importar cartola',
      );
    });
  });
}
