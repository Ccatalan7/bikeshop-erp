import 'package:flutter/material.dart';

import '../../shared/utils/chilean_utils.dart';
import '../models/customer_portal_presentation.dart';
import 'customer_bike_drawing.dart';
import 'customer_portal_style.dart';

/// Columnas de la tabla de trabajos en ancho: bici y pedido, número, fecha,
/// estado y total.
const double _numberColumn = 120;
const double _dateColumn = 120;
const double _statusColumn = 200;
const double _totalColumn = 110;

/// Desde este ancho los trabajos se leen como tabla.
const double customerJobTableBreakpoint = 880;

class CustomerJobTableHeader extends StatelessWidget {
  const CustomerJobTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    Text label(String text, {TextAlign align = TextAlign.left}) =>
        Text(text, textAlign: align, style: style.micro);
    return ExcludeSemantics(
      child: Row(
        children: [
          const SizedBox(width: 72 + 20),
          Expanded(child: label('BICICLETA')),
          SizedBox(width: _numberColumn, child: label('SERVICIO')),
          SizedBox(width: _dateColumn, child: label('INGRESÓ')),
          SizedBox(width: _statusColumn, child: label('ESTADO')),
          SizedBox(
            width: _totalColumn,
            child: label('TOTAL', align: TextAlign.right),
          ),
          const SizedBox(width: 18 + 16),
        ],
      ),
    );
  }
}

/// El dibujo chico de la bici de un trabajo, sobre el gris.
Widget _bikeThumb(Map<String, dynamic> job, PortalStyle style,
        {double size = 72}) =>
    PortalThumb(
      fallbackIcon: Icons.pedal_bike_outlined,
      size: size,
      child: CustomerBikeDrawing(
        silhouette: customerBikeSilhouette(job['bike_type']),
        width: size * 0.82,
        color: style.ink,
      ),
    );

/// Un trabajo de taller en una fila: la bici, lo que se pidió y cuándo
/// entró, con el estado en palabras del cliente. En ancho son columnas; en
/// teléfono se apila. La usan el resumen y «Taller».
class CustomerJobRow extends StatelessWidget {
  const CustomerJobRow({
    super.key,
    required this.job,
    required this.onTap,
    this.showTotal = false,
  });

  final Map<String, dynamic> job;
  final VoidCallback onTap;

  /// En «Taller» se muestra el total; en el resumen, no (ahí manda el estado).
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final presentation = CustomerWorkshopPresentation.of(job);
    final received = CustomerWorkshopPresentation.receivedAt(job);
    final request = CustomerWorkshopPresentation.requestSummary(job);
    final amount = showTotal ? CustomerWorkshopPresentation.total(job) : null;
    final total = amount == null ? null : ChileanUtils.formatCurrency(amount);
    final number = (job['job_number'] ?? '').toString().trim();
    final bike = CustomerWorkshopPresentation.bikeTitle(job);
    final tag = PortalStatusTag(
      label: presentation.label,
      tone: presentation.tone,
      needsCustomer: presentation.needsCustomer,
      active: presentation.isActive,
    );
    final nextStep = presentation.needsCustomer ? presentation.nextStep : null;
    // Fecha sin cortes: «24 sep 2026» no se parte al final de una línea.
    final date =
        received == null ? null : portalDate(received).replaceAll(' ', ' ');
    final what = request.isNotEmpty
        ? request
        : number.isEmpty
            ? null
            : 'Servicio $number';

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bike,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.rowTitle,
        ),
        if (what != null) ...[
          const SizedBox(height: 3),
          Text(
            what,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.rowMeta,
          ),
        ],
        if (nextStep != null) ...[
          const SizedBox(height: 4),
          Text(nextStep, style: style.nextStep),
        ],
      ],
    );

    return Semantics(
      button: true,
      label: [
        bike,
        if (number.isNotEmpty) 'servicio $number',
        presentation.label,
      ].join(', '),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (width >= customerJobTableBreakpoint) {
                  return Row(
                    children: [
                      _bikeThumb(job, style),
                      const SizedBox(width: 20),
                      Expanded(child: title),
                      SizedBox(
                        width: _numberColumn,
                        child: Text(
                          number,
                          style: style.heading(
                            14,
                            weight: FontWeight.w500,
                            color: style.inkSecondary,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _dateColumn,
                        child: Text(date ?? '—', style: style.rowMeta),
                      ),
                      SizedBox(
                        width: _statusColumn,
                        child:
                            Align(alignment: Alignment.centerLeft, child: tag),
                      ),
                      SizedBox(
                        width: _totalColumn,
                        child: Text(
                          total ?? '',
                          textAlign: TextAlign.right,
                          style: style.figure,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, size: 18, color: style.ink),
                    ],
                  );
                }
                final tail = [
                  if (date != null) date,
                  if (total != null) total,
                ].join(' · ');
                if (width >= PortalStyle.compactBreakpoint) {
                  return Row(
                    children: [
                      _bikeThumb(job, style),
                      const SizedBox(width: 20),
                      Expanded(child: title),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          tag,
                          if (tail.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(tail, style: style.rowMeta),
                          ],
                        ],
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, size: 18, color: style.ink),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bikeThumb(job, style, size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const SizedBox(height: 10),
                          // El estado a la izquierda y la fecha con el total
                          // a la derecha; si no caben juntos, la fecha baja
                          // una línea en vez de cortar el estado.
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                tag,
                                if (tail.isNotEmpty)
                                  Text(tail, style: style.rowMeta),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Un trabajo que sigue en el taller, en grande: el dibujo de la bici sobre
/// el gris, el estado, lo que se pidió, el avance en cinco pasos y qué hacer.
///
/// Con [PortalTileLayout.equalHeight] la ficha llena el alto que le dan (dos
/// fichas lado a lado dentro de un `IntrinsicHeight`) y los botones bajan al
/// pie; por eso no lleva `LayoutBuilder` adentro.
class CustomerJobTile extends StatelessWidget {
  const CustomerJobTile({
    super.key,
    required this.job,
    required this.onOpen,
    required this.onNavigate,
    required this.compact,
    this.layout = PortalTileLayout.stacked,
  });

  final Map<String, dynamic> job;
  final VoidCallback onOpen;
  final ValueChanged<String> onNavigate;
  final bool compact;
  final PortalTileLayout layout;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final presentation = CustomerWorkshopPresentation.of(job);
    final number = (job['job_number'] ?? '').toString().trim();
    final bike = CustomerWorkshopPresentation.bikeTitle(job);
    final step = customerWorkshopStep(job);
    final message = customerJobMessage(job);
    final approval = presentation.needsCustomer &&
        (job['status'] ?? '').toString().toUpperCase() ==
            'ESPERANDO_APROBACION';

    final actions = <Widget>[
      if (approval) ...[
        PortalButton(
          label: 'Responder al taller',
          arrow: true,
          expand: compact,
          onPressed: () => onNavigate('/cuenta/chats'),
        ),
        PortalButton(
          label: 'Ver ficha',
          kind: PortalButtonKind.secondary,
          expand: compact,
          onPressed: onOpen,
        ),
      ] else if (presentation.needsCustomer)
        PortalButton(
          label: 'Ver ficha',
          arrow: true,
          expand: compact,
          onPressed: onOpen,
        )
      else ...[
        PortalButton(
          label: 'Ver ficha',
          kind: PortalButtonKind.secondary,
          expand: compact,
          onPressed: onOpen,
        ),
        if (!compact)
          PortalLink(
            label: 'Preguntar al taller',
            onTap: () => onNavigate('/cuenta/chats'),
          ),
      ],
    ];

    final horizontal = layout == PortalTileLayout.horizontal;
    final well = PortalWell(
      height: horizontal ? 300 : (compact ? 190 : 220),
      topLeft: const PortalTag(label: 'Taller'),
      topRight: number.isEmpty ? null : number,
      child: CustomerBikeDrawing(
        silhouette: customerBikeSilhouette(job['bike_type']),
        width: compact ? 230 : (horizontal ? 330 : 270),
        color: style.ink,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PortalStatusTag(
            label: presentation.label,
            tone: presentation.tone,
            needsCustomer: presentation.needsCustomer,
            active: presentation.isActive,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            bike.toUpperCase(),
            semanticsLabel: bike,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.featureTitle(compact: compact),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message, style: style.pageSubtitle),
        ],
        if (step != null && step < customerWorkshopSteps.length) ...[
          const SizedBox(height: 18),
          PortalWorkshopProgress(
            step: step,
            needsCustomer: presentation.needsCustomer,
            showLabels: !compact,
          ),
        ],
        if (layout == PortalTileLayout.equalHeight)
          const Spacer()
        else
          const SizedBox(height: 4),
        const SizedBox(height: 20),
        if (compact)
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            actions[i],
          ]
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
      ],
    );
    return portalTileFrame(
      well: well,
      details: details,
      layout: layout,
      compact: compact,
    );
  }
}

/// La frase de un trabajo en grande: el presupuesto cuando espera la
/// aprobación del cliente, lo que pidió en los demás casos.
String? customerJobMessage(Map<String, dynamic> job) {
  final request = CustomerWorkshopPresentation.requestSummary(job);
  final amount = CustomerWorkshopPresentation.total(job);
  final presentation = CustomerWorkshopPresentation.of(job);
  final code = (job['status'] ?? '').toString().trim().toUpperCase();
  if (code == 'ESPERANDO_APROBACION' &&
      presentation.needsCustomer &&
      amount != null) {
    final total = ChileanUtils.formatCurrency(amount);
    if (request.isEmpty) return 'Presupuesto de $total.';
    final lower = request[0].toLowerCase() + request.substring(1);
    return 'Presupuesto de $total por $lower.';
  }
  if (presentation.needsCustomer && amount != null && request.isEmpty) {
    return 'Total ${ChileanUtils.formatCurrency(amount)}.';
  }
  return request.isEmpty ? null : request;
}

/// La ficha de un trabajo: qué se pidió, qué encontró el taller, qué se hizo,
/// fechas y total. Si espera la aprobación del cliente, lo lleva a Soporte.
Future<void> showCustomerJobDetail(
  BuildContext context, {
  required Map<String, dynamic> job,
  required ValueChanged<String> onNavigate,
}) {
  final presentation = CustomerWorkshopPresentation.of(job);
  final number = (job['job_number'] ?? '').toString().trim();
  final received = CustomerWorkshopPresentation.receivedAt(job);
  final deadline = portalParseDate(job['deadline']);
  final total = CustomerWorkshopPresentation.total(job);
  final request = CustomerWorkshopPresentation.requestSummary(job);
  final step = customerWorkshopStep(job);
  String? text(String key) {
    final value = (job[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  return showPortalDetail(
    context,
    title: CustomerWorkshopPresentation.bikeTitle(job),
    subtitle: number.isEmpty ? null : 'Servicio $number',
    status: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PortalStatusTag(
            label: presentation.label,
            tone: presentation.tone,
            needsCustomer: presentation.needsCustomer,
            active: presentation.isActive,
          ),
        ),
        if (step != null && step < customerWorkshopSteps.length) ...[
          const SizedBox(height: 16),
          PortalWorkshopProgress(
            step: step,
            needsCustomer: presentation.needsCustomer,
            showLabels: MediaQuery.sizeOf(context).width >= 600,
          ),
        ],
      ],
    ),
    body: PortalFacts(
      facts: [
        ('Lo que pediste', request.isEmpty ? null : request),
        ('Diagnóstico', text('diagnosis')),
        ('Trabajo realizado', text('work_performed')),
        ('Ingresó', received == null ? null : portalDate(received)),
        (
          'Fecha estimada',
          presentation.isActive && deadline != null
              ? portalDate(deadline)
              : null
        ),
        ('Total', total == null ? null : ChileanUtils.formatCurrency(total)),
      ],
    ),
    actions: [
      Builder(
        builder: (buttonContext) => PortalButton(
          label: presentation.needsCustomer
              ? 'Responder al taller'
              : 'Preguntar al taller',
          arrow: true,
          onPressed: () {
            Navigator.of(buttonContext).pop();
            onNavigate('/cuenta/chats');
          },
        ),
      ),
    ],
  );
}
