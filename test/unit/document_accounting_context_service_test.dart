import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/services/document_accounting_context_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '92000000-0000-4000-8000-000000000001';
const _invoiceId = '92000000-0000-4000-8000-000000000002';
const _invoiceNumber = '208049';
const _userId = '92000000-0000-4000-8000-000000000003';

/// 2026-11-08: opening a purchase invoice kept «Cargando pagos y diario...»
/// on screen for 1.7–2.1 s. Each server trip costs ~250 ms from the shop and
/// the evidence went out as a chain of up to eight trips, one after another,
/// starting with a second lookup of the tenant.
void main() {
  group('purchase invoice evidence', () {
    test(
        'payments, linked expenses and journal leave together, in one trip '
        'each, without asking for the tenant again', () async {
      final requests = <http.BaseRequest>[];
      final release = Completer<void>();
      final threeInFlight = Completer<void>();
      final client = _client((request) async {
        requests.add(request);
        if (requests.length == 3 && !threeInFlight.isCompleted) {
          threeInFlight.complete();
        }
        await release.future;
        return _respond(request);
      });
      var profileLookups = 0;
      final service = DocumentAccountingContextService(
        client: client,
        tenantService: _tenant(onLookup: () => profileLookups++),
      );

      final load = service.loadPurchaseInvoice(
        invoiceId: _invoiceId,
        invoiceNumber: _invoiceNumber,
      );
      // A chain would wait here forever: the second read only leaves once
      // the first one answers.
      await threeInFlight.future.timeout(const Duration(seconds: 2));
      release.complete();
      final context = await load;

      expect(
        requests.map((request) => request.url.pathSegments.last).toSet(),
        {'purchase_payments', 'expense_links', 'journal_entries'},
      );
      expect(requests, hasLength(3));
      expect(
        requests.where((r) => r.url.path.endsWith('/user_profiles')),
        isEmpty,
      );
      expect(profileLookups, 1);

      for (final request in requests) {
        expect(
          request.url.queryParameters['tenant_id'],
          'eq.$_tenantId',
          reason: '${request.url.path} must stay inside the tenant',
        );
      }
      final payments = _byTable(requests, 'purchase_payments').url;
      expect(payments.queryParameters['select'], '*,payment_methods(name)');
      expect(
        payments.queryParameters['payment_methods.tenant_id'],
        'eq.$_tenantId',
      );
      final links = _byTable(requests, 'expense_links').url;
      expect(
          links.queryParameters['select'], contains('payment_methods(name)'));
      expect(
        links.queryParameters['expenses.payment_methods.tenant_id'],
        'eq.$_tenantId',
      );
      final journal = _byTable(requests, 'journal_entries').url;
      expect(
        journal.queryParameters['select'],
        '*,${DocumentAccountingContextService.journalLinesEmbed}',
      );
      expect(
        journal.queryParameters['source_reference'],
        'in.("$_invoiceNumber","$_invoiceId")',
      );
      expect(
        journal.queryParameters['journal_lines.tenant_id'],
        'eq.$_tenantId',
      );

      expect(context.payments.map((payment) => payment.number), [
        'GTO-00129',
        'PAG-000001',
      ]);
      expect(context.payments.map((payment) => payment.methodName), [
        'Efectivo',
        'Transferencia',
      ]);
      expect(context.journalEntries.single.entryNumber, 'AC-01951');
      expect(
        context.journalEntries.single.lines.map((line) => line.accountCode),
        ['1105', '2101', '2120'],
      );
      expect(context.journalEntries.single.totalDebit, 62178);
    });

    test('the tenant is resolved once per user, not once per invoice',
        () async {
      var profileLookups = 0;
      final service = DocumentAccountingContextService(
        client: _client((request) async => _respond(request)),
        tenantService: _tenant(onLookup: () => profileLookups++),
      );

      for (var i = 0; i < 3; i++) {
        await service.loadPurchaseInvoice(
          invoiceId: _invoiceId,
          invoiceNumber: _invoiceNumber,
        );
      }

      expect(profileLookups, 1);
    });

    test('without one active profile it reads nothing', () async {
      final requests = <http.BaseRequest>[];
      final service = DocumentAccountingContextService(
        client: _client((request) async {
          requests.add(request);
          return _respond(request);
        }),
        tenantService: TenantService.testing(
          currentUserId: () => _userId,
          profileLookup: (_) async => [
            {'tenant_id': _tenantId},
            {'tenant_id': '92000000-0000-4000-8000-000000000009'},
          ],
        ),
      );

      final context = await service.loadPurchaseInvoice(
        invoiceId: _invoiceId,
        invoiceNumber: _invoiceNumber,
      );

      expect(context.payments, isEmpty);
      expect(context.journalEntries, isEmpty);
      expect(requests, isEmpty);
    });

    test('a journal the database cannot embed still arrives whole', () async {
      final requests = <http.BaseRequest>[];
      final service = DocumentAccountingContextService(
        client: _client((request) async {
          requests.add(request);
          final select = request.url.queryParameters['select'] ?? '';
          if (request.url.path.endsWith('/journal_entries') &&
              select.contains('journal_lines')) {
            return http.Response(
              jsonEncode({
                'code': 'PGRST200',
                'message': 'Could not find a relationship',
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return _respond(request);
        }),
        tenantService: _tenant(),
      );

      final context = await service.loadPurchaseInvoice(
        invoiceId: _invoiceId,
        invoiceNumber: _invoiceNumber,
      );

      final entry = context.journalEntries.single;
      expect(entry.entryNumber, 'AC-01951');
      expect(entry.lines.map((line) => line.accountCode), [
        '1105',
        '2101',
        '2120',
      ]);
      final fallback = requests
          .where((request) => request.url.path.endsWith('/journal_entries'))
          .where(
            (request) => !(request.url.queryParameters['select'] ?? '')
                .contains('journal_lines'),
          )
          .map((request) => request.url.queryParameters['source_reference'])
          .toSet();
      expect(fallback, {'eq.$_invoiceNumber', 'eq.$_invoiceId'});
      final lines = _byTable(requests, 'journal_lines').url;
      expect(lines.queryParameters['tenant_id'], 'eq.$_tenantId');
      expect(lines.queryParameters['entry_id'], 'in.("entry-1")');
    });
  });

  test('a payment receipt reads its own journal in one trip', () async {
    final requests = <http.BaseRequest>[];
    final service = DocumentAccountingContextService(
      client: _client((request) async {
        requests.add(request);
        return _respond(request);
      }),
      tenantService: _tenant(),
    );

    await service.loadPurchasePayment(paymentId: 'payment-1');

    final journal = requests.single.url;
    expect(journal.path, endsWith('/journal_entries'));
    expect(journal.queryParameters['source_module'], 'eq.purchase_payments');
    expect(journal.queryParameters['source_reference'], 'in.("payment-1")');
  });
}

SupabaseClient _client(
  Future<http.Response> Function(http.BaseRequest request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) => handler(request)),
  );
  addTearDown(client.dispose);
  return client;
}

TenantService _tenant({void Function()? onLookup}) => TenantService.testing(
      currentUserId: () => _userId,
      profileLookup: (_) async {
        onLookup?.call();
        return [
          {'tenant_id': _tenantId, 'role': 'admin'},
        ];
      },
    );

http.BaseRequest _byTable(List<http.BaseRequest> requests, String table) =>
    requests.firstWhere((request) => request.url.path.endsWith('/$table'));

http.Response _respond(http.BaseRequest request) {
  final table = request.url.pathSegments.last;
  final select = request.url.queryParameters['select'] ?? '';
  final rows = switch (table) {
    'purchase_payments' => [
        {
          'id': '00000000-0000-0000-0000-000000000001',
          'date': '2026-06-30',
          'reference': _invoiceNumber,
          'amount': 62178,
          'deleted_at': null,
          'payment_method_id': 'method-transfer',
          'payment_methods': {'name': 'Transferencia'},
        },
        {
          'id': '00000000-0000-0000-0000-000000000002',
          'date': '2026-06-29',
          'amount': 62178,
          'deleted_at': '2026-06-30T10:00:00Z',
          'payment_methods': {'name': 'Transferencia'},
        },
      ],
    'expense_links' => [
        {
          'expense_id': 'expense-1',
          'link_kind': 'delivery',
          'allocated_amount': 4990,
          'expenses': {
            'id': 'expense-1',
            'expense_number': 'GTO-00129',
            'supplier_name': 'Starken',
            'issue_date': '2026-07-02',
            'total_amount': 4990,
            'payment_status': 'paid',
            'payment_methods': {'name': 'Efectivo'},
          },
        },
      ],
    'journal_entries' when select.contains('journal_lines') => [
        {..._entry, 'journal_lines': _lines},
      ],
    'journal_entries' =>
      request.url.queryParameters['source_reference'] == 'eq.$_invoiceNumber'
          ? [_entry]
          : <Map<String, dynamic>>[],
    'journal_lines' => _lines,
    _ => throw StateError('Unexpected read: ${request.url}'),
  };
  return http.Response(
    jsonEncode(rows),
    200,
    headers: {'content-type': 'application/json'},
    request: request,
  );
}

const _entry = <String, dynamic>{
  'id': 'entry-1',
  'entry_number': 'AC-01951',
  'entry_date': '2026-06-30',
  'description': 'Factura 208049',
  'status': 'posted',
  'source_module': 'purchase_invoices',
  'source_reference': _invoiceNumber,
  'total_debit': 62178,
  'total_credit': 62178,
};

const _lines = <Map<String, dynamic>>[
  {
    'entry_id': 'entry-1',
    'account_code': '2120',
    'account_name': 'IVA Crédito Fiscal',
    'debit_amount': 9928,
    'credit_amount': 0,
  },
  {
    'entry_id': 'entry-1',
    'account_code': '1105',
    'account_name': 'Inventarios',
    'debit_amount': 52250,
    'credit_amount': 0,
  },
  {
    'entry_id': 'entry-1',
    'account_code': '2101',
    'account_name': 'Cuentas por Pagar Proveedores',
    'debit_amount': 0,
    'credit_amount': 62178,
  },
];
