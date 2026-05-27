import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bikeshop_models.dart';

class DeadlineCell extends StatefulWidget {
  final MechanicJob job;
  final VoidCallback? onTap;

  const DeadlineCell({
    super.key,
    required this.job,
    this.onTap,
  });

  @override
  State<DeadlineCell> createState() => _DeadlineCellState();
}

class _DeadlineCellState extends State<DeadlineCell> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final now = DateTime.now();
    final canEdit = widget.onTap != null;
    final idleGrey = Colors.grey.withValues(alpha: 0);
    final hoverGreyFill = Colors.grey.withValues(alpha: 0.08);
    final hoverGreyBorder = Colors.grey.withValues(alpha: 0.24);

    // Check availability
    final hasDiagnostic = job.diagnosticDeadline != null;
    final hasDelivery = job.deliveryDeadline != null;

    if (!hasDiagnostic && !hasDelivery) {
      return MouseRegion(
        cursor: canEdit ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _isHovering ? hoverGreyFill : idleGrey,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovering ? hoverGreyBorder : idleGrey,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Sin plazo',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Determine overdue status
    final isDiagOverdue = hasDiagnostic &&
        job.diagnosticDeadline!.isBefore(now) &&
        job.diagnosticSentAt == null &&
        job.status != JobStatus.entregado;

    final isDeliveryOverdue = hasDelivery &&
        job.deliveryDeadline!.isBefore(now) &&
        job.status != JobStatus.entregado;

    // Determine which deadline is "primary" (currently active)
    // If diagnostic is not sent yet (and deadline exists), it's the primary concern.
    // Otherwise, delivery is the primary concern.
    final bool showDiagnosticAsPrimary =
        hasDiagnostic && job.diagnosticSentAt == null;

    return MouseRegion(
      cursor: canEdit ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: _buildCompactView(showDiagnosticAsPrimary, isDiagOverdue,
              isDeliveryOverdue, hasDiagnostic, hasDelivery),
        ),
      ),
    );
  }

  Widget _buildCompactView(
    bool showDiagnostic,
    bool isDiagOverdue,
    bool isDeliveryOverdue,
    bool hasDiagnostic,
    bool hasDelivery,
  ) {
    // If we should show diagnostic, but it doesn't exist, fallback to delivery
    if (showDiagnostic && !hasDiagnostic) {
      showDiagnostic = false;
    }
    // If we should show delivery (showDiagnostic is false), but it doesn't exist, fallback to diagnostic
    else if (!showDiagnostic && !hasDelivery) {
      showDiagnostic = true;
    }

    if (showDiagnostic) {
      return _buildChip(
        icon: Icons.search,
        label: DateFormat('dd/MM').format(widget.job.diagnosticDeadline!),
        isOverdue: isDiagOverdue,
        color: Colors.blue,
        showIndicator: hasDiagnostic && hasDelivery,
      );
    } else {
      return _buildChip(
        icon: Icons.local_shipping_outlined,
        label: DateFormat('dd/MM').format(widget.job.deliveryDeadline!),
        isOverdue: isDeliveryOverdue,
        color: Colors.green,
        showIndicator: hasDiagnostic && hasDelivery,
      );
    }
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required bool isOverdue,
    required MaterialColor color,
    bool showIndicator = false,
  }) {
    final effectiveColor = isOverdue ? Colors.red : color;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: effectiveColor.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: effectiveColor.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: effectiveColor.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: effectiveColor.shade700,
            ),
          ),
        ],
      ),
    );

    if (!showIndicator) return chip;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: effectiveColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        chip,
      ],
    );
  }
}
