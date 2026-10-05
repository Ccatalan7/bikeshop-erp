import '../../modules/website/models/website_destination.dart';
import '../../modules/website/models/website_page_models.dart';

/// Public-route truth for editor-owned website pages.
///
/// `website_pages.is_published` is the only owner. Navigation, footer rows,
/// CTA blocks and other authored consumers may place a published page, but
/// they cannot make an absent or draft page public.
class PublicPagePublication {
  const PublicPagePublication({
    required this.publishedPaths,
    required this.isAuthoritative,
    this.managedPageIds = const <String>{},
    this.publishedPageIds = const <String>{},
    this.internalOrigins = const <Uri>[],
  });

  factory PublicPagePublication.resolve({
    required Iterable<WebsitePage> pages,
    required bool isAuthoritative,
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final pageList = List<WebsitePage>.unmodifiable(pages);
    if (!isAuthoritative) {
      return PublicPagePublication(
        publishedPaths: const <String>{},
        isAuthoritative: false,
        managedPageIds: Set<String>.unmodifiable({
          for (final page in pageList) page.id,
        }),
        publishedPageIds: const <String>{},
        internalOrigins: internalOrigins,
      );
    }
    return PublicPagePublication(
      publishedPaths: Set<String>.unmodifiable({
        for (final page in pageList)
          if (page.isPublished) page.fullPath,
      }),
      managedPageIds: Set<String>.unmodifiable({
        for (final page in pageList) page.id,
      }),
      publishedPageIds: Set<String>.unmodifiable({
        for (final page in pageList)
          if (page.isPublished) page.id,
      }),
      isAuthoritative: true,
      internalOrigins: internalOrigins,
    );
  }

  /// Clean routes whose public availability is owned by a `website_pages` row.
  ///
  /// `/contacto` belongs here: the static generator already treats it as an
  /// editor-owned page (`is_published` plus meaningful content) and excludes a
  /// draft from the sitemap, so leaving the runtime ungated let a route the
  /// owner never published stay linkable and indexable.
  ///
  /// `/servicios` is deliberately **absent**. It is a catalog collection whose
  /// owner is the root catalog presentation, not a `website_pages` row; gating
  /// it here would hand it a second publisher.
  static const managedCleanPaths = <String>{
    '/nosotros',
    '/terminos',
    '/privacidad',
    '/devoluciones',
    '/envios',
    '/contacto',
  };

  final Set<String> publishedPaths;
  final bool isAuthoritative;
  final Set<String> managedPageIds;
  final Set<String> publishedPageIds;
  final Iterable<Uri> internalOrigins;

  bool isPublishedPath(String path) => publishedPaths.contains(path);

  bool isManagedHref(String href) {
    final path = _normalizedPath(href);
    return path != null &&
        (managedCleanPaths.contains(path) ||
            path.startsWith('/pagina/') ||
            _managedPageId(path) != null);
  }

  bool allowsHref(String href) {
    final path = _normalizedPath(href);
    if (path == null) return true;
    final pageId = _managedPageId(path);
    if (pageId != null) {
      return isAuthoritative && publishedPageIds.contains(pageId);
    }
    if (!managedCleanPaths.contains(path) && !path.startsWith('/pagina/')) {
      return true;
    }
    if (!isAuthoritative) return false;
    return publishedPaths.contains(path);
  }

  bool canNavigate(WebsiteNavigation navigation) {
    if (_isUnresolvedPageIdNavigation(navigation)) return false;
    final href = navigation.href?.trim() ?? '';
    return href.isEmpty || allowsHref(href);
  }

  List<WebsiteNavigation> forDesktop(
    Iterable<WebsiteNavigation> navigation,
  ) =>
      _project(navigation, desktop: true);

  List<WebsiteNavigation> forMobile(
    Iterable<WebsiteNavigation> navigation,
  ) =>
      _project(navigation, desktop: false);

  List<WebsiteNavigation> forAllAudiences(
    Iterable<WebsiteNavigation> navigation,
  ) =>
      _project(navigation, desktop: null);

  List<WebsiteNavigation> _project(
    Iterable<WebsiteNavigation> navigation, {
    required bool? desktop,
  }) {
    return List<WebsiteNavigation>.unmodifiable(
      _projectLevel(
        navigation,
        desktop: desktop,
        depth: 0,
      ),
    );
  }

  List<WebsiteNavigation> _projectLevel(
    Iterable<WebsiteNavigation> navigation, {
    required bool? desktop,
    required int depth,
  }) {
    final projected = <WebsiteNavigation>[];
    for (final item in navigation) {
      if (!item.isVisible ||
          (desktop == true && !item.showOnDesktop) ||
          (desktop == false && !item.showOnMobile)) {
        continue;
      }
      final children = _projectLevel(
        item.children,
        desktop: desktop,
        depth: depth + 1,
      );
      final href = item.href?.trim() ?? '';
      if (!canNavigate(item) ||
          (href.isNotEmpty && isManagedHref(href) && !allowsHref(href))) {
        if (children.isEmpty) continue;
        if (depth == 0) {
          projected.add(_asStructuralGroup(item, children));
        } else {
          projected.addAll(children);
        }
        continue;
      }
      projected.add(
        item.copyWith(
          children: List<WebsiteNavigation>.unmodifiable(children),
        ),
      );
    }
    return projected;
  }

  WebsiteNavigation _asStructuralGroup(
    WebsiteNavigation source,
    List<WebsiteNavigation> children,
  ) {
    return WebsiteNavigation(
      id: source.id,
      tenantId: source.tenantId,
      menuLocation: source.menuLocation,
      label: source.label,
      icon: source.icon,
      linkType: NavLinkType.action,
      openInNewTab: false,
      parentId: source.parentId,
      orderIndex: source.orderIndex,
      isVisible: source.isVisible,
      showOnDesktop: source.showOnDesktop,
      showOnMobile: source.showOnMobile,
      cssClass: source.cssClass,
      highlight: source.highlight,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      children: List<WebsiteNavigation>.unmodifiable(children),
    );
  }

  String? _normalizedPath(String rawHref) {
    final normalized = WebsiteDestination.normalizeHref(
      rawHref,
      internalOrigins: internalOrigins,
    );
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.hasScheme || uri.host.isNotEmpty) {
      return null;
    }
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.startsWith('/pagina/')) {
      final segments = WebsiteDestination.pathSegments(path);
      if (segments.length != 2 || segments.last.trim().isEmpty) return null;
    }
    return path;
  }

  String? _managedPageId(String normalizedPath) {
    final segments = WebsiteDestination.pathSegments(normalizedPath);
    if (segments.length != 1) return null;
    final candidate = segments.single;
    return managedPageIds.contains(candidate) ? candidate : null;
  }

  bool _isUnresolvedPageIdNavigation(WebsiteNavigation navigation) {
    if (navigation.linkType != NavLinkType.page ||
        navigation.linkedPage != null) {
      return false;
    }
    final value = navigation.linkValue?.trim() ?? '';
    return RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
