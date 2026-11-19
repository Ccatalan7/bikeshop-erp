import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_service.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_relationship_service.dart';
import 'package:vinabike_erp/shared/utils/contact_greeting.dart';

// «Cómo saludarle» (20261119200000). Nombres inventados.
void main() {
  group('la regla del saludo', () {
    String greet(
      String name,
      ContactGreetingStyle style, [
      String? custom,
    ]) =>
        contactGreetingName(fullName: name, style: style, customName: custom);

    test('el primer nombre es la primera palabra, siempre', () {
      expect(greet('Ana Lucía Rivas', ContactGreetingStyle.firstName), 'Ana');
      expect(greet('  Pedro   Soto ', ContactGreetingStyle.firstName), 'Pedro');
      expect(greet('Yuri', ContactGreetingStyle.firstName), 'Yuri');
      expect(greet('   ', ContactGreetingStyle.firstName), '');
    });

    test('dos nombres conserva los «de», «del», «la», «los» entremedio', () {
      expect(
        greet('Ana Lucía Rivas', ContactGreetingStyle.twoNames),
        'Ana Lucía',
      );
      expect(
        greet('Rocío del Mar Fuentes', ContactGreetingStyle.twoNames),
        'Rocío del Mar',
      );
      expect(
        greet('Inés de los Ángeles Mora', ContactGreetingStyle.twoNames),
        'Inés de los Ángeles',
      );
      expect(
        greet('Tomás De La Cruz Vera', ContactGreetingStyle.twoNames),
        'Tomás De La Cruz',
      );
      // «Delia» empieza con «del» pero es un nombre.
      expect(
        greet('Rosa Delia Paz', ContactGreetingStyle.twoNames),
        'Rosa Delia',
      );
      // Con una sola palabra no hay segundo nombre que agregar.
      expect(greet('Yuri', ContactGreetingStyle.twoNames), 'Yuri');
    });

    test('personalizado va tal cual, en una línea; vacío vuelve al primero',
        () {
      expect(
        greet('Ana Lucía Rivas', ContactGreetingStyle.custom, '  Anita\n '),
        'Anita',
      );
      expect(
        greet('Pedro Soto', ContactGreetingStyle.custom, 'Don   Pedro'),
        'Don Pedro',
      );
      expect(greet('Pedro Soto', ContactGreetingStyle.custom, '  '), 'Pedro');
      expect(greet('Pedro Soto', ContactGreetingStyle.custom), 'Pedro');
    });

    test('lee y escribe los valores de la base', () {
      expect(
        ContactGreetingStyle.values.map((style) => style.wireValue),
        ['first_name', 'two_names', 'custom'],
      );
      expect(
        ContactGreetingStyle.fromWire('two_names'),
        ContactGreetingStyle.twoNames,
      );
      // Un recibo anterior a la columna no la trae: primer nombre.
      expect(
          ContactGreetingStyle.fromWire(null), ContactGreetingStyle.firstName);
      expect(
        ContactGreetingStyle.fromWire('apodo'),
        ContactGreetingStyle.firstName,
      );
    });

    test('a un contacto sin nombre no se le saluda «Hola Contacto»', () {
      expect(
        usableContactGreetingName(
          fullName: unnamedWhatsAppContactName,
          style: ContactGreetingStyle.firstName,
        ),
        isNull,
      );
      expect(
        usableContactGreetingName(
          fullName: unnamedWhatsAppContactName,
          style: ContactGreetingStyle.custom,
          customName: 'Carla',
        ),
        'Carla',
      );
      expect(
        usableContactGreetingName(
          fullName: ' ',
          style: ContactGreetingStyle.twoNames,
        ),
        isNull,
      );
    });
  });

  group('el contacto y su comando', () {
    Map<String, dynamic> row({Object? style, Object? custom}) => {
          'id': 'c-1',
          'tenant_id': 't-1',
          'supplier_id': 's-1',
          'name': 'Ana Lucía Rivas',
          if (style != null) 'greeting_style': style,
          if (custom != null) 'greeting_custom_name': custom,
          'updated_at': '2026-11-19T12:00:00Z',
        };

    test('el contacto trae su saludo, y sin la columna es el primer nombre',
        () {
      final chosen =
          SupplierContact.fromJson(row(style: 'two_names', custom: null));
      expect(chosen.greetingStyle, ContactGreetingStyle.twoNames);
      expect(chosen.greetingName, 'Ana Lucía');

      final custom =
          SupplierContact.fromJson(row(style: 'custom', custom: 'Anita'));
      expect(custom.greetingName, 'Anita');

      final before = SupplierContact.fromJson(row());
      expect(before.greetingStyle, ContactGreetingStyle.firstName);
      expect(before.greetingName, 'Ana');
    });

    SaveSupplierContactCommand command({
      ContactGreetingStyle? style,
      String? custom,
    }) =>
        SaveSupplierContactCommand(
          operationId: '00000000-0000-4000-8000-000000000001',
          supplierId: 's-1',
          name: 'Ana Lucía Rivas',
          greetingStyle: style,
          greetingCustomName: custom,
        );

    test('el comando manda el saludo sólo cuando el formulario lo eligió', () {
      expect(command().toJson().containsKey('greeting_style'), isFalse);
      expect(command().toJson().containsKey('greeting_custom_name'), isFalse);

      final two =
          command(style: ContactGreetingStyle.twoNames, custom: 'x').toJson();
      expect(two['greeting_style'], 'two_names');
      expect(two['greeting_custom_name'], isNull);

      final custom =
          command(style: ContactGreetingStyle.custom, custom: ' Don  Pedro ')
              .toJson();
      expect(custom['greeting_style'], 'custom');
      expect(custom['greeting_custom_name'], 'Don Pedro');

      expect(
        () => command(style: ContactGreetingStyle.custom, custom: '  '),
        throwsArgumentError,
      );
    });
  });

  group('el saludo de un chat de proveedor', () {
    test('sale de la fila del contacto, como objeto o como lista', () {
      final contact = {
        'name': 'Ana Lucía Rivas',
        'greeting_style': 'two_names',
        'greeting_custom_name': null,
      };
      expect(supplierContactGreetingFromRow(contact), 'Ana Lucía');
      expect(supplierContactGreetingFromRow([contact]), 'Ana Lucía');
      expect(supplierContactGreetingFromRow(const []), isNull);
      expect(supplierContactGreetingFromRow(null), isNull);
      expect(
        supplierContactGreetingFromRow({
          'name': unnamedWhatsAppContactName,
          'greeting_style': 'first_name',
        }),
        isNull,
      );
    });

    test('la ficha vieja no saluda con el nombre provisorio', () {
      expect(
        resolveSupplierMessagingContactName({
          'sales_rep_name': unnamedWhatsAppContactName,
          'contact_person': 'Pedro Soto',
        }),
        'Pedro',
      );
      expect(
        resolveSupplierMessagingContactName({
          'sales_rep_name': unnamedWhatsAppContactName,
          'contact_person': null,
        }),
        isNull,
      );
    });
  });
}
