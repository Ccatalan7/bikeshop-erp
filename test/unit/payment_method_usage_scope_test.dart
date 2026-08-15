import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/payment_method.dart';

void main() {
  test('terminal card rails are inbound and retain provider identity', () {
    final debit = PaymentMethod.fromJson(<String, dynamic>{
      'id': 'debit-id',
      'tenant_id': 'tenant-id',
      'code': 'card_debit',
      'name': 'Tarjeta de débito',
      'account_id': 'bank-id',
      'usage_scope': 'inbound',
      'settlement_provider': 'transbank',
      'payment_instrument': 'debit',
      'terminal_profile_id': 'terminal-id',
    });

    expect(debit.supportsInbound, isTrue);
    expect(debit.supportsOutbound, isFalse);
    expect(debit.isCardInstrument, isTrue);
    expect(debit.paymentInstrument, PaymentCardInstrument.debit);
    expect(debit.settlementProvider, PaymentSettlementProvider.transbank);
    expect(debit.terminalProfileId, 'terminal-id');
    expect(debit.toJson()['usage_scope'], 'inbound');
  });

  test('legacy business card can remain outbound without leaking into sales',
      () {
    final card = PaymentMethod.fromJson(<String, dynamic>{
      'id': 'card-id',
      'tenant_id': 'tenant-id',
      'code': 'card',
      'name': 'Tarjeta del negocio',
      'account_id': 'bank-id',
      'usage_scope': 'outbound',
      'payment_instrument': 'unknown',
    });

    expect(card.supportsInbound, isFalse);
    expect(card.supportsOutbound, isTrue);
    expect(card.isCardInstrument, isTrue);
  });

  test('missing scope remains backward-compatible in both directions', () {
    final historical = PaymentMethod.fromJson(<String, dynamic>{
      'id': 'historical-id',
      'tenant_id': 'tenant-id',
      'code': 'transfer',
      'name': 'Transferencia',
      'account_id': 'bank-id',
    });

    expect(historical.usageScope, PaymentMethodUsageScope.both);
    expect(historical.supportsInbound, isTrue);
    expect(historical.supportsOutbound, isTrue);
  });
}
