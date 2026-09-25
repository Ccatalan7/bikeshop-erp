import 'package:flutter/material.dart';

import '../../shared/utils/chilean_utils.dart';
import '../models/customer_portal_presentation.dart';
import 'customer_portal_style.dart';

/// Un trabajo de taller en una fila del portal: la bici, lo que se pidió y
/// cuándo entró, con el estado en palabras del cliente. La usan el resumen y
/// «Taller», así se leen igual en los dos lados.
class CustomerJobRow extends StatelessWidget {
  const CustomerJobRow({
    super.key,
    required this.job,
    required this.compact,
    required this.onTap,
    this.showTotal = false,
  });

  final Map<String, dynamic> job;
  final bool compact;
  final VoidCallback onTap;

  /// En «Taller» se muestra el total; en el resumen, no (ahí manda el estado).
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final presentation = CustomerWorkshopPresentation.of(job);
    final received = CustomerWorkshopPresentation.receivedAt(job);
    final request = CustomerWorkshopPresentation.requestSummary(job);
    final total = showTotal ? CustomerWorkshopPresentation.total(job) : null;
    final number = (job['job_number'] ?? '').toString().trim();
    final pill = PortalStatusPill(
      label: presentation.label,
      tone: presentation.tone,
    );
    final nextStep = presentation.needsCustomer ? presentation.nextStep : null;
    // Fecha sin cortes: «24 sep 2026» no se parte al final de una línea.
    final date = received == null
        ? null
        : portalDate(received).replaceAll(' ', '\u00A0');
    final what = request.isNotEmpty
        ? request
        : number.isEmpty
            ? null
            : 'Servicio $number';

    // En teléfono lo pedido ocupa el detalle, y la fecha y el total van a la
    // derecha del estado: así un pedido largo no se come la fecha.
    final tail = [
      if (date != null) date,
      if (total != null) ChileanUtils.formatCurrency(total),
    ].join(' · ');

    return PortalRow(
      leading: const PortalThumb(fallbackIcon: Icons.pedal_bike_outlined),
      title: CustomerWorkshopPresentation.bikeTitle(job),
      meta: compact
          ? what
          : [if (what != null) what, if (date != null) 'ingresó el $date']
              .join(' · '),
      semanticsLabel: [
        CustomerWorkshopPresentation.bikeTitle(job),
        if (number.isNotEmpty) 'servicio $number',
        presentation.label,
      ].join(', '),
      footer: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // El estado a la izquierda y la fecha con el total a la
                // derecha; si no caben juntos, la fecha baja una línea en vez
                // de cortar el estado.
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      pill,
                      if (tail.isNotEmpty) Text(tail, style: style.rowMeta),
                    ],
                  ),
                ),
                if (nextStep != null) ...[
                  const SizedBox(height: 6),
                  Text(nextStep, style: style.nextStep),
                ],
              ],
            )
          : nextStep == null
              ? null
              : Text(nextStep, style: style.nextStep),
      trailing: compact
          ? null
          : PortalTrailingColumns(
              pill: pill,
              figure: total == null ? null : ChileanUtils.formatCurrency(total),
            ),
      onTap: onTap,
    );
  }
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
  String? text(String key) {
    final value = (job[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  return showPortalDetail(
    context,
    title: CustomerWorkshopPresentation.bikeTitle(job),
    subtitle: number.isEmpty ? null : 'Servicio $number',
    status: PortalStatusLine(
      pill: PortalStatusPill(
        label: presentation.label,
        tone: presentation.tone,
      ),
      nextStep: presentation.needsCustomer ? presentation.nextStep : null,
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
        builder: (buttonContext) => FilledButton(
          style: portalPrimaryButton(buttonContext),
          onPressed: () {
            Navigator.of(buttonContext).pop();
            onNavigate('/cuenta/chats');
          },
          child: Text(
            presentation.needsCustomer
                ? 'Responder al taller'
                : 'Preguntar al taller',
          ),
        ),
      ),
    ],
  );
}
