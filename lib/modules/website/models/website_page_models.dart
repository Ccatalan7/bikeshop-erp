/// Website page and navigation models for multi-page support
/// Part of the Odoo-style visual editor redesign (Dec 2025)
library;

/// Template types for website pages
enum PageTemplate {
  /// Default page with block editor
  defaultTemplate,
  /// Landing page with full-width sections
  landing,
  /// Blog-style page with sidebar
  blog,
  /// Product listing page (system)
  productList,
  /// Product detail page (system)
  productDetail,
  /// Cart/checkout page (system)
  cart,
}

/// Extension to convert PageTemplate to/from string
extension PageTemplateX on PageTemplate {
  String get value {
    switch (this) {
      case PageTemplate.defaultTemplate:
        return 'default';
      case PageTemplate.landing:
        return 'landing';
      case PageTemplate.blog:
        return 'blog';
      case PageTemplate.productList:
        return 'product-list';
      case PageTemplate.productDetail:
        return 'product-detail';
      case PageTemplate.cart:
        return 'cart';
    }
  }

  static PageTemplate fromString(String? value) {
    switch (value) {
      case 'landing':
        return PageTemplate.landing;
      case 'blog':
        return PageTemplate.blog;
      case 'product-list':
        return PageTemplate.productList;
      case 'product-detail':
        return PageTemplate.productDetail;
      case 'cart':
        return PageTemplate.cart;
      default:
        return PageTemplate.defaultTemplate;
    }
  }
}

/// Represents a website page that can contain blocks
class WebsitePage {
  final String id;
  final String tenantId;

  /// URL path for the page (e.g., 'inicio', 'servicios', 'contacto')
  final String slug;

  /// Page title shown in browser tab
  final String title;

  // SEO fields
  final String? metaTitle;
  final String? metaDescription;
  final String? metaKeywords;
  final String? ogImageUrl;

  // Page status
  final bool isPublished;
  final bool isHome;
  final bool isSystem;

  /// Page template type
  final PageTemplate template;

  // Timestamps
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  WebsitePage({
    required this.id,
    required this.tenantId,
    required this.slug,
    required this.title,
    this.metaTitle,
    this.metaDescription,
    this.metaKeywords,
    this.ogImageUrl,
    this.isPublished = false,
    this.isHome = false,
    this.isSystem = false,
    this.template = PageTemplate.defaultTemplate,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WebsitePage.fromJson(Map<String, dynamic> json) {
    return WebsitePage(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      metaTitle: json['meta_title'] as String?,
      metaDescription: json['meta_description'] as String?,
      metaKeywords: json['meta_keywords'] as String?,
      ogImageUrl: json['og_image_url'] as String?,
      isPublished: json['is_published'] as bool? ?? false,
      isHome: json['is_home'] as bool? ?? false,
      isSystem: json['is_system'] as bool? ?? false,
      template: PageTemplateX.fromString(json['template'] as String?),
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'slug': slug,
      'title': title,
      'meta_title': metaTitle,
      'meta_description': metaDescription,
      'meta_keywords': metaKeywords,
      'og_image_url': ogImageUrl,
      'is_published': isPublished,
      'is_home': isHome,
      'is_system': isSystem,
      'template': template.value,
      'published_at': publishedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Creates a JSON map for database insert (excludes id, timestamps)
  Map<String, dynamic> toInsertJson() {
    return {
      'slug': slug,
      'title': title,
      'meta_title': metaTitle,
      'meta_description': metaDescription,
      'meta_keywords': metaKeywords,
      'og_image_url': ogImageUrl,
      'is_published': isPublished,
      'is_home': isHome,
      'is_system': isSystem,
      'template': template.value,
    };
  }

  /// Creates a JSON map for database update
  Map<String, dynamic> toUpdateJson() {
    return {
      'slug': slug,
      'title': title,
      'meta_title': metaTitle,
      'meta_description': metaDescription,
      'meta_keywords': metaKeywords,
      'og_image_url': ogImageUrl,
      'is_published': isPublished,
      'is_home': isHome,
      // is_system should not be updated
      'template': template.value,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  WebsitePage copyWith({
    String? id,
    String? tenantId,
    String? slug,
    String? title,
    String? metaTitle,
    String? metaDescription,
    String? metaKeywords,
    String? ogImageUrl,
    bool? isPublished,
    bool? isHome,
    bool? isSystem,
    PageTemplate? template,
    DateTime? publishedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WebsitePage(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      metaTitle: metaTitle ?? this.metaTitle,
      metaDescription: metaDescription ?? this.metaDescription,
      metaKeywords: metaKeywords ?? this.metaKeywords,
      ogImageUrl: ogImageUrl ?? this.ogImageUrl,
      isPublished: isPublished ?? this.isPublished,
      isHome: isHome ?? this.isHome,
      isSystem: isSystem ?? this.isSystem,
      template: template ?? this.template,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Full URL path for this page
  String get fullPath => isHome ? '/' : '/$slug';

  /// Display name for UI (uses meta_title if available)
  String get displayTitle => metaTitle?.isNotEmpty == true ? metaTitle! : title;

  @override
  String toString() => 'WebsitePage($slug: $title)';
}

// ============================================================================
// NAVIGATION MODEL
// ============================================================================

/// Menu location types
enum MenuLocation {
  header,
  footer,
  sidebar,
}

extension MenuLocationX on MenuLocation {
  String get value {
    switch (this) {
      case MenuLocation.header:
        return 'header';
      case MenuLocation.footer:
        return 'footer';
      case MenuLocation.sidebar:
        return 'sidebar';
    }
  }

  static MenuLocation fromString(String? value) {
    switch (value) {
      case 'footer':
        return MenuLocation.footer;
      case 'sidebar':
        return MenuLocation.sidebar;
      default:
        return MenuLocation.header;
    }
  }
}

/// Link type for navigation items
enum NavLinkType {
  /// Links to a website page
  page,
  /// Links to an external URL
  external,
  /// Links to an anchor on the current page
  anchor,
  /// Links to a product category
  category,
  /// Triggers an action (e.g., 'open_cart', 'open_search')
  action,
}

extension NavLinkTypeX on NavLinkType {
  String get value {
    switch (this) {
      case NavLinkType.page:
        return 'page';
      case NavLinkType.external:
        return 'external';
      case NavLinkType.anchor:
        return 'anchor';
      case NavLinkType.category:
        return 'category';
      case NavLinkType.action:
        return 'action';
    }
  }

  static NavLinkType fromString(String? value) {
    switch (value) {
      case 'external':
        return NavLinkType.external;
      case 'anchor':
        return NavLinkType.anchor;
      case 'category':
        return NavLinkType.category;
      case 'action':
        return NavLinkType.action;
      default:
        return NavLinkType.page;
    }
  }
}

/// Represents a navigation menu item
class WebsiteNavigation {
  final String id;
  final String tenantId;

  /// Where this item appears
  final MenuLocation menuLocation;

  /// Display text
  final String label;

  /// Optional icon name (Material icon)
  final String? icon;

  /// Type of link
  final NavLinkType linkType;

  /// Link target (page_id, URL, #anchor, category_id, or action name)
  final String? linkValue;

  /// Whether to open in new tab (for external links)
  final bool openInNewTab;

  /// Parent item ID (for dropdown menus)
  final String? parentId;

  /// Sort order
  final int orderIndex;

  /// Visibility
  final bool isVisible;
  final bool showOnDesktop;
  final bool showOnMobile;

  /// Styling
  final String? cssClass;
  final bool highlight;

  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;

  // Runtime fields (not persisted)
  /// Child items (populated during fetch)
  List<WebsiteNavigation> children;

  /// Referenced page (populated during fetch)
  WebsitePage? linkedPage;

  WebsiteNavigation({
    required this.id,
    required this.tenantId,
    this.menuLocation = MenuLocation.header,
    required this.label,
    this.icon,
    this.linkType = NavLinkType.page,
    this.linkValue,
    this.openInNewTab = false,
    this.parentId,
    this.orderIndex = 0,
    this.isVisible = true,
    this.showOnDesktop = true,
    this.showOnMobile = true,
    this.cssClass,
    this.highlight = false,
    required this.createdAt,
    required this.updatedAt,
    List<WebsiteNavigation>? children,
    this.linkedPage,
  }) : children = children ?? [];

  factory WebsiteNavigation.fromJson(Map<String, dynamic> json) {
    return WebsiteNavigation(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      menuLocation: MenuLocationX.fromString(json['menu_location'] as String?),
      label: json['label'] as String? ?? '',
      icon: json['icon'] as String?,
      linkType: NavLinkTypeX.fromString(json['link_type'] as String?),
      linkValue: json['link_value'] as String?,
      openInNewTab: json['open_in_new_tab'] as bool? ?? false,
      parentId: json['parent_id'] as String?,
      orderIndex: json['order_index'] as int? ?? 0,
      isVisible: json['is_visible'] as bool? ?? true,
      showOnDesktop: json['show_on_desktop'] as bool? ?? true,
      showOnMobile: json['show_on_mobile'] as bool? ?? true,
      cssClass: json['css_class'] as String?,
      highlight: json['highlight'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'menu_location': menuLocation.value,
      'label': label,
      'icon': icon,
      'link_type': linkType.value,
      'link_value': linkValue,
      'open_in_new_tab': openInNewTab,
      'parent_id': parentId,
      'order_index': orderIndex,
      'is_visible': isVisible,
      'show_on_desktop': showOnDesktop,
      'show_on_mobile': showOnMobile,
      'css_class': cssClass,
      'highlight': highlight,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Creates a JSON map for database insert
  Map<String, dynamic> toInsertJson() {
    return {
      'menu_location': menuLocation.value,
      'label': label,
      'icon': icon,
      'link_type': linkType.value,
      'link_value': linkValue,
      'open_in_new_tab': openInNewTab,
      'parent_id': parentId,
      'order_index': orderIndex,
      'is_visible': isVisible,
      'show_on_desktop': showOnDesktop,
      'show_on_mobile': showOnMobile,
      'css_class': cssClass,
      'highlight': highlight,
    };
  }

  /// Creates a JSON map for database update
  Map<String, dynamic> toUpdateJson() {
    return {
      'menu_location': menuLocation.value,
      'label': label,
      'icon': icon,
      'link_type': linkType.value,
      'link_value': linkValue,
      'open_in_new_tab': openInNewTab,
      'parent_id': parentId,
      'order_index': orderIndex,
      'is_visible': isVisible,
      'show_on_desktop': showOnDesktop,
      'show_on_mobile': showOnMobile,
      'css_class': cssClass,
      'highlight': highlight,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  WebsiteNavigation copyWith({
    String? id,
    String? tenantId,
    MenuLocation? menuLocation,
    String? label,
    String? icon,
    NavLinkType? linkType,
    String? linkValue,
    bool? openInNewTab,
    String? parentId,
    int? orderIndex,
    bool? isVisible,
    bool? showOnDesktop,
    bool? showOnMobile,
    String? cssClass,
    bool? highlight,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<WebsiteNavigation>? children,
    WebsitePage? linkedPage,
  }) {
    return WebsiteNavigation(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      menuLocation: menuLocation ?? this.menuLocation,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      linkType: linkType ?? this.linkType,
      linkValue: linkValue ?? this.linkValue,
      openInNewTab: openInNewTab ?? this.openInNewTab,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      isVisible: isVisible ?? this.isVisible,
      showOnDesktop: showOnDesktop ?? this.showOnDesktop,
      showOnMobile: showOnMobile ?? this.showOnMobile,
      cssClass: cssClass ?? this.cssClass,
      highlight: highlight ?? this.highlight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      children: children ?? this.children,
      linkedPage: linkedPage ?? this.linkedPage,
    );
  }

  /// Whether this item has children (is a dropdown parent)
  bool get hasChildren => children.isNotEmpty;

  /// Whether this is a top-level item
  bool get isTopLevel => parentId == null;

  /// Computed href based on link type
  String? get href {
    switch (linkType) {
      case NavLinkType.page:
        if (linkedPage != null) return linkedPage!.fullPath;
        final v = linkValue?.trim();
        if (v == null || v.isEmpty) return '/';
        // Newer UI stores '/slug' (or sometimes 'slug') directly.
        if (v.startsWith('/')) return v;
        return '/$v';
      case NavLinkType.external:
        return linkValue;
      case NavLinkType.anchor:
        return linkValue?.startsWith('#') == true ? linkValue : '#$linkValue';
      case NavLinkType.category:
        return '/productos?categoria=$linkValue';
      case NavLinkType.action:
        return null; // Actions are handled by onClick
    }
  }

  @override
  String toString() => 'WebsiteNavigation($label -> $linkType:$linkValue)';
}
