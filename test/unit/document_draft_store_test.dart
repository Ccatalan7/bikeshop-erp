import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/shared/services/form_drafts/document_draft_store.dart';
import 'package:vinabike_erp/shared/services/form_drafts/form_draft_store.dart';
import 'package:vinabike_erp/shared/widgets/draft_restored_pill.dart';

class _MemoryDocumentDraftStore implements DocumentDraftStore {
  final Map<String, DocumentDraft> drafts = {};
  int writes = 0;
  bool failReads = false;

  @override
  Future<DocumentDraft?> read(String userId, String key) async {
    if (failReads) throw StateError('equipo sin leer');
    return drafts['$userId|$key'];
  }

  @override
  Future<List<DocumentDraft>> list(String userId, String keyPrefix) async {
    if (failReads) throw StateError('equipo sin leer');
    final found = drafts.values
        .where((d) => d.userId == userId && d.key.startsWith(keyPrefix))
        .toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return found;
  }

  @override
  Future<void> remove(String userId, String key) async =>
      drafts.remove('$userId|$key');

  @override
  Future<void> write(DocumentDraft draft) async {
    writes += 1;
    drafts['${draft.userId}|${draft.key}'] = draft;
  }
}

/// La venta que se está armando, con sus líneas, queda en el equipo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryDocumentDraftStore store;
  Map<String, Object?>? current;

  DocumentDraftKeeper keeper() => DocumentDraftKeeper(
        draftKey: 'venta:nueva',
        capture: () => current,
        store: store,
        currentUserId: () => 'usuario-1',
        every: const Duration(hours: 1),
      );

  setUp(() {
    store = _MemoryDocumentDraftStore();
    current = null;
    DraftSlots.resetForTest();
  });

  test('guarda cuando cambia y no repite lo mismo', () async {
    final draft = keeper()..start();
    current = {'reference': 'Pedido'};
    await draft.flush();
    await draft.flush();
    expect(store.writes, 1);
    current = {'reference': 'Pedido 2'};
    await draft.flush();
    expect(store.writes, 2);
    expect(
        store.drafts['usuario-1|venta:nueva']!.data['reference'], 'Pedido 2');
    draft.stop();
  });

  test('si ya no queda nada que valga guardar, lo borra', () async {
    final draft = keeper()..start();
    current = {'reference': 'Pedido'};
    await draft.flush();
    current = null;
    await draft.flush();
    expect(store.drafts, isEmpty);
    draft.stop();
  });

  test('lo recuperado que la persona vacía tampoco queda', () async {
    await store.write(DocumentDraft(
      key: 'venta:nueva',
      userId: 'usuario-1',
      savedAt: DateTime.now(),
      data: const {'reference': 'Antes'},
    ));
    final draft = keeper();
    expect((await draft.read())!.data['reference'], 'Antes');
    draft.start();
    current = null;
    await draft.flush();
    expect(store.drafts, isEmpty);
    draft.stop();
  });

  test('al guardarse de verdad se borra y deja de seguirse', () async {
    final draft = keeper()..start();
    current = {'reference': 'Pedido'};
    await draft.flush();
    await draft.clear();
    expect(store.drafts, isEmpty);
    current = {'reference': 'Otra cosa'};
    await draft.flush();
    expect(store.drafts, isEmpty, reason: 'ya no lo sigue');
  });

  test('al cerrar el formulario guarda lo último una vez', () async {
    final draft = keeper()..start();
    current = {'reference': 'Último'};
    draft.stop();
    await pumpEventQueue();
    expect(store.drafts['usuario-1|venta:nueva']!.data['reference'], 'Último');
  });

  test('una venta con sus líneas sale y vuelve igual', () {
    final original = Invoice.fromJson({
      'tenant_id': 't1',
      'customer_id': 'c1',
      'customer_name': 'Dora Pérez',
      'invoice_number': 'V-00031',
      'date': '2026-11-04T15:00:00Z',
      'reference': 'Retira el viernes',
      'status': 'draft',
      'tax_treatment': 'tax_included',
      'total': 47000,
      'items': [
        {
          'product_id': 'p1',
          'product_name': 'Cámara 29 x 2.10 FV',
          'product_sku': 'CAM-29',
          'is_catalog_product': true,
          'quantity': 2,
          'unit_price': 6500,
          'discount': 0,
        },
        {
          'product_name': 'Ajuste de frenos',
          'is_catalog_product': false,
          'is_service': true,
          'quantity': 1,
          'unit_price': 34000,
          'discount': 0,
        },
      ],
    });
    final stored = jsonDecode(jsonEncode(original.toFirestoreMap()));
    final back = Invoice.fromJson(Map<String, dynamic>.from(stored as Map));
    expect(back.customerId, 'c1');
    expect(back.reference, 'Retira el viernes');
    expect(back.items, hasLength(2));
    expect(back.items.first.productName, 'Cámara 29 x 2.10 FV');
    expect(back.items.first.quantity, 2);
    expect(back.items.first.unitPrice, 6500);
    expect(back.items.last.productName, 'Ajuste de frenos');
    expect(back.items.last.isCatalogProduct, isFalse);
    expect(back.taxTreatment, original.taxTreatment);
  });

  group('cada venta nueva tiene su lugar', () {
    DocumentDraft stored(String key, DateTime at) => DocumentDraft(
          key: key,
          userId: 'usuario-1',
          savedAt: at,
          data: {'reference': key},
        );

    setUp(() {
      DocumentDrafts.store = store;
    });

    test('dos pestañas abiertas a la vez no comparten borrador', () async {
      final first = DocumentDrafts.claim('venta:nueva', userId: 'usuario-1');
      final second = DocumentDrafts.claim('venta:nueva', userId: 'usuario-1');
      final slots = await Future.wait([first, second]);
      expect(slots[0], startsWith('venta:nueva#'));
      expect(slots[1], startsWith('venta:nueva#'));
      expect(slots[0], isNot(slots[1]));
    });

    test('lo que quedó sin guardar lo toma la próxima venta, de a una',
        () async {
      final now = DateTime.now();
      await store.write(
          stored('venta:nueva#vieja', now.subtract(const Duration(hours: 2))));
      await store.write(stored(
          'venta:nueva#reciente', now.subtract(const Duration(minutes: 5))));
      // La de un cliente es otro tipo de borrador.
      await store.write(stored('venta:nueva:cliente:c1#otra', now));

      final slots = await Future.wait([
        DocumentDrafts.claim('venta:nueva', userId: 'usuario-1'),
        DocumentDrafts.claim('venta:nueva', userId: 'usuario-1'),
        DocumentDrafts.claim('venta:nueva', userId: 'usuario-1'),
      ]);
      expect(slots[0], 'venta:nueva#reciente');
      expect(slots[1], 'venta:nueva#vieja');
      expect(
          slots[2],
          allOf(startsWith('venta:nueva#'),
              isNot(anyOf('venta:nueva#reciente', 'venta:nueva#vieja'))));
    });

    test('al cerrar la pestaña, su venta queda para la siguiente', () async {
      await store.write(stored('venta:nueva#a', DateTime.now()));
      final open =
          await DocumentDrafts.claim('venta:nueva', userId: 'usuario-1');
      expect(open, 'venta:nueva#a');
      final meanwhile =
          await DocumentDrafts.claim('venta:nueva', userId: 'usuario-1');
      expect(meanwhile, isNot('venta:nueva#a'), reason: 'está abierta');
      DocumentDrafts.release(open);
      expect(await DocumentDrafts.claim('venta:nueva', userId: 'usuario-1'),
          'venta:nueva#a');
    });

    test('si el equipo no se deja leer, igual hay un lugar nuevo', () async {
      store.failReads = true;
      expect(await DocumentDrafts.claim('venta:nueva', userId: 'usuario-1'),
          startsWith('venta:nueva#'));
    });
  });

  test('la antigüedad no se parte en dos líneas', () {
    final now = DateTime(2026, 11, 4, 18, 0);
    final ages = [
      describeDraftAge(now, now: now),
      describeDraftAge(now.subtract(const Duration(minutes: 5)), now: now),
      describeDraftAge(now.subtract(const Duration(hours: 3)), now: now),
      describeDraftAge(now.subtract(const Duration(days: 4)), now: now),
    ];
    expect(ages.map((age) => age.replaceAll('\u00a0', ' ')), [
      'hace un momento',
      'hace 5 min',
      'hace 3 horas',
      'hace 4 días',
    ]);
    for (final age in ages) {
      expect(age.contains(' '), isFalse, reason: '«$age» se cortaría');
    }
  });

  // El formulario de venta no se puede montar en una prueba sin la mitad del
  // ERP; estas reglas se leen en su fuente. Si una falla, la venta recuperada
  // puede volver a quedar dos veces.
  group('la venta manual recuperada sigue siendo la misma venta', () {
    final source = File('lib/modules/sales/pages/invoice_form_page.dart')
        .readAsStringSync();

    test('su identidad vive con el borrador, no con el formulario', () {
      expect(source, contains('await RecordIdentities.of(saleSlot)'));
      expect(source, contains('DocumentDrafts.claim(_saleDraftBase)'));
      expect(
          source, contains('recordId: invoice.id == null ? recordId : null'));
    });

    test('un reintento usa el número que ya se le asignó', () {
      expect(source, contains('_takenNumberFor == recordId'));
      expect(source, contains('data[_draftTakenNumberKey] = _takenNumber'));
    });

    test('se suelta al guardar, al deshacer, si ya llegó y al cerrar vacía',
        () {
      final releases = RegExp(r'RecordIdentities\.release\((slot|saleSlot)\)')
          .allMatches(source)
          .length;
      expect(releases, greaterThanOrEqualTo(4));
      expect(source, contains('DocumentDrafts.release(slot);'));
    });

    test('si el intento anterior llegó, no se presenta como venta nueva', () {
      final restore = source.substring(
        source.indexOf('Future<void> _restoreSaleDraft('),
        source.indexOf('/// La persona no quiere lo recuperado'),
      );
      expect(restore.indexOf('_findSavedSale(heldId)'),
          lessThan(restore.indexOf('_applyInvoice(invoice)')));
    });

    test('al cerrar, el borrador lee los controladores antes de soltarlos', () {
      final dispose = source.substring(
        source.indexOf('  void dispose() {'),
        source.indexOf('_invoiceNumberController.dispose();'),
      );
      expect(dispose, contains('saleDraft?.stop();'));
    });
  });
}
