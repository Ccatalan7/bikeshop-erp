import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/route_share_service.dart';

class AppLinkLandingPage extends StatefulWidget {
  final Uri uri;

  const AppLinkLandingPage({
    super.key,
    required this.uri,
  });

  @override
  State<AppLinkLandingPage> createState() => _AppLinkLandingPageState();
}

class _AppLinkLandingPageState extends State<AppLinkLandingPage> {
  SharedRouteLink? _link;
  bool _triedAutoOpen = false;

  @override
  void initState() {
    super.initState();
    _link = _resolveLink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openInApp();
      }
    });
  }

  SharedRouteLink? _resolveLink() {
    final route = RouteShareService.routeFromUri(widget.uri);
    if (route == null) return null;

    return RouteShareService.buildForRoute(
      route: route,
      title: widget.uri.queryParameters['title'] ?? '',
    );
  }

  Future<void> _openInApp() async {
    final link = _link;
    if (link == null) return;

    try {
      await launchUrl(link.uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The manual button remains available when the browser blocks auto-open.
    } finally {
      if (mounted) {
        setState(() => _triedAutoOpen = true);
      }
    }
  }

  Future<void> _copyInternalLink() async {
    final link = _link;
    if (link == null) return;

    await Clipboard.setData(ClipboardData(text: link.uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace interno copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: link == null
                ? _InvalidLinkContent(theme: theme)
                : _ValidLinkContent(
                    theme: theme,
                    link: link,
                    triedAutoOpen: _triedAutoOpen,
                    onOpen: _openInApp,
                    onCopy: _copyInternalLink,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ValidLinkContent extends StatelessWidget {
  final ThemeData theme;
  final SharedRouteLink link;
  final bool triedAutoOpen;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  const _ValidLinkContent({
    required this.theme,
    required this.link,
    required this.triedAutoOpen,
    required this.onOpen,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.travel_explore_outlined,
            color: Color(0xFF2563EB),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Abrir en Vinabike ERP',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          link.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          triedAutoOpen
              ? 'Si el ERP no se abrio automaticamente, usa el boton para intentarlo de nuevo.'
              : 'Intentando abrir la pagina compartida en la app.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Abrir en la app'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Copiar enlace interno'),
          ),
        ),
      ],
    );
  }
}

class _InvalidLinkContent extends StatelessWidget {
  final ThemeData theme;

  const _InvalidLinkContent({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.link_off_rounded,
          color: Color(0xFFEF4444),
          size: 42,
        ),
        const SizedBox(height: 18),
        Text(
          'Enlace no disponible',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Este enlace no apunta a una pagina valida del ERP.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
