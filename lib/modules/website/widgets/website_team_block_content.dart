import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

typedef WebsiteTeamImageProviderBuilder = ImageProvider<Object> Function(
  String url,
);

/// Shared visitor content for the Website Builder Team block.
///
/// Public and Preview render this tree directly. Edit may replace persisted
/// text and media leaves through [presenters], but it never owns a second
/// layout or manufactures team members.
class WebsiteTeamBlockContent extends StatelessWidget {
  const WebsiteTeamBlockContent({
    super.key,
    required this.data,
    required this.accentColor,
    this.previewMode = false,
    this.headingFont,
    this.bodyFont,
    this.onNavigate,
    this.isNavigationEligible,
    this.presenters,
    this.padding = const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
    this.imageProviderBuilder,
  });

  final Map<String, dynamic> data;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;
  final EdgeInsetsGeometry padding;

  /// Allows focused widget tests to exercise media without network access.
  final WebsiteTeamImageProviderBuilder? imageProviderBuilder;

  static const rootKey = ValueKey<String>('website-team-content-root');
  static const frameKey = ValueKey<String>('website-team-content-frame');
  static const titleKey = ValueKey<String>('website-team-title');
  static const descriptionKey = ValueKey<String>('website-team-description');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawTitle = _firstPresentString(data, const <String>['title']);
    final title = rawTitle.trim().isEmpty ? 'Nuestro equipo' : rawTitle.trim();
    final description = _firstPresentString(
      data,
      const <String>['description', 'subtitle'],
    ).trim();
    final members = _firstPresentMapList(
      data,
      const <String>['members', 'team', 'items'],
    );
    final titleFormatting = _resolveFormatting(data['titleFormatting']);
    final descriptionFormatting = _resolveFormatting(
      data['descriptionFormatting'] ?? data['subtitleFormatting'],
    );

    final titleSlot = WebsiteInlineTextSlot(
      id: 'team.title',
      value: rawTitle,
      valueKeys: const <String>['title'],
      baseStyle: (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
      ),
      formatting: titleFormatting,
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Nuestro equipo',
    );
    final descriptionSlot = WebsiteInlineTextSlot(
      id: 'team.description',
      value: description,
      valueKeys: const <String>['description', 'subtitle'],
      baseStyle: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      formatting: descriptionFormatting,
      formattingKeys: const <String>[
        'descriptionFormatting',
        'subtitleFormatting',
      ],
      textAlign: TextAlign.center,
      placeholder: 'Descripción del equipo',
    );

    return Padding(
      key: rootKey,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          key: frameKey,
          constraints: const BoxConstraints(maxWidth: 1100),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final usefulWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final compact = usefulWidth < 600;
              final cardWidth = compact ? usefulWidth : 300.0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  KeyedSubtree(
                    key: titleKey,
                    child: _presentText(
                      context,
                      slot: titleSlot,
                      publicValue: title,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: descriptionKey,
                      child: _presentText(
                        context,
                        slot: descriptionSlot,
                        publicValue: description,
                      ),
                    ),
                  ],
                  if (members.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    Wrap(
                      key: membersKey,
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        for (var index = 0; index < members.length; index++)
                          _buildMemberCard(
                            context,
                            member: members[index],
                            index: index,
                            cardWidth: cardWidth,
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(
    BuildContext context, {
    required Map<String, dynamic> member,
    required int index,
    required double cardWidth,
  }) {
    final theme = Theme.of(context);
    final name = _firstPresentString(member, const <String>['name']).trim();
    final role = _firstPresentString(member, const <String>['role']).trim();
    final bio = _firstPresentString(member, const <String>['bio']).trim();
    final avatarUrl = _firstPresentString(
      member,
      const <String>['avatarUrl', 'image'],
    ).trim();
    final avatarAltText = _firstPresentString(
      member,
      const <String>['avatarAltText'],
    ).trim();
    final instagram =
        _firstPresentString(member, const <String>['instagram']).trim();
    final linkedin =
        _firstPresentString(member, const <String>['linkedin']).trim();
    final target = _targetFor(
      collectionKeys: const <String>['members', 'team', 'items'],
      item: member,
      itemIndex: index,
    );
    final nameFormatting = _resolveFormatting(member['nameFormatting']);
    final roleFormatting = _resolveFormatting(member['roleFormatting']);
    final bioFormatting = _resolveFormatting(member['bioFormatting']);
    final showInstagram = _isEligible(instagram);
    final showLinkedin = _isEligible(linkedin);

    final nameSlot = WebsiteInlineTextSlot(
      id: 'team.member.$index.name',
      value: name,
      valueKeys: const <String>['name'],
      baseStyle: (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
        fontWeight: FontWeight.bold,
      ),
      formatting: nameFormatting,
      formattingKeys: const <String>['nameFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Nombre',
      repeaterTarget: target,
    );
    final roleSlot = WebsiteInlineTextSlot(
      id: 'team.member.$index.role',
      value: role,
      valueKeys: const <String>['role'],
      baseStyle: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      formatting: roleFormatting,
      formattingKeys: const <String>['roleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Cargo',
      repeaterTarget: target,
    );
    final bioSlot = WebsiteInlineTextSlot(
      id: 'team.member.$index.bio',
      value: bio,
      valueKeys: const <String>['bio'],
      baseStyle: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
      ),
      formatting: bioFormatting,
      formattingKeys: const <String>['bioFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Resumen profesional',
      repeaterTarget: target,
    );

    return SizedBox(
      key: memberCardKey(index),
      width: cardWidth,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox.square(
                key: memberAvatarKey(index),
                dimension: 96,
                child: _presentAvatar(
                  context,
                  index: index,
                  name: name,
                  imageUrl: avatarUrl,
                  altText: avatarAltText,
                  target: target,
                ),
              ),
              if (name.isNotEmpty) ...[
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: memberNameKey(index),
                  child: _presentText(
                    context,
                    slot: nameSlot,
                    publicValue: name,
                  ),
                ),
              ],
              if (role.isNotEmpty) ...[
                const SizedBox(height: 6),
                KeyedSubtree(
                  key: memberRoleKey(index),
                  child: _presentText(
                    context,
                    slot: roleSlot,
                    publicValue: role,
                  ),
                ),
              ],
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: memberBioKey(index),
                  child: _presentText(
                    context,
                    slot: bioSlot,
                    publicValue: bio,
                  ),
                ),
              ],
              if (showInstagram || showLinkedin)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showInstagram)
                        IconButton(
                          tooltip: 'Instagram',
                          onPressed: _navigationCallback(instagram),
                          icon: const Icon(Icons.camera_alt_outlined),
                          color: accentColor,
                        ),
                      if (showLinkedin)
                        IconButton(
                          tooltip: 'LinkedIn',
                          onPressed: _navigationCallback(linkedin),
                          icon: const Icon(Icons.work_outline),
                          color: accentColor,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presentText(
    BuildContext context, {
    required WebsiteInlineTextSlot slot,
    required String publicValue,
  }) {
    final presenter = presenters?.text;
    if (presenter != null) return presenter(context, slot);

    return Text(
      publicValue,
      maxLines: slot.maxLines,
      overflow: TextOverflow.visible,
      textAlign: slot.resolvedTextAlign,
      style: slot.formatting.applyTo(slot.baseStyle),
    );
  }

  Widget _presentAvatar(
    BuildContext context, {
    required int index,
    required String name,
    required String imageUrl,
    required String altText,
    required WebsiteInlineRepeaterTarget target,
  }) {
    final semanticLabel = altText.isNotEmpty
        ? altText
        : name.isNotEmpty
            ? 'Foto de $name'
            : 'Foto de integrante del equipo';
    final fallback = _TeamAvatarFallback(
      key: memberAvatarFallbackKey(index),
      accentColor: accentColor,
      semanticLabel: semanticLabel,
      editable: presenters?.media != null,
    );
    final slot = WebsiteInlineMediaSlot(
      id: 'team.member.$index.avatar',
      url: imageUrl.isEmpty ? null : imageUrl,
      valueKeys: const <String>['avatarUrl', 'image'],
      fit: BoxFit.cover,
      alignment: Alignment.center,
      fallback: fallback,
      borderRadius: BorderRadius.circular(48),
      semanticLabel: semanticLabel,
      repeaterTarget: target,
    );
    final presenter = presenters?.media;
    if (presenter != null) return presenter(context, slot);
    if (imageUrl.isEmpty) return fallback;

    final provider =
        imageProviderBuilder?.call(imageUrl) ?? NetworkImage(imageUrl);
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: ClipOval(
          child: Image(
            image: provider,
            width: double.infinity,
            height: double.infinity,
            fit: slot.fit,
            alignment: slot.alignment,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }

  bool _isEligible(String href) {
    if (href.isEmpty) return false;
    return isNavigationEligible?.call(href) ?? true;
  }

  VoidCallback? _navigationCallback(String href) {
    if (previewMode || presenters != null || onNavigate == null) return null;
    return () => onNavigate!(href);
  }

  static WebsiteInlineRepeaterTarget _targetFor({
    required List<String> collectionKeys,
    required Map<String, dynamic> item,
    required int itemIndex,
  }) {
    final identity = item['id'];
    final hasIdentity =
        identity != null && identity.toString().trim().isNotEmpty;
    return WebsiteInlineRepeaterTarget(
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      identityKey: hasIdentity ? 'id' : null,
      identityValue: hasIdentity ? identity : null,
    );
  }

  static String _firstPresentString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (source.containsKey(key)) return source[key]?.toString() ?? '';
    }
    return '';
  }

  static List<Map<String, dynamic>> _firstPresentMapList(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    Object? raw;
    for (final key in keys) {
      if (source.containsKey(key)) {
        raw = source[key];
        break;
      }
    }
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static TextFormatting _resolveFormatting(Object? raw) {
    if (raw is! Map) return const TextFormatting();
    return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
  }
}

class _TeamAvatarFallback extends StatelessWidget {
  const _TeamAvatarFallback({
    super.key,
    required this.accentColor,
    required this.semanticLabel,
    required this.editable,
  });

  final Color accentColor;
  final String semanticLabel;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            editable ? Icons.add_a_photo_outlined : Icons.person,
            size: 48,
            color: accentColor,
          ),
        ),
      ),
    );
  }
}
