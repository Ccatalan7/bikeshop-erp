import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/public_store/models/customer_portal_presentation.dart';
import 'package:vinabike_erp/public_store/pages/customer_dashboard_page.dart';
import 'package:vinabike_erp/public_store/widgets/customer_job_row.dart';
import 'package:vinabike_erp/public_store/widgets/customer_portal_style.dart';

/// Reglas del portal «Sendero» (2026-09-26): el avance del taller, el dibujo
/// de cada bici, el aviso de lo pendiente, el color de cada estado y las
/// fotos que el dueño elige en el editor.
OnlineOrder _order({
  required String status,
  required String payment,
  String? method,
  double total = 43990,
}) {
  final at = DateTime(2026, 9, 23);
  return OnlineOrder(
    id: 'o-1',
    tenantId: 't-1',
    orderNumber: 'WEB-26-00004',
    customerEmail: 'c@example.com',
    customerName: 'Cliente',
    subtotal: total,
    taxAmount: 0,
    shippingCost: 0,
    discountAmount: 0,
    total: total,
    status: status,
    paymentStatus: payment,
    paymentMethod: method,
    createdAt: at,
    updatedAt: at,
    items: [
      OnlineOrderItem(
        id: 'i-1',
        orderId: 'o-1',
        productId: 'p-1',
        productName: 'Cadena KMC X11',
        quantity: 2,
        unitPrice: total / 2,
        subtotal: total,
        createdAt: at,
      ),
    ],
  );
}

void main() {
  group('avance del taller', () {
    test('cada código cae en su paso; lo que no recorre pasos, en ninguno', () {
      int? step(String code) => customerWorkshopStep({'status': code});
      expect(step('PENDIENTE'), 0);
      expect(step('DIAGNOSTICO'), 1);
      expect(step('CONTACTAR'), 1);
      expect(step('ESPERANDO_APROBACION'), 2);
      expect(step('presupuesto'), 2);
      expect(step('EN_CURSO'), 3);
      expect(step('ESPERANDO_REPUESTOS'), 3);
      expect(step('FINALIZADO'), 4);
      expect(step('ENTREGADO'), customerWorkshopSteps.length);
      expect(step('CANCELADO'), isNull);
      expect(step('RETIRO_SIN_SERVICIO'), isNull);
      // Un código nuevo del taller no inventa un avance.
      expect(step('REVISION_EXTRA'), isNull);
    });
  });

  group('dibujo de la bici', () {
    test('sin tipo o «otra» se dibuja rígida, lo que más llega', () {
      expect(customerBikeSilhouette(null), CustomerBikeSilhouette.hardtail);
      expect(customerBikeSilhouette(''), CustomerBikeSilhouette.hardtail);
      expect(customerBikeSilhouette('other'), CustomerBikeSilhouette.hardtail);
      expect(customerBikeSilhouette('mountain_hardtail'),
          CustomerBikeSilhouette.hardtail);
      expect(customerBikeSilhouette('mountain'),
          CustomerBikeSilhouette.fullSuspension);
      expect(customerBikeSilhouette('road'), CustomerBikeSilhouette.road);
      expect(customerBikeSilhouette('gravel'), CustomerBikeSilhouette.road);
      expect(customerBikeSilhouette('paseo'), CustomerBikeSilhouette.city);
    });

    test('la etiqueta del tipo usa las palabras del ERP y calla «Otra»', () {
      expect(customerBikeTypeLabel('mountain_hardtail'), 'MTB hardtail');
      expect(customerBikeTypeLabel('paseo'), 'Paseo / Urbana');
      expect(customerBikeTypeLabel('other'), isNull);
      expect(customerBikeTypeLabel(null), isNull);
    });
  });

  group('aviso de lo pendiente', () {
    final approval = {
      'id': 'j-1',
      'status': 'ESPERANDO_APROBACION',
      'bike_brand': 'Trek',
      'bike_model': 'Marlin 7',
    };
    final repairing = {'id': 'j-2', 'status': 'EN_CURSO'};

    test('un trabajo que espera al cliente va antes que un pedido', () {
      final action = CustomerPendingAction.first(
        orders: [
          _order(status: 'pending', payment: 'pending', method: 'transfer')
        ],
        jobs: [repairing, approval],
      );
      expect(action, isNotNull);
      expect(action!.status, 'Espera tu aprobación');
      expect(action.subject, 'Trek Marlin 7');
      expect(action.job, same(approval));
    });

    test('sin trabajos pendientes, el pedido que espera su pago', () {
      final action = CustomerPendingAction.first(
        orders: [
          _order(status: 'pending', payment: 'pending', method: 'transfer')
        ],
        jobs: [repairing],
      );
      expect(action!.status, 'Esperando transferencia');
      expect(action.subject, 'Pedido WEB-26-00004');
      expect(action.order, isNotNull);
    });

    test('nada que hacer, nada que avisar', () {
      expect(
        CustomerPendingAction.first(
          orders: [
            _order(status: 'delivered', payment: 'paid', method: 'transfer')
          ],
          jobs: [repairing],
        ),
        isNull,
      );
    });
  });

  group('pedido en grande', () {
    test('una transferencia pendiente dice qué hacer y cuánto', () {
      final order =
          _order(status: 'pending', payment: 'pending', method: 'transfer');
      expect(CustomerOrderPresentation.of(order).awaitsTransfer, isTrue);
      final copy = CustomerOrderPresentation.feature(
        order,
        formattedTotal: r'$43.990',
      );
      expect(copy.headline, r'Transfiere $43.990');
      expect(copy.message, contains('apenas veamos el pago'));
      expect(CustomerOrderPresentation.unitCount(order), 2);
    });

    test('un pedido entregado no pide nada', () {
      final order =
          _order(status: 'delivered', payment: 'paid', method: 'transfer');
      expect(CustomerOrderPresentation.of(order).awaitsTransfer, isFalse);
      final copy = CustomerOrderPresentation.feature(
        order,
        formattedTotal: r'$43.990',
      );
      expect(copy.headline, 'Cadena KMC X11');
      expect(copy.message, isNull);
    });
  });

  group('frase del trabajo en grande', () {
    test('espera aprobación con monto: el presupuesto y lo que se pidió', () {
      final message = customerJobMessage({
        'status': 'ESPERANDO_APROBACION',
        'client_request': 'Cambio de maneta izquierda +DIAGNÓSTICO',
        'total_cost': 10000,
      });
      expect(message, startsWith('Presupuesto de '));
      expect(
          message, endsWith('por cambio de maneta izquierda · Diagnóstico.'));
    });

    test('en reparación: lo que se pidió, sin monto', () {
      expect(
        customerJobMessage({
          'status': 'EN_CURSO',
          'client_request': '+Purga de frenos',
          'total_cost': 30000,
        }),
        'Purga de frenos',
      );
    });
  });

  test('el color de un estado dice quién tiene que moverse', () {
    expect(
      portalStatusTagKind(PortalTone.warning,
          needsCustomer: true, active: true),
      PortalTagKind.attention,
    );
    expect(
      portalStatusTagKind(PortalTone.success,
          needsCustomer: true, active: true),
      PortalTagKind.success,
    );
    expect(
      portalStatusTagKind(PortalTone.danger, needsCustomer: true, active: true),
      PortalTagKind.danger,
    );
    // «Pago en proceso» es naranjo de tono, pero no espera al cliente.
    expect(
      portalStatusTagKind(PortalTone.warning,
          needsCustomer: false, active: true),
      PortalTagKind.ink,
    );
    expect(
      portalStatusTagKind(PortalTone.success,
          needsCustomer: false, active: false),
      PortalTagKind.outline,
    );
    expect(
      portalStatusTagKind(PortalTone.neutral,
          needsCustomer: false, active: false),
      PortalTagKind.quiet,
    );
  });

  test('la franja del resumen no dice ceros', () {
    expect(
      customerDashboardBandMeta(
        profile: {'created_at': '2025-09-02T13:00:00Z'},
        bikes: 2,
        orders: 0,
      ),
      'Cliente desde septiembre de 2025\n2 bicicletas',
    );
    expect(
      customerDashboardBandMeta(profile: const {}, bikes: 0, orders: 1),
      '1 pedido',
    );
    expect(
      customerDashboardBandMeta(profile: null, bikes: 0, orders: 0),
      isNull,
    );
  });

  test('las fotos del portal salen del editor y sólo si son http(s)', () {
    WebsiteResolvedTheme resolve(String hero, String workshop) =>
        WebsiteResolvedTheme.resolve((key, fallback) => switch (key) {
              WebsiteResolvedTheme.customerPortalImageKey => hero,
              WebsiteResolvedTheme.customerPortalWorkshopImageKey => workshop,
              _ => fallback,
            });

    final theme = resolve(
      ' https://example.com/sendero.webp ',
      'http://example.com/taller.webp',
    );
    expect(theme.customerPortalImage, 'https://example.com/sendero.webp');
    expect(theme.customerPortalWorkshopImage, 'http://example.com/taller.webp');

    final bad = resolve('javascript:alert(1)', 'assets/taller.png');
    expect(bad.customerPortalImage, isEmpty);
    expect(bad.customerPortalWorkshopImage, isEmpty);
    expect(WebsiteResolvedTheme.fallback.customerPortalImage, isEmpty);
  });
}
