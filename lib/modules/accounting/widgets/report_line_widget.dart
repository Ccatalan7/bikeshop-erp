import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_line.dart';

/// Widget to display a single line in a financial report
/// Handles indentation, formatting, and styling based on line type
/// Redesigned for compact, space-efficient layout
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
      return const SizedBox(height: 4);
    }

    // Determine indentation based on level (reduced from 24px to 16px per level)
    final indent = _getIndentation(line.level);

    // Determine text style
    final textStyle = _getTextStyle(context, line);

    // Determine background color
    final backgroundColor = _getBackgroundColor(context, line);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 4), // Reduced from 16px/8px
      decoration: BoxDecoration(
        color: backgroundColor,
        border: line.isTotal
            ? Border(
                top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1), // Reduced from 2px
                bottom:
                    BorderSide(color: Theme.of(context).dividerColor, width: 1),
              )
            : line.isSubtotal
                ? Border(
                    bottom: BorderSide(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.5),
                        width: 1),
                  )
                : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Indentation
          SizedBox(width: indent),

          // Account code (flexible width instead of fixed)
          if (showCode &&
              line.code.isNotEmpty &&
              !line.isTotal &&
              !line.isSubtotal)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Text(
                line.code,
                style: textStyle.copyWith(
                  fontFamily: 'Courier', // Monospace for alignment
                  fontSize: textStyle.fontSize! * 0.85,
                  color: Theme.of(context)
                      .colorScheme
                      .secondary
                      .withValues(alpha: 0.7),
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
              maxLines: 1, // Reduced from 2 for compactness
            ),
          ),

          const SizedBox(width: 12), // Reduced from 16

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

  /// Get indentation in pixels based on hierarchical level (reduced spacing)
  double _getIndentation(int level) {
    switch (level) {
      case 0:
        return 0.0; // Total
      case 1:
        return 0.0; // Subtotal
      case 2:
        return 16.0; // Account (reduced from 24px)
      case 3:
        return 32.0; // Subaccount (reduced from 48px)
      default:
        return (16 * level).toDouble(); // Reduced from 24px per level
    }
  }

  /// Get text style based on line type
  TextStyle _getTextStyle(BuildContext context, ReportLine line) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium!;

    if (line.isTotal) {
      return baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: 15, // Slightly reduced from 16
      );
    }

    if (line.isSubtotal || line.isBold) {
      return baseStyle.copyWith(
        fontWeight: FontWeight.w600, // Slightly lighter than bold
        fontSize: 14,
      );
    }

    return baseStyle.copyWith(fontSize: 13); // Slightly smaller for compactness
  }

  /// Get background color based on line type (more subtle)
  Color? _getBackgroundColor(BuildContext context, ReportLine line) {
    if (line.isTotal) {
      return Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3);
    }

    if (line.isSubtotal) {
      return Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.15);
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
