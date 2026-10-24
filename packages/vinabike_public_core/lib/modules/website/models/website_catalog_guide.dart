/// What a category page says under its products, and the pages a category
/// offers for one of its filters («Cámaras aro 26»).
///
/// Both are what the stores Google ranks first put on a collection
/// (2026-10-23, owner: «a la altura de grandes empresas»): a buying guide and
/// its questions in the page's own words, and a real page with its own
/// address, title and text for each measure or brand people search for,
/// instead of a filtered copy Google is told to ignore. They live in the
/// category's presentation (`catalog_category_presentations_v1`), edited on
/// its page in the site editor.
library;

import 'website_action.dart';
import 'website_catalog_query.dart';

/// One question of a catalog page's guide and its answer.
class WebsiteCatalogQuestion {
  const WebsiteCatalogQuestion({required this.question, required this.answer});

  factory WebsiteCatalogQuestion.fromJson(Map<String, dynamic> json) =>
      WebsiteCatalogQuestion(
        question: (json['question'] ?? '').toString().trim(),
        answer: (json['answer'] ?? '').toString().trim(),
      );

  final String question;
  final String answer;

  /// A question without its answer, or an answer without its question, is
  /// still being written: the page shows neither.
  bool get isComplete => question.isNotEmpty && answer.isNotEmpty;

  Map<String, dynamic> toJson() => {'question': question, 'answer': answer};

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogQuestion &&
      other.question == question &&
      other.answer == answer;

  @override
  int get hashCode => Object.hash(question, answer);
}

/// The guide under a category's products: a title, its text (paragraphs
/// separated by a blank line), the questions a buyer asks and one link to
/// read more (the workshop's guide on the subject, a service).
class WebsiteCatalogGuide {
  const WebsiteCatalogGuide({
    this.title = '',
    this.text = '',
    this.questions = const [],
    this.link,
  });

  static const WebsiteCatalogGuide empty = WebsiteCatalogGuide();

  factory WebsiteCatalogGuide.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final questions = raw['questions'];
    return WebsiteCatalogGuide(
      title: (raw['title'] ?? '').toString().trim(),
      text: (raw['text'] ?? '').toString().trim(),
      questions: [
        if (questions is List)
          for (final item in questions.whereType<Map>())
            WebsiteCatalogQuestion.fromJson(Map<String, dynamic>.from(item)),
      ],
      link: switch (raw['link']) {
        final Map link => WebsiteActionValue(
          label: (link['label'] ?? '').toString(),
          href: (link['to'] ?? link['href'] ?? '').toString(),
        ),
        _ => null,
      },
    );
  }

  final String title;
  final String text;
  final List<WebsiteCatalogQuestion> questions;

  /// «Lee la guía: ¿por qué se pincha la cámara?», after the text.
  final WebsiteActionValue? link;

  /// The link the page shows: its words and where it goes, both written.
  WebsiteActionValue? get shownLink =>
      link != null &&
          link!.label.trim().isNotEmpty &&
          link!.href.trim().isNotEmpty
      ? link
      : null;

  bool get isEmpty =>
      title.trim().isEmpty &&
      text.trim().isEmpty &&
      questions.isEmpty &&
      link == null;

  /// The paragraphs of [text], as the page draws them.
  List<String> get paragraphs => [
    for (final paragraph in text.split(RegExp(r'\n\s*\n')))
      if (paragraph.replaceAll(RegExp(r'\s+'), ' ').trim() case final clean
          when clean.isNotEmpty)
        clean,
  ];

  /// The questions the page shows: both halves written.
  List<WebsiteCatalogQuestion> get shownQuestions => [
    for (final question in questions)
      if (question.isComplete) question,
  ];

  /// Whether the page draws anything for it.
  bool get isShown =>
      paragraphs.isNotEmpty || shownQuestions.isNotEmpty || shownLink != null;

  /// As saved: trimmed, without questions left blank on both halves and
  /// without a link half written.
  WebsiteCatalogGuide normalized() => WebsiteCatalogGuide(
    title: title.trim(),
    text: text.trim(),
    link: switch (shownLink) {
      final link? => WebsiteActionValue(
        label: link.label.trim(),
        href: link.href.trim(),
      ),
      null => null,
    },
    questions: [
      for (final question in questions)
        if (question.question.trim().isNotEmpty ||
            question.answer.trim().isNotEmpty)
          WebsiteCatalogQuestion(
            question: question.question.trim(),
            answer: question.answer.trim(),
          ),
    ],
  );

  WebsiteCatalogGuide copyWith({
    String? title,
    String? text,
    List<WebsiteCatalogQuestion>? questions,
    WebsiteActionValue? link,
    bool clearLink = false,
  }) => WebsiteCatalogGuide(
    title: title ?? this.title,
    text: text ?? this.text,
    questions: questions ?? this.questions,
    link: clearLink ? null : link ?? this.link,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'text': text,
    'questions': [for (final question in questions) question.toJson()],
    if (link case final link?) 'link': {'label': link.label, 'to': link.href},
  };

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogGuide &&
      other.title == title &&
      other.text == text &&
      other.link?.label == link?.label &&
      other.link?.href == link?.href &&
      _sameList(other.questions, questions);

  @override
  int get hashCode => Object.hash(
    title,
    text,
    link?.label,
    link?.href,
    Object.hashAll(questions),
  );
}

/// A category's page for one value of its filters: «Cámaras aro 26»
/// (`/productos/categoria/camaras/aro-26`), its products those of the
/// category with that measure or brand.
///
/// It is the editor's, never generated from every combination: Google indexes
/// what someone chose to publish, with its own title and text, and every
/// other filtered address keeps pointing to the category.
class WebsiteCatalogLanding {
  WebsiteCatalogLanding({
    required String slug,
    required String label,
    Map<String, List<String>> specFilters = const {},
    List<String> brandIds = const [],
    String heroTitle = '',
    String heroDescription = '',
    String seoTitle = '',
    String seoDescription = '',
    this.guide = WebsiteCatalogGuide.empty,
    this.allowIndexing = true,
  }) : slug = websiteCatalogLandingSlug(slug),
       label = label.trim(),
       specFilters = _normalizedSpecFilters(specFilters),
       brandIds = List.unmodifiable(
         {
           for (final id in brandIds)
             if (_uuid.hasMatch(id.trim())) id.trim().toLowerCase(),
         }.toList()..sort(),
       ),
       heroTitle = heroTitle.trim(),
       heroDescription = heroDescription.trim(),
       seoTitle = seoTitle.trim(),
       seoDescription = seoDescription.trim();

  factory WebsiteCatalogLanding.fromJson(Map<String, dynamic> json) {
    final rawFilters = json['spec_filters'];
    final rawBrands = json['brand_ids'];
    return WebsiteCatalogLanding(
      slug: (json['slug'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      specFilters: {
        if (rawFilters is Map)
          for (final entry in rawFilters.entries)
            entry.key.toString(): [
              if (entry.value is List)
                for (final value in entry.value as List) value.toString(),
            ],
      },
      brandIds: [
        if (rawBrands is List)
          for (final id in rawBrands) id.toString(),
      ],
      heroTitle: (json['hero_title'] ?? '').toString(),
      heroDescription: (json['hero_description'] ?? '').toString(),
      seoTitle: (json['seo_title'] ?? '').toString(),
      seoDescription: (json['seo_description'] ?? '').toString(),
      guide: WebsiteCatalogGuide.fromJson(json['guide']),
      allowIndexing: json['allow_indexing'] != false,
    );
  }

  /// The last step of its address, unique within its category.
  final String slug;

  /// What its link says beside the others («Aro 26»).
  final String label;

  /// The technical values it lists, by spec key, as a visitor's filter
  /// would ([WebsiteCatalogQuery.specFilters]).
  final Map<String, List<String>> specFilters;

  /// The brands it lists, when it is a brand's page.
  final List<String> brandIds;

  final String heroTitle;
  final String heroDescription;
  final String seoTitle;
  final String seoDescription;
  final WebsiteCatalogGuide guide;
  final bool allowIndexing;

  /// A page with nothing to narrow is its category again: it is not saved.
  bool get hasFilter => specFilters.isNotEmpty || brandIds.isNotEmpty;

  /// Its filters as a visitor's query on the category.
  WebsiteCatalogQuery get query =>
      WebsiteCatalogQuery(brandIds: brandIds, specFilters: specFilters);

  /// Whether a visitor's [visitor] query asks for exactly this page's
  /// products: the same filters and nothing else (no search, order or
  /// page), so its address can move to this page.
  bool matchesQuery(WebsiteCatalogQuery visitor) {
    if (!hasFilter) return false;
    final asked = visitor.toQueryParameters();
    final own = query.toQueryParameters();
    return asked.length == own.length &&
        own.entries.every((entry) => asked[entry.key] == entry.value);
  }

  WebsiteCatalogLanding copyWith({
    String? slug,
    String? label,
    Map<String, List<String>>? specFilters,
    List<String>? brandIds,
    String? heroTitle,
    String? heroDescription,
    String? seoTitle,
    String? seoDescription,
    WebsiteCatalogGuide? guide,
    bool? allowIndexing,
  }) => WebsiteCatalogLanding(
    slug: slug ?? this.slug,
    label: label ?? this.label,
    specFilters: specFilters ?? this.specFilters,
    brandIds: brandIds ?? this.brandIds,
    heroTitle: heroTitle ?? this.heroTitle,
    heroDescription: heroDescription ?? this.heroDescription,
    seoTitle: seoTitle ?? this.seoTitle,
    seoDescription: seoDescription ?? this.seoDescription,
    guide: guide ?? this.guide,
    allowIndexing: allowIndexing ?? this.allowIndexing,
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'label': label,
    'spec_filters': specFilters,
    'brand_ids': brandIds,
    'hero_title': heroTitle,
    'hero_description': heroDescription,
    'seo_title': seoTitle,
    'seo_description': seoDescription,
    'guide': guide.normalized().toJson(),
    'allow_indexing': allowIndexing,
  };

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogLanding &&
      other.slug == slug &&
      other.label == label &&
      _sameFilters(other.specFilters, specFilters) &&
      _sameList(other.brandIds, brandIds) &&
      other.heroTitle == heroTitle &&
      other.heroDescription == heroDescription &&
      other.seoTitle == seoTitle &&
      other.seoDescription == seoDescription &&
      other.guide == guide &&
      other.allowIndexing == allowIndexing;

  @override
  int get hashCode => Object.hash(
    slug,
    label,
    Object.hashAll(specFilters.keys),
    Object.hashAll(brandIds),
    heroTitle,
    heroDescription,
    seoTitle,
    seoDescription,
    guide,
    allowIndexing,
  );
}

/// Below this many products a filter's page is too thin to rank: it stays
/// out of Google and points to its category, as the filtered list does.
const int websiteCatalogLandingMinimumItems = 3;

/// The pages of a category as saved: complete, each address once.
List<WebsiteCatalogLanding> normalizedWebsiteCatalogLandings(
  Iterable<WebsiteCatalogLanding> landings,
) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final landing in landings)
      if (landing.slug.isNotEmpty &&
          landing.label.isNotEmpty &&
          landing.hasFilter &&
          seen.add(landing.slug))
        landing.copyWith(guide: landing.guide.normalized()),
  ]);
}

/// «Aro 29 / 700c» → `aro-29-700c`, as a category's address is written.
String websiteCatalogLandingSlug(String raw) {
  var value = raw.trim().toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  for (final entry in replacements.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  return value
      .replaceAll(RegExp(r'[^a-z0-9.]+'), '-')
      .replaceAll('.', '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// The filters as [WebsiteCatalogQuery] accepts them: a definition key and
/// values without commas (the address separates them with one), so a saved
/// page always turns into a valid query.
Map<String, List<String>> _normalizedSpecFilters(
  Map<String, List<String>> filters,
) {
  final result = <String, List<String>>{};
  for (final entry in filters.entries) {
    final key = entry.key.trim();
    if (!_specKey.hasMatch(key)) continue;
    final values = {
      for (final value in entry.value)
        if (value.trim().replaceAll(RegExp(r'\s+'), ' ') case final clean
            when clean.isNotEmpty && !clean.contains(','))
          clean,
    }.toList()..sort();
    if (values.isNotEmpty) result[key] = List.unmodifiable(values);
  }
  final keys = result.keys.toList()..sort();
  return Map.unmodifiable({for (final key in keys) key: result[key]!});
}

final RegExp _specKey = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _sameFilters(Map<String, List<String>> a, Map<String, List<String>> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !_sameList(entry.value, other)) return false;
  }
  return true;
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
