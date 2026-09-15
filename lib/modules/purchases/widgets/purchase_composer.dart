/// El bloque de captura del Asistente de compras.
///
/// Es el control que el dueño puso lado a lado con el diseño el 2026-08-17: la
/// versión anterior dejaba título, subtítulo, campo y botones **sueltos sobre
/// el fondo**, con la tipografía a 15-16 px y el atajo pegado a los botones.
/// El diseño es un solo panel que contiene todo, con el campo adentro y la fila
/// de acciones cerrando el mismo borde.
///
/// Todos los valores vienen leídos de la página fuente del prototipo. El único
/// que el prototipo no declara es el color del texto de ayuda del campo —ahí usa
/// el gris por defecto del navegador—, y va marcado en su línea.
library;

import 'package:flutter/material.dart';

import 'purchase_visual_language.dart';

class PurchaseComposer extends StatelessWidget {
  const PurchaseComposer({
    super.key,
    required this.controller,
    required this.onAnalyze,
    required this.onToggleExamples,
    this.examplesOpen = false,
    this.busy = false,
  });

  final TextEditingController controller;

  /// `null` mientras no haya nada que analizar: el botón se apaga solo.
  final VoidCallback? onAnalyze;
  final VoidCallback onToggleExamples;
  final bool examplesOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return PurchasePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Caja dentro de caja: el campo lleva el borde fuerte y el panel el
          // suave. Esa diferencia es la que hace que el bloque se lea como un
          // objeto y no como un formulario apoyado en la página.
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: PurchaseMetrics.fieldMinHeight,
            ),
            child: TextField(
              key: const ValueKey('intelligent-purchasing-composer'),
              controller: controller,
              minLines: 2,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              style: PurchaseType.input.copyWith(color: tokens.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: tokens.surface,
                contentPadding: PurchaseMetrics.fieldPadding,
                hintText:
                    'Escríbelo como lo dirías en voz alta. Ej: necesito neumáticos '
                    '27,5 de ancho mayor a 2,0, económicos pero con buen margen.',
                hintStyle: PurchaseType.input.copyWith(
                  // Sin fuente en el prototipo: ahí el placeholder usa el gris
                  // por defecto del navegador. Se elige el tercer nivel de
                  // tinta, que es el rol de lo prescindible.
                  color: tokens.inkFaint,
                ),
                border: _fieldBorder(tokens.borderStrong),
                enabledBorder: _fieldBorder(tokens.borderStrong),
                focusedBorder: _fieldBorder(tokens.focusBorder),
              ),
            ),
          ),
          const SizedBox(height: PurchaseMetrics.actionsTopGap),
          _Actions(
            primary: PurchasePrimaryButton(
              key: const ValueKey('intelligent-purchasing-analyze'),
              label: busy ? 'Analizando' : 'Analizar',
              onPressed: busy ? null : onAnalyze,
            ),
            secondary: PurchaseInlineAction(
              key: const ValueKey('intelligent-purchasing-examples'),
              label: examplesOpen ? 'Ocultar ejemplos' : 'Ejemplos',
              onPressed: onToggleExamples,
            ),
            hint: Text(
              '⌘/Ctrl + Enter',
              style: PurchaseType.hint.copyWith(color: tokens.inkFaint),
            ),
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(PurchaseMetrics.fieldRadius),
        ),
        borderSide: BorderSide(color: color),
      );
}

/// La fila de acciones del prototipo declara `flex-wrap: wrap`.
///
/// En una columna ancha el espaciador manda el atajo al borde derecho; en una
/// angosta el atajo baja de línea. Implementarla como `Row` rígida desbordaba
/// 40 px a 390 px de ancho, que es exactamente lo que `flex-wrap` evita.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.primary,
    required this.secondary,
    required this.hint,
  });

  final Widget primary;
  final Widget secondary;
  final Widget hint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Umbral por contenido, no por breakpoint: es el ancho bajo el cual las
        // tres piezas dejan de caber en una línea.
        if (constraints.maxWidth < 430) {
          return Wrap(
            spacing: PurchaseMetrics.actionsGap,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [primary, secondary, hint],
          );
        }
        return Row(
          children: [
            primary,
            const SizedBox(width: PurchaseMetrics.actionsGap),
            secondary,
            const Spacer(),
            hint,
          ],
        );
      },
    );
  }
}
