import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/web_url.dart';
import '../../../shared/services/deep_link_handler.dart';
import '../providers/email_provider.dart';
import '../providers/mail_account_manager.dart';
import '../widgets/email_list_item_unified.dart';
import '../widgets/email_detail_view_unified.dart';
import '../widgets/compose_email_dialog.dart';
import '../widgets/mail_error_diagnostic_banner.dart';

enum _InboxQuickFilter { all, unread, attachments }

/// Unified Mail Inbox Page - Shows merged emails from all connected providers
class MailInboxPage extends StatefulWidget {
  const MailInboxPage({super.key});

  @override
  State<MailInboxPage> createState() => _MailInboxPageState();
}

class _MailInboxPageState extends State<MailInboxPage> {
  late final MailAccountManager _manager;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  Timer? _searchDebounceTimer;
  bool _isProcessingOAuthCallback = false;
  String _searchQuery = '';
  _InboxQuickFilter _quickFilter = _InboxQuickFilter.all;

  @override
  void initState() {
    super.initState();
    // Use singleton - preserves state across navigation
    _manager = MailAccountManager.instance;
    _manager.addListener(_onManagerChange);
    _searchController.addListener(_onSearchChanged);
    _listScrollController.addListener(_onListScrolled);
    DeepLinkHandler.instance.addListener(_onDeepLinkChange);
    _initialize();
  }

  void _onManagerChange() {
    if (mounted) setState(() {});
  }

  void _onDeepLinkChange() {
    if (!mounted || !_manager.isInitialized) return;
    if (!DeepLinkHandler.instance.hasPendingOAuthCallback) return;
    Future.microtask(_handleOAuthCallbacks);
  }

  void _onSearchChanged() {
    final value = _searchController.text.trim();
    if (value == _searchQuery) return;
    setState(() => _searchQuery = value);

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (value.isEmpty) {
        _manager.clearSearch();
      } else {
        _manager.searchInbox(value);
      }
    });
  }

  void _onListScrolled() {
    if (!_listScrollController.hasClients) return;
    if (_listScrollController.position.extentAfter > 520) return;
    if (!_manager.canLoadMore || _manager.isLoadingMore) return;
    _manager.loadMore();
  }

  Future<void> _initialize() async {
    // Initialize providers FIRST (so they exist for OAuth handling)
    await _manager.initialize();

    // THEN handle OAuth callbacks (providers must exist first!)
    await _handleOAuthCallbacks();

    // If we have cached emails, do a background refresh
    if (_manager.hasCachedEmails) {
      _manager.backgroundRefresh();
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChange);
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _listScrollController.removeListener(_onListScrolled);
    _searchController.dispose();
    _listScrollController.dispose();
    DeepLinkHandler.instance.removeListener(_onDeepLinkChange);
    // Don't call _manager.dispose() - it's a singleton
    super.dispose();
  }

  Future<void> _handleOAuthCallbacks() async {
    if (_isProcessingOAuthCallback) return;
    _isProcessingOAuthCallback = true;

    try {
      if (kIsWeb) {
        String? zohoCode = getAndClearZohoOAuthCode();
        zohoCode ??= Uri.base.queryParameters['zoho_code'];

        if (zohoCode != null) {
          await _processOAuthCode('zoho', zohoCode);
          _cleanUrl();
        }

        String? gmailCode = getAndClearGmailOAuthCode();
        gmailCode ??= Uri.base.queryParameters['gmail_code'];

        if (gmailCode != null) {
          await _processOAuthCode('gmail', gmailCode);
          _cleanUrl();
        }
      }

      final deepLinks = DeepLinkHandler.instance;
      final pendingProvider = deepLinks.pendingOAuthProvider;
      final pendingCode = deepLinks.pendingOAuthCode;
      if (pendingProvider != null && pendingCode != null) {
        deepLinks.clearPendingOAuth();
        await _processOAuthCode(pendingProvider, pendingCode);
      }
    } finally {
      _isProcessingOAuthCallback = false;
    }
  }

  Future<void> _processOAuthCode(String providerId, String code) async {
    await _exchangeOAuthCode(providerId, code);
  }

  Future<void> _exchangeOAuthCode(String providerId, String code) async {
    debugPrint('🔐 [Mail] Found $providerId auth code, exchanging...');
    final success = await _manager.exchangeCodeForTokens(
      providerId,
      code: code,
      redirectUri: _redirectUriForProvider(providerId),
    );

    if (!success) {
      final provider = _manager.getProvider(providerId);
      final message = provider?.error ??
          _manager.error ??
          'No se pudo conectar la cuenta de correo.';
      debugPrint('🔐 [Mail] $providerId token exchange failed: $message');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
      return;
    }

    debugPrint('🔐 [Mail] $providerId token exchange complete');
    if (mounted) {
      final providerName = providerId == 'gmail' ? 'Gmail' : 'Zoho';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$providerName conectado')),
      );
    }
  }

  String _redirectUriForProvider(String providerId) {
    return providerId == 'zoho'
        ? 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/zoho-oauth'
        : 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/gmail-oauth';
  }

  void _cleanUrl() {
    cleanMailUrl();
  }

  void _connectProvider(String providerId) async {
    try {
      debugPrint('🔐 [Mail] Starting OAuth flow for $providerId...');
      final redirectUri = _redirectUriForProvider(providerId);

      // On mobile, pass state=mobile so edge function redirects to deep link
      const state = kIsWeb ? null : 'mobile';
      final authUrl = await _manager.getAuthorizationUrl(
        providerId,
        redirectUri: redirectUri,
        state: state,
      );

      if (kIsWeb) {
        // Web: direct navigation
        debugPrint('🔐 [Mail] Redirecting browser for $providerId OAuth');
        navigateToUrl(authUrl);
      } else {
        // Mobile: open in external browser, deep link will bring user back
        final uri = Uri.parse(authUrl);
        if (await canLaunchUrl(uri)) {
          debugPrint('🔐 [Mail] Opening browser for $providerId OAuth');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo abrir el navegador'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('🔐 [Mail] Could not start $providerId OAuth: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo iniciar la conexión con $providerId.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showComposeDialog(
      {String? replyTo,
      String? replySubject,
      String? quotedContent,
      bool replyAll = false}) {
    showDialog(
      context: context,
      builder: (context) => ComposeEmailDialog(
        manager: _manager,
        replyTo: replyTo,
        replySubject: replySubject,
        quotedContent: quotedContent,
        replyAll: replyAll,
      ),
    );
  }

  void _replyToEmail(bool replyAll) {
    final email = _manager.selectedEmail;
    if (email == null) return;

    String subject = email.subject;
    if (!subject.toLowerCase().startsWith('re:')) {
      subject = 'Re: $subject';
    }

    final quoted = '''
<br><br>
<div style="margin-left: 12px; padding-left: 12px; border-left: 2px solid #ccc; color: #666;">
<p><strong>El ${_formatDate(email.receivedTime)}, ${email.senderName} escribió:</strong></p>
${email.content ?? email.summary ?? ''}
</div>
''';

    _showComposeDialog(
      replyTo: replyAll
          ? '${email.senderEmail}, ${email.ccAddress ?? ''}'
          : email.senderEmail,
      replySubject: subject,
      quotedContent: quoted,
      replyAll: replyAll,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: !_manager.isInitialized && !_manager.hasCachedEmails
          ? const Center(child: CircularProgressIndicator())
          : _manager.connectedProviders.isEmpty
              ? _buildConnectView()
              : _buildInboxView(),
    );
  }

  Widget _buildConnectView() {
    final theme = Theme.of(context);

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                'Conectar Correo',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Conecta tus cuentas de correo para ver todos\ntus mensajes en un solo lugar.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              _buildConnectButton('zoho', 'Zoho Mail'),
              const SizedBox(height: 16),
              _buildConnectButton('gmail', 'Gmail'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInboxView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
          return _buildDesktopSplitView();
        } else {
          return _buildMobileView();
        }
      },
    );
  }

  Widget _buildDesktopSplitView() {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 420,
          child: Column(
            children: [
              _buildListHeader(),
              Expanded(child: _buildEmailList()),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: theme.dividerColor),
        Expanded(
          child: _manager.selectedEmail != null
              ? EmailDetailViewUnified(
                  email: _manager.selectedEmail!,
                  provider: _manager.selectedProvider,
                  isLoading: _manager.isLoadingSelectedEmail,
                  error: _manager.selectedEmailError,
                  onRetry: () => _manager.selectEmail(_manager.selectedEmail!),
                  onToggleRead: () => _manager.markAsRead(
                    _manager.selectedEmail!,
                    read: !_manager.selectedEmail!.isRead,
                  ),
                  onReply: () => _replyToEmail(false),
                  onReplyAll: () => _replyToEmail(true),
                  onDelete: () async {
                    await _manager.deleteSelectedEmail();
                  },
                )
              : _buildEmptyDetailView(),
        ),
      ],
    );
  }

  Widget _buildMobileView() {
    if (_manager.selectedEmail != null) {
      return EmailDetailViewUnified(
        email: _manager.selectedEmail!,
        provider: _manager.selectedProvider,
        isLoading: _manager.isLoadingSelectedEmail,
        error: _manager.selectedEmailError,
        onClose: () => _manager.clearSelection(),
        onRetry: () => _manager.selectEmail(_manager.selectedEmail!),
        onToggleRead: () => _manager.markAsRead(
          _manager.selectedEmail!,
          read: !_manager.selectedEmail!.isRead,
        ),
        onReply: () => _replyToEmail(false),
        onReplyAll: () => _replyToEmail(true),
        onDelete: () async {
          await _manager.deleteSelectedEmail();
        },
      );
    }

    return Column(
      children: [
        _buildListHeader(),
        Expanded(child: _buildEmailList()),
      ],
    );
  }

  Widget _buildListHeader() {
    final theme = Theme.of(context);
    final connectedProviders = _manager.connectedProviders;
    final visibleCount = _visibleEmails.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Bandeja Unificada',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_manager.lastFetch != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '• ${_formatTime(_manager.lastFetch!)}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildHeaderIconButton(
                onPressed: () => _showComposeDialog(),
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Redactar',
              ),
              _buildHeaderIconButton(
                onPressed:
                    _manager.isLoading ? null : () => _manager.refreshInbox(),
                icon: _manager.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                tooltip: 'Actualizar',
              ),
              _buildAddAccountMenu(),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar correo',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Limpiar búsqueda',
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildProviderChip(
                  label: 'Todos',
                  selected: _manager.providerFilter == null,
                  onSelected: () => _manager.setProviderFilter(null),
                ),
                const SizedBox(width: 8),
                ...connectedProviders.map((provider) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildProviderChip(
                        label: provider.displayName,
                        icon: _providerIcon(provider.providerId),
                        selected:
                            _manager.providerFilter == provider.providerId,
                        onSelected: () => _manager.setProviderFilter(
                          _manager.providerFilter == provider.providerId
                              ? null
                              : provider.providerId,
                        ),
                      ),
                    )),
                const SizedBox(width: 8),
                _buildQuickFilterChip(
                  label: 'No leídos',
                  icon: Icons.markunread_outlined,
                  filter: _InboxQuickFilter.unread,
                ),
                const SizedBox(width: 8),
                _buildQuickFilterChip(
                  label: 'Adjuntos',
                  icon: Icons.attach_file,
                  filter: _InboxQuickFilter.attachments,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _manager.isSearchActive
                      ? (_manager.isSearching
                          ? 'Buscando...'
                          : '$visibleCount resultados')
                      : '$visibleCount visibles de ${_manager.loadedCount} cargados',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!_manager.isSearchActive && _manager.canLoadMore)
                TextButton.icon(
                  onPressed:
                      _manager.isLoadingMore ? null : () => _manager.loadMore(),
                  icon: _manager.isLoadingMore
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.keyboard_arrow_down, size: 18),
                  label: const Text('Más'),
                ),
            ],
          ),
          if (_manager.error != null) ...[
            const SizedBox(height: 6),
            _buildMailErrorBanner(_manager.error!),
          ],
        ],
      ),
    );
  }

  Widget _buildMailErrorBanner(String message) {
    final diagnostic = MailErrorDiagnostic.fromMessage(message);
    final providerId = _providerIdFromError(message);
    final canReconnect = providerId != null &&
        (diagnostic.kind == MailErrorKind.token ||
            diagnostic.kind == MailErrorKind.permissions);

    return MailErrorDiagnosticBanner(
      message: message,
      actionLabel: canReconnect
          ? 'Reconectar ${_providerDisplayName(providerId)}'
          : null,
      actionIcon: Icons.sync_outlined,
      onAction: canReconnect ? () => _connectProvider(providerId) : null,
    );
  }

  Widget _buildHeaderIconButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }

  Widget _buildAddAccountMenu() {
    final connectedProviderIds = _manager.connectedProviders
        .map((provider) => provider.providerId)
        .toSet();
    final availableProviders = <({String id, String label})>[
      (id: 'zoho', label: 'Zoho'),
      (id: 'gmail', label: 'Gmail'),
    ].where((provider) => !connectedProviderIds.contains(provider.id)).toList();

    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: const Icon(Icons.add),
        tooltip: 'Agregar cuenta',
        itemBuilder: (context) => availableProviders.isEmpty
            ? [
                const PopupMenuItem(
                  enabled: false,
                  child: Text('No hay cuentas nuevas'),
                ),
              ]
            : availableProviders
                .map(
                  (provider) => PopupMenuItem(
                    value: provider.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _providerIcon(provider.id),
                        const SizedBox(width: 10),
                        Text('Conectar ${provider.label}'),
                      ],
                    ),
                  ),
                )
                .toList(),
        onSelected: _connectProvider,
      ),
    );
  }

  Widget _buildProviderChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    Widget? icon,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon,
            const SizedBox(width: 5),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }

  Widget _buildQuickFilterChip({
    required String label,
    required IconData icon,
    required _InboxQuickFilter filter,
  }) {
    final selected = _quickFilter == filter;
    return FilterChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _quickFilter = selected ? _InboxQuickFilter.all : filter;
        });
      },
    );
  }

  List<Email> get _visibleEmails {
    final query = _searchQuery.toLowerCase();
    return _manager.emails.where((email) {
      if (_quickFilter == _InboxQuickFilter.unread && email.isRead) {
        return false;
      }
      if (_quickFilter == _InboxQuickFilter.attachments &&
          !email.hasAttachment) {
        return false;
      }
      if (_manager.isSearchActive) return true;
      if (query.isEmpty) return true;

      final searchable = [
        email.subject,
        email.senderName,
        email.senderEmail,
        email.fromAddress,
        email.toAddress,
        email.summary ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _providerIcon(String providerId) {
    switch (providerId) {
      case 'gmail':
        return Image.asset('assets/icons/gmail_logo.webp',
            width: 16, height: 16);
      case 'zoho':
        return Image.asset('assets/icons/zoho_logo.png', width: 16, height: 16);
      default:
        return const Icon(Icons.email_outlined, size: 16);
    }
  }

  String? _providerIdFromError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('gmail')) return 'gmail';
    if (lower.contains('zoho')) return 'zoho';
    return null;
  }

  String _providerDisplayName(String providerId) {
    return providerId == 'gmail' ? 'Gmail' : 'Zoho';
  }

  Widget _buildEmailList() {
    final emails = _visibleEmails;
    final showLoadMoreFooter =
        !_manager.isSearchActive && _manager.canLoadMore && emails.isNotEmpty;

    if (_manager.isLoading && _manager.emails.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_manager.isSearching && emails.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_manager.emails.isEmpty) {
      return Center(
        child: Text(
          'No hay correos',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    if (emails.isEmpty) {
      return Center(
        child: Text(
          _manager.isSearchActive
              ? 'No se encontraron correos'
              : 'No hay correos para estos filtros',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ListView.builder(
      controller: _listScrollController,
      itemCount: emails.length + (showLoadMoreFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == emails.length) return _buildLoadMoreFooter();

        final email = emails[index];
        final isSelected = _manager.selectedEmail?.id == email.id &&
            _manager.selectedEmail?.providerId == email.providerId;

        return EmailListItemUnified(
          email: email,
          isSelected: isSelected,
          onTap: () => _manager.selectEmail(email),
        );
      },
    );
  }

  Widget _buildLoadMoreFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: OutlinedButton.icon(
        onPressed: _manager.isLoadingMore ? null : () => _manager.loadMore(),
        icon: _manager.isLoadingMore
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(_manager.isLoadingMore ? 'Cargando...' : 'Cargar más'),
      ),
    );
  }

  Widget _buildEmptyDetailView() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline,
              size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Selecciona un correo para leerlo',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton(String providerId, String label) {
    return SizedBox(
      width: 240,
      child: OutlinedButton(
        onPressed: () => _connectProvider(providerId),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _providerIcon(providerId),
            const SizedBox(width: 12),
            Text('Conectar $label'),
          ],
        ),
      ),
    );
  }
}
