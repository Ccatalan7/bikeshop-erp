import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

/// TOKENS EXACTOS del rediseño de Nóminas (frames 2a–2e y 3a–3c).
/// Todo valor visual de las superficies nuevas sale de acá. Ningún widget de
/// payroll declara Color(0x…), radios, tamaños ni sombras propios.
///
/// PROHIBIDO: reutilizar el aspecto de payroll_week_queue.dart,
/// payroll_week_worksheet.dart, payroll_payment_sheet.dart o la página actual.
/// Solo se reutilizan modelos, servicios y callbacks.
class PayrollTokens {
  const PayrollTokens._();

  // ── Shell / marco navy ────────────────────────────────────────────────────
  static const Color shell = Color(0xFF0C2537);
  static const Color shellDeep = Color(0xFF08202F);
  static const Color shellRaised = Color(0xFF12374E);
  static const Color shellEdge = Color(0xFF1B4869);
  static const Color tabHairline = Color(0xFF123951);
  static const Color onShell = Color(0xFFEDF6FC);
  static const Color onShellMuted = Color(0xFF8FA9BD);
  static const Color brand = Color(0xFF6FD1F6);
  static const Color onBrand = Color(0xFF08222F);

  // ── Workspace ─────────────────────────────────────────────────────────────
  static const Color canvas = Color(0xFFEEF1F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSunken = Color(0xFFF7F8FA);
  static const Color surfaceSelected = Color(0xFFF7FBFF);
  static const Color border = Color(0xFFE2E7ED);
  static const Color borderStrong = Color(0xFFCDD5DE);

  static const Color ink = Color(0xFF10243A);
  static const Color inkMuted = Color(0xFF4A5B6B);
  static const Color inkFaint = Color(0xFF8493A1);
  static const Color inkDisabled = Color(0xFFB3BCC4);

  static const Color accent = Color(0xFF1668BD);
  static const Color accentSoft = Color(0xFFE8F2FC);
  static const Color accentBorder = Color(0xFFB9D6F2);

  // ── Semánticos: fg / soft / border ────────────────────────────────────────
  static const Color successFg = Color(0xFF1F8A54);
  static const Color successSoft = Color(0xFFE6F4EC);
  static const Color successBorder = Color(0xFFB6DDC6);
  static const Color warningFg = Color(0xFF8A5A00);
  static const Color warningSoft = Color(0xFFFDF0DC);
  static const Color warningBorder = Color(0xFFF0CF95);
  static const Color dangerFg = Color(0xFFA8352E);
  static const Color dangerSoft = Color(0xFFFBE9E7);
  static const Color dangerBorder = Color(0xFFEDB9B2);
  static const Color neutralFg = Color(0xFF5D6B78);
  static const Color neutralSoft = Color(0xFFEEF1F4);
  static const Color neutralBorder = Color(0xFFD5DBE1);

  /// Fondo de avatar por persona (círculo, texto siempre `shell`).
  static const Color avatarCyan = Color(0xFF6FD1F6); // Lucas
  static const Color avatarSky = Color(0xFF9BE1FA); // Vicente
  static const Color avatarAmber = Color(0xFFF5D08A); // Guillermo
  static const Color groupLabor = Color(0xFF6B4FC2); // grupo "Servicios"

  // ── Chrome (spec.tokens) ──────────────────────────────────────────────────
  static const Color railAttentionDot = Color(0xFFF2637A);
  static const Color dirtyTabDot = Color(0xFFF5B545);
  static const Color tabCloseIcon = Color(0xFF5C7D95);
  static const Color sidebarLabel = Color(0xFFBCD3E2);
  static const Color sidebarSubdot = Color(0xFF42607A);
  static const Color avatarPlateBg = Color(0xFF123C56);

  // ── Tipografía ────────────────────────────────────────────────────────────
  //
  // Las tres familias del handoff se resuelven vía google_fonts (ya presente
  // en el proyecto): mismas familias, mismos números. `fontHeading/fontBody/
  // fontMono` quedan como los nombres registrados por google_fonts para que
  // los estilos puntuales de las superficies (iniciales de avatar, glifos)
  // usen la misma resolución.
  static final String fontHeading = GoogleFonts.poppins().fontFamily!;
  static final String fontBody = GoogleFonts.ibmPlexSans().fontFamily!;
  static final String fontMono = GoogleFonts.ibmPlexMono().fontFamily!;

  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle _heading({
    required double size,
    required FontWeight weight,
    required double height,
    Color color = ink,
  }) =>
      GoogleFonts.poppins(
          fontSize: size, fontWeight: weight, height: height, color: color);

  static TextStyle _body({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    Color color = ink,
  }) =>
      GoogleFonts.ibmPlexSans(
          fontSize: size, fontWeight: weight, height: height, color: color);

  static TextStyle _mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
    double? letterSpacing,
    Color color = inkFaint,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      ).copyWith(fontFeatures: tabular);

  static final TextStyle moduleTitle =
      _heading(size: 15, weight: FontWeight.w600, height: 1.2, color: onShell);
  static final TextStyle recordTitle =
      _heading(size: 21, weight: FontWeight.w600, height: 1.2, color: onShell);
  static final TextStyle sectionTitle =
      _body(size: 13.5, weight: FontWeight.w600, height: 1.3);
  static final TextStyle cardTitle =
      _body(size: 12.5, weight: FontWeight.w600, height: 1.3);
  static final TextStyle bodyM = _body(size: 12.5);
  static final TextStyle bodyS = _body(size: 11.5, color: inkMuted);
  static final TextStyle label =
      _body(size: 11, weight: FontWeight.w500, height: 1.3, color: inkMuted);
  static final TextStyle labelStrong =
      _body(size: 11.5, weight: FontWeight.w600, height: 1.3);

  /// Etiquetas de campo y headers de tabla: mono 9.5 / 600 / +0.8 / MAYÚSCULA.
  static final TextStyle overline = _mono(
      size: 9.5, weight: FontWeight.w600, letterSpacing: 0.8, height: 1.3);
  static final TextStyle monoS = _mono(size: 10);
  static final TextStyle monoM =
      _mono(size: 11.5, weight: FontWeight.w500, color: inkMuted);

  /// Cifra de decisión en fila (dinero nuevo).
  static final TextStyle numRow =
      _mono(size: 14, weight: FontWeight.w700, height: 1.2, color: ink);

  /// Cifra de tarjeta de semana seleccionada.
  static final TextStyle numCard =
      _mono(size: 19, weight: FontWeight.w700, height: 1.15, color: ink);

  /// Cifra de la barra monetaria.
  static final TextStyle numBar =
      _mono(size: 21, weight: FontWeight.w700, height: 1.15, color: ink);

  /// Iniciales sobre avatar circular (texto siempre `shell`).
  static TextStyle avatarInitials(double size) =>
      _body(size: size, weight: FontWeight.w600, height: 1, color: shell);

  /// Letra de logo/plate sobre el rail.
  static TextStyle railLogo(double size, {Color color = shell}) =>
      _heading(size: size, weight: FontWeight.w700, height: 1, color: color);

  /// Cifras diminutas de badge.
  static TextStyle badgeDigits(double size, {Color color = onBrand}) =>
      _mono(size: size, weight: FontWeight.w600, height: 1, color: color);

  // ── Geometría ─────────────────────────────────────────────────────────────
  static const double rTag = 4;
  static const double rControl = 6;
  static const double rField = 8;
  static const double rPanel = 10;
  static const double rSheet = 14;
  static const double rPill = 999;

  // La geometría del shell (sidebar, rail, workspace bar y toolbar derecha)
  // pertenece a WorkspaceShellScope/RightToolbar. Nóminas sólo define la fila
  // de comando que agrega dentro del canvas que el shell le entrega.
  static const double moduleCommandH = 44; // header de módulo
  static const double queueStripH = 76; // banda de cola de semanas
  static const double tableHeaderH = 44;
  static const double tableColsH = 30;
  static const double rowH = 48; // fila de decisión (3a) · 50 en 2a
  static const double moneyBarH = 56; // 60 en 2a a 1400
  static const double ctaH = 34;
  static const double ctaHDense = 28;
  static const double fieldH = 31;
  static const double touchMin = 44;
  static const double touchMobile = 48;

  static const EdgeInsets workspacePad = EdgeInsets.fromLTRB(18, 16, 18, 0);
  static const EdgeInsets cardPadH = EdgeInsets.symmetric(horizontal: 16);
  static const double gapBlocks = 12; // 14 a 1400
  static const double gapCards = 9; // 10 a 1400

  // ── Sombras ───────────────────────────────────────────────────────────────
  static const List<BoxShadow> raised = <BoxShadow>[
    BoxShadow(color: Color(0x0F0C2537), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> moneyBar = <BoxShadow>[
    BoxShadow(color: Color(0x0D0C2537), blurRadius: 8, offset: Offset(0, -2)),
  ];
  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(color: Color(0x380C2537), blurRadius: 40, offset: Offset(0, 12)),
  ];

  /// Anillo de selección: 3px del accent al 12%.
  static BoxDecoration selectedRing({Color color = accent}) => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(rPanel),
        border: Border.all(color: color),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 0,
              spreadRadius: 3),
        ],
      );

  // ── Motion ────────────────────────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration pane = Duration(milliseconds: 380);
  static const Curve curve = Cubic(0.22, 1, 0.36, 1);

  // ── Breakpoints (contrato del shell) ──────────────────────────────────────
  static const double bpDesktop = 900; // >=900 rail/tabs/toolbar; <900 drawer
  static const double bpTablet = 834;
}

/// Theme-aware visual vocabulary for Payroll surfaces.
///
/// Geometry, density and motion remain in [PayrollTokens]. Anything that must
/// react to the selected appearance preset or brightness comes from this
/// object instead. During the migration, legacy static colors/styles remain in
/// [PayrollTokens] only so each surface can move independently; new code must
/// use this owner.
@immutable
class PayrollVisualTokens {
  const PayrollVisualTokens._({
    required this.theme,
    required this.roles,
  });

  factory PayrollVisualTokens.of(BuildContext context) {
    final theme = Theme.of(context);
    return PayrollVisualTokens._(
      theme: theme,
      roles: theme.extension<VinabikeThemeRoles>(),
    );
  }

  final ThemeData theme;
  final VinabikeThemeRoles? roles;

  ColorScheme get scheme => theme.colorScheme;

  // ── Shell / marco ────────────────────────────────────────────────────────

  Color get shell => roles?.shell.canvas ?? scheme.inverseSurface;
  Color get shellDeep => Color.alphaBlend(
        scheme.shadow.withValues(alpha: 0.14),
        shell,
      );
  Color get shellRaised =>
      roles?.shell.raised ?? scheme.surfaceContainerHighest;
  Color get shellEdge => roles?.shell.edge ?? scheme.outline;
  Color get tabHairline => shellEdge.withValues(alpha: 0.72);
  Color get onShell => roles?.shell.foreground ?? scheme.onInverseSurface;
  Color get onShellMuted =>
      roles?.shell.mutedForeground ?? scheme.onSurfaceVariant;
  Color get brand => roles?.shell.accent ?? scheme.primary;
  Color get onBrand => roles?.shell.onAccent ?? scheme.onPrimary;

  // ── Workspace / content ─────────────────────────────────────────────────

  /// Content canvas below every Payroll surface. The resolver owns the
  /// per-brightness semantics through `ThemeData.scaffoldBackgroundColor`
  /// (cool `surfaceContainer` ladder in light, preset-tinted
  /// `surfaceContainerLowest` in dark); Payroll must not branch on
  /// brightness locally.
  Color get canvas => theme.scaffoldBackgroundColor;
  Color get surface => scheme.surface;
  Color get surfaceSunken => scheme.surfaceContainerLow;

  /// Selected-surface treatment owned by the canonical role set; no local
  /// alpha/brightness mixing (Codex review 2026-07-30).
  Color get surfaceSelected =>
      roles?.selectionContainer ?? scheme.primaryContainer;
  Color get onSurfaceSelected =>
      roles?.onSelectionContainer ?? scheme.onPrimaryContainer;

  /// Foreground for content painted directly on [accent] (CTAs, filled
  /// actions). Never a surface color: contrast is the role's contract.
  Color get onAccent => scheme.onPrimary;
  Color get border => scheme.outlineVariant;
  Color get borderStrong => scheme.outline;

  Color get ink => scheme.onSurface;
  Color get inkMuted => scheme.onSurfaceVariant;
  Color get inkFaint =>
      roles?.neutral.accent ?? scheme.onSurfaceVariant.withValues(alpha: 0.78);
  Color get inkDisabled =>
      roles?.disabledForeground ??
      scheme.onSurfaceVariant.withValues(alpha: 0.52);

  Color get accent => scheme.primary;
  Color get accentSoft => scheme.primaryContainer;
  Color get accentBorder => roles?.info.border ?? scheme.outline;

  // ── Semantic state families ─────────────────────────────────────────────

  Color get successFg =>
      roles?.success.onContainer ?? scheme.onSecondaryContainer;
  Color get successSoft =>
      roles?.success.container ?? scheme.secondaryContainer;
  Color get successBorder => roles?.success.border ?? scheme.outline;
  Color get warningFg =>
      roles?.warning.onContainer ?? scheme.onTertiaryContainer;
  Color get warningSoft => roles?.warning.container ?? scheme.tertiaryContainer;
  Color get warningBorder => roles?.warning.border ?? scheme.outline;
  Color get dangerFg => scheme.onErrorContainer;
  Color get dangerSoft => scheme.errorContainer;
  Color get dangerBorder => Color.alphaBlend(
        scheme.error.withValues(alpha: 0.56),
        scheme.surface,
      );
  Color get neutralFg => roles?.neutral.onContainer ?? scheme.onSurfaceVariant;
  Color get neutralSoft =>
      roles?.neutral.container ?? scheme.surfaceContainerHigh;
  Color get neutralBorder => roles?.neutral.border ?? scheme.outlineVariant;

  PayrollStateTone get success =>
      PayrollStateTone(successFg, successSoft, successBorder);
  PayrollStateTone get warning =>
      PayrollStateTone(warningFg, warningSoft, warningBorder);
  PayrollStateTone get danger =>
      PayrollStateTone(dangerFg, dangerSoft, dangerBorder);
  PayrollStateTone get info =>
      PayrollStateTone(accent, accentSoft, accentBorder);
  PayrollStateTone get neutral =>
      PayrollStateTone(neutralFg, neutralSoft, neutralBorder);

  // ── Avatars / chrome details ─────────────────────────────────────────────

  /// Los tres tonos de avatar.
  ///
  /// **En oscuro pierden su matiz a propósito** (turno 7 de Design). El avatar
  /// cyan y el acento de Pacific son casi el mismo color, así que una persona
  /// parecía un control: la identidad la tiene que llevar la inicial, no el
  /// círculo. En oscuro son tres pasos neutros del mismo tono del preset, con
  /// croma casi nulo; en claro se conservan los matices del turno 4.
  Color get avatarCyan =>
      _isDark ? _neutralAvatar(0.46) : (roles?.avatarA ?? scheme.primary);
  Color get avatarSky =>
      _isDark ? _neutralAvatar(0.40) : (roles?.avatarB ?? scheme.secondary);
  Color get avatarAmber =>
      _isDark ? _neutralAvatar(0.34) : (roles?.avatarD ?? scheme.tertiary);

  bool get _isDark => scheme.brightness == Brightness.dark;

  /// Un paso neutro derivado del tono del preset. `lightness` es el valor que
  /// Design especifica por paso (0.46 / 0.40 / 0.34); el croma se aplasta para
  /// que el círculo nunca compita con un control accionable.
  Color _neutralAvatar(double lightness) {
    final hsl = HSLColor.fromColor(brand);
    return hsl
        .withSaturation((hsl.saturation * 0.12).clamp(0.0, 0.12))
        .withLightness(lightness)
        .toColor();
  }

  Color get groupLabor => roles?.avatarC ?? scheme.secondary;
  Color get railAttentionDot => roles?.shell.attention ?? scheme.error;
  Color get dirtyTabDot => roles?.shell.dirty ?? scheme.tertiary;
  Color get tabCloseIcon => onShellMuted;
  Color get sidebarLabel => onShellMuted;
  Color get sidebarSubdot => shellEdge;
  Color get avatarPlateBg => shellRaised;

  // ── Typography ───────────────────────────────────────────────────────────

  TextStyle _heading({
    required double size,
    required FontWeight weight,
    required double height,
    Color? color,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? ink,
      );

  TextStyle _body({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    Color? color,
  }) =>
      GoogleFonts.ibmPlexSans(
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? ink,
      );

  TextStyle _mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color ?? inkFaint,
      ).copyWith(fontFeatures: PayrollTokens.tabular);

  TextStyle get moduleTitle =>
      _heading(size: 15, weight: FontWeight.w600, height: 1.2, color: onShell);
  TextStyle get recordTitle => _heading(
        size: 21,
        weight: FontWeight.w600,
        height: 1.2,
        color: onShell,
      );
  TextStyle get sectionTitle =>
      _body(size: 13.5, weight: FontWeight.w600, height: 1.3);
  TextStyle get cardTitle =>
      _body(size: 12.5, weight: FontWeight.w600, height: 1.3);
  TextStyle get bodyM => _body(size: 12.5);
  TextStyle get bodyS => _body(size: 11.5, color: inkMuted);
  TextStyle get label =>
      _body(size: 11, weight: FontWeight.w500, height: 1.3, color: inkMuted);
  TextStyle get labelStrong =>
      _body(size: 11.5, weight: FontWeight.w600, height: 1.3);
  TextStyle get overline => _mono(
        size: 9.5,
        weight: FontWeight.w600,
        letterSpacing: 0.8,
        height: 1.3,
      );
  TextStyle get monoS => _mono(size: 10);
  TextStyle get monoM =>
      _mono(size: 11.5, weight: FontWeight.w500, color: inkMuted);
  TextStyle get numRow =>
      _mono(size: 14, weight: FontWeight.w700, height: 1.2, color: ink);
  TextStyle get numCard =>
      _mono(size: 19, weight: FontWeight.w700, height: 1.15, color: ink);
  TextStyle get numBar =>
      _mono(size: 21, weight: FontWeight.w700, height: 1.15, color: ink);

  /// En oscuro la inicial ES la identidad —el círculo perdió su matiz— así que
  /// tiene que leerse. La tinta fija `shell` es navy casi negro: sobre un
  /// avatar neutro oscuro desaparecería. Se elige contra el fondo real.
  TextStyle avatarInitials(double size) => _body(
        size: size,
        weight: FontWeight.w600,
        height: 1,
        color: _isDark ? onShell : shell,
      );

  TextStyle railLogo(double size, {Color? color}) => _heading(
        size: size,
        weight: FontWeight.w700,
        height: 1,
        color: color ?? shell,
      );

  TextStyle badgeDigits(double size, {Color? color}) => _mono(
        size: size,
        weight: FontWeight.w600,
        height: 1,
        color: color ?? onBrand,
      );

  /// Modal barrier scrim owned by the resolver's role set.
  Color get scrim => roles?.scrim ?? scheme.scrim.withValues(alpha: 0.46);

  // ── Elevation / selection ────────────────────────────────────────────────

  Color get _shadow =>
      roles?.shadow ?? theme.shadowColor.withValues(alpha: 0.2);

  List<BoxShadow> get raised => <BoxShadow>[
        BoxShadow(
          color: _shadow.withValues(alpha: 0.3),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  List<BoxShadow> get moneyBar => <BoxShadow>[
        BoxShadow(
          color: _shadow.withValues(alpha: 0.24),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ];

  List<BoxShadow> get overlay => <BoxShadow>[
        BoxShadow(
          color: _shadow,
          blurRadius: 40,
          offset: const Offset(0, 12),
        ),
      ];

  BoxDecoration selectedRing({Color? color}) {
    final resolved = color ?? accent;
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
      border: Border.all(color: resolved),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: resolved.withValues(alpha: 0.12),
          blurRadius: 0,
          spreadRadius: 3,
        ),
      ],
    );
  }
}

/// Trío semántico reutilizable para píldoras de estado.
class PayrollStateTone {
  const PayrollStateTone(this.fg, this.soft, this.border);
  final Color fg;
  final Color soft;
  final Color border;

  static const PayrollStateTone success = PayrollStateTone(
      PayrollTokens.successFg,
      PayrollTokens.successSoft,
      PayrollTokens.successBorder);
  static const PayrollStateTone warning = PayrollStateTone(
      PayrollTokens.warningFg,
      PayrollTokens.warningSoft,
      PayrollTokens.warningBorder);
  static const PayrollStateTone danger = PayrollStateTone(
      PayrollTokens.dangerFg,
      PayrollTokens.dangerSoft,
      PayrollTokens.dangerBorder);
  static const PayrollStateTone info = PayrollStateTone(PayrollTokens.accent,
      PayrollTokens.accentSoft, PayrollTokens.accentBorder);
  static const PayrollStateTone neutral = PayrollStateTone(
      PayrollTokens.neutralFg,
      PayrollTokens.neutralSoft,
      PayrollTokens.neutralBorder);
}
