import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
import 'package:vinabike_erp/public_store/models/customer_portal_presentation.dart';
import 'package:vinabike_erp/public_store/pages/customer_dashboard_page.dart';
import 'package:vinabike_erp/public_store/pages/customer_orders_page.dart';
import 'package:vinabike_erp/public_store/theme/public_store_theme.dart';

/// Portal de clientes (`/cuenta`): qué palabra ve el cliente para cada pedido
/// y cada trabajo de taller, y que el resumen y «Pedidos» se armen sin
/// desbordar en teléfono y escritorio.
void main() {
  group('pedido', () {
    CustomerOrderPresentation of(
      String status,
      String payment, {
      String method = 'transfer',
    }) =>
        CustomerOrderPresentation.of(
          _order(status: status, paymentStatus: payment, paymentMethod: method),
        );

    test('cancelado manda sobre un pago pendiente que quedó viejo', () {
      // WEB-26-00019 en producción: cancelado, pago «pending». El portal
      // mostraba «Pago pendiente» y el cliente creía que debía plata.
      final p = of('cancelled', 'pending', method: 'mercadopago');
      expect(p.label, 'Cancelado');
      expect(p.group, CustomerOrderGroup.cancelled);
      expect(p.needsCustomer, isFalse);
    });

    test('pago y entrega en palabras del cliente', () {
      expect(of('confirmed', 'pending').label, 'Esperando transferencia');
      expect(of('confirmed', 'pending').needsCustomer, isTrue);
      expect(of('pending', 'pending', method: 'mercadopago').label,
          'Pago en proceso');
      expect(of('pending', 'failed', method: 'mercadopago').label,
          'Pago rechazado');
      expect(
          of('pending', 'failed', method: 'mercadopago').needsCustomer, isTrue);
      expect(of('processing', 'paid').label, 'En preparación');
      expect(of('shipped', 'paid').label, 'En camino');
      expect(of('ready_for_pickup', 'paid').label, 'Listo para retirar');
      expect(of('ready_for_pickup', 'paid').needsCustomer, isTrue);
      expect(of('delivered', 'paid').label, 'Entregado');
      expect(of('delivered', 'paid').group, CustomerOrderGroup.delivered);
    });

    test('resume los productos por su nombre', () {
      expect(CustomerOrderPresentation.itemsSummary(_order()),
          'Sin detalle de productos');
      expect(
        CustomerOrderPresentation.itemsSummary(
          _order(items: ['Aceite mineral Shimano']),
        ),
        'Aceite mineral Shimano',
      );
      expect(
        CustomerOrderPresentation.itemsSummary(
          _order(items: ['Cadena KMC X11', 'Cámara 29', 'Parche']),
        ),
        'Cadena KMC X11 y 2 más',
      );
    });
  });

  group('taller', () {
    // Los códigos de job_statuses de Viñabike el 2026-09-24.
    const productionCodes = [
      'ESPERANDO_APROBACION', 'PENDIENTE', 'RETIRO_SIN_SERVICIO',
      'DIAGNOSTICO', 'CONTACTAR', 'FINALIZADO', 'ESPERANDO_REPUESTOS',
      'PROBADO', 'EN_CURSO', 'ENTREGADO', 'COMENZAR', 'CANCELADO',
      'PRESUPUESTO', 'GARANTA', 'EN_PAUSA', 'DESGLOSAR', //
    ];

    test('ningún código del taller llega crudo al cliente', () {
      for (final code in productionCodes) {
        final label = CustomerWorkshopPresentation.of({'status': code}).label;
        expect(label, isNot(contains('_')), reason: code);
        expect(label, isNot(equals(label.toUpperCase())), reason: code);
        expect(label, isNot('En el taller'),
            reason: '$code tiene su propia frase');
      }
    });

    test('lo entregado, retirado o cancelado ya no está en curso', () {
      for (final code in ['ENTREGADO', 'RETIRO_SIN_SERVICIO', 'CANCELADO']) {
        expect(
            CustomerWorkshopPresentation.of({'status': code}).isActive, isFalse,
            reason: code);
      }
      expect(CustomerWorkshopPresentation.of({'status': 'EN_PAUSA'}).isActive,
          isTrue);
    });

    test('lo que espera al cliente se marca', () {
      expect(
        CustomerWorkshopPresentation.of({'status': 'FINALIZADO'}).label,
        'Lista para retirar',
      );
      expect(
        CustomerWorkshopPresentation.of({'status': 'FINALIZADO'}).needsCustomer,
        isTrue,
      );
      expect(
        CustomerWorkshopPresentation.of({'status': 'ESPERANDO_APROBACION'})
            .needsCustomer,
        isTrue,
      );
      expect(
        CustomerWorkshopPresentation.of({
          'status': 'ESPERANDO_APROBACION',
          'approved_by_customer': true,
        }).needsCustomer,
        isFalse,
      );
    });

    test('un código nuevo del taller se lee como «En el taller»', () {
      final p = CustomerWorkshopPresentation.of({'status': 'LAVADO'});
      expect(p.label, 'En el taller');
      expect(p.isActive, isTrue);
    });

    test('lo pedido sale de client_request, en una línea', () {
      // Tal como los anota el taller (PG-00574, PG-00575, PG-00573).
      String of(String raw) =>
          CustomerWorkshopPresentation.requestSummary({'client_request': raw});
      expect(
        of('+Enrayado rueda delantera.\n+Mantención para maza trasera.'),
        'Enrayado rueda delantera · Mantención para maza trasera',
      );
      expect(
        of('Cambio de maneta izquierda +Diagnostico'),
        'Cambio de maneta izquierda · Diagnostico',
      );
      expect(of('DIAGNÓSTICO'), 'Diagnóstico');
      expect(of('   '), '');
      expect(
        CustomerWorkshopPresentation.requestSummary(
            {'description': 'no existe en mechanic_jobs'}),
        '',
      );
    });

    test('el total es el primero con precio', () {
      expect(
        CustomerWorkshopPresentation.total(
            {'total_cost': 0, 'final_cost': 0, 'estimated_cost': 0}),
        isNull,
      );
      expect(
        CustomerWorkshopPresentation.total({'total_cost': '16000.00'}),
        16000,
      );
      expect(
        CustomerWorkshopPresentation.total(
            {'total_cost': 0, 'estimated_cost': 32000}),
        32000,
      );
    });
  });

  group('bicicleta', () {
    test('tipo con las palabras del ERP, color y aro', () {
      final details = customerBikeDetails({
        'color': 'negra',
        'wheel_size': "29''",
        'bike_type': 'mountain_hardtail',
      });
      expect(details, 'MTB hardtail · Negra · aro 29');
      expect(customerBikeDetails({'bike_type': 'other'}), '',
          reason: '«Otra» no dice nada');
      expect(customerBikeDetails({'bike_type': 'gravel'}), 'Gravel');
      expect(customerBikeDetails(const {}), '');
    });

    test('el aro se escribe de una sola manera', () {
      expect(customerWheelSize('29"'), '29');
      expect(customerWheelSize("26''"), '26');
      expect(customerWheelSize('700'), '700c');
      expect(customerWheelSize('27,5'), '27.5');
      expect(customerWheelSize(''), isNull);
      expect(customerWheelSize(null), isNull);
    });

    test('servicios y último ingreso', () {
      expect(customerBikeServiceSummary(const {}), 'Sin servicios todavía');
      expect(
        customerBikeServiceSummary({
          'service_count': 3,
          'last_service_date': '2026-09-12T15:00:00Z',
        }),
        '3 servicios · último 12 sep 2026',
      );
    });
  });

  group('conversación', () {
    test('título, último mensaje y quién lo escribió', () {
      final p = CustomerConversationPresentation.of(
        {
          'title': 'Chat: Factura #FV-00573',
          'status': 'active',
          'messages': [
            {
              'content': 'Hola, ¿ya está?',
              'sender_id': 'me',
              'created_at': '2026-09-20T10:00:00Z',
            },
            {
              'content': 'Sí,  lista\npara retirar',
              'sender_id': 'staff',
              'created_at': '2026-09-21T10:00:00Z',
            },
          ],
        },
        currentUserId: 'me',
      );
      expect(p.title, 'Factura #FV-00573');
      expect(p.preview, 'Sí, lista para retirar');
      expect(p.statusLabel, isNull, reason: 'abierta es lo normal');

      final mine = CustomerConversationPresentation.of(
        {
          'status': 'pending',
          'messages': [
            {'content': 'Necesito una cámara', 'sender_id': 'me'},
          ],
        },
        currentUserId: 'me',
      );
      expect(mine.title, 'Consulta');
      expect(mine.preview, 'Tú: Necesito una cámara');
      expect(mine.statusLabel, 'Esperando al equipo');
    });

    test('hoy, ayer o la fecha', () {
      final now = DateTime(2026, 9, 25, 18);
      expect(portalRelativeDay(DateTime(2026, 9, 25, 9), now: now), 'hoy');
      expect(portalRelativeDay(DateTime(2026, 9, 24, 23), now: now), 'ayer');
      expect(
          portalRelativeDay(DateTime(2026, 9, 2, 9), now: now), '2 sep 2026');
    });
  });

  group('nombre', () {
    test('el relleno y el correo no son un nombre', () {
      expect(customerFirstName({'name': 'Usuario'}), isNull);
      expect(customerFirstName({'name': 'cliente'}), isNull);
      expect(customerFirstName({'name': ''}), isNull);
      expect(customerFirstName(null), isNull);
      expect(
        customerFirstName(
            {'name': 'vinabikechile', 'email': 'vinabikechile@gmail.com'}),
        isNull,
      );
      expect(customerFirstName({'name': 'Andrés Pérez'}), 'Andrés');
    });

    test('fechas en castellano sin depender del locale cargado', () {
      expect(portalDate(DateTime(2026, 7, 19, 12)), '19 jul 2026');
      expect(portalMonthYear(DateTime(2025, 9, 3)), 'septiembre de 2025');
    });
  });

  group('pantallas', () {
    final orders = [
      _order(
        id: 'o-1',
        number: 'WEB-26-00019',
        status: 'cancelled',
        paymentStatus: 'pending',
        paymentMethod: 'mercadopago',
        items: ['Cubierta Maxxis Minion DHF 29 x 2.5 WT EXO+ TR'],
      ),
      _order(
        id: 'o-2',
        number: 'WEB-26-00004',
        status: 'confirmed',
        paymentStatus: 'pending',
        paymentMethod: 'transfer',
        items: ['Cadena KMC X11', 'Parche'],
      ),
    ];
    final jobs = [
      {
        'status': 'ESPERANDO_REPUESTOS',
        'bike_brand': 'Specialized',
        'bike_model': 'Rockhopper Comp 29',
        'created_at': '2026-09-12T15:00:00Z',
      },
    ];

    for (final width in [375.0, 820.0]) {
      testWidgets('resumen a $width px', (tester) async {
        await _pump(
          tester,
          width,
          CustomerDashboardBody(
            profile: const {
              'name': 'Usuario',
              'email': 'vinabikechile@gmail.com',
              'created_at': '2025-09-03T12:00:00Z',
            },
            orders: orders,
            orderImages: const {},
            jobs: jobs,
            bikes: const [],
            addressesCount: 0,
            onNavigate: (_) {},
          ),
        );
        expect(tester.takeException(), isNull);
        // El saludo y «Cliente desde…» van en la franja del marco
        // (`customerDashboardBandMeta`); el cuerpo pide el nombre.
        expect(find.text('COMPLETAR PERFIL'), findsOneWidget);
        // Lo que espera al cliente, en grande; lo demás en curso, también.
        expect(find.text('PARA TI AHORA'), findsOneWidget);
        expect(find.text('ESPERANDO TRANSFERENCIA'), findsOneWidget);
        expect(find.text('EN CURSO'), findsOneWidget);
        expect(find.text('ESPERANDO REPUESTOS'), findsOneWidget);
        expect(find.text('CANCELADO'), findsOneWidget);
        expect(find.text('PAGO PENDIENTE'), findsNothing);
        expect(find.textContaining('Usuario'), findsNothing);
      });

      testWidgets('pedidos a $width px', (tester) async {
        CustomerOrderGroup? selected;
        await _pump(
          tester,
          width,
          CustomerOrdersBody(
            orders: orders,
            orderImages: const {},
            group: null,
            onGroupChanged: (group) => selected = group,
            onNavigate: (_) {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('TODOS'), findsOneWidget);
        expect(find.text('EN CURSO'), findsOneWidget);
        expect(find.text('CANCELADOS'), findsOneWidget);
        expect(find.text('ENTREGADOS'), findsNothing,
            reason: 'sin pedidos entregados no hay pestaña vacía');
        await tester.tap(find.text('CANCELADOS'));
        expect(selected, CustomerOrderGroup.cancelled);
      });
    }
  });
}

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = WebsiteThemeBuilder.build(
    base: PublicStoreTheme.theme,
    resolved: WebsiteResolvedTheme.resolve((key, fallback) => fallback),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

OnlineOrder _order({
  String id = 'order-1',
  String number = 'WEB-26-00019',
  String status = 'confirmed',
  String paymentStatus = 'pending',
  String paymentMethod = 'transfer',
  List<String> items = const [],
}) {
  final createdAt = DateTime.utc(2026, 7, 18, 19);
  return OnlineOrder(
    id: id,
    tenantId: '',
    orderNumber: number,
    customerEmail: '',
    customerName: '',
    subtotal: 10000,
    taxAmount: 1597,
    shippingCost: 0,
    discountAmount: 0,
    total: 43990,
    status: status,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    createdAt: createdAt,
    updatedAt: createdAt,
    items: [
      for (var i = 0; i < items.length; i++)
        OnlineOrderItem(
          id: '$id-$i',
          orderId: id,
          productId: 'p-$i',
          productName: items[i],
          quantity: 1,
          unitPrice: 10000,
          subtotal: 10000,
          createdAt: createdAt,
        ),
    ],
  );
}
