import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/services/whatsapp_settings_service.dart';

void main() {
  test('counts only Meta regular per-message receipts as billable', () {
    final pricing = parseWhatsAppProviderPricing({
      'whatsapp_status_payload': {
        'status': 'delivered',
        'timestamp': '1787851800',
        'pricing': {
          'pricing_model': 'PMP',
          'type': 'regular',
          'category': 'utility',
        },
      },
    });

    expect(pricing, isNotNull);
    expect(pricing!.isBillable, isTrue);
    expect(pricing.category, 'utility');
    expect(pricing.pricingModel, 'PMP');
    expect(
      pricing.statusAt,
      DateTime.fromMillisecondsSinceEpoch(1787851800 * 1000, isUtc: true),
    );
  });

  test('recognizes customer-service messages as explicitly free', () {
    final pricing = parseWhatsAppProviderPricing({
      'whatsapp_status_payload': {
        'pricing': {
          'pricing_model': 'PMP',
          'type': 'free_customer_service',
          'category': 'service',
        },
      },
    });

    expect(pricing, isNotNull);
    expect(pricing!.isBillable, isFalse);
    expect(pricing.type, 'free_customer_service');
  });

  test('does not invent a charge without provider pricing evidence', () {
    expect(
      parseWhatsAppProviderPricing({
        'template_name': 'seguimiento_servicio_bicicleta',
        'external_status': 'delivered',
      }),
      isNull,
    );
  });

  test('keeps legacy billable receipts readable during the transition', () {
    final pricing = parseWhatsAppProviderPricing({
      'whatsapp_status_payload': {
        'pricing': {
          'billable': true,
          'pricing_model': 'CBP',
          'category': 'utility',
        },
      },
    });

    expect(pricing, isNotNull);
    expect(pricing!.isBillable, isTrue);
  });
}
