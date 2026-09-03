import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/supplier_whatsapp_phone.dart';

/// A qué número se le escribe por WhatsApp a un proveedor: el vendedor manda
/// y el Teléfono de la ficha es el respaldo, igual que en SQL.
void main() {
  test('el vendedor manda cuando tiene número (RBX, Andes, MKR)', () {
    expect(
      supplierWhatsAppPhone(
        phone: '+56225200600',
        salesRepPhone: '+56988182352',
      ),
      '+56988182352',
    );
    expect(
      supplierWhatsAppPhone(phone: null, salesRepPhone: '+56995082698'),
      '+56995082698',
    );
  });

  test('sin vendedor con número, el Teléfono de la ficha es el respaldo', () {
    expect(
      supplierWhatsAppPhone(phone: '+56934867574', salesRepPhone: null),
      '+56934867574',
    );
    expect(
      supplierWhatsAppPhone(phone: '+56934867574', salesRepPhone: '  '),
      '+56934867574',
    );
    expect(
      supplierWhatsAppPhone(phone: '+56934867574', salesRepPhone: '123'),
      '+56934867574',
    );
  });

  test('un número extranjero de 8+ dígitos sirve', () {
    expect(
      supplierWhatsAppPhone(phone: '+86 138 0013 8000', salesRepPhone: null),
      '+86 138 0013 8000',
    );
  });

  test('sin nada usable no se inventa un número', () {
    expect(supplierWhatsAppPhone(phone: null, salesRepPhone: null), isNull);
    expect(supplierWhatsAppPhone(phone: '223', salesRepPhone: ''), isNull);
  });

  test('usable es tener al menos 8 dígitos, con cualquier formato', () {
    expect(supplierPhoneIsUsable('+56 9 3486 7574'), isTrue);
    expect(supplierPhoneIsUsable('9348-6757'), isTrue);
    expect(supplierPhoneIsUsable('1234567'), isFalse);
    expect(supplierPhoneIsUsable(null), isFalse);
    expect(supplierPhoneDigits('+56 (9) 3486-7574'), '56934867574');
  });

  group('supplierThreadPhoneDiffers', () {
    test('el hilo viejo con el vendedor anterior difiere del registrado', () {
      expect(
        supplierThreadPhoneDiffers(
          threadPhone: '+56988155152',
          registeredPhone: '+56 9 3486 7574',
        ),
        isTrue,
      );
    });

    test('el mismo número en distinto formato no difiere', () {
      expect(
        supplierThreadPhoneDiffers(
          threadPhone: '56934867574',
          registeredPhone: '+56 9 3486 7574',
        ),
        isFalse,
      );
    });

    test('sin dos números usables no hay diferencia que declarar', () {
      expect(
        supplierThreadPhoneDiffers(
            threadPhone: null, registeredPhone: '+56934867574'),
        isFalse,
      );
      expect(
        supplierThreadPhoneDiffers(
            threadPhone: '+56934867574', registeredPhone: '123'),
        isFalse,
      );
    });
  });

  group('supplierContactPersonName', () {
    test('el hilo viejo lleva el nombre de perfil de quien escribió', () {
      expect(
        supplierContactPersonName(
          supplierName: 'Comercial Ciclo',
          bindingContactName: 'Fabiola',
          threadPhone: '56988155152',
          salesRepName: 'Victor',
          salesRepPhone: '+56934867574',
        ),
        'Fabiola',
      );
    });

    test(
        'el hilo con el número del vendedor lleva al vendedor aunque no haya contestado',
        () {
      expect(
        supplierContactPersonName(
          supplierName: 'Comercial Ciclo',
          bindingContactName: 'Comercial Ciclo',
          threadPhone: '56934867574',
          salesRepName: 'Victor',
          salesRepPhone: '+56934867574',
        ),
        'Victor',
      );
    });

    test('la empresa o un número guardados como nombre no son una persona', () {
      expect(
        supplierContactPersonName(
          supplierName: 'Comercial Ciclo',
          bindingContactName: 'comercial ciclo',
          threadPhone: '56911111111',
          salesRepName: null,
          salesRepPhone: null,
        ),
        isNull,
      );
      expect(
        supplierContactPersonName(
          supplierName: 'RBX',
          bindingContactName: '+56 9 1111 1111',
          threadPhone: '56911111111',
          salesRepName: '',
          salesRepPhone: null,
        ),
        isNull,
      );
    });
  });
}
