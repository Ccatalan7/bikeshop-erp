import 'package:flutter/material.dart';

import '../providers/email_provider.dart';
import '../work/mail_work_words.dart';
import 'mail_chrome.dart';

/// Un correo de la vista Normal, dibujado con la misma fila de la vista
/// Inteligente ([MailListRow]): marca del remitente, punto de no leído, hora,
/// asunto y el comienzo del correo como línea de detalle.
class EmailListItemUnified extends StatelessWidget {
  final Email email;
  final bool isSelected;

  /// En Enviados y Borradores el interlocutor de la fila es el destinatario
  /// («Para: …»), no el remitente — que ahí siempre sería uno mismo.
  final bool showsRecipient;

  /// En la bandeja unida de varias cuentas: el logo de la cuenta del correo.
  final bool showAccount;
  final bool compact;
  final VoidCallback onTap;

  const EmailListItemUnified({
    super.key,
    required this.email,
    required this.isSelected,
    this.showsRecipient = false,
    this.showAccount = true,
    this.compact = false,
    required this.onTap,
  });

  String get _recipientName {
    final to = email.toAddress.trim();
    if (to.isEmpty) return '(sin destinatario)';
    final first = to.split(',').first.trim();
    final match = RegExp(r'^"?([^"<]+)"?\s*<').firstMatch(first);
    return match?.group(1)?.trim() ?? first.split('@').first;
  }

  @override
  Widget build(BuildContext context) {
    final counterpart = showsRecipient ? _recipientName : email.senderName;
    final summary = email.summary?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return MailListRow(
      title: showsRecipient ? 'Para $counterpart' : counterpart,
      markName: counterpart.isEmpty ? email.senderEmail : counterpart,
      accountBadge: showAccount ? mailAccountLogo(email.providerId) : null,
      time: MailWords.shortTime(email.receivedTime, DateTime.now()),
      subject: email.subject,
      detail: summary,
      hasAttachment: email.hasAttachment,
      unread: !email.isRead,
      selected: isSelected,
      compact: compact,
      onTap: onTap,
    );
  }
}
