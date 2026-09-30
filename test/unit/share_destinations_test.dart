import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/chat_attachment_draft.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/utils/share_destinations.dart';

/// A quién se le puede mandar algo desde «Compartir» o «Reenviar»: chats,
/// clientes y proveedores sin chat, el equipo y un número suelto.
void main() {
  Conversation chat(
    String id, {
    String channel = 'whatsapp',
    String type = 'support',
    String status = 'active',
    String counterparty = 'customer',
    String? title,
    ConversationContextHint? hint,
    DateTime? last,
  }) =>
      Conversation(
        id: id,
        type: type,
        channel: channel,
        counterpartyType: counterparty,
        status: status,
        title: title ?? id,
        updatedAt: DateTime(2026, 9, 1),
        lastMessageAt: last,
        participantIds: const [],
        contextHint: hint,
      );

  final conversations = [
    chat('antiguo', title: 'Ana Muñoz', last: DateTime(2026, 9, 20)),
    chat(
      'reciente',
      title: 'José Pérez',
      hint: const ConversationContextHint(
        customerId: 'c-jose',
        phone: '+56 9 4188 4520',
      ),
      last: DateTime(2026, 9, 29),
    ),
    chat(
      'derman',
      title: 'Derman',
      counterparty: 'supplier',
      hint: const ConversationContextHint(supplierId: 's-derman'),
      last: DateTime(2026, 9, 28),
    ),
    chat('instagram', channel: 'instagram', last: DateTime(2026, 9, 29)),
    chat('equipo',
        channel: 'internal',
        type: 'internal',
        title: 'Taller',
        last: DateTime(2026, 9, 27)),
    chat('rechazado', status: 'rejected', last: DateTime(2026, 9, 29)),
    chat('pendiente', status: 'pending', last: DateTime(2026, 9, 25)),
  ];

  const directory = [
    // Ya tiene chat: por id y por teléfono.
    ShareDirectoryContact(
      isSupplier: false,
      id: 'c-jose',
      name: 'José Pérez',
      phone: '+56941884520',
    ),
    ShareDirectoryContact(
      isSupplier: false,
      id: 'c-otro-jose',
      name: 'José Pérez (ficha repetida)',
      phone: '941884520',
    ),
    ShareDirectoryContact(
      isSupplier: false,
      id: 'c-constanza',
      name: 'Constanza Harbin',
      phone: '+56 9 8729 7798',
      searchTerms: ['12.345.678-5'],
    ),
    ShareDirectoryContact(
      isSupplier: false,
      id: 'c-camila',
      name: 'Camila Constanzo',
      phone: '+56 9 1000 2000',
    ),
    ShareDirectoryContact(
      isSupplier: true,
      id: 's-derman',
      name: 'Derman',
      phone: '+56 9 2749 7948',
    ),
    ShareDirectoryContact(
      isSupplier: true,
      id: 's-tekno',
      name: 'TeknoBike',
      phone: '+56 9 8206 5716',
      detail: 'Diego Muñoz',
    ),
  ];

  ShareDestinationSections build(
    String query, {
    ShareAudience audience = ShareAudience.all,
    Map<String, DateTime> inbound = const {},
    String? exclude,
  }) =>
      ShareDestinations.build(
        conversations: conversations,
        directory: directory,
        query: query,
        audience: audience,
        titleFor: (c) => c.title ?? '',
        lastInboundAt: inbound,
        excludeConversationId: exclude,
        now: DateTime.utc(2026, 9, 29, 15),
      );

  List<String> ids(Iterable<ShareDestination> destinations) =>
      [for (final destination in destinations) destination.id];

  test('chats de WhatsApp con compositor y del equipo, el más reciente primero',
      () {
    expect(ids(build('').chats), [
      'chat-reciente',
      'chat-derman',
      'chat-equipo',
      'chat-pendiente',
      'chat-antiguo',
    ]);
  });

  test('busca sin tildes y por dígitos del teléfono', () {
    expect(ids(build('munoz').chats), ['chat-antiguo']);
    expect(ids(build('jose').chats), ['chat-reciente']);
    expect(ids(build('41884520').chats), ['chat-reciente']);
  });

  test('sin buscar, los clientes sin chat se cuentan pero no se listan', () {
    final sections = build('');
    expect(sections.customers, isEmpty);
    expect(sections.hiddenCustomers, 2);
    // Los proveedores son pocos, pero en «Todos» tampoco llenan la lista.
    expect(sections.suppliers, isEmpty);
  });

  test(
      'al buscar aparecen los clientes sin chat; los que tienen, no se repiten',
      () {
    final sections = build('constanz');
    // Empieza con lo buscado primero.
    expect(
        ids(sections.customers), ['customer-c-constanza', 'customer-c-camila']);
    expect(ids(build('jose').customers), isEmpty,
        reason: 'José ya tiene chat: por su id y por su teléfono.');
    expect(ids(build('12.345.678').customers), ['customer-c-constanza'],
        reason: 'Se busca por RUT aunque no se muestre.');
  });

  test('«Proveedores» lista todos los proveedores sin chat sin buscar', () {
    final sections = build('', audience: ShareAudience.suppliers);
    expect(ids(sections.chats), ['chat-derman']);
    expect(ids(sections.suppliers), ['supplier-s-tekno']);
    expect(sections.customers, isEmpty);
    expect(ids(build('diego').suppliers), ['supplier-s-tekno'],
        reason: 'Se busca por el vendedor.');
  });

  test('«Equipo» sólo muestra los chats internos y ningún número', () {
    final sections = build('', audience: ShareAudience.team);
    expect(ids(sections.chats), ['chat-equipo']);
    expect(
        build('+56 9 5555 6666', audience: ShareAudience.team).phone, isNull);
  });

  test('un número desconocido se ofrece; uno conocido no', () {
    expect(build('+56 9 5555 6666').phone?.phone, '+56 9 5555 6666');
    expect(build('87297798').phone, isNull, reason: 'Es de Constanza.');
    expect(build('41884520').phone, isNull, reason: 'Es del chat de José.');
    expect(build('1234').phone, isNull, reason: 'No es un teléfono todavía.');
  });

  test('la ventana de 24 h marca quién recibe archivos ahora', () {
    final sections = build('', inbound: {
      'reciente': DateTime.utc(2026, 9, 29, 10),
      'derman': DateTime.utc(2026, 9, 28, 14),
    });
    final open = {
      for (final destination in sections.chats)
        destination.id: destination.windowOpen,
    };
    expect(open['chat-reciente'], isTrue);
    expect(open['chat-derman'], isFalse, reason: 'Hace 25 h.');
    expect(open['chat-equipo'], isFalse, reason: 'Un chat interno no tiene.');
  });

  test('el chat desde el que se reenvía no es destino', () {
    expect(ids(build('', exclude: 'reciente').chats),
        isNot(contains('chat-reciente')));
  });

  test('la llave de teléfono es el celular chileno completo', () {
    expect(ShareDestinations.phoneKey('+56 9 4188-4520'), '56941884520');
    expect(ShareDestinations.phoneKey('941884520'), '56941884520');
    expect(ShareDestinations.phoneKey('41884520'), '56941884520',
        reason: 'Un celular antiguo de 8 dígitos lleva el 9 adelante.');
    expect(ShareDestinations.phoneKey('+1 212 1234 5678'), '121212345678',
        reason: 'Otro país conserva su código: no choca con +56 9 1234 5678.');
    expect(ShareDestinations.phoneKey('1234567'), isNull);
  });

  test('sólo un celular chileno se ofrece como número nuevo', () {
    // El normalizador del servidor le antepone 569 a cualquier cosa.
    final foreign = build('+1 206 555 0123');
    expect(foreign.phone, isNull);
    expect(foreign.phoneRejected, isTrue);
    expect(build('+56 2 2345 6789').phone, isNull, reason: 'Un fijo.');
    expect(build('12.345.678-5').phoneRejected, isFalse,
        reason: 'Un RUT no es un teléfono.');
  });

  test('una ficha cuyo número cambió aparece junto al chat del número viejo',
      () {
    final sections = ShareDestinations.build(
      conversations: conversations,
      directory: const [
        ShareDirectoryContact(
          isSupplier: false,
          id: 'c-jose',
          name: 'José Pérez',
          phone: '+56 9 7777 8888',
        ),
      ],
      query: 'jose',
      audience: ShareAudience.all,
      titleFor: (c) => c.title ?? '',
    );
    expect(ids(sections.chats), ['chat-reciente']);
    expect(ids(sections.customers), ['customer-c-jose']);
  });

  test('se compara con el número al que escribe el hilo, no el de la ficha',
      () {
    // La bandeja muestra el teléfono de la ficha (+56 9 4188 4520), pero el
    // hilo sigue escribiéndole al número viejo del vínculo.
    ShareDestinationSections withThread(String threadPhone) =>
        ShareDestinations.build(
          conversations: conversations,
          directory: const [
            ShareDirectoryContact(
              isSupplier: false,
              id: 'c-jose',
              name: 'José Pérez',
              phone: '+56 9 4188 4520',
            ),
          ],
          query: 'jose',
          audience: ShareAudience.all,
          titleFor: (c) => c.title ?? '',
          threadPhones: {'reciente': threadPhone},
        );
    final old = withThread('+56 9 1000 0001');
    expect(ids(old.customers), ['customer-c-jose'],
        reason: 'La ficha lleva al número nuevo.');
    expect(old.chats.single.threadPhone, '+56 9 1000 0001');
    expect(ids(withThread('56941884520').customers), isEmpty);
  });

  group('leyendas al reenviar', () {
    PendingChatAttachment file(String? caption) => PendingChatAttachment(
          id: 'a',
          fileName: 'a.jpg',
          bytes: Uint8List(0),
          extension: 'jpg',
          isImage: true,
          caption: caption,
        );

    test('cada archivo sale con la suya; el texto de la caja, en el primero',
        () {
      expect(
        pendingAttachmentCaption(
            index: 0, attachment: file('A'), composerText: ''),
        'A',
      );
      expect(
        pendingAttachmentCaption(
            index: 1, attachment: file('B'), composerText: 'Hola'),
        'B',
      );
      expect(
        pendingAttachmentCaption(
            index: 0, attachment: file('A'), composerText: 'Hola'),
        'A\n\nHola',
      );
      expect(
        pendingAttachmentCaption(
            index: 0, attachment: file(null), composerText: 'Hola'),
        'Hola',
      );
      expect(
        pendingAttachmentCaption(
            index: 1, attachment: file(null), composerText: 'Hola'),
        isNull,
      );
    });

    test('la leyenda sobrevive a las copias del adjunto', () {
      final attachment = file(null).withCaption('B');
      expect(attachment.withReply(null).caption, 'B');
      expect(attachment.resetForNewAttempt().caption, 'B');
    });
  });
}
