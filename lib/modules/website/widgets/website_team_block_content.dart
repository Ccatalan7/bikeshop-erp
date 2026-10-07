import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

typedef WebsiteTeamImageProviderBuilder = WebsiteSectionImageProviderBuilder;

/// Shared visitor content for the Website Builder Team block: the ruled
/// header with its note, then each member with the portrait (or the person
/// mark) in a tinted circle, the name, the role and the line about them; in
/// up to three columns, a list with rules on a phone. The HTML storefront
/// draws the same (`TeamSectionView`).
///
/// Public and Preview render this tree directly. Edit may replace persisted
/// text and media leaves through [presenters], but it never owns a second
/// layout or manufactures team members.
class WebsiteTeamBlockContent extends StatelessWidget {
  const WebsiteTeamBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.previewMode = false,
    this.headingFont,
    this.bodyFont,
    this.onNavigate,
    this.isNavigationEligible,
    this.presenters,
    this.padding,
    this.paintSurface = true,
    this.imageProviderBuilder,
  });

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  /// Allows focused widget tests to exercise media without network access.
  final WebsiteTeamImageProviderBuilder? imageProviderBuilder;

  static const rootKey = ValueKey<String>('website-team-content-root');
  static const membersKey = ValueKey<String>('website-team-members');

  static ValueKey<String> memberCardKey(int index) =>
      ValueKey<String>('website-team-member-card-$index');

  static ValueKey<String> memberAvatarKey(int index) =>
      ValueKey<String>('website-team-member-avatar-$index');

  static ValueKey<String> memberAvatarFallbackKey(int index) =>
      ValueKey<String>('website-team-member-avatar-fallback-$index');

  static ValueKey<String> memberNameKey(int index) =>
      ValueKey<String>('website-team-member-name-$index');

  static ValueKey<String> memberRoleKey(int index) =>
      ValueKey<String>('website-team-member-role-$index');

  static ValueKey<String> memberBioKey(int index) =>
      ValueKey<String>('website-team-member-bio-$index');

  static const _collection = <String>['members', 'team', 'items'];

  @override
  Widget build(BuildContext context) {
    final members = websiteSectionItems(data, 'members', const [
      'team',
      'items',
    ]);
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.team, data),
        primaryColor: primaryColor,
        accentColor: accentColor,
        headingFont: headingFont,
        bodyFont: bodyFont,
        padding: padding,
        paintSurface: paintSurface,
        builder: (context, scope) {
          final header = WebsiteSectionHeader(
            scope: scope,
            data: data,
            idPrefix: 'team',
            presenters: presenters,
            noteKey: 'description',
            noteAliases: const ['subtitle'],
            ruled: true,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!header.isEmpty) header,
              if (members.isNotEmpty) _members(context, scope, members),
            ],
          );
        },
      ),
    );
  }

  Widget _members(
    BuildContext context,
    WebsiteSectionScope scope,
    List<(int, Map<String, dynamic>)> members,
  ) {
    if (scope.isPhone) {
      return Column(
        key: membersKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, member) in members)
            Container(
              key: memberCardKey(index),
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scope.colors.rule)),
              ),
              child: _member(context, scope, member, index),
            ),
        ],
      );
    }
    final columns =
        scope.isDesktop ? (members.length < 3 ? members.length : 3) : 2;
    final rows = <Widget>[];
    for (var start = 0; start < members.length; start += columns) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: 28),
              Expanded(
                child: start + column < members.length
                    ? Padding(
                        key: memberCardKey(members[start + column].$1),
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: _member(
                          context,
                          scope,
                          members[start + column].$2,
                          members[start + column].$1,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      key: membersKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _member(
    BuildContext context,
    WebsiteSectionScope scope,
    Map<String, dynamic> member,
    int index,
  ) {
    final phone = scope.isPhone;
    final target = websiteSectionTarget(
      member,
      index: index,
      collectionKeys: _collection,
    );
    final name = websiteSectionText(member, const ['name']);
    final role = websiteSectionText(member, const ['role']);
    final bio = websiteSectionText(member, const ['bio']);
    final photo = websiteSectionText(member, const [
      'avatarUrl',
      'image',
    ]).trim();
    final alt = websiteSectionText(member, const ['avatarAltText']).trim();
    final size = phone ? 64.0 : 88.0;
    final semanticLabel = alt.isNotEmpty
        ? alt
        : name.trim().isNotEmpty
            ? 'Foto de ${name.trim()}'
            : 'Foto de integrante del equipo';
    final fallback = Container(
      key: memberAvatarFallbackKey(index),
      decoration: BoxDecoration(
        color: scope.colors.tint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        presenters?.media != null
            ? Icons.add_a_photo_outlined
            : Icons.person_outline,
        size: phone ? 28 : 36,
        color: scope.colors.mark,
        semanticLabel: semanticLabel,
      ),
    );
    final links = [
      for (final (key, label) in const [
        ('instagram', 'Instagram'),
        ('linkedin', 'LinkedIn'),
      ])
        if (websiteSectionText(member, [key]).trim() case final href
            when href.isNotEmpty && (isNavigationEligible?.call(href) ?? true))
          (label, href),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: memberAvatarKey(index),
          width: size,
          height: size,
          child: websiteSectionMedia(
            context,
            presenters: presenters,
            id: 'team.member.$index.avatar',
            url: photo,
            valueKeys: const <String>['avatarUrl', 'image'],
            fallback: fallback,
            semanticLabel: semanticLabel,
            oval: true,
            repeaterTarget: target,
            imageProviderBuilder: imageProviderBuilder,
          ),
        ),
        SizedBox(width: phone ? 16 : 20),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              websiteSectionSlot(
                context,
                presenters,
                WebsiteInlineTextSlot(
                  id: 'team.member.$index.name',
                  value: name,
                  valueKeys: const <String>['name'],
                  baseStyle: scope.heading(phone ? 20 : 24, height: 1.2),
                  formatting: websiteSectionFormatting(
                    member['nameFormatting'],
                  ),
                  formattingKeys: const <String>['nameFormatting'],
                  placeholder: 'Nombre',
                  displayTransform: (value) => value.toUpperCase(),
                  repeaterTarget: target,
                ),
                key: memberNameKey(index),
              ),
              if (role.trim().isNotEmpty) ...[
                SizedBox(height: phone ? 3 : 4),
                websiteSectionSlot(
                  context,
                  presenters,
                  WebsiteInlineTextSlot(
                    id: 'team.member.$index.role',
                    value: role,
                    valueKeys: const <String>['role'],
                    baseStyle: scope
                        .caps(
                          phone ? 12 : 13,
                          tracking: 0.12,
                        )
                        .copyWith(height: 1.4),
                    formatting: websiteSectionFormatting(
                      member['roleFormatting'],
                    ),
                    formattingKeys: const <String>['roleFormatting'],
                    placeholder: 'Cargo',
                    displayTransform: (value) => value.trim().toUpperCase(),
                    repeaterTarget: target,
                  ),
                  key: memberRoleKey(index),
                ),
              ],
              if (bio.trim().isNotEmpty) ...[
                SizedBox(height: phone ? 8 : 12),
                websiteSectionSlot(
                  context,
                  presenters,
                  WebsiteInlineTextSlot(
                    id: 'team.member.$index.bio',
                    value: bio,
                    valueKeys: const <String>['bio'],
                    baseStyle: scope.body(
                      phone ? 15 : 16,
                      color: scope.colors.muted,
                    ),
                    formatting: websiteSectionFormatting(
                      member['bioFormatting'],
                    ),
                    formattingKeys: const <String>['bioFormatting'],
                    placeholder: 'Una línea sobre su especialidad',
                    displayTransform: (value) => value.trim(),
                    repeaterTarget: target,
                  ),
                  key: memberBioKey(index),
                ),
              ],
              if (links.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  children: [
                    for (final (label, href) in links)
                      _TeamLink(
                        label: label,
                        style: scope.caps(13, tracking: 0.06).copyWith(
                              color: scope.colors.mark,
                              height: 1.4,
                            ),
                        href: href,
                        onPressed: presenters != null || onNavigate == null
                            ? null
                            : () => onNavigate!(href),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TeamLink extends StatelessWidget {
  const _TeamLink({
    required this.label,
    required this.style,
    required this.href,
    required this.onPressed,
  });

  final String label;
  final TextStyle style;
  final String href;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label.toUpperCase(), style: style),
        ),
      ),
    );
  }
}
