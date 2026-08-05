import 'package:flutter/material.dart';

/// Carpetas canónicas del módulo de correo, neutrales al proveedor.
///
/// El conjunto es cerrado a propósito: son las cinco carpetas que Gmail y
/// Zoho garantizan como carpetas de sistema, y las únicas que la bandeja
/// unificada puede fusionar entre cuentas sin inventar equivalencias. Las
/// carpetas personalizadas de una cuenta no entran aquí: pertenecen a un solo
/// proveedor y romperían la unificación.
enum MailFolder { inbox, sent, drafts, spam, trash }

extension MailFolderPresentation on MailFolder {
  String get label => switch (this) {
        MailFolder.inbox => 'Bandeja de entrada',
        MailFolder.sent => 'Enviados',
        MailFolder.drafts => 'Borradores',
        MailFolder.spam => 'Spam',
        MailFolder.trash => 'Papelera',
      };

  IconData get icon => switch (this) {
        MailFolder.inbox => Icons.inbox_outlined,
        MailFolder.sent => Icons.send_outlined,
        MailFolder.drafts => Icons.drafts_outlined,
        MailFolder.spam => Icons.report_gmailerrorred_outlined,
        MailFolder.trash => Icons.delete_outline,
      };

  /// Label de sistema que Gmail usa para esta carpeta en `users.messages`.
  String get gmailLabelId => switch (this) {
        MailFolder.inbox => 'INBOX',
        MailFolder.sent => 'SENT',
        MailFolder.drafts => 'DRAFT',
        MailFolder.spam => 'SPAM',
        MailFolder.trash => 'TRASH',
      };

  /// En Enviados y Borradores el interlocutor es el destinatario, no el
  /// remitente — igual que en Gmail/Outlook, la fila muestra «Para: …».
  bool get showsRecipientAsCounterpart =>
      this == MailFolder.sent || this == MailFolder.drafts;
}

/// Resuelve la carpeta canónica de una carpeta remota de Zoho.
///
/// Zoho identifica sus carpetas de sistema con `folderType` («Inbox»,
/// «Sent», «Drafts», «Spam», «Trash»); el nombre visible puede venir
/// localizado o editado, así que sólo se usa como respaldo cuando el tipo no
/// llega. Devuelve `null` para carpetas personalizadas.
MailFolder? resolveZohoSystemFolder({
  String? folderType,
  String? folderName,
}) {
  final type = folderType?.trim().toLowerCase();
  switch (type) {
    case 'inbox':
      return MailFolder.inbox;
    case 'sent':
    case 'sent items':
      return MailFolder.sent;
    case 'drafts':
      return MailFolder.drafts;
    case 'spam':
    case 'junk':
      return MailFolder.spam;
    case 'trash':
      return MailFolder.trash;
  }

  final name = folderName?.trim().toLowerCase();
  return switch (name) {
    'inbox' || 'bandeja de entrada' => MailFolder.inbox,
    'sent' || 'sent items' || 'enviados' => MailFolder.sent,
    'drafts' || 'borradores' => MailFolder.drafts,
    'spam' || 'junk' || 'correo no deseado' => MailFolder.spam,
    'trash' || 'papelera' => MailFolder.trash,
    _ => null,
  };
}
