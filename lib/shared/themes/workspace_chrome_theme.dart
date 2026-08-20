import 'package:flutter/material.dart';

import 'appearance_preset.dart';
import 'sidebar_palette_option.dart';
import 'vinabike_theme_resolver.dart';
import 'vinabike_theme_roles.dart';
import '../widgets/workspace_shell_scope.dart';

/// Resolves one semantic chrome vocabulary for the workspace bar, module
/// command bars and both navigation compositions.
///
/// The shell is intentionally dark in light and dark application modes. The
/// selected palette changes its hue and contrast roles; [brightness] remains
/// an explicit input so future Design-approved dark variants can be added
/// here without changing any consumer.
abstract final class WorkspaceChromeTheme {
  static WorkspaceChromeStyleData resolve({
    required SidebarPaletteOption palette,
    required Brightness brightness,
  }) {
    final preset = AppearancePresets.maybeByCode(palette.code);
    if (preset != null) {
      final roles = VinabikeThemeResolver.rolesFor(
        preset: preset,
        brightness: brightness,
      );
      return WorkspaceChromeStyleData.fromThemeRoles(roles);
    }

    // Preserve the public API for an external/custom legacy palette that has
    // not joined the canonical preset catalog yet.
    return WorkspaceChromeStyleData(
      canvas: palette.background,
      raised: palette.backgroundAlt,
      edge: palette.border,
      foreground: palette.foreground,
      mutedForeground: palette.mutedForeground,
      accent: palette.accent,
      onAccent: palette.onAccent,
      dirty: const Color(0xFFF5B545),
      attention: const Color(0xFFF2637A),
    );
  }

  /// Reads shell roles from the already-resolved root app theme.
  ///
  /// Canonical shell hosts use this path so the workspace cannot drift from
  /// the selected app preset. [resolve] remains as the compatibility entry
  /// point for scoped legacy consumers and tests.
  static WorkspaceChromeStyleData resolveFromTheme(
    ThemeData theme, {
    WorkspaceChromeStyleData fallback = WorkspaceChromeStyleData.vinabike,
  }) {
    final roles = theme.extension<VinabikeThemeRoles>();
    return roles == null
        ? fallback
        : WorkspaceChromeStyleData.fromThemeRoles(roles);
  }

  static ThemeData sidebarTheme(
    ThemeData baseTheme,
    WorkspaceChromeStyleData chrome,
  ) {
    final chromeBrightness = chrome.canvas.computeLuminance() < 0.35
        ? Brightness.dark
        : Brightness.light;
    final surfaceDim = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.12),
      chrome.canvas,
    );
    final surfaceContainerLow = Color.alphaBlend(
      chrome.raised.withValues(alpha: 0.36),
      chrome.canvas,
    );
    final surfaceContainer = Color.alphaBlend(
      chrome.raised.withValues(alpha: 0.58),
      chrome.canvas,
    );
    final surfaceContainerHigh = Color.alphaBlend(
      chrome.raised.withValues(alpha: 0.8),
      chrome.canvas,
    );
    final surfaceBright = chromeBrightness == Brightness.dark
        ? Color.alphaBlend(
            chrome.foreground.withValues(alpha: 0.08),
            chrome.raised,
          )
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.72),
            chrome.raised,
          );
    final selectionContainer = Color.alphaBlend(
      chrome.accent.withValues(alpha: 0.14),
      chrome.canvas,
    );
    final warningContainer = Color.alphaBlend(
      chrome.dirty.withValues(alpha: 0.16),
      chrome.canvas,
    );
    final errorContainer = Color.alphaBlend(
      chrome.attention.withValues(alpha: 0.16),
      chrome.canvas,
    );
    final disabledForeground = chrome.mutedForeground.withValues(alpha: 0.52);
    final textTheme = baseTheme.textTheme.apply(
      bodyColor: chrome.foreground,
      displayColor: chrome.foreground,
    );
    final colorScheme = baseTheme.colorScheme.copyWith(
      brightness: chromeBrightness,
      primary: chrome.accent,
      onPrimary: chrome.onAccent,
      primaryContainer: selectionContainer,
      onPrimaryContainer: _contrastSafeForeground(
        chrome.accent,
        selectionContainer,
      ),
      secondary: chrome.accent,
      onSecondary: chrome.onAccent,
      secondaryContainer: chrome.raised,
      onSecondaryContainer: chrome.foreground,
      tertiary: chrome.dirty,
      onTertiary: _bestForegroundFor(chrome.dirty),
      tertiaryContainer: warningContainer,
      onTertiaryContainer: _contrastSafeForeground(
        chrome.dirty,
        warningContainer,
      ),
      error: chrome.attention,
      onError: _bestForegroundFor(chrome.attention),
      errorContainer: errorContainer,
      onErrorContainer: _contrastSafeForeground(
        chrome.attention,
        errorContainer,
      ),
      surface: chrome.canvas,
      onSurface: chrome.foreground,
      onSurfaceVariant: chrome.mutedForeground,
      surfaceDim: surfaceDim,
      surfaceBright: surfaceBright,
      surfaceContainerLowest:
          chromeBrightness == Brightness.dark ? surfaceDim : chrome.canvas,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: chrome.raised,
      outline: chrome.edge,
      outlineVariant: chrome.edge,
      surfaceTint: chrome.accent,
      inverseSurface: chrome.foreground,
      onInverseSurface: chrome.canvas,
      inversePrimary: chrome.onAccent,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: chrome.edge),
    );

    return baseTheme.copyWith(
      brightness: chromeBrightness,
      primaryColor: chrome.accent,
      dividerColor: chrome.edge,
      scaffoldBackgroundColor: chrome.canvas,
      canvasColor: chrome.canvas,
      cardColor: chrome.raised,
      disabledColor: disabledForeground,
      focusColor: chrome.accent.withValues(alpha: 0.18),
      hoverColor: chrome.foreground.withValues(alpha: 0.06),
      highlightColor: chrome.foreground.withValues(alpha: 0.08),
      splashColor: chrome.accent.withValues(alpha: 0.12),
      iconTheme: baseTheme.iconTheme.copyWith(
        color: chrome.mutedForeground,
      ),
      primaryIconTheme: baseTheme.primaryIconTheme.copyWith(
        color: chrome.foreground,
      ),
      textTheme: textTheme,
      listTileTheme: baseTheme.listTileTheme.copyWith(
        iconColor: chrome.mutedForeground,
        textColor: chrome.foreground,
        selectedColor: colorScheme.onPrimaryContainer,
        selectedTileColor: colorScheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: chrome.edge,
        thickness: 1,
        space: 1,
      ),
      // Mismo defecto que el `segmentedButtonTheme` de abajo: `menuTheme` y
      // `popupMenuTheme` capturan el esquema de la APP, así que un desplegable
      // abierto desde la barra o el riel salía con fondo blanco y, una vez que
      // el texto sí heredó el chrome, con letra clara sobre blanco: ilegible.
      popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium?.copyWith(color: chrome.foreground),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: chrome.foreground),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: chrome.edge),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(colorScheme.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          side: WidgetStatePropertyAll(BorderSide(color: chrome.edge)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return disabledForeground;
            return chrome.foreground;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return disabledForeground;
            return chrome.mutedForeground;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return chrome.accent.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return chrome.foreground.withValues(alpha: 0.08);
            }
            return null;
          }),
        ),
      ),
      // El `segmentedButtonTheme` de la app resuelve sus colores contra el
      // esquema de la APP, capturado en un closure. Sustituir el `colorScheme`
      // aquí no lo alcanza, así que un SegmentedButton dentro de la barra salía
      // claro sobre el navy — se veía en «Menú lateral» y en el selector de
      // tema. Se reemplaza entero contra el esquema del chrome.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledForeground;
            }
            return states.contains(WidgetState.selected)
                ? colorScheme.onPrimaryContainer
                : chrome.mutedForeground;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.surfaceContainerLowest;
            }
            return states.contains(WidgetState.selected)
                ? selectionContainer
                : colorScheme.surfaceContainerLow;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return chrome.accent.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return chrome.foreground.withValues(alpha: 0.06);
            }
            return null;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.selected)
                  ? chrome.accent
                  : chrome.edge,
            );
          }),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: chrome.canvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      cardTheme: baseTheme.cardTheme.copyWith(
        color: chrome.raised,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: chrome.mutedForeground,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: chrome.mutedForeground,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: chrome.accent,
        ),
        prefixIconColor: chrome.mutedForeground,
        suffixIconColor: chrome.mutedForeground,
        iconColor: chrome.mutedForeground,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(
            color: chrome.accent,
            width: 1.5,
          ),
        ),
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: disabledForeground),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: chrome.accent,
        selectionColor: chrome.accent.withValues(alpha: 0.28),
        selectionHandleColor: chrome.accent,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledForeground;
            }
            if (states.contains(WidgetState.selected)) {
              return chrome.accent;
            }
            return chrome.mutedForeground;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return selectionContainer;
            }
            return Colors.transparent;
          }),
          overlayColor: _interactiveOverlay(chrome),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? disabledForeground
                : chrome.accent;
          }),
          overlayColor: _interactiveOverlay(chrome),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? disabledForeground
                : chrome.foreground;
          }),
          overlayColor: _interactiveOverlay(chrome),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? disabledForeground
                  : chrome.edge,
            );
          }),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? disabledForeground
                : chrome.onAccent;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? surfaceContainerHigh
                : chrome.accent;
          }),
          overlayColor: WidgetStatePropertyAll(
            chrome.onAccent.withValues(alpha: 0.12),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return surfaceContainerHigh;
          }
          if (states.contains(WidgetState.selected)) {
            return chrome.accent;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(chrome.onAccent),
        side: BorderSide(color: chrome.edge),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabledForeground;
          }
          if (states.contains(WidgetState.selected)) {
            return chrome.accent;
          }
          return chrome.mutedForeground;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabledForeground;
          }
          return states.contains(WidgetState.selected)
              ? chrome.onAccent
              : chrome.mutedForeground;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return surfaceContainerHigh;
          }
          return states.contains(WidgetState.selected)
              ? chrome.accent
              : colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStatePropertyAll(chrome.edge),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        textColor: chrome.foreground,
        collapsedTextColor: chrome.foreground,
        iconColor: chrome.mutedForeground,
        collapsedIconColor: chrome.mutedForeground,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      colorScheme: colorScheme,
    );
  }

  static WidgetStateProperty<Color?> _interactiveOverlay(
    WorkspaceChromeStyleData chrome,
  ) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return chrome.accent.withValues(alpha: 0.16);
      }
      if (states.contains(WidgetState.focused)) {
        return chrome.accent.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered)) {
        return chrome.foreground.withValues(alpha: 0.06);
      }
      return null;
    });
  }

  static Color _bestForegroundFor(Color background) {
    const dark = Color(0xFF07141D);
    const light = Color(0xFFF7FBFE);
    final darkContrast = _contrastRatio(dark, background);
    final lightContrast = _contrastRatio(light, background);
    return darkContrast >= lightContrast ? dark : light;
  }

  static Color _contrastSafeForeground(
    Color preferred,
    Color background,
  ) {
    return _contrastRatio(preferred, background) >= 4.5
        ? preferred
        : _bestForegroundFor(background);
  }

  static double _contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter =
        firstLuminance >= secondLuminance ? firstLuminance : secondLuminance;
    final darker =
        firstLuminance >= secondLuminance ? secondLuminance : firstLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static BoxDecoration sidebarDecoration(
    WorkspaceChromeStyleData chrome,
  ) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          chrome.canvas,
          Color.alphaBlend(
            chrome.accent.withValues(alpha: 0.08),
            chrome.raised,
          ),
        ],
      ),
    );
  }
}
