import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/record_peek.dart';
import 'mail_navigation.dart';
import 'mail_record_list.dart';
import 'mail_work_controller.dart';
import 'mail_work_detail.dart';

/// Los correos de un registro: la etapa 2 de «Correo que trabaja». Un trabajo,
/// un cliente, un proveedor, una compra o un gasto muestran los correos
/// ligados a ellos donde ya vive su conversación, y cada uno se lee encima,
/// con sus botones, sin salir del registro (`showMailPeek`).
///
/// Sin correos, o sin acceso al correo, no ocupa lugar.
class MailRecordHistory extends StatelessWidget {
  const MailRecordHistory({
    super.key,
    required this.recordType,
    required this.recordId,
    this.maxRows = 4,
    this.padding = EdgeInsets.zero,
    this.onCount,
    this.frame,
  });

  /// `job`, `customer`, `supplier`, `purchase_invoice`, `online_order`,
  /// `expense` o `sales_invoice`.
  final String recordType;
  final String recordId;
  final int maxRows;
  final EdgeInsetsGeometry padding;
  final ValueChanged<int>? onCount;

  /// Ver `MailRecordList.frame`.
  final Widget Function(BuildContext context, int count, Widget body)? frame;

  @override
  Widget build(BuildContext context) {
    return MailRecordList(
      recordType: recordType,
      recordId: recordId,
      maxRows: maxRows,
      padding: padding,
      onCount: onCount,
      frame: frame,
      onOpen: (item) => showMailPeek(context, messageId: item.id),
    );
  }
}

/// Lee un correo encima de lo que se está haciendo, con sus botones: en
/// escritorio entra desde la derecha; en el teléfono es una hoja. «Abrir en
/// Correo» lleva a la pantalla del correo con ese mismo correo abierto.
Future<void> showMailPeek(BuildContext context, {required String messageId}) {
  return showRecordPeek(
    context,
    panelWidth: 560,
    builder: (hostContext, close) => _MailPeek(
      messageId: messageId,
      close: close,
      pageContext: context,
    ),
  );
}

class _MailPeek extends StatefulWidget {
  const _MailPeek({
    required this.messageId,
    required this.close,
    required this.pageContext,
  });

  final String messageId;
  final VoidCallback close;
  final BuildContext pageContext;

  @override
  State<_MailPeek> createState() => _MailPeekState();
}

class _MailPeekState extends State<_MailPeek> {
  final MailWorkController _controller = MailWorkController(followsList: false);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    unawaited(_controller.select(widget.messageId));
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  /// Un botón del correo que lleva a otra pantalla (registrar el cobro,
  /// abrir el proveedor) cierra este panel y navega el espacio de trabajo.
  Future<void> _leaveTo(String route) async {
    final page = widget.pageContext;
    widget.close();
    if (page.mounted) openMailRoute(page, route);
  }

  void _openInMail() {
    final page = widget.pageContext;
    final route = '/mail?mail=${widget.messageId}';
    widget.close();
    if (page.mounted) openMailRoute(page, route);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final detail = _controller.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _openInMail,
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Abrir en Correo'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: widget.close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        Expanded(
          child: detail != null
              ? MailNavigation(
                  go: _leaveTo,
                  child: MailWorkDetail(
                    key: ValueKey(detail.id),
                    item: detail,
                    controller: _controller,
                    compact: true,
                  ),
                )
              : _controller.detailError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo abrir este correo.',
                          style: TextStyle(
                              fontSize: 14, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ],
    );
  }
}
