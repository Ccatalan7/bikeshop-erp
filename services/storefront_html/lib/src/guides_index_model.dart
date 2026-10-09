import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/seo/public_guide.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';

import 'editor_page_model.dart';
import 'guide_page.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'website_page_css.dart';

/// `/guias`: the editor page `guias` (its title and description head the
/// page, its blocks follow the list; edited like any other page) around the
/// published guides, newest first. Without that page the index still lists
/// the guides under «Guías».
class GuidesIndexModel {
  GuidesIndexModel._({
    required this.page,
    required this.meta,
    required this.title,
    required this.lead,
    required this.cards,
    required this.intro,
  });

  factory GuidesIndexModel.build({
    required PageContext page,
    required HomePageReads reads,
    required List<Map<String, dynamic>> guides,
    bool draft = false,
  }) {
    final shell = page.shell;
    final row = reads.page;
    final intro = row == null
        ? null
        : EditorPageModel.build(
            page: page,
            slug: websiteGuidesIndexSlug,
            reads: reads,
            draft: draft,
          );
    String text(String key) => (row?[key] ?? '').toString().trim();
    final title = guidesIndexTitle(row);
    final storeName = shell.setting(
      'seo_business_name',
      shell.setting('store_name'),
    );
    final lead = text('meta_description');
    final cards = [for (final guide in guides) GuideCard.of(guide)];
    final description = lead.isNotEmpty
        ? lead
        : '$title de ${storeName.isEmpty ? 'la tienda' : storeName}.';
    // Indexed once it lists a guide: an empty index is not a page for Google.
    final route = projectStorefrontSeoRoute(
      Uri(path: websiteGuidesIndexPath),
      isErpMounted: false,
      hasEligibleContent: cards.isNotEmpty,
    );
    final theme = intro?.theme ?? WebsiteThemeRoles.resolve(shell.setting);
    final configuredTitle = text('meta_title');
    return GuidesIndexModel._(
      page: page,
      title: title,
      lead: lead,
      cards: cards,
      intro: intro,
      meta: PageMeta(
        title: configuredTitle.isNotEmpty
            ? configuredTitle
            : storeName.isEmpty
            ? title
            : '$title | $storeName',
        description: description,
        canonicalUrl: '${page.storeUrl}$websiteGuidesIndexPath',
        indexable: route.isIndexable,
        imageUrl: intro?.meta.imageUrl ?? shell.setting('seo_og_image'),
        structuredData: [
          buildPublicGuidesIndexStructuredData(
            storeUrl: page.storeUrl,
            title: title,
            description: description,
            guides: [
              for (final card in cards)
                (url: '${page.storeUrl}${card.path}', name: card.title),
            ],
          ),
        ],
        styles:
            '${homePageCss(theme)}\n${editorPageEmptyCss(theme)}\n'
            '${guidePageCss(theme)}',
      ),
    );
  }

  final PageContext page;
  final PageMeta meta;
  final String title;
  final String lead;
  final List<GuideCard> cards;

  /// The index's editor page, for its blocks; null when it does not exist.
  final EditorPageModel? intro;
}
