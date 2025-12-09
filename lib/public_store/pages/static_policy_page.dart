import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/editable_block_renderer.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../providers/public_store_tenant_provider.dart';

/// Lightweight read-only page renderer for policy/info pages.
/// Avoids WebsiteService/notifyListeners to prevent unwanted redirects.
class StaticPolicyPage extends StatefulWidget {
  final String slug;
  final String fallbackTitle;

  const StaticPolicyPage({super.key, required this.slug, required this.fallbackTitle});

  @override
  State<StaticPolicyPage> createState() => _StaticPolicyPageState();
}

class _StaticPolicyPageState extends State<StaticPolicyPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _blocks = [];
  String? _pageId;
  String? _pageTitle;
  Map<String, dynamic> _settings = {};
  bool _editModeChecked = false;

  // Theme defaults (will be overridden by settings if present)
  Color _primaryColor = const Color(0xFF2E7D32);
  Color _accentColor = const Color(0xFFFF6F00);
  Color _textColor = Colors.black87;
  String _headingFont = 'Roboto';
  String _bodyFont = 'Roboto';
  double _headingSize = 48.0;
  double _bodySize = 16.0;
  double _sectionSpacing = 64.0;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;
      if (tenantId == null) {
        throw Exception('No tenant detected');
      }

      final client = Supabase.instance.client;

      // Load settings (optional, ignore errors)
      final settingsResp = await client
          .from('website_settings')
          .select('key, value')
          .eq('tenant_id', tenantId);
      _applySettings(settingsResp);

      // Load page by slug
      final pagesResp = await client
          .from('website_pages')
          .select('id, title')
          .eq('tenant_id', tenantId)
          .eq('slug', widget.slug)
          .eq('is_published', true)
          .maybeSingle();

      if (pagesResp == null) {
        throw Exception('Página no encontrada');
      }

      final pageId = pagesResp['id'] as String;
  _pageId = pageId;
  _pageTitle = pagesResp['title'] as String? ?? widget.fallbackTitle;

      // Load visible blocks ordered by order_index
      final blocksResp = await client
          .from('website_blocks')
          .select()
          .eq('tenant_id', tenantId)
          .eq('page_id', pageId)
          .eq('is_visible', true)
          .order('order_index', ascending: true);

      _blocks = blocksResp.cast<Map<String, dynamic>>();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applySettings(List<dynamic> rows) {
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String? ?? '';
      if (key == null) continue;
      _settings[key] = value;
      switch (key) {
        case 'theme_primary_color':
          _primaryColor = _parseColor(value) ?? _primaryColor;
          break;
        case 'theme_accent_color':
          _accentColor = _parseColor(value) ?? _accentColor;
          break;
        case 'theme_text_color':
          _textColor = _parseColor(value) ?? _textColor;
          break;
        case 'theme_heading_font':
          if (value.isNotEmpty) _headingFont = value;
          break;
        case 'theme_body_font':
          if (value.isNotEmpty) _bodyFont = value;
          break;
        case 'theme_heading_size':
          final v = double.tryParse(value);
          if (v != null) _headingSize = v.clamp(24.0, 72.0);
          break;
        case 'theme_body_size':
          final v = double.tryParse(value);
          if (v != null) _bodySize = v.clamp(12.0, 24.0);
          break;
        case 'theme_section_spacing':
          final v = double.tryParse(value);
          if (v != null) _sectionSpacing = v.clamp(32.0, 128.0);
          break;
      }
    }
  }

  void _checkEditModeFromRouter(BuildContext context) {
    if (_loading || _pageId == null) return;
    if (_editModeChecked) return;

    final goRouterState = GoRouterState.of(context);
    final queryParams = goRouterState.uri.queryParameters;
    final shouldEdit = queryParams['edit'] == 'true';
    final shouldPreview = queryParams['preview'] == 'true';

    if (!shouldEdit && !shouldPreview) return;
    _editModeChecked = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editProvider = context.read<WebsiteEditModeProvider>();
      final blocks = List<Map<String, dynamic>>.from(_blocks);
      final settingsCopy = Map<String, dynamic>.from(_settings);

      if (shouldEdit) {
        editProvider.enterEditMode(
          blocks,
          settingsCopy,
          pageId: _pageId,
          pageSlug: widget.slug,
        );
      } else {
        editProvider.enterPreviewMode(
          blocks,
          settingsCopy,
          pageId: _pageId,
          pageSlug: widget.slug,
        );
      }
    });
  }

  Color? _parseColor(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      var cleaned = trimmed.toLowerCase();
      if (cleaned.startsWith('color(')) {
        cleaned = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      }
      int? intValue = int.tryParse(cleaned);
      if (intValue == null && cleaned.startsWith('0x')) {
        intValue = int.tryParse(cleaned);
      }
      if (intValue == null) {
        cleaned = cleaned.replaceAll('#', '');
        intValue = int.tryParse(cleaned, radix: 16);
        if (intValue != null && cleaned.length <= 6) {
          intValue = 0xFF000000 | intValue;
        }
      }
      return intValue != null ? Color(intValue) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkEditModeFromRouter(context);

    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;
    final blocksToRender = isEditMode ? editProvider.blocks : _blocks;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                widget.fallbackTitle,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _textColor.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      );
    }

    if (_blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Esta página está en construcción',
            style: TextStyle(fontSize: 18, color: _textColor.withOpacity(0.7)),
          ),
        ),
      );
    }

    // Render blocks; Editable when in edit mode
    return Column(
      children: blocksToRender.map((block) {
        final data = block['block_data'] as Map<String, dynamic>? ?? {};
        final isVisible = block['is_visible'] == true;
        final blockType = block['block_type']?.toString() ?? 'hero';
        final blockId = block['id']?.toString() ?? '';
        final tenantId = context.read<PublicStoreTenantProvider>().tenantId;

        final widgetBuilder = isEditMode
            ? EditableBlockRenderer.build(
                context: context,
                blockId: blockId,
                blockType: blockType,
                data: data,
                primaryColor: _primaryColor,
                accentColor: _accentColor,
                headingFont: _headingFont,
                bodyFont: _bodyFont,
                headingSize: _headingSize,
                bodySize: _bodySize,
                onNavigate: (route) => context.go(route),
                isVisible: isVisible,
                tenantId: tenantId,
              )
            : WebsiteBlockRenderer.build(
                context: context,
                blockType: blockType,
                data: data,
                primaryColor: _primaryColor,
                accentColor: _accentColor,
                headingFont: _headingFont,
                bodyFont: _bodyFont,
                headingSize: _headingSize,
                bodySize: _bodySize,
                onNavigate: (route) => context.go(route),
                tenantId: tenantId,
              );

        return Padding(
          padding: EdgeInsets.only(bottom: _sectionSpacing),
          child: widgetBuilder,
        );
      }).toList(),
    );
  }
}
