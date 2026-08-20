import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/crm/models/crm_models.dart';
import '../../modules/crm/services/customer_service.dart';
import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/utils/conversation_activity.dart';
import '../../modules/messaging/utils/conversation_channel_presentation.dart';
import '../../modules/messaging/utils/conversation_search.dart';
import '../../modules/messaging/widgets/chat_window.dart';
import '../../modules/messaging/widgets/conversation_tile.dart';
import '../../modules/messaging/widgets/new_chat_dialog.dart';
import '../services/image_service.dart';
import '../services/right_toolbar_service.dart';
import 'conversation_inbox_host.dart';

enum _MessageFilter {
  all,
  unread,
  meta,
  whatsapp,
  instagram,
  messenger,
  web,
  clients,
  team,
}

class QuickMessagesPanel extends StatefulWidget {
  const QuickMessagesPanel({super.key, this.showTitle = true});

  /// En la hoja de Actividad el segmento ya dice «Mensajes»; repetirlo aquí
  /// gasta una fila de alto en un teléfono. Las acciones de la barra sí siguen.
  final bool showTitle;

  @override
  State<QuickMessagesPanel> createState() => _QuickMessagesPanelState();
}

/// Lo único que Clientes necesita conservar además de lo común: su filtro.
class _CustomerSessionExtra {
  const _CustomerSessionExtra(this.filter);
  final _MessageFilter filter;
}

class _QuickMessagesPanelState extends State<QuickMessagesPanel>
    with ConversationInboxHost<QuickMessagesPanel> {
  // El buscador, el alcance activo/historial, la conversación abierta, la
  // recarga y la retención de sesión los aporta `ConversationInboxHost`. Aquí
  // queda sólo lo que es de clientes.
  _MessageFilter _filter = _MessageFilter.all;
  String? _openingCustomerId;
  Set<String> _pinnedConversationIds = {};
  List<Customer> _whatsAppContacts = [];
  bool _isLoadingWhatsAppContacts = false;

  @override
  ToolbarTool get inboxTool => ToolbarTool.messages;

  @override
  Object? captureSessionExtra() => _CustomerSessionExtra(_filter);

  @override
  void restoreSessionExtra(Object? extra) {
    if (extra is _CustomerSessionExtra) _filter = extra.filter;
  }

  @override
  void initState() {
    super.initState();
    initInboxHost();
  }

  /// Los contactos de WhatsApp sin conversación son datos propios de esta
  /// bandeja: el común los recarga junto a las conversaciones, igual que
  /// Proveedores recarga los suyos.
  @override
  Future<void> loadInboxData() => _loadWhatsAppContacts();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    didChangeInboxDependencies();
  }

  @override
  void dispose() {
    disposeInboxHost();
    super.dispose();
  }





  Future<void> _loadWhatsAppContacts() async {
    if (_isLoadingWhatsAppContacts) return;
    setState(() => _isLoadingWhatsAppContacts = true);
    try {
      final customers =
          await context.read<CustomerService>().getCustomersForList();
      final contacts = customers
          .where((customer) =>
              customer.id != null &&
              customer.isActive &&
              _hasWhatsAppPhone(customer.phone))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _whatsAppContacts = contacts;
        _isLoadingWhatsAppContacts = false;
      });
    } catch (error) {
      debugPrint('Error loading WhatsApp contact search candidates: $error');
      if (mounted) {
        setState(() => _isLoadingWhatsAppContacts = false);
      }
    }
  }

  bool _hasWhatsAppPhone(String? phone) {
    return _normalizedPhone(phone).length >= 8;
  }

  String _normalizedPhone(String? phone) {
    return phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

  Future<void> _togglePinnedConversation(String conversationId) async {
    final next = {..._pinnedConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }

    setState(() => _pinnedConversationIds = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'quick_messages_pinned_conversations',
      next.toList()..sort(),
    );
  }


  void _showNewChatDialog() {
    showDialog(
      context: context,
      builder: (_) => const NewChatDialog(),
    );
  }

  void _openFullChat([Conversation? conversation]) {
    final route = conversation == null
        ? '/chat'
        : Uri(
            path: '/chat',
            queryParameters: {'conversation': conversation.id},
          ).toString();
    context.read<RightToolbarService>().close();
    context.go(route);
  }

  Future<void> _openWhatsAppContact(Customer customer) async {
    final phone = customer.phone?.trim();
    final customerId = customer.id;
    if (phone == null || phone.isEmpty || customerId == null) return;

    setState(() => _openingCustomerId = customerId);
    try {
      final provider = context.read<ChatProvider>();
      await provider.openWhatsAppCustomerChat(
        phoneNumber: phone,
        contactName: customer.name,
        customerId: customerId,
      );

      if (!mounted) return;
      final conversationId = provider.activeConversationId;
      setState(() {
        selectedConversationId = conversationId;
        panelActiveConversationId = conversationId;
        _openingCustomerId = null;
      });
      searchController.clear();
    } catch (error) {
      debugPrint('Error opening WhatsApp customer from quick search: $error');
      if (!mounted) return;
      setState(() => _openingCustomerId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar el chat de WhatsApp'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Conversation? _selectedConversation(List<Conversation> conversations) {
    final selectedId = selectedConversationId;
    if (selectedId == null) return null;

    for (final conversation in conversations) {
      if (conversation.id == selectedId) return conversation;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final selectedConversation = _selectedConversation(provider.conversations);
    if (selectedConversationId != null && selectedConversation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedConversationId == null) return;
        returnToInbox(selectedConversationId!);
      });
    }

    if (selectedConversation != null) {
      return _buildConversationView(selectedConversation);
    }

    return Column(
      children: [
        _buildActionBar(),
        _buildSearchField(),
        _buildFilterStrip(provider),
        Expanded(child: _buildConversationList(provider)),
      ],
    );
  }

  Widget _buildConversationView(Conversation conversation) {
    return Column(
      children: [
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: 'Volver a bandeja de entrada',
                onPressed: () => returnToInbox(conversation.id),
              ),
              const Expanded(
                child: Text(
                  'Bandeja de entrada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full, size: 18),
                tooltip: 'Abrir mensajería completa',
                onPressed: () => _openFullChat(conversation),
              ),
            ],
          ),
        ),
        Expanded(
          child: ChatWindow(
            conversation: conversation,
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Padding(
      // Sin título la barra es sólo acciones: se ciñe para no dejar un hueco
      // entre el segmento y el buscador.
      padding: widget.showTitle
          ? const EdgeInsets.fromLTRB(12, 10, 8, 8)
          : const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (widget.showTitle)
              Expanded(
                child: Text(
                  'Mensajería',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
              )
            else
              const Spacer(),
            _buildActiveModeMenu(compact: constraints.maxWidth < 300),
            const SizedBox(width: 2),
            IconButton(
              tooltip: 'Nuevo chat interno',
              onPressed: _showNewChatDialog,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Recargar',
              onPressed: isRefreshing ? null : refreshInbox,
              visualDensity: VisualDensity.compact,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
            ),
            IconButton(
              tooltip: 'Abrir mensajería completa',
              onPressed: () => _openFullChat(),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_full, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: searchTerm.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Limpiar búsqueda',
                  onPressed: searchController.clear,
                ),
          hintText: 'Nombre, teléfono, trabajo, bici o factura',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveModeMenu({bool compact = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<bool>(
      initialValue: showOnlyActiveChats,
      tooltip: 'Elegir alcance de la bandeja',
      padding: EdgeInsets.zero,
      onSelected: (value) => unawaited(setShowOnlyActiveChats(value)),
      itemBuilder: (context) => [
        _buildActiveModeMenuItem(
          value: true,
          icon: Icons.bolt_outlined,
          label: 'Activos',
          description: 'Trabajo operativo abierto',
        ),
        _buildActiveModeMenuItem(
          value: false,
          icon: Icons.history,
          label: 'Historial',
          description: 'Incluye conversaciones cerradas',
        ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showOnlyActiveChats ? Icons.bolt_outlined : Icons.history,
              size: 15,
              color: colorScheme.primary,
            ),
            if (!compact) ...[
              const SizedBox(width: 5),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Text(
                  showOnlyActiveChats ? 'Activos' : 'Historial',
                  key: ValueKey(showOnlyActiveChats),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 15,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<bool> _buildActiveModeMenuItem({
    required bool value,
    required IconData icon,
    required String label,
    required String description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = value == showOnlyActiveChats;
    return PopupMenuItem<bool>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected) Icon(Icons.check, size: 17, color: colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildFilterStrip(ChatProvider provider) {
    final visibleConversations = _clientConversations(provider.conversations)
        .where(_matchesActivityMode)
        .toList();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final counts = <_MessageFilter, int>{
      _MessageFilter.all: visibleConversations.length,
      _MessageFilter.unread: visibleConversations
          .where((conversation) =>
              conversation.unreadCount > 0 ||
              (conversation.isSupport && conversation.status == 'pending'))
          .length,
      _MessageFilter.whatsapp:
          visibleConversations.where((c) => c.isWhatsApp).length,
      _MessageFilter.meta:
          visibleConversations.where((c) => c.isMetaMessaging).length,
      _MessageFilter.instagram:
          visibleConversations.where((c) => c.isInstagram).length,
      _MessageFilter.messenger:
          visibleConversations.where((c) => c.isFacebookMessenger).length,
      _MessageFilter.web:
          visibleConversations.where((c) => c.isWebsitePortal).length,
      _MessageFilter.clients:
          visibleConversations.where((c) => c.isSupport).length,
      _MessageFilter.team:
          visibleConversations.where((c) => c.isInternal).length,
    };
    final resultCount = _visibleConversationResults(provider).length +
        (searchTerm.isEmpty || !_filterAllowsWhatsAppContacts
            ? 0
            : _matchingWhatsAppContacts(provider).take(10).length);

    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(12, 0, 14, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactMenu = constraints.maxWidth < 300;
          final showResultCount = constraints.maxWidth >= 360;

          return Row(
            children: [
              PopupMenuButton<_MessageFilter>(
                initialValue: _filter,
                tooltip: 'Filtrar conversaciones',
                padding: EdgeInsets.zero,
                onSelected: (filter) => setState(() => _filter = filter),
                itemBuilder: (context) => _MessageFilter.values
                    .map(
                      (filter) => PopupMenuItem<_MessageFilter>(
                        value: filter,
                        height: 42,
                        child: Row(
                          children: [
                            _buildFilterGlyph(
                              filter,
                              size: 17,
                              color: filter == _filter
                                  ? _filterAccent(filter, colorScheme)
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _filterLabel(filter),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: filter == _filter
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${counts[filter] ?? 0}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (filter == _filter) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                    .toList(),
                child: Container(
                  height: 32,
                  padding: EdgeInsets.symmetric(
                    horizontal: compactMenu ? 6 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      colorScheme.primary.withValues(alpha: 0.055),
                      colorScheme.surface,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFilterGlyph(
                        _filter,
                        size: 16,
                        color: _filterAccent(_filter, colorScheme),
                      ),
                      if (!compactMenu) ...[
                        const SizedBox(width: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 140),
                          child: Text(
                            _filterLabel(_filter),
                            key: ValueKey(_filter),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else
                        const SizedBox(width: 4),
                      Text(
                        '${counts[_filter] ?? 0}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.expand_more,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _buildPlatformFilterButton(
                key: const ValueKey('quick_messages_platform_whatsapp'),
                filter: _MessageFilter.whatsapp,
                label: 'WhatsApp',
                icon: ConversationChannelPresentation.platformIconForChannel(
                  'whatsapp',
                ),
                accent: ConversationChannelPresentation.whatsAppAccent,
                count: counts[_MessageFilter.whatsapp] ?? 0,
              ),
              const SizedBox(width: 4),
              _buildPlatformFilterButton(
                key: const ValueKey('quick_messages_platform_instagram'),
                filter: _MessageFilter.instagram,
                label: 'Instagram',
                icon: ConversationChannelPresentation.platformIconForChannel(
                  'instagram',
                ),
                accent: ConversationChannelPresentation.instagramAccent,
                count: counts[_MessageFilter.instagram] ?? 0,
              ),
              const SizedBox(width: 4),
              _buildPlatformFilterButton(
                key: const ValueKey('quick_messages_platform_messenger'),
                filter: _MessageFilter.messenger,
                label: 'Messenger',
                icon: ConversationChannelPresentation.platformIconForChannel(
                  'facebook_messenger',
                ),
                accent: ConversationChannelPresentation.facebookMessengerAccent,
                count: counts[_MessageFilter.messenger] ?? 0,
              ),
              const SizedBox(width: 4),
              _buildPlatformFilterButton(
                key: const ValueKey('quick_messages_platform_web'),
                filter: _MessageFilter.web,
                label: 'Web',
                icon: ConversationChannelPresentation.platformIconForChannel(
                  'website_portal',
                ),
                accent: ConversationChannelPresentation.websiteAccent,
                count: counts[_MessageFilter.web] ?? 0,
              ),
              if (showResultCount) ...[
                const Spacer(),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    child: Text(
                      '$resultCount ${resultCount == 1 ? 'resultado' : 'resultados'}',
                      key: ValueKey('$resultCount-$_filter-$searchTerm'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlatformFilterButton({
    required Key key,
    required _MessageFilter filter,
    required String label,
    required IconData icon,
    required Color accent,
    required int count,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _filter == filter;
    final background = selected
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.12),
            colorScheme.surface,
          )
        : colorScheme.surface;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Filtrar por $label',
      value: '$count ${count == 1 ? 'conversación' : 'conversaciones'}',
      child: Tooltip(
        message: 'Filtrar por $label',
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 350),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.58)
                  : colorScheme.outlineVariant.withValues(alpha: 0.8),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(
                () => _filter = selected ? _MessageFilter.all : filter,
              ),
              child: Center(
                child: FaIcon(
                  icon,
                  size: 16,
                  color: selected ? accent : accent.withValues(alpha: 0.88),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _filterLabel(_MessageFilter filter) {
    return switch (filter) {
      _MessageFilter.all => 'Todos',
      _MessageFilter.unread => 'Sin leer',
      _MessageFilter.meta => 'Meta',
      _MessageFilter.whatsapp => 'WhatsApp',
      _MessageFilter.instagram => 'Instagram',
      _MessageFilter.messenger => 'Messenger',
      _MessageFilter.web => 'Web',
      _MessageFilter.clients => 'Clientes',
      _MessageFilter.team => 'Equipo',
    };
  }

  IconData _filterIcon(_MessageFilter filter) {
    return switch (filter) {
      _MessageFilter.all => Icons.inbox_outlined,
      _MessageFilter.unread => Icons.mark_chat_unread_outlined,
      _MessageFilter.meta =>
        ConversationChannelPresentation.platformIconForChannel(
          'facebook_messenger',
        ),
      _MessageFilter.whatsapp =>
        ConversationChannelPresentation.platformIconForChannel('whatsapp'),
      _MessageFilter.instagram =>
        ConversationChannelPresentation.platformIconForChannel('instagram'),
      _MessageFilter.messenger =>
        ConversationChannelPresentation.platformIconForChannel(
          'facebook_messenger',
        ),
      _MessageFilter.web =>
        ConversationChannelPresentation.platformIconForChannel(
          'website_portal',
        ),
      _MessageFilter.clients => Icons.person_outline,
      _MessageFilter.team => Icons.groups_outlined,
    };
  }

  Widget _buildFilterGlyph(
    _MessageFilter filter, {
    required double size,
    required Color color,
  }) {
    final icon = _filterIcon(filter);
    return switch (filter) {
      _MessageFilter.meta ||
      _MessageFilter.whatsapp ||
      _MessageFilter.instagram ||
      _MessageFilter.messenger ||
      _MessageFilter.web =>
        FaIcon(icon, size: size, color: color),
      _ => Icon(icon, size: size, color: color),
    };
  }

  Color _filterAccent(_MessageFilter filter, ColorScheme colorScheme) {
    return switch (filter) {
      _MessageFilter.meta =>
        ConversationChannelPresentation.facebookMessengerAccent,
      _MessageFilter.whatsapp => ConversationChannelPresentation.whatsAppAccent,
      _MessageFilter.instagram =>
        ConversationChannelPresentation.instagramAccent,
      _MessageFilter.messenger =>
        ConversationChannelPresentation.facebookMessengerAccent,
      _MessageFilter.web => ConversationChannelPresentation.websiteAccent,
      _ => colorScheme.primary,
    };
  }

  List<Conversation> _visibleConversationResults(ChatProvider provider) {
    return _clientConversations(provider.conversations)
        .where(_matchesActivityMode)
        .where(_matchesFilter)
        .where((conversation) => _matchesSearch(provider, conversation))
        .toList()
      ..sort(_compareConversations);
  }

  Widget _buildConversationList(ChatProvider provider) {
    final isSearching = searchTerm.isNotEmpty;
    final conversations = _visibleConversationResults(provider);
    final contactMatches = isSearching && _filterAllowsWhatsAppContacts
        ? _matchingWhatsAppContacts(provider).take(10).toList()
        : <Customer>[];
    final hasClientConversations =
        _clientConversations(provider.conversations).isNotEmpty;

    if (conversations.isEmpty &&
        contactMatches.isEmpty &&
        !(isSearching && _isLoadingWhatsAppContacts)) {
      return _buildEmptyState(
        !hasClientConversations,
        activeModeEmpty: showOnlyActiveChats &&
            hasClientConversations &&
            !_clientConversations(provider.conversations)
                .any(_matchesActivityMode),
      );
    }

    return RefreshIndicator(
      onRefresh: refreshInbox,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (isSearching && conversations.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildSearchSectionHeader(
                icon: Icons.chat_bubble_outline,
                title: 'Chats',
                count: conversations.length,
              ),
            ),
          SliverList.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return Column(
                key: ValueKey('conversation-${conversation.id}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildConversationResult(provider, conversation),
                  const Divider(height: 1),
                ],
              );
            },
          ),
          if (isSearching &&
              (contactMatches.isNotEmpty || _isLoadingWhatsAppContacts))
            SliverToBoxAdapter(
              child: _buildSearchSectionHeader(
                icon: Icons.phone_in_talk_outlined,
                title: 'Clientes con WhatsApp',
                count: contactMatches.length,
              ),
            ),
          if (isSearching &&
              _filterAllowsWhatsAppContacts &&
              _isLoadingWhatsAppContacts)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          SliverList.builder(
            itemCount: contactMatches.length,
            itemBuilder: (context, index) {
              final customer = contactMatches[index];
              return Column(
                key: ValueKey('whatsapp-contact-${customer.id}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildWhatsAppContactTile(customer),
                  const Divider(height: 1),
                ],
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  Widget _buildConversationResult(
    ChatProvider provider,
    Conversation conversation,
  ) {
    final isPinned = _pinnedConversationIds.contains(conversation.id);
    return ConversationTile(
      conversation: conversation,
      isActive: selectedConversationId != null &&
          conversation.id == selectedConversationId,
      isPinned: isPinned,
      isMobile: false,
      subtitle: _subtitle(conversation),
      onTap: () => openConversationInPanel(conversation.id),
      onTogglePinned: () => _togglePinnedConversation(conversation.id),
      onArchive: () => _confirmArchive(provider, conversation),
    );
  }



  Widget _buildSearchSectionHeader({
    required IconData icon,
    required String title,
    required int count,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppContactTile(Customer customer) {
    final theme = Theme.of(context);
    final phone = customer.phone?.trim() ?? '';
    final isOpening = _openingCustomerId == customer.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isOpening ? null : () => _openWhatsAppContact(customer),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: _buildCustomerAvatar(customer),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isOpening)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: Color(0xFF64748B),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerAvatar(Customer customer) {
    const accentColor = Color(0xFF047857);
    final fallbackAvatar = CircleAvatar(
      radius: 22,
      backgroundColor: accentColor.withValues(alpha: 0.1),
      child: Text(
        customer.initials,
        style: const TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
    final imageUrl = customer.imageUrl?.trim();

    if (imageUrl == null || imageUrl.isEmpty) return fallbackAvatar;

    return ImageService.buildCachedImage(
      imageUrl: imageUrl,
      width: 44,
      height: 44,
      isCircular: true,
      placeholder: fallbackAvatar,
      errorWidget: fallbackAvatar,
    );
  }

  Iterable<Conversation> _clientConversations(
    List<Conversation> conversations,
  ) {
    return conversations.where(
      (conversation) => !conversation.isSupplierConversation,
    );
  }

  bool _matchesFilter(Conversation conversation) {
    return switch (_filter) {
      _MessageFilter.all => true,
      _MessageFilter.unread => conversation.unreadCount > 0 ||
          (conversation.isSupport && conversation.status == 'pending'),
      _MessageFilter.meta => conversation.isMetaMessaging,
      _MessageFilter.whatsapp => conversation.isWhatsApp,
      _MessageFilter.instagram => conversation.isInstagram,
      _MessageFilter.messenger => conversation.isFacebookMessenger,
      _MessageFilter.web => conversation.isWebsitePortal,
      _MessageFilter.clients => conversation.isSupport,
      _MessageFilter.team => conversation.isInternal,
    };
  }

  bool get _filterAllowsWhatsAppContacts =>
      _filter == _MessageFilter.all ||
      _filter == _MessageFilter.whatsapp ||
      _filter == _MessageFilter.clients;

  bool _matchesActivityMode(Conversation conversation) {
    return !showOnlyActiveChats ||
        conversation.isInternal ||
        ConversationActivity.isActiveConversation(conversation);
  }

  bool _matchesSearch(ChatProvider provider, Conversation conversation) {
    if (searchTerm.isEmpty) return true;

    final hint = conversation.contextHint;
    return ConversationSearch.matches(searchTerm, [
      provider.getChatTitle(conversation),
      conversation.title ?? '',
      conversation.creatorName ?? '',
      hint?.customerName ?? '',
      hint?.phone ?? '',
      hint?.jobNumber ?? '',
      hint?.jobStatus ?? '',
      hint?.bikeName ?? '',
      hint?.invoiceNumber ?? '',
      hint?.invoiceStatus ?? '',
      conversation.contextType ?? '',
      conversation.contextId ?? '',
      conversation.channelLabel,
      conversation.lastMessageContent ?? '',
      _subtitle(conversation),
    ]);
  }

  List<Customer> _matchingWhatsAppContacts(ChatProvider provider) {
    final existingCustomerIds = <String>{};
    final existingPhones = <String>{};
    final existingNames = <String>{};
    for (final conversation in _clientConversations(provider.conversations)) {
      if (!conversation.isWhatsApp) continue;
      final title =
          ConversationSearch.normalize(provider.getChatTitle(conversation));
      if (title.isNotEmpty) existingNames.add(title);
      final customerId = conversation.contextHint?.customerId;
      if (customerId != null && customerId.isNotEmpty) {
        existingCustomerIds.add(customerId);
      }
      final phone = _normalizedPhone(conversation.contextHint?.phone);
      if (phone.isNotEmpty) existingPhones.add(phone);
    }

    return _whatsAppContacts.where((customer) {
      final customerId = customer.id;
      final phone = _normalizedPhone(customer.phone);
      final name = ConversationSearch.normalize(customer.name);
      if (customerId != null && existingCustomerIds.contains(customerId)) {
        return false;
      }
      if (phone.isNotEmpty && existingPhones.contains(phone)) {
        return false;
      }
      if (name.isNotEmpty && existingNames.contains(name)) {
        return false;
      }
      return _matchesCustomerSearch(customer);
    }).toList();
  }

  bool _matchesCustomerSearch(Customer customer) {
    final phone = _normalizedPhone(customer.phone);
    return ConversationSearch.matches(searchTerm, [
      customer.name,
      customer.email ?? '',
      customer.rut,
      customer.phone ?? '',
      phone,
    ]);
  }

  int _compareConversations(Conversation a, Conversation b) {
    final pinCompare = _pinRank(b).compareTo(_pinRank(a));
    if (pinCompare != 0) return pinCompare;

    final pendingCompare = _pendingRank(b).compareTo(_pendingRank(a));
    if (pendingCompare != 0) return pendingCompare;

    final unreadCompare = _unreadRank(b).compareTo(_unreadRank(a));
    if (unreadCompare != 0) return unreadCompare;

    final aDate = a.lastMessageAt ?? a.updatedAt;
    final bDate = b.lastMessageAt ?? b.updatedAt;
    final dateCompare = bDate.compareTo(aDate);
    if (dateCompare != 0) return dateCompare;

    return b.unreadCount.compareTo(a.unreadCount);
  }

  int _pendingRank(Conversation conversation) {
    return conversation.isSupport && conversation.status == 'pending' ? 1 : 0;
  }

  int _unreadRank(Conversation conversation) {
    return conversation.unreadCount > 0 ? 1 : 0;
  }

  int _pinRank(Conversation conversation) {
    return _pinnedConversationIds.contains(conversation.id) ? 1 : 0;
  }

  String _subtitle(Conversation conversation) {
    final contextLabel = _contextLabel(conversation.contextType);

    if (conversation.isSupport) {
      final statusLabel = switch (conversation.status) {
        'pending' =>
          'Solicitud ${conversation.shortChannelLabel.toLowerCase()} pendiente',
        'resolved' => 'Resuelto',
        _ => conversation.channelLabel,
      };
      return contextLabel == null
          ? statusLabel
          : '$contextLabel · $statusLabel';
    }

    return contextLabel == null ? 'Chat de equipo' : '$contextLabel · Equipo';
  }

  String? _contextLabel(String? contextType) {
    switch (contextType) {
      case 'order':
        return 'Pedido web';
      case 'job':
        return 'Trabajo';
      case 'invoice':
        return 'Factura';
      case 'bike':
        return 'Bicicleta';
      case 'customer':
        return 'Cliente';
      case 'product':
        return 'Producto';
      default:
        return null;
    }
  }

  Future<bool> _confirmArchive(
    ChatProvider provider,
    Conversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Archivar chat?'),
        content: Text(
          'El chat con "${provider.getChatTitle(conversation)}" pasará al historial sin perder mensajes ni trazabilidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    final success = await provider.archiveConversation(conversation.id);
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo archivar la conversación'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return success;
  }

  Widget _buildEmptyState(
    bool isTotallyEmpty, {
    bool activeModeEmpty = false,
  }) {
    final theme = Theme.of(context);
    final title = activeModeEmpty
        ? 'Sin chats activos'
        : isTotallyEmpty
            ? 'Sin conversaciones'
            : 'No hay mensajes para este filtro';
    final subtitle = activeModeEmpty
        ? 'Desactiva "Solo activos" para ver el historial completo.'
        : isTotallyEmpty
            ? 'Los chats internos, web, WhatsApp, Instagram y Messenger aparecerán aquí.'
            : 'Prueba con otro filtro o limpia la búsqueda.';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.chat_bubble_outline,
          size: 46,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
