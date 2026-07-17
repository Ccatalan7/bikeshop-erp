import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/utils/conversation_activity.dart';
import '../../modules/messaging/widgets/chat_window.dart';
import '../../modules/purchases/models/purchase_invoice.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../models/supplier.dart' as shared_supplier;
import '../services/right_toolbar_service.dart';

enum _SupplierMessageFilter { all, unread, whatsapp }

class QuickSupplierMessagesPanel extends StatefulWidget {
  const QuickSupplierMessagesPanel({super.key});

  @override
  State<QuickSupplierMessagesPanel> createState() =>
      _QuickSupplierMessagesPanelState();
}

class _QuickSupplierMessagesPanelState
    extends State<QuickSupplierMessagesPanel> {
  final TextEditingController _searchController = TextEditingController();

  _SupplierMessageFilter _filter = _SupplierMessageFilter.all;
  String _searchTerm = '';
  String? _selectedConversationId;
  String? _panelActiveConversationId;
  String? _openingSupplierId;
  ChatProvider? _chatProvider;
  List<shared_supplier.Supplier> _suppliers = [];
  List<PurchaseInvoice> _purchaseInvoices = [];
  bool _isRefreshing = false;
  bool _isLoadingSuppliers = false;
  bool _showOnlyActiveChats = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    ConversationActivity.showOnlyActiveChats.addListener(
      _handleActiveModeChanged,
    );
    unawaited(_loadPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.read<ChatProvider>().refreshConversationContextHints(),
      );
      unawaited(_loadSupplierData());
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
        conversationId: panelActiveConversationId,
        notify: false,
      );
    }
    _searchController.removeListener(_handleSearchChanged);
    ConversationActivity.showOnlyActiveChats.removeListener(
      _handleActiveModeChanged,
    );
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

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final showOnlyActive =
        prefs.getBool(ConversationActivity.activeOnlyPreferenceKey) ?? true;
    if (!mounted) return;
    if (ConversationActivity.showOnlyActiveChats.value != showOnlyActive) {
      ConversationActivity.showOnlyActiveChats.value = showOnlyActive;
    }
    setState(() {
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

  Future<void> _loadSupplierData() async {
    if (_isLoadingSuppliers) return;
    setState(() => _isLoadingSuppliers = true);
    try {
      final purchaseService = context.read<PurchaseService>();
      final suppliers = await purchaseService.getSuppliers(activeOnly: true);
      final invoices = await purchaseService.getPurchaseInvoicesForList();

      if (!mounted) return;
      setState(() {
        _suppliers = suppliers
            .where((supplier) => _supplierChatPhone(supplier) != null)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _purchaseInvoices = invoices;
        _isLoadingSuppliers = false;
      });
    } catch (error) {
      debugPrint('Error loading supplier chats in quick panel: $error');
      if (mounted) {
        setState(() => _isLoadingSuppliers = false);
      }
    }
  }

  bool _hasWhatsAppPhone(String? phone) {
    return _normalizedPhone(phone).length >= 8;
  }

  String _normalizedPhone(String? phone) {
    return phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    final provider = context.read<ChatProvider>();
    await provider.loadConversations(refreshContextHints: false);
    await provider.refreshConversationContextHints();
    await _loadSupplierData();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
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

  Conversation? _selectedConversation(List<Conversation> conversations) {
    final selectedId = _selectedConversationId;
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
        Expanded(child: _buildSupplierList(provider)),
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
                tooltip: 'Volver a proveedores',
                onPressed: () => _returnToInbox(conversation.id),
              ),
              const Expanded(
                child: Text(
                  'Chats proveedores',
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Proveedores',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
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
          hintText: 'Buscar proveedores, compras o WhatsApp...',
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
          ? 'Solo activos: muestra proveedores con compras abiertas o chats activos.'
          : 'Historial completo: muestra también proveedores y documentos cerrados.',
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
    final entries = _filteredSupplierEntries(provider);
    final includeInactive = _searchTerm.isNotEmpty ? true : null;
    final allEntries = _supplierEntries(
      provider,
      includeInactive: includeInactive,
    );
    final allCount = allEntries.length;
    final unreadCount = allEntries
        .where((entry) => (entry.conversation?.unreadCount ?? 0) > 0)
        .length;
    final whatsappCount =
        allEntries.where((entry) => _hasWhatsAppPhone(entry.phone)).length;

    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(_SupplierMessageFilter.all, 'Todos', allCount),
          _buildFilterChip(
            _SupplierMessageFilter.unread,
            'Sin leer',
            unreadCount,
          ),
          _buildFilterChip(
            _SupplierMessageFilter.whatsapp,
            'WhatsApp',
            whatsappCount,
          ),
          if (_searchTerm.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Center(
                child: Text(
                  '${entries.length} resultados',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    _SupplierMessageFilter filter,
    String label,
    int count,
  ) {
    final theme = Theme.of(context);
    final selected = _filter == filter;
    final colorScheme = theme.colorScheme;
    final accentColor = switch (filter) {
      _SupplierMessageFilter.unread => const Color(0xFF16A34A),
      _SupplierMessageFilter.whatsapp => const Color(0xFF047857),
      _SupplierMessageFilter.all => const Color(0xFF7C3AED),
    };
    final hasSignal = filter == _SupplierMessageFilter.unread && count > 0;

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

  Widget _buildSupplierList(ChatProvider provider) {
    final entries = _filteredSupplierEntries(provider);

    if (entries.isEmpty && !_isLoadingSuppliers) {
      return _buildEmptyState(
        isTotallyEmpty: _supplierEntries(provider).isEmpty,
        activeModeEmpty: _showOnlyActiveChats &&
            _supplierEntries(provider, includeInactive: true).isNotEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (_isLoadingSuppliers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          for (final entry in entries) ...[
            _buildSupplierResult(entry),
            const Divider(height: 1),
          ],
        ],
      ),
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    child: Text(
                      _supplierInitials(entry.supplier.name),
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if ((conversation?.unreadCount ?? 0) > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 17, minHeight: 17),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${conversation!.unreadCount > 99 ? '99+' : conversation.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
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
                  Icons.chevron_right,
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

  List<_QuickSupplierChatEntry> _filteredSupplierEntries(
    ChatProvider provider,
  ) {
    return _supplierEntries(
      provider,
      includeInactive: _searchTerm.isNotEmpty ? true : null,
    ).where(_matchesFilter).where(_matchesSearch).toList()
      ..sort(_compareSupplierEntries);
  }

  List<_QuickSupplierChatEntry> _supplierEntries(
    ChatProvider provider, {
    bool? includeInactive,
  }) {
    final supplierConversations = provider.conversations
        .where((conversation) => conversation.isSupplierConversation)
        .toList();
    return _quickSupplierEntries(
      supplierConversations,
      includeInactive: includeInactive ?? !_showOnlyActiveChats,
    );
  }

  List<_QuickSupplierChatEntry> _quickSupplierEntries(
    List<Conversation> supplierConversations, {
    required bool includeInactive,
  }) {
    final entries = <_QuickSupplierChatEntry>[];
    final usedConversationIds = <String>{};

    for (final supplier in _suppliers) {
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
    final invoices = _purchaseInvoices
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

  bool _matchesFilter(_QuickSupplierChatEntry entry) {
    return switch (_filter) {
      _SupplierMessageFilter.all => true,
      _SupplierMessageFilter.unread =>
        (entry.conversation?.unreadCount ?? 0) > 0,
      _SupplierMessageFilter.whatsapp => _hasWhatsAppPhone(entry.phone),
    };
  }

  bool _matchesSearch(_QuickSupplierChatEntry entry) {
    if (_searchTerm.isEmpty) return true;
    final searchDigits = _normalizedPhone(_searchTerm);
    final haystack = _normalizeSearchText([
      entry.supplier.name,
      entry.phone,
      entry.conversation?.lastMessageContent ?? '',
      for (final invoice in entry.invoices)
        '${invoice.invoiceNumber} ${invoice.supplierInvoiceNumber ?? ''} ${invoice.status.displayName}',
    ].join(' '));
    final phone = _normalizedPhone(entry.phone);

    return haystack.contains(_searchTerm) ||
        (searchDigits.isNotEmpty && phone.contains(searchDigits));
  }

  int _compareSupplierEntries(
    _QuickSupplierChatEntry a,
    _QuickSupplierChatEntry b,
  ) {
    final unreadCompare = (b.conversation?.unreadCount ?? 0)
        .compareTo(a.conversation?.unreadCount ?? 0);
    if (unreadCompare != 0) return unreadCompare;

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

  Widget _buildEmptyState({
    required bool isTotallyEmpty,
    bool activeModeEmpty = false,
  }) {
    final theme = Theme.of(context);
    final title = activeModeEmpty
        ? 'Sin proveedores activos'
        : isTotallyEmpty
            ? 'Sin proveedores con WhatsApp'
            : 'No hay proveedores para este filtro';
    final subtitle = activeModeEmpty
        ? 'Desactiva "Solo activos" para ver el historial completo.'
        : isTotallyEmpty
            ? 'Los proveedores con teléfono aparecerán aquí para iniciar o retomar chats.'
            : 'Prueba con otro filtro o limpia la búsqueda.';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.storefront_outlined,
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
