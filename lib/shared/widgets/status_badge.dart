import 'package:flutter/material.dart';

/// Reusable status badge widget for invoices
/// Displays status with appropriate color and style
class StatusBadge extends StatelessWidget {
  final String status;
  final bool isLarge;

  const StatusBadge({
    super.key,
    required this.status,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 12 : 8,
        vertical: isLarge ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(isLarge ? 6 : 4),
        border: Border.all(
          color: config.borderColor,
          width: 1,
        ),
      ),
      child: Text(
        config.label,
        style: TextStyle(
          color: config.textColor,
          fontSize: isLarge ? 14 : 12,
          fontWeight: isLarge ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return _StatusConfig(
          label: 'Borrador',
          backgroundColor: Colors.grey.shade100,
          borderColor: Colors.grey.shade300,
          textColor: Colors.grey.shade700,
        );
      case 'sent':
        return _StatusConfig(
          label: 'Enviada',
          backgroundColor: Colors.blue.shade50,
          borderColor: Colors.blue.shade300,
          textColor: Colors.blue.shade700,
        );
      case 'confirmed':
        return _StatusConfig(
          label: 'Confirmada',
          backgroundColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade300,
          textColor: Colors.orange.shade700,
        );
      case 'received':
        return _StatusConfig(
          label: 'Recibida',
          backgroundColor: Colors.purple.shade50,
          borderColor: Colors.purple.shade300,
          textColor: Colors.purple.shade700,
        );
      case 'paid':
        return _StatusConfig(
          label: 'Pagada',
          backgroundColor: Colors.green.shade50,
          borderColor: Colors.green.shade300,
          textColor: Colors.green.shade700,
        );
      case 'cancelled':
        return _StatusConfig(
          label: 'Cancelada',
          backgroundColor: Colors.red.shade50,
          borderColor: Colors.red.shade300,
          textColor: Colors.red.shade700,
        );
      default:
        return _StatusConfig(
          label: status,
          backgroundColor: Colors.grey.shade100,
          borderColor: Colors.grey.shade300,
          textColor: Colors.grey.shade700,
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  _StatusConfig({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });
}
