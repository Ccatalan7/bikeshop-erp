import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/mail/models/mail_folder.dart';

/// El conjunto de carpetas canónicas es cerrado y su mapeo por proveedor es
/// parte del contrato de seguridad: la edge function de Gmail sólo acepta los
/// cinco labels de sistema, y Zoho resuelve por `folderType` con el nombre
/// como respaldo — nunca al revés, porque el nombre visible puede venir
/// localizado o editado por el usuario.
void main() {
  test('los cinco labels de Gmail coinciden con la allowlist del servidor',
      () {
    // Debe calzar 1:1 con `allowedListLabels` en
    // supabase/functions/gmail-oauth/index.ts.
    expect(
      MailFolder.values.map((folder) => folder.gmailLabelId).toSet(),
      {'INBOX', 'SENT', 'DRAFT', 'SPAM', 'TRASH'},
    );
  });

  test('Zoho resuelve por folderType aunque el nombre venga localizado', () {
    expect(
      resolveZohoSystemFolder(folderType: 'Sent', folderName: 'Enviados'),
      MailFolder.sent,
    );
    expect(
      resolveZohoSystemFolder(folderType: 'Spam', folderName: 'Correo malo'),
      MailFolder.spam,
    );
    expect(
      resolveZohoSystemFolder(folderType: 'Trash', folderName: 'Basurero'),
      MailFolder.trash,
    );
  });

  test('sin folderType, el nombre estándar o localizado es el respaldo', () {
    expect(
      resolveZohoSystemFolder(folderName: 'Bandeja de entrada'),
      MailFolder.inbox,
    );
    expect(resolveZohoSystemFolder(folderName: 'Junk'), MailFolder.spam);
    expect(
      resolveZohoSystemFolder(folderName: 'Papelera'),
      MailFolder.trash,
    );
  });

  test('una carpeta personalizada nunca se disfraza de carpeta de sistema',
      () {
    expect(
      resolveZohoSystemFolder(folderType: 'Custom', folderName: 'Facturas'),
      isNull,
    );
    expect(resolveZohoSystemFolder(folderName: 'Proveedores'), isNull);
    expect(resolveZohoSystemFolder(), isNull);
  });

  test('Enviados y Borradores muestran al destinatario como interlocutor',
      () {
    expect(
      MailFolder.values
          .where((folder) => folder.showsRecipientAsCounterpart)
          .toSet(),
      {MailFolder.sent, MailFolder.drafts},
    );
  });
}
