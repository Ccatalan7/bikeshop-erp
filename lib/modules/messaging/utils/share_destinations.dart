import '../models/conversation.dart';
import 'conversation_search.dart';

/// A quién se le puede mandar algo desde «Compartir» (el menú del teléfono) o
/// «Reenviar» (desde otro chat): los chats que ya existen, cualquier cliente o
/// proveedor con teléfono aunque nunca haya escrito, y un número suelto.
///
/// Antes sólo aparecían los chats existentes: el 2026-09-29 eran 8 de
/// clientes y 9 de proveedores, frente a 486 clientes con teléfono. El dueño:
/// «¿Qué pasa si quiero compartirle a algún cliente?».
enum ShareAudience { all, customers, suppliers, team }

enum ShareDestinationKind { chat, customer, supplier, phone }

/// Un cliente o proveedor de las fichas del ERP, con un teléfono usable para
/// WhatsApp.
class ShareDirectoryContact {
  const ShareDirectoryContact({
    required this.isSupplier,
    required this.id,
    required this.name,
    required this.phone,
    this.detail,
    this.imageUrl,
    this.searchTerms = const [],
  });

  final bool isSupplier;
  final String id;
  final String name;
  final String phone;

  /// El vendedor de un proveedor, que es quien contesta el WhatsApp.
  final String? detail;
  final String? imageUrl;

  /// RUT, correo, alias: se busca por ellos, no se muestran.
  final List<String> searchTerms;
}

class ShareDestination {
  const ShareDestination._({
    required this.kind,
    required this.title,
    this.conversation,
    this.contact,
    this.phone,
    this.threadPhone,
    this.windowOpen = false,
  });

  factory ShareDestination.chat(
    Conversation conversation, {
    required String title,
    String? threadPhone,
    bool windowOpen = false,
  }) =>
      ShareDestination._(
        kind: ShareDestinationKind.chat,
        title: title,
        conversation: conversation,
        threadPhone: threadPhone,
        windowOpen: windowOpen,
      );

  factory ShareDestination.contact(ShareDirectoryContact contact) =>
      ShareDestination._(
        kind: contact.isSupplier
            ? ShareDestinationKind.supplier
            : ShareDestinationKind.customer,
        title: contact.name,
        contact: contact,
      );

  factory ShareDestination.phone(String phone) => ShareDestination._(
        kind: ShareDestinationKind.phone,
        title: phone,
        phone: phone,
      );

  final ShareDestinationKind kind;
  final String title;
  final Conversation? conversation;
  final ShareDirectoryContact? contact;
  final String? phone;

  /// El número al que escribe un chat de WhatsApp: el del vínculo, que puede
  /// no ser el de la ficha.
  final String? threadPhone;

  /// El contacto escribió en las últimas 24 h: WhatsApp acepta archivos y
  /// texto libre ahora mismo. Si no, Meta exige primero una plantilla
  /// autorizada (el saludo) y que la persona responda.
  final bool windowOpen;

  bool get isTeam => conversation?.isInternal ?? false;
  bool get isSupplier =>
      conversation?.isSupplierConversation ??
      kind == ShareDestinationKind.supplier;

  /// Identidad estable, para las llaves de la vista y las pruebas.
  String get id => switch (kind) {
        ShareDestinationKind.chat => 'chat-${conversation!.id}',
        ShareDestinationKind.customer => 'customer-${contact!.id}',
        ShareDestinationKind.supplier => 'supplier-${contact!.id}',
        ShareDestinationKind.phone => 'phone',
      };
}

class ShareDestinationSections {
  const ShareDestinationSections({
    this.chats = const [],
    this.customers = const [],
    this.suppliers = const [],
    this.phone,
    this.phoneRejected = false,
    this.hiddenCustomers = 0,
  });

  final List<ShareDestination> chats;

  /// Clientes y proveedores que todavía no tienen chat.
  final List<ShareDestination> customers;
  final List<ShareDestination> suppliers;

  /// Un número escrito en la búsqueda que no es de nadie conocido.
  final ShareDestination? phone;

  /// Lo escrito parece un teléfono, pero no un celular chileno: el ERP no
  /// sabe abrirle un chat sin cambiarlo por otro número.
  final bool phoneRejected;

  /// Clientes sin chat que sólo aparecen al buscar: son cientos.
  final int hiddenCustomers;

  bool get isEmpty =>
      chats.isEmpty && customers.isEmpty && suppliers.isEmpty && phone == null;
}

abstract final class ShareDestinations {
  static const Duration whatsAppWindow = Duration(hours: 24);

  /// Por sección: más que esto es una búsqueda que hay que afinar.
  static const int maxDirectoryMatches = 30;

  static bool isWindowOpen(DateTime? lastInboundAt, DateTime now) =>
      lastInboundAt != null &&
      now.toUtc().difference(lastInboundAt.toUtc()) < whatsAppWindow;

  static ShareDestinationSections build({
    required List<Conversation> conversations,
    required List<ShareDirectoryContact> directory,
    required String query,
    required ShareAudience audience,
    required String Function(Conversation) titleFor,
    Map<String, DateTime> lastInboundAt = const {},
    Map<String, String> threadPhones = const {},
    String? excludeConversationId,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final normalized = ConversationSearch.normalize(query);
    final queryDigits = query.replaceAll(RegExp(r'[^0-9]'), '');

    final eligible = conversations.where((conversation) {
      if (conversation.id == excludeConversationId) return false;
      if (conversation.isInternal) return conversation.status == 'active';
      // Instagram y Messenger no aceptan adjuntos desde el ERP, y un chat
      // cerrado o rechazado no tiene compositor.
      return conversation.isWhatsApp &&
          (conversation.status == 'active' || conversation.status == 'pending');
    }).toList();

    // Lo que ya tiene chat no se repite como ficha: por el número al que
    // escribe el hilo, y por la ficha sólo si no se sabe ese número. El
    // teléfono de la bandeja es el de la FICHA: con él (o con el id), una
    // ficha cuyo número cambió quedaba escondida detrás del chat que le
    // escribe al número viejo.
    final chatCustomerIds = <String>{};
    final chatSupplierIds = <String>{};
    final chatPhones = <String>{};
    for (final conversation in eligible) {
      if (!conversation.isWhatsApp) continue;
      final hint = conversation.contextHint;
      final threadKey = phoneKey(threadPhones[conversation.id]);
      final keys = threadKey != null
          ? [threadKey]
          : [
              for (final phone in [hint?.phone, hint?.supplierPhone])
                if (phoneKey(phone) case final key?) key,
            ];
      chatPhones.addAll(keys);
      if (keys.isNotEmpty) continue;
      if (hint?.customerId case final id? when id.isNotEmpty) {
        chatCustomerIds.add(id);
      }
      final supplierId = hint?.supplierId ??
          (conversation.effectiveContextType == 'supplier'
              ? conversation.effectiveContextId
              : null);
      if (supplierId != null && supplierId.isNotEmpty) {
        chatSupplierIds.add(supplierId);
      }
    }

    final chats = <ShareDestination>[
      for (final conversation in eligible)
        if (_inAudience(conversation, audience) &&
            _chatMatches(conversation, normalized, titleFor))
          ShareDestination.chat(
            conversation,
            title: titleFor(conversation),
            threadPhone: threadPhones[conversation.id],
            windowOpen: conversation.isWhatsApp &&
                isWindowOpen(lastInboundAt[conversation.id], moment),
          ),
    ]..sort((a, b) =>
        _recency(b.conversation!).compareTo(_recency(a.conversation!)));

    final withoutChat = [
      for (final contact in directory)
        if (!(contact.isSupplier ? chatSupplierIds : chatCustomerIds)
                .contains(contact.id) &&
            !chatPhones.contains(phoneKey(contact.phone)))
          contact,
    ];

    List<ShareDestination> section(bool suppliers, {required bool listAll}) {
      final matches = withoutChat
          .where((contact) => contact.isSupplier == suppliers)
          .where((contact) => ConversationSearch.matches(normalized, [
                contact.name,
                contact.detail,
                contact.phone,
                ...contact.searchTerms,
              ]))
          .toList()
        ..sort((a, b) => _byMatch(a, b, normalized));
      if (!listAll && normalized.isEmpty) return const [];
      return [
        for (final contact in matches.take(maxDirectoryMatches))
          ShareDestination.contact(contact),
      ];
    }

    final showCustomers =
        audience == ShareAudience.all || audience == ShareAudience.customers;
    final showSuppliers =
        audience == ShareAudience.all || audience == ShareAudience.suppliers;
    final customers =
        showCustomers ? section(false, listAll: false) : <ShareDestination>[];
    final suppliers = showSuppliers
        ? section(true, listAll: audience == ShareAudience.suppliers)
        : <ShareDestination>[];

    // Sólo dígitos, espacios, + - ( ): un RUT con puntos no es un teléfono.
    final looksLikePhone = queryDigits.length >= 8 &&
        RegExp(r'^\+?[0-9\s\-()]+$').hasMatch(query.trim()) &&
        audience != ShareAudience.team;
    final mobile = chileanMobile(queryDigits);
    final known = mobile != null &&
        (chatPhones.contains(mobile) ||
            directory.any((contact) => phoneKey(contact.phone) == mobile));
    final phone = looksLikePhone && mobile != null && !known
        ? ShareDestination.phone(query.trim())
        : null;

    return ShareDestinationSections(
      chats: chats,
      customers: customers,
      suppliers: suppliers,
      phone: phone,
      phoneRejected: looksLikePhone && mobile == null,
      hiddenCustomers: showCustomers && normalized.isEmpty
          ? withoutChat.where((contact) => !contact.isSupplier).length
          : 0,
    );
  }

  /// Un celular chileno como lo escribe `open_whatsapp_support_conversation`
  /// (`569XXXXXXXX`), con o sin +56, espacios o el 9 inicial de los números
  /// antiguos de 8 dígitos. `null` para un fijo, un extranjero o un número
  /// incompleto: ese normalizador les antepone 569 y los vuelve otro número.
  static String? chileanMobile(String? raw) {
    var digits = raw?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (digits.length == 11 && digits.startsWith('56')) {
      digits = digits.substring(2);
    }
    if (digits.length == 8) digits = '9$digits';
    if (digits.length != 9 || !digits.startsWith('9')) return null;
    return '56$digits';
  }

  /// La identidad de un teléfono para no repetir a nadie: el celular chileno
  /// canónico, o los dígitos completos de cualquier otro (con su código de
  /// país, para que +1 212 1234 5678 no sea el +56 9 1234 5678).
  static String? phoneKey(String? raw) {
    final mobile = chileanMobile(raw);
    if (mobile != null) return mobile;
    final digits = raw?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    return digits.length < 8 ? null : digits;
  }

  static bool _inAudience(Conversation conversation, ShareAudience audience) =>
      switch (audience) {
        ShareAudience.all => true,
        ShareAudience.team => conversation.isInternal,
        ShareAudience.suppliers =>
          conversation.isWhatsApp && conversation.isSupplierConversation,
        ShareAudience.customers =>
          conversation.isWhatsApp && !conversation.isSupplierConversation,
      };

  static bool _chatMatches(
    Conversation conversation,
    String normalized,
    String Function(Conversation) titleFor,
  ) {
    final hint = conversation.contextHint;
    return ConversationSearch.matches(normalized, [
      titleFor(conversation),
      conversation.title,
      conversation.creatorName,
      hint?.phone,
      hint?.supplierPhone,
      hint?.customerLabel,
      hint?.supplierLabel,
      hint?.contactPersonName,
    ]);
  }

  /// Primero los que empiezan con lo buscado; después, por nombre.
  static int _byMatch(
    ShareDirectoryContact a,
    ShareDirectoryContact b,
    String normalized,
  ) {
    if (normalized.isNotEmpty) {
      final aStarts =
          ConversationSearch.normalize(a.name).startsWith(normalized);
      final bStarts =
          ConversationSearch.normalize(b.name).startsWith(normalized);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
    }
    return ConversationSearch.normalize(a.name)
        .compareTo(ConversationSearch.normalize(b.name));
  }

  static DateTime _recency(Conversation conversation) =>
      conversation.lastMessageAt ?? conversation.updatedAt;
}
