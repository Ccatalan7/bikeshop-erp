/// Una reacción a un mensaje.
///
/// Vive en su propia tabla y no dentro del mensaje a propósito: WhatsApp la
/// entrega como un evento aparte que apunta al mensaje anotado, y tratarla como
/// un mensaje fue exactamente el defecto que dejaba la palabra «reaction» en el
/// chat y levantaba un no-leído falso.
///
/// WhatsApp permite **una** reacción por persona por mensaje: poner otra
/// reemplaza la anterior y quitarla la borra. La base lo garantiza con un único
/// índice sobre (mensaje, reactor); el cliente no debe acumular varias.
class MessageReaction {
  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.emoji,
    this.reactorUserId,
    this.reactorWaId,
    this.reactorName,
    required this.createdAt,
  });

  final String id;
  final String messageId;
  final String emoji;

  /// Exactamente uno de los dos viene poblado: un usuario del ERP o un contacto
  /// externo de WhatsApp.
  final String? reactorUserId;
  final String? reactorWaId;

  final String? reactorName;
  final DateTime createdAt;

  bool get isFromWhatsAppContact => reactorWaId != null;

  /// Quién la puso, para el tooltip. Cae al teléfono sólo si no hay nombre.
  String get reactorLabel {
    final name = reactorName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return reactorWaId ?? 'Alguien';
  }

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'].toString(),
      messageId: json['message_id'].toString(),
      emoji: (json['emoji'] ?? '').toString(),
      reactorUserId: json['reactor_user_id']?.toString(),
      reactorWaId: json['reactor_wa_id']?.toString(),
      reactorName: json['reactor_name']?.toString(),
      createdAt: DateTime.parse(json['created_at'].toString()).toLocal(),
    );
  }
}

/// Reacciones de un mensaje agrupadas por emoji, en orden estable de aparición.
///
/// Un grupo sabe si el usuario actual está dentro, que es lo que decide si el
/// chip se pinta como propio y si tocarlo pone o quita.
class MessageReactionGroup {
  const MessageReactionGroup({
    required this.emoji,
    required this.reactions,
    required this.includesCurrentUser,
  });

  final String emoji;
  final List<MessageReaction> reactions;
  final bool includesCurrentUser;

  int get count => reactions.length;

  String get tooltip => reactions.map((r) => r.reactorLabel).join(', ');

  static List<MessageReactionGroup> group(
    List<MessageReaction> reactions, {
    String? currentUserId,
  }) {
    final byEmoji = <String, List<MessageReaction>>{};
    for (final reaction in reactions) {
      byEmoji.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }
    return byEmoji.entries.map((entry) {
      final ordered = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return MessageReactionGroup(
        emoji: entry.key,
        reactions: ordered,
        includesCurrentUser: currentUserId != null &&
            ordered.any((r) => r.reactorUserId == currentUserId),
      );
    }).toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return a.reactions.first.createdAt
            .compareTo(b.reactions.first.createdAt);
      });
  }
}
