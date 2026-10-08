// The portal's support chat (`/cuenta/chats`): what it says and how it
// reads a conversation. Flutter's `CustomerChatHubPage` and
// `CustomerChatView` and the HTML store's chat use these, so a word or a
// rule changes in one place (2026-10-08).

// ================================================================ the list

const customerChatTitle = 'Soporte';
const customerChatLead =
    'Escríbele a la tienda y al taller: pedidos, tu bici o lo que necesites.';
const customerChatNew = 'Nueva consulta';
const customerChatEmptyTitle = 'No tienes conversaciones.';
const customerChatEmptyBody =
    'Pregúntanos por un pedido, un repuesto o tu bici en el taller. Te '
    'respondemos aquí mismo.';
const customerChatNoMessages = 'Sin mensajes todavía';

/// The longest consultation or message the customer writes: the base's own
/// limit for the first one (`create_customer_support_request`, 8000), kept
/// for every message so both stores take the same text (2026-10-08).
const customerChatMessageMaxLength = 8000;

/// The longest «Solicitar cambios» note (`respond_to_action_request`, 1000).
const customerChatNoteMaxLength = 1000;

/// How long a text is for those limits: in code points, as PostgreSQL's
/// `length` counts it — not Dart's UTF-16 units (an emoji is two) nor
/// Flutter's characters (an accent written apart is one with its letter).
int customerChatLength(String text) => text.runes.length;

// ====================================================== a new consultation

const customerChatNewLead =
    'Cuéntanos qué necesitas. Si es por un pedido o tu bici, indica cuál.';
const customerChatNewHint = '¿En qué podemos ayudarte?';
const customerChatSend = 'Enviar';
const customerChatNewFailed =
    'No pudimos enviar tu consulta. Intenta de nuevo.';
const customerChatNewNoStore =
    'No pudimos enviar tu consulta. Recarga la página e intenta de nuevo.';

// ============================================================== the thread

const customerChatWaiting = 'Esperando respuesta del equipo…';
const customerChatRejected = 'Esta consulta fue cerrada.';
const customerChatUnavailable =
    'No pudimos abrir esta conversación. Vuelve a Soporte e inténtalo de '
    'nuevo.';
const customerChatArchived =
    'Esta conversación está archivada y se conserva como respaldo.';
const customerChatHint = 'Escribe un mensaje…';
const customerChatHintPending = 'Agregar más información…';

/// Where a message's time goes while it is on its way.
const customerChatSending = 'Enviando…';
const customerChatSendFailed =
    'No se envió el mensaje. El texto quedó listo para reintentar.';
const customerChatOlder = 'Cargar mensajes anteriores';
const customerChatStart = 'Inicio de la conversación';
const customerChatRetry = 'Reintentar';
const customerChatDetails = 'Ver detalles';

/// The conversation stopped updating (`ChatProvider`'s stream error).
const customerChatOffline =
    'La conversación perdió conexión. Tus mensajes visibles se conservaron.';
const customerChatOlderFailed = 'No pudimos cargar los mensajes anteriores.';

// ============================================================ attachments

const customerChatImage = 'Imagen';
const customerChatDocument = 'Documento';
const customerChatImageFailed = 'No se pudo cargar la imagen · Reintentar';
const customerChatFileRenewFailed = 'No se pudo renovar el acceso al adjunto.';

/// A file whose link could not be made: «Imagen no disponible · Reintentar».
String customerChatFileUnavailable(String label) =>
    '$label no disponible · Reintentar';

// ====================================================== the store's asks

const customerChatAskChanges = 'Solicitar cambios';
const customerChatAskChangesHint = 'Indica qué necesitas ajustar';
const customerChatCancel = 'Cancelar';
const customerChatAskChangesSend = 'Enviar solicitud';
const customerChatAccepted = 'Listo, le avisamos al taller.';
const customerChatDeclined = 'Enviamos tu pedido de cambios.';
const customerChatAnswerFailed = 'No se pudo registrar la respuesta.';

/// A rule of the base that refused the answer (`23514`: the quote expired,
/// is no longer pending…), in its own words, as Flutter shows it.
String customerChatAnswerRefused(String reason) =>
    'No se pudo registrar la respuesta: ${reason.trim()}';
const customerChatAnswerUncertain =
    'No pudimos confirmar la respuesta. Puede haberse guardado; vuelve a '
    'pulsar la misma opción para verificarla sin duplicar.';

/// What the composer and the banner say of a conversation's `status`, as
/// `CustomerChatView` reads it.
enum CustomerChatState {
  /// Still being read: nothing is said and nothing can be written.
  loading,

  /// Waiting for the team to take it; the customer can add more.
  pending,

  /// Open: the customer writes.
  open,

  /// Closed by the team, with its reason (`reject_reason`).
  rejected,

  /// Resolved, closed, archived or cancelled: kept as a record.
  archived,

  /// Not readable by this account, or gone.
  unavailable;

  static CustomerChatState of(String? status) =>
      switch ((status ?? '').trim().toLowerCase()) {
        'loading' => loading,
        'pending' => pending,
        'rejected' => rejected,
        'resolved' || 'closed' || 'archived' || 'cancelled' => archived,
        'unavailable' => unavailable,
        _ => open,
      };

  /// Whether the composer shows.
  bool get canWrite => this == pending || this == open;

  /// The line over the thread, or null.
  String? banner({String? rejectReason}) => switch (this) {
    pending => customerChatWaiting,
    rejected =>
      (rejectReason ?? '').trim().isEmpty
          ? customerChatRejected
          : rejectReason!.trim(),
    unavailable => customerChatUnavailable,
    archived => customerChatArchived,
    loading || open => null,
  };

  /// The composer's hint.
  String get hint =>
      this == pending ? customerChatHintPending : customerChatHint;
}

/// A day over the messages: «HOY», «AYER» or «dd/MM/yyyy», by the
/// customer's [today].
String customerChatDay(DateTime day, DateTime today) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  if (d == t) return 'Hoy';
  if (d == DateTime(t.year, t.month, t.day - 1)) return 'Ayer';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// A message's time, «HH:mm».
String customerChatTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// A request of the store in the chat (`type: action_request`): approve a
/// quote, confirm a delivery, a payment. Only the first two are answered
/// here, by the audited server command (`respond_to_action_request`).
class CustomerChatActionCard {
  const CustomerChatActionCard._({
    required this.actionType,
    required this.status,
    required this.title,
    required this.buttonLabel,
    required this.tag,
    required this.decision,
    required this.note,
  });

  factory CustomerChatActionCard.of(Map<String, dynamic> metadata) {
    final actionType = metadata['action_type']?.toString() ?? 'unknown';
    final status = metadata['status']?.toString() ?? 'pending';
    final amount = metadata['amount'];
    final (title, buttonLabel) = switch (actionType) {
      'approve_quote' => ('Presupuesto', 'Aprobar presupuesto'),
      'pay_now' => (
        'Pago solicitado',
        amount is num
            ? 'Monto: \$${amount.toStringAsFixed(0)}'
            : 'Revisa tu pedido',
      ),
      'confirm_delivery' => ('Confirmar entrega', 'Confirmar recibido'),
      _ => ('Acción requerida', 'Ver detalles'),
    };
    final tag = switch (status) {
      'accepted' => (
        actionType == 'approve_quote' ? 'Aprobado' : 'Listo',
        'success',
      ),
      'declined' => (
        actionType == 'approve_quote' ? 'Pediste cambios' : 'Rechazado',
        'quiet',
      ),
      'pending' => ('Espera tu respuesta', 'attention'),
      _ => null,
    };
    final note = metadata['response_note']?.toString().trim();
    return CustomerChatActionCard._(
      actionType: actionType,
      status: status,
      title: title,
      buttonLabel: buttonLabel,
      tag: tag,
      decision:
          actionType == 'approve_quote' || actionType == 'confirm_delivery',
      note: note == null || note.isEmpty ? null : note,
    );
  }

  final String actionType;
  final String status;
  final String title;
  final String buttonLabel;

  /// The label and kind of its tag (`success`, `quiet`, `attention`).
  final (String, String)? tag;

  /// Answered here: a quote or a delivery.
  final bool decision;

  /// What the customer wrote when asking for changes.
  final String? note;

  bool get pending => status == 'pending';

  /// A payment asked in the chat: the chat never opens a charge.
  String? get payNote => pending && actionType == 'pay_now'
      ? '$buttonLabel. El chat no abre cobros sin una sesión de pago '
            'autorizada; revisa el pedido o solicita un enlace vigente al '
            'equipo.'
      : null;

  /// Whether it can be answered now, and with «Solicitar cambios».
  bool get answerable => pending && decision;
  bool get canAskChanges => answerable && actionType == 'approve_quote';
}

// ======================================================= a message's file

/// The bucket of the chat's private files.
const customerChatFileBucket = 'chat-attachments';

/// How long a link to a chat file lasts, in seconds
/// (`MessagingAttachmentService.signedUrlLifetimeSeconds`).
const customerChatFileLinkSeconds = 300;

const _chatFileTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'txt': 'text/plain',
  'mp4': 'video/mp4',
  '3gp': 'video/3gpp',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
};

final _chatFileUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? _chatText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// The private file a message of [conversationId] carries, by
/// `MessagingAttachmentService.hasPrivateReference`: its path in
/// [customerChatFileBucket] (`<tenant>/<conversation>/<id>.<ext>`), or null.
String? customerChatFilePath(
  Map<String, dynamic> metadata,
  String conversationId,
) {
  final id = _chatText(metadata['attachment_id']);
  final bucket =
      _chatText(metadata['storageBucket']) ??
      _chatText(metadata['storage_bucket']);
  final path =
      _chatText(metadata['storagePath']) ?? _chatText(metadata['storage_path']);
  if (id == null || bucket != customerChatFileBucket || path == null) {
    return null;
  }
  final parts = path.split('/');
  if (parts.length != 3 ||
      !_chatFileUuid.hasMatch(parts[0]) ||
      parts[1] != conversationId ||
      !_chatFileUuid.hasMatch(parts[1]) ||
      !_chatFileUuid.hasMatch(id)) {
    return null;
  }
  final dot = parts[2].lastIndexOf('.');
  final extension = dot <= 0 ? '' : parts[2].substring(dot + 1).toLowerCase();
  return _chatFileTypes.containsKey(extension) && parts[2] == '$id.$extension'
      ? path
      : null;
}

/// Whether a message's file is a picture (`type: image`, or its
/// `content_type`).
bool customerChatFileIsImage(String? type, Map<String, dynamic> metadata) =>
    type == 'image' ||
    (metadata['content_type']?.toString().startsWith('image/') ?? false);

/// What a file is called in the chat: its name, or «Imagen» / «Documento».
String customerChatFileLabel(String? type, Map<String, dynamic> metadata) {
  final name = _chatText(metadata['filename']);
  if (name != null) return name;
  return customerChatFileIsImage(type, metadata)
      ? customerChatImage
      : customerChatDocument;
}
