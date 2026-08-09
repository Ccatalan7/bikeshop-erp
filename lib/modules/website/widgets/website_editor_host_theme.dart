import 'package:flutter/material.dart';

import '../../../shared/themes/app_theme.dart';
import '../../../shared/themes/appearance_preset.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';

/// The ERP's own appearance, carried across the storefront theme boundary.
///
/// **The boundary this exists to hold.** Inside the editor the tree crosses one
/// deliberate line: everything below `Theme(data: websiteTheme)` renders the
/// tenant's *authored* site, and must, because that is what the operator is
/// judging. But the operator's own chrome — selection rings, badges, docks,
/// sheets, toolbars — is not part of the site. Reading `Theme.of` below that
/// line dressed the editor's tools in the customer's brand, made them change
/// when the tenant changed their palette, and could put a light selection ring
/// on a light site in a dark ERP.
///
/// The shell publishes the host appearance above the storefront and any chrome
/// mounted underneath restores it explicitly. It is not a copy of the theme:
/// it is the one the app already resolved, passed through.
class WebsiteEditorHostTheme extends InheritedWidget {
  const WebsiteEditorHostTheme({
    super.key,
    required this.theme,
    required this.roles,
    required super.child,
  });

  /// The ERP `ThemeData` in force above the storefront.
  final ThemeData theme;

  /// The ERP semantic roles in force above the storefront, when it publishes
  /// them. Null only for a build that ships no role extension at all.
  final VinabikeThemeRoles? roles;

  static WebsiteEditorHostTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WebsiteEditorHostTheme>();

  /// Publishes whatever appearance is in force at [context].
  ///
  /// Called ABOVE the storefront's own `Theme`, so what it captures is the ERP.
  static Widget capture({
    required BuildContext context,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return WebsiteEditorHostTheme(
      theme: theme,
      roles: theme.extension<VinabikeThemeRoles>(),
      child: child,
    );
  }

  @override
  bool updateShouldNotify(WebsiteEditorHostTheme oldWidget) =>
      theme != oldWidget.theme || roles != oldWidget.roles;
}

/// The Website Builder inspector's own dark appearance.
///
/// The inspector is an authoring instrument, not authored storefront content
/// and not ordinary ERP chrome. Its desktop pane was designed on a graphite
/// canvas and its controls use the matching dark ink hierarchy. O-05 reuses
/// those exact controls, so the whole surface must cross this boundary
/// together: title, tabs, controls and footer. Applying dark only to the
/// deferred body creates the split light/dark sheet this owner prevents.
///
/// Design source: `ERP Bikeshop UI Mockups` ->
/// `Website Builder · Estilo de bloque.dc.html`, turn t19, frames 19a-19k.
/// The inspector remains graphite in both host brightnesses. These three
/// literals are the published graphite variant-B layers; semantic tones still
/// resolve through the active ERP preset so universal controls such as
/// `VbSubTabs` and `VbStatusBadge` keep their canonical role model.
abstract final class WebsiteEditorInspectorTheme {
  static const Color canvas = Color(0xFF0A1524);
  static const Color raised = Color(0xFF111A25);
  static const Color selection = Color(0xFF17263B);

  /// Resolves a dark inspector regardless of the ERP's current brightness.
  static ThemeData resolveFrom(BuildContext context) {
    final host = WebsiteEditorHostTheme.maybeOf(context);
    final hostTheme = host?.theme ?? Theme.of(context);
    final hostRoles = host?.roles ?? hostTheme.extension<VinabikeThemeRoles>();
    final preset = AppearancePresets.byCode(
      hostRoles?.presetCode ?? AppearancePresets.vinabike.code,
    );
    final dark = AppTheme.resolve(
      preset: preset,
      brightness: Brightness.dark,
    );
    final scheme = dark.colorScheme.copyWith(
      surface: canvas,
      surfaceDim: canvas,
      surfaceBright: raised,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: canvas,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: raised,
    );
    final resolvedRoles = dark.extension<VinabikeThemeRoles>();
    final extensions = List<ThemeExtension<dynamic>>.of(
      dark.extensions.values,
    )..removeWhere((extension) => extension is VinabikeThemeRoles);
    if (resolvedRoles != null) {
      extensions.add(
        resolvedRoles.copyWith(selectionContainer: selection),
      );
    }

    return dark.copyWith(
      colorScheme: scheme,
      extensions: extensions,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: raised,
      dividerColor: Colors.white12,
      dividerTheme: const DividerThemeData(
        color: Colors.white12,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
