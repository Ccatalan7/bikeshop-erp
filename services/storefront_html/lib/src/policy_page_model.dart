import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_composition.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/seo/public_page_structured_data.dart';

import 'block_composition.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';
import 'website_page_css.dart';

/// The window widths at which Flutter's policy page changes what it decides
/// (static_policy_page.dart). Blocks show by the window (640 and 1024, as
/// every page); their data is read at the width of the column they are drawn
/// in: the window less 48 below 816, and beside the 240 + 64 side column
/// from 816 up (`isDesktop` is a frame of at least 768), at most 1120 wide.
const policyBands = <WidthBand>[
  WidthBand(
    index: 0,
    minWidth: 0,
    maxWidth: 640,
    sample: 400,
    canvasWidth: 352,
  ),
  WidthBand(
    index: 1,
    minWidth: 640,
    maxWidth: 688,
    sample: 660,
    canvasWidth: 612,
  ),
  WidthBand(
    index: 2,
    minWidth: 688,
    maxWidth: 816,
    sample: 750,
    canvasWidth: 702,
  ),
  WidthBand(
    index: 3,
    minWidth: 816,
    maxWidth: 992,
    sample: 900,
    canvasWidth: 548,
  ),
  WidthBand(
    index: 4,
    minWidth: 992,
    maxWidth: 1024,
    sample: 1000,
    canvasWidth: 648,
  ),
  WidthBand(
    index: 5,
    minWidth: 1024,
    maxWidth: null,
    sample: 1440,
    canvasWidth: 768,
  ),
];

/// One of the store's information pages (`/nosotros`, `/envios`…), read
/// and decided as Flutter's `StaticPolicyPage` does: the editor page's
/// blocks, its title and summary beside them, and the navigation to the
/// other information pages that have something to read.
class PolicyPageModel {
  PolicyPageModel._({
    required this.page,
    required this.meta,
    required this.slug,
    required this.available,
    required this.title,
    required this.summary,
    required this.navigation,
    required this.blocks,
    required this.theme,
  });

  factory PolicyPageModel.build({
    required PageContext page,
    required String slug,
    required PolicyPagesReads reads,
  }) {
    final shell = page.shell;
    final theme = WebsiteThemeRoles.resolve(shell.setting);
    final rowsBySlug = <String, Map<String, dynamic>>{
      for (final row in reads.pages)
        if (row is Map && row['slug'] is String)
          row['slug'] as String: Map<String, dynamic>.from(row),
    };
    // Read as the Flutter store reads them on load (`WebsiteService`): the
    // type's defaults under the saved values, legacy keys synchronized.
    List<Map<String, dynamic>> blocksOf(Map<String, dynamic>? row) =>
        normalizeWebsiteBlockRows([
          if (row?['website_blocks'] case final List<Object?> blocks)
            for (final block in blocks)
              if (block is Map) Map<String, dynamic>.from(block),
        ]);

    // A page links the others that a visitor can read: published (the read
    // returns no other) and with something to read.
    final navigation = [
      for (final candidate in publicPolicySlugs)
        if (hasMeaningfulPublicPolicyContent(blocksOf(rowsBySlug[candidate])))
          candidate,
    ];
    final row = rowsBySlug[slug];
    final rows = blocksOf(row);
    final words = PublicPolicyMeta.forSlug(slug, slug);
    final configuredTitle = (row?['title'] ?? '').toString().trim();
    final title = configuredTitle.isNotEmpty ? configuredTitle : words.title;
    final available = navigation.contains(slug);

    // The side summary is the page's own words as a visitor can read them
    // on some screen; Flutter reads the blocks of the current screen, the
    // same set unless a block is hidden on one of them.
    final reachable = WebsitePageComposition.projectPubliclyReachableBlocks(
      rows,
    ).map((block) => block.sourceBlock).toList(growable: false);
    final configuredSummary = (row?['meta_description'] ?? '')
        .toString()
        .trim();
    final ownWords = publicPolicyContentSummary(reachable);
    final summary = configuredSummary.isNotEmpty
        ? configuredSummary
        : ownWords.isNotEmpty
        ? ownWords
        : 'Información publicada por la tienda.';

    final storeName = shell.setting(
      'seo_business_name',
      shell.setting('store_name'),
    );
    final configuredSeoTitle = (row?['meta_title'] ?? '').toString().trim();
    final seoTitle = configuredSeoTitle.isNotEmpty
        ? configuredSeoTitle
        : storeName.isEmpty
        ? title
        : '$title | $storeName';
    // Flutter describes the page with all its blocks (static_policy_page
    // `_scheduleSeoUpdate`), visible or not on the current screen.
    final allWords = publicPolicyContentSummary(rows);
    final description = configuredSummary.isNotEmpty
        ? configuredSummary
        : allWords.isNotEmpty
        ? allWords
        : 'Esta página no tiene contenido público disponible en este momento.';
    final configuredImage = (row?['og_image_url'] ?? '').toString().trim();
    final canonicalUrl = '${page.storeUrl}/$slug';

    return PolicyPageModel._(
      page: page,
      meta: PageMeta(
        title: available
            ? seoTitle
            : '${words.title}${storeName.isEmpty ? '' : ' | $storeName'}',
        description: available
            ? description
            : 'Esta página no tiene contenido público disponible en este '
                  'momento.',
        canonicalUrl: canonicalUrl,
        indexable: available,
        imageUrl: configuredImage.isNotEmpty
            ? configuredImage
            : shell.setting('seo_og_image', shell.setting('logo_url')),
        structuredData: [
          if (available)
            buildPublicPageStructuredData(
              slug: slug,
              title: title,
              description: description,
              pageUrl: canonicalUrl,
              storeUrl: page.storeUrl,
              storeName: storeName,
            ),
        ],
        styles: policyPageCss(theme),
      ),
      slug: slug,
      available: available,
      title: title,
      summary: summary,
      navigation: navigation,
      blocks: available
          ? composeBlocks(
              rows: rows,
              bands: policyBands,
              sectionSpacing: theme.sectionSpacing,
              draft: page.showsHidden,
            )
          : const [],
      theme: theme,
    );
  }

  final PageContext page;
  final PageMeta meta;
  final String slug;

  /// Published and with something to read; otherwise the page says it has
  /// no public content and answers 404.
  final bool available;
  final String title;
  final String summary;

  /// The information pages a visitor can read, in [publicPolicySlugs] order.
  final List<String> navigation;
  final List<ComposedBlock> blocks;
  final WebsiteThemeRoles theme;

  /// The block types this page has that the HTML storefront does not draw
  /// yet (`x-storefront-uncovered`): such a page stays in Flutter when the
  /// routes open.
  late final Set<String> uncoveredTypes = {
    for (final composed in blocks)
      if (extractPublicPolicySections([composed.block.sourceBlock]).isEmpty &&
          !sharedBlockCovers(composed, coveredSharedBlockTypes))
        composed.block.blockType,
  };
}
