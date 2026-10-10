import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../services/website_service.dart';
import '../theme/website_resolved_theme.dart';
import '../theme/website_theme_builder.dart';
import 'catalog_web_models.dart';

/// The store's own theme (colors and fonts saved in the editor), so a
/// preview looks like vinabike.cl and not like the ERP.
ThemeData catalogStoreTheme(BuildContext context) {
  final base = ThemeData.light(useMaterial3: true);
  WebsiteService? service;
  try {
    service = context.read<WebsiteService>();
  } catch (_) {
    service = null;
  }
  final resolved = service == null
      ? WebsiteResolvedTheme.fallback
      : WebsiteResolvedTheme.resolve(service.getSetting);
  return WebsiteThemeBuilder.build(base: base, resolved: resolved);
}

/// The store the previews link to.
const catalogStoreOrigin = 'https://vinabike.cl';

/// An amount that never breaks between the sign and the number.
String catalogMoney(num amount) =>
    ChileanUtils.formatCurrency(amount.toDouble())
        .replaceFirst(r'$ ', '\$\u00A0');

/// The public page of an item, as the store builds its URL.
String catalogPublicPath(CatalogWebItem item) => buildPublicProductPath(
      name: item.displayName,
      sku: item.sku,
      fallbackProductId: item.id,
    );

Future<void> openCatalogStorePath(BuildContext context, String path) async {
  final uri = Uri.parse('$catalogStoreOrigin$path');
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo abrir $uri')),
    );
  }
}

VbStatusTone catalogStateTone(CatalogItemState state) => switch (state) {
      CatalogItemState.selling => VbStatusTone.success,
      CatalogItemState.soldOut => VbStatusTone.info,
      CatalogItemState.blocked => VbStatusTone.warning,
      CatalogItemState.hidden => VbStatusTone.neutral,
      CatalogItemState.workshop => VbStatusTone.neutral,
    };

IconData catalogStateIcon(CatalogItemState state) => switch (state) {
      CatalogItemState.selling => Icons.storefront_outlined,
      CatalogItemState.soldOut => Icons.inventory_2_outlined,
      CatalogItemState.blocked => Icons.error_outline,
      CatalogItemState.hidden => Icons.visibility_off_outlined,
      CatalogItemState.workshop => Icons.handyman_outlined,
    };

/// The dot that stands for a state in a tab: it differs in lightness, not
/// only in hue, and the tab's text always names it.
Color catalogStateDot(BuildContext context, CatalogItemState state) {
  final roles = VinabikeThemeRoles.of(context);
  final scheme = Theme.of(context).colorScheme;
  return switch (state) {
    CatalogItemState.selling => roles.success.accent,
    CatalogItemState.soldOut => roles.info.accent,
    CatalogItemState.blocked => roles.warning.accent,
    CatalogItemState.hidden => scheme.outline,
    CatalogItemState.workshop => scheme.tertiary,
  };
}

class CatalogStateBadge extends StatelessWidget {
  const CatalogStateBadge(this.state, {super.key, this.dense = false});

  final CatalogItemState state;
  final bool dense;

  @override
  Widget build(BuildContext context) => VbStatusBadge(
        label: state.label,
        tone: catalogStateTone(state),
        icon: catalogStateIcon(state),
        dense: dense,
      );
}

/// The item's photo, or an empty dashed box that says it has none.
class CatalogThumb extends StatelessWidget {
  const CatalogThumb({super.key, required this.item, this.size = 44});

  final CatalogWebItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final radius = BorderRadius.circular(size >= 80 ? 12 : 9);
    final url = item.imageUrl;
    if (url == null) {
      final needsPhoto = item.kind.sellsGoods &&
          item.state != CatalogItemState.workshop &&
          item.state != CatalogItemState.hidden;
      return Semantics(
        label: 'Sin foto',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: needsPhoto
                ? roles.warning.container
                : scheme.surfaceContainerHigh,
            border: Border.all(
              color: needsPhoto ? roles.warning.border : scheme.outlineVariant,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            item.kind == CatalogItemKind.service
                ? Icons.build_outlined
                : Icons.no_photography_outlined,
            size: size * 0.42,
            color: needsPhoto
                ? roles.warning.onContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: scheme.surfaceContainerHigh,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          memCacheWidth: (size * 3).round(),
          errorWidget: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            size: size * 0.42,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A label over a value, as the detail pane and the cards line facts up.
class CatalogFact extends StatelessWidget {
  const CatalogFact({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The frame of every «así se ve en vinabike.cl» preview: what the
/// customer sees, drawn by the store's own components, with the real page
/// one click away.
class CatalogStorePreview extends StatelessWidget {
  const CatalogStorePreview({
    super.key,
    required this.title,
    required this.child,
    this.path,
    this.note,
  });

  final String title;
  final Widget child;

  /// The live page, when there is one to open.
  final String? path;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Icon(Icons.public, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (path != null)
                  TextButton.icon(
                    onPressed: () => openCatalogStorePath(context, path!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Página real'),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Theme(
              data: catalogStoreTheme(context),
              child: child,
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The message under a list that has nothing to show.
class CatalogEmpty extends StatelessWidget {
  const CatalogEmpty({super.key, required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 32, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows what a write did, or why it failed, in the operator's words.
void showCatalogMessage(BuildContext context, String message,
    {SnackBarAction? action}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      duration: Duration(seconds: action == null ? 4 : 8),
    ));
}

String catalogErrorMessage(Object error) {
  // The base already says which product and why, in the owner's words
  // (20261010060000).
  if (error is PostgrestException &&
      error.hint == 'catalog_featured_not_on_sale') {
    return error.message;
  }
  final text = '$error';
  if (text.contains('catalog_edit_forbidden')) {
    return 'Tu cuenta no puede cambiar el catálogo web (pide el permiso de editar ajustes).';
  }
  if (text.contains('catalog_consumable_not_for_web') ||
      text.contains('Es consumible del taller')) {
    return 'Es consumible del taller: conviértelo en producto de venta antes de venderlo en la web.';
  }
  if (text.contains('No se puede desactivar el control de inventario')) {
    return 'Tiene stock: primero hay que pasar ese stock a gasto. Ábrelo en su ficha.';
  }
  return 'No se pudo guardar: $text';
}
