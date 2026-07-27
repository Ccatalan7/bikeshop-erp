import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('financial Realtime is private, tenant-scoped, and payload-minimal', () {
    final migration = File(
      'supabase/migrations/'
      '20260726164000_enable_tenant_financial_projection_broadcast.sql',
    ).readAsStringSync();
    final authorizationFix = File(
      'supabase/migrations/'
      '20260726170500_fix_financial_projection_broadcast_authorization.sql',
    ).readAsStringSync();
    final tenantInvariant = File(
      'supabase/migrations/'
      '20260726174500_enforce_sales_invoice_tenant_scope.sql',
    ).readAsStringSync();
    final transport = File(
      'lib/modules/accounting/services/'
      'financial_projection_realtime_transport.dart',
    ).readAsStringSync();

    expect(
      migration,
      contains('drop policy if exists "Employees can view all invoices"'),
    );
    expect(
      migration,
      contains("'financial-projections:' || v_tenant_id::text"),
    );
    expect(
      migration,
      contains("'financial-projections:' ||\n"
          '            (select public.user_tenant_id())::text'),
    );
    expect(migration, contains("extension = 'broadcast'"));
    expect(migration, contains("'event_id', gen_random_uuid()::text"));
    expect(migration, contains("'kind', v_kind"));
    expect(migration, contains("'entity_id', v_entity_id"));
    expect(migration, contains("'operation', lower(tg_op)"));
    expect(
      migration,
      isNot(contains('alter publication supabase_realtime')),
    );
    expect(
      migration,
      isNot(contains('for insert\n  to authenticated')),
    );
    expect(
      authorizationFix,
      contains(
        'drop policy if exists '
        '"Tenant members receive financial projection broadcasts"',
      ),
    );
    expect(
      authorizationFix,
      contains("'financial-projections:' ||\n"
          '            (select public.user_tenant_id())::text'),
    );
    expect(authorizationFix, contains("extension = 'broadcast'"));
    expect(authorizationFix, isNot(contains('and private is true')));
    expect(
      authorizationFix,
      isNot(contains('for insert\n        to authenticated')),
    );
    expect(
      tenantInvariant,
      contains('customer.id = invoice.customer_id'),
    );
    expect(
      tenantInvariant,
      contains('Cannot infer tenant_id for every legacy sales invoice'),
    );
    expect(
      tenantInvariant,
      contains('alter column tenant_id set not null'),
    );

    for (final table in <String>[
      'accounts',
      'employee_advance_allocations',
      'employee_advances',
      'expense_lines',
      'expense_payments',
      'expenses',
      'journal_entries',
      'journal_lines',
      'payroll_voucher_lines',
      'payroll_vouchers',
      'purchase_invoices',
      'purchase_payments',
      'sales_invoices',
      'sales_payments',
    ]) {
      expect(migration, contains("'$table'"), reason: table);
    }

    expect(
      transport,
      contains("channel(\n          'financial-projections:\$tenantId'"),
    );
    expect(
      transport,
      contains('RealtimeChannelConfig(private: true)'),
    );
    expect(transport, contains("event: 'changed'"));
    expect(transport, contains('_client.removeChannel(_channel)'));
    expect(transport, isNot(contains('onPostgresChanges')));
  });

  test('core schema mirrors the financial Broadcast migration', () {
    final core = File('supabase/sql/core_schema.sql').readAsStringSync();

    for (final invariant in <String>[
      'drop policy if exists "Employees can view all invoices"',
      'create or replace function '
          'public.broadcast_financial_projection_change()',
      "'realtime.send(jsonb,text,text,boolean)'",
      "'financial-projections:' || v_tenant_id::text",
      'create policy "Tenant members receive financial projection broadcasts"',
      "extension = 'broadcast'",
      "'employee_advance_allocations'",
      "'payroll_voucher_lines'",
      'create trigger trg_broadcast_financial_projection_change',
    ]) {
      expect(core, contains(invariant), reason: invariant);
    }
    expect(
      core.toLowerCase(),
      isNot(contains('create policy "employees can view all invoices"')),
    );
    expect(core, isNot(contains('and private is true')));
  });
}
