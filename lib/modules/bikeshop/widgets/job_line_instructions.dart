import 'package:flutter/material.dart';

/// La instrucción de una línea del trabajo: qué incluye el servicio (su
/// descripción del catálogo como está hoy, la misma que el cliente ve en la
/// tienda) y las indicaciones escritas para este trabajo. La línea no guarda
/// una copia fechada del catálogo (`mechanic_job_items.description` repite sus
/// notas), así que un servicio cuyo texto cambió muestra el de hoy.
///
/// Es texto para leer, no una lista de tareas: no tiene casillas ni avance.
/// Los renglones se muestran tal como están escritos (viñetas, `1)` y
/// advertencias incluidas), porque en el catálogo real una viñeta puede ser
/// una advertencia al cliente y un paso puede ir sin marca (2026-09-29). Una
/// tarea accionable la crea una persona aparte.
class JobLineInstructions extends StatefulWidget {
  const JobLineInstructions({
    super.key,
    this.catalogDescription,
    this.notes,
  });

  final String? catalogDescription;
  final String? notes;

  /// Renglones visibles antes de «Ver todo».
  static const int collapsedLines = 4;

  static List<String> linesOf(String? text) => [
        for (final line in (text ?? '').split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  bool get isEmpty =>
      linesOf(catalogDescription).isEmpty && (notes ?? '').trim().isEmpty;

  @override
  State<JobLineInstructions> createState() => _JobLineInstructionsState();
}

class _JobLineInstructionsState extends State<JobLineInstructions> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = JobLineInstructions.linesOf(widget.catalogDescription);
    final notes = (widget.notes ?? '').trim();
    final overflow = lines.length > JobLineInstructions.collapsedLines + 1;
    final shown = overflow && !_expanded
        ? lines.take(JobLineInstructions.collapsedLines).toList()
        : lines;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isNotEmpty) ...[
            const _Heading(
              icon: Icons.menu_book_outlined,
              title: 'Qué incluye',
              caption: 'Del catálogo, como está hoy · lo que ve el cliente',
            ),
            const SizedBox(height: 6),
            for (final line in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(line, style: theme.textTheme.bodyMedium),
              ),
            if (overflow)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    _expanded
                        ? 'Ver menos'
                        : 'Ver todo (${lines.length} renglones)',
                  ),
                ),
              ),
          ],
          if (lines.isNotEmpty && notes.isNotEmpty) const SizedBox(height: 10),
          if (notes.isNotEmpty) ...[
            const _Heading(
              icon: Icons.sticky_note_2_outlined,
              title: 'Indicaciones de este trabajo',
            ),
            const SizedBox(height: 6),
            Text(notes, style: theme.textTheme.bodyMedium),
          ],
          if (lines.isEmpty && notes.isEmpty)
            Text('Sin instrucciones', style: muted),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.title, this.caption});

  final IconData icon;
  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
