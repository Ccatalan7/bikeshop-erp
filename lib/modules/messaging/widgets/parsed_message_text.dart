import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/right_toolbar_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/message_parser.dart';
import '../../../shared/services/workspace_manager.dart';
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
          } else if (segment is AppRouteLinkSegment) {
            return TextSpan(
              text: segment.text,
              style: baseStyle.copyWith(
                color: linkColor,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _handleRouteLinkTap(context, segment),
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

    if (ref.type == RefType.task) {
      // La tarjeta canónica de la tarea vive en la bandeja: se abre el panel
      // directamente en ese detalle (mismo mecanismo pendiente que usan las
      // notificaciones para abrir un hilo).
      context.read<RightToolbarService>().openConversation(
            tool: ToolbarTool.tasks,
            conversationId: ref.id,
          );
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

  Future<void> _handleRouteLinkTap(
    BuildContext context,
    AppRouteLinkSegment link,
  ) async {
    try {
      context
          .read<WorkspaceManager>()
          .navigateActiveWorkspaceFromSharedLink(link.route);
      return;
    } catch (_) {
      if (await canLaunchUrl(link.uri)) {
        await launchUrl(link.uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace compartido.')),
    );
  }
}
