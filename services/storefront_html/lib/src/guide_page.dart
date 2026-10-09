import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/seo/public_guide.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// A guide as a card of the index or of «Sigue leyendo».
class GuideCard {
  const GuideCard({
    required this.title,
    required this.path,
    required this.description,
    required this.minutes,
    this.published,
  });

  /// A `website_pages` row of a guide, with its `website_blocks`.
  factory GuideCard.of(Map<String, dynamic> row) {
    final slug = (row['slug'] ?? '').toString().trim().toLowerCase();
    final title = (row['title'] ?? '').toString().trim();
    return GuideCard(
      title: title.isEmpty ? slug.replaceAll('-', ' ') : title,
      path: websiteGuidePath(slug),
      description: (row['meta_description'] ?? '').toString().trim(),
      minutes: guideReadingMinutes(row),
      published: websiteGuidePublishedAt(row),
    );
  }

  final String title;
  final String path;
  final String description;
  final int minutes;
  final DateTime? published;
}

/// Minutes to read a guide row's visible blocks.
int guideReadingMinutes(Map<String, dynamic> row) =>
    websiteGuideReadingMinutes(publicWebsitePageWordCount(guideBlockRows(row)));

/// A page row's `website_blocks`, normalized and in order.
List<Map<String, dynamic>> guideBlockRows(Map<String, dynamic> row) =>
    normalizeWebsiteBlockRows([
      if (row['website_blocks'] case final List<Object?> blocks)
        for (final block in blocks)
          if (block is Map) Map<String, dynamic>.from(block),
    ]);

/// The title of the guides' index: its editor page's, else «Guías».
String guidesIndexTitle(Map<String, dynamic>? indexPage) {
  final title = (indexPage?['title'] ?? '').toString().trim();
  return title.isEmpty ? 'Guías' : title;
}

/// What a guide's page draws around its blocks: the trail, its title and
/// summary, when it was published and how long it takes to read, and the
/// other guides after it.
class GuideChrome {
  const GuideChrome({
    required this.indexTitle,
    required this.title,
    required this.lead,
    required this.published,
    required this.updated,
    required this.minutes,
    required this.related,
  });

  final String indexTitle;
  final String title;
  final String lead;
  final DateTime? published;
  final DateTime? updated;
  final int minutes;
  final List<GuideCard> related;

  /// «Publicada el 8 de octubre de 2026 · 6 min de lectura», or
  /// «Actualizada el …» once it changed on a later day.
  String get metaLine {
    final publishedDay = published == null
        ? null
        : websiteGuideDateLabel(published!);
    final updatedDay = updated == null ? null : websiteGuideDateLabel(updated!);
    final date = updatedDay != null && updatedDay != publishedDay
        ? 'Actualizada el $updatedDay'
        : publishedDay == null
        ? null
        : 'Publicada el $publishedDay';
    return [?date, '$minutes min de lectura'].join(' · ');
  }
}

/// The guide's header: trail, eyebrow, title, summary and date.
/// Its column is the text blocks' own (800 px, centered), so the title and
/// the paragraphs start on the same line.
Component guideHeader(GuideChrome guide) => section(
  classes: 'guide-head article',
  [
    div([
      nav(
        classes: 'guide-crumbs',
        attributes: {'aria-label': 'Ruta'},
        [
          a(href: '/', [.text('Inicio')]),
          span(attributes: {'aria-hidden': 'true'}, [.text('/')]),
          a(href: websiteGuidesIndexPath, [.text(guide.indexTitle)]),
          span(attributes: {'aria-hidden': 'true'}, [.text('/')]),
          span(attributes: {'aria-current': 'page'}, [.text(guide.title)]),
        ],
      ),
      p(classes: 'guide-eyebrow', [.text(guide.indexTitle)]),
      h1(classes: 'guide-title', [.text(guide.title)]),
      if (guide.lead.isNotEmpty) p(classes: 'guide-lead', [.text(guide.lead)]),
      p(classes: 'guide-meta', [.text(guide.metaLine)]),
    ]),
  ],
);

/// «Sigue leyendo»: the other guides, newest first.
Component? guideRelated(GuideChrome guide) {
  if (guide.related.isEmpty) return null;
  return section(classes: 'guide-more', [
    div([
      h2([.text('Sigue leyendo')]),
      guideCards(guide.related),
    ]),
  ]);
}

/// The guides as cards linking to each one.
Component guideCards(
  List<GuideCard> cards, {
  bool featureFirst = false,
}) => ul(classes: 'guide-cards', [
  for (final (index, card) in cards.indexed)
    li(classes: featureFirst && index == 0 ? 'guide-card lead' : 'guide-card', [
      a(href: card.path, [
        span(classes: 'guide-card-k', [
          .text('${card.minutes} min de lectura'),
        ]),
        span(classes: 'guide-card-t', [.text(card.title)]),
        if (card.description.isNotEmpty)
          span(classes: 'guide-card-d', [.text(card.description)]),
      ]),
    ]),
]);

/// The index's header: trail, its page's title and description.
Component guidesIndexHeader({required String title, required String lead}) =>
    section(classes: 'guide-head', [
      div([
        nav(
          classes: 'guide-crumbs',
          attributes: {'aria-label': 'Ruta'},
          [
            a(href: '/', [.text('Inicio')]),
            span(attributes: {'aria-hidden': 'true'}, [.text('/')]),
            span(attributes: {'aria-current': 'page'}, [.text(title)]),
          ],
        ),
        h1(classes: 'guide-title', [.text(title)]),
        if (lead.isNotEmpty) p(classes: 'guide-lead', [.text(lead)]),
      ]),
    ]);

/// The index's list, or what it says while there is no guide.
Component guidesIndexList(List<GuideCard> cards) =>
    section(classes: 'guide-list', [
      div([
        if (cards.isEmpty)
          p(classes: 'guide-empty', [
            .text('Pronto publicaremos las primeras guías.'),
          ])
        else
          guideCards(cards, featureFirst: true),
      ]),
    ]);

/// The rules of the guides' header, cards and index. Colors and fonts are
/// the theme's (`--primary`, `--head`…), as every page of the store; the
/// featured card writes on the primary color in the ink the theme reads on
/// it (`onPrimary`), whatever color the store chose.
String guidePageCss(WebsiteThemeRoles theme) =>
    '''
.guide-head{background:var(--soft);padding:28px 16px 40px}
.guide-head>div,.guide-more>div,.guide-list>div{max-width:1120px;margin:0 auto}
.guide-head.article>div{max-width:800px}
.guide-crumbs{display:flex;flex-wrap:wrap;gap:8px;font:400 14px/1.4 var(--body);color:var(--muted)}
.guide-crumbs a{color:var(--muted)}
.guide-crumbs [aria-current]{color:var(--ink)}
.guide-eyebrow{margin:24px 0 0;font:600 14px/1.3 var(--head);letter-spacing:.14em;text-transform:uppercase;color:var(--primary)}
.guide-title{margin:10px 0 0;font:600 clamp(32px,5vw,52px)/1.06 var(--head);letter-spacing:-.01em;color:var(--ink);max-width:900px;text-wrap:balance}
.guide-head nav+.guide-title{margin-top:24px}
.guide-lead{margin:16px 0 0;font:400 clamp(17px,2.2vw,20px)/1.55 var(--body);color:var(--on-variant);max-width:760px}
.guide-meta{margin:16px 0 0;font:400 14px/1.4 var(--body);color:var(--muted)}
.guide-head+.blocks{padding-top:24px}
.guide-more{padding:48px 16px 56px}
.guide-more h2{margin:0;font:600 28px/1.2 var(--head);color:var(--ink)}
.guide-list{padding:40px 16px 56px}
.guide-cards{display:flex;flex-wrap:wrap;gap:16px;margin:20px 0 0;padding:0;list-style:none}
.guide-list .guide-cards{margin:0}
.guide-card{flex:1 1 260px;display:flex}
.guide-card a{flex:1;display:flex;flex-direction:column;gap:10px;border:1px solid var(--line);border-radius:var(--r);padding:22px;text-decoration:none;color:var(--ink);background:#fff;transition:border-color .15s ease}
.guide-card a:hover,.guide-card a:focus-visible{border-color:var(--primary)}
.guide-card-k{font:700 13px/1.3 var(--body);letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
.guide-card-t{font:600 22px/1.2 var(--head);color:var(--ink)}
.guide-card-d{font:400 16px/1.5 var(--body);color:var(--on-variant)}
.guide-card.lead{flex:2 1 520px}
.guide-card.lead a{background:${theme.primary.css};border-color:${theme.primary.css};padding:30px}
.guide-card.lead .guide-card-k{color:${theme.onPrimary.withAlpha(0.78).css}}
.guide-card.lead .guide-card-t{font-size:32px;color:${theme.onPrimary.css}}
.guide-card.lead .guide-card-d{color:${theme.onPrimary.withAlpha(0.86).css}}
.guide-empty{margin:0;font:400 18px/1.5 var(--body);color:var(--muted)}
''';
