import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/website_destination.dart';

enum WebsiteDestinationHealth { ready, warning, broken }

enum WebsiteDestinationOwner {
  pages,
  catalogCategories,
  catalogProducts,
  navigation,
  advanced,
  none,
}

class WebsiteDestinationAuditItem {
  const WebsiteDestinationAuditItem({
    required this.href,
    required this.kind,
    required this.title,
    required this.health,
    required this.message,
    required this.owner,
    required this.usageCount,
    required this.pageNames,
    required this.sourceLabels,
    required this.navigationLocations,
  });

  final String href;
  final WebsiteDestinationKind kind;
  final String title;
  final WebsiteDestinationHealth health;
  final String message;
  final WebsiteDestinationOwner owner;
  final int usageCount;
  final List<String> pageNames;
  final List<String> sourceLabels;
  final List<String> navigationLocations;

  bool get needsAttention => health != WebsiteDestinationHealth.ready;
  bool get appearsInNavigation => navigationLocations.isNotEmpty;
}

class WebsiteDestinationAudit {
  const WebsiteDestinationAudit({required this.items});

  final List<WebsiteDestinationAuditItem> items;

  int get readyCount => items
      .where((item) => item.health == WebsiteDestinationHealth.ready)
      .length;
  int get warningCount => items
      .where((item) => item.health == WebsiteDestinationHealth.warning)
      .length;
  int get brokenCount => items
      .where((item) => item.health == WebsiteDestinationHealth.broken)
      .length;
}

/// Builds a read-only integrity view of every persisted CTA and navigation
/// destination. It never creates pages or menu entries implicitly.
class WebsiteDestinationAuditService {
  WebsiteDestinationAuditService({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _client;
  final TenantService _tenantService;

  static const _linkKeys = {
    'ctalink',
    'buttonlink',
    'link',
    'href',
    'to',
  };

  Future<WebsiteDestinationAudit> load() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw StateError('No se pudo determinar la tienda activa.');
    }

    final responses = await Future.wait<dynamic>([
      _client
          .from('website_pages')
          .select('id,slug,title,is_home,is_published')
          .eq('tenant_id', tenantId),
      _client
          .from('website_blocks')
          .select('id,page_id,block_type,block_data,is_visible')
          .eq('tenant_id', tenantId),
      _client
          .from('website_navigation')
          .select(
              'id,label,menu_location,link_type,link_value,is_visible,parent_id')
          .eq('tenant_id', tenantId),
      _client
          .from('product_categories')
          .select('id,name,full_path,is_active,show_on_website')
          .eq('tenant_id', tenantId),
      _client
          .from('products')
          .select(
              'id,name,sku,category_id,is_active,is_published,show_on_website')
          .eq('tenant_id', tenantId),
    ]);

    final pages = _maps(responses[0]);
    final blocks = _maps(responses[1]);
    final navigation = _maps(responses[2]);
    final categories = _maps(responses[3]);
    final products = _maps(responses[4]);

    final pageById = <String, Map<String, dynamic>>{
      for (final page in pages)
        if (_text(page['id']).isNotEmpty) _text(page['id']): page,
    };
    final pageBySlug = <String, Map<String, dynamic>>{
      for (final page in pages)
        if (_text(page['slug']).isNotEmpty) _text(page['slug']): page,
    };
    final categoryById = <String, Map<String, dynamic>>{
      for (final category in categories)
        if (_text(category['id']).isNotEmpty) _text(category['id']): category,
    };
    final productByToken = <String, Map<String, dynamic>>{};
    final markedProductCountByCategory = <String, int>{};
    for (final product in products) {
      final id = _text(product['id']);
      final sku = _text(product['sku']);
      if (id.isNotEmpty) productByToken[id] = product;
      if (sku.isNotEmpty) productByToken[sku] = product;
      if (_isMarkedForWebsite(product)) {
        final categoryId = _text(product['category_id']);
        if (categoryId.isNotEmpty) {
          markedProductCountByCategory[categoryId] =
              (markedProductCountByCategory[categoryId] ?? 0) + 1;
        }
      }
    }

    final usages = <String, _UsageBuilder>{};
    void addUsage({
      required String rawHref,
      required String source,
      String? pageName,
      String? navigationLocation,
    }) {
      final href = WebsiteDestination.normalizeHref(rawHref);
      if (href.isEmpty) return;
      final builder = usages.putIfAbsent(href, () => _UsageBuilder(href));
      builder.usageCount += 1;
      builder.sourceLabels.add(source);
      if (pageName != null && pageName.isNotEmpty) {
        builder.pageNames.add(pageName);
      }
      if (navigationLocation != null && navigationLocation.isNotEmpty) {
        builder.navigationLocations.add(navigationLocation);
      }
    }

    for (final block in blocks) {
      final page = pageById[_text(block['page_id'])];
      final pageName = page == null
          ? 'Página desconocida'
          : (_text(page['title']).isEmpty
              ? _text(page['slug'])
              : _text(page['title']));
      final blockType = _text(block['block_type']);
      final blockData = _decodeBlockData(block['block_data']);
      for (final link in extractLinks(blockData)) {
        addUsage(
          rawHref: link.href,
          source: blockType.isEmpty
              ? link.fieldPath
              : '$blockType · ${link.fieldPath}',
          pageName: pageName,
        );
      }
    }

    for (final nav in navigation) {
      if (_text(nav['link_type']) == 'action') continue;
      final href = _navigationHref(nav, pageById);
      if (href.isEmpty) continue;
      addUsage(
        rawHref: href,
        source: 'Menú · ${_text(nav['label'])}',
        navigationLocation: _menuLocationLabel(_text(nav['menu_location'])),
      );
    }

    final items = usages.values.map((usage) {
      final destination = WebsiteDestination.parse(usage.href);
      return _resolveItem(
        destination: destination,
        usage: usage,
        pageBySlug: pageBySlug,
        categoryById: categoryById,
        productByToken: productByToken,
        markedProductCountByCategory: markedProductCountByCategory,
      );
    }).toList();

    items.sort((a, b) {
      final health = b.health.index.compareTo(a.health.index);
      if (health != 0) return health;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return WebsiteDestinationAudit(items: items);
  }

  static List<WebsiteExtractedLink> extractLinks(dynamic blockData) {
    final links = <WebsiteExtractedLink>[];

    void visit(dynamic value, String path) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final nextPath = path.isEmpty ? key : '$path.$key';
          final nested = entry.value;
          if (_linkKeys.contains(key.toLowerCase()) && nested is String) {
            final href = nested.trim();
            if (href.isNotEmpty) {
              links.add(WebsiteExtractedLink(href: href, fieldPath: nextPath));
            }
          } else {
            visit(nested, nextPath);
          }
        }
      } else if (value is List) {
        for (var index = 0; index < value.length; index += 1) {
          visit(value[index], '$path[$index]');
        }
      }
    }

    visit(blockData, '');
    return links;
  }

  WebsiteDestinationAuditItem _resolveItem({
    required WebsiteDestination destination,
    required _UsageBuilder usage,
    required Map<String, Map<String, dynamic>> pageBySlug,
    required Map<String, Map<String, dynamic>> categoryById,
    required Map<String, Map<String, dynamic>> productByToken,
    required Map<String, int> markedProductCountByCategory,
  }) {
    var title = destination.href;
    var health = WebsiteDestinationHealth.ready;
    var message = 'Destino listo.';
    var owner = WebsiteDestinationOwner.none;

    switch (destination.kind) {
      case WebsiteDestinationKind.none:
        health = WebsiteDestinationHealth.broken;
        message = 'El enlace está vacío.';
        owner = WebsiteDestinationOwner.advanced;
        break;
      case WebsiteDestinationKind.system:
        title = WebsiteDestination.systemRoutes[destination.reference] ??
            destination.href;
        message = 'Ruta del sistema disponible.';
        break;
      case WebsiteDestinationKind.page:
        owner = WebsiteDestinationOwner.pages;
        final page = pageBySlug[destination.reference];
        if (page == null) {
          health = WebsiteDestinationHealth.broken;
          message = 'No existe una página CMS con esta ruta.';
          title = destination.reference ?? destination.href;
        } else {
          title = _text(page['title']).isEmpty
              ? _text(page['slug'])
              : _text(page['title']);
          if (page['is_published'] != true) {
            health = WebsiteDestinationHealth.warning;
            message = 'La página existe, pero todavía está en borrador.';
          } else {
            message = 'Página CMS publicada.';
          }
        }
        break;
      case WebsiteDestinationKind.category:
        owner = WebsiteDestinationOwner.catalogCategories;
        final category = categoryById[destination.reference];
        if (category == null) {
          health = WebsiteDestinationHealth.broken;
          message =
              'La categoría enlazada ya no existe o usa una ruta antigua.';
          title = 'Categoría no encontrada';
        } else {
          title = _text(category['full_path']).isEmpty
              ? _text(category['name'])
              : _text(category['full_path']);
          final count =
              markedProductCountByCategory[destination.reference] ?? 0;
          if (category['is_active'] != true ||
              category['show_on_website'] != true) {
            health = WebsiteDestinationHealth.warning;
            message = 'La categoría está oculta del catálogo público.';
          } else if (count == 0) {
            health = WebsiteDestinationHealth.warning;
            message = 'La categoría está visible, pero no tiene productos web.';
          } else {
            message = 'Categoría visible con $count productos web.';
          }
        }
        break;
      case WebsiteDestinationKind.product:
        owner = WebsiteDestinationOwner.catalogProducts;
        final product = productByToken[destination.reference];
        if (product == null) {
          health = WebsiteDestinationHealth.broken;
          message = 'El producto enlazado ya no existe.';
          title = 'Producto no encontrado';
        } else {
          title = _text(product['name']).isEmpty
              ? _text(product['sku'])
              : _text(product['name']);
          if (!_isMarkedForWebsite(product)) {
            health = WebsiteDestinationHealth.warning;
            message = 'El producto existe, pero no está publicado en la web.';
          } else {
            message = 'Producto publicado en el catálogo web.';
          }
        }
        break;
      case WebsiteDestinationKind.anchor:
        owner = WebsiteDestinationOwner.advanced;
        title = '#${destination.reference ?? ''}';
        health = WebsiteDestinationHealth.warning;
        message = 'Verifica el ancla en la vista previa de la misma página.';
        break;
      case WebsiteDestinationKind.external:
        title = destination.reference ?? destination.href;
        message = 'URL externa; se valida al abrir la vista previa.';
        break;
      case WebsiteDestinationKind.custom:
        owner = WebsiteDestinationOwner.advanced;
        health = WebsiteDestinationHealth.warning;
        message =
            'Ruta interna avanzada: no está respaldada por una página o entidad reconocida.';
        break;
    }

    return WebsiteDestinationAuditItem(
      href: destination.href,
      kind: destination.kind,
      title: title,
      health: health,
      message: message,
      owner: owner,
      usageCount: usage.usageCount,
      pageNames: usage.pageNames.toList()..sort(),
      sourceLabels: usage.sourceLabels.toList()..sort(),
      navigationLocations: usage.navigationLocations.toList()..sort(),
    );
  }

  static dynamic _decodeBlockData(dynamic raw) {
    if (raw is Map || raw is List) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }

  static String _navigationHref(
    Map<String, dynamic> nav,
    Map<String, Map<String, dynamic>> pageById,
  ) {
    final type = _text(nav['link_type']);
    final value = _text(nav['link_value']);
    if (value.isEmpty) return '';
    if (type == 'category' && !value.startsWith('/')) {
      return '/productos?category=$value';
    }
    if (type == 'anchor') {
      return value.startsWith('#') ? value : '#$value';
    }
    if (type == 'page' && pageById.containsKey(value)) {
      final page = pageById[value]!;
      return WebsiteDestination.routeForPage(
        slug: _text(page['slug']),
        isHome: page['is_home'] == true,
      );
    }
    return value;
  }

  static List<Map<String, dynamic>> _maps(dynamic response) {
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  static bool _isMarkedForWebsite(Map<String, dynamic> product) {
    return product['is_active'] == true &&
        product['is_published'] == true &&
        product['show_on_website'] == true;
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static String _menuLocationLabel(String raw) {
    return switch (raw) {
      'footer' => 'Footer',
      'sidebar' => 'Menú lateral',
      _ => 'Header',
    };
  }
}

class WebsiteExtractedLink {
  const WebsiteExtractedLink({required this.href, required this.fieldPath});

  final String href;
  final String fieldPath;
}

class _UsageBuilder {
  _UsageBuilder(this.href);

  final String href;
  int usageCount = 0;
  final Set<String> pageNames = {};
  final Set<String> sourceLabels = {};
  final Set<String> navigationLocations = {};
}
