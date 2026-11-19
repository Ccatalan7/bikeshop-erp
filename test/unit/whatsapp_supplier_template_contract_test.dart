import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_service.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';

void main() {
  group('supplier WhatsApp templates', () {
    test('publish the exact approved supplier vocabulary', () {
      const options = WhatsAppService.supplierTemplateOptions;

      expect(
        options.map((option) => option.defaultTemplateName),
        orderedEquals(const [
          'proveedor_presentacion_nuevo_numero_v1',
          'proveedor_saludo_v1',
          'proveedor_retomar_contacto_v1',
          'proveedor_consulta_novedades_v1',
          'proveedor_pedido_pendiente_v3',
        ]),
      );
      expect(
        options.every(
          (option) =>
              option.audience == WhatsAppTemplateAudience.supplier &&
              option.defaultLanguage == 'es_CL',
        ),
        isTrue,
      );

      expect(
        options[0].renderPreview(
          contactName: 'Felipe',
          agentName: 'Claudio',
          businessName: 'Viñabike',
        ),
        'Hola Felipe, buen día. Soy Claudio, del equipo de Viñabike en Viña del Mar, razón social NEWEN SpA. Con nuestro equipo estamos usando este nuevo número para comunicarnos con nuestros proveedores, así que quería presentarme y confirmar que podemos coordinarnos por aquí para compras, cotizaciones, documentos y despachos.\n\nQuedo atento. Saludos.',
      );
      expect(
        options[1].renderPreview(
          contactName: 'Felipe',
          businessName: 'Viñabike',
        ),
        'Hola Felipe, buen día.',
      );
      expect(
        options[2].renderPreview(
          contactName: 'Felipe',
          businessName: 'Viñabike',
        ),
        'Hola Felipe, buen día. Cuando puedas me hablas, porfa. Quedo atento. Saludos.',
      );
      expect(
        options[3].renderPreview(
          contactName: 'Felipe',
          businessName: 'Viñabike',
        ),
        'Hola Felipe, buen día. Cuando puedas me cuentas si hay alguna novedad, porfa. Quedo atento. Saludos.',
      );
      expect(
        options[4].renderPreview(
          contactName: 'Felipe',
          businessName: 'Viñabike',
        ),
        'Hola Felipe, buen día. Te escribo para seguir con el pedido que tenemos pendiente. Cuando puedas me hablas, porfa. Quedo atento, saludos.',
      );
    });

    test('uses contact plus signed-in agent only for the introduction', () {
      const options = WhatsAppService.supplierTemplateOptions;

      expect(
        options.first.bodyParameters(
          contactName: 'Felipe',
          agentName: 'Claudio',
          businessName: 'Viñabike',
        ),
        ['Felipe', 'Claudio'],
      );
      for (final option in options.skip(1).take(3)) {
        expect(
          option.bodyParameters(
            contactName: 'Felipe',
            agentName: 'No debe enviarse',
            businessName: 'Viñabike',
          ),
          ['Felipe'],
        );
      }
      expect(
        options.last.bodyParameters(
          contactName: 'Felipe',
          businessName: 'Viñabike',
        ),
        ['Felipe'],
      );
      expect(
        () => options.first.bodyParameters(
          contactName: 'Felipe',
          businessName: 'Viñabike',
        ),
        throwsArgumentError,
      );
    });

    test('uses only the configured vendor first name and not the company', () {
      expect(
        resolveSupplierMessagingContactName({
          'sales_rep_name': 'Felipe Soto',
          'contact_person': 'María Pérez',
        }),
        'Felipe',
      );
      expect(
        resolveSupplierMessagingContactName({
          'sales_rep_name': ' ',
          'contact_person': 'María Pérez',
        }),
        'María',
      );
      expect(
        resolveSupplierMessagingContactName({
          'sales_rep_name': '  Paul   Calderón  ',
          'contact_person': null,
        }),
        'Paul',
      );
      expect(
        resolveSupplierMessagingContactName({
          'sales_rep_name': null,
          'contact_person': null,
          'name': 'Comercial Ciclo',
        }),
        isNull,
      );
    });

    test('shared picker scopes options and passes supplier contact separately',
        () {
      final source = File(
        'lib/modules/messaging/widgets/chat_window.dart',
      ).readAsStringSync();

      expect(source, contains('templateOptionsForConversation('));
      expect(
        source,
        contains('isSupplier: widget.conversation.isSupplierConversation'),
      );
      expect(source, contains("contact?['template_contact_name']"));
      expect(source, contains('bindingContactName: bindingContactName'));
      expect(
        source,
        contains(
          'Falta el nombre del contacto o vendedor en el perfil del proveedor.',
        ),
      );
    });

    test('greets with the name chosen in the contact sheet, as is', () {
      // «Cómo saludarle» (20261119200000): quien llama ya pasa el saludo
      // elegido. Dos palabras no son nombre y apellido: son dos nombres.
      const options = WhatsAppService.supplierTemplateOptions;
      expect(
        options[1].renderPreview(
          contactName: 'Ana Lucía',
          businessName: 'Viñabike',
        ),
        'Hola Ana Lucía, buen día.',
      );
      expect(
        options[4].bodyParameters(
          contactName: '  Ana   Lucía ',
          businessName: 'Viñabike',
        ),
        ['Ana Lucía'],
      );
      // Al cliente todavía se le saluda con la regla de nombres.
      expect(
        WhatsAppService.customerTemplateOptions.first.bodyParameters(
          contactName: 'Pedro Soto',
          agentName: 'Claudio',
          businessName: 'Viñabike',
        ),
        ['Pedro', 'Claudio'],
      );
    });

    test('marks supplier sends so the server keeps the chosen greeting', () {
      final source = File(
        'lib/shared/services/whatsapp_service.dart',
      ).readAsStringSync();
      expect(source, contains('if (option.isSupplier)'));
      expect(
        source,
        contains(
          'whatsAppGreetingNameSourceKey: whatsAppGreetingFromContactPreference',
        ),
      );
      expect(whatsAppGreetingNameSourceKey, 'greeting_name_source');
      expect(whatsAppGreetingFromContactPreference, 'contact_preference');
    });

    test('the supplier PDF greets with the chosen name and carries the mark',
        () {
      final chosen = WhatsAppService.documentTemplateRequest(
        phoneNumber: '56900000001',
        attachmentId: 'a-1',
        filename: 'pedido.pdf',
        greetingName: 'Ana Lucía',
        greetingIsChosen: true,
      );
      final parameters = ((chosen['templateComponents'] as List).single
          as Map)['parameters'] as List;
      expect((parameters.single as Map)['text'], 'Ana Lucía');
      expect(chosen['caption'], startsWith('Hola Ana Lucía, te enviamos'));
      expect(
        (chosen['metadata'] as Map)['greeting_name_source'],
        'contact_preference',
      );
      expect(
        WhatsAppService.documentTemplatePreview(
          'Ana Lucía',
          greetingIsChosen: true,
        ),
        startsWith('Hola Ana Lucía,'),
      );

      // Sin la marca —un cliente— sigue la regla de nombres sobre el nombre
      // completo, y el servidor puede normalizar.
      final customer = WhatsAppService.documentTemplateRequest(
        phoneNumber: '56900000001',
        attachmentId: 'a-1',
        filename: 'boleta.pdf',
        greetingName: 'Pedro Soto',
      );
      expect(customer['caption'], startsWith('Hola Pedro, te enviamos'));
      expect(
        (customer['metadata'] as Map).containsKey('greeting_name_source'),
        isFalse,
      );
    });

    test('only live APPROVED status enables supplier template sends', () {
      expect(
        WhatsAppTemplateReviewStatus.fromMap({
          'status': 'approved',
          'category': 'utility',
        }).isApproved,
        isTrue,
      );
      expect(
        WhatsAppTemplateReviewStatus.fromMap({
          'status': 'pending',
          'category': 'utility',
        }).isApproved,
        isFalse,
      );
    });
  });
}
