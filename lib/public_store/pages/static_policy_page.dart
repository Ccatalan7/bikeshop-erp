import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/models/website_editor_capability.dart';
import '../../modules/website/models/website_page_composition.dart';
import '../../modules/website/models/website_page_models.dart';
import '../../modules/website/models/website_responsive_authoring.dart';
import '../../modules/website/models/website_seo_settings_aliases.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/theme/website_resolved_theme.dart';
import '../../modules/website/widgets/website_editor_document_binding.dart';
import '../../shared/utils/seo_helper.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';
import '../widgets/page_composition.dart';
import '../widgets/public_store_layout.dart';

/// Policy page renderer that uses WebsiteService for caching.
/// Much simpler than the old StaticPolicyPage - no duplicate DB logic!
class StaticPolicyPage extends StatefulWidget {
  final String slug;
  final String fallbackTitle;

  const StaticPolicyPage(
      {super.key, required this.slug, required this.fallbackTitle});

  @override
  State<StaticPolicyPage> createState() => _StaticPolicyPageState();
}

class _PublicPolicyView extends StatelessWidget {
  final String slug;
  final String fallbackTitle;
  final List<Map<String, dynamic>> blocks;
  final Widget composedContent;
  final WebsitePage? page;
  final Set<String> availablePolicySlugs;
  final bool isStale;

  const _PublicPolicyView({
    required this.slug,
    required this.fallbackTitle,
    required this.blocks,
    required this.composedContent,
    required this.page,
    required this.availablePolicySlugs,
    required this.isStale,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final meta = _PolicyMeta.forSlug(slug, fallbackTitle);
    final configuredTitle = page?.title.trim() ?? '';
    final configuredSummary = page?.metaDescription?.trim() ?? '';
    final summaryFromContent = contentSummary(blocks);
    final title = configuredTitle.isNotEmpty ? configuredTitle : meta.title;
    final summary = configuredSummary.isNotEmpty
        ? configuredSummary
        : summaryFromContent.isNotEmpty
            ? summaryFromContent
            : 'Información publicada por la tienda.';
    final showNavigation = availablePolicySlugs.isNotEmpty;

    return Container(
      key: const ValueKey<String>('static-policy-public-view'),
      width: double.infinity,
      color: colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 768;

                if (!isDesktop) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isStale) ...[
                        const _PolicyFreshnessNotice(),
                        const SizedBox(height: 24),
                      ],
                      _PolicyHero(
                        meta: meta,
                        title: title,
                        summary: summary,
                      ),
                      if (showNavigation) ...[
                        const SizedBox(height: 32),
                        _PolicyNav(
                          currentSlug: slug,
                          availableSlugs: availablePolicySlugs,
                          isDesktop: false,
                        ),
                      ],
                      const SizedBox(height: 32),
                      composedContent,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 240,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isStale) ...[
                            const _PolicyFreshnessNotice(),
                            const SizedBox(height: 24),
                          ],
                          _PolicyHero(
                            meta: meta,
                            title: title,
                            summary: summary,
                          ),
                          if (showNavigation) ...[
                            const SizedBox(height: 32),
                            _PolicyNav(
                              currentSlug: slug,
                              availableSlugs: availablePolicySlugs,
                              isDesktop: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 64),
                    Expanded(
                      child: composedContent,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static List<_PolicySection> extractSections(
    List<Map<String, dynamic>> source,
  ) {
    final sections = <_PolicySection>[];
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
        final items = <_PolicyItem>[];
        final features = data['features'];
        if (features is List) {
          for (final feature in features) {
            if (feature is! Map) continue;
            final map = Map<String, dynamic>.from(feature);
            final itemTitle = _clean(map['title']);
            final itemBody = _clean(map['description']);
            if (itemTitle.isEmpty && itemBody.isEmpty) continue;
            items.add(_PolicyItem(itemTitle, itemBody));
          }
        }
        if (items.isNotEmpty) {
          sections.add(_PolicySection(
            title.isEmpty ? 'Puntos importantes' : title,
            const [],
            items,
          ));
        }
        continue;
      }

      if (type == 'faq') {
        final items = <_PolicyItem>[];
        final faqItems = data['items'];
        if (faqItems is List) {
          for (final item in faqItems) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final question = _clean(map['question']);
            final answer = _clean(map['answer']);
            if (question.isEmpty || answer.isEmpty) continue;
            items.add(_PolicyItem(question, answer));
          }
        }
        if (items.isNotEmpty) {
          sections.add(_PolicySection(
            title.isEmpty ? 'Preguntas frecuentes' : title,
            const [],
            items,
          ));
        }
        continue;
      }

      final paragraphs = [
        ..._paragraphs(subtitle),
        ..._paragraphs(content),
      ];
      if (type == 'contact') {
        final facts = _publicContactFactStrings(data);
        if (facts.isNotEmpty) {
          sections.add(_PolicySection(
            title.isEmpty ? 'Información de contacto' : title,
            facts,
            const [],
          ));
        }
        continue;
      }
      if (paragraphs.isNotEmpty) {
        sections.add(_PolicySection(
          title.isEmpty ? 'Detalle' : title,
          paragraphs,
          const [],
        ));
      }
    }

    return sections;
  }

  static String contentSummary(List<Map<String, dynamic>> source) {
    final fragments = <String>[];
    for (final section in extractSections(source)) {
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

  static String _clean(dynamic value) {
    return (value ?? '')
        .toString()
        .replaceAll(r'\n', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static List<String> _paragraphs(String text) {
    final clean = _clean(text);
    if (clean.isEmpty) return const [];
    return clean
        .split(RegExp(r'\n\s*\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

class _PolicyHero extends StatelessWidget {
  final _PolicyMeta meta;
  final String title;
  final String summary;

  const _PolicyHero({
    required this.meta,
    required this.title,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(meta.icon, color: meta.color, size: 24),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: TextStyle(
            fontFamily: null,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          summary,
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PolicyFreshnessNotice extends StatelessWidget {
  const _PolicyFreshnessNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey<String>('static-policy-freshness-notice'),
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFFED7AA)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sync_outlined,
              size: 20,
              color: Color(0xFF9A3412),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Estamos verificando esta información. La última versión '
                'disponible podría cambiar.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF7C2D12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyNav extends StatelessWidget {
  final String currentSlug;
  final Set<String> availableSlugs;
  final bool isDesktop;

  const _PolicyNav({
    required this.currentSlug,
    required this.availableSlugs,
    this.isDesktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const orderedSlugs = [
      'nosotros',
      'envios',
      'devoluciones',
      'terminos',
      'privacidad'
    ];
    final slugs =
        orderedSlugs.where(availableSlugs.contains).toList(growable: false);

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final slug in slugs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NavButton(
                slug: slug,
                isSelected: currentSlug == slug,
                onTap: () =>
                    PublicStoreLayout.navigateToHref(context, '/$slug'),
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final slug in slugs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ChoiceChip(
                  selected: currentSlug == slug,
                  label: Text(_PolicyMeta.forSlug(slug, slug).navLabel),
                  avatar: Icon(
                    _PolicyMeta.forSlug(slug, slug).icon,
                    size: 16,
                    color: currentSlug == slug
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (_) =>
                      PublicStoreLayout.navigateToHref(context, '/$slug'),
                  selectedColor: colorScheme.surfaceContainerLow,
                  backgroundColor: colorScheme.surface,
                  side: BorderSide(
                    color: currentSlug == slug
                        ? Colors.transparent
                        : colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        currentSlug == slug ? FontWeight.w700 : FontWeight.w500,
                    color: currentSlug == slug
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String slug;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({
    required this.slug,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _PolicyMeta.forSlug(slug, slug);
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: colorScheme.surfaceContainerLow,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected ? colorScheme.surfaceContainerLow : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              meta.icon,
              size: 18,
              color: isSelected
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                meta.navLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyContent extends StatelessWidget {
  final List<_PolicySection> sections;

  const _PolicyContent({required this.sections});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 48),
          Text(
            sections[i].title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          for (final paragraph in sections[i].paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                paragraph,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.65,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (sections[i].items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in sections[i].items)
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 260, maxWidth: 500),
                      child: _PolicyItemCard(item: item),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PolicyItemCard extends StatelessWidget {
  final _PolicyItem item;

  const _PolicyItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.title.isNotEmpty)
            Text(
              item.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          if (item.title.isNotEmpty && item.body.isNotEmpty)
            const SizedBox(height: 8),
          if (item.body.isNotEmpty)
            Text(
              item.body,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicPolicyUnavailableView extends StatelessWidget {
  final String title;

  const _PublicPolicyUnavailableView({required this.title});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('static-policy-unavailable-view'),
      width: double.infinity,
      color: colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Esta página no tiene contenido público disponible en este '
                  'momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: OutlinedButton(
                    onPressed: () => PublicStoreLayout.navigateToHref(
                      context,
                      '/productos',
                    ),
                    child: const Text('Ver productos'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PublicWebsiteContactFacts {
  const PublicWebsiteContactFacts({
    this.phone = '',
    this.email = '',
    this.address = '',
  });

  final String phone;
  final String email;
  final String address;

  bool get hasAny =>
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      address.trim().isNotEmpty;
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
  return WebsitePageComposition.projectPubliclyReachableBlocks(blocks)
      .map((block) => block.sourceBlock)
      .any(_hasMeaningfulPublicWebsiteBlockContent);
}

bool _hasMeaningfulPublicWebsiteBlockContent(Map<String, dynamic> block) {
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
    return _publicContactFactStrings(data).isNotEmpty;
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
    final normalizedField =
        fieldName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!semanticBodyKeys.contains(normalizedField)) return;
    final text = _publicContentText(value);
    if (text.isEmpty || !seen.add(text.toLowerCase())) return;
    fragments.add(text);
  }

  collect(data);
  return fragments;
}

List<String> _publicContactFactStrings(Map<String, dynamic> data) {
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
    final normalizedField =
        fieldName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

bool hasMeaningfulPublicPolicyContent(
  List<Map<String, dynamic>> blocks,
) {
  final projected = WebsitePageComposition.projectPubliclyReachableBlocks(
    blocks,
  ).map((block) => block.sourceBlock).toList(growable: false);
  return _PublicPolicyView.extractSections(projected).isNotEmpty;
}

enum StaticPolicyRetainedProvenance {
  none,
  editor,
  publicOrigin,
  publicStale,
}

/// Pure public-trust projection shared by rendering, SEO and tests.
///
/// Cached editor reads are useful for authoring but never establish public
/// publication or indexability. A stale public snapshot may remain visible
/// with a freshness notice, while only origin-confirmed content is canonical.
class StaticPolicyPublicationProjection {
  const StaticPolicyPublicationProjection({
    required this.hasOwner,
    required this.ownerIsPublished,
    required this.hasEligibleContent,
    required this.provenance,
  });

  factory StaticPolicyPublicationProjection.fromLoadResult(
    PageSnapshotLoadResult result,
  ) {
    final snapshot = result.snapshot;
    return StaticPolicyPublicationProjection(
      hasOwner: snapshot != null,
      ownerIsPublished:
          result.isOriginConfirmed && snapshot?.page.isPublished == true,
      hasEligibleContent: hasMeaningfulPublicPolicyContent(
        snapshot?.blocks ?? const <Map<String, dynamic>>[],
      ),
      provenance: snapshot == null
          ? StaticPolicyRetainedProvenance.none
          : result.isOriginConfirmed
              ? StaticPolicyRetainedProvenance.publicOrigin
              : result.isStaleFallback
                  ? StaticPolicyRetainedProvenance.publicStale
                  : StaticPolicyRetainedProvenance.none,
    );
  }

  factory StaticPolicyPublicationProjection.fromState({
    required WebsitePage? page,
    required List<Map<String, dynamic>> blocks,
    required StaticPolicyRetainedProvenance provenance,
  }) {
    return StaticPolicyPublicationProjection(
      hasOwner: page != null,
      ownerIsPublished:
          provenance == StaticPolicyRetainedProvenance.publicOrigin &&
              page?.isPublished == true,
      hasEligibleContent: hasMeaningfulPublicPolicyContent(blocks),
      provenance:
          page == null ? StaticPolicyRetainedProvenance.none : provenance,
    );
  }

  final bool hasOwner;
  final bool ownerIsPublished;
  final bool hasEligibleContent;
  final StaticPolicyRetainedProvenance provenance;

  bool get isStaleSnapshot =>
      provenance == StaticPolicyRetainedProvenance.publicStale;
  bool get canRenderRetainedContent => hasOwner && hasEligibleContent;
  bool get isAuthoritativelyPublic => ownerIsPublished && hasEligibleContent;
  bool get shouldRenderPublicContent =>
      canRenderRetainedContent && (isAuthoritativelyPublic || isStaleSnapshot);
  bool get shouldIndex => isAuthoritativelyPublic;
}

Set<String> availablePublicPolicySlugs(
  Map<String, PageSnapshotLoadResult> results,
) {
  return Set<String>.unmodifiable({
    for (final entry in results.entries)
      if (StaticPolicyPublicationProjection.fromLoadResult(entry.value)
          .isAuthoritativelyPublic)
        entry.key,
  });
}

class _PolicyMeta {
  final String title;
  final String navLabel;
  final IconData icon;
  final Color color;

  const _PolicyMeta({
    required this.title,
    required this.navLabel,
    required this.icon,
    required this.color,
  });

  static _PolicyMeta forSlug(String slug, String fallbackTitle) {
    switch (slug) {
      case 'nosotros':
        return const _PolicyMeta(
          title: 'Sobre nosotros',
          navLabel: 'Nosotros',
          icon: Icons.storefront_outlined,
          color: PublicStoreTheme.primaryBlue,
        );
      case 'envios':
        return const _PolicyMeta(
          title: 'Envíos',
          navLabel: 'Envíos',
          icon: Icons.local_shipping_outlined,
          color: Color(0xFF2E7D32),
        );
      case 'devoluciones':
        return const _PolicyMeta(
          title: 'Devoluciones',
          navLabel: 'Devoluciones',
          icon: Icons.assignment_return_outlined,
          color: PublicStoreTheme.primaryBlue,
        );
      case 'terminos':
        return const _PolicyMeta(
          title: 'Términos y condiciones',
          navLabel: 'Términos',
          icon: Icons.gavel_outlined,
          color: Color(0xFFB45309),
        );
      case 'privacidad':
        return const _PolicyMeta(
          title: 'Privacidad',
          navLabel: 'Privacidad',
          icon: Icons.shield_outlined,
          color: PublicStoreTheme.primaryBlue,
        );
      default:
        return _PolicyMeta(
          title: fallbackTitle,
          navLabel: fallbackTitle,
          icon: Icons.info_outline,
          color: PublicStoreTheme.primaryBlue,
        );
    }
  }
}

class _PolicySection {
  final String title;
  final List<String> paragraphs;
  final List<_PolicyItem> items;

  const _PolicySection(this.title, this.paragraphs, this.items);
}

class _PolicyItem {
  final String title;
  final String body;

  const _PolicyItem(this.title, this.body);
}

class _StaticPolicyPageState extends State<StaticPolicyPage>
    with AutomaticKeepAliveClientMixin {
  static const List<String> _policySlugs = <String>[
    'nosotros',
    'terminos',
    'privacidad',
    'devoluciones',
    'envios',
  ];

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _blocks = [];
  WebsitePage? _page;
  String? _pageId;
  String? _snapshotFingerprint;
  Set<String> _availablePolicySlugs = const <String>{};
  // TYPED lease that authorized editor-provenance content (fingerprint AND
  // authorityEpoch — an A→B→A churn reproduces the fingerprint, never the
  // epoch); see the audience guard in build().
  WebsiteEditorCapabilitySnapshot? _editorLease;
  int _loadGeneration = 0;
  WebsiteService? _observedWebsiteService;
  bool _cmsRevalidationPending = false;
  bool _cmsRevalidationScheduled = false;
  bool _seoProjectionPending = false;
  bool _initialLoadStarted = false;
  StaticPolicyRetainedProvenance _retainedProvenance =
      StaticPolicyRetainedProvenance.none;

  bool get _originConfirmed =>
      _retainedProvenance == StaticPolicyRetainedProvenance.publicOrigin;
  bool get _isStaleSnapshot =>
      _retainedProvenance == StaticPolicyRetainedProvenance.publicStale;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _seedFromSnapshot(widget.slug);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final websiteService = context.read<WebsiteService>();
    if (!identical(_observedWebsiteService, websiteService)) {
      _observedWebsiteService?.cmsPageFreshnessSignal
          .removeListener(_handleCmsPageFreshnessSignal);
      _observedWebsiteService = websiteService;
      websiteService.cmsPageFreshnessSignal
          .addListener(_handleCmsPageFreshnessSignal);
    }
    if (!_initialLoadStarted) {
      _initialLoadStarted = true;
      unawaited(_loadPage());
    }

    if (_cmsRevalidationPending && TickerMode.of(context)) {
      _cmsRevalidationPending = false;
      _scheduleCmsPageOriginRevalidation();
    }
    if (_seoProjectionPending && TickerMode.of(context)) {
      _seoProjectionPending = false;
      _scheduleSeoUpdate(
        _page,
        _loadGeneration,
        originConfirmed: _originConfirmed,
        hasEligibleContent: hasMeaningfulPublicPolicyContent(_blocks),
      );
    }
  }

  @override
  void didUpdateWidget(covariant StaticPolicyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _seedFromSnapshot(widget.slug, clearOnMiss: true);
      _loadPage();
    }
  }

  @override
  void dispose() {
    _observedWebsiteService?.cmsPageFreshnessSignal
        .removeListener(_handleCmsPageFreshnessSignal);
    super.dispose();
  }

  void _handleCmsPageFreshnessSignal() {
    if (!mounted) return;
    if (!TickerMode.of(context)) {
      _cmsRevalidationPending = true;
      return;
    }
    _scheduleCmsPageOriginRevalidation();
  }

  void _scheduleCmsPageOriginRevalidation() {
    if (_cmsRevalidationScheduled) return;
    _cmsRevalidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cmsRevalidationScheduled = false;
      if (!mounted) return;
      if (!TickerMode.of(context)) {
        _cmsRevalidationPending = true;
        return;
      }
      unawaited(_loadPage());
    });
  }

  bool _seedFromSnapshot(String slug, {bool clearOnMiss = false}) {
    final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
    final snapshot = tenantId == null || tenantId.isEmpty
        ? null
        : context
            .read<WebsiteService>()
            .peekPageWithBlocks(slug, tenantId: tenantId);

    if (snapshot != null) {
      _page = snapshot.page;
      _pageId = snapshot.page.id;
      _snapshotFingerprint = snapshot.fingerprint;
      _blocks = snapshot.blocks;
      _retainedProvenance = StaticPolicyRetainedProvenance.publicStale;
      _loading = false;
      _error = null;
      return true;
    }

    if (clearOnMiss) {
      _page = null;
      _pageId = null;
      _snapshotFingerprint = null;
      _blocks = [];
      _retainedProvenance = StaticPolicyRetainedProvenance.none;
      _availablePolicySlugs = const <String>{};
      _loading = true;
      _error = null;
    }
    return false;
  }

  /// Invalidates an editor-provenance snapshot whose lease was lost and
  /// reloads through the public read path. The current frame already renders
  /// the safe loading state; the reset happens post-frame (build-safe).
  void _invalidateEditorContentAndReloadPublic() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_retainedProvenance != StaticPolicyRetainedProvenance.editor) return;
      setState(() {
        _page = null;
        _pageId = null;
        _snapshotFingerprint = null;
        _blocks = [];
        _retainedProvenance = StaticPolicyRetainedProvenance.none;
        _editorLease = null;
        _loading = true;
        _error = null;
      });
      // The reload arrives exclusively through the central CMS revalidation
      // signal emitted on the lease transition (exactly one load per
      // transition; no second local path).
    });
  }

  /// Attaches this policy page's document to the open editor session once its
  /// blocks are loaded. Mode entry/exit is owned by the FSM route binding in
  /// the storefront layout; this consumer only supplies its page document.
  void _bindEditorDocument(WebsiteEditModeProvider editProvider) {
    if (_loading || _pageId == null) return;
    WebsiteEditorDocumentBinding.bind(
      context,
      editProvider: editProvider,
      ready: true,
      blocks: () => List<Map<String, dynamic>>.from(_blocks),
      settings: () =>
          Map<String, dynamic>.from(context.read<WebsiteService>().settings),
      pageId: _pageId,
      pageSlug: widget.slug,
    );
  }

  Future<void> _loadPage() async {
    final loadGeneration = ++_loadGeneration;
    final requestedSlug = widget.slug;
    final shouldShowSpinner = _pageId == null;
    if (shouldShowSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      // Keep rendering existing content; just clear previous error.
      _error = null;
    }
    _scheduleSeoUpdate(
      _page,
      loadGeneration,
      originConfirmed: _originConfirmed,
      hasEligibleContent: hasMeaningfulPublicPolicyContent(_blocks),
    );

    try {
      // Get tenant from provider or authenticated user
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      String? tenantId = tenantProvider.tenantId;

      if (tenantId == null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final profileResp = await Supabase.instance.client
              .from('user_profiles')
              .select('tenant_id')
              .eq('user_id', user.id)
              .maybeSingle();
          tenantId = profileResp?['tenant_id'] as String?;
        }
      }

      if (tenantId == null) {
        throw Exception('No tenant detected');
      }
      if (!mounted ||
          loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug) {
        return;
      }

      final websiteService = context.read<WebsiteService>();
      if (_pageId == null) {
        setState(() {
          _seedFromSnapshot(requestedSlug);
        });
      }

      WebsiteEditModeProvider? editProvider;
      try {
        editProvider = context.read<WebsiteEditModeProvider>();
      } catch (_) {
        editProvider = null;
      }
      // The provider is the sole mode owner and the layout's capability gate
      // has already applied (or refused) any URL entry command by the time
      // this routed child builds: an unauthorized visitor can never request
      // the editor load path from here.
      final editorRequested = editProvider?.isInEditorContext == true;

      if (editorRequested) {
        final requestLease = editProvider?.editorEntryLease;
        final requestGeneration = editProvider?.editorEntryLeaseGeneration;
        final requestIdentityRevision =
            editProvider?.editorEntryLeaseIdentityRevision;
        final requestServiceEpoch = websiteService.identityEpoch;
        final requestServiceIdentity =
            websiteService.editorCapabilityRequestIdentity;
        CachedPageSnapshot? editorSnapshot;
        var editorAuthorityLost = false;
        try {
          editorSnapshot = await websiteService.loadEditorPageWithBlocks(
            requestedSlug,
            tenantId: tenantId,
          );
        } on WebsiteEditorAuthorityException {
          // Editor authority was lost: either the local gate denied, or the
          // server (RLS/auth) rejected a read a stale cached grant still
          // believed authorized. Revoke the lease/FSM and adopt ONLY the
          // public result, never draft content. Transient errors never take
          // this branch (they rethrow upstream unclassified).
          editorAuthorityLost = true;
          // The single CMS revalidation for this transition is emitted by
          // the layout when it adopts the durable denial — emitting here
          // too would double the reload.
          if (mounted) {
            try {
              context.read<WebsiteEditModeProvider>().revokeEditorEntryLease();
            } catch (_) {}
          }
        }
        // A stale editor response after a revoke/identity change is dropped;
        // the audience guard in build() reloads through the public read.
        if (!editorAuthorityLost) {
          final currentLease = editProvider?.editorEntryLease;
          if (currentLease == null ||
              !currentLease.granted ||
              requestLease == null ||
              currentLease.fingerprint != requestLease.fingerprint ||
              currentLease.authorityEpoch != requestLease.authorityEpoch ||
              requestGeneration != editProvider?.editorEntryLeaseGeneration ||
              requestIdentityRevision !=
                  editProvider?.editorEntryLeaseIdentityRevision ||
              requestServiceEpoch != websiteService.identityEpoch ||
              requestServiceIdentity !=
                  websiteService.editorCapabilityRequestIdentity) {
            return;
          }
        }
        if (!editorAuthorityLost) {
          if (!mounted ||
              loadGeneration != _loadGeneration ||
              requestedSlug != widget.slug) {
            return;
          }
          if (editorSnapshot == null) {
            setState(() {
              _page = null;
              _pageId = null;
              _snapshotFingerprint = null;
              _blocks = [];
              _retainedProvenance = StaticPolicyRetainedProvenance.none;
              _loading = false;
              _error = null;
            });
            _scheduleSeoUpdate(
              null,
              loadGeneration,
              originConfirmed: false,
              hasEligibleContent: false,
            );
            return;
          }

          setState(() {
            _page = editorSnapshot!.page;
            _pageId = editorSnapshot.page.id;
            _snapshotFingerprint = editorSnapshot.fingerprint;
            _blocks = editorSnapshot.blocks;
            // Authorized editor reads never become public trust/index
            // evidence.
            _retainedProvenance = StaticPolicyRetainedProvenance.editor;
            _editorLease = requestLease;
            _loading = false;
            _error = null;
          });
          _scheduleSeoUpdate(
            editorSnapshot.page,
            loadGeneration,
            originConfirmed: false,
            hasEligibleContent: false,
          );
          // The setState above triggers a rebuild whose document binding
          // attaches this page to the editor session.
          return;
        }
        // editorAuthorityLost: fall through to the public revalidation below.
      }

      // Even when a snapshot painted synchronously, this always revalidates
      // the canonical CMS page and blocks against the origin.
      final result = await websiteService.loadPageWithBlocksResult(
        requestedSlug,
        tenantId: tenantId,
      );

      if (!mounted ||
          loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug) {
        return;
      }

      if (result.isAuthoritativelyMissing) {
        setState(() {
          _page = null;
          _pageId = null;
          _snapshotFingerprint = null;
          _blocks = [];
          _retainedProvenance = StaticPolicyRetainedProvenance.none;
          _loading = false;
          _error = null;
        });
        _scheduleSeoUpdate(
          null,
          loadGeneration,
          originConfirmed: false,
          hasEligibleContent: false,
        );
        unawaited(
          _refreshPublishedPolicyNavigation(
            websiteService: websiteService,
            tenantId: tenantId,
            requestedSlug: requestedSlug,
            currentResult: result,
            loadGeneration: loadGeneration,
          ),
        );
        return;
      }

      final refreshed = result.snapshot;
      if (refreshed == null) {
        setState(() {
          _page = null;
          _pageId = null;
          _snapshotFingerprint = null;
          _blocks = [];
          _retainedProvenance = StaticPolicyRetainedProvenance.none;
          _loading = false;
          _error = null;
        });
        _scheduleSeoUpdate(
          null,
          loadGeneration,
          originConfirmed: false,
          hasEligibleContent: false,
        );
        unawaited(
          _refreshPublishedPolicyNavigation(
            websiteService: websiteService,
            tenantId: tenantId,
            requestedSlug: requestedSlug,
            currentResult: result,
            loadGeneration: loadGeneration,
          ),
        );
        return;
      }

      final didContentChange = _snapshotFingerprint != refreshed.fingerprint ||
          _pageId != refreshed.page.id;
      final nextProvenance = result.isOriginConfirmed
          ? StaticPolicyRetainedProvenance.publicOrigin
          : result.isStaleFallback
              ? StaticPolicyRetainedProvenance.publicStale
              : StaticPolicyRetainedProvenance.none;
      final didProvenanceChange = _retainedProvenance != nextProvenance;
      if (didContentChange ||
          didProvenanceChange ||
          _loading ||
          _error != null) {
        setState(() {
          _page = refreshed.page;
          _pageId = refreshed.page.id;
          _snapshotFingerprint = refreshed.fingerprint;
          _blocks = refreshed.blocks;
          _retainedProvenance = nextProvenance;
          _loading = false;
          _error = null;
        });
      }
      _scheduleSeoUpdate(
        refreshed.page,
        loadGeneration,
        originConfirmed: result.isOriginConfirmed,
        hasEligibleContent: hasMeaningfulPublicPolicyContent(refreshed.blocks),
      );

      unawaited(
        _refreshPublishedPolicyNavigation(
          websiteService: websiteService,
          tenantId: tenantId,
          requestedSlug: requestedSlug,
          currentResult: result,
          loadGeneration: loadGeneration,
        ),
      );

      // If the user navigated here while already in edit/preview mode, the
      // rebuild after the setState above binds this page's document so the
      // right panel can edit selected blocks.
    } on WebsiteEditorReadSupersededException {
      // An obsolete completion for a previous identity: discard silently —
      // no error surface, no revocation, no data.
      return;
    } catch (e) {
      if (mounted &&
          loadGeneration == _loadGeneration &&
          requestedSlug == widget.slug) {
        setState(() {
          _loading = false;
          _error = e.toString();
          _retainedProvenance = switch (_retainedProvenance) {
            StaticPolicyRetainedProvenance.publicOrigin =>
              StaticPolicyRetainedProvenance.publicStale,
            StaticPolicyRetainedProvenance.publicStale =>
              StaticPolicyRetainedProvenance.publicStale,
            StaticPolicyRetainedProvenance.editor =>
              StaticPolicyRetainedProvenance.editor,
            StaticPolicyRetainedProvenance.none =>
              StaticPolicyRetainedProvenance.none,
          };
        });
        _scheduleSeoUpdate(
          _page,
          loadGeneration,
          originConfirmed: false,
          hasEligibleContent: hasMeaningfulPublicPolicyContent(_blocks),
        );
      }
    }
  }

  void _scheduleSeoUpdate(
    WebsitePage? page,
    int loadGeneration, {
    required bool originConfirmed,
    required bool hasEligibleContent,
  }) {
    final requestedSlug = widget.slug;
    final websiteService = context.read<WebsiteService>();
    final policyMeta = _PolicyMeta.forSlug(
      requestedSlug,
      widget.fallbackTitle,
    );
    final storeName = websiteService
        .getSetting(
          'seo_business_name',
          websiteService.getSetting('store_name', ''),
        )
        .trim();
    final configuredTitle = page?.metaTitle?.trim() ?? '';
    final pageTitle = page?.title.trim() ?? '';
    final effectivePageTitle =
        pageTitle.isNotEmpty ? pageTitle : policyMeta.title;
    final title = configuredTitle.isNotEmpty
        ? configuredTitle
        : storeName.isEmpty
            ? effectivePageTitle
            : '$effectivePageTitle | $storeName';
    final configuredDescription = page?.metaDescription?.trim() ?? '';
    final configuredImage = page?.ogImageUrl?.trim() ?? '';
    final contentSummary = _PublicPolicyView.contentSummary(_blocks);
    final defaultImage =
        websiteService.getSetting('seo_og_image', '').trim().isNotEmpty
            ? websiteService.getSetting('seo_og_image', '').trim()
            : websiteService.getSetting('logo_url', '').trim();
    final currentUri = GoRouterState.of(context).uri;
    final isErpMounted =
        currentUri.path == '/tienda' || currentUri.path.startsWith('/tienda/');
    final routeProjection = projectStorefrontSeoRoute(
      currentUri,
      isErpMounted: isErpMounted,
      ownerIsPublished: originConfirmed && page?.isPublished == true,
      hasEligibleContent: hasEligibleContent,
    );
    final configuredStoreUrl = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      websiteService.getSetting('store_url', ''),
    );
    final canonicalBase = configuredStoreUrl.isEmpty
        ? null
        : Uri.tryParse(
            configuredStoreUrl.endsWith('/')
                ? configuredStoreUrl
                : '$configuredStoreUrl/',
          );
    final canonicalUrl = canonicalBase
        ?.resolve(routeProjection.canonicalPath)
        .replace(query: null, fragment: null)
        .toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug) {
        return;
      }
      if (!TickerMode.of(context)) {
        _seoProjectionPending = true;
        return;
      }
      _seoProjectionPending = false;
      SeoHelper.updateSeo(
        title: title,
        description: configuredDescription.isNotEmpty
            ? configuredDescription
            : contentSummary.isNotEmpty
                ? contentSummary
                : 'Esta página no tiene contenido público disponible en este '
                    'momento.',
        imageUrl: configuredImage.isNotEmpty
            ? configuredImage
            : defaultImage.isEmpty
                ? null
                : defaultImage,
        keywords: page?.metaKeywords,
        canonicalUrl: canonicalUrl,
        robots: routeProjection.robots,
      );
    });
  }

  Future<void> _refreshPublishedPolicyNavigation({
    required WebsiteService websiteService,
    required String tenantId,
    required String requestedSlug,
    required PageSnapshotLoadResult currentResult,
    required int loadGeneration,
  }) async {
    final results = <String, PageSnapshotLoadResult>{
      requestedSlug: currentResult,
    };
    final otherSlugs =
        _policySlugs.where((slug) => slug != requestedSlug).toList();
    final List<PageSnapshotLoadResult> otherResults;
    try {
      otherResults = await Future.wait(
        otherSlugs.map(
          (slug) => websiteService.loadPageWithBlocksResult(
            slug,
            tenantId: tenantId,
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        'No se pudo verificar la navegación pública de políticas: $error',
      );
      return;
    }
    for (var index = 0; index < otherSlugs.length; index++) {
      results[otherSlugs[index]] = otherResults[index];
    }

    if (!mounted ||
        loadGeneration != _loadGeneration ||
        requestedSlug != widget.slug) {
      return;
    }

    final publishedSlugs = availablePublicPolicySlugs(results);
    if (setEquals(_availablePolicySlugs, publishedSlugs)) return;
    setState(() {
      _availablePolicySlugs = Set.unmodifiable(publishedSlugs);
    });
  }

  StaticPolicyPublicationProjection get _publication {
    return StaticPolicyPublicationProjection.fromState(
      page: _page,
      blocks: _blocks,
      provenance: _retainedProvenance,
    );
  }

  bool get _canRenderRetainedPublicContent {
    return _publication.canRenderRetainedContent;
  }

  bool get _isAuthoritativelyPublic {
    return _publication.isAuthoritativelyPublic;
  }

  String get _unavailableTitle {
    final title = _page?.title.trim() ?? '';
    if (title.isNotEmpty && _isStaleSnapshot) {
      return title;
    }
    return widget.fallbackTitle;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final editProvider = context.watch<WebsiteEditModeProvider>();
    context.watch<WebsiteService>();
    final isEditMode = editProvider.isEditMode;

    // Audience guard: editor-provenance content must never render a single
    // frame beyond its authorizing lease. On revoke/suspend the snapshot is
    // invalidated BEFORE painting and the page reloads through the public
    // read; an unpublished public owner then resolves to unavailable.
    final editorContentAuthorized =
        _retainedProvenance != StaticPolicyRetainedProvenance.editor ||
            (editProvider.isInEditorContext &&
                editProvider.editorEntryLeaseGranted &&
                _editorLease != null &&
                editProvider.editorEntryLease?.fingerprint ==
                    _editorLease?.fingerprint &&
                editProvider.editorEntryLease?.authorityEpoch ==
                    _editorLease?.authorityEpoch);
    if (!editorContentAuthorized) {
      _invalidateEditorContentAndReloadPublic();
      return const Center(child: CircularProgressIndicator());
    }
    // Desired vs loaded audience. A late lease grant triggers the CENTRAL
    // CMS revalidation signal (emitted by the layout on the lease
    // transition); while the desired editor audience is still pending, this
    // page keeps rendering its safe state and never binds a public snapshot
    // into the editor session.
    final desiredEditorAudience =
        editProvider.isInEditorContext && editProvider.editorEntryLeaseGranted;
    final audienceSatisfied = desiredEditorAudience
        ? (_retainedProvenance == StaticPolicyRetainedProvenance.editor &&
            _editorLease != null &&
            _editorLease?.fingerprint ==
                editProvider.editorEntryLease?.fingerprint &&
            _editorLease?.authorityEpoch ==
                editProvider.editorEntryLease?.authorityEpoch)
        : _retainedProvenance != StaticPolicyRetainedProvenance.editor;

    // The FSM route command in the storefront layout already owns the mode;
    // this consumer only binds its page document once blocks are loaded AND
    // the loaded audience matches the session's audience.
    if (audienceSatisfied) {
      _bindEditorDocument(editProvider);
    }

    // Only use provider blocks if we are actually editing THIS page
    // This prevents showing homepage blocks when navigating to a policy page
    // without explicitly entering edit mode for that specific page.
    final matchesPage = editProvider.ownsPageDocument(
      pageId: _pageId,
      pageSlug: widget.slug,
    );

    // In editor context (preview or edit), render the provider blocks for THIS page.
    // This ensures switching to preview after saving shows the updated content.
    final blocksToRender = (editProvider.isInEditorContext && matchesPage)
        ? editProvider.blocks
        : _blocks;

    final resolvedTheme = WebsiteResolvedTheme.of(context);
    final primaryColor = resolvedTheme.primaryColor;
    final accentColor = resolvedTheme.accentColor;
    final headingFont = resolvedTheme.headingFont;
    final bodyFont = resolvedTheme.bodyFont;
    final headingSize = resolvedTheme.headingSize;
    final bodySize = resolvedTheme.bodySize;
    final sectionSpacing = resolvedTheme.sectionSpacing;
    final containerPadding = resolvedTheme.containerPadding;
    final textColor = resolvedTheme.textColor;

    if (_loading && !_canRenderRetainedPublicContent) {
      final minHeight = MediaQuery.sizeOf(context).height * 0.55;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (editProvider.isInEditorContext && !matchesPage) {
      return const Center(child: CircularProgressIndicator());
    }

    final logicalWidth = MediaQuery.sizeOf(context).width;
    final breakpoint = WebsiteViewport.fromLogicalWidth(logicalWidth).wireName;
    final compositionMode = isEditMode
        ? WebsitePageCompositionMode.edit
        : editProvider.isPreviewMode
            ? WebsitePageCompositionMode.preview
            : WebsitePageCompositionMode.public;
    final composition = WebsitePageComposition.project(
      blocks: blocksToRender,
      mode: compositionMode,
      breakpoint: breakpoint,
      logicalWidth: logicalWidth,
      sectionSpacing: sectionSpacing,
    );
    final composedRows = composition.blocks
        .map((block) => block.sourceBlock)
        .toList(growable: false);
    // The trust shell (hero/summary/nav) always derives from PUBLICLY
    // reachable rows. Edit keeps hidden draft blocks repairable inside the
    // composed canvas (with chrome), but they must not change the shell's
    // title/summary relative to Preview/Public.
    final shellRows = isEditMode
        ? WebsitePageComposition.project(
            blocks: blocksToRender,
            mode: WebsitePageCompositionMode.preview,
            breakpoint: breakpoint,
            logicalWidth: logicalWidth,
            sectionSpacing: sectionSpacing,
          ).blocks.map((block) => block.sourceBlock).toList(growable: false)
        : composedRows;
    String? tenantId;
    try {
      tenantId = context.read<PublicStoreTenantProvider>().tenantId;
    } catch (_) {
      tenantId = null;
    }
    final composedContent = PageComposition(
      composition: composition,
      primaryColor: primaryColor,
      accentColor: accentColor,
      textColor: textColor,
      containerPadding: containerPadding,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      tenantId: tenantId,
      onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
      isNavigationEligible: (href) =>
          PublicStoreLayout.isHrefPubliclyEligible(context, href),
      onAddBlock: (type, {atIndex}) =>
          editProvider.addBlock(type, atIndex: atIndex),
      onSpacingChanged: (blockId, spacing) =>
          editProvider.updateBlockData(blockId, 'spacingAfter', spacing),
      contentAdapter: (context, block, sharedContent) {
        final sections = _PublicPolicyView.extractSections([
          block.sourceBlock,
        ]);
        return sections.isEmpty
            ? sharedContent
            : KeyedSubtree(
                key: ValueKey<String>(
                  'static-policy-adapted-content-${block.id}',
                ),
                child: _PolicyContent(sections: sections),
              );
      },
      emptyState: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Esta página está en construcción',
            style: TextStyle(
              fontSize: 18,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );

    if (!editProvider.isInEditorContext) {
      if (_publication.shouldRenderPublicContent) {
        return _PublicPolicyView(
          slug: widget.slug,
          fallbackTitle: widget.fallbackTitle,
          blocks: composedRows,
          composedContent: composedContent,
          page: _page,
          availablePolicySlugs: _availablePolicySlugs,
          isStale: !_isAuthoritativelyPublic,
        );
      }
      return _PublicPolicyUnavailableView(title: _unavailableTitle);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                widget.fallbackTitle,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: textColor.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    // Edit -> Preview -> Public parity: every mode renders the same trust
    // shell + adapted composition; Edit only adds chrome inside it.
    return _PublicPolicyView(
      slug: widget.slug,
      fallbackTitle: widget.fallbackTitle,
      blocks: shellRows,
      composedContent: composedContent,
      page: _page,
      availablePolicySlugs: _availablePolicySlugs,
      isStale: false,
    );
  }
}
