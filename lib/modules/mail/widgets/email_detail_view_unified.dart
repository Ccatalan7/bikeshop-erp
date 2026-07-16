import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../shared/services/spreadsheet_file_handoff_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/services/window_zoom_service.dart';
import '../../../shared/utils/file_download.dart';
import '../../spreadsheets/services/spreadsheet_service.dart';
import '../../storage/models/app_stored_file.dart';
import '../../storage/services/app_file_storage_service.dart';
import '../providers/email_provider.dart';
import 'mail_error_diagnostic_banner.dart';

const int _emailBodyRendererVersion = 8;
const String _emailReaderBaseUrl = 'https://mail.vinabike.local/';
const bool _emailReaderDiagnosticsEnabled = false;

const String _emailLinkBridgeJavaScript = r'''
(function() {
  if (window.__vinabikeEmailLinkBridgeInstalled) return;
  window.__vinabikeEmailLinkBridgeInstalled = true;

  var lastSentUrl = '';
  var lastSentAt = 0;
  var lastAnchorLogCount = -1;

  function safeText(value, maxLength) {
    value = value == null ? '' : String(value);
    value = value.replace(/\s+/g, ' ').trim();
    if (value.length > maxLength) return value.slice(0, maxLength) + '...';
    return value;
  }

  function nodeLabel(node) {
    if (!node) return 'null';
    var tag = node.tagName ? String(node.tagName).toLowerCase() : String(node.nodeName || 'node');
    var id = node.id ? ('#' + node.id) : '';
    var cls = node.className && typeof node.className === 'string'
      ? ('.' + safeText(node.className, 60).replace(/\s+/g, '.'))
      : '';
    return tag + id + cls;
  }

  function debug(event, details) {
    try {
      var payload = JSON.stringify({
        event: event,
        details: details || {},
        href: window.location.href,
        base: document.baseURI,
        ready: document.readyState
      });
      try {
        if (window.EmailDebugBridge && EmailDebugBridge.postMessage) {
          EmailDebugBridge.postMessage(payload);
        }
      } catch (channelError) {}
      if (window.console && console.info) {
        console.info('[VinabikeMailReader] ' + payload);
      }
    } catch (error) {}
  }

  debug('bridge-installed', {
    title: safeText(document.title, 80),
    bodyLength: document.body && document.body.innerText ? document.body.innerText.length : 0
  });

  function sendToFlutter(url) {
    if (!url) {
      debug('send-ignored-empty', {});
      return;
    }
    url = String(url);
    if (!url || /^javascript:/i.test(url)) {
      debug('send-ignored-javascript', { url: safeText(url, 220) });
      return;
    }

    var now = Date.now ? Date.now() : new Date().getTime();
    if (url === lastSentUrl && now - lastSentAt < 900) {
      debug('send-deduped', { url: safeText(url, 220) });
      return;
    }
    lastSentUrl = url;
    lastSentAt = now;

    try {
      if (window.EmailLinkBridge && EmailLinkBridge.postMessage) {
        debug('send-post-message', { url: safeText(url, 220) });
        EmailLinkBridge.postMessage(url);
        return;
      }
    } catch (error) {
      debug('send-post-message-error', { error: safeText(error, 160) });
    }
    debug('send-location-fallback', { url: safeText(url, 220) });
    window.location.href = url;
  }

  function closestLinkedElement(target) {
    var node = target;
    while (node && node !== document) {
      if (node.getAttribute) {
        var nativeHref = node.getAttribute('href') ||
          node.getAttribute('xlink:href');
        if (nativeHref) {
          return { node: node, href: nativeHref, nativeLink: true };
        }

        var href = node.getAttribute('data-href') ||
          node.getAttribute('data-url') ||
          node.getAttribute('data-link');
        if (href) return { node: node, href: href, nativeLink: false };
      }
      node = node.parentElement || node.parentNode;
    }
    return null;
  }

  function absoluteUrl(url) {
    try {
      return new URL(url, document.baseURI || 'https://mail.vinabike.local/').href;
    } catch (error) {
      return url;
    }
  }

  function eventPoint(event) {
    if (event.clientX != null && event.clientY != null) {
      return { x: event.clientX, y: event.clientY };
    }
    var touch = event.changedTouches && event.changedTouches.length
      ? event.changedTouches[0]
      : null;
    if (touch && touch.clientX != null && touch.clientY != null) {
      return { x: touch.clientX, y: touch.clientY };
    }
    return null;
  }

  function gapToRect(point, rect) {
    var dx = 0;
    if (point.x < rect.left) dx = rect.left - point.x;
    else if (point.x > rect.right) dx = point.x - rect.right;

    var dy = 0;
    if (point.y < rect.top) dy = rect.top - point.y;
    else if (point.y > rect.bottom) dy = point.y - rect.bottom;

    return {
      dx: Math.round(dx * 10) / 10,
      dy: Math.round(dy * 10) / 10,
      distance: Math.round(Math.sqrt(dx * dx + dy * dy) * 10) / 10
    };
  }

  function anchorRectCandidates(point, limit, maxDistance) {
    if (!point) return [];
    var anchors = document.querySelectorAll('a[href], area[href]');
    var matches = [];

    anchors.forEach(function(anchor) {
      var rects = anchor.getClientRects ? anchor.getClientRects() : [];
      if (!rects || !rects.length) {
        rects = [anchor.getBoundingClientRect()];
      }

      for (var i = 0; i < rects.length; i++) {
        var rect = rects[i];
        if (!rect || rect.width < 1 || rect.height < 1) continue;
        var gap = gapToRect(point, rect);
        if (maxDistance != null && gap.distance > maxDistance) continue;
        matches.push({
          node: anchor,
          href: anchor.href || anchor.getAttribute('href'),
          text: safeText(anchor.innerText, 90),
          distance: gap.distance,
          dx: gap.dx,
          dy: gap.dy,
          rect: {
            left: Math.round(rect.left),
            top: Math.round(rect.top),
            right: Math.round(rect.right),
            bottom: Math.round(rect.bottom),
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          }
        });
      }
    });

    matches.sort(function(a, b) {
      return a.distance - b.distance;
    });
    return matches.slice(0, limit || 3);
  }

  function normalizeAnchor(node) {
    if (!node || !node.setAttribute || !node.tagName) return;
    var tag = String(node.tagName).toUpperCase();
    if (tag !== 'A' && tag !== 'AREA') return;
    node.setAttribute('target', '_self');
    node.setAttribute('rel', 'noopener noreferrer');
  }

  function linkedElementFromEvent(event) {
    var linked = closestLinkedElement(event.target);
    if (linked) return linked;

    var point = eventPoint(event);
    if (document.elementsFromPoint && point) {
      var elements = document.elementsFromPoint(point.x, point.y);
      for (var i = 0; i < elements.length; i++) {
        linked = closestLinkedElement(elements[i]);
        if (linked) return linked;
      }
    }
    return null;
  }

  function handlePointer(event) {
    var linked = linkedElementFromEvent(event);
    if (!linked) {
      var point = eventPoint(event);
      debug('pointer-no-link', {
        type: event.type,
        x: point && point.x,
        y: point && point.y,
        target: nodeLabel(event.target),
        text: safeText(event.target && event.target.innerText, 90),
        nearbyAnchors: anchorRectCandidates(point, 4, 140)
      });
      return;
    }

    var url = linked.node.href || absoluteUrl(linked.href);
    if (!url) {
      debug('pointer-link-no-url', {
        type: event.type,
        target: nodeLabel(linked.node),
        rawHref: safeText(linked.href, 220)
      });
      return;
    }

    if (linked.nativeLink) {
      normalizeAnchor(linked.node);
      event.preventDefault();
      event.stopPropagation();
      debug('pointer-native-link-bridged', {
        type: event.type,
        target: nodeLabel(linked.node),
        url: safeText(url, 220),
        text: safeText(linked.node && linked.node.innerText, 90)
      });
      sendToFlutter(url);
      return false;
    }

    event.preventDefault();
    event.stopPropagation();
    debug('pointer-data-link-bridged', {
      type: event.type,
      target: nodeLabel(linked.node),
      url: safeText(url, 220),
      text: safeText(linked.node && linked.node.innerText, 90)
    });
    sendToFlutter(url);
    return false;
  }

  ['click', 'auxclick', 'mouseup', 'touchend'].forEach(function(eventName) {
    document.addEventListener(eventName, handlePointer, true);
  });

  document.addEventListener('submit', function(event) {
    var form = event.target;
    if (!form || !form.action) return;
    event.preventDefault();
    event.stopPropagation();
    debug('form-submit-bridged', { action: safeText(form.action, 220) });
    sendToFlutter(form.action);
    return false;
  }, true);

  var nativeOpen = window.open;
  window.open = function(url) {
    if (url) {
      debug('window-open-bridged', { url: safeText(url, 220) });
      sendToFlutter(url);
      return null;
    }
    return nativeOpen ? nativeOpen.apply(window, arguments) : null;
  };

  function normalizeAllAnchors() {
    var anchors = document.querySelectorAll('a[href], area[href]');
    var promotedButtons = 0;
    document.querySelectorAll('a[target], area[target]').forEach(function(anchor) {
      normalizeAnchor(anchor);
    });
    anchors.forEach(function(anchor) {
      normalizeAnchor(anchor);
    });

    document.querySelectorAll('button').forEach(function(button) {
      var childLink = button.querySelector && button.querySelector('a[href]');
      if (!childLink) return;
      button.setAttribute('data-href', childLink.href || childLink.getAttribute('href'));
      button.setAttribute('role', 'link');
      button.setAttribute('tabindex', '0');
      promotedButtons += 1;
    });

    if (anchors.length !== lastAnchorLogCount) {
      lastAnchorLogCount = anchors.length;
      var sample = [];
      for (var i = 0; i < Math.min(anchors.length, 8); i++) {
        sample.push({
          node: nodeLabel(anchors[i]),
          href: safeText(anchors[i].href || anchors[i].getAttribute('href'), 180),
          text: safeText(anchors[i].innerText, 60)
        });
      }
      debug('anchors-normalized', {
        count: anchors.length,
        promotedButtons: promotedButtons,
        viewport: {
          innerWidth: window.innerWidth,
          innerHeight: window.innerHeight,
          devicePixelRatio: window.devicePixelRatio,
          visualScale: window.visualViewport && window.visualViewport.scale,
          visualOffsetTop: window.visualViewport && window.visualViewport.offsetTop,
          visualPageTop: window.visualViewport && window.visualViewport.pageTop
        },
        sample: sample
      });
    }
  }

  document.addEventListener('DOMContentLoaded', normalizeAllAnchors);
  normalizeAllAnchors();

  if (window.MutationObserver) {
    new MutationObserver(normalizeAllAnchors).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }
})();
''';

const String _emailLinkBridgeScript = '''
<script>
$_emailLinkBridgeJavaScript
</script>
''';

const String _emailKeyboardBridgeJavaScript = r'''
(function() {
  if (window.__vinabikeEmailKeyboardBridgeInstalled) return;
  window.__vinabikeEmailKeyboardBridgeInstalled = true;

  function isEditableTarget(target) {
    if (!target) return false;
    var tag = target.tagName ? String(target.tagName).toLowerCase() : '';
    return tag === 'input' ||
      tag === 'textarea' ||
      tag === 'select' ||
      target.isContentEditable === true;
  }

  document.addEventListener('keydown', function(event) {
    if (!event || event.defaultPrevented) return;
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    if (isEditableTarget(event.target)) return;

    try {
      if (window.EmailKeyboardBridge && EmailKeyboardBridge.postMessage) {
        event.preventDefault();
        event.stopPropagation();
        EmailKeyboardBridge.postMessage(event.key === 'ArrowDown' ? '1' : '-1');
        return false;
      }
    } catch (error) {}
  }, true);
})();
''';

const String _emailKeyboardBridgeScript = '''
<script>
$_emailKeyboardBridgeJavaScript
</script>
''';

void _mailReaderDebug(String message) {
  if (!_emailReaderDiagnosticsEnabled) return;
  debugPrint('📧 [MailReaderDebug] $message');
}

String _debugShort(String value, [int maxLength = 180]) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= maxLength) return compact;
  return '${compact.substring(0, maxLength)}...';
}

class _EmailFragmentParts {
  final String head;
  final String body;

  const _EmailFragmentParts({
    required this.head,
    required this.body,
  });
}

/// Email detail view for unified inbox
class EmailDetailViewUnified extends StatelessWidget {
  final Email email;
  final EmailProvider? provider;
  final bool isLoading;
  final String? error;
  final VoidCallback? onClose;
  final VoidCallback onRetry;
  final VoidCallback? onToggleRead;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onDelete;
  final ValueChanged<int>? onNavigateSelection;

  const EmailDetailViewUnified({
    super.key,
    required this.email,
    this.provider,
    required this.isLoading,
    this.error,
    this.onClose,
    required this.onRetry,
    this.onToggleRead,
    this.onReply,
    this.onReplyAll,
    this.onDelete,
    this.onNavigateSelection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Mobile: Outlook-style architecture
    // 1. Native AppBar with subject
    // 2. Native sender header (Flutter widget)
    // 3. WebView for email body ONLY
    if (onClose != null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onClose,
          ),
          title: Text(
            email.subject,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          actions: _buildActions(context),
        ),
        body: Column(
          children: [
            _SubjectHeader(email: email),
            // Native sender header - like Outlook
            _SenderHeader(email: email),
            _AttachmentStrip(
              email: email,
              provider: provider,
              isLoading: isLoading,
            ),
            // WebView with email body only
            Expanded(
              child: _EmailBodyPane(
                email: email,
                isLoading: isLoading,
                error: error,
                onRetry: onRetry,
                onNavigateSelection: onNavigateSelection,
              ),
            ),
          ],
        ),
      );
    }

    // Desktop: Toolbar + Content
    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _ProviderBadge(providerId: email.providerId),
                const Spacer(),
                ..._buildActions(context),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Column(
              children: [
                _SubjectHeader(email: email),
                _SenderHeader(email: email),
                _AttachmentStrip(
                  email: email,
                  provider: provider,
                  isLoading: isLoading,
                ),
                Expanded(
                  child: _EmailBodyPane(
                    email: email,
                    isLoading: isLoading,
                    error: error,
                    onRetry: onRetry,
                    onNavigateSelection: onNavigateSelection,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      if (onToggleRead != null)
        IconButton(
          icon: Icon(
            email.isRead
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
          ),
          onPressed: onToggleRead,
          tooltip: email.isRead ? 'Marcar como no leído' : 'Marcar como leído',
        ),
      if (onReply != null)
        IconButton(
          icon: const Icon(Icons.reply),
          onPressed: onReply,
          tooltip: 'Responder',
        ),
      if (onReplyAll != null)
        IconButton(
          icon: const Icon(Icons.reply_all),
          onPressed: onReplyAll,
          tooltip: 'Responder a todos',
        ),
      if (onDelete != null)
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
          tooltip: 'Eliminar',
        ),
    ];
  }
}

class _ProviderBadge extends StatelessWidget {
  final String providerId;

  const _ProviderBadge({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _getIcon(),
          const SizedBox(width: 4),
          Text(
            _getLabel(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _getColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (providerId) {
      case 'gmail':
        return Colors.red;
      case 'zoho':
        return const Color(0xFF2B579A);
      default:
        return Colors.blue;
    }
  }

  Widget _getIcon() {
    switch (providerId) {
      case 'gmail':
        return Image.asset(
          'assets/icons/gmail_logo.webp',
          width: 16,
          height: 16,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.mail, size: 16, color: Colors.red),
        );
      case 'zoho':
        return Image.asset(
          'assets/icons/zoho_logo.png',
          width: 16,
          height: 16,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.business, size: 16, color: Color(0xFF2B579A)),
        );
      default:
        return const Icon(Icons.email_outlined, size: 14);
    }
  }

  String _getLabel() {
    switch (providerId) {
      case 'gmail':
        return 'Gmail';
      case 'zoho':
        return 'Zoho';
      default:
        return 'Email';
    }
  }
}

class _SubjectHeader extends StatelessWidget {
  final Email email;

  const _SubjectHeader({required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      color: theme.colorScheme.surface,
      child: Text(
        email.subject.isEmpty ? '(sin asunto)' : email.subject,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Native sender header widget - like Outlook/Gmail
class _SenderHeader extends StatelessWidget {
  final Email email;

  const _SenderHeader({required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderInitial =
        email.senderName.isNotEmpty ? email.senderName[0].toUpperCase() : '?';
    final avatarColor =
        email.providerId.contains('gmail') ? Colors.red : Colors.blue;

    final date = email.receivedTime;
    final dateStr =
        '${date.day} ${_monthName(date.month)}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 19,
            backgroundColor: avatarColor,
            child: Text(
              senderInitial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        email.senderName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        email.senderEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Para: ${email.toAddress}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            dateStr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
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
      'dic'
    ];
    return months[month - 1];
  }
}

class _AttachmentStrip extends StatelessWidget {
  final Email email;
  final EmailProvider? provider;
  final bool isLoading;

  const _AttachmentStrip({
    required this.email,
    required this.provider,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final attachments = email.attachments;
    if (!email.hasAttachment && attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: attachments.isEmpty ? 48 : 72,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.7)),
        ),
      ),
      child: attachments.isEmpty
          ? Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: isLoading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          Icons.attach_file,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                ),
                const SizedBox(width: 10),
                Text(
                  isLoading
                      ? 'Cargando adjuntos...'
                      : 'Adjunto detectado, sin detalles disponibles.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final attachment = attachments[index];
                return _AttachmentChip(
                  email: email,
                  provider: provider,
                  attachment: attachment,
                );
              },
            ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final Email email;
  final EmailProvider? provider;
  final EmailAttachment attachment;

  const _AttachmentChip({
    required this.email,
    required this.provider,
    required this.attachment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: provider == null
            ? null
            : () => _EmailAttachmentPreviewDialog.show(
                  context,
                  provider: provider!,
                  email: email,
                  attachment: attachment,
                ),
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.75),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForAttachment(attachment),
                  size: 19,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      attachment.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (attachment.displaySize.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        attachment.displaySize,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_full_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailAttachmentPreviewDialog extends StatefulWidget {
  final EmailProvider provider;
  final Email email;
  final EmailAttachment attachment;

  const _EmailAttachmentPreviewDialog({
    required this.provider,
    required this.email,
    required this.attachment,
  });

  static Future<void> show(
    BuildContext context, {
    required EmailProvider provider,
    required Email email,
    required EmailAttachment attachment,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _EmailAttachmentPreviewDialog(
        provider: provider,
        email: email,
        attachment: attachment,
      ),
    );
  }

  @override
  State<_EmailAttachmentPreviewDialog> createState() =>
      _EmailAttachmentPreviewDialogState();
}

class _EmailAttachmentPreviewDialogState
    extends State<_EmailAttachmentPreviewDialog> {
  late Future<Uint8List> _bytesFuture;
  bool _isOpeningInSpreadsheets = false;
  SpreadsheetFileImportStage? _spreadsheetImportStage;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  Future<Uint8List> _loadBytes() {
    return widget.provider.downloadAttachment(
      widget.email,
      widget.attachment,
    );
  }

  bool get _canOpenInSpreadsheets => SpreadsheetFileHandoffService.instance
      .supportsFileName(widget.attachment.displayName);

  Future<void> _openInSpreadsheets(Uint8List bytes) async {
    if (_isOpeningInSpreadsheets || !_canOpenInSpreadsheets) return;

    setState(() {
      _isOpeningInSpreadsheets = true;
      _spreadsheetImportStage = SpreadsheetFileImportStage.decoding;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final workspaceManager = context.read<WorkspaceManager>();
    var completed = false;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Abriendo ${widget.attachment.displayName} en Planillas...',
        ),
      ),
    );

    try {
      final sheet = await SpreadsheetFileHandoffService.instance.importBytes(
        bytes: bytes,
        fileName: widget.attachment.displayName,
        store: context.read<SpreadsheetService>(),
        onStageChanged: (stage) {
          if (mounted) {
            setState(() => _spreadsheetImportStage = stage);
          }
        },
      );
      final sheetId = sheet.id;
      if (!mounted || sheetId == null) {
        throw StateError('La planilla importada no recibió un identificador.');
      }

      completed = true;
      messenger.hideCurrentSnackBar();
      navigator.pop();
      final route = '/tools/spreadsheets/$sheetId';
      // Attachment dialogs are hosted by the root Navigator, outside the
      // active workspace's GoRouter subtree. WorkspaceManager is the canonical
      // bridge for navigation from global overlays.
      workspaceManager.navigateActiveWorkspace(route);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '“${widget.attachment.displayName}” se abrió en Planillas.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
          'Email spreadsheet attachment import error: $error\n$stackTrace');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir en Planillas: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted && !completed) {
        setState(() {
          _isOpeningInSpreadsheets = false;
          _spreadsheetImportStage = null;
        });
      }
    }
  }

  Future<void> _download(Uint8List bytes) async {
    var savedInternally = false;
    try {
      await AppFileStorageService.instance.saveFile(
        bytes: bytes,
        fileName: _safeFileName(widget.attachment.displayName),
        mimeType: widget.attachment.mimeType,
        context: AppFileContext(
          sourceType: 'email_attachment',
          sourceId: widget.email.id,
          sourceProvider: widget.email.providerId,
          sourceRoute: '/mail',
          contextType: 'email',
          contextId: widget.email.id,
          contextTitle: widget.email.subject,
          contextSubtitle:
              '${widget.email.senderName} · ${widget.email.receivedTime.toLocal()}',
          tags: const ['correo', 'adjunto'],
          metadata: {
            'attachment_id': widget.attachment.id,
            'provider_attachment_id': widget.attachment.attachmentId,
            'from': widget.email.fromAddress,
            'to': widget.email.toAddress,
            'received_at': widget.email.receivedTime.toIso8601String(),
          },
        ),
      );
      savedInternally = true;
    } catch (error) {
      debugPrint('No se pudo guardar adjunto en Archivos: $error');
    }

    await downloadFile(
      bytes: bytes,
      fileName: _safeFileName(widget.attachment.displayName),
      mimeType: widget.attachment.mimeType,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedInternally
              ? 'Archivo descargado y guardado en Archivos.'
              : 'Archivo descargado. No se pudo guardar en Archivos.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalInset = screenSize.width < 720 ? 12.0 : 36.0;
    final verticalInset = screenSize.height < 720 ? 12.0 : 22.0;
    final availableWidth = screenSize.width - (horizontalInset * 2);
    final availableHeight = screenSize.height - (verticalInset * 2);
    final dialogWidth = availableWidth < 1180 ? availableWidth : 1180.0;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: dialogWidth,
        height: availableHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: FutureBuilder<Uint8List>(
              future: _bytesFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                return Column(
                  children: [
                    _EmailAttachmentPreviewHeader(
                      attachment: widget.attachment,
                      isLoading:
                          snapshot.connectionState == ConnectionState.waiting,
                      isOpeningInSpreadsheets: _isOpeningInSpreadsheets,
                      onClose: () => Navigator.of(context).maybePop(),
                      onRetry: () {
                        setState(() {
                          _bytesFuture = _loadBytes();
                        });
                      },
                      onDownload: bytes == null ? null : () => _download(bytes),
                      onOpenInSpreadsheets:
                          bytes == null || !_canOpenInSpreadsheets
                              ? null
                              : () => _openInSpreadsheets(bytes),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildPreview(snapshot)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(AsyncSnapshot<Uint8List> snapshot) {
    final theme = Theme.of(context);

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (snapshot.hasError || snapshot.data == null) {
      return _AttachmentPreviewEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el adjunto',
        subtitle: 'El correo indica que existe, pero no se pudo obtener.',
        actionIcon: Icons.refresh,
        actionLabel: 'Reintentar',
        onAction: () {
          setState(() {
            _bytesFuture = _loadBytes();
          });
        },
      );
    }

    final bytes = snapshot.data!;
    final attachment = widget.attachment;

    if (attachment.isImage) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _AttachmentPreviewEmptyState(
                icon: Icons.broken_image_outlined,
                title: 'Imagen no compatible',
                subtitle:
                    'Puedes descargar el archivo desde el botón superior.',
              ),
            ),
          ),
        ),
      );
    }

    if (attachment.isPdf) {
      return PdfPreview(
        build: (PdfPageFormat _) async => bytes,
        useActions: false,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: _safeFileName(attachment.displayName),
        scrollViewDecoration: const BoxDecoration(
          color: Color(0xFFE5E7EB),
        ),
      );
    }

    if (attachment.isTextLike) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF8FAFC),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.45,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      );
    }

    return _AttachmentPreviewEmptyState(
      icon: _iconForAttachment(attachment),
      title: 'Vista previa no disponible',
      subtitle: _canOpenInSpreadsheets
          ? '${attachment.displayName} se puede abrir directamente en Planillas.'
          : '${attachment.displayName} está listo para descargar desde el botón superior.',
      actionIcon: _canOpenInSpreadsheets ? Icons.table_view_outlined : null,
      actionLabel: _canOpenInSpreadsheets
          ? switch (_spreadsheetImportStage) {
              SpreadsheetFileImportStage.decoding => 'Leyendo archivo...',
              SpreadsheetFileImportStage.saving => 'Guardando planilla...',
              null => 'Abrir en Planillas',
            }
          : null,
      actionInProgress: _isOpeningInSpreadsheets,
      onAction:
          _canOpenInSpreadsheets ? () => _openInSpreadsheets(bytes) : null,
    );
  }
}

class _EmailAttachmentPreviewHeader extends StatelessWidget {
  final EmailAttachment attachment;
  final bool isLoading;
  final bool isOpeningInSpreadsheets;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenInSpreadsheets;

  const _EmailAttachmentPreviewHeader({
    required this.attachment,
    required this.isLoading,
    required this.isOpeningInSpreadsheets,
    required this.onClose,
    required this.onRetry,
    required this.onDownload,
    required this.onOpenInSpreadsheets,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(
            _iconForAttachment(attachment),
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (attachment.displaySize.isNotEmpty)
                  Text(
                    attachment.displaySize,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'Reintentar',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            ),
          if (isOpeningInSpreadsheets)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (onOpenInSpreadsheets != null)
            IconButton(
              tooltip: 'Abrir en Planillas',
              onPressed: onOpenInSpreadsheets,
              icon: const Icon(Icons.table_view_outlined),
            ),
          IconButton(
            tooltip: 'Descargar',
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreviewEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionInProgress;

  const _AttachmentPreviewEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
    this.actionInProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionIcon != null && actionLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton.icon(
                  onPressed: actionInProgress ? null : onAction,
                  icon: actionInProgress
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(actionIcon),
                  label: Text(actionLabel!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForAttachment(EmailAttachment attachment) {
  if (attachment.isPdf) return Icons.picture_as_pdf_outlined;
  if (attachment.isImage) return Icons.image_outlined;
  switch (attachment.extension) {
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'mp4':
    case 'mov':
      return Icons.movie_outlined;
    case 'mp3':
    case 'ogg':
    case 'wav':
      return Icons.audio_file_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _safeFileName(String value) {
  final cleaned = value
      .trim()
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return cleaned.isEmpty ? 'archivo' : cleaned;
}

class _EmailBodyPane extends StatelessWidget {
  final Email email;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<int>? onNavigateSelection;

  const _EmailBodyPane({
    required this.email,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.onNavigateSelection,
  });

  bool get _hasContent => email.content?.trim().isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (error != null && !_hasContent) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: colorScheme.error),
              const SizedBox(height: 14),
              Text(
                'No se pudo cargar el mensaje',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              MailErrorDiagnosticBanner(
                message: error!.contains('404')
                    ? 'No se pudo encontrar el contenido del mensaje.'
                    : error!,
                compact: false,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading && !_hasContent) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Cargando mensaje...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (!_hasContent) {
      return Center(
        child: Text(
          'Este mensaje no tiene contenido.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Stack(
      children: [
        _EmailBodyWebView(
          email: email,
          onNavigateSelection: onNavigateSelection,
        ),
        if (isLoading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

/// WebView that renders ONLY the email body HTML (no sender info)
class _EmailBodyWebView extends StatefulWidget {
  final Email email;
  final ValueChanged<int>? onNavigateSelection;

  const _EmailBodyWebView({
    required this.email,
    required this.onNavigateSelection,
  });

  @override
  State<_EmailBodyWebView> createState() => _EmailBodyWebViewState();
}

class _EmailBodyWebViewState extends State<_EmailBodyWebView> {
  WebViewController? _controller;
  bool _isReady = false;
  bool _controllerConfigured = false;
  String _lastLoadedContent = '';
  int _loadGeneration = 0;
  int _lastLoadedRendererVersion = -1;
  double _appScale = 1.0;
  double? _lastAppliedContentScale;
  double? _pendingContentScale;

  bool get _useNativeWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _appScale = _readAppScale(context);
    if (_useNativeWebView) {
      _mailReaderDebug(
        'init email=${widget.email.id} provider=${widget.email.providerId} '
        'subject="${_debugShort(widget.email.subject)}"',
      );
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'EmailLinkBridge',
          onMessageReceived: (message) {
            _mailReaderDebug(
              'js-link-channel url=${_debugShort(message.message, 260)}',
            );
            unawaited(_openEmailUrl(context, message.message));
          },
        )
        ..addJavaScriptChannel(
          'EmailDebugBridge',
          onMessageReceived: (message) {
            _mailReaderDebug('js ${_debugShort(message.message, 500)}');
          },
        )
        ..addJavaScriptChannel(
          'EmailKeyboardBridge',
          onMessageReceived: (message) {
            final delta = int.tryParse(message.message);
            if (delta == null || delta == 0) return;
            widget.onNavigateSelection?.call(delta > 0 ? 1 : -1);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              _mailReaderDebug('page-started url=${_debugShort(url, 260)}');
            },
            onPageFinished: (url) {
              _mailReaderDebug('page-finished url=${_debugShort(url, 260)}');
              unawaited(_installLinkBridge());
              unawaited(_applyContentScale(_appScale));
              if (mounted) setState(() => _isReady = true);
            },
            onWebResourceError: (error) {
              _mailReaderDebug(
                'resource-error code=${error.errorCode} '
                'type=${error.errorType} '
                'description="${_debugShort(error.description, 220)}" '
                'url=${_debugShort(error.url ?? '', 260)}',
              );
            },
            onNavigationRequest: (request) async {
              _mailReaderDebug(
                'nav-request url=${_debugShort(request.url, 320)}',
              );
              // Allow initial local loads and in-document anchors. Any real
              // link click is handed to the OS browser like a desktop mail app.
              if (request.url.startsWith('about:') ||
                  request.url.startsWith('data:') ||
                  _isReaderInternalNavigation(request.url)) {
                _mailReaderDebug(
                  'nav-allow-local url=${_debugShort(request.url, 260)}',
                );
                return NavigationDecision.navigate;
              }

              if (_isSyntheticReaderUrl(request.url)) {
                _mailReaderDebug(
                  'nav-prevent-synthetic url=${_debugShort(request.url, 260)}',
                );
                return NavigationDecision.prevent;
              }

              final handled = await _openEmailUrl(context, request.url);
              _mailReaderDebug(
                'nav-external handled=$handled '
                'url=${_debugShort(request.url, 260)}',
              );
              return handled
                  ? NavigationDecision.prevent
                  : NavigationDecision.navigate;
            },
          ),
        );
      unawaited(_configureControllerAndLoad(_controller!));
    }
  }

  Future<void> _configureControllerAndLoad(WebViewController controller) async {
    await _installConsoleDiagnostics(controller);
    try {
      await controller.enableZoom(false);
      _mailReaderDebug('zoom disabled before load');
    } catch (error) {
      _mailReaderDebug('zoom disable unavailable: $error');
    }
    if (!mounted) return;
    _controllerConfigured = true;
    _loadContent();
  }

  double _readAppScale(BuildContext context) {
    if (!WindowZoomService.isDesktop) return 1.0;
    try {
      return context.read<WindowZoomService>().scale.clamp(0.5, 3.0).toDouble();
    } on ProviderNotFoundException {
      return 1.0;
    }
  }

  double _watchAppScale(BuildContext context) {
    if (!WindowZoomService.isDesktop) return 1.0;
    try {
      return context
          .watch<WindowZoomService>()
          .scale
          .clamp(0.5, 3.0)
          .toDouble();
    } on ProviderNotFoundException {
      return 1.0;
    }
  }

  void _scheduleContentScaleSync(double appScale) {
    if (!_useNativeWebView || !_controllerConfigured) return;
    if (_pendingContentScale != null &&
        (_pendingContentScale! - appScale).abs() < 0.001) {
      return;
    }
    if (_lastAppliedContentScale != null &&
        (_lastAppliedContentScale! - appScale).abs() < 0.001) {
      return;
    }

    _pendingContentScale = appScale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingContentScale;
      _pendingContentScale = null;
      if (pending == null) return;
      unawaited(_applyContentScale(pending));
    });
  }

  Future<void> _applyContentScale(double appScale) async {
    final controller = _controller;
    if (controller == null) return;
    if (_lastAppliedContentScale != null &&
        (_lastAppliedContentScale! - appScale).abs() < 0.001) {
      return;
    }

    final scale = appScale.clamp(0.5, 3.0).toDouble();
    try {
      await controller.runJavaScript('''
(function() {
  var scale = ${scale.toStringAsFixed(3)};
  document.documentElement.style.setProperty('--vinabike-email-content-scale', String(scale));
  if (document.body) {
    document.body.style.zoom = String(scale);
  }
})();
''');
      _lastAppliedContentScale = scale;
      _mailReaderDebug('content-scale-applied scale=$scale');
    } catch (error) {
      _mailReaderDebug('content-scale failed: $error');
    }
  }

  @override
  void didUpdateWidget(covariant _EmailBodyWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newContent = widget.email.content ?? '';
    final rendererChanged =
        _lastLoadedRendererVersion != _emailBodyRendererVersion;
    if (_controllerConfigured &&
        (newContent != _lastLoadedContent || rendererChanged) &&
        newContent.isNotEmpty) {
      _loadContent();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_useNativeWebView && _controllerConfigured) {
      _lastLoadedRendererVersion = -1;
      Future<void>.microtask(_loadContent);
    }
  }

  void _loadContent() {
    final generation = ++_loadGeneration;
    _lastLoadedContent = widget.email.content ?? '';
    _lastLoadedRendererVersion = _emailBodyRendererVersion;
    final lower = _lastLoadedContent.toLowerCase();
    _mailReaderDebug(
      'load generation=$generation renderer=$_emailBodyRendererVersion '
      'chars=${_lastLoadedContent.length} '
      'fullDoc=${_looksLikeEmailDocument(_lastLoadedContent)} '
      'hasAnchor=${lower.contains('<a')} hasHref=${lower.contains('href=')} '
      'subject="${_debugShort(widget.email.subject)}"',
    );
    if (_isReady) setState(() => _isReady = false);
    _controller?.loadHtmlString(
      _buildBodyHtml(),
      baseUrl: _emailReaderBaseUrl,
    );
    _lastAppliedContentScale = null;
    _scheduleContentScaleSync(_appScale);

    // macOS WKWebView doesn't reliably fire onPageFinished for loadHtmlString.
    // Keep a white surface briefly so the native view doesn't flash dark before
    // the email document paints, then reveal the already-loaded content.
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      Future<void>.delayed(const Duration(milliseconds: 140), () async {
        await _installLinkBridge();
        await _applyContentScale(_appScale);
        if (mounted && generation == _loadGeneration) {
          setState(() => _isReady = true);
        }
      });
    }
  }

  Future<void> _installLinkBridge() async {
    try {
      await _controller?.runJavaScript(_emailLinkBridgeJavaScript);
      await _controller?.runJavaScript(_emailKeyboardBridgeJavaScript);
      _mailReaderDebug('js bridge install requested');
    } catch (error) {
      _mailReaderDebug('js bridge install failed: $error');
      debugPrint('No se pudo instalar bridge de links del correo: $error');
    }
  }

  Future<void> _installConsoleDiagnostics(WebViewController controller) async {
    if (!_emailReaderDiagnosticsEnabled) return;
    try {
      await controller.setOnConsoleMessage((message) {
        _mailReaderDebug(
          'console ${message.level}: ${_debugShort(message.message, 500)}',
        );
      });
      _mailReaderDebug('console diagnostics installed');
    } catch (error) {
      _mailReaderDebug('console diagnostics unavailable: $error');
    }
  }

  String _buildBodyHtml() {
    final rawContent = (widget.email.content ?? 'Sin contenido.').trim();
    if (_looksLikeEmailDocument(rawContent)) {
      _mailReaderDebug('build using full email document');
      return _injectReaderAssets(rawContent);
    }

    _mailReaderDebug('build using fragment wrapper');
    final parts = _splitFragmentParts(_extractBodyInnerHtml(rawContent));
    return '''
<!DOCTYPE html>
<html>
<head>
  ${_readerHeadAssets(includeCharset: true, includeViewport: true)}
  ${parts.head}
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      min-width: 0;
      background: #ffffff;
      color: #242424;
      overflow-x: auto;
      -webkit-text-size-adjust: 100%;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size: 14px;
      line-height: 1.45;
    }
    #mail-reader {
      box-sizing: border-box;
      width: 100%;
      min-height: 100vh;
      padding: 24px 32px;
      background: #ffffff;
    }
    #mail-content {
      width: 100%;
      margin: 0 auto;
    }
    img { max-width: 100% !important; height: auto !important; }
    table { max-width: 100%; }
    pre { white-space: pre-wrap; word-wrap: break-word; }
    a, area, [href], [onclick], [role="button"], button,
    [data-href], [data-url], [data-link] {
      cursor: pointer !important;
      pointer-events: auto !important;
    }
  </style>
</head>
<body><div id="mail-reader"><div id="mail-content">${parts.body}</div></div></body>
</html>
''';
  }

  bool _looksLikeEmailDocument(String html) {
    final lower = html.toLowerCase();
    return lower.contains('<!doctype') ||
        lower.contains('<html') ||
        lower.contains('<head') ||
        lower.contains('<body');
  }

  String _injectReaderAssets(String html) {
    final htmlWithoutViewport = _removeViewportMeta(html);
    final lower = htmlWithoutViewport.toLowerCase();
    final assets = _readerHeadAssets(
      includeCharset: !lower.contains('charset='),
      includeViewport: true,
      includeBase: !lower.contains('<base'),
    );

    final headClose = RegExp(r'</head\s*>', caseSensitive: false);
    final withHeadAssets = htmlWithoutViewport.replaceFirstMapped(
      headClose,
      (match) => '$assets${match.group(0)}',
    );
    if (withHeadAssets != htmlWithoutViewport) return withHeadAssets;

    final headOpen = RegExp(r'<head\b[^>]*>', caseSensitive: false);
    final withHeadOpen = htmlWithoutViewport.replaceFirstMapped(
      headOpen,
      (match) => '${match.group(0)}$assets',
    );
    if (withHeadOpen != htmlWithoutViewport) return withHeadOpen;

    final htmlOpen = RegExp(r'<html\b[^>]*>', caseSensitive: false);
    final withHtmlOpen = htmlWithoutViewport.replaceFirstMapped(
      htmlOpen,
      (match) => '${match.group(0)}<head>$assets</head>',
    );
    if (withHtmlOpen != htmlWithoutViewport) return withHtmlOpen;

    return '''
<!DOCTYPE html>
<html>
<head>$assets</head>
$htmlWithoutViewport
</html>
''';
  }

  String _readerHeadAssets({
    bool includeCharset = false,
    bool includeViewport = false,
    bool includeBase = true,
  }) {
    final charset = includeCharset ? '<meta charset="UTF-8">' : '';
    final scale = _appScale.clamp(0.5, 3.0).toStringAsFixed(3);
    final viewport = includeViewport
        ? '<meta name="viewport" content="width=device-width, initial-scale=$scale, maximum-scale=$scale, user-scalable=no">'
        : '';
    final base = includeBase ? '<base href="$_emailReaderBaseUrl">' : '';

    return '''
$charset
$viewport
$base
<style id="vinabike-email-reader-style">
  html, body {
    --vinabike-email-content-scale: $scale;
    background: #ffffff !important;
    width: 100%;
    min-width: 0;
    overflow-x: auto;
    -webkit-text-size-adjust: 100%;
  }
  body {
    zoom: var(--vinabike-email-content-scale);
    margin: 0 !important;
    word-break: normal !important;
  }
  img {
    max-width: 100% !important;
    height: auto !important;
  }
  table {
    max-width: 100% !important;
  }
  td, th {
    word-break: normal !important;
    overflow-wrap: break-word;
  }
  pre {
    max-width: 100%;
    white-space: pre-wrap;
    overflow-wrap: break-word;
  }
  a, area, [href], [onclick], [role="button"], button,
  [data-href], [data-url], [data-link] {
    cursor: pointer !important;
    pointer-events: auto !important;
  }
</style>
$_emailLinkBridgeScript
$_emailKeyboardBridgeScript
''';
  }

  _EmailFragmentParts _splitFragmentParts(String html) {
    final head = StringBuffer();
    var body = _removeViewportMeta(html);

    body = body.replaceAllMapped(
      RegExp(r'<meta\b[^>]*>', caseSensitive: false),
      (match) {
        head.writeln(match.group(0));
        return '';
      },
    );

    body = body.replaceAllMapped(
      RegExp(r'<title\b[^>]*>.*?</title\s*>',
          caseSensitive: false, dotAll: true),
      (match) {
        head.writeln(match.group(0));
        return '';
      },
    );

    body = body.replaceAllMapped(
      RegExp(r'<style\b[^>]*>.*?</style\s*>',
          caseSensitive: false, dotAll: true),
      (match) {
        head.writeln(match.group(0));
        return '';
      },
    );

    body = body
        .replaceAll(
          RegExp(r'<p\b[^>]*>\s*(?:&nbsp;|\s)*</p\s*>', caseSensitive: false),
          '',
        )
        .trim();

    return _EmailFragmentParts(head: head.toString(), body: body);
  }

  String _removeViewportMeta(String html) {
    return html.replaceAll(
      RegExp(
        r'''<meta\b(?=[^>]*\bname\s*=\s*["']?viewport["']?)[^>]*>''',
        caseSensitive: false,
      ),
      '',
    );
  }

  String _extractBodyInnerHtml(String html) {
    final lower = html.toLowerCase();
    int start = lower.indexOf('<body');
    if (start != -1) {
      start = lower.indexOf('>', start) + 1;
      int end = lower.lastIndexOf('</body>');
      if (end != -1 && end > start) {
        return html.substring(start, end);
      }
    }
    return html
        .replaceAll(RegExp(r'<!doctype[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<html[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</html>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'<head\b[^>]*>.*?</head>',
              caseSensitive: false, dotAll: true),
          '',
        )
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    _appScale = _watchAppScale(context);
    _scheduleContentScaleSync(_appScale);

    if (!_useNativeWebView) {
      return ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: HtmlWidget(
                widget.email.content ?? '',
                customStylesBuilder: (element) {
                  switch (element.localName) {
                    case 'table':
                      return {'max-width': '100%'};
                    case 'img':
                      return {'max-width': '100%', 'height': 'auto'};
                    case 'td':
                    case 'th':
                      return {
                        'word-break': 'normal',
                        'overflow-wrap': 'break-word',
                      };
                    case 'pre':
                      return {
                        'max-width': '100%',
                        'white-space': 'pre-wrap',
                        'overflow-wrap': 'break-word',
                      };
                    default:
                      return null;
                  }
                },
                onTapUrl: (url) => _openEmailUrl(context, url),
              ),
            ),
          ),
        ),
      );
    }

    if (_controllerConfigured &&
        _lastLoadedRendererVersion != _emailBodyRendererVersion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _controllerConfigured &&
            _lastLoadedRendererVersion != _emailBodyRendererVersion) {
          _loadContent();
        }
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _NativeEmailWebViewZoomBoundary(
          appScale: _appScale,
          child: WebViewWidget(controller: _controller!),
        ),
        if (!_isReady) const ColoredBox(color: Colors.white),
      ],
    );
  }
}

class _NativeEmailWebViewZoomBoundary extends StatelessWidget {
  const _NativeEmailWebViewZoomBoundary({
    required this.appScale,
    required this.child,
  });

  final double appScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowZoomService.isDesktop || (appScale - 1.0).abs() < 0.001) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }

        final nativeWidth = constraints.maxWidth * appScale;
        final nativeHeight = constraints.maxHeight * appScale;

        return ClipRect(
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: 1 / appScale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: nativeWidth,
                  height: nativeHeight,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _isReaderInternalNavigation(String rawUrl) {
  if (rawUrl == _emailReaderBaseUrl) return true;
  if (rawUrl == '$_emailReaderBaseUrl#') return true;
  return rawUrl.startsWith('$_emailReaderBaseUrl#');
}

bool _isSyntheticReaderUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  final baseUri = Uri.tryParse(_emailReaderBaseUrl);
  if (uri == null || baseUri == null) return false;
  return uri.scheme == baseUri.scheme && uri.host == baseUri.host;
}

Future<bool> _openEmailUrl(BuildContext context, String rawUrl) async {
  final url = rawUrl.trim();
  _mailReaderDebug('open-request raw=${_debugShort(rawUrl, 320)}');
  if (url.isEmpty) return false;
  if (_isSyntheticReaderUrl(url)) {
    _mailReaderDebug('open-ignore-synthetic url=${_debugShort(url, 260)}');
    return true;
  }

  final lower = url.toLowerCase();
  if (lower.startsWith('javascript:')) {
    _mailReaderDebug('open-ignore-javascript');
    return true;
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    _mailReaderDebug('open-invalid-url url=${_debugShort(url, 260)}');
    return false;
  }

  if (uri.scheme == 'http' || uri.scheme == 'https') {
    final route = _webWorkspaceRouteForEmailLink(uri);
    _mailReaderDebug('open-workspace route=${_debugShort(route, 320)}');

    try {
      final isSmallScreen =
          (MediaQuery.maybeOf(context)?.size.width ?? 1000) < 800;
      if (isSmallScreen) {
        if (context.mounted) context.push(route);
        return true;
      }

      context.read<WorkspaceManager>().openRouteInWorkspace(route);
      return true;
    } catch (error) {
      _mailReaderDebug('open-workspace-fallback $error');
      if (context.mounted) {
        context.go(route);
        return true;
      }
      return false;
    }
  }

  try {
    _mailReaderDebug('open-non-web-external url=${_debugShort(url, 320)}');
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _mailReaderDebug('open-launch-external-success');
      return true;
    }
    final fallbackOpened =
        await launchUrl(uri, mode: LaunchMode.platformDefault);
    _mailReaderDebug('open-launch-platform-default result=$fallbackOpened');
    return fallbackOpened;
  } catch (error) {
    _mailReaderDebug('open-launch-error $error');
    debugPrint('No se pudo abrir link de correo: $url ($error)');
    return false;
  }
}

String _webWorkspaceRouteForEmailLink(Uri uri) {
  return Uri(
    path: '/tools/web',
    queryParameters: {
      'url': uri.toString(),
      'name': _emailLinkWorkspaceTitle(uri),
    },
  ).toString();
}

String _emailLinkWorkspaceTitle(Uri uri) {
  final host = uri.host.trim();
  if (host.isEmpty) return 'Navegador web';

  if (RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host)) {
    return 'Documento web';
  }

  final normalizedHost = host.replaceFirst(RegExp(r'^www\.'), '');
  final parts = normalizedHost.split('.');
  final base = parts.length >= 2 ? parts[parts.length - 2] : parts.first;
  if (base.isEmpty) return normalizedHost;

  return base[0].toUpperCase() + base.substring(1);
}
