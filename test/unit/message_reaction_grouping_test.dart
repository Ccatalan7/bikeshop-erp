import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/message_reaction.dart';

MessageReaction _reaction({
  required String emoji,
  String? userId,
  String? waId,
  String? name,
  int minute = 0,
}) {
  return MessageReaction(
    id: '$emoji-${userId ?? waId}-$minute',
    messageId: 'msg-1',
    emoji: emoji,
    reactorUserId: userId,
    reactorWaId: waId,
    reactorName: name,
    createdAt: DateTime(2026, 8, 20, 12, minute),
  );
}

void main() {
  test('agrupa por emoji y cuenta cuántos reaccionaron', () {
    final groups = MessageReactionGroup.group([
      _reaction(emoji: '👍', waId: '56911111111', minute: 1),
      _reaction(emoji: '👍', userId: 'user-a', minute: 2),
      _reaction(emoji: '❤️', waId: '56922222222', minute: 3),
    ]);

    expect(groups.length, 2);
    expect(groups.first.emoji, '👍');
    expect(groups.first.count, 2);
    expect(groups.last.emoji, '❤️');
    expect(groups.last.count, 1);
  });

  test('el grupo sabe si el usuario actual está dentro', () {
    final groups = MessageReactionGroup.group(
      [
        _reaction(emoji: '👍', userId: 'user-a', minute: 1),
        _reaction(emoji: '😂', waId: '56911111111', minute: 2),
      ],
      currentUserId: 'user-a',
    );

    final mine = groups.firstWhere((g) => g.emoji == '👍');
    final theirs = groups.firstWhere((g) => g.emoji == '😂');
    expect(
      mine.includesCurrentUser,
      isTrue,
      reason: 'De esto depende que el chip se pinte propio y que tocarlo quite.',
    );
    expect(theirs.includesCurrentUser, isFalse);
  });

  test('una reacción de WhatsApp nunca se confunde con la del usuario', () {
    // Un contacto externo no tiene usuario nuestro. Si `includesCurrentUser`
    // se apoyara en el nombre o el teléfono, tocar el chip intentaría quitar
    // la reacción de otra persona.
    final groups = MessageReactionGroup.group(
      [_reaction(emoji: '👍', waId: 'user-a', name: 'Claudio Catalán')],
      currentUserId: 'user-a',
    );

    expect(groups.single.includesCurrentUser, isFalse);
    expect(groups.single.reactions.single.isFromWhatsAppContact, isTrue);
  });

  test('el tooltip nombra a quien reaccionó, y cae al teléfono sin nombre', () {
    final groups = MessageReactionGroup.group([
      _reaction(emoji: '👍', waId: '56911111111', name: 'Claudio', minute: 1),
      _reaction(emoji: '👍', waId: '56922222222', minute: 2),
    ]);

    expect(groups.single.tooltip, 'Claudio, 56922222222');
  });

  test('ordena por cantidad y desempata por quién llegó primero', () {
    final groups = MessageReactionGroup.group([
      _reaction(emoji: '😂', waId: '1', minute: 1),
      _reaction(emoji: '👍', waId: '2', minute: 2),
      _reaction(emoji: '👍', waId: '3', minute: 3),
      _reaction(emoji: '❤️', waId: '4', minute: 4),
    ]);

    expect(groups.map((g) => g.emoji).toList(), ['👍', '😂', '❤️']);
  });

  test('sin reacciones no hay grupos', () {
    expect(MessageReactionGroup.group(const []), isEmpty);
  });
}
