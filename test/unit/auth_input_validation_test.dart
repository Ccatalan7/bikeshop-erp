import 'package:vinabike_erp/shared/utils/auth_input_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthInputValidation', () {
    test('keeps existing six-character passwords valid for sign-in', () {
      expect(
        AuthInputValidation.validatePassword(
          'abc123',
          isNewPassword: false,
        ),
        isNull,
      );
    });

    test('requires stronger passwords only for new credentials', () {
      expect(
        AuthInputValidation.validatePassword(
          'abc123',
          isNewPassword: true,
        ),
        isNotNull,
      );
      expect(
        AuthInputValidation.validatePassword(
          'solocontrasena',
          isNewPassword: true,
        ),
        contains('letra y un número'),
      );
      expect(
        AuthInputValidation.validatePassword(
          'segura123',
          isNewPassword: true,
        ),
        isNull,
      );
    });

    test('validates confirmation without weakening the password policy', () {
      expect(
        AuthInputValidation.validatePasswordConfirmation(
          'segura124',
          password: 'segura123',
        ),
        'Las contraseñas no coinciden',
      );
      expect(
        AuthInputValidation.validatePasswordConfirmation(
          'segura123',
          password: 'segura123',
        ),
        isNull,
      );
    });

    test('requires the stricter policy for administrator-managed passwords',
        () {
      expect(
        AuthInputValidation.validateAdminManagedPassword('Segura123!'),
        contains('12 y 128'),
      );
      expect(
        AuthInputValidation.validateAdminManagedPassword('sinmayuscula123!'),
        contains('mayúscula'),
      );
      expect(
        AuthInputValidation.validateAdminManagedPassword('SinSimbolo123'),
        contains('símbolo'),
      );
      expect(
        AuthInputValidation.validateAdminManagedPassword('Valida Worker1!'),
        isNull,
      );
      expect(
        AuthInputValidation.validateAdminManagedPassword(
          'InvalidaWorker1!\n',
        ),
        contains('control'),
      );
    });

    test('builds a URL-safe tenant subdomain from Spanish shop names', () {
      expect(
        AuthInputValidation.tenantSubdomain('  Taller Ñandú Viña  '),
        'taller-nandu-vina',
      );
      expect(
        AuthInputValidation.validateShopName('!!!'),
        contains('letras o números'),
      );
    });

    test('rejects malformed email without rejecting a normal address', () {
      expect(AuthInputValidation.validateEmail('persona@ejemplo.cl'), isNull);
      expect(AuthInputValidation.validateEmail('persona@'), isNotNull);
      expect(
          AuthInputValidation.validateEmail('persona @ejemplo.cl'), isNotNull);
    });
  });
}
