import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/mail/widgets/mail_error_diagnostic_banner.dart';

void main() {
  group('MailErrorDiagnostic', () {
    test('classifies Zoho OAuth function socket failures as network errors',
        () {
      final diagnostic = MailErrorDiagnostic.fromMessage(
        'No se pudo actualizar Zoho Mail: ClientException with '
        'SocketException: Connection reset by peer, errno = 54, '
        'uri=https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/zoho-oauth',
      );

      expect(diagnostic.kind, MailErrorKind.network);
      expect(diagnostic.label, 'Red/API');
    });

    test('still classifies explicit token failures as token errors', () {
      final diagnostic = MailErrorDiagnostic.fromMessage(
        'Token/OAuth Gmail: la conexión venció o fue revocada. '
        'Detalle: invalid_grant',
      );

      expect(diagnostic.kind, MailErrorKind.token);
      expect(diagnostic.label, 'Token/OAuth');
    });

    test('classifies the sanitized retry exhaustion copy as network', () {
      final diagnostic = MailErrorDiagnostic.fromMessage(
        'No se pudo actualizar Zoho Mail: Red/API: la conexión falló '
        'temporalmente. Mostrando correos guardados.',
      );

      expect(diagnostic.kind, MailErrorKind.network);
      expect(diagnostic.label, 'Red/API');
    });

    test('classifies a missing Zoho group scope as permissions', () {
      final diagnostic = MailErrorDiagnostic.fromMessage(
        'Permisos Zoho insuficientes: falta el scope '
        'ZohoMail.organization.groups.READ. Reconecta Zoho.',
      );

      expect(diagnostic.kind, MailErrorKind.permissions);
      expect(diagnostic.label, 'Permisos');
    });
  });
}
