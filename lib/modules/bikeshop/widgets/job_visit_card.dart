import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/bikeshop_models.dart';
import '../services/bike_directory_entries.dart';
import '../services/bike_visit_history.dart';
import '../services/job_line_systems.dart';
import 'bike_module_style.dart';

final NumberFormat _money =
    NumberFormat.currency(symbol: r'$', decimalDigits: 0);

bool isCancelledJob(MechanicJob job) =>
    job.status == JobStatus.cancelado ||
    job.customStatus?.code.trim().toUpperCase() == 'CANCELADO';

/// Lo que entró al taller en una visita: una bici (con su página), un
/// componente o nada (una cotización).
@immutable
class JobVisitSubject {
  const JobVisitSubject({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// El estado de un trabajo como se lee en su visita. Una cotización sin
/// objeto no tiene estado de taller: su estado es el de la propuesta.
String jobVisitStatusLabel(MechanicJob job) =>
    job.isStandaloneQuotation ? job.statusDisplayName : jobStatusLabel(job);

Color jobVisitStatusColor(MechanicJob job) {
  if (!job.isStandaloneQuotation) return jobStatusColor(job);
  return switch (job.effectiveQuotationStatus) {
    QuotationStatus.pending => const Color(0xFFF59E0B),
    QuotationStatus.approved => const Color(0xFF84CC16),
    QuotationStatus.rejected => const Color(0xFFEF4444),
    QuotationStatus.expired => const Color(0xFF6B7280),
  };
}

/// Una visita al taller como tarjeta: la fecha en una franja dentro de la
/// tarjeta, el trabajo con su estado, lo que pidió, las líneas por sistema y
/// el monto.
///
/// La usan la página de la bici (lo que se le hizo a esa bici) y la del
/// cliente (el trabajo entero, con sus bicis y su factura al pie). La fecha
/// va dentro de la tarjeta y no suelta al lado: todos los bloques del
/// historial empiezan en el mismo borde (dueño, 2026-10-02: la fecha suelta
/// dejaba «en el aire» a la tarjeta de abajo).
class JobVisitCard extends StatelessWidget {
  const JobVisitCard({
    super.key,
    required this.visit,
    required this.today,
    required this.narrow,
    this.filter,
    this.onOpenJob,
    this.subjects = const [],
    this.emptyLinesText = 'Sin líneas registradas.',
    this.footer,
  });

  final BikeVisit visit;
  final DateTime today;

  /// Teléfono: la fecha arriba en vez de la franja y el sistema sobre sus
  /// líneas en vez de en su columna.
  final bool narrow;

  /// Sólo las líneas de este sistema («Por sistema» de la bici).
  final JobLineSystem? filter;
  final ValueChanged<String>? onOpenJob;

  /// Las bicis, el componente o «Sin objeto recibido», al lado del estado.
  final List<JobVisitSubject> subjects;
  final String emptyLinesText;

  /// La factura del trabajo, en la franja del pie.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final job = visit.job;
    final groups = filter == null
        ? visit.groups
        : visit.groups.where((group) => group.system == filter).toList();
    final cancelled = isCancelledJob(job);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (narrow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      bikeFullDate(visit.date),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (job.jobNumber != null)
                      _JobNumber(
                        number: job.jobNumber!,
                        narrow: narrow,
                        onTap: job.id == null || onOpenJob == null
                            ? null
                            : () => onOpenJob!(job.id!),
                      ),
                    _status(context, job, cancelled: cancelled),
                    for (final subject in subjects)
                      _SubjectChip(subject: subject, narrow: narrow),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _meta(),
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _amount(context, cancelled: cancelled),
        ],
      ),
    );

    final request = visit.request?.trim();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (request != null && request.isNotEmpty && filter == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(
                  text: 'Pidió: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: bikeRequestAsSentence(request),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        if (groups.isEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Text(
              emptyLinesText,
              style: TextStyle(fontSize: 14, color: roles.faintForeground),
            ),
          ),
        for (final group in groups)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(group.system.label.toUpperCase(),
                          style: BikeModuleText.label(context)),
                      const SizedBox(height: 6),
                      for (final line in group.lines)
                        _VisitLine(line: line, narrow: true),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 128,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            group.system.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final line in group.lines)
                              _VisitLine(line: line, narrow: false),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        if (visit.separatePurchaseAmount > 0 && filter == null)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Text(
              'Además, ${_money.format(visit.separatePurchaseAmount)} en '
              'compras aparte en este trabajo.',
              style: TextStyle(fontSize: 13, color: roles.faintForeground),
            ),
          ),
        if (footer != null)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: footer,
          ),
      ],
    );

    final decoration = BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: theme.colorScheme.outlineVariant),
    );
    if (narrow) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    const stubWidth = 92.0;
    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: stubWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border(right: BorderSide(color: roles.hairline)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: stubWidth),
            child: content,
          ),
          Positioned(
            left: 0,
            top: 14,
            width: stubWidth,
            child: Semantics(
              label: bikeFullDate(visit.date),
              excludeSemantics: true,
              child: Column(
                children: [
                  Text(
                    visit.date.toLocal().day.toString().padLeft(2, '0'),
                    style: BikeModuleText.figure(context, size: 32)
                        .copyWith(fontWeight: FontWeight.w600, height: 1.05),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    bikeMonthYear(visit.date).toUpperCase(),
                    style: BikeModuleText.label(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «Ingresó el 12 ago · lleva 52 días». Una cotización sin objeto y una
  /// venta no ingresaron nada al taller: se dice de cuándo son.
  String _meta() {
    final job = visit.job;
    final arrival = bikeShortDate(job.arrivalDate, today: today);
    if (job.isStandaloneQuotation) return 'Cotización del $arrival';
    if (job.isSaleWorkflow) return 'Venta del $arrival';
    final days = visit.daysInWorkshop(today);
    final daysText = days == 1 ? '1 día' : '$days días';
    return switch ((visit.inWorkshop, days)) {
      (true, 0) => 'Ingresó hoy',
      (true, _) => 'Ingresó el $arrival · lleva $daysText',
      (false, 0) => 'Ingresó el $arrival · salió el mismo día',
      (false, _) => 'Ingresó el $arrival · $daysText en el taller',
    };
  }

  /// El estado del taller y, en un presupuesto con bici, el de la propuesta
  /// debajo: son dos ejes distintos.
  Widget _status(BuildContext context, MechanicJob job,
      {required bool cancelled}) {
    final dot = BikeJobStatusDot(
      label: jobVisitStatusLabel(job),
      color: jobVisitStatusColor(job),
      muted: cancelled,
    );
    if (job.isServiceBudget) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: 8),
          Text(
            job.proposalStatusDisplayName,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: VinabikeThemeRoles.of(context).faintForeground,
            ),
          ),
        ],
      );
    }
    return dot;
  }

  /// El monto. El de una propuesta todavía no se cobra: se dice que es un
  /// total presupuestado o cotizado.
  Widget _amount(BuildContext context, {required bool cancelled}) {
    final theme = Theme.of(context);
    final job = visit.job;
    final figure = Text(
      visit.amount > 0 ? _money.format(visit.amount) : '—',
      style: BikeModuleText.figure(context, size: narrow ? 19 : 22).copyWith(
        color: cancelled
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface,
        decoration: cancelled ? TextDecoration.lineThrough : null,
      ),
    );
    if (!job.isQuotationWorkflow) return figure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        figure,
        const SizedBox(height: 4),
        Text(
          job.isServiceBudget ? 'Total presupuestado' : 'Total cotizado',
          style: TextStyle(
            fontSize: 12,
            color: VinabikeThemeRoles.of(context).faintForeground,
          ),
        ),
      ],
    );
  }
}

class _JobNumber extends StatelessWidget {
  const _JobNumber({
    required this.number,
    required this.narrow,
    required this.onTap,
  });

  final String number;
  final bool narrow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      label: 'Abrir trabajo $number',
      // Sin el hijo en la semántica, la acción va aquí.
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          // En teléfono el número es un objetivo táctil.
          constraints: BoxConstraints(
            minHeight: narrow ? 48 : 28,
            minWidth: narrow ? 48 : 0,
          ),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              number,
              style: BikeModuleText.code(
                context,
                color: onTap == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({required this.subject, required this.narrow});

  final JobVisitSubject subject;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      subject.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final onTap = subject.onTap;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: narrow && onTap != null ? 44 : 28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                if (onTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitLine extends StatelessWidget {
  const _VisitLine({required this.line, required this.narrow});

  final BikeVisitLine line;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final quantity = line.quantity == 1
        ? ''
        : ' × ${line.quantity == line.quantity.roundToDouble() ? line.quantity.toInt() : line.quantity}';
    final amount = Text(
      line.amount > 0 ? _money.format(line.amount) : '—',
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 14,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${line.name}$quantity'),
                if (line.isService && narrow)
                  TextSpan(
                    text: ' · servicio',
                    style:
                        TextStyle(fontSize: 12, color: roles.faintForeground),
                  ),
              ]),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
          if (!narrow)
            SizedBox(
              width: 72,
              child: Text(
                line.isService ? 'Servicio' : 'Repuesto',
                style: TextStyle(fontSize: 12, color: roles.faintForeground),
              ),
            ),
          SizedBox(width: narrow ? 78 : 90, child: amount),
        ],
      ),
    );
  }
}
