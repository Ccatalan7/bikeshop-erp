import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Semantic state colors resolved for one preset and brightness.
///
/// Components consume the meaning of the tone instead of choosing shades.
@immutable
class VinabikeSemanticTone {
  const VinabikeSemanticTone({
    required this.accent,
    required this.onAccent,
    required this.container,
    required this.onContainer,
    required this.border,
  });

  final Color accent;
  final Color onAccent;
  final Color container;
  final Color onContainer;
  final Color border;

  VinabikeSemanticTone lerp(VinabikeSemanticTone other, double t) {
    return VinabikeSemanticTone(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      container: Color.lerp(container, other.container, t)!,
      onContainer: Color.lerp(onContainer, other.onContainer, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

/// Semantic roles painted directly on authenticated workspace chrome.
@immutable
class VinabikeShellRoles {
  const VinabikeShellRoles({
    required this.canvas,
    required this.raised,
    required this.edge,
    required this.foreground,
    required this.mutedForeground,
    required this.accent,
    required this.onAccent,
    required this.dirty,
    required this.attention,
    required this.onAttention,
  });

  final Color canvas;
  final Color raised;
  final Color edge;
  final Color foreground;
  final Color mutedForeground;
  final Color accent;
  final Color onAccent;
  final Color dirty;
  final Color attention;
  final Color onAttention;

  VinabikeShellRoles lerp(VinabikeShellRoles other, double t) {
    return VinabikeShellRoles(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      dirty: Color.lerp(dirty, other.dirty, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      onAttention: Color.lerp(onAttention, other.onAttention, t)!,
    );
  }
}

/// Product-wide roles that do not fit directly into Material [ColorScheme].
///
/// This extension is the shared boundary for shell, semantic states and
/// interaction feedback. It contains resolved values only; presets and feature
/// widgets remain on opposite sides of this boundary.
@immutable
class VinabikeThemeRoles extends ThemeExtension<VinabikeThemeRoles> {
  const VinabikeThemeRoles({
    required this.presetCode,
    required this.brightness,
    required this.shell,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.selectionContainer,
    required this.onSelectionContainer,
    required this.hairline,
    required this.accentBorder,
    required this.faintForeground,
    required this.focusRing,
    required this.disabledForeground,
    required this.scrim,
    required this.shadow,
    required this.avatarA,
    required this.onAvatarA,
    required this.avatarB,
    required this.onAvatarB,
    required this.avatarC,
    required this.onAvatarC,
    required this.avatarD,
    required this.onAvatarD,
  });

  final String presetCode;
  final Brightness brightness;
  final VinabikeShellRoles shell;
  final VinabikeSemanticTone success;
  final VinabikeSemanticTone warning;

  /// Irreversible or failed outcomes: cancelled, overdue, returned unserviced.
  ///
  /// Distinct from [warning], which asks for attention on something still
  /// recoverable. A surface that means "this went wrong" must not borrow the
  /// warning tone: the two have to stay tellable apart at a glance.
  final VinabikeSemanticTone danger;
  final VinabikeSemanticTone info;
  final VinabikeSemanticTone neutral;
  final Color selectionContainer;
  final Color onSelectionContainer;

  /// Separador interno más tenue que `outlineVariant`: divide filas **dentro**
  /// de una superficie sin dibujar el contorno de otra caja.
  ///
  /// `outlineVariant` delimita un objeto; una lista de filas dentro de ese
  /// objeto necesita una línea que se lea como pausa, no como borde. Sin este
  /// rol la única salida era bajarle la opacidad a un borde, que el contrato de
  /// paletas prohíbe.
  final Color hairline;

  /// Borde del acento para un contenedor ya teñido con `selectionContainer`.
  ///
  /// El relleno solo no basta cuando el bloque tiene que leerse como elegido o
  /// como propio del operador: necesita cerrar con un borde de la misma familia,
  /// más presente que el relleno y más suave que el acento pleno.
  final Color accentBorder;

  /// Tercer nivel de tinta: lo prescindible —etiquetas de columna, unidades,
  /// atajos de teclado—, por debajo de `mutedForeground` y por encima de
  /// `disabledForeground`.
  ///
  /// No es lo mismo que deshabilitado: esto se lee, sólo que último. La
  /// distinción importa porque `mutedForeground` carga los caveats que cambian
  /// una decisión; si lo prescindible usa ese mismo tono, el caveat deja de
  /// destacar y la jerarquía se aplana.
  final Color faintForeground;
  final Color focusRing;
  final Color disabledForeground;
  final Color scrim;
  final Color shadow;
  final Color avatarA;
  final Color onAvatarA;
  final Color avatarB;
  final Color onAvatarB;
  final Color avatarC;
  final Color onAvatarC;
  final Color avatarD;
  final Color onAvatarD;

  static VinabikeThemeRoles of(BuildContext context) {
    final roles = maybeOf(context);
    assert(
      roles != null,
      'VinabikeThemeRoles is missing. Build the app theme through AppTheme.',
    );
    return roles!;
  }

  static VinabikeThemeRoles? maybeOf(BuildContext context) {
    return Theme.of(context).extension<VinabikeThemeRoles>();
  }

  @override
  VinabikeThemeRoles copyWith({
    String? presetCode,
    Brightness? brightness,
    VinabikeShellRoles? shell,
    VinabikeSemanticTone? success,
    VinabikeSemanticTone? warning,
    VinabikeSemanticTone? danger,
    VinabikeSemanticTone? info,
    VinabikeSemanticTone? neutral,
    Color? selectionContainer,
    Color? onSelectionContainer,
    Color? hairline,
    Color? accentBorder,
    Color? faintForeground,
    Color? focusRing,
    Color? disabledForeground,
    Color? scrim,
    Color? shadow,
    Color? avatarA,
    Color? onAvatarA,
    Color? avatarB,
    Color? onAvatarB,
    Color? avatarC,
    Color? onAvatarC,
    Color? avatarD,
    Color? onAvatarD,
  }) {
    return VinabikeThemeRoles(
      presetCode: presetCode ?? this.presetCode,
      brightness: brightness ?? this.brightness,
      shell: shell ?? this.shell,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      selectionContainer: selectionContainer ?? this.selectionContainer,
      onSelectionContainer: onSelectionContainer ?? this.onSelectionContainer,
      hairline: hairline ?? this.hairline,
      accentBorder: accentBorder ?? this.accentBorder,
      faintForeground: faintForeground ?? this.faintForeground,
      focusRing: focusRing ?? this.focusRing,
      disabledForeground: disabledForeground ?? this.disabledForeground,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      avatarA: avatarA ?? this.avatarA,
      onAvatarA: onAvatarA ?? this.onAvatarA,
      avatarB: avatarB ?? this.avatarB,
      onAvatarB: onAvatarB ?? this.onAvatarB,
      avatarC: avatarC ?? this.avatarC,
      onAvatarC: onAvatarC ?? this.onAvatarC,
      avatarD: avatarD ?? this.avatarD,
      onAvatarD: onAvatarD ?? this.onAvatarD,
    );
  }

  @override
  VinabikeThemeRoles lerp(
    covariant VinabikeThemeRoles other,
    double t,
  ) {
    return VinabikeThemeRoles(
      presetCode: t < 0.5 ? presetCode : other.presetCode,
      brightness: t < 0.5 ? brightness : other.brightness,
      shell: shell.lerp(other.shell, t),
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      info: info.lerp(other.info, t),
      neutral: neutral.lerp(other.neutral, t),
      selectionContainer:
          Color.lerp(selectionContainer, other.selectionContainer, t)!,
      onSelectionContainer:
          Color.lerp(onSelectionContainer, other.onSelectionContainer, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      faintForeground: Color.lerp(faintForeground, other.faintForeground, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      disabledForeground:
          Color.lerp(disabledForeground, other.disabledForeground, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      avatarA: Color.lerp(avatarA, other.avatarA, t)!,
      onAvatarA: Color.lerp(onAvatarA, other.onAvatarA, t)!,
      avatarB: Color.lerp(avatarB, other.avatarB, t)!,
      onAvatarB: Color.lerp(onAvatarB, other.onAvatarB, t)!,
      avatarC: Color.lerp(avatarC, other.avatarC, t)!,
      onAvatarC: Color.lerp(onAvatarC, other.onAvatarC, t)!,
      avatarD: Color.lerp(avatarD, other.avatarD, t)!,
      onAvatarD: Color.lerp(onAvatarD, other.onAvatarD, t)!,
    );
  }
}

/// La barra de estado del sistema, teñida con el color que hay justo debajo.
///
/// **Por qué existe.** En el teléfono la barra del sistema —reloj, wifi,
/// batería— quedaba blanca pegada encima de un header navy: una franja que no
/// pertenecía a la app. En Android 15+ la barra es transparente y la app pinta
/// detrás de ella; este estilo mantiene la compatibilidad anterior y decide el
/// brillo de iconos contra el canvas real. El host debe conservar el inset
/// superior hasta el AppBar en vez de consumirlo con un SafeArea exterior.
///
/// El brillo de los iconos **se calcula contra el fondo real** en vez de fijarse
/// en claro: un preset puede traer un chrome claro, y ahí unos iconos blancos
/// serían invisibles. El umbral es el mismo que usa el chrome para decidir su
/// propio brillo, así que las dos decisiones no pueden separarse.
///
/// Se le pasa el color que la pantalla pinta arriba —no «el navy»—, porque una
/// barra navy encima de un AppBar blanco es el mismo defecto al revés.
SystemUiOverlayStyle vinabikeSystemOverlayStyleFor(Color background) {
  final isDark = background.computeLuminance() < 0.35;
  return SystemUiOverlayStyle(
    statusBarColor: background,
    // Android nombra el brillo del ICONO; iOS nombra el del FONDO. Son
    // opuestos, y confundirlos deja una de las dos plataformas ilegible.
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: background,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
}
