import 'package:flutter/foundation.dart';

/// Las vistas del correo que trabaja (`mail_inbox_v1`).
enum MailView {
  today('today', 'Para hoy'),
  waiting('waiting', 'Esperando'),
  all('all', 'Todo'),
  archived('archived', 'Archivo');

  const MailView(this.code, this.label);

  final String code;
  final String label;
}

/// El estado de la acción de un correo, calculado del registro cada vez
/// (`mail_message_state_internal`). Nunca se guarda en el correo: si alguien
/// ya registró la factura o el pago por otro lado, aquí llega hecho.
@immutable
class MailState {
  const MailState({
    required this.actionable,
    required this.done,
    this.action,
    this.doneText,
    this.doneAt,
    this.doneBy,
    this.waitingSince,
    this.overdue = false,
    this.remindTo,
  });

  const MailState.none()
      : actionable = false,
        done = false,
        action = null,
        doneText = null,
        doneAt = null,
        doneBy = null,
        waitingSince = null,
        overdue = false,
        remindTo = null;

  factory MailState.fromJson(Object? raw) {
    if (raw is! Map) return const MailState.none();
    return MailState(
      actionable: raw['actionable'] == true,
      done: raw['done'] == true,
      action: _text(raw['action']),
      doneText: _text(raw['done_text']),
      doneAt: _date(raw['done_at']),
      doneBy: _text(raw['done_by']),
      waitingSince: _date(raw['waiting_since']),
      overdue: raw['overdue'] == true,
      remindTo: _text(raw['remind_to']),
    );
  }

  final bool actionable;
  final bool done;
  final String? action;
  final String? doneText;
  final DateTime? doneAt;
  final String? doneBy;

  /// Lo que espera respuesta de otro (`remind`): desde cuándo, si ya venció
  /// (3 días lo que mandamos, 5 un reclamo) y a quién va el recordatorio.
  final DateTime? waitingSince;
  final bool overdue;
  final String? remindTo;

  bool get pending => actionable && !done;

  bool get waiting => action == 'remind' && actionable && !done;

  /// Lo hizo una persona con «Hecho» en el correo (y se puede deshacer aquí).
  bool get markedByPerson => done && doneText == 'Marcado como hecho';
}

/// Un registro del ERP al que el correo está ligado.
@immutable
class MailLink {
  const MailLink({
    required this.type,
    required this.id,
    required this.primary,
    this.source,
    this.confidence,
    this.label,
    this.detail,
    this.imageUrl,
  });

  factory MailLink.fromJson(Map<String, dynamic> json) => MailLink(
        type: _text(json['type']) ?? '',
        id: _text(json['id']) ?? '',
        primary: json['primary'] == true,
        source: _text(json['source']),
        confidence: (json['confidence'] as num?)?.toDouble(),
        label: _text(json['label']),
        detail: _text(json['detail']),
        imageUrl: _text(json['image_url']),
      );

  final String type;
  final String id;
  final bool primary;
  final String? source;
  final double? confidence;
  final String? label;
  final String? detail;
  final String? imageUrl;

  /// Ligado por una regla segura (número, documento, remitente) o a mano.
  bool get certain => source == 'person' || (confidence ?? 1) >= 0.9;
}

@immutable
class MailAttachmentRef {
  const MailAttachmentRef({
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.inline,
    this.attachmentId,
    this.partId,
  });

  factory MailAttachmentRef.fromJson(Map<String, dynamic> json) =>
      MailAttachmentRef(
        filename: _text(json['filename']) ?? 'adjunto',
        mimeType: _text(json['mime_type']) ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
        inline: json['inline'] == true,
        attachmentId: _text(json['attachment_id']),
        partId: _text(json['part_id']),
      );

  final String filename;
  final String mimeType;
  final int size;
  final bool inline;
  final String? attachmentId;
  final String? partId;

  String get ref => attachmentId ?? partId ?? '';
}

/// Otro correo del mismo caso (el mismo envío, la misma orden de flete).
@immutable
class MailCaseEntry {
  const MailCaseEntry({
    required this.id,
    required this.subject,
    required this.receivedAt,
    required this.kind,
    required this.direction,
    this.fromName,
  });

  factory MailCaseEntry.fromJson(Map<String, dynamic> json) => MailCaseEntry(
        id: _text(json['id']) ?? '',
        subject: _text(json['subject']) ?? '',
        receivedAt: _date(json['received_at']) ?? DateTime.now(),
        kind: _text(json['kind']) ?? 'other',
        direction: _text(json['direction']) ?? 'in',
        fromName: _text(json['from_name']),
      );

  final String id;
  final String subject;
  final DateTime receivedAt;
  final String kind;
  final String direction;
  final String? fromName;
}

/// Un correo de las casillas de la empresa, como lo devuelve el servidor.
@immutable
class MailItem {
  const MailItem({
    required this.id,
    required this.mailbox,
    required this.provider,
    required this.providerMessageId,
    required this.direction,
    required this.fromAddress,
    required this.subject,
    required this.receivedAt,
    required this.read,
    required this.archived,
    required this.kind,
    required this.space,
    required this.facts,
    required this.links,
    required this.state,
    required this.attachments,
    required this.hasAttachments,
    this.to = const [],
    this.fromName,
    this.snippet,
    this.bodyText,
    this.partyType,
    this.partyId,
    this.partyLabel,
    this.kindSource,
    this.caseKey,
    this.caseEntries = const [],
  });

  factory MailItem.fromJson(Map<String, dynamic> json) {
    final links = (json['links'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => MailLink.fromJson(Map<String, dynamic>.from(raw)))
        .where((link) => link.id.isNotEmpty)
        .toList(growable: false);
    final attachments = (json['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (raw) => MailAttachmentRef.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList(growable: false);
    final caseEntries = (json['case'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => MailCaseEntry.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
    return MailItem(
      id: _text(json['id']) ?? '',
      mailbox: _text(json['mailbox']) ?? '',
      provider: _text(json['provider']) ?? '',
      providerMessageId: _text(json['provider_message_id']) ?? '',
      direction: _text(json['direction']) ?? 'in',
      fromAddress: _text(json['from_address']) ?? '',
      fromName: _text(json['from_name']),
      to: (json['to'] as List? ?? const []).map((e) => '$e').toList(),
      subject: _text(json['subject']) ?? '',
      snippet: _text(json['snippet']),
      bodyText: _text(json['body_text']),
      hasAttachments: json['has_attachments'] == true,
      attachments: attachments,
      receivedAt: _date(json['received_at']) ?? DateTime.now(),
      read: json['read'] == true,
      archived: json['archived'] == true,
      kind: _text(json['kind']) ?? 'other',
      kindSource: _text(json['kind_source']),
      space: _text(json['space']) ?? 'otros',
      partyType: _text(json['party_type']),
      partyId: _text(json['party_id']),
      partyLabel: _text(json['party_label']),
      facts: json['facts'] is Map
          ? Map<String, dynamic>.from(json['facts'] as Map)
          : const {},
      caseKey: _text(json['case_key']),
      links: links,
      state: MailState.fromJson(json['state']),
      caseEntries: caseEntries,
    );
  }

  final String id;
  final String mailbox;
  final String provider;
  final String providerMessageId;
  final String direction;
  final String fromAddress;
  final String? fromName;
  final List<String> to;
  final String subject;
  final String? snippet;
  final String? bodyText;
  final bool hasAttachments;
  final List<MailAttachmentRef> attachments;
  final DateTime receivedAt;
  final bool read;
  final bool archived;
  final String kind;
  final String? kindSource;
  final String space;
  final String? partyType;
  final String? partyId;
  final String? partyLabel;
  final Map<String, dynamic> facts;
  final String? caseKey;
  final List<MailLink> links;
  final MailState state;
  final List<MailCaseEntry> caseEntries;

  /// Quién escribe, como lo conoce el ERP: el proveedor, el banco, el cliente.
  String get senderTitle {
    final label = partyLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final name = fromName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return fromAddress.isEmpty ? 'Sin remitente' : fromAddress;
  }

  /// A quién le escribimos (lo que mandamos): el cliente o el proveedor que
  /// el ERP reconoce en los destinatarios, o la primera dirección.
  String get recipientTitle {
    final party = facts['to_party'];
    if (party is Map) {
      final label = '${party['label'] ?? ''}'.trim();
      if (label.isNotEmpty) return label;
      final address = '${party['address'] ?? ''}'.trim();
      if (address.isNotEmpty) return address;
    }
    return to.isEmpty ? 'Sin destinatario' : to.first;
  }

  /// Quién está al otro lado: quien escribió, o a quién le escribimos.
  String get otherSideTitle =>
      direction == 'out' ? recipientTitle : senderTitle;

  /// El logo de quien está al otro lado, si el ERP lo tiene.
  String? get otherSideImageUrl {
    if (direction != 'out') return senderImageUrl;
    final party = facts['to_party'];
    final id = party is Map ? '${party['id'] ?? ''}' : '';
    if (id.isEmpty) return null;
    for (final link in links) {
      if ((link.type == 'supplier' || link.type == 'customer') &&
          link.id == id &&
          (link.imageUrl ?? '').isNotEmpty) {
        return link.imageUrl;
      }
    }
    return null;
  }

  /// Un desconocido que se presenta como un banco (aviso de seguridad).
  bool get fakeBank => facts['fake_bank'] == true;

  String? get bankName {
    final value = facts['bank_name'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  MailLink? get primaryLink {
    for (final link in links) {
      if (link.primary) return link;
    }
    return links.isEmpty ? null : links.first;
  }

  /// El logo del remitente, si el ERP lo tiene (cliente o proveedor ligado).
  String? get senderImageUrl {
    for (final link in links) {
      if ((link.type == 'supplier' || link.type == 'customer') &&
          link.id == partyId &&
          (link.imageUrl ?? '').isNotEmpty) {
        return link.imageUrl;
      }
    }
    return null;
  }

  List<MailAttachmentRef> get visibleAttachments =>
      attachments.where((attachment) => !attachment.inline).toList();

  num? get amount => facts['amount'] is num
      ? facts['amount'] as num
      : num.tryParse('${facts['amount'] ?? ''}');

  String? get payer {
    final value = facts['payer'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  MailItem copyWith({MailState? state, bool? read, bool? archived}) => MailItem(
        id: id,
        mailbox: mailbox,
        provider: provider,
        providerMessageId: providerMessageId,
        direction: direction,
        fromAddress: fromAddress,
        fromName: fromName,
        to: to,
        subject: subject,
        snippet: snippet,
        bodyText: bodyText,
        hasAttachments: hasAttachments,
        attachments: attachments,
        receivedAt: receivedAt,
        read: read ?? this.read,
        archived: archived ?? this.archived,
        kind: kind,
        kindSource: kindSource,
        space: space,
        partyType: partyType,
        partyId: partyId,
        partyLabel: partyLabel,
        facts: facts,
        caseKey: caseKey,
        links: links,
        state: state ?? this.state,
        caseEntries: caseEntries,
      );
}

/// Los conteos de las pestañas y el estado de las casillas (`mail_counts_v1`).
@immutable
class MailCounts {
  const MailCounts({
    this.today = 0,
    this.waiting = 0,
    this.unread = 0,
    this.archived = 0,
    this.spaces = const {},
    this.mailboxes = const [],
  });

  factory MailCounts.fromJson(Object? raw) {
    if (raw is! Map) return const MailCounts();
    final spaces = <String, int>{};
    final rawSpaces = raw['spaces'];
    if (rawSpaces is Map) {
      for (final entry in rawSpaces.entries) {
        spaces['${entry.key}'] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return MailCounts(
      today: (raw['today'] as num?)?.toInt() ?? 0,
      waiting: (raw['waiting'] as num?)?.toInt() ?? 0,
      unread: (raw['unread'] as num?)?.toInt() ?? 0,
      archived: (raw['archived'] as num?)?.toInt() ?? 0,
      spaces: spaces,
      mailboxes: (raw['mailboxes'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => MailboxStatus.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false),
    );
  }

  final int today;
  final int waiting;
  final int unread;
  final int archived;
  final Map<String, int> spaces;
  final List<MailboxStatus> mailboxes;

  int countFor(MailView view) => switch (view) {
        MailView.today => today,
        MailView.waiting => waiting,
        MailView.all => 0,
        MailView.archived => 0,
      };
}

@immutable
class MailboxStatus {
  const MailboxStatus({
    required this.address,
    required this.provider,
    required this.hasError,
    this.lastSyncedAt,
    this.today = 0,
  });

  factory MailboxStatus.fromJson(Map<String, dynamic> json) => MailboxStatus(
        address: _text(json['address']) ?? '',
        provider: _text(json['provider']) ?? '',
        hasError: json['error'] == true,
        lastSyncedAt: _date(json['last_synced_at']),
        today: (json['today'] as num?)?.toInt() ?? 0,
      );

  final String address;
  final String provider;
  final bool hasError;
  final DateTime? lastSyncedAt;

  /// Lo «Para hoy» de esta casilla (20261106240000), para el selector.
  final int today;
}

/// Un cobro al que puede corresponder una transferencia
/// (`mail_payment_candidates_v1`): una factura con saldo o un pedido web sin
/// pagar.
@immutable
class MailPaymentCandidate {
  const MailPaymentCandidate({
    required this.type,
    required this.id,
    required this.label,
    required this.who,
    required this.balance,
    required this.exact,
    required this.named,
    this.at,
  });

  factory MailPaymentCandidate.fromJson(Map<String, dynamic> json) =>
      MailPaymentCandidate(
        type: _text(json['type']) ?? '',
        id: _text(json['id']) ?? '',
        label: _text(json['label']) ?? '',
        who: _text(json['who']) ?? '',
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        exact: json['exact'] == true,
        named: json['named'] == true,
        at: _date(json['at']),
      );

  /// `sales_invoice` u `online_order`.
  final String type;
  final String id;
  final String label;
  final String who;
  final double balance;

  /// El saldo es exactamente lo transferido.
  final bool exact;

  /// Es de quien transfirió (el nombre del aviso calza).
  final bool named;
  final DateTime? at;

  bool get isOrder => type == 'online_order';
}

/// Una casilla conectada en el ERP, con su estado de sincronización.
@immutable
class MailboxInfo {
  const MailboxInfo({
    required this.id,
    required this.provider,
    required this.address,
    required this.active,
    this.lastSyncedAt,
    this.lastSyncError,
    this.backfilledAt,
  });

  factory MailboxInfo.fromJson(Map<String, dynamic> json) => MailboxInfo(
        id: _text(json['id']) ?? '',
        provider: _text(json['provider']) ?? '',
        address: _text(json['address']) ?? '',
        active: json['is_active'] == true,
        lastSyncedAt: _date(json['last_synced_at']),
        lastSyncError: _text(json['last_sync_error']),
        backfilledAt: _date(json['backfilled_at']),
      );

  final String id;
  final String provider;
  final String address;
  final bool active;
  final DateTime? lastSyncedAt;
  final String? lastSyncError;
  final DateTime? backfilledAt;

  String get providerLabel => provider == 'gmail'
      ? 'Gmail'
      : provider == 'zoho'
          ? 'Zoho'
          : provider;
}

/// Un adjunto traído del proveedor para abrirlo.
@immutable
class MailAttachmentData {
  const MailAttachmentData({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  final String filename;
  final String mimeType;
  final Uint8List bytes;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}
