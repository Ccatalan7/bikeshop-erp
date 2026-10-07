import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_public_core/shared/models/public_product_visibility_policy.dart';

import 'block_composition.dart';
import 'block_product_picks.dart';
import 'home_page_model.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';
import 'website_page_css.dart';

/// A page the editor creates (`/pagina/<slug>`), as Flutter's
/// `DynamicWebsitePage` composes it: its blocks at the window's width, as
/// the home, under the header (only the home's header floats).
class EditorPageModel {
  EditorPageModel._({
    required this.page,
    required this.draft,
    required this.meta,
    required this.blocks,
    required this.theme,
    required this.products,
    required this.productLists,
    required this.brandRows,
    required this.thumbnails,
  });

  factory EditorPageModel.build({
    required PageContext page,
    required String slug,
    required HomePageReads reads,
    bool draft = false,
  }) {
    final row = reads.page!;
    final shell = page.shell;
    final theme = WebsiteThemeRoles.resolve(shell.setting);
    final rows = normalizeWebsiteBlockRows([
      if (row['website_blocks'] case final List<Object?> blocks)
        for (final block in blocks)
          if (block is Map) Map<String, dynamic>.from(block),
    ]);
    final policy = PublicProductVisibilityPolicy.hasAnySetting(shell.settings)
        ? PublicProductVisibilityPolicy.fromSettings(shell.settings)
        : null;
    final products = {
      for (final product in reads.products)
        if (product is Map)
          ...() {
            final parsed = Product.fromJson(Map<String, dynamic>.from(product));
            return policy == null || policy.allowsProduct(parsed)
                ? {parsed.id: parsed}
                : const <String, Product>{};
          }(),
    };

    // `_scheduleSeoUpdate`: the page's SEO title, or its title (the slug's
    // words without one) and the store's name; its description, the
    // store's, or the title.
    String text(String key) => (row[key] ?? '').toString().trim();
    final storeName = shell.setting(
      'seo_business_name',
      shell.setting('store_name'),
    );
    final configuredTitle = text('meta_title');
    final pageTitle = text('title');
    final effectiveTitle = pageTitle.isNotEmpty
        ? pageTitle
        : slug
              .replaceAll(RegExp(r'[-_]+'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final title = configuredTitle.isNotEmpty
        ? configuredTitle
        : storeName.isEmpty
        ? effectiveTitle
        : '$effectiveTitle | $storeName';
    final configuredDescription = text('meta_description');
    final storeDescription = shell.setting(
      'seo_meta_description',
      shell.setting('meta_description', shell.storeDescription),
    );
    final description = configuredDescription.isNotEmpty
        ? configuredDescription
        : storeDescription.isNotEmpty
        ? storeDescription
        : effectiveTitle;
    final configuredImage = text('og_image_url');

    // Indexed only with something a visitor can read (the same rule as the
    // information pages), at the path Flutter names.
    final contact = PublicWebsiteContactFacts(
      phone: shell.setting(
        'seo_phone',
        shell.setting('contact_phone', shell.setting('business_phone')),
      ),
      email: shell.setting('seo_email', shell.setting('contact_email')),
      address: <String>{
        shell.setting('seo_address_street', shell.setting('contact_address')),
        shell.setting(
          'seo_address_city',
          shell.setting('seo_address_locality'),
        ),
        shell.setting('seo_address_region'),
        shell.setting('seo_address_postal'),
        shell.setting('seo_address_country'),
      }.where((part) => part.isNotEmpty).join(', '),
    );
    final route = projectStorefrontSeoRoute(
      Uri(path: '/pagina/$slug'),
      isErpMounted: false,
      hasEligibleContent: hasMeaningfulPublicWebsitePageContent(
        rows,
        isContactPage: slug == 'contacto',
        contactFacts: contact,
      ),
    );

    return EditorPageModel._(
      draft: draft,
      page: page,
      meta: PageMeta(
        title: title,
        description: description,
        canonicalUrl: '${page.storeUrl}${route.canonicalPath}',
        indexable: route.isIndexable,
        imageUrl: configuredImage.isNotEmpty
            ? configuredImage
            : shell.setting('seo_og_image', shell.setting('logo_url')),
        styles: '${homePageCss(theme)}\n${editorPageEmptyCss(theme)}',
      ),
      blocks: composeBlocks(
        rows: rows,
        bands: homeBands,
        sectionSpacing: theme.sectionSpacing,
      ),
      theme: theme,
      products: products,
      productLists: blockProductLists(reads.lists, products),
      brandRows: reads.brandRows,
      thumbnails: reads.thumbnails,
    );
  }

  final PageContext page;

  /// The editor's draft ([editorDraftResponse]): each block names its id and
  /// a block the HTML does not draw yet says so in its place.
  final bool draft;
  final PageMeta meta;
  final List<ComposedBlock> blocks;
  final WebsiteThemeRoles theme;
  final Map<String, Product> products;

  /// Each list a block asks for, by [BlockProductList.key].
  final Map<String, List<Product>> productLists;
  final List<Object?> brandRows;
  final List<Object?> thumbnails;

  /// The block types the HTML storefront does not draw yet: the page stays
  /// in Flutter while it has any.
  late final Set<String> uncoveredTypes = {
    for (final composed in blocks)
      if (!sharedBlockCovers(composed, pageCoveredBlockTypes))
        composed.block.blockType,
  };
}
