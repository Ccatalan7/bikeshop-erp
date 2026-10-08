import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';

import 'block_product_picks.dart';
import 'public_reads.dart';

/// The public reads as the editor's draft sees them: every shell carries the
/// unsaved [settings] over the saved ones (theme, header, footer, catalog
/// presentations, product page template…), and the page the editor has
/// open (the [home] or the page [document]) comes with its unsaved [blocks]
/// instead of the saved ones, also before it is published or saved for the
/// first time.
///
/// It lets `storefrontHandler` draw any public path from the draft with the
/// code that serves visits, so the «Vista HTML» shows exactly what the page
/// will be once saved.
class EditorDraftReads implements PublicReads {
  EditorDraftReads(
    this._saved, {
    this.home = false,
    required this.document,
    required this.title,
    required this.blocks,
    required this.settings,
    this.footerNavigation,
  });

  final PublicReads _saved;

  /// The open page: the home, or the page with the slug [document]; none
  /// when neither.
  final bool home;
  final String? document;

  /// The open page's title, for a page that is not saved yet.
  final String title;

  /// The open page's blocks as `website_blocks` keeps them.
  final List<Map<String, dynamic>> blocks;

  /// Unsaved `website_settings` values, by key.
  final Map<String, String> settings;

  /// The footer's menu as drafted (`website_navigation` rows), in place of
  /// the saved one; null when it has no unsaved change.
  final List<Map<String, dynamic>>? footerNavigation;

  Map<String, dynamic> _shell(Map<String, dynamic> saved) => {
    ...saved,
    'settings': {
      if (saved['settings'] case final Map<Object?, Object?> values)
        for (final entry in values.entries) entry.key.toString(): entry.value,
      ...settings,
    },
    if (footerNavigation case final footer?)
      'navigation': [
        if (saved['navigation'] case final List<Object?> rows)
          for (final row in rows)
            if (row is! Map || row['menu_location'] != 'footer') row,
        ...footer,
      ],
  };

  /// [saved] (the published page, or null) as the draft has it.
  Map<String, dynamic> _page(Map<String, dynamic>? saved) => {
    ...?saved,
    'id': saved?['id'] ?? 'draft',
    'slug': document ?? saved?['slug'] ?? '',
    'title': (saved?['title'] ?? '').toString().trim().isNotEmpty
        ? saved!['title']
        : title,
    if (home) 'is_home': true,
    'is_published': true,
    'website_blocks': blocks,
  };

  /// [read] of a page, its blocks replaced by the draft's (and the products
  /// they pick read for them) when [isOpen] says it is the page the editor
  /// has open. The open page that is not published yet ([mustBeOpen]) is
  /// drawn from the draft alone.
  Future<HomePageReads> _open(
    Future<HomePageReads> Function(PagePicker picks) read,
    PagePicker picks, {
    required bool Function(Map<String, dynamic>? saved) isOpen,
    required bool mustBeOpen,
  }) async {
    final data = await read(
      (saved) => picks(isOpen(saved) ? _page(saved) : saved),
    );
    if (data.page == null && mustBeOpen) {
      final drawn = await _saved.draftPage(_page(null), picks);
      return (
        shell: _shell(drawn.shell),
        payments: drawn.payments,
        page: drawn.page,
        products: drawn.products,
        brandRows: drawn.brandRows,
        thumbnails: drawn.thumbnails,
        lists: drawn.lists,
      );
    }
    return (
      shell: _shell(data.shell),
      payments: data.payments,
      page: data.page != null && isOpen(data.page)
          ? _page(data.page)
          : data.page,
      products: data.products,
      brandRows: data.brandRows,
      thumbnails: data.thumbnails,
      lists: data.lists,
    );
  }

  HomePageReads _withShell(HomePageReads data) => (
    shell: _shell(data.shell),
    payments: data.payments,
    page: data.page,
    products: data.products,
    brandRows: data.brandRows,
    thumbnails: data.thumbnails,
    lists: data.lists,
  );

  @override
  Future<ShellReads> shell() async {
    final data = await _saved.shell();
    return (shell: _shell(data.shell), payments: data.payments);
  }

  @override
  Future<HomePageReads> homePage(PagePicker picks) => _open(
    _saved.homePage,
    picks,
    // The editor names the home by its row as well (`{slug: "inicio"}`,
    // measured 2026-10-07): the published home with that slug is the open
    // page too.
    isOpen: (saved) => home || (document != null && saved?['slug'] == document),
    mustBeOpen: home,
  );

  @override
  Future<HomePageReads> websitePage(String slug, PagePicker picks) => _open(
    (inner) => _saved.websitePage(slug, inner),
    picks,
    isOpen: (_) => !home && slug == document,
    mustBeOpen: !home && slug == document,
  );

  @override
  Future<PolicyPagesReads> policyPages() async {
    final data = await _saved.policyPages();
    final open = home ? null : document;
    final pages = <Object?>[
      for (final row in data.pages)
        if (row is Map && row['slug'] == open && open != null)
          _page(Map<String, dynamic>.from(row))
        else
          row,
    ];
    if (open != null &&
        publicPolicySlugs.contains(open) &&
        !pages.any((row) => row is Map && row['slug'] == open)) {
      pages.add(_page(null));
    }
    return (shell: _shell(data.shell), payments: data.payments, pages: pages);
  }

  @override
  Future<ContactPageReads> contactPage() async {
    final data = await _saved.contactPage();
    return (
      shell: _shell(data.shell),
      payments: data.payments,
      page: !home && document == 'contacto' ? _page(data.page) : data.page,
    );
  }

  @override
  Future<ProductPageReads> productPage({String? sku, String? productId}) async {
    final data = await _saved.productPage(sku: sku, productId: productId);
    return (
      shell: _shell(data.shell),
      payments: data.payments,
      page: data.page,
    );
  }

  @override
  Future<CatalogReads> catalog(CatalogRequest request) =>
      _saved.catalog(request);

  @override
  Future<CartReads> cartProducts(List<String> productIds) =>
      _saved.cartProducts(productIds);

  @override
  Future<Map<String, dynamic>?> productById(String id) =>
      _saved.productById(id);

  @override
  Future<String?> productIdForAlias(String path) =>
      _saved.productIdForAlias(path);

  @override
  Future<HomePageReads> draftPage(
    Map<String, dynamic> page,
    PagePicker picks,
  ) async => _withShell(await _saved.draftPage(page, picks));

  @override
  Future<bool> canEditSite(String accessToken) =>
      _saved.canEditSite(accessToken);

  // A draft draws the store's pages, never an order or a customer's
  // account (`EditorDraft.publicPath` lets none through).

  @override
  Future<Object?> publicOrder(String accessToken) => _never();

  @override
  Future<CustomerPortalReads> customerPortal(
    String accessToken, {
    bool files = true,
  }) => _never();

  @override
  Future<Map<String, dynamic>?> customerProfile(String accessToken) => _never();

  @override
  Future<Map<String, dynamic>?> customerEnter(String accessToken) => _never();

  @override
  Future<bool> customerWrite(
    String accessToken, {
    required String method,
    required String table,
    Map<String, String> filters = const {},
    Map<String, Object?>? body,
  }) => _never();

  @override
  Future<CustomerAuthAnswer> customerAuth(
    String accessToken,
    CustomerAuthCall call, {
    Map<String, Object?>? body,
  }) => _never();

  @override
  Future<String?> customerJobFile(String accessToken, String reference) =>
      _never();

  @override
  Future<String> customerSignedObject(
    String accessToken,
    String bucket,
    String path, {
    required int expiresIn,
  }) => _never();

  @override
  Future<List<int>?> signedObjectBytes(String url, {required int maxBytes}) =>
      _never();

  @override
  Future<CustomerChatReads> customerChats(
    String accessToken, {
    String? conversationId,
    int window = 50,
  }) => _never();

  @override
  Future<Object?> customerChatCommand(
    String accessToken,
    String function,
    Map<String, Object?> params,
  ) => _never();

  @override
  Future<String?> customerChatFile(
    String accessToken, {
    required String conversationId,
    required String messageId,
  }) => _never();

  @override
  Future<bool> customerChatMessage(
    String accessToken, {
    required String conversationId,
    required String text,
    required String clientId,
  }) => _never();

  static Never _never() =>
      throw StateError('The editor\'s draft draws no customer page.');
}
