import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/mail/models/mail_folder.dart';

/// Las cinco carpetas de sistema se fusionan entre cuentas; todas las demás
/// son carpetas de una cuenta y sólo las lee su proveedor. Zoho resuelve las
/// de sistema por `folderType` con el nombre como respaldo — nunca al revés,
/// porque el nombre visible puede venir localizado o editado por el usuario.
void main() {
  test('las cinco carpetas de sistema usan los labels de sistema de Gmail', () {
    expect(
      MailFolder.values.map((folder) => folder.gmailLabelId).toSet(),
      {'INBOX', 'SENT', 'DRAFT', 'SPAM', 'TRASH'},
    );
  });

  test('una carpeta de cuenta es de un solo proveedor y se identifica por id',
      () {
    const notification = MailFolder.account(
      providerId: 'zoho',
      remoteId: '8323786000000009001',
      displayName: 'Notification',
      unreadCount: 2,
    );
    expect(notification.appliesTo('zoho'), isTrue);
    expect(notification.appliesTo('gmail'), isFalse);
    expect(MailFolder.inbox.appliesTo('gmail'), isTrue);
    expect(notification.name, 'zoho:8323786000000009001');
    // Los no leídos cambian; la carpeta sigue siendo la misma.
    expect(
      notification,
      const MailFolder.account(
        providerId: 'zoho',
        remoteId: '8323786000000009001',
        displayName: 'Notification',
      ),
    );
    expect(notification == MailFolder.inbox, isFalse);
  });

  test('Zoho: Notification, Newsletter, Archivar y Pospuesto son carpetas', () {
    final folders = zohoAccountFolders([
      {
        'folderId': '1',
        'folderName': 'Bandeja de entrada',
        'folderType': 'Inbox'
      },
      {'folderId': '2', 'folderName': 'Borradores', 'folderType': 'Drafts'},
      {'folderId': '3', 'folderName': 'Plantillas', 'folderType': 'Templates'},
      {'folderId': '4', 'folderName': 'Pospuesto', 'folderType': 'Snoozed'},
      {'folderId': '5', 'folderName': 'Enviado', 'folderType': 'Sent'},
      {'folderId': '6', 'folderName': 'Spam', 'folderType': 'Spam'},
      {'folderId': '7', 'folderName': 'Papelera', 'folderType': 'Trash'},
      {'folderId': '8', 'folderName': 'Archivar', 'folderType': 'Archive'},
      {
        'folderId': '9',
        'folderName': 'Bandeja de salida',
        'folderType': 'Outbox'
      },
      {
        'folderId': '10',
        'folderName': 'Newsletter',
        'folderType': 'Newsletter'
      },
      {
        'folderId': '11',
        'folderName': 'Notification',
        'folderType': 'Notification'
      },
      {'folderId': '12', 'folderName': 'Proveedores', 'folderType': 'Custom'},
    ]);
    expect(
      folders.map((folder) => folder.label).toList(),
      ['Pospuesto', 'Archivar', 'Newsletter', 'Notification', 'Proveedores'],
    );
    expect(folders.every((folder) => folder.providerId == 'zoho'), isTrue);
  });

  test(
      'Zoho entrega Notification y Newsletter con tipo Inbox: '
      'la entrada es la de ruta /Inbox', () {
    // Forma real de /folders en la cuenta contacto@vinabike.cl (2026-11-08).
    final resolved = resolveZohoFolders([
      {
        'folderId': '14',
        'folderName': 'Inbox',
        'folderType': 'Inbox',
        'path': '/Inbox'
      },
      {
        'folderId': '16',
        'folderName': 'Drafts',
        'folderType': 'Drafts',
        'path': '/Drafts'
      },
      {
        'folderId': '18',
        'folderName': 'Templates',
        'folderType': 'Templates',
        'path': '/Templates'
      },
      {
        'folderId': '20',
        'folderName': 'Snoozed',
        'folderType': 'Snoozed',
        'path': '/Snoozed'
      },
      {
        'folderId': '22',
        'folderName': 'Sent',
        'folderType': 'Sent',
        'path': '/Sent'
      },
      {
        'folderId': '24',
        'folderName': 'Spam',
        'folderType': 'Spam',
        'path': '/Spam'
      },
      {
        'folderId': '26',
        'folderName': 'Trash',
        'folderType': 'Trash',
        'path': '/Trash'
      },
      {
        'folderId': '28',
        'folderName': 'Outbox',
        'folderType': 'Outbox',
        'path': '/Outbox'
      },
      {
        'folderId': '9001',
        'folderName': 'Notification',
        'folderType': 'Inbox',
        'path': '/Notification'
      },
      {
        'folderId': '9011',
        'folderName': 'Newsletter',
        'folderType': 'Inbox',
        'path': '/Newsletter'
      },
      {
        'folderId': '9021',
        'folderName': 'Archive',
        'folderType': 'Archive',
        'path': '/Archive'
      },
    ]);
    expect(resolved.system[MailFolder.inbox], '14');
    expect(resolved.system[MailFolder.sent], '22');
    expect(
      resolved.account.map((folder) => folder.label).toList(),
      ['Pospuesto', 'Notification', 'Newsletter', 'Archivar'],
    );
    expect(resolved.account[1].remoteId, '9001');
  });

  test('si una carpeta del usuario llega antes que la entrada, gana /Inbox',
      () {
    final resolved = resolveZohoFolders([
      {
        'folderId': '30',
        'folderName': 'Proveedores',
        'folderType': 'Inbox',
        'path': '/Proveedores'
      },
      {
        'folderId': '14',
        'folderName': 'Inbox',
        'folderType': 'Inbox',
        'path': '/Inbox'
      },
    ]);
    expect(resolved.system[MailFolder.inbox], '14');
    expect(resolved.account.single.label, 'Proveedores');
  });

  test('Gmail: categorías y etiquetas del usuario, sin los labels técnicos',
      () {
    final folders = gmailAccountFolders([
      {'id': 'INBOX', 'name': 'INBOX', 'type': 'system'},
      {'id': 'UNREAD', 'name': 'UNREAD', 'type': 'system'},
      {
        'id': 'CATEGORY_PROMOTIONS',
        'name': 'CATEGORY_PROMOTIONS',
        'type': 'system'
      },
      {'id': 'Label_7', 'name': 'Proveedores', 'type': 'user'},
      {
        'id': 'CATEGORY_UPDATES',
        'name': 'CATEGORY_UPDATES',
        'type': 'system',
        'messagesUnread': 4
      },
      {'id': 'CHAT', 'name': 'CHAT', 'type': 'system'},
      {'id': 'STARRED', 'name': 'STARRED', 'type': 'system'},
    ]);
    expect(
      folders.map((folder) => folder.label).toList(),
      ['Notificaciones', 'Promociones', 'Destacados', 'Proveedores'],
    );
    expect(folders.first.unreadCount, 4);
    expect(folders.last.gmailLabelId, 'Label_7');
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

  test('una carpeta personalizada nunca se disfraza de carpeta de sistema', () {
    expect(
      resolveZohoSystemFolder(folderType: 'Custom', folderName: 'Facturas'),
      isNull,
    );
    expect(resolveZohoSystemFolder(folderName: 'Proveedores'), isNull);
    expect(resolveZohoSystemFolder(), isNull);
  });

  test('Enviados y Borradores muestran al destinatario como interlocutor', () {
    expect(
      MailFolder.values
          .where((folder) => folder.showsRecipientAsCounterpart)
          .toSet(),
      {MailFolder.sent, MailFolder.drafts},
    );
  });
}
