import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/supplier_whatsapp_phone.dart';
import '../../crm/services/customer_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../providers/chat_provider.dart';
import '../utils/conversation_channel_presentation.dart';
import '../utils/share_destinations.dart';
import 'counterparty_avatar_image.dart';

typedef ShareDirectoryLoader = Future<List<ShareDirectoryContact>> Function(
    BuildContext context);

/// La conversación de [destination]: la que ya existe, o la que se abre sin
/// escribir nada para un cliente, un proveedor o un número sin chat.
Future<String> resolveShareConversation(
  ChatProvider chat,
  ShareDestination destination,
) async {
  final contact = destination.contact;
  if (destination.kind == ShareDestinationKind.chat) {
    return destination.conversation!.id;
  }
  return switch (destination.kind) {
    ShareDestinationKind.chat => throw StateError('Ya tiene chat.'),
    ShareDestinationKind.customer => chat.openWhatsAppConversationForHandoff(
        phoneNumber: contact!.phone,
        contactName: contact.name,
        customerId: contact.id,
      ),
    ShareDestinationKind.supplier => chat.openWhatsAppConversationForHandoff(
        phoneNumber: contact!.phone,
        contactName: contact.name,
        contextType: 'supplier',
        contextId: contact.id,
      ),
    ShareDestinationKind.phone => chat.openWhatsAppConversationForHandoff(
        phoneNumber: destination.phone!,
        contactName: destination.phone!,
      ),
  };
}

/// Abre el chat destino donde lo abre una notificación del teléfono: el rail
/// derecho en escritorio, pantalla completa en compacto.
void openShareConversation(
  RightToolbarService toolbar,
  ShareDestination destination,
  String conversationId,
) {
  toolbar.openConversation(
    tool: destination.isSupplier
        ? ToolbarTool.supplierMessages
        : ToolbarTool.messages,
    conversationId: conversationId,
  );
}

/// Los clientes y proveedores de las fichas con un celular chileno, sólo del
/// taller con sesión.
///
/// **El filtro de taller va acá a propósito.** La caché de
/// `CustomerService.getCustomersForList` sobrevive un cambio de cuenta y su
/// consulta confía sólo en RLS (2026-09-29): sin este filtro, otra cuenta
/// que entrara en el mismo proceso podía ver los clientes de la anterior en
/// el buscador.
Future<List<ShareDirectoryContact>> loadShareDirectory(
  BuildContext context,
) async {
  final customerService = _maybeRead<CustomerService>(context);
  final purchaseService = _maybeRead<PurchaseService>(context);
  if (customerService == null && purchaseService == null) return const [];
  final tenantId = await TenantService().getTenantId();
  if (tenantId == null || tenantId.isEmpty) return const [];
  final results = await Future.wait<List<ShareDirectoryContact>>([
    (() async {
      if (customerService == null) return <ShareDirectoryContact>[];
      var customers = await customerService.getCustomersForList();
      if (customers.isEmpty ||
          customers.any((customer) => customer.tenantId != tenantId)) {
        // La caché puede ser de la cuenta anterior —con sus filas, o vacía—:
        // se pide la de este taller.
        customers = await customerService.getCustomersForList(
          forceRefresh: true,
        );
      }
      return [
        for (final customer in customers)
          if (customer.id != null &&
              customer.tenantId == tenantId &&
              customer.isActive &&
              ShareDestinations.chileanMobile(customer.phone) != null)
            ShareDirectoryContact(
              isSupplier: false,
              id: customer.id!,
              name: customer.name,
              phone: customer.phone!.trim(),
              imageUrl: customer.imageUrl,
              searchTerms: [customer.rut, customer.email ?? ''],
            ),
      ];
    })(),
    (() async {
      if (purchaseService == null) return <ShareDirectoryContact>[];
      final suppliers = await purchaseService.getSuppliers(activeOnly: true);
      return [
        for (final supplier in suppliers)
          if (supplier.isActive && supplier.tenantId == tenantId)
            if (supplierWhatsAppPhone(
              phone: supplier.phone,
              salesRepPhone: supplier.salesRepPhone,
            )
                case final phone?
                when ShareDestinations.chileanMobile(phone) != null)
              ShareDirectoryContact(
                isSupplier: true,
                id: supplier.id,
                name: supplier.name,
                phone: phone,
                detail: _nonEmpty(supplier.salesRepName) ??
                    _nonEmpty(supplier.contactPerson),
                imageUrl: supplier.imageUrl,
                searchTerms: [
                  supplier.rut ?? '',
                  supplier.legalName ?? '',
                  supplier.tradeName ?? '',
                  ...supplier.aliases,
                ],
              ),
      ];
    })(),
  ]);
  return [...results[0], ...results[1]];
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// A quién mandarlo, con búsqueda y filtros, como slivers para ir debajo de lo
/// que se manda (el menú Compartir del teléfono y «Reenviar»).
///
/// Elegir un destino llama a [onChoose]; el host deja los archivos en el
/// compositor de ese chat y lo abre. **Nada se envía acá.**
class ShareDestinationSliver extends StatefulWidget {
  const ShareDestinationSliver({
    super.key,
    required this.enabled,
    required this.onChoose,
    this.keyPrefix = 'share-destination',
    this.excludeConversationId,
    this.directoryLoader,
  });

  final bool enabled;
  final void Function(ShareDestination destination) onChoose;

  /// Llaves de la búsqueda y de cada fila: `<prefijo>-search`,
  /// `<prefijo>-chat-<id>`, `<prefijo>-customer-<id>`…
  final String keyPrefix;

  /// El chat desde el que se reenvía.
  final String? excludeConversationId;
  final ShareDirectoryLoader? directoryLoader;

  @override
  State<ShareDestinationSliver> createState() => _ShareDestinationSliverState();
}

class _ShareDestinationSliverState extends State<ShareDestinationSliver> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  ShareAudience _audience = ShareAudience.all;
  List<ShareDirectoryContact> _directory = const [];
  bool _directoryLoading = true;
  Map<String, DateTime> _lastInbound = const {};
  Map<String, String> _threadPhones = const {};
  final Set<String> _windowRequested = {};
  Timer? _warmup;
  bool _warming = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    final chat = context.read<ChatProvider>();
    // Si la app se abrió desde el menú Compartir, la bandeja puede no haber
    // cargado —ni tener la sesión lista— todavía. La lista aparece apenas
    // llega; mientras tanto se espera un rato antes de afirmar que no hay chats.
    if (chat.conversations.isEmpty) {
      _warming = true;
      _warmup = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _warming = false);
      });
      unawaited(chat.loadConversations());
    }
    unawaited(_loadDirectory());
  }

  Future<void> _loadDirectory() async {
    List<ShareDirectoryContact> contacts = const [];
    try {
      contacts =
          await (widget.directoryLoader ?? loadShareDirectory).call(context);
    } catch (error) {
      debugPrint('📤 [ShareDestinations] Directorio no disponible: $error');
    }
    if (!mounted) return;
    setState(() {
      _directory = contacts;
      _directoryLoading = false;
    });
  }

  /// El número del hilo y la ventana de 24 h de los chats de WhatsApp a la
  /// vista, una sola lectura por chat.
  void _requestWindows(ChatProvider chat) {
    final missing = [
      for (final conversation in chat.conversations)
        if (conversation.isWhatsApp && _windowRequested.add(conversation.id))
          conversation.id,
    ];
    if (missing.isEmpty) return;
    unawaited(() async {
      try {
        final found = await chat.whatsAppBindingSummaries(missing);
        if (!mounted || found.isEmpty) return;
        setState(() {
          _lastInbound = {
            ..._lastInbound,
            for (final MapEntry(:key, :value) in found.entries)
              if (value.lastInboundAt case final at?) key: at,
          };
          _threadPhones = {
            ..._threadPhones,
            for (final MapEntry(:key, :value) in found.entries)
              if (value.phone case final phone?) key: phone,
          };
        });
      } catch (error) {
        // Se reintenta en la próxima reconstrucción: sin el número del hilo,
        // la deduplicación cae al teléfono de la ficha.
        _windowRequested.removeAll(missing);
        debugPrint('📤 [ShareDestinations] Ventanas no disponibles: $error');
      }
    }());
  }

  @override
  void dispose() {
    _warmup?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _key(String suffix) => '${widget.keyPrefix}-$suffix';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = context.watch<ChatProvider>();
    if (chat.conversations.any(
      (c) => c.isWhatsApp && !_windowRequested.contains(c.id),
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestWindows(chat);
      });
    }
    final query = _search.text;
    final sections = ShareDestinations.build(
      conversations: chat.conversations,
      directory: _directory,
      query: query,
      audience: _audience,
      titleFor: chat.getChatTitle,
      lastInboundAt: _lastInbound,
      threadPhones: _threadPhones,
      excludeConversationId: widget.excludeConversationId,
    );
    final hasTeam = chat.conversations.any(
      (c) =>
          c.isInternal &&
          c.status == 'active' &&
          c.id != widget.excludeConversationId,
    );
    final showsWhatsApp = sections.chats.any((d) => !d.isTeam);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    List<Widget> tiles(Iterable<ShareDestination> destinations) => [
          for (final destination in destinations)
            _ShareDestinationTile(
              key: ValueKey(_key(destination.id)),
              destination: destination,
              enabled: widget.enabled,
              onTap: () => widget.onChoose(destination),
            ),
        ];

    final loadingChats = _warming && chat.conversations.isEmpty;
    final trimmed = query.trim();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: ValueKey(_key('search')),
              controller: _search,
              focusNode: _searchFocus,
              enabled: widget.enabled,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, RUT o teléfono',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: trimmed.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close),
                      ),
                isDense: true,
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                for (final (audience, label) in [
                  (ShareAudience.all, 'Todos'),
                  (ShareAudience.customers, 'Clientes'),
                  (ShareAudience.suppliers, 'Proveedores'),
                  if (hasTeam) (ShareAudience.team, 'Equipo'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey(_key('audience-${audience.name}')),
                      label: Text(label),
                      selected: _audience == audience,
                      showCheckmark: false,
                      // Los cuatro caben a 360 px; el área de toque sigue en
                      // 48 px (materialTapTargetSize por defecto).
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      onSelected: widget.enabled
                          ? (_) => setState(() => _audience = audience)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (showsWhatsApp)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: _WindowDot(size: 9, ring: scheme.surface),
                  ),
                  Expanded(
                    child: Text(
                      'Te escribió en las últimas 24 h: recibe archivos al '
                      'tiro. A los demás, WhatsApp pide un saludo antes.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (loadingChats && sections.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (sections.chats.isNotEmpty) ...[
          SliverToBoxAdapter(child: header('Chats')),
          SliverList.list(children: tiles(sections.chats)),
        ],
        if (sections.customers.isNotEmpty) ...[
          SliverToBoxAdapter(child: header('Clientes sin chat')),
          SliverList.list(children: tiles(sections.customers)),
        ],
        if (sections.suppliers.isNotEmpty) ...[
          SliverToBoxAdapter(child: header('Proveedores sin chat')),
          SliverList.list(children: tiles(sections.suppliers)),
        ],
        if (sections.phone case final phone?) ...[
          SliverToBoxAdapter(child: header('Otro número')),
          SliverList.list(children: tiles([phone])),
        ],
        if (sections.hiddenCustomers > 0)
          SliverToBoxAdapter(
            child: ListTile(
              key: ValueKey(_key('search-hint')),
              enabled: widget.enabled,
              onTap: _searchFocus.requestFocus,
              leading: Icon(Icons.person_search_outlined,
                  color: scheme.onSurfaceVariant),
              title: Text(
                sections.hiddenCustomers == 1
                    ? 'Busca a tu cliente'
                    : 'Busca entre tus ${sections.hiddenCustomers} clientes',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: const Text(
                'Por nombre, RUT o teléfono, aunque nunca te hayan escrito.',
              ),
            ),
          ),
        if (!loadingChats && sections.isEmpty && sections.hiddenCustomers == 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _directoryLoading && trimmed.isNotEmpty
                    ? 'Buscando…'
                    : trimmed.isEmpty
                        ? 'No hay chats abiertos.'
                        : sections.phoneRejected
                            ? 'El WhatsApp del ERP escribe sólo a celulares '
                                'de Chile, como +56\u00a09\u00a01234\u00a05678.'
                            : 'Nadie coincide con «$trimmed». Escribe el '
                                'número completo para escribirle igual.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ShareDestinationTile extends StatelessWidget {
  const _ShareDestinationTile({
    super.key,
    required this.destination,
    required this.enabled,
    required this.onTap,
  });

  final ShareDestination destination;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final when = destination.kind == ShareDestinationKind.chat
        ? formatShareWhen(destination.conversation!.lastMessageAt)
        : null;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _DestinationAvatar(destination: destination),
      title: Text(
        destination.kind == ShareDestinationKind.phone
            ? 'Escribir a ${destination.title}'
            : destination.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtitle(destination),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: when == null
          ? null
          : Text(
              when,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
    );
  }

  static String _subtitle(ShareDestination destination) {
    switch (destination.kind) {
      case ShareDestinationKind.chat:
        final conversation = destination.conversation!;
        if (conversation.isInternal) return 'Equipo';
        final hint = conversation.contextHint;
        // El número al que le escribe el chat; la bandeja trae el de la ficha.
        final phone = (destination.threadPhone ??
                (conversation.isSupplierConversation
                    ? hint?.supplierPhone ?? hint?.phone
                    : hint?.phone))
            ?.trim();
        return [
          conversation.isSupplierConversation ? 'Proveedor' : 'Cliente',
          if (phone != null && phone.isNotEmpty && phone != destination.title)
            phone,
        ].join(' · ');
      case ShareDestinationKind.customer:
      case ShareDestinationKind.supplier:
        // El encabezado de la sección ya dice si es cliente o proveedor.
        final contact = destination.contact!;
        return [
          if (contact.detail != null) contact.detail!,
          contact.phone,
        ].join(' · ');
      case ShareDestinationKind.phone:
        return 'Sin ficha · chat nuevo de WhatsApp';
    }
  }
}

class _DestinationAvatar extends StatelessWidget {
  const _DestinationAvatar({required this.destination});

  final ShareDestination destination;

  @override
  Widget build(BuildContext context) {
    final conversation = destination.conversation;
    final accent = conversation == null
        ? ConversationChannelPresentation.accentForChannel('whatsapp')
        : ConversationChannelPresentation.accent(conversation);
    // El verde de WhatsApp es oscuro: sobre el fondo oscuro las iniciales no
    // se leían. En oscuro se aclara la tinta, no el color del canal.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? HSLColor.fromColor(accent).withLightness(0.72).toColor()
        : accent;
    final fallback = CircleAvatar(
      radius: 22,
      backgroundColor: accent.withValues(alpha: 0.12),
      child: destination.kind == ShareDestinationKind.phone
          ? Icon(Icons.dialpad, size: 20, color: ink)
          : Text(
              _initials(destination.title.split(' · ').first),
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
    );
    final url = conversation?.contextHint?.counterpartyImageUrl ??
        destination.contact?.imageUrl;
    final avatar = SizedBox(
      width: 44,
      height: 44,
      child: url == null || url.isEmpty
          ? fallback
          : CounterpartyAvatarImage(
              url: url,
              size: 44,
              isMark: destination.isSupplier,
              backdrop: accent.withValues(alpha: 0.10),
              fallback: fallback,
            ),
    );
    if (!destination.windowOpen) return avatar;
    return Semantics(
      label: 'Recibe archivos ahora',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: _WindowDot(
              size: 13,
              ring: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    if (RegExp(r'^\+?[0-9 ]+$').hasMatch(trimmed)) return '#';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}

/// El punto de «te escribió en las últimas 24 h».
class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.size, required this.ring});

  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final color = VinabikeThemeRoles.maybeOf(context)?.success.accent ??
        Colors.green.shade600;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
      ),
    );
  }
}

/// «14:40», «ayer», «22 sep».
String? formatShareWhen(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  if (days == 1) return 'ayer';
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${local.day} ${months[local.month - 1]}';
}

/// Para que un host muestre el título del destino elegido en un aviso.
String shareDestinationLabel(ShareDestination destination) =>
    destination.kind == ShareDestinationKind.phone
        ? destination.phone!
        : destination.title;
