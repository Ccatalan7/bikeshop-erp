import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'website_block_content_presenters.dart';

/// Pure, responsive content tree for a Website Builder contact block.
///
/// Public, Preview and Edit share this geometry. Edit may replace only the
/// title and subtitle leaves through [presenters]; contact details remain
/// read-only and navigation is suppressed while presenters are attached.
class WebsiteContactBlockContent extends StatelessWidget {
  const WebsiteContactBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.previewMode = false,
    this.onNavigate,
    this.isNavigationEligible,
    this.presenters,
    this.padding = const EdgeInsets.symmetric(
      vertical: 64,
      horizontal: 24,
    ),
  });

  static const frameKey = ValueKey<String>('website-contact-content-frame');
  static const headerKey = ValueKey<String>('website-contact-content-header');
  static const titleKey = ValueKey<String>('website-contact-content-title');
  static const subtitleKey =
      ValueKey<String>('website-contact-content-subtitle');
  static const layoutKey = ValueKey<String>('website-contact-content-layout');
  static const infoCardKey =
      ValueKey<String>('website-contact-content-info-card');
  static const formCardKey =
      ValueKey<String>('website-contact-content-form-card');
  static const mapCardKey =
      ValueKey<String>('website-contact-content-map-card');
  static const mapActionKey =
      ValueKey<String>('website-contact-content-map-action');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Contáctanos').toString();
    final title = rawTitle.trim().isEmpty ? 'Contáctanos' : rawTitle.trim();
    final rawSubtitle = (data['subtitle'] ?? '').toString();
    final subtitle = rawSubtitle.trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final address = (data['address'] ?? '').toString().trim();
    final mapUrl = (data['mapUrl'] ?? '').toString().trim();
    final showForm = data['showForm'] != false;
    final showMap = data['showMap'] == true;
    final showMapAction = showMap &&
        mapUrl.isNotEmpty &&
        (isNavigationEligible == null || isNavigationEligible!(mapUrl));

    return Container(
      key: frameKey,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth =
                  constraints.hasBoundedWidth ? constraints.maxWidth : 1100.0;
              final layout = _ContactLayout.resolve(
                availableWidth: availableWidth,
              );
              final titleStyle =
                  (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
                fontFamily: headingFont,
                fontSize: layout.headingSize,
                fontWeight: FontWeight.w700,
                height: 1.12,
              );
              final subtitleStyle =
                  (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
                fontFamily: bodyFont,
                fontSize: 17,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              );
              final textPresenter = presenters?.text;

              final cards = <_ContactCard>[
                _ContactCard(
                  key: infoCardKey,
                  desktopWidth: 320,
                  child: _ContactInfoCard(
                    phone: phone,
                    email: email,
                    address: address,
                    headingFont: headingFont,
                    bodyFont: bodyFont,
                  ),
                ),
                if (showForm)
                  _ContactCard(
                    key: formCardKey,
                    desktopWidth: 360,
                    child: _ContactFormCard(
                      primaryColor: primaryColor,
                      headingFont: headingFont,
                    ),
                  ),
                if (showMap)
                  _ContactCard(
                    key: mapCardKey,
                    desktopWidth: 360,
                    child: _ContactMapCard(
                      accentColor: accentColor,
                      headingFont: headingFont,
                      showAction: showMapAction,
                      onOpenMap: showMapAction
                          ? () {
                              // Visitor navigation works in Preview and
                              // Public; only Edit (presenters) is inert.
                              if (presenters != null) return;
                              onNavigate?.call(mapUrl);
                            }
                          : null,
                    ),
                  ),
              ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: headerKey,
                    child: Column(
                      children: [
                        KeyedSubtree(
                          key: titleKey,
                          child: textPresenter?.call(
                                context,
                                WebsiteInlineTextSlot(
                                  id: 'contact-title',
                                  value: rawTitle,
                                  valueKeys: const ['title'],
                                  baseStyle: titleStyle,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  placeholder: 'Título de contacto',
                                  displayTransform: (value) {
                                    final trimmed = value.trim();
                                    return trimmed.isEmpty
                                        ? 'Contáctanos'
                                        : trimmed;
                                  },
                                ),
                              ) ??
                              Text(
                                title,
                                style: titleStyle,
                                textAlign: TextAlign.center,
                              ),
                        ),
                        if (subtitle.isNotEmpty || textPresenter != null) ...[
                          const SizedBox(height: 12),
                          KeyedSubtree(
                            key: subtitleKey,
                            child: textPresenter?.call(
                                  context,
                                  WebsiteInlineTextSlot(
                                    id: 'contact-subtitle',
                                    value: rawSubtitle,
                                    valueKeys: const ['subtitle'],
                                    baseStyle: subtitleStyle,
                                    textAlign: TextAlign.center,
                                    maxLines: 5,
                                    placeholder: 'Subtítulo o descripción',
                                    displayTransform: (value) => value.trim(),
                                  ),
                                ) ??
                                Text(
                                  subtitle,
                                  style: subtitleStyle,
                                  textAlign: TextAlign.center,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  KeyedSubtree(
                    key: layoutKey,
                    child: _ContactCardsLayout(
                      layout: layout,
                      cards: cards,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ContactLayoutKind {
  desktop,
  medium,
  compact,
}

class _ContactLayout {
  const _ContactLayout({
    required this.kind,
    required this.availableWidth,
    required this.headingSize,
  });

  factory _ContactLayout.resolve({
    required double availableWidth,
  }) {
    if (availableWidth >= 1088) {
      return _ContactLayout(
        kind: _ContactLayoutKind.desktop,
        availableWidth: availableWidth,
        headingSize: 40,
      );
    }
    // The content frame owns 24 logical pixels of horizontal padding per
    // side by default, so 552 corresponds to the 600px viewport breakpoint.
    if (availableWidth >= 552) {
      return _ContactLayout(
        kind: _ContactLayoutKind.medium,
        availableWidth: availableWidth,
        headingSize: 34,
      );
    }
    return _ContactLayout(
      kind: _ContactLayoutKind.compact,
      availableWidth: availableWidth,
      headingSize: 26,
    );
  }

  final _ContactLayoutKind kind;
  final double availableWidth;
  final double headingSize;
}

class _ContactCardsLayout extends StatelessWidget {
  const _ContactCardsLayout({
    required this.layout,
    required this.cards,
  });

  final _ContactLayout layout;
  final List<_ContactCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.length == 1) {
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          key: cards.single.key,
          width: math.min(520, layout.availableWidth),
          child: cards.single.child,
        ),
      );
    }

    return switch (layout.kind) {
      _ContactLayoutKind.desktop => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              if (index > 0) const SizedBox(width: 24),
              SizedBox(
                key: cards[index].key,
                width: cards[index].desktopWidth,
                child: cards[index].child,
              ),
            ],
          ],
        ),
      _ContactLayoutKind.medium => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox(
                    key: cards[0].key,
                    width: double.infinity,
                    child: cards[0].child,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: SizedBox(
                    key: cards[1].key,
                    width: double.infinity,
                    child: cards[1].child,
                  ),
                ),
              ],
            ),
            if (cards.length > 2) ...[
              const SizedBox(height: 24),
              SizedBox(
                key: cards[2].key,
                width: double.infinity,
                child: cards[2].child,
              ),
            ],
          ],
        ),
      _ContactLayoutKind.compact => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              if (index > 0) const SizedBox(height: 24),
              SizedBox(
                key: cards[index].key,
                width: layout.availableWidth,
                child: cards[index].child,
              ),
            ],
          ],
        ),
    };
  }
}

class _ContactCard {
  const _ContactCard({
    required this.key,
    required this.desktopWidth,
    required this.child,
  });

  final Key key;
  final double desktopWidth;
  final Widget child;
}

class _ContactInfoCard extends StatelessWidget {
  const _ContactInfoCard({
    required this.phone,
    required this.email,
    required this.address,
    required this.headingFont,
    required this.bodyFont,
  });

  final String phone;
  final String email;
  final String address;
  final String? headingFont;
  final String? bodyFont;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[
      if (phone.isNotEmpty)
        _ContactDetail(
          icon: Icons.phone,
          label: 'Teléfono',
          value: phone,
          bodyFont: bodyFont,
        ),
      if (email.isNotEmpty)
        _ContactDetail(
          icon: Icons.email_outlined,
          label: 'Correo',
          value: email,
          bodyFont: bodyFont,
        ),
      if (address.isNotEmpty)
        _ContactDetail(
          icon: Icons.location_on_outlined,
          label: 'Dirección',
          value: address,
          bodyFont: bodyFont,
        ),
    ];

    return _ContactSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información de contacto',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: headingFont,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Text(
              'Completa tus datos de contacto desde el editor.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: bodyFont,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...items,
        ],
      ),
    );
  }
}

class _ContactDetail extends StatelessWidget {
  const _ContactDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.bodyFont,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? bodyFont;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: bodyFont,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: bodyFont,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactFormCard extends StatelessWidget {
  const _ContactFormCard({
    required this.primaryColor,
    required this.headingFont,
  });

  final Color primaryColor;
  final String? headingFont;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ContactSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Envíanos un mensaje',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: headingFont,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const _DisabledContactField(label: 'Nombre'),
          const SizedBox(height: 12),
          const _DisabledContactField(label: 'Correo electrónico'),
          const SizedBox(height: 12),
          const _DisabledContactField(
            label: 'Mensaje',
            maxLines: 4,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar consulta'),
          ),
        ],
      ),
    );
  }
}

class _DisabledContactField extends StatelessWidget {
  const _DisabledContactField({
    required this.label,
    this.maxLines = 1,
  });

  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
    );
  }
}

class _ContactMapCard extends StatelessWidget {
  const _ContactMapCard({
    required this.accentColor,
    required this.headingFont,
    required this.showAction,
    required this.onOpenMap,
  });

  final Color accentColor;
  final String? headingFont;
  final bool showAction;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ContactSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cómo llegar',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: headingFont,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Icon(
                Icons.map_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (showAction) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              key: WebsiteContactBlockContent.mapActionKey,
              onPressed: onOpenMap,
              icon: const Icon(Icons.arrow_outward),
              label: const Text('Abrir mapa'),
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactSurfaceCard extends StatelessWidget {
  const _ContactSurfaceCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    );
  }
}
