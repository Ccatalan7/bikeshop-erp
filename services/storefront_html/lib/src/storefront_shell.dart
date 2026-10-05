import 'dart:convert';

import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_destination.dart';
import 'package:vinabike_public_core/modules/website/models/website_font_registry.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/models/website_seo_settings_aliases.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_color_value.dart';
import 'package:vinabike_public_core/public_store/models/public_category_route.dart';
import 'package:vinabike_public_core/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_public_core/public_store/models/public_payment_claims.dart';
import 'package:vinabike_public_core/public_store/services/public_category_publication.dart';
import 'package:vinabike_public_core/public_store/services/public_page_publication.dart';

/// What every page shares, read by `get_public_storefront_shell_v1` and
/// `get_public_checkout_capabilities`: public settings, menus, published
/// pages, active categories, shipping tiers and the payment methods the store
/// can confirm.
class StorefrontShell {
  StorefrontShell._({
    required this.settings,
    required this.navigation,
    required this.pagesById,
    required this.categories,
    required this.shippingTiers,
    required this.paymentClaims,
  });

  factory StorefrontShell.fromJson(
    Map<String, dynamic> json, {
    Object? checkoutCapabilities,
  }) {
    final rawSettings = json['settings'];
    return StorefrontShell._(
      settings: {
        if (rawSettings is Map)
          for (final entry in rawSettings.entries)
            entry.key.toString(): switch (entry.value) {
              null => '',
              final String text => text,
              final other => jsonEncode(other),
            },
      },
      navigation: [
        for (final row in rowsOf(json['navigation']))
          WebsiteNavigation.fromJson(row),
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
      pagesById: {
        for (final row in rowsOf(json['pages']))
          // The read returns only published pages, without the column.
          row['id'].toString(): WebsitePage.fromJson({
            ...row,
            'is_published': true,
          }),
      },
      categories: {
        for (final row in rowsOf(json['categories'])) row['id'].toString(): row,
      },
      shippingTiers: rowsOf(json['shipping_tiers']),
      paymentClaims: _paymentClaims(checkoutCapabilities),
    );
  }

  final Map<String, String> settings;
  final List<WebsiteNavigation> navigation;
  final Map<String, WebsitePage> pagesById;
  final Map<String, Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> shippingTiers;

  /// The methods the footer may name, from the server's own confirmation,
  /// as the Flutter footer decides them (`resolvePublicPaymentClaims`).
  final List<PublicCheckoutPaymentCode> paymentClaims;

  late final WebsiteCatalogPresentationRegistry presentations =
      WebsiteCatalogPresentationRegistry.decode(
        settings[websiteCatalogPresentationsSettingKey],
      );

  /// Which categories are public destinations: the flag, as the Flutter
  /// store's menus and catalog decide it.
  late final PublicCategoryPublication publication =
      PublicCategoryPublication.resolve(
        categories: [
          for (final row in categories.values)
            PublicCategoryDescriptor(
              id: row['id'].toString(),
              name: (row['name'] ?? '').toString(),
              fullPath: (row['full_path'] ?? '').toString(),
              showOnWebsite: row['show_on_website'] == true,
            ),
        ],
        navigation: navigation,
        presentationRegistry: presentations,
      );

  /// Which editor pages a link may lead to: a link to an unpublished policy
  /// or CMS page is hidden, as in the Flutter menus and footer.
  late final PublicPagePublication pagePublication =
      PublicPagePublication.resolve(
        pages: pagesById.values,
        isAuthoritative: true,
      );

  String setting(String key, [String fallback = '']) {
    final value = settings[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  /// The store's name as the Flutter layout shows it.
  String get storeName =>
      setting('seo_business_name', setting('store_name', 'Tienda'));

  String get storeDescription => setting('store_description');

  /// `site_published` = false shows a holding page to visitors, as Flutter.
  bool get sitePublished => setting('site_published', 'true') == 'true';

  String get headingFont =>
      WebsiteFontRegistry.resolveHeadingFont(settings['theme_heading_font']);
  String get bodyFont =>
      WebsiteFontRegistry.resolveBodyFont(settings['theme_body_font']);

  String get primaryColor => _hex(settings['theme_primary_color'], '#123f68');
  String get accentColor => _hex(settings['theme_accent_color'], '#ff7000');

  /// The Google Analytics tag configured in the editor, when valid.
  String? get googleAnalyticsId {
    final id = setting('seo_ga_id');
    return RegExp(r'^G-[A-Z0-9]+$').hasMatch(id) ? id : null;
  }

  /// WhatsApp digits for `wa.me`, from the editor's contact number.
  String get whatsappDigits =>
      setting('whatsapp').replaceAll(RegExp(r'[^0-9]'), '');

  /// The store's own origin for canonical URLs and structured data: the
  /// editor's `store_url`, normalized like the Flutter page and the snapshot
  /// generator do, or the service's configured origin when it is not set.
  String storeOrigin(String fallback) {
    final configured = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      settings['store_url'] ?? '',
    );
    return (configured.isNotEmpty ? configured : fallback).replaceAll(
      RegExp(r'/+$'),
      '',
    );
  }

  /// The host GA4 measures: the store origin's, without `www.`.
  String canonicalHost(String fallbackOrigin) {
    final host = Uri.tryParse(storeOrigin(fallbackOrigin))?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// The presentation the editor's «Catálogo web» gives a category, or the
  /// shared design with the slug of its name.
  WebsiteCatalogPresentation presentationFor(String id) =>
      presentations.forCategory(id) ??
      WebsiteCatalogPresentation.fallback(
        categoryId: id,
        categoryName: (categories[id]?['name'] ?? '').toString(),
      );

  /// The public path of a category.
  String categoryPath(String id, {bool services = false}) =>
      publicCategoryPath(presentation: presentationFor(id), services: services);

  bool isPublishedCategory(String id) => publication.isPublished(id);

  String categoryName(String id) => (categories[id]?['name'] ?? '').toString();

  String? parentOf(String id) {
    final parent = (categories[id]?['parent_id'] ?? '').toString();
    return parent.isEmpty ? null : parent;
  }

  /// Direct children in the Flutter catalog's order: `sort_order`, then name.
  List<String> childrenOfCategory(String? id) {
    final children = [
      for (final row in categories.values)
        if ((row['parent_id'] ?? '').toString() == (id ?? '')) row['id'].toString(),
    ]..sort(compareCategories);
    return children;
  }

  int compareCategories(String a, String b) {
    final byOrder = _sortOrder(a).compareTo(_sortOrder(b));
    return byOrder != 0 ? byOrder : categoryName(a).compareTo(categoryName(b));
  }

  int _sortOrder(String id) {
    final value = categories[id]?['sort_order'];
    return value is num ? value.toInt() : 0;
  }

  /// The category and every category below it: the catalog's default scope.
  List<String> subtreeOf(String id) {
    final result = <String>[];
    final pending = [id];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!seen.add(current)) continue;
      result.add(current);
      pending.addAll(childrenOfCategory(current));
    }
    return result;
  }

  /// The published category `/productos/categoria/<value>` (or an old
  /// `?category=<value>`) opens, with the Flutter catalog's rule
  /// (`resolvePublishedCategoryRouteValue`); [alias] when the value is an old
  /// slug the category kept.
  ({String id, bool alias})? resolveCategorySlug(String value) {
    final id = resolvePublishedCategoryRouteValue(
      value,
      presentations: presentations,
      categories: [
        for (final entry in categories.entries)
          (
            id: entry.key,
            name: (entry.value['name'] ?? '').toString(),
            fullPath: (entry.value['full_path'] ?? '').toString(),
            isPublished: isPublishedCategory(entry.key),
          ),
      ],
    );
    if (id == null) return null;
    return (
      id: id,
      alias: presentations.resolveSlug(value)?.matchedAlias == true,
    );
  }

  /// Menu items as the Flutter store draws them: a phone shows only
  /// `show_on_mobile`, a desktop only `show_on_desktop`, so an item hidden on
  /// both is never drawn. The view turns the rest into responsive classes.
  List<WebsiteNavigation> topLevel(MenuLocation location) => [
    for (final item in navigation)
      if (item.menuLocation == location &&
          item.parentId == null &&
          _shownSomewhere(item))
        item,
  ];

  List<WebsiteNavigation> childrenOf(WebsiteNavigation parent) => [
    for (final item in navigation)
      if (item.parentId == parent.id && _shownSomewhere(item)) item,
  ];

  static bool _shownSomewhere(WebsiteNavigation item) =>
      item.isVisible && (item.showOnDesktop || item.showOnMobile);

  /// Where a menu item leads, through the same models the Flutter store uses
  /// (`WebsiteNavigation.href`, `WebsitePage.fullPath`,
  /// `WebsiteDestination.parse`). A category link becomes its clean public
  /// path; any other filter in the link is kept. `null` hides the item: an
  /// action, a page that is not published, or a category that is not.
  String? hrefFor(WebsiteNavigation item) {
    var resolved = item;
    if (item.linkType == NavLinkType.page) {
      final value = item.linkValue?.trim() ?? '';
      final page = pagesById[value];
      if (page != null) {
        resolved = item.copyWith(linkedPage: page);
      } else if (_uuid.hasMatch(value)) {
        return null;
      }
    }
    if (!publication.allowsNavigationDestination(resolved) ||
        !pagePublication.canNavigate(resolved)) {
      return null;
    }
    final raw = resolved.href;
    if (raw == null) return null;
    final destination = WebsiteDestination.parse(raw);
    switch (destination.kind) {
      case WebsiteDestinationKind.none:
        return null;
      case WebsiteDestinationKind.category:
        final id = destination.reference ?? '';
        if (!categories.containsKey(id)) return destination.href;
        final uri = Uri.parse(destination.href);
        final rest = Map<String, String>.of(uri.queryParameters)
          ..remove('category');
        final path = categoryPath(
          id,
          services: uri.path.startsWith('/servicios'),
        );
        return rest.isEmpty
            ? path
            : Uri(path: path, queryParameters: rest).toString();
      default:
        return _publicPath(destination.href);
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// `/tienda/...` is the ERP's mounted copy of the store; a public link
  /// never leads there.
  static String _publicPath(String href) {
    if (href == '/tienda') return '/';
    if (href.startsWith('/tienda/') || href.startsWith('/tienda?')) {
      return href.substring('/tienda'.length);
    }
    return href;
  }

  static List<PublicCheckoutPaymentCode> _paymentClaims(Object? raw) {
    if (raw == null) return const [];
    try {
      return resolvePublicPaymentClaims(
        PublicCheckoutCapabilities.fromRpc(raw),
      );
    } on FormatException {
      // Unknown is not an answer: the footer names no method.
      return const [];
    }
  }
}

List<Map<String, dynamic>> rowsOf(Object? value) => [
  if (value is List)
    for (final row in value)
      if (row is Map) Map<String, dynamic>.from(row),
];

String? textOf(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

String _hex(String? raw, String fallback) {
  final argb = parseWebsiteThemeColorValue(raw ?? '');
  if (argb == null) return fallback;
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
