import 'package:flutter/material.dart';

import 'appearance_preset.dart';
import 'vinabike_theme_roles.dart';

/// Sole resolver from persisted appearance intent to a complete app theme.
///
/// The resolver owns preset × brightness semantics. `AppearanceService`
/// persists the selected preset and mode; widgets consume [ThemeData] and
/// [VinabikeThemeRoles] only.
abstract final class VinabikeThemeResolver {
  static ThemeData resolve({
    required ThemeData baseTheme,
    required AppearancePreset preset,
    required Brightness brightness,
  }) {
    final palette = _ResolvedContentPalette.resolve(preset, brightness);
    final roles = _rolesFor(
      preset: preset,
      brightness: brightness,
      palette: palette,
    );
    final scheme = palette.colorScheme;
    final textTheme = baseTheme.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final primaryTextTheme = baseTheme.primaryTextTheme.apply(
      bodyColor: scheme.onPrimary,
      displayColor: scheme.onPrimary,
    );
    final disabledSurface = Color.alphaBlend(
      roles.disabledForeground.withValues(alpha: 0.08),
      scheme.surfaceContainerHigh,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    final componentShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final overlay = _interactiveOverlay(scheme);
    final scrollbarTrack = scheme.surfaceContainerHighest;
    final scrollbarThumb = _ResolvedContentPalette._minimumContrastBlend(
      foreground: scheme.onSurfaceVariant,
      background: scrollbarTrack,
      minimumRatio: 3,
    );
    final scrollbarHoverThumb = _ResolvedContentPalette._minimumContrastBlend(
      foreground: scheme.onSurfaceVariant,
      background: scrollbarTrack,
      minimumRatio: 4.5,
    );
    final scrollbarDraggedThumb = _ResolvedContentPalette._minimumContrastBlend(
      foreground: scheme.onSurface,
      background: scrollbarTrack,
      minimumRatio: 7,
    );
    final extensions = List<ThemeExtension<dynamic>>.of(
      baseTheme.extensions.values,
    )
      ..removeWhere((extension) => extension is VinabikeThemeRoles)
      ..add(roles);

    final contentCanvas = brightness == Brightness.dark
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainer;

    return baseTheme.copyWith(
      brightness: brightness,
      colorScheme: scheme,
      extensions: extensions,
      primaryColor: scheme.primary,
      primaryColorDark: scheme.primary,
      primaryColorLight: scheme.primaryContainer,
      // Light content keeps the canonical canvas/card separation used by the
      // new Payroll language: a quiet neutral canvas with white working
      // surfaces. Palette tint belongs to accents and explicit semantic
      // containers, never every legacy Card/Input in the application.
      scaffoldBackgroundColor: contentCanvas,
      canvasColor: scheme.surface,
      cardColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      disabledColor: roles.disabledForeground,
      focusColor: roles.focusRing.withValues(alpha: 0.2),
      hoverColor: scheme.onSurface.withValues(alpha: 0.05),
      highlightColor: scheme.onSurface.withValues(alpha: 0.07),
      splashColor: scheme.primary.withValues(alpha: 0.12),
      shadowColor: roles.shadow,
      hintColor: scheme.onSurfaceVariant,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      iconTheme: baseTheme.iconTheme.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      primaryIconTheme: baseTheme.primaryIconTheme.copyWith(
        color: scheme.onPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.onPrimary),
        actionsIconTheme: IconThemeData(color: scheme.onPrimary),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: baseTheme.listTileTheme.copyWith(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        selectedColor: scheme.onPrimaryContainer,
        selectedTileColor: scheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        iconColor: scheme.onSurfaceVariant,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: roles.focusRing, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: scheme.primary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: _buttonForeground(
            enabled: scheme.onPrimary,
            disabled: roles.disabledForeground,
          ),
          backgroundColor: _buttonBackground(
            enabled: scheme.primary,
            disabled: disabledSurface,
          ),
          overlayColor: WidgetStatePropertyAll(
            scheme.onPrimary.withValues(alpha: 0.12),
          ),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          foregroundColor: _buttonForeground(
            enabled: scheme.onPrimary,
            disabled: roles.disabledForeground,
          ),
          backgroundColor: _buttonBackground(
            enabled: scheme.primary,
            disabled: disabledSurface,
          ),
          overlayColor: WidgetStatePropertyAll(
            scheme.onPrimary.withValues(alpha: 0.12),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: _buttonForeground(
            enabled: scheme.primary,
            disabled: roles.disabledForeground,
          ),
          overlayColor: overlay,
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? scheme.outlineVariant
                  : scheme.outline,
            );
          }),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: _buttonForeground(
            enabled: scheme.primary,
            disabled: roles.disabledForeground,
          ),
          overlayColor: overlay,
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return roles.disabledForeground;
            }
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.onSurfaceVariant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? roles.selectionContainer
                : Colors.transparent;
          }),
          overlayColor: overlay,
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: roles.selectionContainer,
        disabledColor: disabledSurface,
        deleteIconColor: scheme.onSurfaceVariant,
        checkmarkColor: roles.onSelectionContainer,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: roles.onSelectionContainer,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: componentShape,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledSurface;
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return roles.disabledForeground;
          }
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.onSurfaceVariant;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return roles.disabledForeground;
          }
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledSurface;
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStatePropertyAll(scheme.outlineVariant),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return roles.selectionContainer;
          }
          return scheme.surface;
        }),
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        dividerThickness: 1,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: roles.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: roles.scrim,
        elevation: 8,
        modalElevation: 8,
        shadowColor: roles.shadow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: roles.shadow,
        elevation: 6,
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(roles.shadow),
          elevation: const WidgetStatePropertyAll(6),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          border: fieldBorder,
          enabledBorder: fieldBorder,
          focusedBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: roles.focusRing, width: 1.5),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        disabledColor: roles.disabledForeground,
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(roles.shadow),
        overlayColor: overlay,
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant),
        ),
        shape: WidgetStatePropertyAll(componentShape),
        textStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        ),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        constraints: const BoxConstraints(minHeight: 48),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: roles.shadow,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        headerBackgroundColor: scheme.primary,
        headerForegroundColor: scheme.onPrimary,
        headerHeadlineStyle: textTheme.headlineSmall?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
        headerHelpStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
        ),
        weekdayStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        dayStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return roles.disabledForeground;
          }
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.onSurface;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent;
        }),
        dayOverlayColor: overlay,
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.primary;
        }),
        todayBorder: BorderSide(color: scheme.primary),
        yearStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return roles.disabledForeground;
          }
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.onSurface;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent;
        }),
        yearOverlayColor: overlay,
        rangePickerBackgroundColor: scheme.surfaceContainerLow,
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerShadowColor: roles.shadow,
        rangePickerHeaderBackgroundColor: scheme.surfaceContainerHigh,
        rangePickerHeaderForegroundColor: scheme.onSurface,
        rangeSelectionBackgroundColor: scheme.primary
            .withValues(alpha: brightness == Brightness.dark ? 0.28 : 0.16),
        rangeSelectionOverlayColor: overlay,
        dividerColor: scheme.outlineVariant,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainer,
          border: fieldBorder,
          enabledBorder: fieldBorder,
          focusedBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: roles.focusRing, width: 1.5),
          ),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        helpTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        hourMinuteColor: WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roles.selectionContainer
              : scheme.surfaceContainerHigh;
        }),
        hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roles.onSelectionContainer
              : scheme.onSurface;
        }),
        hourMinuteShape: componentShape,
        dayPeriodColor: WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roles.selectionContainer
              : scheme.surfaceContainerHigh;
        }),
        dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roles.onSelectionContainer
              : scheme.onSurfaceVariant;
        }),
        dayPeriodBorderSide: BorderSide(color: scheme.outlineVariant),
        dayPeriodShape: componentShape,
        dialBackgroundColor: scheme.surfaceContainerHigh,
        dialHandColor: scheme.primary,
        dialTextColor: WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurface;
        }),
        entryModeIconColor: scheme.onSurfaceVariant,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainer,
          border: fieldBorder,
          enabledBorder: fieldBorder,
          focusedBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: roles.focusRing, width: 1.5),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        margin: const EdgeInsets.all(8),
        verticalOffset: 12,
        preferBelow: false,
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: roles.shadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 420),
        showDuration: const Duration(seconds: 3),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return roles.disabledForeground;
            }
            return states.contains(WidgetState.selected)
                ? roles.onSelectionContainer
                : scheme.onSurfaceVariant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return disabledSurface;
            return states.contains(WidgetState.selected)
                ? roles.selectionContainer
                : scheme.surfaceContainerLow;
          }),
          overlayColor: overlay,
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.selected)
                  ? roles.info.border
                  : scheme.outlineVariant,
            );
          }),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(componentShape),
        ),
        selectedIcon: Icon(
          Icons.check,
          size: 18,
          color: roles.onSelectionContainer,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant,
        dividerHeight: 1,
        labelColor: scheme.primary,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelColor: scheme.onSurfaceVariant,
        unselectedLabelStyle: textTheme.labelLarge,
        overlayColor: overlay,
        splashBorderRadius: BorderRadius.circular(8),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        smallSize: 8,
        largeSize: 18,
        textStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onError,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      sliderTheme: baseTheme.sliderTheme.copyWith(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        secondaryActiveTrackColor: scheme.primary.withValues(alpha: 0.42),
        disabledActiveTrackColor: roles.disabledForeground,
        disabledInactiveTrackColor: disabledSurface,
        thumbColor: scheme.primary,
        disabledThumbColor: roles.disabledForeground,
        overlayColor: scheme.primary.withValues(alpha: 0.16),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        interactive: true,
        radius: const Radius.circular(999),
        thickness: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ? 10 : 6;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return scrollbarDraggedThumb;
          }
          if (states.contains(WidgetState.hovered)) {
            return scrollbarHoverThumb;
          }
          return scrollbarThumb;
        }),
        trackColor: WidgetStatePropertyAll(scrollbarTrack),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: roles.selectionContainer,
        indicatorShape: componentShape,
        overlayColor: overlay,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? roles.onSelectionContainer
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        tileHeight: 48,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: roles.selectionContainer,
        indicatorShape: componentShape,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.bodyMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? roles.onSelectionContainer
                : scheme.onSurface,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: roles.shadow,
        dividerColor: scheme.outlineVariant,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: _ResolvedContentPalette._contrastSafeForeground(
          scheme.inversePrimary,
          scheme.inverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: componentShape,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  static VinabikeThemeRoles rolesFor({
    required AppearancePreset preset,
    required Brightness brightness,
  }) {
    final palette = _ResolvedContentPalette.resolve(preset, brightness);
    return _rolesFor(
      preset: preset,
      brightness: brightness,
      palette: palette,
    );
  }

  static VinabikeThemeRoles _rolesFor({
    required AppearancePreset preset,
    required Brightness brightness,
    required _ResolvedContentPalette palette,
  }) {
    final shell = preset.shell;
    final isDark = brightness == Brightness.dark;
    final scheme = palette.colorScheme;

    return VinabikeThemeRoles(
      presetCode: preset.code,
      brightness: brightness,
      shell: VinabikeShellRoles(
        canvas: shell.canvas,
        raised: shell.raised,
        edge: shell.edge,
        foreground: shell.foreground,
        mutedForeground: shell.mutedForeground,
        accent: shell.accent,
        onAccent: shell.onAccent,
        dirty: shell.dirty,
        attention: shell.attention,
        onAttention: shell.onAttention,
      ),
      success: isDark
          ? const VinabikeSemanticTone(
              accent: Color(0xFF69D39C),
              onAccent: Color(0xFF082719),
              container: Color(0xFF173A2A),
              onContainer: Color(0xFFD7F7E5),
              border: Color(0xFF347757),
            )
          : const VinabikeSemanticTone(
              accent: Color(0xFF18764B),
              onAccent: Color(0xFFFFFFFF),
              container: Color(0xFFDFF4E9),
              onContainer: Color(0xFF14583A),
              border: Color(0xFF75BC97),
            ),
      warning: isDark
          ? const VinabikeSemanticTone(
              accent: Color(0xFFF5B545),
              onAccent: Color(0xFF2C1B00),
              container: Color(0xFF45320E),
              onContainer: Color(0xFFFFE7B5),
              border: Color(0xFF8D6B2D),
            )
          : const VinabikeSemanticTone(
              accent: Color(0xFF8A5700),
              onAccent: Color(0xFFFFFFFF),
              container: Color(0xFFFFEDD0),
              onContainer: Color(0xFF5C3A00),
              border: Color(0xFFD6A653),
            ),
      danger: isDark
          ? const VinabikeSemanticTone(
              accent: Color(0xFFF0897F),
              onAccent: Color(0xFF2E0F0C),
              container: Color(0xFF43211E),
              onContainer: Color(0xFFFFE0DA),
              border: Color(0xFF854540),
            )
          : const VinabikeSemanticTone(
              accent: Color(0xFFA8352E),
              onAccent: Color(0xFFFFFFFF),
              container: Color(0xFFFAE5E2),
              onContainer: Color(0xFF6E211C),
              border: Color(0xFFDCA69F),
            ),
      info: VinabikeSemanticTone(
        accent: scheme.primary,
        onAccent: scheme.onPrimary,
        container: scheme.primaryContainer,
        onContainer: scheme.onPrimaryContainer,
        border: Color.alphaBlend(
          scheme.primary.withValues(alpha: isDark ? 0.56 : 0.42),
          scheme.surface,
        ),
      ),
      neutral: isDark
          ? const VinabikeSemanticTone(
              accent: Color(0xFFB7C1CE),
              onAccent: Color(0xFF20262D),
              container: Color(0xFF2B333C),
              onContainer: Color(0xFFE3E8EE),
              border: Color(0xFF56616E),
            )
          : const VinabikeSemanticTone(
              accent: Color(0xFF596573),
              onAccent: Color(0xFFFFFFFF),
              container: Color(0xFFE9EDF2),
              onContainer: Color(0xFF37414C),
              border: Color(0xFFAAB3BE),
            ),
      selectionContainer: scheme.primaryContainer,
      onSelectionContainer: scheme.onPrimaryContainer,
      focusRing: scheme.primary,
      disabledForeground:
          scheme.onSurfaceVariant.withValues(alpha: isDark ? 0.5 : 0.56),
      scrim: scheme.scrim.withValues(alpha: isDark ? 0.68 : 0.46),
      shadow: scheme.shadow.withValues(alpha: isDark ? 0.48 : 0.2),
      avatarA: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF087DA5),
      avatarB: isDark ? const Color(0xFFF0ABFC) : const Color(0xFF7B3C8F),
      avatarC: isDark ? const Color(0xFF69D39C) : const Color(0xFF18764B),
      avatarD: isDark ? const Color(0xFFF5B545) : const Color(0xFF8A5700),
    );
  }

  static WidgetStateProperty<Color?> _buttonForeground({
    required Color enabled,
    required Color disabled,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.disabled) ? disabled : enabled;
    });
  }

  static WidgetStateProperty<Color?> _buttonBackground({
    required Color enabled,
    required Color disabled,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.disabled) ? disabled : enabled;
    });
  }

  static WidgetStateProperty<Color?> _interactiveOverlay(ColorScheme scheme) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return scheme.primary.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.focused)) {
        return scheme.primary.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return scheme.onSurface.withValues(alpha: 0.05);
      }
      return null;
    });
  }
}

@immutable
class _ResolvedContentPalette {
  const _ResolvedContentPalette(this.colorScheme);

  final ColorScheme colorScheme;

  factory _ResolvedContentPalette.resolve(
    AppearancePreset preset,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    final seed = preset.contentSeedFor(brightness);
    final shell = preset.shell;

    // Light-mode working surfaces preserve the exact cool neutral hierarchy
    // delivered by the canonical Claude Design Payroll handoff. Preset colour
    // belongs to actions, selection and semantic state; it must not tint the
    // shared canvas or replace this hierarchy with warm generic greys.
    //
    // Dark mode intentionally keeps a restrained shell-derived undertone so
    // the selected preset can produce the layered navy/aubergine/graphite
    // compositions expected from a modern dark theme.
    final surface = isDark
        ? _blend(shell.canvas, const Color(0xFF14181D), 0.2)
        : const Color(0xFFFFFFFF);
    final surfaceLowest = isDark
        ? _blend(shell.canvas, const Color(0xFF0E1216), 0.28)
        : const Color(0xFFFFFFFF);
    final surfaceLow = isDark
        ? _blend(shell.canvas, const Color(0xFF1A1F25), 0.2)
        : const Color(0xFFF7F8FA);
    final surfaceContainer = isDark
        ? _blend(shell.canvas, const Color(0xFF1F252C), 0.22)
        : const Color(0xFFEEF1F5);
    final surfaceHigh = isDark
        ? _blend(shell.raised, const Color(0xFF262D36), 0.2)
        : const Color(0xFFEEF1F4);
    final surfaceHighest = isDark
        ? _blend(shell.raised, const Color(0xFF2E3742), 0.24)
        : const Color(0xFFE2E7ED);
    final surfaceDim = isDark
        ? _blend(shell.canvas, const Color(0xFF0E1216), 0.36)
        : const Color(0xFFCDD5DE);
    final surfaceBright =
        isDark ? _blend(shell.raised, const Color(0xFF343C46), 0.24) : surface;
    final onSurface =
        isDark ? const Color(0xFFE4E8EE) : const Color(0xFF10243A);
    final onSurfaceVariant = isDark
        ? _blend(shell.mutedForeground, const Color(0xFFA6B0BE), 0.24)
        : const Color(0xFF4A5B6B);
    final outline = isDark
        ? _blend(shell.edge, const Color(0xFF6B7684), 0.38)
        : const Color(0xFFCDD5DE);
    final outlineVariant = isDark
        ? _blend(shell.edge, const Color(0xFF3D4753), 0.42)
        : const Color(0xFFE2E7ED);
    final primaryContainer = _blend(
      seed.primary,
      isDark ? surfaceHigh : surfaceLow,
      isDark ? 0.2 : 0.14,
    );
    final onPrimaryContainer =
        _contrastSafeForeground(seed.primary, primaryContainer);
    final secondary = _blend(
      seed.primary,
      isDark ? const Color(0xFF9AABBC) : const Color(0xFF40566B),
      isDark ? 0.34 : 0.3,
    );
    final onSecondary = _bestForegroundFor(secondary);
    final secondaryContainer = _blend(
      secondary,
      isDark ? surfaceHigh : surfaceLow,
      isDark ? 0.18 : 0.12,
    );
    final onSecondaryContainer =
        _contrastSafeForeground(secondary, secondaryContainer);
    final warning = isDark ? const Color(0xFFF5B545) : const Color(0xFF8A5700);
    final onWarning = _bestForegroundFor(warning);
    final warningContainer =
        isDark ? const Color(0xFF45320E) : const Color(0xFFFFEDD0);
    final onWarningContainer =
        isDark ? const Color(0xFFFFE7B5) : const Color(0xFF5C3A00);
    final error = isDark ? const Color(0xFFF2637A) : const Color(0xFFB3261E);
    final onError = _bestForegroundFor(error);
    final errorContainer =
        isDark ? const Color(0xFF521E28) : const Color(0xFFFBE3E3);
    final onErrorContainer =
        isDark ? const Color(0xFFFFD9DF) : const Color(0xFF6B1414);

    return _ResolvedContentPalette(
      ColorScheme(
        brightness: brightness,
        primary: seed.primary,
        onPrimary: seed.onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        primaryFixed: seed.primary,
        primaryFixedDim: _blend(
          seed.primary,
          isDark ? surface : const Color(0xFFFFFFFF),
          0.76,
        ),
        onPrimaryFixed: seed.onPrimary,
        onPrimaryFixedVariant: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        secondaryFixed: secondary,
        secondaryFixedDim: _blend(
          secondary,
          isDark ? surface : const Color(0xFFFFFFFF),
          0.76,
        ),
        onSecondaryFixed: onSecondary,
        onSecondaryFixedVariant: onSecondaryContainer,
        tertiary: warning,
        onTertiary: onWarning,
        tertiaryContainer: warningContainer,
        onTertiaryContainer: onWarningContainer,
        tertiaryFixed: warning,
        tertiaryFixedDim: _blend(
          warning,
          isDark ? surface : const Color(0xFFFFFFFF),
          0.76,
        ),
        onTertiaryFixed: onWarning,
        onTertiaryFixedVariant: onWarningContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
        surfaceContainerLowest: surfaceLowest,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: surfaceHighest,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        shadow: const Color(0xFF000000),
        scrim: const Color(0xFF000000),
        inverseSurface:
            isDark ? const Color(0xFFE4E8EE) : const Color(0xFF283039),
        onInverseSurface:
            isDark ? const Color(0xFF1A1F25) : const Color(0xFFF1F3F7),
        inversePrimary: isDark
            ? _blend(seed.primary, const Color(0xFF0E1216), 0.64)
            : _blend(seed.primary, const Color(0xFFFFFFFF), 0.68),
        surfaceTint: seed.surfaceTint,
      ),
    );
  }

  static Color _blend(Color foreground, Color background, double opacity) {
    return Color.alphaBlend(
      foreground.withValues(alpha: opacity),
      background,
    );
  }

  static Color _contrastSafeForeground(Color preferred, Color background) {
    return _contrastRatio(preferred, background) >= 4.5
        ? preferred
        : _bestForegroundFor(background);
  }

  static Color _minimumContrastBlend({
    required Color foreground,
    required Color background,
    required double minimumRatio,
  }) {
    final contrastForeground =
        _contrastRatio(foreground, background) >= minimumRatio
            ? foreground
            : _bestForegroundFor(background);
    var low = 0.0;
    var high = 1.0;

    for (var iteration = 0; iteration < 12; iteration++) {
      final alpha = (low + high) / 2;
      final candidate = Color.alphaBlend(
        contrastForeground.withValues(alpha: alpha),
        background,
      );
      if (_contrastRatio(candidate, background) >= minimumRatio) {
        high = alpha;
      } else {
        low = alpha;
      }
    }

    return Color.alphaBlend(
      contrastForeground.withValues(alpha: high),
      background,
    );
  }

  static Color _bestForegroundFor(Color background) {
    const dark = Color(0xFF07141D);
    const light = Color(0xFFF7FBFE);
    return _contrastRatio(dark, background) >= _contrastRatio(light, background)
        ? dark
        : light;
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
}
