import 'package:flutter/material.dart';

import '../../../shared/widgets/vb_notice.dart';
import '../models/bikeshop_models.dart';

/// La decisión de garantía que sigue en la bandeja de este equipo, igual en
/// el Estado de la tabla y en el panel de garantía del formulario.
///
/// Nunca se muestra como aplicada: la cobertura a la vista es la del
/// servidor, y ésta sólo dice lo que falta enviar (punto 2 del cierre,
/// 2026-09-29).
class WarrantyDecisionPendingNotice extends StatelessWidget {
  const WarrantyDecisionPendingNotice({super.key, required this.outcome});

  final WarrantyOutcome outcome;

  static String titleFor(WarrantyOutcome outcome) => switch (outcome) {
        WarrantyOutcome.pending =>
          'Devolver la garantía a evaluación todavía no se aplica',
        _ => 'La decisión «${outcome.displayName}» todavía no se aplica',
      };

  static const body = 'Quedó en este equipo y se envía sola, antes de '
      'cualquier cambio de estado del trabajo. Mientras tanto, la cobertura '
      'y el documento siguen como están.';

  @override
  Widget build(BuildContext context) {
    return VbNotice(
      key: const ValueKey('warranty-decision-pending'),
      title: titleFor(outcome),
      body: body,
    );
  }
}
