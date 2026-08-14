import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';

void main() {
  group('customer WhatsApp template greeting', () {
    test('keeps compound given names while removing surnames', () {
      expect(
        resolveWhatsAppTemplateGreetingName('José Luis Campodónico'),
        'José Luis',
      );
      expect(
        resolveWhatsAppTemplateGreetingName('Jose Luis Campodónico'),
        'Jose Luis',
      );
      expect(
        resolveWhatsAppTemplateGreetingName('Juan Pablo González Pérez'),
        'Juan Pablo',
      );
      expect(
        resolveWhatsAppTemplateGreetingName('Ana María Muñoz'),
        'Ana María',
      );
      expect(
        resolveWhatsAppTemplateGreetingName('Paul Calderón'),
        'Paul',
      );
      expect(
        resolveWhatsAppTemplateGreetingName('Pedro González Pérez'),
        'Pedro',
      );
    });

    test('uses the greeting name in every customer template parameter', () {
      for (final option in WhatsAppService.customerTemplateOptions) {
        final parameters = option.bodyParameters(
          contactName: 'José Luis Campodónico',
          agentName: 'parte del equipo',
          businessName: 'Viñabike',
        );
        expect(parameters.first, 'José Luis');
        expect(
          option.renderPreview(
            contactName: 'José Luis Campodónico',
            agentName: 'parte del equipo',
            businessName: 'Viñabike',
          ),
          startsWith('Hola José Luis,'),
        );
      }
    });
  });
}
