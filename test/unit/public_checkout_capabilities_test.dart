import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_checkout_capabilities.dart';

void main() {
  PublicCheckoutCapabilities parse({
    required bool mercadopago,
    required bool transfer,
  }) {
    return PublicCheckoutCapabilities.fromRpc({
      'schemaVersion': 1,
      'methods': [
        {
          'code': 'mercadopago',
          'available': mercadopago,
          'reasonCode': mercadopago ? 'available' : 'configuration_incomplete',
        },
        {
          'code': 'transfer',
          'available': transfer,
          'reasonCode': transfer ? 'available' : 'configuration_incomplete',
        },
      ],
    });
  }

  test('projects zero, one, or two effective payment methods', () {
    expect(
        parse(mercadopago: false, transfer: false).availableMethods, isEmpty);
    expect(
      parse(mercadopago: false, transfer: true).availableMethods,
      [PublicCheckoutPaymentCode.transfer],
    );
    expect(
      parse(mercadopago: true, transfer: true).availableMethods,
      [
        PublicCheckoutPaymentCode.mercadopago,
        PublicCheckoutPaymentCode.transfer,
      ],
    );
  });

  test('fails closed for unknown or contradictory server data', () {
    expect(
      () => PublicCheckoutCapabilities.fromRpc({
        'schemaVersion': 1,
        'methods': const [
          {
            'code': 'mercadopago',
            'available': true,
            'reasonCode': 'configuration_incomplete',
          },
          {
            'code': 'cash',
            'available': true,
            'reasonCode': 'available',
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('bootstrap applies the deployable capability migration after old readers',
      () {
    final core = File('supabase/sql/core_schema.sql').readAsStringSync();
    const include =
        r'\ir ../migrations/20260728220000_harden_public_checkout_capabilities.sql';

    expect(include.allMatches(core), hasLength(1));
    expect(
      core.lastIndexOf(include),
      greaterThan(
        core.lastIndexOf(
          'create or replace function public.create_public_online_order_with_access',
        ),
      ),
    );
    expect(
      core.lastIndexOf(include),
      greaterThan(
        core.lastIndexOf(
          'create or replace function public.get_public_online_order_by_access_token',
        ),
      ),
    );
  });
}
