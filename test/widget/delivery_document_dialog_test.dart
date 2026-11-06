// El comprobante de entrega en el ERP (20261104200000…240000): arma el
// documento con la base, saca el código del QR sólo si el cliente no tiene
// cuenta, muestra lo que queda de garantía y, si algo falla, lo dice dentro
// del diálogo con un reintento.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/delivery_document_policy.dart';
import 'package:vinabike_erp/modules/bikeshop/services/delivery_document_service.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/delivery_document_dialog.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_public_core/public_store/documents/delivery_warranty_pdf.dart';

Map<String, dynamic> _projection({
  bool hasAccount = false,
  String? phone,
  bool withPart = true,
}) =>
    {
      'id': 'doc-1',
      'job_id': 'job-1',
      'job_number': 'PG-26-00412',
      'delivered_at': '2026-11-04T19:30:00+00:00',
      'service_warranty_days': 14,
      'service_warranty_expires_at': '2026-11-18T19:30:00+00:00',
      'service_warranty_days_remaining': 9,
      'parts_warranty_months': 2,
      'parts_warranty_expires_at': '2027-01-04T19:30:00+00:00',
      'parts_warranty_days_remaining': 61,
      'snapshot': {
        'customer': {'name': 'Dora Pérez'},
        'lines': [
          {'kind': 'service', 'name': 'Mantención completa', 'quantity': 1},
          if (withPart) {'kind': 'part', 'name': 'Pastillas', 'quantity': 2},
        ],
      },
      'storefront': {
        'schemaVersion': 1,
        'displayName': 'Viñabike',
        'storeUrl': 'https://vinabike.cl',
      },
      'customer_has_account': hasAccount,
      'customer_phone': phone,
      'customer_email': null,
    };

class _Rpc {
  _Rpc(this.answers);

  final Map<String, Object? Function(Map<String, dynamic>)> answers;
  final calls = <(String, Map<String, dynamic>)>[];

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    final answer = answers[name];
    if (answer == null) throw StateError('unexpected $name');
    return answer(params);
  }
}

Future<void> _pump(WidgetTester tester, DeliveryDocumentService service) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: DeliveryDocumentDialog(
        jobId: 'job-1',
        service: service,
        previewBuilder: (context, bytes, fileName) =>
            Text('vista previa $fileName (${bytes.length > 0})'),
      ),
    ),
  ));
  // The PDF is drawn off the frame: let it finish.
  for (var i = 0; i < 40; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    if (find.textContaining('vista previa').evaluate().isNotEmpty ||
        find.text('Reintentar').evaluate().isNotEmpty) {
      break;
    }
  }
}

void main() {
  testWidgets(
      'sin cuenta: arma el comprobante con un código de entrega y muestra lo '
      'que queda de garantía', (tester) async {
    final rpc = _Rpc({
      'ensure_job_delivery_document_v1': (_) =>
          _projection(phone: '+56 9 1234 5678'),
      'issue_customer_portal_claim_code_v1': (_) => {
            'status': 'issued',
            'code': 'q1w2e3r4t5y6u7i8o9p0a1s2d3f4g5h6j7k8l9z0x1c',
            'expires_at': '2027-03-04T19:30:00+00:00',
          },
    });
    await _pump(tester, DeliveryDocumentService(rpc: rpc.call));

    expect(find.text('vista previa comprobante_entrega_PG-26-00412.pdf (true)'),
        findsOneWidget);
    expect(find.text('PG-26-00412 · Dora Pérez'), findsOneWidget);
    expect(find.text('Quedan 9 días'), findsOneWidget);
    expect(find.text('Quedan 61 días'), findsOneWidget);
    expect(
      find.text(
          'Dora no tiene cuenta. El comprobante incluye el QR para crearla.'),
      findsOneWidget,
    );
    expect(rpc.calls.map((c) => c.$1), [
      'ensure_job_delivery_document_v1',
      'issue_customer_portal_claim_code_v1',
    ]);
    expect(rpc.calls.last.$2['p_purpose'], 'delivery');
    expect(find.text('Enviar por WhatsApp'), findsOneWidget);
  });

  testWidgets('con cuenta no saca código y lo dice', (tester) async {
    final rpc = _Rpc({
      'ensure_job_delivery_document_v1': (_) => _projection(hasAccount: true),
    });
    await _pump(tester, DeliveryDocumentService(rpc: rpc.call));

    expect(rpc.calls.map((c) => c.$1), ['ensure_job_delivery_document_v1']);
    expect(
      find.text(
          'Dora ya tiene cuenta: el comprobante también queda en su portal.'),
      findsOneWidget,
    );
    // Sin teléfono no se ofrece WhatsApp: dice por qué.
    expect(find.text('El cliente no tiene teléfono.'), findsOneWidget);
  });

  testWidgets('sin repuestos instalados no muestra garantía de repuestos',
      (tester) async {
    final rpc = _Rpc({
      'ensure_job_delivery_document_v1': (_) =>
          _projection(hasAccount: true, withPart: false),
    });
    await _pump(tester, DeliveryDocumentService(rpc: rpc.call));

    expect(find.text('Quedan 9 días'), findsOneWidget);
    expect(find.text('Repuestos'), findsNothing);
    expect(find.text('Quedan 61 días'), findsNothing);
  });

  testWidgets(
      'un trabajo sin entrega lo dice dentro del diálogo, con reintento',
      (tester) async {
    final rpc = _Rpc({
      'ensure_job_delivery_document_v1': (_) =>
          throw const PostgrestException(message: 'job_not_delivered'),
    });
    await _pump(tester, DeliveryDocumentService(rpc: rpc.call));

    expect(
      find.textContaining('todavía no tiene una entrega registrada'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  test('el texto del chat dice el número y hasta cuándo vale cada garantía',
      () {
    final document = DeliveryWarrantyPdfInput.fromProjection(_projection())!;
    expect(
      deliveryDocumentWhatsAppText(document),
      'Hola Dora, te adjuntamos el comprobante de entrega y garantía de tu '
      'servicio PG-26-00412. La garantía del servicio es válida hasta el 18 '
      'de noviembre de 2026 y la de repuestos hasta el 4 de enero de 2027. '
      'Gracias por confiar en Viñabike.',
    );
  });

  test(
      'el comprobante se ofrece después de la primera entrega de taller; el QR '
      'sólo a quien no tiene cuenta', () {
    MechanicJob job({
      JobStatus status = JobStatus.enCurso,
      JobWorkflowKind workflow = JobWorkflowKind.service,
      DateTime? deliveredAt,
    }) =>
        MechanicJob(
          id: 'job-1',
          tenantId: 't',
          customerId: 'c',
          jobType: JobType.service,
          workflowKind: workflow,
          arrivalDate: DateTime(2026, 11, 1),
          status: status,
          deliveredAt: deliveredAt,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        );

    expect(DeliveryDocumentPolicy.offersDeliveryDocument(job()), isFalse);
    expect(
      DeliveryDocumentPolicy.offersDeliveryDocument(
          job(status: JobStatus.entregado)),
      isTrue,
    );
    // Reabierto después de entregarse: conserva su comprobante.
    expect(
      DeliveryDocumentPolicy.offersDeliveryDocument(
          job(deliveredAt: DateTime(2026, 11, 3))),
      isTrue,
    );
    // Una venta no abre garantía de taller.
    expect(
      DeliveryDocumentPolicy.offersDeliveryDocument(job(
        status: JobStatus.entregado,
        workflow: JobWorkflowKind.sale,
      )),
      isFalse,
    );
    // «Presupuestar primero»: la bici se entrega antes de facturarse y la
    // base sí le arma comprobante; el ERP no lo puede esconder.
    expect(
      DeliveryDocumentPolicy.offersDeliveryDocument(job(
        status: JobStatus.entregado,
        workflow: JobWorkflowKind.quotation,
      )),
      isTrue,
    );

    final withoutAccount =
        Customer(id: 'c', tenantId: 't', name: 'Dora', rut: '');
    final withAccount = Customer(
      id: 'c',
      tenantId: 't',
      name: 'Dora',
      rut: '',
      authUserId: 'u',
    );
    expect(
        DeliveryDocumentPolicy.offersAccountQr(job(), withoutAccount), isTrue);
    expect(DeliveryDocumentPolicy.offersAccountQr(job(), withAccount), isFalse);
    expect(
      DeliveryDocumentPolicy.offersAccountQr(
          job(status: JobStatus.cancelado), withoutAccount),
      isFalse,
    );
  });
}
