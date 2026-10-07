import '../../modules/website/models/website_page_composition.dart';

/// The store's information pages (`/nosotros`, `/envios`…), in the order the
/// page's own navigation lists them.
const publicPolicySlugs = <String>[
  'nosotros',
  'envios',
  'devoluciones',
  'terminos',
  'privacidad',
];

/// The title a policy page falls back to when its editor page has none, and
/// the word its navigation uses. Each renderer owns its own icon.
class PublicPolicyMeta {
  const PublicPolicyMeta({required this.title, required this.navLabel});

  final String title;
  final String navLabel;

  static PublicPolicyMeta forSlug(String slug, String fallbackTitle) {
    return switch (slug) {
      'nosotros' => const PublicPolicyMeta(
        title: 'Sobre nosotros',
        navLabel: 'Nosotros',
      ),
      'envios' => const PublicPolicyMeta(title: 'Envíos', navLabel: 'Envíos'),
      'devoluciones' => const PublicPolicyMeta(
        title: 'Devoluciones',
        navLabel: 'Devoluciones',
      ),
      'terminos' => const PublicPolicyMeta(
        title: 'Términos y condiciones',
        navLabel: 'Términos',
      ),
      'privacidad' => const PublicPolicyMeta(
        title: 'Privacidad',
        navLabel: 'Privacidad',
      ),
      _ => PublicPolicyMeta(title: fallbackTitle, navLabel: fallbackTitle),
    };
  }
}

/// One section of a policy page: a block read as a title with paragraphs, or
/// with item cards (features and FAQ).
class PublicPolicySection {
  const PublicPolicySection(this.title, this.paragraphs, this.items);

  final String title;
  final List<String> paragraphs;
  final List<PublicPolicyItem> items;
}

class PublicPolicyItem {
  const PublicPolicyItem(this.title, this.body);

  final String title;
  final String body;
}

/// The sections a policy page draws from its blocks. A hero is never a
/// section, and a block with nothing a visitor can read gives none: the page
/// then draws that block as the editor does.
List<PublicPolicySection> extractPublicPolicySections(
  List<Map<String, dynamic>> source,
) {
  final sections = <PublicPolicySection>[];
  for (final block in source) {
    final type = (block['block_type'] ?? '').toString().toLowerCase();
    final data = block['block_data'] is Map
        ? Map<String, dynamic>.from(block['block_data'] as Map)
        : <String, dynamic>{};

    if (type == 'hero') continue;

    final title = _clean(data['title']);
    final subtitle = _clean(data['subtitle']);
    final content = _clean(data['content']);

    if (type == 'features') {
      final items = <PublicPolicyItem>[];
      final features = data['features'];
      if (features is List) {
        for (final feature in features) {
          if (feature is! Map) continue;
          final map = Map<String, dynamic>.from(feature);
          final itemTitle = _clean(map['title']);
          final itemBody = _clean(map['description']);
          if (itemTitle.isEmpty && itemBody.isEmpty) continue;
          items.add(PublicPolicyItem(itemTitle, itemBody));
        }
      }
      if (items.isNotEmpty) {
        sections.add(
          PublicPolicySection(
            title.isEmpty ? 'Puntos importantes' : title,
            const [],
            items,
          ),
        );
      }
      continue;
    }

    if (type == 'faq') {
      final items = <PublicPolicyItem>[];
      final faqItems = data['items'];
      if (faqItems is List) {
        for (final item in faqItems) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final question = _clean(map['question']);
          final answer = _clean(map['answer']);
          if (question.isEmpty || answer.isEmpty) continue;
          items.add(PublicPolicyItem(question, answer));
        }
      }
      if (items.isNotEmpty) {
        sections.add(
          PublicPolicySection(
            title.isEmpty ? 'Preguntas frecuentes' : title,
            const [],
            items,
          ),
        );
      }
      continue;
    }

    final paragraphs = [..._paragraphs(subtitle), ..._paragraphs(content)];
    if (type == 'contact') {
      final facts = publicContactFactStrings(data);
      if (facts.isNotEmpty) {
        sections.add(
          PublicPolicySection(
            title.isEmpty ? 'Información de contacto' : title,
            facts,
            const [],
          ),
        );
      }
      continue;
    }
    if (paragraphs.isNotEmpty) {
      sections.add(
        PublicPolicySection(
          title.isEmpty ? 'Detalle' : title,
          paragraphs,
          const [],
        ),
      );
    }
  }

  return sections;
}

/// The page's own words, up to 320 characters: the description when the
/// editor page has none.
String publicPolicyContentSummary(List<Map<String, dynamic>> source) {
  final fragments = <String>[];
  for (final section in extractPublicPolicySections(source)) {
    fragments.addAll(section.paragraphs);
    for (final item in section.items) {
      if (item.title.isNotEmpty) fragments.add(item.title);
      if (item.body.isNotEmpty) fragments.add(item.body);
    }
  }
  final summary = fragments.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (summary.length <= 320) return summary;
  return summary.substring(0, 320).trimRight();
}

/// Whether a policy page has something a visitor can read on at least one
/// public breakpoint.
bool hasMeaningfulPublicPolicyContent(List<Map<String, dynamic>> blocks) {
  final projected = WebsitePageComposition.projectPubliclyReachableBlocks(
    blocks,
  ).map((block) => block.sourceBlock).toList(growable: false);
  return extractPublicPolicySections(projected).isNotEmpty;
}

/// The store's contact data as the website settings own it.
class PublicWebsiteContactFacts {
  const PublicWebsiteContactFacts({
    this.phone = '',
    this.email = '',
    this.address = '',
    this.whatsapp = '',
    this.mapsUrl = '',
  });

  final String phone;
  final String email;
  final String address;

  /// The store's WhatsApp number (`whatsapp`), as written.
  final String whatsapp;

  /// Where the business is on Google Maps (`business_google_maps_url`, or
  /// `google_maps_url`).
  final String mapsUrl;

  /// [whatsapp]'s digits, as `wa.me` takes them.
  String get whatsappDigits => whatsapp.replaceAll(RegExp(r'[^0-9]'), '');

  /// The store's chat on WhatsApp, or '' when it has no number.
  String get whatsappHref =>
      whatsappDigits.isEmpty ? '' : 'https://wa.me/$whatsappDigits';

  bool get hasAny =>
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      address.trim().isNotEmpty;
}

/// What a contact block shows: its own phone, email and address when it has
/// any, otherwise the store's from the website settings (Configuración →
/// Contacto). A visitor never sees an empty card asking to fill it in.
PublicWebsiteContactFacts resolveWebsiteContactBlockFacts(
  Map<String, dynamic> data, {
  PublicWebsiteContactFacts site = const PublicWebsiteContactFacts(),
}) {
  final own = PublicWebsiteContactFacts(
    phone: (data['phone'] ?? '').toString().trim(),
    email: (data['email'] ?? '').toString().trim(),
    address: (data['address'] ?? '').toString().trim(),
  );
  if (own.hasAny) return own;
  return PublicWebsiteContactFacts(
    phone: site.phone.trim(),
    email: site.email.trim(),
    address: site.address.trim(),
  );
}

/// Runtime counterpart of the deploy-time crawler-content gate.
///
/// A title, image, link or CTA is presentation, not a complete public page.
/// Structured Features/FAQ blocks need real items, while Contacto may rely on
/// factual contact data owned by website settings.
bool hasMeaningfulPublicWebsitePageContent(
  List<Map<String, dynamic>> blocks, {
  bool isContactPage = false,
  PublicWebsiteContactFacts contactFacts = const PublicWebsiteContactFacts(),
}) {
  if (isContactPage && contactFacts.hasAny) return true;
  return WebsitePageComposition.projectPubliclyReachableBlocks(
    blocks,
  ).map((block) => block.sourceBlock).any(_hasMeaningfulPublicBlockContent);
}

bool _hasMeaningfulPublicBlockContent(Map<String, dynamic> block) {
  final type = (block['block_type'] ?? '').toString().trim().toLowerCase();
  final rawData = block['block_data'];
  if (rawData is! Map) return false;
  final data = Map<String, dynamic>.from(rawData);

  if (type == 'cta') return false;
  if (type == 'features') {
    final features = data['features'];
    if (features is! List) return false;
    return features.whereType<Map>().any((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      return _publicContentText(item['title']).isNotEmpty ||
          _publicContentText(item['description']).isNotEmpty;
    });
  }
  if (type == 'faq') {
    final items = data['items'];
    if (items is! List) return false;
    return items.whereType<Map>().any((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      return _publicContentText(item['question']).isNotEmpty &&
          _publicContentText(item['answer']).isNotEmpty;
    });
  }
  if (type == 'contact') {
    return publicContactFactStrings(data).isNotEmpty;
  }

  return _publicSemanticBodyFragments(data).isNotEmpty;
}

List<String> _publicSemanticBodyFragments(Map<String, dynamic> data) {
  const semanticBodyKeys = <String>{
    'answer',
    'body',
    'caption',
    'comment',
    'content',
    'description',
    'detail',
    'details',
    'html',
    'quote',
    'richtext',
    'subtitle',
    'text',
  };
  final fragments = <String>[];
  final seen = <String>{};

  void collect(dynamic value, {String? fieldName}) {
    if (value is Map) {
      for (final entry in value.entries) {
        collect(entry.value, fieldName: entry.key.toString());
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        collect(item, fieldName: fieldName);
      }
      return;
    }
    if (value is! String || fieldName == null) return;
    final normalizedField = fieldName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (!semanticBodyKeys.contains(normalizedField)) return;
    final text = _publicContentText(value);
    if (text.isEmpty || !seen.add(text.toLowerCase())) return;
    fragments.add(text);
  }

  collect(data);
  return fragments;
}

/// The address, email and phone values a block's data holds, at any depth.
List<String> publicContactFactStrings(Map<String, dynamic> data) {
  const factualKeys = <String>{
    'address',
    'contactaddress',
    'email',
    'contactemail',
    'phone',
    'telephone',
    'contactphone',
    'whatsapp',
  };
  final facts = <String>[];
  final seen = <String>{};

  void collect(dynamic value, {String? fieldName}) {
    if (value is Map) {
      for (final entry in value.entries) {
        collect(entry.value, fieldName: entry.key.toString());
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        collect(item, fieldName: fieldName);
      }
      return;
    }
    if (value is! String || fieldName == null) return;
    final normalizedField = fieldName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (!factualKeys.contains(normalizedField)) return;
    final fact = _publicContentText(value);
    if (fact.isNotEmpty && seen.add(fact.toLowerCase())) facts.add(fact);
  }

  collect(data);
  return facts;
}

String _publicContentText(dynamic value) {
  return (value ?? '')
      .toString()
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(r'\n', '\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _clean(dynamic value) {
  return (value ?? '')
      .toString()
      .replaceAll(r'\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

List<String> _paragraphs(String text) {
  final clean = _clean(text);
  if (clean.isEmpty) return const [];
  return clean
      .split(RegExp(r'\n\s*\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}
