import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// **E-04 · `VbNotice`** — banner / notice del kit compartido
/// (`GUÍA GENERAL Viñabike · Componentes`, proyecto `ERP Bikeshop UI Mockups`).
///
/// Es el dueño canónico del aviso en línea. `universal-ui-component-system.md`
/// lista «inline and persistent notices» entre las piezas P0 y nombra
/// explícitamente los *«many local chips, notices, dialogs»* como el problema a
/// cerrar: antes de este archivo había tres avisos distintos —uno en
/// `public_store`, uno en `mail`, uno en `website`— y Nóminas estaba por
/// escribir el cuarto dentro de su diálogo de confirmación.
///
/// **Geometría leída del archivo de Design, no estimada:** contenedor
/// `radius 8`, `padding 12/13`, `gap 12`; insignia del glifo `radius 7` sobre
/// `surface` con el borde del tono; título `600 12`, cuerpo `400 11.5/1.5`.
///
/// **El color no se escribe acá.** Los tres pares que la guía dibuja
/// (`#E8F2FC/#B9D6F2` informativo, `#E6F4EC/#B6DDC6` de éxito,
/// `#FDF0DC/#F0CF95` de atención) son los roles `info`, `success` y `warning`
/// de [VinabikeThemeRoles]; pegarlos literales congelaría el modo claro dentro
/// del widget, que es exactamente lo que la primera regla de la guía prohíbe.
enum VbNoticeTone { info, success, warning, danger, neutral }

class VbNotice extends StatelessWidget {
  const VbNotice({
    super.key,
    required this.title,
    this.body,
    this.tone = VbNoticeTone.info,
    this.glyph,
    this.action,
  });

  /// Primera línea: qué pasa. Una frase, sin punto final.
  final String title;

  /// Segunda línea, opcional: por qué, o qué hacer al respecto.
  final String? body;

  final VbNoticeTone tone;

  /// Sobrescribe el glifo del tono. La guía dibuja `i`, `✓` y `!`.
  final String? glyph;

  /// Acción opcional al final — «Abrir Asistencias ↗» en el ejemplo de la guía.
  final Widget? action;

  VinabikeSemanticTone _tone(VinabikeThemeRoles roles) {
    switch (tone) {
      case VbNoticeTone.info:
        return roles.info;
      case VbNoticeTone.success:
        return roles.success;
      case VbNoticeTone.warning:
        return roles.warning;
      case VbNoticeTone.danger:
        return roles.danger;
      case VbNoticeTone.neutral:
        return roles.neutral;
    }
  }

  String get _glyph {
    if (glyph != null) return glyph!;
    switch (tone) {
      case VbNoticeTone.success:
        return '✓';
      case VbNoticeTone.warning:
      case VbNoticeTone.danger:
        return '!';
      case VbNoticeTone.info:
      case VbNoticeTone.neutral:
        return 'i';
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final semantic = _tone(roles);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: semantic.container,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: semantic.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El glifo es DECORATIVO: repite en un carácter lo que el tono ya
          // dice. Sin excluirlo, un lector de pantalla anuncia «i» o «!» suelto
          // antes del aviso, que no significa nada dicho en voz alta.
          ExcludeSemantics(
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: semantic.border),
              ),
              child: Text(
                _glyph,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: semantic.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            // Un aviso se anuncia ENTERO: leer el título sin su cuerpo deja
            // al lector de pantalla con la alarma y sin la salida. Se excluye
            // la semántica de los hijos para que el nodo diga una sola cosa;
            // la acción queda fuera de este bloque y conserva la suya.
            child: Semantics(
              container: true,
              excludeSemantics: true,
              label: body == null ? title : '$title. $body',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: semantic.onContainer,
                    ),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      body!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: semantic.onContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
