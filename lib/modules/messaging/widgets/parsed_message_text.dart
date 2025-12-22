import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../utils/message_parser.dart';
import 'quick_actions/job_preview_dialog.dart';
import 'quick_actions/invoice_preview_dialog.dart';

class ParsedMessageText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool isMe;
  final Function(ReferenceSegment)? onReferenceTap;

  const ParsedMessageText({
    super.key,
    required this.text,
    this.style,
    this.isMe = false,
    this.onReferenceTap,
  });

  @override
  Widget build(BuildContext context) {
    final segments = MessageParser.parse(text);
    final baseStyle =
        style ?? const TextStyle(fontSize: 14, color: Colors.black87);
    final linkColor = isMe ? Colors.white : Colors.blue[700];

    return Text.rich(
      TextSpan(
        children: segments.map((segment) {
          if (segment is ReferenceSegment) {
            return TextSpan(
              text: segment.text,
              style: baseStyle.copyWith(
                color: linkColor,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _handleRefTap(context, segment),
            );
          } else {
            return TextSpan(text: segment.text, style: baseStyle);
          }
        }).toList(),
      ),
    );
  }

  void _handleRefTap(BuildContext context, ReferenceSegment ref) {
    if (onReferenceTap != null) {
      onReferenceTap!(ref);
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        switch (ref.type) {
          case RefType.job:
            return JobPreviewDialog(jobNumber: ref.id);
          case RefType.invoice:
            return InvoicePreviewDialog(invoiceNumber: ref.id);
          default:
            return AlertDialog(title: Text('Unknown Ref: ${ref.text}'));
        }
      },
    );
  }
}
