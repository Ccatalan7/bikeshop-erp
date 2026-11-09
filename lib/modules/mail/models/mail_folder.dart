import 'package:flutter/material.dart';

/// Qué es una carpeta del módulo de correo.
///
/// Las cinco primeras son las carpetas de sistema que Gmail y Zoho garantizan:
/// la bandeja unificada las fusiona entre cuentas. [account] es cualquier otra
/// carpeta de una cuenta: las que Zoho llena solo (Notification, Newsletter),
/// Archivar y Pospuesto, las carpetas que crea el usuario, y las categorías y
/// etiquetas de Gmail.
enum MailFolderKind { inbox, sent, drafts, spam, trash, account }

/// Una carpeta del módulo de correo, neutral al proveedor.
///
/// Las de sistema son constantes ([inbox], [sent], [drafts], [spam],
/// [trash]) y se leen en todas las cuentas a la vez. Una carpeta de cuenta
/// ([MailFolder.account]) pertenece a un solo proveedor: se lista desde ese
/// proveedor y sólo él la lee ([appliesTo]). Antes el conjunto era cerrado y
/// el ERP no mostraba nada fuera de las cinco: un código de verificación que
/// Zoho archivó en «Notification» no aparecía en ninguna parte (2026-11-08).
@immutable
class MailFolder {
  const MailFolder._system(this.kind)
      : providerId = null,
        remoteId = null,
        displayName = null,
        unreadCount = 0;

  const MailFolder.account({
    required String this.providerId,
    required String this.remoteId,
    required String this.displayName,
    this.unreadCount = 0,
  }) : kind = MailFolderKind.account;

  final MailFolderKind kind;

  /// Proveedor dueño de una carpeta de cuenta; null en las de sistema.
  final String? providerId;

  /// Id remoto de una carpeta de cuenta: el `folderId` de Zoho o el id del
  /// label de Gmail. Null en las de sistema, que cada proveedor resuelve.
  final String? remoteId;

  /// Nombre que muestra el proveedor para una carpeta de cuenta.
  final String? displayName;

  /// No leídos que informó el proveedor al listar, cuando los informa.
  final int unreadCount;

  static const inbox = MailFolder._system(MailFolderKind.inbox);
  static const sent = MailFolder._system(MailFolderKind.sent);
  static const drafts = MailFolder._system(MailFolderKind.drafts);
  static const spam = MailFolder._system(MailFolderKind.spam);
  static const trash = MailFolder._system(MailFolderKind.trash);

  /// Las carpetas de sistema, en el orden del selector.
  static const List<MailFolder> values = [inbox, sent, drafts, spam, trash];

  bool get isSystem => kind != MailFolderKind.account;
  bool get isAccountFolder => kind == MailFolderKind.account;

  /// Identidad estable: `inbox`… en las de sistema y `<proveedor>:<id>` en
  /// las de cuenta. La igualdad no mira el contador de no leídos.
  String get name => isSystem ? kind.name : '$providerId:$remoteId';

  /// Si el proveedor [id] lee esta carpeta: las de sistema, todos; las de
  /// cuenta, sólo su dueño.
  bool appliesTo(String id) => isSystem || providerId == id;

  @override
  bool operator ==(Object other) => other is MailFolder && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'MailFolder($name)';
}

extension MailFolderPresentation on MailFolder {
  String get label => switch (kind) {
        MailFolderKind.inbox => 'Bandeja de entrada',
        MailFolderKind.sent => 'Enviados',
        MailFolderKind.drafts => 'Borradores',
        MailFolderKind.spam => 'Spam',
        MailFolderKind.trash => 'Papelera',
        MailFolderKind.account => displayName ?? remoteId ?? 'Carpeta',
      };

  IconData get icon => switch (kind) {
        MailFolderKind.inbox => Icons.inbox_outlined,
        MailFolderKind.sent => Icons.send_outlined,
        MailFolderKind.drafts => Icons.drafts_outlined,
        MailFolderKind.spam => Icons.report_gmailerrorred_outlined,
        MailFolderKind.trash => Icons.delete_outline,
        MailFolderKind.account => _accountFolderIcon(this),
      };

  /// Label de Gmail que lista esta carpeta en `users.messages`: el de sistema
  /// o, en una carpeta de cuenta de Gmail, su propio id.
  String get gmailLabelId => switch (kind) {
        MailFolderKind.inbox => 'INBOX',
        MailFolderKind.sent => 'SENT',
        MailFolderKind.drafts => 'DRAFT',
        MailFolderKind.spam => 'SPAM',
        MailFolderKind.trash => 'TRASH',
        MailFolderKind.account => remoteId ?? 'INBOX',
      };

  /// En Enviados y Borradores el interlocutor es el destinatario, no el
  /// remitente — igual que en Gmail/Outlook, la fila muestra «Para: …».
  bool get showsRecipientAsCounterpart =>
      kind == MailFolderKind.sent || kind == MailFolderKind.drafts;
}

IconData _accountFolderIcon(MailFolder folder) {
  final id = (folder.remoteId ?? '').toUpperCase();
  final name = (folder.displayName ?? '').toLowerCase();
  if (id == 'CATEGORY_UPDATES' ||
      name.contains('notification') ||
      name.contains('notificaci')) {
    return Icons.notifications_none_outlined;
  }
  if (id == 'CATEGORY_PROMOTIONS' || name.contains('newsletter')) {
    return Icons.campaign_outlined;
  }
  if (id == 'CATEGORY_SOCIAL') return Icons.people_outline;
  if (id == 'CATEGORY_FORUMS') return Icons.forum_outlined;
  if (id == 'STARRED') return Icons.star_outline;
  if (id == 'IMPORTANT') return Icons.label_important_outline;
  if (name.contains('archiv')) return Icons.archive_outlined;
  if (name.contains('pospuest') || name.contains('snooze')) {
    return Icons.snooze_outlined;
  }
  return folder.providerId == 'gmail'
      ? Icons.label_outline
      : Icons.folder_outlined;
}

/// Resuelve la carpeta canónica de una carpeta remota de Zoho.
///
/// Zoho identifica sus carpetas de sistema con `folderType` («Inbox»,
/// «Sent», «Drafts», «Spam», «Trash»); el nombre visible puede venir
/// localizado o editado, así que sólo se usa como respaldo cuando el tipo no
/// llega. Devuelve `null` para carpetas que no son de sistema.
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
    'sent' || 'sent items' || 'enviados' || 'enviado' => MailFolder.sent,
    'drafts' || 'borradores' => MailFolder.drafts,
    'spam' || 'junk' || 'correo no deseado' => MailFolder.spam,
    'trash' || 'papelera' => MailFolder.trash,
    _ => null,
  };
}

/// Carpetas de Zoho que no guardan correo para leer: plantillas y la bandeja
/// de salida, que sólo retiene lo que se está enviando.
bool isZohoNonMailFolder({String? folderType, String? folderName}) {
  final type = folderType?.trim().toLowerCase() ?? '';
  final name = folderName?.trim().toLowerCase() ?? '';
  return type == 'templates' ||
      type == 'outbox' ||
      name == 'templates' ||
      name == 'plantillas' ||
      name == 'outbox' ||
      name == 'bandeja de salida';
}

/// Nombre en español de las carpetas propias de Zoho que su API entrega en
/// inglés; Notification y Newsletter quedan como las muestra Zoho en español.
const Map<String, String> _zohoFolderNames = {
  'snoozed': 'Pospuesto',
  'archive': 'Archivar',
};

/// Las carpetas de una cuenta de Zoho, separadas en las cinco de sistema y
/// las de cuenta.
///
/// Zoho entrega con `folderType` «Inbox» no sólo la bandeja de entrada sino
/// también las carpetas que llena su filtro inteligente (Notification,
/// Newsletter) y las del usuario: el tipo solo no identifica la entrada. La
/// entrada es la de ruta `/Inbox` (o nombre «Inbox»), y si no viene ninguna
/// así, la primera de ese tipo. Leer sólo el tipo escondía Notification —
/// donde Zoho archivó el código de verificación de Meta (2026-11-08).
({Map<MailFolder, String> system, List<MailFolder> account}) resolveZohoFolders(
    List<Map<String, dynamic>> rawFolders) {
  final candidates = <MailFolder, List<Map<String, dynamic>>>{};
  for (final raw in rawFolders) {
    final folderId = raw['folderId']?.toString().trim() ?? '';
    if (folderId.isEmpty) continue;
    final resolved = resolveZohoSystemFolder(
      folderType: raw['folderType']?.toString(),
      folderName: raw['folderName']?.toString(),
    );
    if (resolved != null) {
      (candidates[resolved] ??= <Map<String, dynamic>>[]).add(raw);
    }
  }

  final system = <MailFolder, String>{};
  candidates.forEach((folder, list) {
    final canonical = list.where((raw) {
      final path = raw['path']?.toString().trim().toLowerCase() ?? '';
      final name = raw['folderName']?.toString().trim().toLowerCase() ?? '';
      return switch (folder.kind) {
        MailFolderKind.inbox =>
          path == '/inbox' || name == 'inbox' || name == 'bandeja de entrada',
        _ => path.split('/').where((part) => part.isNotEmpty).length <= 1,
      };
    }).firstOrNull;
    system[folder] = (canonical ?? list.first)['folderId'].toString().trim();
  });

  final systemIds = system.values.toSet();
  final account = <MailFolder>[];
  for (final raw in rawFolders) {
    final folderType = raw['folderType']?.toString();
    final folderName = raw['folderName']?.toString();
    final folderId = raw['folderId']?.toString().trim() ?? '';
    if (folderId.isEmpty || systemIds.contains(folderId)) continue;
    if (isZohoNonMailFolder(folderType: folderType, folderName: folderName)) {
      continue;
    }
    final path = raw['path']?.toString().trim() ?? '';
    final rawLabel = (folderName?.trim().isNotEmpty ?? false)
        ? folderName!.trim()
        : path.replaceAll(RegExp(r'^/+'), '');
    final label = _zohoFolderNames[rawLabel.toLowerCase()] ?? rawLabel;
    account.add(MailFolder.account(
      providerId: 'zoho',
      remoteId: folderId,
      displayName: label.isEmpty ? folderId : label,
      unreadCount: int.tryParse(raw['unreadCount']?.toString() ?? '') ?? 0,
    ));
  }
  return (system: system, account: account);
}

/// Las carpetas de cuenta de Zoho: todo lo que no es una de las cinco de
/// sistema y guarda correo. Respeta el orden de Zoho.
List<MailFolder> zohoAccountFolders(List<Map<String, dynamic>> rawFolders) =>
    resolveZohoFolders(rawFolders).account;

/// Nombres en español de los labels de sistema de Gmail que no son carpetas
/// canónicas. Las categorías siguen los nombres de Gmail en español.
const Map<String, String> _gmailSystemLabelNames = {
  'CATEGORY_PERSONAL': 'Principal',
  'CATEGORY_UPDATES': 'Notificaciones',
  'CATEGORY_PROMOTIONS': 'Promociones',
  'CATEGORY_SOCIAL': 'Social',
  'CATEGORY_FORUMS': 'Foros',
  'STARRED': 'Destacados',
  'IMPORTANT': 'Importantes',
};

/// Las carpetas de cuenta de Gmail: categorías, destacados, importantes y
/// las etiquetas del usuario. Los cinco labels canónicos y los técnicos
/// (UNREAD, CHAT) quedan fuera.
List<MailFolder> gmailAccountFolders(List<Map<String, dynamic>> rawLabels) {
  final system = <MailFolder>[];
  final user = <MailFolder>[];
  for (final raw in rawLabels) {
    final id = raw['id']?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    final unread = int.tryParse(raw['messagesUnread']?.toString() ?? '') ?? 0;
    final systemName = _gmailSystemLabelNames[id];
    if (systemName != null) {
      system.add(MailFolder.account(
        providerId: 'gmail',
        remoteId: id,
        displayName: systemName,
        unreadCount: unread,
      ));
      continue;
    }
    if (raw['type']?.toString().toLowerCase() != 'user') continue;
    final name = raw['name']?.toString().trim() ?? '';
    user.add(MailFolder.account(
      providerId: 'gmail',
      remoteId: id,
      displayName: name.isEmpty ? id : name,
      unreadCount: unread,
    ));
  }
  final order = _gmailSystemLabelNames.keys.toList(growable: false);
  system.sort(
    (a, b) => order.indexOf(a.remoteId!).compareTo(order.indexOf(b.remoteId!)),
  );
  user.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return [...system, ...user];
}
