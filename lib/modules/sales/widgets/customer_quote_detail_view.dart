import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/shop_time.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/customer_quote.dart';
import '../services/customer_quote_service.dart';

/// Una cotización completa: lo que pidió el cliente, el borrador con lo que
/// falta confirmar con los proveedores, la oferta enviada y la historia.
///
/// La misma vista vive en la bandeja (panel derecho en escritorio) y en su
/// ruta propia (teléfono y avisos). Cada comando devuelve la cotización
/// completa desde la base, así que la vista siempre muestra lo guardado.
class CustomerQuoteDetailView extends StatefulWidget {
  const CustomerQuoteDetailView({
    super.key,
    required this.quoteId,
    this.onClose,
    this.onChanged,
    this.service,
  });

  final String quoteId;

  /// Cerrar la vista (ruta propia). En el panel de la bandeja es null.
  final VoidCallback? onClose;

  /// Avisa a la bandeja que la cotización cambió de estado.
  final VoidCallback? onChanged;
  final CustomerQuoteService? service;

  @override
  State<CustomerQuoteDetailView> createState() =>
      _CustomerQuoteDetailViewState();
}

class _CustomerQuoteDetailViewState extends State<CustomerQuoteDetailView> {
  late final CustomerQuoteService _service =
      widget.service ?? CustomerQuoteService();
  CustomerQuoteDetail? _quote;
  Object? _loadError;
  bool _busy = false;
  String? _sendKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomerQuoteDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quoteId != widget.quoteId) {
      _quote = null;
      _sendKey = null;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final quote = await _service.fetchDetail(widget.quoteId);
      if (!mounted) return;
      setState(() => _quote = quote);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _run(Future<CustomerQuoteDetail> Function() command,
      {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final quote = await command();
      if (!mounted) return;
      setState(() => _quote = quote);
      widget.onChanged?.call();
      if (done != null) _snack(done);
    } catch (error) {
      if (!mounted) return;
      _snack(CustomerQuoteService.describeError(error));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editLine(CustomerQuoteOfferLine line) async {
    final confirmation = await showQuoteLineEditor(context, line);
    if (confirmation == null) return;
    await _run(() => _service.confirmLine(line.id, confirmation));
  }

  Future<void> _sendOffer(CustomerQuoteDetail quote) async {
    // Por correo sale sola; por WhatsApp la manda el equipo con un clic.
    final how = switch ((quote.notifiesByEmail, quote.notifiesByWhatsapp)) {
      (true, true) => 'Le llega por correo y, por WhatsApp, la mandas tú con '
          '«Abrir WhatsApp».',
      (false, true) => 'Por WhatsApp la mandas tú con «Abrir WhatsApp».',
      _ => 'Le llega por correo.',
    };
    final notes = await _askText(
      title: 'Enviar oferta a ${quote.customerName}',
      body: 'Vale ${quote.offerValidityHours} horas. $how Lleva su enlace para '
          'aceptar, pedir cambios o rechazar.',
      label: 'Nota para el cliente (opcional)',
      confirm: 'Enviar oferta',
      optional: true,
    );
    if (notes == null) return;
    // Una llave por intento: un reintento tras un corte no envía dos veces.
    _sendKey ??= CustomerQuoteService.newOperationKey();
    final key = _sendKey!;
    await _run(
      () => _service.sendOffer(quote.id,
          operationKey: key, notesToCustomer: notes),
      done: 'Oferta enviada',
    );
    _sendKey = null;
  }

  Future<void> _revise(CustomerQuoteDetail quote) async {
    await _run(
      () => _service.reviseOffer(
        quote.id,
        operationKey: CustomerQuoteService.newOperationKey(),
      ),
      done: 'Oferta reabierta como borrador',
    );
  }

  Future<void> _cancel(CustomerQuoteDetail quote) async {
    final reason = await _askText(
      title: 'Anular ${quote.number}',
      body: 'El cliente ya no podrá responderla. La historia queda guardada.',
      label: 'Motivo',
      confirm: 'Anular cotización',
      destructive: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => _service.cancel(
        quote.id,
        operationKey: CustomerQuoteService.newOperationKey(),
        reason: reason.trim(),
      ),
      done: 'Cotización anulada',
    );
  }

  Future<void> _copyLink(CustomerQuoteDetail quote) async {
    try {
      final url = await _service.issueLink(quote.id);
      await Clipboard.setData(ClipboardData(text: url));
      _snack('Enlace del cliente copiado');
    } catch (error) {
      _snack(CustomerQuoteService.describeError(error));
    }
  }

  /// Abre WhatsApp con el mensaje y un enlace nuevo; queda «Por enviar»
  /// hasta que el equipo lo marca.
  Future<void> _openWhatsApp(
    CustomerQuoteDetail quote,
    CustomerQuoteMessage message,
  ) async {
    final digits = message.recipient.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    try {
      final url = await _service.issueLink(quote.id);
      final first = quote.customerName.trim().split(RegExp(r'\s+')).first;
      final text = message.kind == 'reminder'
          ? 'Hola $first, la oferta de tu cotización ${quote.number} vence pronto. '
              'La puedes ver y responder aquí: $url'
          : 'Hola $first, tu cotización ${quote.number} está lista. '
              'La puedes ver y responder aquí: $url';
      await launchUrl(
        Uri.https('wa.me', '/$digits', {'text': text}),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      _snack(CustomerQuoteService.describeError(error));
    }
  }

  Future<String?> _askText({
    required String title,
    required String body,
    required String label,
    required String confirm,
    bool optional = false,
    bool destructive = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _AskTextDialog(
        title: title,
        body: body,
        label: label,
        confirm: confirm,
        optional: optional,
        destructive: destructive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    if (quote == null) {
      if (_loadError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: VbNotice(
              title: 'No se pudo abrir la cotización',
              body: CustomerQuoteService.describeError(_loadError!),
              tone: VbNoticeTone.danger,
              action: VbButton(
                label: 'Reintentar',
                variant: VbButtonVariant.secondary,
                onPressed: _load,
              ),
            ),
          ),
        );
      }
      return const Center(child: BrandedLoading());
    }

    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      final gutter = compact ? 16.0 : 28.0;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, compact ? 12 : 20, gutter, 40),
          children: [
            _Header(
              quote: quote,
              compact: compact,
              busy: _busy,
              onClose: widget.onClose,
              onCopyLink: quote.status == CustomerQuoteStatus.cancelled
                  ? null
                  : () => _copyLink(quote),
              onCancel: quote.status.isOpen ? () => _cancel(quote) : null,
              onRevise: quote.status == CustomerQuoteStatus.offered ||
                      quote.status == CustomerQuoteStatus.expired
                  ? () => _revise(quote)
                  : null,
            ),
            const SizedBox(height: 18),
            _CustomerStrip(quote: quote),
            const SizedBox(height: 22),
            ..._statusSections(quote, compact),
            const SizedBox(height: 28),
            _History(events: quote.events),
          ],
        ),
      );
    });
  }

  List<Widget> _statusSections(CustomerQuoteDetail quote, bool compact) {
    final draft = quote.draft;
    final current = quote.currentOffer;
    final sections = <Widget>[];

    if (quote.status == CustomerQuoteStatus.accepted && current != null) {
      sections.add(VbNotice(
        title: 'Aceptada el ${_when(current.respondedAt)}',
        body: current.lines.any(
                (line) => line.availability == QuoteLineAvailability.onOrder)
            ? 'Lleva productos a pedido: se cobra el ${quote.onOrderPrepayPercent} % '
                'antes de pedirlos al proveedor.'
            : 'Todo está en stock: se puede preparar el pedido.',
        tone: VbNoticeTone.success,
      ));
      sections.add(const SizedBox(height: 16));
    }
    if (quote.status == CustomerQuoteStatus.rejected ||
        quote.status == CustomerQuoteStatus.cancelled) {
      final reason = quote.closedReason;
      sections.add(VbNotice(
        title: quote.status == CustomerQuoteStatus.rejected
            ? 'El cliente la rechazó'
            : 'Anulada',
        body: reason,
        tone: VbNoticeTone.neutral,
      ));
      sections.add(const SizedBox(height: 16));
    }

    if (draft != null) {
      sections.add(_OfferSection(
        offer: draft,
        title: 'Borrador · oferta ${draft.number}',
        compact: compact,
        onEditLine: _busy ? null : _editLine,
        footer: _DraftFooter(
          offer: draft,
          busy: _busy,
          onSend: () => _sendOffer(quote),
        ),
      ));
      final openTasks = quote.openTasks;
      if (openTasks.isNotEmpty) {
        sections.add(const SizedBox(height: 22));
        sections.add(_SupplierTasks(tasks: openTasks, onCopied: _snack));
      }
    } else if (current != null) {
      sections.add(_OfferSection(
        offer: current,
        title:
            'Oferta ${current.number} · ${current.statusLabel.toLowerCase()}',
        compact: compact,
        footer: _SentFooter(offer: current),
      ));
    }

    if (quote.messages.isNotEmpty) {
      sections.add(const SizedBox(height: 22));
      sections.add(_Messages(
        messages: quote.messages,
        busy: _busy,
        onOpenWhatsApp: (message) => _openWhatsApp(quote, message),
        onMarkSent: (message) => _run(
          () => _service.markMessageSent(message.id),
          done: 'Marcado como enviado',
        ),
      ));
    }
    sections.add(const SizedBox(height: 22));
    sections.add(_RequestedLines(lines: quote.requested));
    return sections;
  }
}

/// Pide un texto antes de un comando (nota al cliente, motivo de anular).
/// El diálogo es dueño de su controlador: lo suelta cuando su campo ya no
/// existe, no cuando el diálogo empieza a cerrarse (soltarlo al cerrar
/// tumbó la app al enviar una oferta, 2026-11-02).
class _AskTextDialog extends StatefulWidget {
  const _AskTextDialog({
    required this.title,
    required this.body,
    required this.label,
    required this.confirm,
    required this.optional,
    required this.destructive,
  });

  final String title;
  final String body;
  final String label;
  final String confirm;
  final bool optional;
  final bool destructive;

  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = widget.optional || _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.body),
            const SizedBox(height: 16),
            // La llave deja escribir con `app_control.sh enter-text --key`;
            // `type` pierde los espacios.
            TextField(
              key: const ValueKey('customer-quote-dialog-text'),
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: widget.label),
            ),
          ],
        ),
      ),
      actions: [
        VbButton(
          label: 'Volver',
          variant: VbButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        VbButton(
          label: widget.confirm,
          variant: widget.destructive
              ? VbButtonVariant.destructive
              : VbButtonVariant.primary,
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
        ),
      ],
    );
  }
}

String _when(DateTime? value) {
  if (value == null) return '—';
  return DateFormat("d MMM, HH:mm", 'es').format(shopTime(value));
}

String _relative(DateTime value) {
  final diff = DateTime.now().toUtc().difference(value.toUtc());
  if (diff.isNegative) {
    final ahead = diff.abs();
    if (ahead.inMinutes < 60) return 'en ${ahead.inMinutes} min';
    if (ahead.inHours < 48) return 'en ${ahead.inHours} h';
    return 'en ${ahead.inDays} días';
  }
  if (diff.inMinutes < 1) return 'recién';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 48) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} días';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.quote,
    required this.compact,
    required this.busy,
    this.onClose,
    this.onCopyLink,
    this.onCancel,
    this.onRevise,
  });

  final CustomerQuoteDetail quote;
  final bool compact;
  final bool busy;
  final VoidCallback? onClose;
  final VoidCallback? onCopyLink;
  final VoidCallback? onCancel;
  final VoidCallback? onRevise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final title = Row(
      children: [
        // On a phone the compact shell header already carries «volver».
        if (onClose != null && !compact) ...[
          IconButton(
            tooltip: 'Volver',
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            quote.number,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        VbStatusBadge(label: quote.status.label, tone: quote.status.tone),
      ],
    );
    final meta = Text(
      '${quote.sourceLabel} · ${_when(quote.requestedAt)}'
      '${quote.expiresAt != null && quote.status == CustomerQuoteStatus.offered ? ' · vence ${_relative(quote.expiresAt!)}' : ''}',
      style: theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onCopyLink != null)
          VbButton(
            label: 'Copiar enlace del cliente',
            icon: Icons.link,
            variant: VbButtonVariant.text,
            onPressed: onCopyLink,
          ),
        if (onRevise != null)
          VbButton(
            label: 'Corregir oferta',
            icon: Icons.edit_note_outlined,
            variant: VbButtonVariant.secondary,
            busy: busy,
            onPressed: onRevise,
          ),
        if (onCancel != null)
          VbButton(
            label: 'Anular',
            variant: VbButtonVariant.text,
            onPressed: busy ? null : onCancel,
          ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 4),
          meta,
          const SizedBox(height: 10),
          actions
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 4), meta],
          ),
        ),
        actions,
      ],
    );
  }
}

class _CustomerStrip extends StatelessWidget {
  const _CustomerStrip({required this.quote});

  final CustomerQuoteDetail quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final contact = [quote.customerEmail, quote.customerPhone]
        .whereType<String>()
        .join(' · ');
    final notices = quote.notices;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: roles.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                quote.customerName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (notices.isNotEmpty)
                VbStatusBadge(
                  label: 'Avisos por ${QuoteChannel.inSentence(notices)}',
                  tone: VbStatusTone.neutral,
                  icon: notices.length > 1
                      ? Icons.notifications_none_outlined
                      : notices.single == QuoteChannel.whatsapp
                          ? Icons.chat_outlined
                          : Icons.mail_outline,
                ),
            ],
          ),
          if (contact.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(contact, style: theme.textTheme.bodyMedium),
          ],
          if (quote.fromAccount) ...[
            const SizedBox(height: 4),
            Text(
              'Datos de su cuenta en la tienda: si los cambia, la cotización '
              'los toma.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: roles.faintForeground),
            ),
          ],
          if (quote.customerNotes != null) ...[
            const SizedBox(height: 10),
            Text(
              '«${quote.customerNotes}»',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: roles.faintForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _OfferSection extends StatelessWidget {
  const _OfferSection({
    required this.offer,
    required this.title,
    required this.compact,
    required this.footer,
    this.onEditLine,
  });

  final CustomerQuoteOffer offer;
  final String title;
  final bool compact;
  final Widget footer;
  final ValueChanged<CustomerQuoteOfferLine>? onEditLine;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: roles.hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < offer.lines.length; i++) ...[
                if (i > 0) Divider(height: 1, color: roles.hairline),
                _OfferLineRow(
                  line: offer.lines[i],
                  compact: compact,
                  onEdit: offer.isDraft && onEditLine != null
                      ? () => onEditLine!(offer.lines[i])
                      : null,
                ),
              ],
              Divider(height: 1, color: roles.hairline),
              footer,
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferLineRow extends StatelessWidget {
  const _OfferLineRow({required this.line, required this.compact, this.onEdit});

  final CustomerQuoteOfferLine line;
  final bool compact;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);

    final facts = <String>[
      if (line.sku != null) line.sku!,
      'pidió ${line.quantityRequested}',
      if (line.availability == QuoteLineAvailability.inStock &&
          line.stockNow != null)
        'stock ${line.stockNow}',
      if (line.leadLabel != null &&
          line.availability == QuoteLineAvailability.onOrder)
        line.leadLabel!,
      if (line.supplierName != null) line.supplierName!,
      if (line.marginPercent != null) 'margen ${line.marginPercent!.round()} %',
      if (line.confirmedBySystem && !line.isPending) 'confirmada sola',
    ];

    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line.name,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(facts.join(' · '), style: faint),
        if (line.customerNote != null) ...[
          const SizedBox(height: 4),
          Text('Al cliente: ${line.customerNote}',
              style: faint?.copyWith(fontStyle: FontStyle.italic)),
        ],
        if (line.staffNote != null) ...[
          const SizedBox(height: 2),
          Text('Interna: ${line.staffNote}', style: faint),
        ],
      ],
    );

    final amount =
        line.isPending || line.availability == QuoteLineAvailability.unavailable
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    VbMoneyText.formatClp(line.lineTotal ?? 0),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '${line.quantityOffered} × ${VbMoneyText.formatClp(line.unitPrice ?? 0)}',
                    style: faint?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              );

    final badge = VbStatusBadge(
      label: line.isPartial
          ? '${line.availability.label} · ${line.quantityOffered} de ${line.quantityRequested}'
          : line.availability.label,
      tone: line.isPartial ? VbStatusTone.warning : line.availability.tone,
    );

    final action = onEdit == null
        ? null
        : VbButton(
            label: line.isPending ? 'Confirmar' : 'Cambiar',
            variant:
                line.isPending ? VbButtonVariant.primary : VbButtonVariant.text,
            density: VbDensity.compact,
            onPressed: onEdit,
          );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            name,
            const SizedBox(height: 8),
            Row(
              children: [
                badge,
                const Spacer(),
                if (amount != null) amount,
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: name),
          const SizedBox(width: 12),
          SizedBox(
              width: 190,
              child: Align(alignment: Alignment.centerLeft, child: badge)),
          SizedBox(width: 130, child: amount ?? const SizedBox.shrink()),
          SizedBox(
            width: 110,
            child: action == null
                ? const SizedBox.shrink()
                : Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      ),
    );
  }
}

class _DraftFooter extends StatelessWidget {
  const _DraftFooter(
      {required this.offer, required this.busy, required this.onSend});

  final CustomerQuoteOffer offer;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = offer.pendingLines;
    final reason = pending > 0
        ? 'Se habilita con todas las líneas confirmadas: ${pending == 1 ? 'queda 1' : 'quedan $pending'}.'
        : !offer.hasOfferedLine
            ? 'Ninguna línea tiene un producto disponible.'
            : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 16,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'Total con IVA  ', style: theme.textTheme.bodyMedium),
              TextSpan(
                text: VbMoneyText.formatClp(offer.draftTotal),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ]),
          ),
          VbButton(
            label: 'Enviar oferta',
            icon: Icons.send_outlined,
            busy: busy,
            disabledReason: reason,
            onPressed: reason == null && !busy ? onSend : null,
          ),
        ],
      ),
    );
  }
}

class _SentFooter extends StatelessWidget {
  const _SentFooter({required this.offer});

  final CustomerQuoteOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    Widget row(String label, num? value, {bool strong = false}) => Row(
          children: [
            Expanded(
                child: Text(label,
                    style: strong ? theme.textTheme.bodyMedium : faint)),
            Text(
              value == null ? '—' : VbMoneyText.formatClp(value),
              style: (strong
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Neto', offer.subtotal),
          const SizedBox(height: 4),
          row('IVA', offer.taxAmount),
          const SizedBox(height: 6),
          row('Total', offer.total, strong: true),
          const SizedBox(height: 8),
          Text(
            'Enviada ${_when(offer.sentAt)} · válida hasta ${_when(offer.validUntil)}',
            style: faint,
          ),
          if (offer.notesToCustomer != null) ...[
            const SizedBox(height: 6),
            Text('Nota: ${offer.notesToCustomer}',
                style: faint?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

class _SupplierTasks extends StatelessWidget {
  const _SupplierTasks({required this.tasks, required this.onCopied});

  final List<CustomerQuoteSupplierTask> tasks;
  final ValueChanged<String> onCopied;

  Future<void> _openWhatsApp(CustomerQuoteSupplierTask task) async {
    final digits = (task.salesRepPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.https('wa.me', '/$digits', {'text': task.messageDraft});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(tasks.length == 1
            ? 'Consultar al proveedor'
            : 'Consultar a ${tasks.length} proveedores'),
        for (final task in tasks) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: roles.warning.container.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: roles.warning.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.supplierName ?? 'Sin proveedor asignado',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      task.dueAt.isBefore(DateTime.now())
                          ? 'atrasada ${_relative(task.dueAt).replaceFirst('hace ', '')}'
                          : 'responder ${_relative(task.dueAt)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: roles.warning.onContainer),
                    ),
                  ],
                ),
                if (task.salesRepName != null ||
                    task.salesRepPhone != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [task.salesRepName, task.salesRepPhone]
                        .whereType<String>()
                        .join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: roles.faintForeground),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: roles.hairline),
                  ),
                  child: SelectableText(task.messageDraft,
                      style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    VbButton(
                      label: 'Copiar mensaje',
                      icon: Icons.copy_outlined,
                      variant: VbButtonVariant.secondary,
                      density: VbDensity.compact,
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: task.messageDraft));
                        onCopied('Mensaje copiado');
                      },
                    ),
                    if ((task.salesRepPhone ?? '').isNotEmpty)
                      VbButton(
                        label: 'Abrir WhatsApp',
                        icon: Icons.chat_outlined,
                        variant: VbButtonVariant.secondary,
                        density: VbDensity.compact,
                        onPressed: () => _openWhatsApp(task),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Messages extends StatelessWidget {
  const _Messages({
    required this.messages,
    required this.busy,
    required this.onOpenWhatsApp,
    required this.onMarkSent,
  });

  final List<CustomerQuoteMessage> messages;
  final bool busy;
  final ValueChanged<CustomerQuoteMessage> onOpenWhatsApp;
  final ValueChanged<CustomerQuoteMessage> onMarkSent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Mensajes al cliente'),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: Icon(
                    message.channel == QuoteChannel.whatsapp
                        ? Icons.chat_outlined
                        : Icons.mail_outline,
                    size: 18,
                    color: roles.faintForeground,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(message.kindLabel,
                              style: theme.textTheme.bodyMedium),
                          VbStatusBadge(
                            label: message.stateLabel,
                            tone: message.tone,
                            dense: true,
                          ),
                        ],
                      ),
                      Text(
                        '${message.recipient} · '
                        '${_when(message.sentAt ?? message.createdAt)}'
                        '${message.lastError != null && message.state == 'failed' ? ' · ${message.lastError}' : ''}'
                        '${message.state == 'skipped' ? ((message.lastError ?? '').startsWith('La oferta') ? ' · la oferta ya no está vigente' : ' · no se envió') : ''}',
                        style: faint,
                      ),
                      if (message.needsStaff) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            VbButton(
                              label: 'Abrir WhatsApp',
                              icon: Icons.chat_outlined,
                              density: VbDensity.compact,
                              onPressed:
                                  busy ? null : () => onOpenWhatsApp(message),
                            ),
                            VbButton(
                              label: 'Marcar enviado',
                              variant: VbButtonVariant.secondary,
                              density: VbDensity.compact,
                              onPressed:
                                  busy ? null : () => onMarkSent(message),
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
      ],
    );
  }
}

class _RequestedLines extends StatelessWidget {
  const _RequestedLines({required this.lines});

  final List<CustomerQuoteRequestedLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Lo que pidió el cliente'),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${line.quantity} ×',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.name, style: theme.textTheme.bodyMedium),
                      Text(
                        [
                          line.kindLabel,
                          if (line.unitPriceReference != null)
                            'publicado a ${VbMoneyText.formatClp(line.unitPriceReference!)}',
                        ].join(' · '),
                        style: faint,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.events});

  final List<CustomerQuoteEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    final visible = events.reversed.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Historia'),
        for (final event in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 12),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (event.actorKind) {
                        'customer' => roles.info.accent,
                        'staff' => theme.colorScheme.primary,
                        _ => roles.neutral.accent,
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.label, style: theme.textTheme.bodyMedium),
                      if (event.note != null)
                        Text('«${event.note}»',
                            style:
                                faint?.copyWith(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(_when(event.occurredAt), style: faint),
              ],
            ),
          ),
      ],
    );
  }
}

/// Confirma una línea del borrador: si hay, cuánto, a qué precio y en qué
/// plazo, o que no hay. En el teléfono sube como hoja; en escritorio, diálogo.
Future<QuoteLineConfirmation?> showQuoteLineEditor(
  BuildContext context,
  CustomerQuoteOfferLine line,
) {
  final compact = MediaQuery.sizeOf(context).width < 720;
  if (compact) {
    return showModalBottomSheet<QuoteLineConfirmation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _QuoteLineEditor(line: line),
      ),
    );
  }
  return showDialog<QuoteLineConfirmation>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _QuoteLineEditor(line: line),
      ),
    ),
  );
}

class _QuoteLineEditor extends StatefulWidget {
  const _QuoteLineEditor({required this.line});

  final CustomerQuoteOfferLine line;

  @override
  State<_QuoteLineEditor> createState() => _QuoteLineEditorState();
}

class _QuoteLineEditorState extends State<_QuoteLineEditor> {
  late QuoteLineAvailability _availability = widget.line.isPending
      ? (widget.line.supplierId != null
          ? QuoteLineAvailability.onOrder
          : QuoteLineAvailability.inStock)
      : widget.line.availability;
  late final _quantity = TextEditingController(
    text:
        '${widget.line.quantityOffered > 0 ? widget.line.quantityOffered : widget.line.quantityRequested}',
  );
  late final _price = TextEditingController(
    text: widget.line.unitPrice == null
        ? ''
        : '${widget.line.unitPrice!.round()}',
  );
  late final _leadMin =
      TextEditingController(text: '${widget.line.leadDaysMin ?? 3}');
  late final _leadMax =
      TextEditingController(text: '${widget.line.leadDaysMax ?? 5}');
  late final _cost = TextEditingController(
    text: widget.line.unitCostNet == null
        ? ''
        : '${widget.line.unitCostNet!.round()}',
  );
  late final _customerNote =
      TextEditingController(text: widget.line.customerNote ?? '');
  late final _staffNote =
      TextEditingController(text: widget.line.staffNote ?? '');

  @override
  void dispose() {
    for (final controller in [
      _quantity,
      _price,
      _leadMin,
      _leadMax,
      _cost,
      _customerNote,
      _staffNote
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), ''));

  String? get _problem {
    if (_availability == QuoteLineAvailability.unavailable ||
        _availability == QuoteLineAvailability.pending) {
      return null;
    }
    final quantity = _int(_quantity);
    if (quantity == null || quantity < 1 || quantity > 99) {
      return 'La cantidad va de 1 a 99.';
    }
    if (_price.text.trim().isNotEmpty && (_int(_price) ?? 0) <= 0) {
      return 'El precio tiene que ser mayor que cero.';
    }
    if (_availability == QuoteLineAvailability.onOrder) {
      final min = _int(_leadMin);
      final max = _int(_leadMax);
      if (min == null || max == null || max < min) {
        return 'El plazo va de menor a mayor.';
      }
    }
    return null;
  }

  void _save() {
    final onOrder = _availability == QuoteLineAvailability.onOrder;
    final offers = _availability == QuoteLineAvailability.inStock || onOrder;
    Navigator.of(context).pop(QuoteLineConfirmation(
      availability: _availability,
      quantityOffered: offers ? _int(_quantity) : null,
      unitPrice: offers && _price.text.trim().isNotEmpty ? _int(_price) : null,
      leadDaysMin: onOrder ? _int(_leadMin) : null,
      leadDaysMax: onOrder ? _int(_leadMax) : null,
      unitCostNet: offers && _cost.text.trim().isNotEmpty ? _int(_cost) : null,
      customerNote: _customerNote.text.trim(),
      staffNote: _staffNote.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final line = widget.line;
    final offers = _availability == QuoteLineAvailability.inStock ||
        _availability == QuoteLineAvailability.onOrder;
    final problem = _problem;
    InputDecoration field(String label, {String? suffix, String? helper}) =>
        InputDecoration(
            labelText: label, suffixText: suffix, helperText: helper);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(line.name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            [
              if (line.sku != null) line.sku!,
              'pidió ${line.quantityRequested}',
              if (line.stockNow != null) 'stock hoy ${line.stockNow}',
              if (line.supplierName != null) line.supplierName!,
            ].join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: roles.faintForeground),
          ),
          const SizedBox(height: 16),
          SegmentedButton<QuoteLineAvailability>(
            segments: const [
              ButtonSegment(
                  value: QuoteLineAvailability.inStock,
                  label: Text('En stock')),
              ButtonSegment(
                  value: QuoteLineAvailability.onOrder,
                  label: Text('A pedido')),
              ButtonSegment(
                  value: QuoteLineAvailability.unavailable,
                  label: Text('No hay')),
            ],
            selected: {
              _availability == QuoteLineAvailability.pending
                  ? QuoteLineAvailability.onOrder
                  : _availability,
            },
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _availability = value.first),
          ),
          const SizedBox(height: 16),
          if (offers) ...[
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: field('Cantidad'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: field('Precio unitario con IVA',
                        suffix: 'CLP',
                        helper: _price.text.isEmpty
                            ? 'Vacío usa el precio publicado'
                            : null),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_availability == QuoteLineAvailability.onOrder) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _leadMin,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: field('Llega desde', suffix: 'días háb.'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _leadMax,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: field('hasta', suffix: 'días háb.'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  field('Costo neto del proveedor (interno)', suffix: 'CLP'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _customerNote,
            maxLength: 300,
            decoration: field(
              'Nota para el cliente',
              helper: _availability == QuoteLineAvailability.unavailable
                  ? 'Por ejemplo: sin stock en Chile; ofrecemos otra medida.'
                  : null,
            ),
          ),
          TextField(
            controller: _staffNote,
            maxLength: 300,
            decoration: field('Nota interna'),
          ),
          if (problem != null) ...[
            const SizedBox(height: 4),
            Text(problem,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: roles.danger.accent)),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!line.isPending)
                VbButton(
                  label: 'Dejar por confirmar',
                  variant: VbButtonVariant.text,
                  onPressed: () => Navigator.of(context).pop(
                    const QuoteLineConfirmation(
                        availability: QuoteLineAvailability.pending),
                  ),
                ),
              VbButton(
                label: 'Volver',
                variant: VbButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
              VbButton(
                label: 'Confirmar línea',
                onPressed: problem == null ? _save : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
