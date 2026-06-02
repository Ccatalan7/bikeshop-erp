import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/crm/models/crm_models.dart';
import '../../modules/crm/services/customer_service.dart';
import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/utils/conversation_activity.dart';
import '../../modules/messaging/widgets/chat_window.dart';
import '../../modules/messaging/widgets/conversation_tile.dart';
import '../../modules/messaging/widgets/new_chat_dialog.dart';
import '../../modules/purchases/models/purchase_invoice.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../models/supplier.dart' as shared_supplier;
import '../services/image_service.dart';
import '../services/right_toolbar_service.dart';

enum _MessageFilter { all, unread, whatsapp, clients, suppliers, team }

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
  String? _panelActiveConversationId;
  String? _openingCustomerId;
  ChatProvider? _chatProvider;
  Set<String> _pinnedConversationIds = {};
  List<Customer> _whatsAppContacts = [];
  List<shared_supplier.Supplier> _supplierChatSuppliers = [];
  List<PurchaseInvoice> _supplierChatInvoices = [];
  bool _isRefreshing = false;
  bool _isLoadingWhatsAppContacts = false;
  bool _isLoadingSupplierChats = false;
  bool _showOnlyActiveChats = true;
  String? _openingSupplierId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    ConversationActivity.showOnlyActiveChats.addListener(
      _handleActiveModeChanged,
    );
    unawaited(_loadPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          context
              .read<ChatProvider>()
              .loadConversations(refreshContextHints: true),
        );
        unawaited(_loadSupplierChatData());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = context.read<ChatProvider>();
  }

  @override
  void dispose() {
    final panelActiveConversationId = _panelActiveConversationId;
    if (panelActiveConversationId != null) {
      _chatProvider?.clearActiveConversation(
          conversationId: panelActiveConversationId);
    }
    _searchController.removeListener(_handleSearchChanged);
    ConversationActivity.showOnlyActiveChats.removeListener(
      _handleActiveModeChanged,
    );
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextSearchTerm = _normalizeSearchText(_searchController.text);
    setState(() => _searchTerm = nextSearchTerm);
    if (nextSearchTerm.isNotEmpty && _whatsAppContacts.isEmpty) {
      unawaited(_loadWhatsAppContacts());
    }
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

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = prefs.getStringList('quick_messages_pinned_conversations');
    final showOnlyActive =
        prefs.getBool(ConversationActivity.activeOnlyPreferenceKey) ?? true;
    if (!mounted) return;
    if (ConversationActivity.showOnlyActiveChats.value != showOnlyActive) {
      ConversationActivity.showOnlyActiveChats.value = showOnlyActive;
    }
    setState(() {
      _pinnedConversationIds = pinned?.toSet() ?? {};
      _showOnlyActiveChats = ConversationActivity.showOnlyActiveChats.value;
    });
  }

  Future<void> _setShowOnlyActiveChats(bool value) async {
    if (ConversationActivity.showOnlyActiveChats.value != value) {
      ConversationActivity.showOnlyActiveChats.value = value;
    } else if (mounted) {
      setState(() => _showOnlyActiveChats = value);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ConversationActivity.activeOnlyPreferenceKey, value);
  }

  void _handleActiveModeChanged() {
    if (!mounted) return;
    final value = ConversationActivity.showOnlyActiveChats.value;
    if (_showOnlyActiveChats == value) return;
    setState(() => _showOnlyActiveChats = value);
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

  Future<void> _loadSupplierChatData() async {
    if (_isLoadingSupplierChats) return;
    setState(() => _isLoadingSupplierChats = true);
    try {
      final purchaseService = context.read<PurchaseService>();
      final suppliers = await purchaseService.getSuppliers(activeOnly: true);
      final invoices = await purchaseService.getPurchaseInvoicesForList();

      if (!mounted) return;
      setState(() {
        _supplierChatSuppliers = suppliers
            .where((supplier) => _supplierChatPhone(supplier) != null)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _supplierChatInvoices = invoices;
        _isLoadingSupplierChats = false;
      });
    } catch (error) {
      debugPrint('Error loading supplier chats in quick panel: $error');
      if (mounted) {
        setState(() => _isLoadingSupplierChats = false);
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
    await context
        .read<ChatProvider>()
        .loadConversations(refreshContextHints: true);
    await _loadSupplierChatData();
    if (_searchTerm.isNotEmpty || _whatsAppContacts.isNotEmpty) {
      await _loadWhatsAppContacts();
    }
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
        _panelActiveConversationId = conversationId;
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
    if (_selectedConversationId != null && selectedConversation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedConversationId == null) return;
        _returnToInbox(_selectedConversationId!);
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
                onPressed: () => _returnToInbox(conversation.id),
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
              _buildActiveModeToggleButton(),
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

  Widget _buildActiveModeToggleButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _showOnlyActiveChats;

    return Tooltip(
      waitDuration: const Duration(milliseconds: 1500),
      message: active
          ? 'Solo activos: muestra clientes y proveedores con trabajos, facturas o compras abiertas.'
          : 'Historial completo: muestra también conversaciones y documentos cerrados.',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => unawaited(_setShowOnlyActiveChats(!active)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: 46,
          height: 24,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.18)
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: active ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: active ? colorScheme.primary : colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                active ? Icons.filter_alt : Icons.history,
                size: 12,
                color: active ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterStrip(ChatProvider provider) {
    final visibleConversations =
        provider.conversations.where(_matchesActivityMode).toList();
    final supplierEntries = _quickSupplierEntries(
      provider.conversations
          .where((conversation) => conversation.isSupplierConversation)
          .toList(),
      includeInactive: !_showOnlyActiveChats,
    );
    final supplierConversationIds = supplierEntries
        .map((entry) => entry.conversation?.id)
        .whereType<String>()
        .toSet();
    final visibleNonSupplierConversations = visibleConversations
        .where(
          (conversation) => !supplierConversationIds.contains(conversation.id),
        )
        .toList();

    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            _MessageFilter.all,
            'Todos',
            visibleNonSupplierConversations.length + supplierEntries.length,
          ),
          _buildFilterChip(
            _MessageFilter.unread,
            'Sin leer',
            visibleNonSupplierConversations
                .where((conversation) =>
                    conversation.unreadCount > 0 ||
                    (conversation.isSupport &&
                        conversation.status == 'pending'))
                .length,
          ),
          _buildFilterChip(
            _MessageFilter.whatsapp,
            'WhatsApp',
            visibleNonSupplierConversations.where((c) => c.isWhatsApp).length,
          ),
          _buildFilterChip(
            _MessageFilter.clients,
            'Clientes',
            visibleNonSupplierConversations
                .where((c) => c.isSupport && !c.isSupplierConversation)
                .length,
          ),
          _buildFilterChip(
            _MessageFilter.suppliers,
            'Proveedores',
            supplierEntries.length,
          ),
          _buildFilterChip(
            _MessageFilter.team,
            'Equipo',
            visibleNonSupplierConversations.where((c) => c.isInternal).length,
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
      _MessageFilter.suppliers => const Color(0xFF7C3AED),
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
    final supplierEntries = _quickSupplierEntries(
      provider.conversations
          .where((conversation) => conversation.isSupplierConversation)
          .toList(),
      includeInactive: !_showOnlyActiveChats,
    ).where((entry) => _matchesSupplierEntryFilter(entry, isSearching)).toList()
      ..sort(_compareSupplierEntries);
    final supplierConversationIds = supplierEntries
        .map((entry) => entry.conversation?.id)
        .whereType<String>()
        .toSet();
    final conversations = provider.conversations
        .where(_matchesActivityMode)
        .where(
          (conversation) => !supplierConversationIds.contains(conversation.id),
        )
        .where((conversation) => isSearching || _matchesFilter(conversation))
        .where((conversation) => _matchesSearch(provider, conversation))
        .toList()
      ..sort(_compareConversations);
    final contactMatches = isSearching
        ? _matchingWhatsAppContacts(provider).take(10).toList()
        : <Customer>[];

    if (conversations.isEmpty &&
        supplierEntries.isEmpty &&
        contactMatches.isEmpty &&
        !(isSearching && _isLoadingWhatsAppContacts)) {
      return _buildEmptyState(
        provider.conversations.isEmpty,
        activeModeEmpty: _showOnlyActiveChats &&
            provider.conversations.isNotEmpty &&
            !provider.conversations.any(_matchesActivityMode),
      );
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
          if (supplierEntries.isNotEmpty) ...[
            if (isSearching || _filter != _MessageFilter.suppliers)
              _buildSearchSectionHeader(
                icon: Icons.storefront_outlined,
                title: 'Proveedores',
                count: supplierEntries.length,
              ),
            for (final entry in supplierEntries) ...[
              _buildSupplierResult(entry),
              const Divider(height: 1),
            ],
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
      isActive: _selectedConversationId != null &&
          conversation.id == _selectedConversationId,
      isPinned: isPinned,
      isMobile: false,
      subtitle: _subtitle(conversation),
      onTap: () => _openConversationInPanel(conversation),
      onTogglePinned: () => _togglePinnedConversation(conversation.id),
      onDelete: () => _confirmDelete(provider, conversation),
    );
  }

  Widget _buildSupplierResult(_QuickSupplierChatEntry entry) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conversation = entry.conversation;
    final isSelected = conversation != null &&
        _selectedConversationId != null &&
        conversation.id == _selectedConversationId;
    final isOpening = _openingSupplierId == entry.supplier.id;
    final preview = conversation?.lastMessageContent?.trim();
    final invoice = entry.relevantInvoice(_showOnlyActiveChats);

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: isOpening ? null : () => _openSupplierChat(entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                child: Text(
                  _supplierInitials(entry.supplier.name),
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.supplier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview?.isNotEmpty == true
                          ? preview!
                          : '${entry.phone} · Proveedor WhatsApp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                    if (invoice != null) ...[
                      const SizedBox(height: 6),
                      _buildSupplierInvoiceChip(invoice),
                    ],
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
                Icon(
                  conversation == null
                      ? Icons.add_comment_outlined
                      : Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierInvoiceChip(PurchaseInvoice invoice) {
    final color = _purchaseInvoiceStatusColor(invoice.status);
    final number = invoice.invoiceNumber.isEmpty
        ? invoice.supplierInvoiceNumber ?? 'Compra'
        : invoice.invoiceNumber;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$number · ${invoice.status.displayName} · ${_formatCLP(invoice.balance > 0 ? invoice.balance : invoice.total)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Future<void> _openSupplierChat(_QuickSupplierChatEntry entry) async {
    final conversation = entry.conversation;
    if (conversation != null) {
      _openConversationInPanel(conversation);
      return;
    }

    setState(() => _openingSupplierId = entry.supplier.id);
    try {
      final provider = context.read<ChatProvider>();
      await provider.openWhatsAppCustomerChat(
        phoneNumber: entry.phone,
        contactName: entry.supplier.name,
        contextType: 'supplier',
        contextId: entry.supplier.id,
      );
      if (!mounted) return;
      final conversationId = provider.activeConversationId;
      setState(() {
        _selectedConversationId = conversationId;
        _panelActiveConversationId = conversationId;
        _openingSupplierId = null;
      });
      _searchController.clear();
    } catch (error) {
      debugPrint('Error opening WhatsApp supplier from quick panel: $error');
      if (!mounted) return;
      setState(() => _openingSupplierId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar el chat del proveedor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openConversationInPanel(Conversation conversation) {
    setState(() {
      _selectedConversationId = conversation.id;
      _panelActiveConversationId = conversation.id;
    });
  }

  void _returnToInbox(String conversationId) {
    final shouldClearActive = _panelActiveConversationId == conversationId;
    debugPrint(
      '[InboxSync] panel:returnToInbox conversation=$conversationId '
      'clearActive=$shouldClearActive',
    );
    setState(() {
      _selectedConversationId = null;
      if (shouldClearActive) {
        _panelActiveConversationId = null;
      }
    });

    if (shouldClearActive) {
      context
          .read<ChatProvider>()
          .clearActiveConversation(conversationId: conversationId);
    }
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

  List<_QuickSupplierChatEntry> _quickSupplierEntries(
    List<Conversation> supplierConversations, {
    required bool includeInactive,
  }) {
    final entries = <_QuickSupplierChatEntry>[];
    final usedConversationIds = <String>{};

    for (final supplier in _supplierChatSuppliers) {
      final phone = _supplierChatPhone(supplier);
      if (phone == null) continue;
      final conversation = _findSupplierConversation(
        supplier,
        supplierConversations,
      );
      if (conversation != null) usedConversationIds.add(conversation.id);

      final invoices = _supplierInvoices(supplier.id);
      final hasActiveInvoices = invoices.any(_isActivePurchaseInvoice);
      final hasStandaloneActiveConversation = invoices.isEmpty &&
          conversation != null &&
          ConversationActivity.isActiveConversation(conversation);
      if (!includeInactive &&
          !hasActiveInvoices &&
          !hasStandaloneActiveConversation) {
        continue;
      }

      entries.add(
        _QuickSupplierChatEntry(
          supplier: supplier,
          phone: phone,
          conversation: conversation,
          invoices: invoices,
        ),
      );
    }

    for (final conversation in supplierConversations) {
      if (usedConversationIds.contains(conversation.id)) continue;
      final phone = conversation.contextHint?.supplierPhone ??
          conversation.contextHint?.phone ??
          '';
      if (!_hasWhatsAppPhone(phone)) continue;
      final supplier = _supplierFromConversation(conversation, phone);
      final invoices = supplier.id.isEmpty
          ? <PurchaseInvoice>[]
          : _supplierInvoices(supplier.id);
      final hasActiveInvoices = invoices.any(_isActivePurchaseInvoice);
      final hasActiveWork = hasActiveInvoices ||
          (invoices.isEmpty &&
              ConversationActivity.isActiveConversation(conversation));
      if (!includeInactive && !hasActiveWork) continue;

      entries.add(
        _QuickSupplierChatEntry(
          supplier: supplier,
          phone: phone,
          conversation: conversation,
          invoices: invoices,
        ),
      );
    }

    return entries;
  }

  Conversation? _findSupplierConversation(
    shared_supplier.Supplier supplier,
    List<Conversation> conversations,
  ) {
    for (final conversation in conversations) {
      if (conversation.contextHint?.supplierId == supplier.id ||
          (conversation.contextType == 'supplier' &&
              conversation.contextId == supplier.id)) {
        return conversation;
      }
    }

    final supplierPhones = _phoneCandidates(_supplierChatPhone(supplier));
    if (supplierPhones.isEmpty) return null;
    for (final conversation in conversations) {
      final conversationPhones = _phoneCandidates(
        conversation.contextHint?.supplierPhone ??
            conversation.contextHint?.phone,
      );
      if (supplierPhones.intersection(conversationPhones).isNotEmpty) {
        return conversation;
      }
    }
    return null;
  }

  shared_supplier.Supplier _supplierFromConversation(
    Conversation conversation,
    String phone,
  ) {
    final now = DateTime.now();
    return shared_supplier.Supplier(
      id: conversation.contextHint?.supplierId ?? conversation.contextId ?? '',
      tenantId: '',
      name: conversation.contextHint?.supplierLabel ??
          conversation.creatorName ??
          conversation.title ??
          phone,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<PurchaseInvoice> _supplierInvoices(String supplierId) {
    if (supplierId.isEmpty) return const [];
    final invoices = _supplierChatInvoices
        .where((invoice) => invoice.supplierId == supplierId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return invoices;
  }

  bool _isActivePurchaseInvoice(PurchaseInvoice invoice) {
    return ConversationActivity.isActivePurchaseInvoiceStatus(
      invoice.status.name,
    );
  }

  bool _matchesSupplierEntryFilter(
    _QuickSupplierChatEntry entry,
    bool isSearching,
  ) {
    if (!_matchesSupplierSearch(entry)) return false;

    if (isSearching) {
      return switch (_filter) {
        _MessageFilter.all ||
        _MessageFilter.whatsapp ||
        _MessageFilter.suppliers =>
          true,
        _MessageFilter.unread => (entry.conversation?.unreadCount ?? 0) > 0,
        _MessageFilter.clients || _MessageFilter.team => false,
      };
    }

    return switch (_filter) {
      _MessageFilter.all || _MessageFilter.suppliers => true,
      _MessageFilter.unread => (entry.conversation?.unreadCount ?? 0) > 0,
      _MessageFilter.whatsapp ||
      _MessageFilter.clients ||
      _MessageFilter.team =>
        false,
    };
  }

  bool _matchesSupplierSearch(_QuickSupplierChatEntry entry) {
    if (_searchTerm.isEmpty) return true;
    final haystack = _normalizeSearchText([
      entry.supplier.name,
      entry.phone,
      entry.conversation?.lastMessageContent ?? '',
      for (final invoice in entry.invoices)
        '${invoice.invoiceNumber} ${invoice.supplierInvoiceNumber ?? ''} ${invoice.status.displayName}',
    ].join(' '));
    return haystack.contains(_searchTerm);
  }

  int _compareSupplierEntries(
    _QuickSupplierChatEntry a,
    _QuickSupplierChatEntry b,
  ) {
    final aDate = a.lastActivityAt;
    final bDate = b.lastActivityAt;
    if (aDate != null && bDate != null) {
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;
    }
    if (aDate != null) return -1;
    if (bDate != null) return 1;
    return a.supplier.name.toLowerCase().compareTo(
          b.supplier.name.toLowerCase(),
        );
  }

  String? _supplierChatPhone(shared_supplier.Supplier supplier) {
    final salesRepPhone = supplier.salesRepPhone?.trim();
    if (_hasWhatsAppPhone(salesRepPhone)) return salesRepPhone;
    final phone = supplier.phone?.trim();
    if (_hasWhatsAppPhone(phone)) return phone;
    return null;
  }

  Set<String> _phoneCandidates(String? phone) {
    final digits = _normalizedPhone(phone);
    if (digits.isEmpty) return {};
    final candidates = <String>{digits};
    if (digits.startsWith('56') && digits.length > 2) {
      candidates.add(digits.substring(2));
    }
    if (digits.startsWith('9') && digits.length == 9) {
      candidates.add('56$digits');
    }
    if (digits.length >= 8) {
      candidates.add(digits.substring(digits.length - 8));
    }
    return candidates;
  }

  String _supplierInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  Color _purchaseInvoiceStatusColor(PurchaseInvoiceStatus status) {
    return switch (status) {
      PurchaseInvoiceStatus.paid => const Color(0xFF2563EB),
      PurchaseInvoiceStatus.received => const Color(0xFF16A34A),
      PurchaseInvoiceStatus.confirmed => const Color(0xFF7C3AED),
      PurchaseInvoiceStatus.sent => const Color(0xFF0EA5E9),
      PurchaseInvoiceStatus.cancelled => const Color(0xFFDC2626),
      PurchaseInvoiceStatus.draft => const Color(0xFF64748B),
    };
  }

  String _formatCLP(double value) {
    final rounded = value.round().toString();
    final formatted = rounded.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '\$$formatted';
  }

  bool _matchesFilter(Conversation conversation) {
    return switch (_filter) {
      _MessageFilter.all => true,
      _MessageFilter.unread => conversation.unreadCount > 0 ||
          (conversation.isSupport && conversation.status == 'pending'),
      _MessageFilter.whatsapp => conversation.isWhatsApp,
      _MessageFilter.clients =>
        conversation.isSupport && !conversation.isSupplierConversation,
      _MessageFilter.suppliers => conversation.isSupplierConversation,
      _MessageFilter.team => conversation.isInternal,
    };
  }

  bool _matchesActivityMode(Conversation conversation) {
    return !_showOnlyActiveChats ||
        conversation.isInternal ||
        ConversationActivity.isActiveConversation(conversation);
  }

  bool _matchesSearch(ChatProvider provider, Conversation conversation) {
    if (_searchTerm.isEmpty) return true;

    final haystack = _normalizeSearchText([
      provider.getChatTitle(conversation),
      conversation.title ?? '',
      conversation.creatorName ?? '',
      conversation.contextHint?.customerLabel ?? '',
      conversation.contextHint?.supplierLabel ?? '',
      conversation.contextHint?.phone ?? '',
      conversation.contextHint?.supplierPhone ?? '',
      conversation.contextHint?.jobNumber ?? '',
      conversation.contextHint?.jobStatus ?? '',
      conversation.contextHint?.purchaseInvoiceNumber ?? '',
      conversation.contextHint?.purchaseInvoiceStatus ?? '',
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
      case 'purchase_invoice':
        return 'Compra';
      case 'supplier':
        return 'Proveedor';
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

class _QuickSupplierChatEntry {
  final shared_supplier.Supplier supplier;
  final String phone;
  final Conversation? conversation;
  final List<PurchaseInvoice> invoices;

  const _QuickSupplierChatEntry({
    required this.supplier,
    required this.phone,
    required this.conversation,
    required this.invoices,
  });

  List<PurchaseInvoice> get activeInvoices => invoices
      .where(
        (invoice) => ConversationActivity.isActivePurchaseInvoiceStatus(
          invoice.status.name,
        ),
      )
      .toList();

  PurchaseInvoice? relevantInvoice(bool showOnlyActive) {
    final relevantInvoices = showOnlyActive ? activeInvoices : invoices;
    if (relevantInvoices.isEmpty) return null;
    return relevantInvoices.first;
  }

  DateTime? get lastActivityAt {
    final conversationDate =
        conversation?.lastMessageAt ?? conversation?.updatedAt;
    if (conversationDate != null) return conversationDate;
    if (invoices.isEmpty) return null;
    return invoices.first.date;
  }
}
