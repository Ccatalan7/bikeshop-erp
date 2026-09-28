import 'package:flutter/material.dart';

/// Avisa que la ficha de la bici no tomó lo que el trabajo instaló (revisión
/// de Codex del paso C–F, 2026-09-27).
///
/// Queda a la vista hasta que se cierra: la ficha se reintenta sola al guardar
/// el trabajo o volver a cambiar su estado, pero el taller tiene que saber que
/// hoy no está al día. Antes el fallo sólo se imprimía en debug.
void showBikeFactProblems(BuildContext context, List<String> problems) {
  if (problems.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(problems.join(' ')),
      action: SnackBarAction(label: 'Entendido', onPressed: () {}),
    ),
  );
}
