import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../purchases/widgets/brand_mark.dart';
import 'mail_work_models.dart';
import 'mail_work_service.dart';
import 'mail_work_words.dart';

/// La lista de los correos de un registro (`mail_record_messages_v1`), sin el
/// lector: liviana para lo que viaja también en la tienda pública (la ficha de
/// un pedido web). Quien la usa dice qué pasa al tocar un correo; en el ERP es
/// `MailRecordHistory`, que lo abre encima.
///
/// Sin correos, o sin acceso al correo, no ocupa lugar.
class MailRecordList extends StatefulWidget {
  const MailRecordList({
    super.key,
    required this.recordType,
    required this.recordId,
    required this.onOpen,
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

  /// Cuántos correos tiene el registro, para el número de una pestaña.
  final ValueChanged<int>? onCount;

  /// Qué pasa al tocar un correo; al terminar, la lista se vuelve a leer
  /// (su estado pudo cambiar).
  final Future<void> Function(MailItem item) onOpen;

  /// El título y el marco de la sección con el estilo de la página que la
  /// hospeda (el proveedor titula sus grupos a su manera). Sin él, la lista
  /// lleva su propia etiqueta «CORREO».
  final Widget Function(BuildContext context, int count, Widget body)? frame;

  @override
  State<MailRecordList> createState() => _MailRecordListState();
}

class _MailRecordListState extends State<MailRecordList> {
  MailWorkService? _service;
  List<MailItem>? _items;
  bool _failed = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MailRecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId ||
        oldWidget.recordType != widget.recordType) {
      _items = null;
      _showAll = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final MailWorkService service;
    try {
      service = _service ??= MailWorkService();
    } catch (_) {
      // Sin Supabase inicializado (una prueba que monta la ficha) no hay
      // correo que leer: la sección no aparece.
      if (mounted) {
        setState(() {
          _items = const [];
          _failed = false;
        });
      }
      return;
    }
    try {
      final items =
          await service.recordMessages(widget.recordType, widget.recordId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _failed = false;
      });
      widget.onCount?.call(items.length);
    } catch (error) {
      if (!mounted) return;
      // Una cuenta sin acceso al correo no ve la sección.
      final forbidden = '$error'.contains('mail_forbidden');
      setState(() {
        _items = forbidden ? const [] : null;
        _failed = !forbidden;
      });
    }
  }

  Future<void> _open(MailItem item) async {
    await widget.onOpen(item);
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    if (_failed && items == null) {
      return Padding(
        padding: widget.padding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'No se pudo leer el correo de este registro.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _failed = false);
                unawaited(_load());
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    // Los roles del tema se piden sólo cuando hay filas que pintar.
    final roles = VinabikeThemeRoles.of(context);
    final shown =
        _showAll ? items : items.take(widget.maxRows).toList(growable: false);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in shown)
          _HistoryRow(item: item, onTap: () => unawaited(_open(item))),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        if (items.length > widget.maxRows)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Text(
                  _showAll ? 'Ver menos' : 'Ver los ${items.length} correos'),
            ),
          ),
      ],
    );
    final frame = widget.frame;
    if (frame != null) {
      return Padding(
        padding: widget.padding,
        child: frame(context, items.length, body),
      );
    }
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'CORREO  ${items.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.onTap});

  final MailItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final done = item.state.actionable && item.state.done;
    final status = MailWords.rowStatus(item);
    final who = item.direction == 'out'
        ? 'Para ${item.recipientTitle}'
        : item.senderTitle;
    return Semantics(
      button: true,
      label: '$who. ${item.subject}. '
          '${MailWords.longTime(item.receivedAt)}${status == null ? '' : '. $status'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: roles.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandMark(
                name: item.senderTitle,
                logoUrl: item.senderImageUrl,
                size: 28,
                solid: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item.direction == 'out') ...[
                          Icon(Icons.north_east,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          MailWords.shortTime(item.receivedAt, DateTime.now()),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.subject.isEmpty ? '(Sin asunto)' : item.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: scheme.onSurface),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (done) ...[
                            Icon(Icons.check_rounded,
                                size: 14, color: roles.success.accent),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            status,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: done
                                  ? roles.success.accent
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
