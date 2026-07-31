import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

@immutable
class WebsiteTextBlockPresentation {
  const WebsiteTextBlockPresentation({
    required this.text,
    required this.preset,
    required this.baseStyle,
    required this.formatting,
    required this.maxWidth,
  });

  factory WebsiteTextBlockPresentation.resolve({
    required BuildContext context,
    required Map<String, dynamic> data,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
  }) {
    final text = (data['text'] ?? '').toString();
    final preset = (data['preset'] ?? 'paragraph').toString();
    final rawFormatting = data['formatting'];
    final formatting = TextFormatting.fromJson(
      rawFormatting is Map ? Map<String, dynamic>.from(rawFormatting) : null,
    );
    final theme = Theme.of(context).textTheme;

    final TextStyle baseStyle;
    switch (preset) {
      case 'heading':
        baseStyle = theme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: headingFont,
              fontSize: headingSize,
            ) ??
            TextStyle(
              fontSize: headingSize ?? 36,
              fontWeight: FontWeight.w700,
              fontFamily: headingFont,
            );
      case 'subheading':
        baseStyle = theme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: headingFont,
            ) ??
            TextStyle(
              fontSize: (bodySize ?? 16) * 1.25,
              fontWeight: FontWeight.w600,
              fontFamily: headingFont,
            );
      case 'caption':
        baseStyle = theme.bodySmall?.copyWith(
              fontFamily: bodyFont,
              fontSize: (bodySize ?? 16) * 0.9,
            ) ??
            TextStyle(
              fontSize: (bodySize ?? 16) * 0.9,
              fontFamily: bodyFont,
            );
      default:
        baseStyle = theme.bodyLarge?.copyWith(
              fontFamily: bodyFont,
              fontSize: bodySize,
            ) ??
            TextStyle(
              fontSize: bodySize ?? 16,
              fontFamily: bodyFont,
            );
    }

    return WebsiteTextBlockPresentation(
      text: text,
      preset: preset,
      baseStyle: baseStyle,
      formatting: formatting,
      maxWidth: _resolveMaxWidth(data['maxWidth']),
    );
  }

  final String text;
  final String preset;
  final TextStyle baseStyle;
  final TextFormatting formatting;
  final double? maxWidth;

  TextStyle get effectiveStyle => formatting.applyTo(baseStyle);

  TextAlign get textAlign => formatting.textAlign;

  static double? _resolveMaxWidth(Object? raw) {
    final parsed = switch (raw) {
      num value => value.toDouble(),
      String value => double.tryParse(value.trim()),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.clamp(200.0, 1200.0).toDouble();
  }
}

/// Canonical responsive frame for the text block's editor-owned max width.
class WebsiteTextWidthFrame extends StatelessWidget {
  const WebsiteTextWidthFrame({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  final double? maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final configuredWidth = maxWidth;
    if (configuredWidth == null) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : configuredWidth;
        final width = math.min(configuredWidth, availableWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            key: const ValueKey<String>('website-text-width-frame-box'),
            width: math.max(0, width),
            child: child,
          ),
        );
      },
    );
  }
}

/// Pure shared content for a standalone text block.
///
/// Preview and public paint [Text]. Edit may inject an inline presenter from
/// the deferred editor library, but it consumes this same presentation.
class WebsiteTextBlockContent extends StatelessWidget {
  const WebsiteTextBlockContent({
    super.key,
    required this.presentation,
    this.inlinePresenter,
  });

  final WebsiteTextBlockPresentation presentation;
  final WebsiteInlineTextPresenter? inlinePresenter;

  @override
  Widget build(BuildContext context) {
    final presenter = inlinePresenter;
    if (presenter != null) {
      return presenter(
        context,
        WebsiteInlineTextSlot(
          id: 'standalone-text',
          value: presentation.text,
          valueKeys: const ['text'],
          baseStyle: presentation.baseStyle,
          formatting: presentation.formatting,
          formattingKeys: const ['formatting'],
          textAlign: presentation.textAlign,
          placeholder: 'Haz clic para escribir',
          maxWidth: presentation.maxWidth,
          widthKeys: const ['maxWidth'],
        ),
      );
    }

    return WebsiteTextWidthFrame(
      maxWidth: presentation.maxWidth,
      child: Text(
        presentation.text,
        style: presentation.effectiveStyle,
        textAlign: presentation.textAlign,
      ),
    );
  }
}
