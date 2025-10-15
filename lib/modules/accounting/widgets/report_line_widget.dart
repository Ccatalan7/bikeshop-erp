import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_line.dart';

/// Widget to display a single line in a financial report
/// Handles indentation, formatting, and styling based on line type
class ReportLineWidget extends StatelessWidget {
  final ReportLine line;
  final NumberFormat currencyFormat;
  final bool showCode;

  const ReportLineWidget({
    super.key,
    required this.line,
    required this.currencyFormat,
    this.showCode = true,
  });

  @override
  Widget build(BuildContext context) {
    // Don't render blank lines with visible content
    if (!line.showAmount && line.name.isEmpty) {
      return const SizedBox(height: 8);
    }

    // Determine indentation based on level
    final indent = _getIndentation(line.level);
    
    // Determine text style
    final textStyle = _getTextStyle(context, line);
    
    // Determine background color
    final backgroundColor = _getBackgroundColor(context, line);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: line.isTotal ? Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 2),
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 2),
        ) : line.isSubtotal ? Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Indentation
          SizedBox(width: indent),
          
          // Account code (if showing)
          if (showCode && line.code.isNotEmpty && !line.isTotal && !line.isSubtotal)
            Container(
              width: 80,
              margin: const EdgeInsets.only(right: 8),
              child: Text(
                line.code,
                style: textStyle.copyWith(
                  fontFamily: 'Courier', // Monospace for alignment
                  fontSize: textStyle.fontSize! * 0.9,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          
          // Account name
          Expanded(
            flex: 3,
            child: Text(
              line.name,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Amount
          if (line.showAmount)
            Expanded(
              flex: 1,
              child: Text(
                _formatAmount(line.amount),
                style: textStyle.copyWith(
                  fontFamily: 'RobotoMono', // Monospace for number alignment
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.visible,
              ),
            ),
        ],
      ),
    );
  }

  /// Get indentation in pixels based on hierarchical level
  double _getIndentation(int level) {
    switch (level) {
      case 0: return 0.0;      // Total
      case 1: return 0.0;      // Subtotal
      case 2: return 24.0;     // Account
      case 3: return 48.0;     // Subaccount
      default: return (24 * level).toDouble();
    }
  }

  /// Get text style based on line type
  TextStyle _getTextStyle(BuildContext context, ReportLine line) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium!;
    
    if (line.isTotal) {
      return baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: 16,
      );
    }
    
    if (line.isSubtotal || line.isBold) {
      return baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: 14,
      );
    }
    
    return baseStyle;
  }

  /// Get background color based on line type
  Color? _getBackgroundColor(BuildContext context, ReportLine line) {
    if (line.isTotal) {
      return Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5);
    }
    
    if (line.isSubtotal) {
      return Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2);
    }
    
    return null;
  }

  /// Format amount with proper sign and Chilean formatting
  String _formatAmount(double amount) {
    if (amount == 0 && !line.isTotal && !line.isSubtotal) {
      return '-';
    }
    
    final absAmount = amount.abs();
    final formatted = currencyFormat.format(absAmount);
    
    // Show negative amounts in parentheses (Chilean accounting standard)
    if (amount < 0) {
      return '($formatted)';
    }
    
    return formatted;
  }
}
