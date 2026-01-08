import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/web_url.dart';
import '../providers/mail_account_manager.dart';
import '../widgets/email_list_item_unified.dart';
import '../widgets/email_detail_view_unified.dart';
import '../widgets/compose_email_dialog.dart';

/// Unified Mail Inbox Page - Shows merged emails from all connected providers
class MailInboxPage extends StatefulWidget {
  const MailInboxPage({super.key});

  @override
  State<MailInboxPage> createState() => _MailInboxPageState();
}

class _MailInboxPageState extends State<MailInboxPage> {
  late final MailAccountManager _manager;

  @override
  void initState() {
    super.initState();
    // Use singleton - preserves state across navigation
    _manager = MailAccountManager.instance;
    _manager.addListener(_onManagerChange);
    _initialize();
  }

  void _onManagerChange() {
    if (mounted) setState(() {});
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
    // Don't call _manager.dispose() - it's a singleton
    super.dispose();
  }

  Future<void> _handleOAuthCallbacks() async {
    if (!kIsWeb) return;

    // Check for Zoho callback
    String? zohoCode = getAndClearZohoOAuthCode();
    zohoCode ??= Uri.base.queryParameters['zoho_code'];

    if (zohoCode != null) {
      debugPrint('🔐 [Mail] Found Zoho auth code, exchanging...');
      await _manager.exchangeCodeForTokens(
        'zoho',
        code: zohoCode,
        redirectUri:
            'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/zoho-oauth',
      );
      _cleanUrl();
      debugPrint('🔐 [Mail] Zoho token exchange complete');
    }

    // Check for Gmail callback
    String? gmailCode = getAndClearGmailOAuthCode();
    gmailCode ??= Uri.base.queryParameters['gmail_code'];

    if (gmailCode != null) {
      debugPrint('🔐 [Mail] Found Gmail auth code, exchanging...');
      await _manager.exchangeCodeForTokens(
        'gmail',
        code: gmailCode,
        redirectUri:
            'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/gmail-oauth',
      );
      _cleanUrl();
      debugPrint('🔐 [Mail] Gmail token exchange complete');
    }
  }

  void _cleanUrl() {
    if (kIsWeb && html.window.location.href.contains('_code')) {
      html.window.history.replaceState(null, '', '/#/mail');
    }
  }

  void _connectProvider(String providerId) {
    final redirectUri = providerId == 'zoho'
        ? 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/zoho-oauth'
        : 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/gmail-oauth';

    final authUrl =
        _manager.getAuthorizationUrl(providerId, redirectUri: redirectUri);
    html.window.location.href = authUrl;
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
          width: 380,
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
                  isLoading: _manager.isLoading,
                  error: _manager.error,
                  onRetry: () => _manager.selectEmail(_manager.selectedEmail!),
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
        isLoading: _manager.isLoading,
        error: _manager.error,
        onClose: () => _manager.clearSelection(),
        onRetry: () => _manager.selectEmail(_manager.selectedEmail!),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Bandeja Unificada',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_manager.lastFetch != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '• ${_formatTime(_manager.lastFetch!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const Spacer(),
              // Compose button
              IconButton(
                onPressed: () => _showComposeDialog(),
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Redactar',
              ),
              IconButton(
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Agregar cuenta',
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'zoho', child: Text('Conectar Zoho')),
                  const PopupMenuItem(
                      value: 'gmail', child: Text('Conectar Gmail')),
                ],
                onSelected: _connectProvider,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Provider filter chips
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Todos'),
                selected: _manager.providerFilter == null,
                onSelected: (_) => _manager.setProviderFilter(null),
              ),
              ...connectedProviders.map((p) => FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _providerIcon(p.providerId),
                        const SizedBox(width: 4),
                        Text(p.displayName),
                      ],
                    ),
                    selected: _manager.providerFilter == p.providerId,
                    onSelected: (_) => _manager.setProviderFilter(
                      _manager.providerFilter == p.providerId
                          ? null
                          : p.providerId,
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildEmailList() {
    if (_manager.isLoading && _manager.emails.isEmpty) {
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

    return ListView.builder(
      itemCount: _manager.emails.length,
      itemBuilder: (context, index) {
        final email = _manager.emails[index];
        final isSelected = _manager.selectedEmail?.id == email.id;

        return EmailListItemUnified(
          email: email,
          isSelected: isSelected,
          onTap: () => _manager.selectEmail(email),
        );
      },
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
