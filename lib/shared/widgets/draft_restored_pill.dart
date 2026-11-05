import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';
import 'vb_status_pill.dart';

/// El aviso de que se recuperó algo que se estaba escribiendo, igual en todo
/// el ERP: «Recuperamos lo que escribiste · hace 2 min · Deshacer · ×».
///
/// Lo usan el borrador por campos de un formulario (`FormDraftScope`) y el
/// borrador de un documento con líneas (la venta manual). Un solo dueño, para
/// que los dos se lean igual.
class DraftRestoredPill extends StatelessWidget {
  const DraftRestoredPill({
    super.key,
    required this.title,
    required this.savedAt,
    required this.onClose,
    this.onUndo,
    this.note,
  });

  final String title;
  final DateTime savedAt;

  /// `null` cuando no hay nada que deshacer.
  final VoidCallback? onUndo;
  final VoidCallback onClose;

  /// Lo que la persona debe saber además de cuándo se guardó.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tone = VinabikeThemeRoles.of(context).info;
    final detail = [
      describeDraftAge(savedAt),
      if (note != null && note!.trim().isNotEmpty) note!.trim(),
    ].join(' · ');
    final undo = onUndo;
    return VbStatusPill(
      tone: tone,
      icon: Icons.history_rounded,
      title: title,
      detail: detail,
      maxLines: 2,
      trailing: [
        if (undo != null)
          VbStatusPillButton(tone: tone, label: 'Deshacer', onPressed: undo),
        VbStatusPillClose(tone: tone, onPressed: onClose),
      ],
    );
  }
}

/// «hace un momento», «hace 5 min», «hace 2 horas», «ayer», «hace 3 días».
///
/// Con espacios que no cortan: el aviso es angosto y, si la frase no cabe al
/// lado del título, baja entera a la línea siguiente en vez de dejar «min»
/// solo abajo.
String describeDraftAge(DateTime at, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(at);
  final String phrase;
  if (age.inMinutes < 1) {
    phrase = 'hace un momento';
  } else if (age.inMinutes < 60) {
    phrase = 'hace ${age.inMinutes} min';
  } else if (age.inHours < 24) {
    phrase = age.inHours == 1 ? 'hace 1 hora' : 'hace ${age.inHours} horas';
  } else if (age.inDays == 1) {
    phrase = 'ayer';
  } else {
    phrase = 'hace ${age.inDays} días';
  }
  return phrase.replaceAll(' ', ' ');
}
