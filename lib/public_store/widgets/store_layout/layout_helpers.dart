part of '../public_store_layout.dart';

Future<void> _launchUri(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

/// Resolves a saved social value that may be a handle **or** a full URL.
///
/// Owners type both forms interchangeably, so the renderer must accept both
/// and produce one valid destination. An unset network returns `null` and the
/// caller omits the icon entirely — it never falls back to another tenant's
/// account.
///
/// [keepAtPrefix] is required by YouTube, whose canonical handle URL is
/// `youtube.com/@handle`; stripping the `@` there produced a dead link.
@visibleForTesting
String? normalizeSocialUrl(
  String raw,
  String baseUrl, {
  bool keepAtPrefix = false,
}) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  // Already absolute: accept only real web schemes so a saved `javascript:`
  // or `mailto:` value can never become a footer link.
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    if (!parsed.isScheme('http') && !parsed.isScheme('https')) return null;
    return parsed.host.isEmpty ? null : value;
  }

  // Scheme-less absolute form, e.g. `www.instagram.com/tienda`.
  if (value.startsWith('www.') || value.contains('/')) {
    final host = Uri.tryParse('https://$value');
    if (host != null && host.host.contains('.')) return 'https://$value';
  }

  // Plain handle.
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  final withoutAt = value.startsWith('@') ? value.substring(1) : value;
  if (withoutAt.isEmpty) return null;
  return '$baseUrl${keepAtPrefix ? '@$withoutAt' : withoutAt}';
}

String _sanitizePhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '';
  }
  if (digits.startsWith('56')) {
    return digits;
  }
  if (digits.length == 9 && digits.startsWith('9')) {
    return '56$digits';
  }
  if (digits.length == 8) {
    return '56$digits';
  }
  return digits;
}

Color _resolveColor(String raw, Color fallback) {
  final value = raw.trim();
  if (value.isEmpty) return fallback;

  Color? parsed;
  int? intValue;

  String cleaned = value.toLowerCase();
  if (cleaned.startsWith('color(')) {
    final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
    intValue = int.tryParse(inside);
  }

  intValue ??= int.tryParse(cleaned);
  if (intValue == null && cleaned.startsWith('0x')) {
    intValue = int.tryParse(cleaned);
  }
  if (intValue == null) {
    cleaned = cleaned.replaceAll('#', '');
    intValue = int.tryParse(cleaned, radix: 16);
    if (intValue != null && cleaned.length <= 6) {
      intValue = 0xFF000000 | intValue;
    }
  }

  if (intValue != null) {
    parsed = Color(intValue);
  }

  return parsed ?? fallback;
}

Map<String, MegaMenuBranchPresentation> _projectMegaMenuBranchPresentations({
  required Iterable<WebsiteNavigation> branches,
  required WebsiteCatalogPresentationRegistry registry,
}) {
  final projections = <String, MegaMenuBranchPresentation>{};
  void visit(WebsiteNavigation branch) {
    final destination = WebsiteDestination.parse(branch.href ?? '');
    if (destination.kind == WebsiteDestinationKind.category) {
      final reference = destination.reference?.trim() ?? '';
      final presentation = reference.isEmpty
          ? null
          : registry.forCategory(reference) ??
              registry.resolveSlug(reference)?.presentation;
      if (presentation != null) {
        projections[branch.id] = MegaMenuBranchPresentation(
          imageUrl: presentation.megaMenuImageUrl,
          overlay: presentation.megaMenuOverlay,
          cardOverlay: presentation.megaMenuCardOverlay,
          overviewWidth: presentation.megaMenuOverviewWidth,
          contentAlignment: presentation.megaMenuContentAlignment,
        );
      }
    }

    for (final child in branch.children) {
      visit(child);
    }
  }

  for (final branch in branches) {
    visit(branch);
  }
  return Map<String, MegaMenuBranchPresentation>.unmodifiable(projections);
}
