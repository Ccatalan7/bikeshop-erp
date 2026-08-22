import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';

void main() {
  // El cuerpo que recibe el cliente es el que Meta aprobó, y vive en
  // `supabase/functions/_shared/whatsapp_templates.ts` —el mismo módulo que las
  // despliega—. La copia de Dart alimenta la previsualización del asistente y
  // el texto que se archiva en la bandeja, así que si se separan, el taller ve
  // algo distinto de lo que le llegó al cliente.
  //
  // Pasó: el 2026-08-21 las tres llevaban tilde y los cuerpos aprobados no. Se
  // descubrió con un envío real al teléfono del dueño, no con una prueba.
  group('quien escribe se presenta por su nombre', () {
    final primerContacto = WhatsAppService.customerTemplateOptions.firstWhere(
      (option) =>
          option.parameterLayout ==
          WhatsAppTemplateParameterLayout.contactAndAgent,
    );

    test('el apellido del operador no viaja al cliente', () {
      expect(
        primerContacto.renderPreview(
          contactName: 'Marcelo Silva',
          businessName: 'Viñabike',
          agentName: 'Claudio Catalán',
        ),
        contains('hablas con Claudio de'),
      );
    });

    test('un nombre compuesto del operador se conserva entero', () {
      expect(
        primerContacto.bodyParameters(
          contactName: 'Marcelo Silva',
          businessName: 'Viñabike',
          agentName: 'José Luis Campodónico',
        )[1],
        'José Luis',
      );
    });

    test('sin nombre resuelto, firma de forma neutra y no en blanco', () {
      expect(
        primerContacto.renderPreview(
          contactName: 'Marcelo Silva',
          businessName: 'Viñabike',
        ),
        contains('parte del equipo'),
      );
    });
  });

  group('la copia local es literalmente el cuerpo aprobado', () {
    final aprobados = _cuerposAprobados();

    test('los tres cuerpos de cliente existen en el módulo compartido', () {
      expect(aprobados.keys, containsAll(<String>[
        'actualizacion_servicio_bicicleta',
        'bicicleta_lista_retiro',
        'seguimiento_presupuesto_bicicleta',
      ]));
    });

    // Proveedores incluidos: la previsualización de mensajería es la misma
    // para ambas bandejas, así que una deriva en el cuerpo del proveedor
    // engaña igual que una del cliente.
    final todas = <WhatsAppTemplateOption>[
      ...WhatsAppService.customerTemplateOptions,
      ...WhatsAppService.supplierTemplateOptions,
    ];
    test('ninguna plantilla queda sin cuerpo aprobado que comparar', () {
      expect(
        todas
            .where((option) => aprobados[option.defaultTemplateName] == null)
            .map((option) => option.defaultTemplateName),
        isEmpty,
      );
    });

    for (final option in todas) {
      final aprobado = aprobados[option.defaultTemplateName];
      if (aprobado == null) continue;
      test('${option.defaultTemplateName} coincide palabra por palabra', () {
        // Los parámetros salen de `bodyParameters`, que es lo que el envío
        // manda a Meta. Sustituirlos a ciegas escondería un error de ORDEN:
        // en «seguimiento_servicio_bicicleta» el segundo parámetro es quien
        // escribe, no el negocio.
        final parametros = option.bodyParameters(
          contactName: 'Marcelo Silva',
          businessName: 'Viñabike',
          agentName: 'Claudio',
        );
        var esperado = aprobado;
        for (var i = 0; i < parametros.length; i++) {
          esperado = esperado.replaceAll('{{${i + 1}}}', parametros[i]);
        }
        expect(
          option.renderPreview(
            contactName: 'Marcelo Silva',
            businessName: 'Viñabike',
            agentName: 'Claudio',
          ),
          esperado,
        );
      });
    }
  });

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

/// Lee los cuerpos aprobados directamente del módulo compartido. Se lee el
/// archivo en vez de duplicar las cadenas: duplicarlas sería repetir el mismo
/// error que esta prueba existe para impedir.
Map<String, String> _cuerposAprobados() {
  final file = File('supabase/functions/_shared/whatsapp_templates.ts');
  if (!file.existsSync()) {
    fail('No se encontró el módulo compartido de plantillas: ${file.path}');
  }
  final source = file.readAsStringSync();
  final pattern = RegExp(
    r'name:\s*"([a-z_0-9]+)",[\s\S]{0,200}?body:\s*\n?\s*"((?:[^"\\]|\\.)*)"',
  );
  final bodies = <String, String>{};
  for (final match in pattern.allMatches(source)) {
    final name = match.group(1)!;
    bodies[name] = match.group(2)!.replaceAll(r'\n', '\n');
  }
  return bodies;
}
