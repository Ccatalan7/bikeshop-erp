import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/crm/models/crm_models.dart';
import '../../modules/crm/services/customer_service.dart';
import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/widgets/chat_window.dart';
import '../../modules/messaging/widgets/conversation_tile.dart';
import '../../modules/messaging/widgets/new_chat_dialog.dart';
import '../services/image_service.dart';
import '../services/right_toolbar_service.dart';

enum _MessageFilter { all, unread, whatsapp, clients, team }

class QuickMessagesPanel extends StatefulWidget {
  const QuickMessagesPanel({super.key});

  @override
  State<QuickMessagesPanel> createState() => _QuickMessagesPanelState();
}

class _QuickMessagesPanelState extends State<QuickMessagesPanel> {
  final TextEditingController _searchController = TextEditingController();

  _MessageFilter _filter = _MessageFilter.all;
  String _searchTerm = '';
  String? _selectedConversationId;
  String? _openingCustomerId;
  Set<String> _pinnedConversationIds = {};
  List<Customer> _whatsAppContacts = [];
  bool _isRefreshing = false;
  bool _isLoadingWhatsAppContacts = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    unawaited(_loadPinnedConversations());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<ChatProvider>().loadConversations());
        unawaited(_loadWhatsAppContacts());
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() => _searchTerm = _normalizeSearchText(_searchController.text));
  }

  String _normalizeSearchText(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    return text
        .replaceAll(RegExp(r'[áàäâãåā]'), 'a')
        .replaceAll(RegExp(r'[éèëêē]'), 'e')
        .replaceAll(RegExp(r'[íìïîī]'), 'i')
        .replaceAll(RegExp(r'[óòöôõøō]'), 'o')
        .replaceAll(RegExp(r'[úùüûū]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c');
  }

  Future<void> _loadPinnedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = prefs.getStringList('quick_messages_pinned_conversations');
    if (!mounted || pinned == null) return;
    setState(() => _pinnedConversationIds = pinned.toSet());
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

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await context.read<ChatProvider>().loadConversations();
    await _loadWhatsAppContacts();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
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
        _selectedConversationId = conversationId;
        _openingCustomerId = null;
      });
      _searchController.clear();
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
    final selectedId = _selectedConversationId;
    if (selectedId == null) return null;

    for (final conversation in conversations) {
      if (conversation.id == selectedId) {
        return conversation;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final selectedConversation = _selectedConversation(provider.conversations);

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
                onPressed: () {
                  setState(() => _selectedConversationId = null);
                },
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showNewChatDialog,
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('Nuevo chat'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(38),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Recargar',
                onPressed: _isRefreshing ? null : _refresh,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Abrir mensajería completa',
                onPressed: () => _openFullChat(),
                icon: const Icon(Icons.open_in_full, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchTerm.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Limpiar búsqueda',
                  onPressed: _searchController.clear,
                ),
          hintText: 'Buscar chats o clientes WhatsApp...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterStrip(ChatProvider provider) {
    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
              _MessageFilter.all, 'Todos', provider.conversations.length),
          _buildFilterChip(
              _MessageFilter.unread, 'Sin leer', provider.totalUnreadCount),
          _buildFilterChip(
            _MessageFilter.whatsapp,
            'WhatsApp',
            provider.conversations.where((c) => c.isWhatsApp).length,
          ),
          _buildFilterChip(
            _MessageFilter.clients,
            'Clientes',
            provider.conversations.where((c) => c.isSupport).length,
          ),
          _buildFilterChip(
            _MessageFilter.team,
            'Equipo',
            provider.conversations.where((c) => c.isInternal).length,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(_MessageFilter filter, String label, int count) {
    final theme = Theme.of(context);
    final selected = _filter == filter;
    final colorScheme = theme.colorScheme;
    final accentColor = switch (filter) {
      _MessageFilter.unread => const Color(0xFF16A34A),
      _MessageFilter.whatsapp => const Color(0xFF047857),
      _MessageFilter.clients => const Color(0xFF0F4C81),
      _MessageFilter.team => const Color(0xFF475569),
      _MessageFilter.all => colorScheme.primary,
    };
    final hasSignal = filter == _MessageFilter.unread && count > 0;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => setState(() => _filter = filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.11)
                : hasSignal
                    ? accentColor.withValues(alpha: 0.07)
                    : colorScheme.surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: 0.55)
                  : hasSignal
                      ? accentColor.withValues(alpha: 0.28)
                      : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: accentColor),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? accentColor
                      : hasSignal
                          ? accentColor
                          : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 19),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? accentColor.withValues(alpha: 0.16)
                      : hasSignal
                          ? accentColor.withValues(alpha: 0.18)
                          : colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? accentColor
                        : hasSignal
                            ? accentColor
                            : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(ChatProvider provider) {
    final isSearching = _searchTerm.isNotEmpty;
    final conversations = provider.conversations
        .where((conversation) => isSearching || _matchesFilter(conversation))
        .where((conversation) => _matchesSearch(provider, conversation))
        .toList()
      ..sort(_compareConversations);
    final contactMatches = isSearching
        ? _matchingWhatsAppContacts(provider).take(10).toList()
        : <Customer>[];

    if (conversations.isEmpty &&
        contactMatches.isEmpty &&
        !(isSearching && _isLoadingWhatsAppContacts)) {
      return _buildEmptyState(provider.conversations.isEmpty);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (isSearching && conversations.isNotEmpty)
            _buildSearchSectionHeader(
              icon: Icons.chat_bubble_outline,
              title: 'Chats',
              count: conversations.length,
            ),
          for (final conversation in conversations) ...[
            _buildConversationResult(provider, conversation),
            const Divider(height: 1),
          ],
          if (isSearching &&
              (contactMatches.isNotEmpty || _isLoadingWhatsAppContacts)) ...[
            _buildSearchSectionHeader(
              icon: Icons.phone_in_talk_outlined,
              title: 'Clientes con WhatsApp',
              count: contactMatches.length,
            ),
            if (_isLoadingWhatsAppContacts)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            for (final customer in contactMatches) ...[
              _buildWhatsAppContactTile(customer),
              const Divider(height: 1),
            ],
          ],
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
      isActive: conversation.id == provider.activeConversationId,
      isPinned: isPinned,
      isMobile: false,
      subtitle: _subtitle(conversation),
      onTap: () {
        setState(() => _selectedConversationId = conversation.id);
        context.read<ChatProvider>().setActiveConversation(conversation.id);
      },
      onTogglePinned: () => _togglePinnedConversation(conversation.id),
      onDelete: () => _confirmDelete(provider, conversation),
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
                  Icons.add_comment_outlined,
                  size: 19,
                  color: Color(0xFF047857),
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

  bool _matchesFilter(Conversation conversation) {
    return switch (_filter) {
      _MessageFilter.all => true,
      _MessageFilter.unread => conversation.unreadCount > 0 ||
          (conversation.isSupport && conversation.status == 'pending'),
      _MessageFilter.whatsapp => conversation.isWhatsApp,
      _MessageFilter.clients => conversation.isSupport,
      _MessageFilter.team => conversation.isInternal,
    };
  }

  bool _matchesSearch(ChatProvider provider, Conversation conversation) {
    if (_searchTerm.isEmpty) return true;

    final haystack = _normalizeSearchText([
      provider.getChatTitle(conversation),
      conversation.title ?? '',
      conversation.creatorName ?? '',
      conversation.contextHint?.customerLabel ?? '',
      conversation.contextHint?.phone ?? '',
      conversation.contextHint?.jobNumber ?? '',
      conversation.contextHint?.jobStatus ?? '',
      conversation.contextHint?.bikeName ?? '',
      conversation.channelLabel,
      conversation.lastMessageContent ?? '',
      _subtitle(conversation),
    ].join(' '));

    return haystack.contains(_searchTerm);
  }

  List<Customer> _matchingWhatsAppContacts(ChatProvider provider) {
    final existingCustomerIds = <String>{};
    final existingPhones = <String>{};
    final existingNames = <String>{};
    for (final conversation in provider.conversations) {
      if (!conversation.isWhatsApp) continue;
      final title = _normalizeSearchText(provider.getChatTitle(conversation));
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
      final name = _normalizeSearchText(customer.name);
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
    final searchDigits = _normalizedPhone(_searchTerm);
    final haystack = _normalizeSearchText([
      customer.name,
      customer.email ?? '',
      customer.rut,
      customer.phone ?? '',
      phone,
    ].join(' '));

    return haystack.contains(_searchTerm) ||
        (searchDigits.isNotEmpty && phone.contains(searchDigits));
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

  Future<bool> _confirmDelete(
    ChatProvider provider,
    Conversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar chat?'),
        content: Text(
          'Estás a punto de eliminar el chat con "${provider.getChatTitle(conversation)}". Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    final success = await provider.deleteConversation(conversation.id);
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar la conversación'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return success;
  }

  Widget _buildEmptyState(bool isTotallyEmpty) {
    final theme = Theme.of(context);
    final title = isTotallyEmpty
        ? 'Sin conversaciones'
        : 'No hay mensajes para este filtro';
    final subtitle = isTotallyEmpty
        ? 'Los chats internos, web y WhatsApp aparecerán aquí.'
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
