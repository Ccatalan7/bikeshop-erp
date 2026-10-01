import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/backup.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_notice.dart';

/// Restaurar un respaldo, antes de hacerlo: pregunta al servidor
/// (`restore_backup_preflight`) si se puede sin perder datos que el respaldo
/// no guarda y qué archivos ya no están. Sólo ofrece Restaurar cuando se puede;
/// si no, dice qué se perdería y ofrece descargarlo.
///
/// Devuelve `true` cuando el operador confirma.
class BackupRestoreConfirmDialog extends StatefulWidget {
  const BackupRestoreConfirmDialog({
    super.key,
    required this.backup,
    required this.loadPreflight,
    this.onDownload,
  });

  final DatabaseBackup backup;
  final Future<RestorePreflight> Function() loadPreflight;
  final VoidCallback? onDownload;

  @override
  State<BackupRestoreConfirmDialog> createState() =>
      _BackupRestoreConfirmDialogState();
}

class _BackupRestoreConfirmDialogState
    extends State<BackupRestoreConfirmDialog> {
  late Future<RestorePreflight> _preflight =
      Future<RestorePreflight>.sync(widget.loadPreflight);

  void _retry() {
    setState(() {
      _preflight = Future<RestorePreflight>.sync(widget.loadPreflight);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RestorePreflight>(
      future: _preflight,
      builder: (context, snapshot) {
        final preflight = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        // Sin nada que falte no hay qué recuperar: no se ofrece un botón que
        // no cambiaría nada.
        final canRestore = preflight?.canRestore == true &&
            !(preflight!.restoresMissingOnly && preflight.changedRecords == 0);

        final Widget body;
        if (loading) {
          body = const _Checking();
        } else if (snapshot.hasError || preflight == null) {
          body = VbNotice(
            title: 'No se pudo revisar el respaldo',
            body: snapshot.error is PostgrestException &&
                    (snapshot.error as PostgrestException).code == '57014'
                ? 'La revisión tardó demasiado. No se restauró ningún dato. '
                    'Vuelve a intentarlo.'
                : 'No llegó una respuesta completa del servidor. No se '
                    'restauró ningún dato. Revisa la conexión y vuelve a '
                    'intentarlo.',
            tone: VbNoticeTone.danger,
          );
        } else if (!preflight.canRestore) {
          body = _Blocked(preflight: preflight);
        } else if (preflight.restoresMissingOnly) {
          body = _MissingOnly(preflight: preflight);
        } else {
          body = _Ready(backup: widget.backup, preflight: preflight);
        }

        return AlertDialog(
          title: const Text('Restaurar respaldo'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BackupHeading(backup: widget.backup),
                  const SizedBox(height: 16),
                  body,
                ],
              ),
            ),
          ),
          actions: [
            VbButton(
              label: canRestore ? 'Cancelar' : 'Cerrar',
              variant: VbButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            if (!loading && snapshot.hasError)
              VbButton(
                label: 'Reintentar',
                icon: Icons.refresh,
                variant: VbButtonVariant.secondary,
                onPressed: _retry,
              ),
            if (!loading &&
                preflight?.canRestore != true &&
                widget.onDownload != null)
              VbButton(
                label: 'Descargar JSON',
                icon: Icons.download_outlined,
                variant: VbButtonVariant.secondary,
                onPressed: () {
                  Navigator.of(context).pop(false);
                  widget.onDownload!();
                },
              ),
            if (canRestore)
              VbButton(
                label: 'Restaurar',
                icon: Icons.restore,
                variant: VbButtonVariant.destructive,
                onPressed: () => Navigator.of(context).pop(true),
              ),
          ],
        );
      },
    );
  }
}

/// Después de restaurar: qué no volvió, qué volvió sin un vínculo y qué
/// registro volvió sin su archivo. Si todo volvió, basta el aviso corto de la
/// página.
class BackupRestoreResultDialog extends StatelessWidget {
  const BackupRestoreResultDialog({
    super.key,
    required this.omitted,
    this.restored = const [],
    this.heldBack = const [],
    this.droppedLinks = const [],
  });

  final List<OmittedAttachment> omitted;
  final List<RestoreCount> restored;
  final List<RestoreHeldBack> heldBack;
  final List<RestoreDroppedLink> droppedLinks;

  @override
  Widget build(BuildContext context) {
    final count = OmittedAttachment.distinctFiles(omitted);
    return AlertDialog(
      title: const Text('Respaldo restaurado'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (restored.isNotEmpty ||
                  heldBack.isNotEmpty ||
                  droppedLinks.isNotEmpty) ...[
                const Text('Volvió lo que faltaba. Lo que existía hoy quedó '
                    'como estaba.'),
                if (restored.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _CountList(title: 'Volvió', items: restored),
                ],
                if (droppedLinks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DroppedLinks(links: droppedLinks),
                ],
                if (heldBack.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _HeldBack(items: heldBack),
                ],
              ],
              if (omitted.isNotEmpty) ...[
                if (restored.isNotEmpty ||
                    heldBack.isNotEmpty ||
                    droppedLinks.isNotEmpty)
                  const SizedBox(height: 14),
                VbNotice(
                  title: count == 1
                      ? 'Volvió sin 1 archivo'
                      : 'Volvió sin $count archivos',
                  body: 'Todo lo demás del respaldo quedó restaurado. Cada '
                      'registro dice qué archivo no volvió y por qué; el '
                      'respaldo descargado los sigue nombrando.',
                  tone: VbNoticeTone.warning,
                ),
                const SizedBox(height: 12),
                OmittedAttachmentList(omitted: omitted),
              ],
            ],
          ),
        ),
      ),
      actions: [
        VbButton(
          label: 'Entendido',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Un registro por fila: «Trabajo RB-50 · adjunto», el archivo y por qué no
/// volvió.
class OmittedAttachmentList extends StatelessWidget {
  const OmittedAttachmentList({super.key, required this.omitted});

  final List<OmittedAttachment> omitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in omitted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    item.table == 'mechanic_jobs'
                        ? Icons.attach_file
                        : Icons.photo_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.recordLabel} · ${item.fieldLabel}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        item.fileName,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (item.reason.isNotEmpty)
                        Text(
                          item.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BackupHeading extends StatelessWidget {
  const _BackupHeading({required this.backup});

  final DatabaseBackup backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          backup.backupName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Guardado el ${DateFormat('dd/MM/yyyy HH:mm').format(backup.createdAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('Revisando qué guarda el respaldo…')),
        ],
      ),
    );
  }
}

/// No se puede restaurar: al respaldo le faltan tablas, se perderían datos
/// que no devuelve, o el motor lo negaría (proveedores o facturas de compra
/// distintos).
class _Blocked extends StatelessWidget {
  const _Blocked({required this.preflight});

  final RestorePreflight preflight;

  /// Cuántos tipos de datos se nombran; el resto se cuenta.
  static const int _shown = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Primero lo que tiene nombre del taller, en el orden del servidor (lo que
    // impide restaurar, lo que se borraría, lo que quedaría sin vínculo).
    final dependents = [
      ...preflight.uncoveredDependents.where((d) => d.label != d.table),
      ...preflight.uncoveredDependents.where((d) => d.label == d.table),
    ];
    final shown = dependents.take(_shown).toList();
    final rest = dependents.length - shown.length;
    final number = NumberFormat.decimalPattern('es_CL');

    final missing = preflight.missingTables;
    final String reason;
    if (missing.isNotEmpty) {
      reason = 'Es de una versión anterior y no guarda ${_list(missing)}: '
          'restaurarlo los borraría sin reponerlos.';
    } else if (dependents.isNotEmpty) {
      reason = 'El taller tiene datos que el respaldo no guarda y '
          'restaurarlo los perdería.';
    } else {
      reason = preflight.foundationBlocker ??
          preflight.message ??
          'La base no lo permite.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VbNotice(
          title: 'Este respaldo no se puede restaurar',
          body: reason.contains('No se tocó nada')
              ? reason
              : '$reason No se tocó nada.',
          tone: VbNoticeTone.danger,
        ),
        if (missing.isEmpty && shown.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Se perdería, entre otros:',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          for (final dependent in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dependent.label,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    number.format(dependent.rows),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                rest == 1
                    ? 'y 1 tipo de dato más'
                    : 'y $rest tipos de datos más',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
        Text(
          'Puedes descargarlo para consultar lo que guardaba.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// «mensajes, conversaciones y 5 más».
  static String _list(List<String> labels) {
    if (labels.length <= 3) return labels.join(', ');
    return '${labels.take(3).join(', ')} y ${labels.length - 3} más';
  }
}

/// Se puede restaurar: qué vuelve y qué archivos no.
class _Ready extends StatelessWidget {
  const _Ready({required this.backup, required this.preflight});

  final DatabaseBackup backup;
  final RestorePreflight preflight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final omitted = preflight.omittedAttachments;
    final counts = <String>[
      '${backup.getSummaryCount('products')} productos',
      '${backup.getSummaryCount('customers')} clientes',
      '${backup.getSummaryCount('mechanic_jobs')} trabajos',
      '${backup.getSummaryCount('bikes')} bicis',
      '${backup.getSummaryCount('sales_invoices')} facturas de venta',
      '${backup.getSummaryCount('purchase_invoices')} facturas de compra',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          preflight.preservesNewRecords
              ? 'Los registros del respaldo recuperan los valores guardados ese día. '
                  'Se conservan los registros nuevos y los campos que este respaldo no guardaba.'
              : 'Lo que guarda el respaldo vuelve a como estaba ese día. Lo que se '
                  'registró después en esos datos se pierde.',
          style: theme.textTheme.bodyMedium,
        ),
        if (preflight.preservesNewRecords &&
            preflight.changedRecords != null) ...[
          const SizedBox(height: 8),
          Text(
            preflight.changedRecords == 0
                ? 'No hay cambios que recuperar.'
                : '${preflight.changedRecords} registros por recuperar.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 10),
        Text(
          counts.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (omitted.isNotEmpty) ...[
          const SizedBox(height: 16),
          VbNotice(
            title: OmittedAttachment.distinctFiles(omitted) == 1
                ? 'Volverá sin 1 archivo'
                : 'Volverá sin ${OmittedAttachment.distinctFiles(omitted)} '
                    'archivos',
            body: 'El registro vuelve; sólo ese archivo no, porque ya no '
                'está o es de otro registro.',
            tone: VbNoticeTone.warning,
          ),
          const SizedBox(height: 8),
          OmittedAttachmentList(omitted: omitted),
        ],
      ],
    );
  }
}

String _capitalized(String label) =>
    label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);

/// «Vuelve lo que falta; lo que existe hoy manda» (20260930172000): qué
/// vuelve, qué vuelve sin un vínculo, qué no vuelve y por qué, y qué se
/// conserva sin tocar.
class _MissingOnly extends StatelessWidget {
  const _MissingOnly({required this.preflight});

  final RestorePreflight preflight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern('es_CL');
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final omitted = preflight.omittedAttachments;
    final missingPreserved = [
      for (final item in preflight.preserved)
        if ((item.missingRows ?? 0) > 0) item,
    ];
    final nothingMissing = preflight.changedRecords == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vuelve lo que falta del taller. Lo que existe hoy se conserva como '
          'está.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        if (nothingMissing)
          const VbNotice(
            title: 'No falta nada',
            body: 'Todo lo que guarda este respaldo existe hoy. No hay nada '
                'que recuperar.',
            tone: VbNoticeTone.success,
          )
        else
          _CountList(
            title: 'Vuelve',
            items: preflight.restored,
          ),
        if (preflight.droppedLinks.isNotEmpty) ...[
          const SizedBox(height: 14),
          _DroppedLinks(links: preflight.droppedLinks),
        ],
        if (preflight.heldBack.isNotEmpty) ...[
          const SizedBox(height: 14),
          _HeldBack(items: preflight.heldBack),
        ],
        if (omitted.isNotEmpty) ...[
          const SizedBox(height: 14),
          VbNotice(
            title: OmittedAttachment.distinctFiles(omitted) == 1
                ? 'Volverá sin 1 archivo'
                : 'Volverá sin ${OmittedAttachment.distinctFiles(omitted)} '
                    'archivos',
            body: 'El registro vuelve; sólo ese archivo no, porque ya no '
                'está o es de otro registro.',
            tone: VbNoticeTone.warning,
          ),
          const SizedBox(height: 8),
          OmittedAttachmentList(omitted: omitted),
        ],
        const SizedBox(height: 14),
        if (preflight.existingRecords > 0)
          Text(
            '${number.format(preflight.existingRecords)} registros del '
            'respaldo existen hoy y quedan como están.',
            style: muted,
          ),
        const SizedBox(height: 4),
        Text(
          missingPreserved.isEmpty
              ? 'Ventas, compras, contabilidad, inventario, mensajes, '
                  'productos y ajustes no se tocan: un respaldo no los repone.'
              : 'Ventas, compras, contabilidad, inventario, mensajes, '
                  'productos y ajustes no se tocan: un respaldo no los repone. '
                  'Del respaldo ya no están '
                  '${missingPreserved.map((p) => '${number.format(p.missingRows)} ${p.label}').join(', ')}.',
          style: muted,
        ),
      ],
    );
  }
}

/// «Vuelve»: una fila por tipo de registro, con sus ejemplos y cuántos.
class _CountList extends StatelessWidget {
  const _CountList({required this.title, required this.items});

  final String title;
  final List<RestoreCount> items;

  /// Cuántos tipos se nombran; el resto se cuenta.
  static const int _shown = 8;

  /// Lo que el taller reconoce primero: el trabajo, la bici, la tarea y el
  /// cliente; después, en el orden de la base, lo que vuelve con ellos.
  static const List<String> _rootsFirst = [
    'mechanic_jobs',
    'bikes',
    'smart_tasks',
    'customers',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern('es_CL');
    final ordered = [
      for (final table in _rootsFirst) ...items.where((i) => i.table == table),
      ...items.where((i) => !_rootsFirst.contains(i.table)),
    ];
    final shown = ordered.take(_shown).toList();
    final rest = ordered.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final item in shown)
          _CountRow(
            label: _capitalized(item.label),
            detail: item.examples.isEmpty ? null : item.examples.join(' · '),
            rows: number.format(item.rows),
          ),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              rest == 1
                  ? 'y 1 tipo de registro más'
                  : 'y $rest tipos de '
                      'registro más',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// «No vuelve»: cuántos y por qué, con ejemplos.
class _HeldBack extends StatelessWidget {
  const _HeldBack({required this.items});

  final List<RestoreHeldBack> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern('es_CL');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('No vuelve', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final item in items)
          _CountRow(
            label: _capitalized(item.label),
            // «Parche — su trabajo existe hoy…»: el nombre primero, para que
            // no se lea como una palabra suelta al final de la razón.
            detail: item.examples.isEmpty
                ? item.explanation
                : '${item.examples.join(' · ')} — '
                    '${item.explanation.substring(0, 1).toLowerCase()}'
                    '${item.explanation.substring(1)}',
            rows: number.format(item.rows),
          ),
      ],
    );
  }
}

/// Registros que vuelven sin un vínculo: aquello a lo que apuntaban ya no
/// existe, o es un acceso al portal, que nunca se repone.
class _DroppedLinks extends StatelessWidget {
  const _DroppedLinks({required this.links});

  final List<RestoreDroppedLink> links;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat.decimalPattern('es_CL');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VbNotice(
          title: 'Algunos vuelven sin un vínculo',
          body: 'Aquello a lo que apuntaban ya no existe; un acceso al '
              'portal nunca se repone.',
          tone: VbNoticeTone.warning,
        ),
        const SizedBox(height: 6),
        for (final link in links)
          _CountRow(
            label: '${_capitalized(link.label)} sin ${link.parentLabel}',
            rows: number.format(link.rows),
          ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.rows, this.detail});

  final String label;
  final String rows;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (detail != null && detail!.isNotEmpty)
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            rows,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
