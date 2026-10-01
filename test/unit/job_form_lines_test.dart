import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_form_lines.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_line_save.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

/// Guardar → reabrir → guardar una línea con el mismo camino que el
/// formulario del trabajo: `jobLineFromLabor`/`jobLineFromPart` arman lo que
/// se envía, `BikeshopService.buildJobLineSaveParams` el pedido, y
/// `JobPartItem.fromPersisted` lo que vuelve al reabrir (revisión del
/// 2026-09-28: 1,5 h volvía como 1 h y el guardado siguiente cambiaba el
/// importe).

const _jobId = 'e28a0000-0000-4000-8000-000000000051';
const _tenantId = 'e28a0000-0000-4000-8000-000000000001';

/// Las columnas que el comando compara para decidir si reescribe una línea
/// (`save_mechanic_job_lines_v1`, «is distinct from»).
const _compared = [
  'job_bike_id',
  'product_id',
  'service_product_id',
  'product_name',
  'product_sku',
  'quantity',
  'unit_price',
  'notes',
  'service_configuration_data',
  'item_type',
  'system_key',
  'component_slot_key',
  'location_key',
  'intervention_type',
  'creates_lifecycle',
];

Product _serviceProduct() => Product(
      id: 'e28a0000-0000-4000-8000-0000000000c1',
      name: 'Mano de obra taller',
      sku: 'MO-1',
      price: 20000,
      cost: 0,
      stockQuantity: 0,
      category: ProductCategory.parts,
      productType: ProductType.service,
      description: 'Revisar\n\nAjustar',
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

/// Lo que devuelve PostgREST al leer la línea que el comando guardó: lo que
/// se envió, con el id, el total y la versión que pone la base.
Map<String, dynamic> _storedRow(Map<String, dynamic> sent, String id) => {
      for (final column in _compared) column: sent[column],
      'id': id,
      'job_id': _jobId,
      'tenant_id': _tenantId,
      'total_price': (sent['quantity'] as num).toDouble() *
          (sent['unit_price'] as num).toDouble(),
      'updated_at': '2026-09-28T15:00:00.123456+00:00',
      'created_at': '2026-09-28T15:00:00.123456+00:00',
    };

void main() {
  late BikeshopService service;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    service = BikeshopService(DatabaseService());
  });

  Map<String, dynamic> firstSave(Product? serviceProduct) {
    final params = service.buildJobLineSaveParams(
      jobId: _jobId,
      seenLines: const [],
      lines: [
        JobLineToSave(
          clientKey: 'labor-7',
          persisted: false,
          item: jobLineFromLabor(
            persistedId: null,
            jobId: _jobId,
            tenantId: _tenantId,
            serviceProduct: serviceProduct,
            name: 'Mano de obra',
            hours: 1.5,
            hourlyRate: 20000,
          ),
        ),
      ],
      bikeFacts: const {},
    );
    return Map<String, dynamic>.from((params['p_lines'] as List).single as Map);
  }

  Map<String, dynamic> reopenAndSave(
    Map<String, dynamic> row, {
    Product? product,
  }) {
    final loaded = MechanicJobItem.fromJson(row);
    final reopened = JobPartItem.fromPersisted(loaded, product: product);
    final params = service.buildJobLineSaveParams(
      jobId: _jobId,
      seenLines: [JobLineVersion(id: loaded.id!, version: loaded.version!)],
      lines: [
        JobLineToSave(
          clientKey: reopened.id,
          persisted: true,
          item: jobLineFromPart(
            reopened,
            persisted: true,
            jobId: _jobId,
            jobBikeId: null,
            tenantId: _tenantId,
            existing: loaded,
            configuration: reopened.wizardAnswers,
          ),
        ),
      ],
      bikeFacts: const {},
    );
    return Map<String, dynamic>.from((params['p_lines'] as List).single as Map);
  }

  group('guardar → reabrir → guardar una mano de obra de 1,5 h', () {
    test('sin producto de servicio: mismas horas, id y total', () {
      final sent = firstSave(null);
      expect(sent['quantity'], 1.5);
      expect(sent['item_type'], 'service',
          reason: 'mano de obra para los costos del trabajo y para la '
              'factura: `adhoc` era repuesto en uno y mano de obra en la otra');

      final row = _storedRow(sent, 'e28a0000-0000-4000-8000-0000000000d1');
      final loaded = JobPartItem.fromPersisted(MechanicJobItem.fromJson(row));
      expect(loaded.quantity, 1.5, reason: 'antes volvía como 1');

      final resent = reopenAndSave(row);
      expect(resent['id'], row['id']);
      expect(resent['quantity'], 1.5);
      expect(
        (resent['quantity'] as num) * (resent['unit_price'] as num),
        30000,
        reason: 'el total que calcula la base no cambia',
      );
      for (final column in _compared) {
        expect(resent[column], row[column], reason: column);
      }
    });

    test('con producto de servicio: servicio las dos veces', () {
      final product = _serviceProduct();
      final sent = firstSave(product);
      expect(sent['item_type'], 'service',
          reason: 'antes se guardaba como repuesto y al reabrir pasaba a '
              'servicio');
      expect(sent.containsKey('auto_task_description'), isFalse,
          reason: 'sus tareas las crea la base al insertar la línea');

      final row = _storedRow(sent, 'e28a0000-0000-4000-8000-0000000000d2');
      final resent = reopenAndSave(row, product: product);
      for (final column in _compared) {
        expect(resent[column], row[column], reason: column);
      }
    });
  });

  group('la cantidad en el formulario', () {
    test('vaciar el campo no la vuelve 1: queda como borrador', () {
      final line = JobPartItem(
        name: 'Aceite de horquilla',
        isCatalogProduct: false,
        quantity: 0.5,
        unitPrice: 8000,
      );
      final emptied = line.withQuantityText('');
      expect(emptied.quantity, 0.5, reason: 'antes pasaba a 1');
      expect(emptied.quantityDraft, '',
          reason: 'el formulario no guarda mientras quede un borrador');

      final written = emptied.withQuantityText('1,5');
      expect(written.quantity, 1.5);
      expect(written.quantityDraft, isNull);
      expect(written.id, line.id);
    });

    test('se muestra con coma y sin decimales de más', () {
      expect(formatJobLineQuantity(1.5), '1,5');
      expect(formatJobLineQuantity(2), '2');
      expect(formatJobLineQuantity(0.25), '0,25');
      expect(formatJobLineQuantity(1.10), '1,1');
    });

    test('se lee con coma o punto y hasta dos decimales', () {
      expect(parseJobLineQuantity('1,5'), 1.5);
      expect(parseJobLineQuantity('1.5'), 1.5);
      expect(parseJobLineQuantity(' 2 '), 2);
      expect(parseJobLineQuantity('1,'), 1);
      expect(parseJobLineQuantity('1,555'), isNull);
      expect(parseJobLineQuantity(''), isNull);
      expect(parseJobLineQuantity('uno'), isNull);
    });
  });
}
