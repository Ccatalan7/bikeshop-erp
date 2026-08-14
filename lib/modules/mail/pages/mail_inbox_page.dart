import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/web_url.dart';
import '../../../shared/services/deep_link_handler.dart';
import '../models/mail_folder.dart';
import '../providers/email_provider.dart';
import '../providers/mail_account_manager.dart';
import '../widgets/email_list_item_unified.dart';
import '../widgets/email_detail_view_unified.dart';
import '../widgets/compose_email_dialog.dart';
import '../widgets/mail_error_diagnostic_banner.dart';

enum _InboxQuickFilter { all, unread, attachments }

class _MailSelectionIntent extends Intent {
  const _MailSelectionIntent(this.delta);

  final int delta;
}

/// Unified Mail Inbox Page - Shows merged emails from all connected providers
class MailInboxPage extends StatefulWidget {
  const MailInboxPage({
    super.key,
    this.initialProviderId,
    this.initialMessageId,
    this.initialOpenRequestId,
  });

  final String? initialProviderId;
  final String? initialMessageId;
  final String? initialOpenRequestId;

  @override
  State<MailInboxPage> createState() => _MailInboxPageState();
}

class _MailInboxPageState extends State<MailInboxPage> {
  static const double _estimatedEmailRowHeight = 92;
  static const double _inboxStatusRowHeight = 32;
  static const double _desktopSplitMinWidth = 1120;
  static const double _defaultListWidth = 540;
  static const double _minimumListWidth = 460;
  static const double _maximumListWidth = 640;
  static const String _listWidthPreferenceKey = 'mail_inbox_list_width_v1';

  late final MailAccountManager _manager;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'Mail inbox');
  final Map<String, GlobalKey> _emailRowKeys = {};
  Timer? _searchDebounceTimer;
  bool _isProcessingOAuthCallback = false;
  String _searchQuery = '';
  _InboxQuickFilter _quickFilter = _InboxQuickFilter.all;
  double _desktopListWidth = _defaultListWidth;
  String? _handledMessageDeepLink;
  int _messageOpenRequestEpoch = 0;

  @override
  void initState() {
    super.initState();
    // Use singleton - preserves state across navigation
    _manager = MailAccountManager.instance;
    _manager.addListener(_onManagerChange);
    _searchController.addListener(_onSearchChanged);
    _listScrollController.addListener(_onListScrolled);
    DeepLinkHandler.instance.addListener(_onDeepLinkChange);
    unawaited(_restoreListWidth());
    _initialize();
  }

  Future<void> _restoreListWidth() async {
    final preferences = await SharedPreferences.getInstance();
    final savedWidth = preferences.getDouble(_listWidthPreferenceKey);
    if (!mounted || savedWidth == null) return;
    setState(() {
      _desktopListWidth = savedWidth
          .clamp(
            _minimumListWidth,
            _maximumListWidth,
          )
          .toDouble();
    });
  }

  Future<void> _saveListWidth() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(
      _listWidthPreferenceKey,
      _desktopListWidth,
    );
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

    await _openRequestedMessage();

    // If we have cached emails, do a background refresh
    if (_manager.hasCachedEmails) {
      _manager.backgroundRefresh();
    }

    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MailInboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialProviderId == widget.initialProviderId &&
        oldWidget.initialMessageId == widget.initialMessageId &&
        oldWidget.initialOpenRequestId == widget.initialOpenRequestId) {
      return;
    }
    unawaited(_openRequestedMessage());
  }

  Future<void> _openRequestedMessage() async {
    final requestEpoch = ++_messageOpenRequestEpoch;
    final providerId = widget.initialProviderId?.trim();
    final messageId = widget.initialMessageId?.trim();
    if (providerId == null ||
        providerId.isEmpty ||
        messageId == null ||
        messageId.isEmpty) {
      return;
    }

    final deepLinkKey =
        '$providerId:$messageId:${widget.initialOpenRequestId ?? ''}';
    if (_handledMessageDeepLink == deepLinkKey) return;
    _handledMessageDeepLink = deepLinkKey;

    _searchDebounceTimer?.cancel();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    _manager.clearSearch();
    if (mounted && _quickFilter != _InboxQuickFilter.all) {
      setState(() => _quickFilter = _InboxQuickFilter.all);
    }

    final opened = await _manager.openEmailByIdentity(
      providerId: providerId,
      messageId: messageId,
      isRequestCurrent: () =>
          mounted && requestEpoch == _messageOpenRequestEpoch,
    );
    if (!mounted || requestEpoch != _messageOpenRequestEpoch || opened) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('No se pudo encontrar ese correo en la cuenta conectada.'),
      ),
    );
  }

  @override
  void dispose() {
    _messageOpenRequestEpoch++;
    _manager.removeListener(_onManagerChange);
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _listScrollController.removeListener(_onListScrolled);
    _searchController.dispose();
    _listScrollController.dispose();
    _keyboardFocusNode.dispose();
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
      bool replyAll = false,
      String? initialProviderId,
      Email? replySource}) {
    showDialog(
      context: context,
      builder: (context) => ComposeEmailDialog(
        manager: _manager,
        initialProviderId: initialProviderId ??
            _manager.selectedProvider?.providerId ??
            _manager.providerFilter,
        replyTo: replyTo,
        replySubject: replySubject,
        quotedContent: quotedContent,
        replyAll: replyAll,
        replySource: replySource,
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

    final replyRecipients = <String>[
      email.senderEmail,
      if (replyAll && (email.ccAddress?.trim().isNotEmpty ?? false))
        email.ccAddress!.trim(),
    ].where((address) => address.trim().isNotEmpty).join(', ');

    _showComposeDialog(
      replyTo: replyRecipients,
      replySubject: subject,
      quotedContent: quoted,
      replyAll: replyAll,
      initialProviderId: email.providerId,
      replySource: email,
    );
  }

  Future<void> _confirmDeleteSelectedEmail() async {
    final selected = _manager.selectedEmail;
    if (selected == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mover a papelera'),
        content: Text(
          selected.subject.trim().isEmpty
              ? 'Este correo se moverá a la papelera.'
              : '“${selected.subject}” se moverá a la papelera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Mover a papelera'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final success = await _manager.deleteSelectedEmail();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Correo movido a la papelera'
              : 'No se pudo mover el correo a la papelera',
        ),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// Restaurar, reportar spam y rescatar de spam no piden confirmación:
  /// las tres son reversibles con la acción contraria, y la papelera y spam
  /// del proveedor siguen existiendo como red. Sólo la papelera confirma,
  /// porque su vaciado automático (30 días) la vuelve eventualmente
  /// irreversible.
  Future<void> _runSelectedEmailAction({
    required Future<bool> Function() action,
    required String successMessage,
    required String failureMessage,
  }) async {
    final success = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? successMessage : failureMessage),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _restoreSelectedEmail() => _runSelectedEmailAction(
        action: _manager.restoreSelectedEmail,
        successMessage: 'Correo restaurado a la bandeja de entrada',
        failureMessage: 'No se pudo restaurar el correo',
      );

  Future<void> _markSelectedAsSpam() => _runSelectedEmailAction(
        action: _manager.markSelectedAsSpam,
        successMessage: 'Correo reportado como spam',
        failureMessage: 'No se pudo reportar el correo',
      );

  Future<void> _markSelectedAsNotSpam() => _runSelectedEmailAction(
        action: _manager.markSelectedAsNotSpam,
        successMessage: 'Correo devuelto a la bandeja de entrada',
        failureMessage: 'No se pudo rescatar el correo',
      );

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
    return _buildKeyboardScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= _desktopSplitMinWidth;

          if (isDesktop) {
            return _buildDesktopSplitView();
          } else {
            return _buildMobileView();
          }
        },
      ),
    );
  }

  Widget _buildKeyboardScope({required Widget child}) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MailSelectionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MailSelectionIntent(-1),
      },
      child: Actions(
        actions: {
          _MailSelectionIntent: CallbackAction<_MailSelectionIntent>(
            onInvoke: (intent) {
              _moveSelection(intent.delta);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          child: child,
        ),
      ),
    );
  }

  void _moveSelection(int delta) {
    if (_isEditableTextFocused) return;

    final emails = _visibleEmails;
    if (emails.isEmpty) return;

    final currentIndex = _selectedEmailIndex(emails);
    final nextIndex = currentIndex == -1
        ? (delta > 0 ? 0 : emails.length - 1)
        : (currentIndex + delta).clamp(0, emails.length - 1).toInt();
    if (nextIndex == currentIndex) return;

    final nextEmail = emails[nextIndex];
    _selectEmail(nextEmail);
    _scrollEmailIntoView(nextEmail, nextIndex, delta);
  }

  bool get _isEditableTextFocused {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  int _selectedEmailIndex(List<Email> emails) {
    final selected = _manager.selectedEmail;
    if (selected == null) return -1;
    return emails.indexWhere(
      (email) =>
          email.id == selected.id && email.providerId == selected.providerId,
    );
  }

  void _selectEmail(Email email) {
    _keyboardFocusNode.requestFocus();
    unawaited(_manager.selectEmail(email));
  }

  String _emailIdentity(Email email) => '${email.providerId}:${email.id}';

  GlobalKey _emailRowKey(Email email) {
    return _emailRowKeys.putIfAbsent(_emailIdentity(email), GlobalKey.new);
  }

  void _scrollEmailIntoView(Email email, int index, int delta) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScrollController.hasClients) return;

      final rowContext = _emailRowKeys[_emailIdentity(email)]?.currentContext;
      if (rowContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            rowContext,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignmentPolicy: delta < 0
                ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
                : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
        return;
      }

      final position = _listScrollController.position;
      final itemTop = index * _estimatedEmailRowHeight;
      final itemBottom = itemTop + _estimatedEmailRowHeight;
      final viewportTop = position.pixels;
      final viewportBottom = viewportTop + position.viewportDimension;

      double? target;
      if (itemTop < viewportTop) {
        target = itemTop;
      } else if (itemBottom > viewportBottom) {
        target = itemBottom - position.viewportDimension;
      }

      if (target == null) return;
      final clampedTarget = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _listScrollController.animateTo(
        clampedTarget.toDouble(),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildDesktopSplitView() {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableMaximum = math.max(
          _minimumListWidth,
          math.min(_maximumListWidth, constraints.maxWidth - 560),
        );
        final listWidth = _desktopListWidth
            .clamp(
              _minimumListWidth,
              availableMaximum,
            )
            .toDouble();

        return Row(
          children: [
            SizedBox(
              width: listWidth,
              child: Column(
                children: [
                  _buildListHeader(),
                  Expanded(child: _buildEmailList()),
                ],
              ),
            ),
            Semantics(
              label: 'Ajustar ancho de la lista de correos',
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _desktopListWidth = (_desktopListWidth + details.delta.dx)
                          .clamp(_minimumListWidth, availableMaximum)
                          .toDouble();
                    });
                  },
                  onHorizontalDragEnd: (_) => unawaited(_saveListWidth()),
                  child: SizedBox(
                    width: 9,
                    child: Center(
                      child: VerticalDivider(
                        width: 1,
                        color: theme.dividerColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _manager.selectedEmail != null
                  ? EmailDetailViewUnified(
                      email: _manager.selectedEmail!,
                      provider: _manager.selectedProvider,
                      isLoading: _manager.isLoadingSelectedEmail,
                      error: _manager.selectedEmailError,
                      onRetry: () =>
                          _manager.selectEmail(_manager.selectedEmail!),
                      onToggleRead: () => _manager.markAsRead(
                        _manager.selectedEmail!,
                        read: !_manager.selectedEmail!.isRead,
                      ),
                      onReply: () => _replyToEmail(false),
                      onReplyAll: () => _replyToEmail(true),
                      onDelete: _manager.activeFolder == MailFolder.trash
                          ? null
                          : _confirmDeleteSelectedEmail,
                      onRestore: _manager.activeFolder == MailFolder.trash
                          ? _restoreSelectedEmail
                          : null,
                      onMarkSpam: _manager.activeFolder == MailFolder.inbox
                          ? _markSelectedAsSpam
                          : null,
                      onMarkNotSpam: _manager.activeFolder == MailFolder.spam
                          ? _markSelectedAsNotSpam
                          : null,
                      onNavigateSelection: _moveSelection,
                    )
                  : _buildEmptyDetailView(),
            ),
          ],
        );
      },
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
        onDelete: _manager.activeFolder == MailFolder.trash
            ? null
            : _confirmDeleteSelectedEmail,
        onRestore: _manager.activeFolder == MailFolder.trash
            ? _restoreSelectedEmail
            : null,
        onMarkSpam: _manager.activeFolder == MailFolder.inbox
            ? _markSelectedAsSpam
            : null,
        onMarkNotSpam: _manager.activeFolder == MailFolder.spam
            ? _markSelectedAsNotSpam
            : null,
        onNavigateSelection: _moveSelection,
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
                        _manager.activeFolder == MailFolder.inbox
                            ? 'Bandeja Unificada'
                            : _manager.activeFolder.label,
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
              FilledButton.icon(
                onPressed: () => _showComposeDialog(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Redactar'),
              ),
              _buildHeaderIconButton(
                onPressed: _manager.isLoading
                    ? null
                    : () => _manager.refreshActiveFolder(),
                icon: _manager.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                tooltip: 'Actualizar',
              ),
              if (_availableProviders.isNotEmpty) _buildAddAccountMenu(),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildFolderSelectorControl(),
              _buildAccountFilterControl(),
              _buildQuickFilterChip(
                label: 'No leídos',
                icon: Icons.markunread_outlined,
                filter: _InboxQuickFilter.unread,
              ),
              _buildQuickFilterChip(
                label: 'Adjuntos',
                icon: Icons.attach_file,
                filter: _InboxQuickFilter.attachments,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _inboxStatusRowHeight,
            child: Row(
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
                    onPressed: _manager.isLoadingMore
                        ? null
                        : () => _manager.loadMore(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, _inboxStatusRowHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: _manager.isLoadingMore
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                              ),
                      ),
                    ),
                    label: const Text('Más'),
                  ),
              ],
            ),
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
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: const Icon(Icons.add),
        tooltip: 'Agregar cuenta',
        itemBuilder: (context) => _availableProviders
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

  List<({String id, String label})> get _availableProviders {
    final connectedProviderIds = _manager.connectedProviders
        .map((provider) => provider.providerId)
        .toSet();
    return <({String id, String label})>[
      (id: 'zoho', label: 'Zoho'),
      (id: 'gmail', label: 'Gmail'),
    ].where((provider) => !connectedProviderIds.contains(provider.id)).toList();
  }

  /// Mismo control ancla que el filtro de cuentas — un popup con chip de
  /// borde — para que la fila de filtros hable un solo idioma visual.
  Widget _buildFolderSelectorControl() {
    final theme = Theme.of(context);

    return PopupMenuButton<MailFolder>(
      tooltip: 'Cambiar de carpeta',
      onSelected: (folder) => unawaited(_manager.setActiveFolder(folder)),
      itemBuilder: (context) => [
        for (final folder in MailFolder.values)
          CheckedPopupMenuItem(
            value: folder,
            checked: _manager.activeFolder == folder,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(folder.icon, size: 16),
                const SizedBox(width: 8),
                Text(folder.label),
              ],
            ),
          ),
      ],
      child: Container(
        key: const ValueKey('mail-folder-selector'),
        height: 32,
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(7),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_manager.activeFolder.icon, size: 16),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                _manager.activeFolder.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountFilterControl() {
    final theme = Theme.of(context);
    final selectedId = _manager.providerFilter;
    final selectedProvider = selectedId == null
        ? null
        : _manager.connectedProviders
            .where((provider) => provider.providerId == selectedId)
            .firstOrNull;
    final label = selectedProvider?.displayName ?? 'Todas las cuentas';

    return PopupMenuButton<String>(
      tooltip: 'Filtrar por cuenta',
      onSelected: (value) {
        _manager.setProviderFilter(value == 'all' ? null : value);
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'all',
          checked: selectedId == null,
          child: const Text('Todas las cuentas'),
        ),
        ..._manager.connectedProviders.map(
          (provider) => CheckedPopupMenuItem(
            value: provider.providerId,
            checked: selectedId == provider.providerId,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _providerIcon(provider.providerId),
                const SizedBox(width: 8),
                Text(provider.displayName),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        height: 32,
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(7),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedProvider != null) ...[
              _providerIcon(selectedProvider.providerId),
              const SizedBox(width: 7),
            ] else ...[
              const Icon(Icons.all_inbox_outlined, size: 16),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
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
        final selectedEmail = _manager.selectedEmail;
        if (selectedEmail != null &&
            !_visibleEmails.any(
              (email) =>
                  email.id == selectedEmail.id &&
                  email.providerId == selectedEmail.providerId,
            )) {
          _manager.clearSelection();
        }
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

        return KeyedSubtree(
          key: _emailRowKey(email),
          child: EmailListItemUnified(
            email: email,
            isSelected: isSelected,
            showsRecipient: _manager.activeFolder.showsRecipientAsCounterpart,
            onTap: () => _selectEmail(email),
          ),
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
