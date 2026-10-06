part of '../public_store_layout.dart';

Future<void> _launchUri(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

// `normalizeSocialUrl` lives in vinabike_public_core since 2026-10-05
// (public_store/utils/social_url.dart): the HTML footer links the same way.

String _sanitizePhone(String input) => whatsappDigits(input);

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
    // The HTML store's wide menu reads the same owner.
    final presentation = megaMenuPresentationOf(branch, registry);
    if (presentation != null) {
      projections[branch.id] = MegaMenuBranchPresentation(
        imageUrl: presentation.megaMenuImageUrl,
        overlay: presentation.megaMenuOverlay,
        cardOverlay: presentation.megaMenuCardOverlay,
        overviewWidth: presentation.megaMenuOverviewWidth,
        contentAlignment: presentation.megaMenuContentAlignment,
      );
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
