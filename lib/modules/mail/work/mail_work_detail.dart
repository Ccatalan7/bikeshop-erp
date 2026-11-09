import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/services/ocr_file_handoff_service.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/file_download.dart';
import '../../../shared/widgets/record_peek.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../purchases/widgets/brand_mark.dart';
import '../providers/email_provider.dart';
import '../providers/mail_account_manager.dart';
import '../widgets/compose_email_dialog.dart';
import '../widgets/email_detail_view_unified.dart' show EmailBodyWebView;
import 'mail_navigation.dart';
import 'mail_reply_drafter.dart';
import 'mail_work_controller.dart';
import 'mail_work_models.dart';
import 'mail_work_words.dart';

/// El correo abierto, en dos mundos que no se mezclan (dueño, 2026-11-08:
/// «separe ambos mundos, pero que dé fácil acceso e intuitivo a ambas áreas»):
///
/// - **Lo que propone el ERP**: una superficie teñida con la marca VB, con el
///   registro con que calza, lo que se leyó del correo, por qué está aquí, la
///   acción y el seguimiento del caso.
/// - **El correo original**: una hoja aparte con el correo tal como llegó
///   (su HTML y sus adjuntos), igual que en la vista Normal.
///
/// En pantallas anchas se ven lado a lado; en las demás, un selector de dos
/// opciones bajo el asunto cambia de uno a otro. Si el ERP no ve nada que
/// hacer, el correo abre directo en el original.
class MailWorkDetail extends StatefulWidget {
  const MailWorkDetail({
    super.key,
    required this.item,
    required this.controller,
    this.compact = false,
  });

  final MailItem item;
  final MailWorkController controller;
  final bool compact;

  /// Ancho desde el que la propuesta y el original van lado a lado.
  static const double splitMinWidth = 1240;

  /// Ancho de la propuesta lado a lado: lo que piden sus filas de pago y de
  /// datos sin cortarse (463 px de contenido medidos en la prueba de
  /// transferencias), y el resto para el correo, que se diseña a 600.
  static const double splitProposalWidth = 540;

  @override
  State<MailWorkDetail> createState() => _MailWorkDetailState();

  /// Si el ERP tiene algo propio que mostrar para este correo.
  static bool hasProposal(MailItem item) {
    final why = MailWords.why(item);
    return item.primaryLink != null ||
        MailWords.facts(item).isNotEmpty ||
        (why.$1.isNotEmpty && !item.state.done && !item.fakeBank) ||
        item.state.actionable ||
        item.fakeBank ||
        MailWords.unverifiedPayment(item) ||
        item.caseEntries.isNotEmpty;
  }

  static String _whyTitle(MailItem item) =>
      item.state.action == 'remind' ? 'Qué sigue' : _kindWhyTitle(item);

  static String _kindWhyTitle(MailItem item) => switch (item.kind) {
        'freight_invoice' ||
        'service_invoice' ||
        'supplier_invoice' =>
          'Qué falta',
        'customer' => 'Qué dice',
        'shipment' || 'claim' => 'Qué sigue',
        _ => 'Por qué',
      };
}

class _MailWorkDetailState extends State<MailWorkDetail> {
  late bool _showOriginal = !MailWorkDetail.hasProposal(widget.item);
  late Future<({String? html, String? text})> _original =
      widget.controller.service.original(widget.item.id);

  @override
  void didUpdateWidget(covariant MailWorkDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _original = widget.controller.service.original(widget.item.id);
      _showOriginal = !MailWorkDetail.hasProposal(widget.item);
    }
  }

  void _setWorld(bool original) {
    if (_showOriginal == original) return;
    setState(() => _showOriginal = original);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final compact = widget.compact;
    final horizontal = compact ? 16.0 : 28.0;
    final scheme = Theme.of(context).colorScheme;
    final header = Padding(
      padding:
          EdgeInsets.fromLTRB(horizontal, compact ? 16 : 20, horizontal, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SenderRow(
              item: item, controller: widget.controller, compact: compact),
          const SizedBox(height: 12),
          SelectableText(
            item.subject.isEmpty ? '(Sin asunto)' : item.subject,
            style: TextStyle(
              fontSize: compact ? 19 : 20,
              height: 1.3,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final split =
            !compact && constraints.maxWidth >= MailWorkDetail.splitMinWidth;
        if (split) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: MailWorkDetail.splitProposalWidth,
                      child: _ErpPanel(
                        item: item,
                        controller: widget.controller,
                        compact: compact,
                        padding: EdgeInsets.fromLTRB(horizontal, 0, 8, 28),
                      ),
                    ),
                    Expanded(
                      child: _OriginalPane(
                        item: item,
                        controller: widget.controller,
                        original: _original,
                        padding: EdgeInsets.fromLTRB(8, 0, horizontal, 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // El selector toma su ancho natural; sólo se acorta si la
                  // pantalla no alcanza (un Spacer al lado lo partía a la mitad).
                  Flexible(
                    child: _WorldSwitch(
                      showOriginal: _showOriginal,
                      attachments: item.visibleAttachments.length,
                      compact: compact,
                      onChanged: _setWorld,
                    ),
                  ),
                  // En el teléfono el original ya ocupa la pantalla: abrirlo
                  // aparte no agrega nada.
                  if (_showOriginal && !compact) ...[
                    const SizedBox(width: 12),
                    _LinkButton(
                      label: 'Abrir aparte',
                      onPressed: () => unawaited(
                          _openOriginalAside(context, item, widget.controller)),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _showOriginal
                  ? _OriginalPane(
                      item: item,
                      controller: widget.controller,
                      original: _original,
                      showHeader: false,
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 0, horizontal, 16),
                    )
                  : _ErpPanel(
                      item: item,
                      controller: widget.controller,
                      compact: compact,
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 0, horizontal, 28),
                      onOpenOriginal: () => _setWorld(true),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// El selector de los dos mundos: la propuesta del ERP, con la marca VB, y el
/// correo original, con su cantidad de adjuntos. En el teléfono los nombres
/// van cortos —la marca y el sobre ya dicen de quién es cada uno— para que
/// ninguno se corte.
class _WorldSwitch extends StatelessWidget {
  const _WorldSwitch({
    required this.showOriginal,
    required this.attachments,
    required this.onChanged,
    this.compact = false,
  });

  final bool showOriginal;
  final int attachments;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: roles.neutral.container,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _WorldPill(
              selected: !showOriginal,
              leading: const ErpMark(size: 18),
              label: compact ? 'Propuesta' : 'Propuesta del ERP',
              erp: true,
              onTap: () => onChanged(false),
            ),
          ),
          Flexible(
            child: _WorldPill(
              selected: showOriginal,
              leading: const Icon(Icons.mail_outline_rounded, size: 17),
              label: compact ? 'Original' : 'Correo original',
              trailing: attachments > 0 ? attachments : null,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldPill extends StatelessWidget {
  const _WorldPill({
    required this.selected,
    required this.leading,
    required this.label,
    required this.onTap,
    this.trailing,
    this.erp = false,
  });

  final bool selected;
  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final int? trailing;

  /// La píldora del ERP, elegida, toma el tinte de su tarjeta; la del correo,
  /// el blanco de su hoja: el selector ya dice en qué mundo se está.
  final bool erp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final color = selected
        ? (erp ? roles.onSelectionContainer : scheme.onSurface)
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? (erp ? roles.selectionContainer : scheme.surface)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected
              ? BorderSide(
                  color: erp ? roles.accentBorder : scheme.outlineVariant)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme(
                    data: IconThemeData(color: color),
                    child:
                        Opacity(opacity: selected ? 1 : 0.75, child: leading),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.attach_file, size: 14, color: color),
                    Text(
                      '$trailing',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La marca del ERP: el ícono VB de la app sobre su lienzo blanco, el mismo
/// en claro y en oscuro, como un ícono de aplicación.
class ErpMark extends StatelessWidget {
  const ErpMark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        // Lienzo del ícono de la app: la V azul marino no se lee sobre el
        // fondo oscuro, así que la marca lleva siempre su propio blanco.
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: roles.accentBorder),
      ),
      child: Image.asset(
        'assets/images/app_icon_source.png',
        cacheWidth: 128,
        fit: BoxFit.contain,
        semanticLabel: 'Viñabike ERP',
      ),
    );
  }
}

/// La propuesta del ERP: todo lo que el ERP dedujo y ofrece hacer, en una
/// superficie teñida con su marca, separada del correo que lo originó.
class _ErpPanel extends StatelessWidget {
  const _ErpPanel({
    required this.item,
    required this.controller,
    required this.compact,
    required this.padding,
    this.onOpenOriginal,
  });

  final MailItem item;
  final MailWorkController controller;
  final bool compact;
  final EdgeInsets padding;

  /// Cuando el original no está a la vista (pantallas angostas): un acceso
  /// al pie para pasar a leerlo.
  final VoidCallback? onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final why = MailWords.why(item);
    final facts = MailWords.facts(item);
    final link = item.primaryLink;
    final others = item.links.where((l) => l != link).toList();
    final kind = MailWords.kindLabels[item.kind];
    final hasProposal = MailWorkDetail.hasProposal(item);

    final blocks = <Widget>[
      if (item.fakeBank)
        _WarningNote(
          text: MailWords.fakeBankText(item),
          note: MailWords.fakeBankNote,
          danger: true,
        )
      else if (MailWords.unverifiedPayment(item))
        const _WarningNote(text: MailWords.unverifiedPaymentText),
      if (link != null) _RecordBlock(link: link, others: others),
      if (facts.isNotEmpty) _FactsBlock(facts: facts, compact: compact),
      if (why.$1.isNotEmpty && !item.state.done && !item.fakeBank)
        _WhyBlock(
          title: MailWorkDetail._whyTitle(item),
          text: why.$1,
          note: why.$2,
        ),
      if (item.state.actionable)
        _ActionBlock(item: item, controller: controller, compact: compact),
      if (!item.state.actionable && item.direction == 'in')
        _QuietActions(item: item, controller: controller),
      if (item.caseEntries.isNotEmpty)
        _CaseBlock(item: item, controller: controller),
    ];

    return ListView(
      padding: padding,
      children: [
        Container(
          decoration: BoxDecoration(
            color: roles.selectionContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: roles.accentBorder),
          ),
          padding: EdgeInsets.fromLTRB(
              compact ? 16 : 20, 14, compact ? 16 : 20, compact ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quién habla y qué dice, en dos líneas: así cabe también en el
              // teléfono junto al tipo de correo, sin cortar ninguna.
              Row(
                children: [
                  const ErpMark(size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Viñabike ERP',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: roles.onSelectionContainer,
                          ),
                        ),
                        Text(
                          hasProposal ? 'Lo que propone' : 'Nada que hacer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (kind != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: roles.accentBorder),
                      ),
                      child: Text(
                        kind,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: roles.onSelectionContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child:
                    Divider(height: 1, thickness: 1, color: roles.accentBorder),
              ),
              if (blocks.isEmpty)
                Text(
                  'Es un aviso: el ERP no ve nada que registrar ni responder.',
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant),
                )
              else
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0) const SizedBox(height: 22),
                  blocks[i],
                ],
            ],
          ),
        ),
        if (onOpenOriginal != null) ...[
          const SizedBox(height: 14),
          _OriginalTeaser(item: item, onTap: onOpenOriginal!),
        ],
      ],
    );
  }
}

/// Al pie de la propuesta: el correo que la originó, a un toque.
class _OriginalTeaser extends StatelessWidget {
  const _OriginalTeaser({required this.item, required this.onTap});

  final MailItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = MailWords.readable(item.bodyText ?? item.snippet ?? '');
    final excerpt =
        text.length > 220 ? '${text.substring(0, 220).trimRight()}…' : text;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.mail_outline_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Correo original',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (excerpt.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

TextStyle _label(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

class _SenderRow extends StatelessWidget {
  const _SenderRow(
      {required this.item, required this.controller, required this.compact});

  final MailItem item;
  final MailWorkController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final address = item.direction == 'out'
        ? 'para ${item.to.join(', ')}'
        : item.fromAddress;
    return Row(
      children: [
        BrandMark(
          name: item.otherSideTitle,
          logoUrl: item.otherSideImageUrl,
          size: 40,
          solid: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.direction == 'out'
                    ? 'Para ${item.recipientTitle}'
                    : item.senderTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$address · ${MailWords.longTime(item.receivedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              // En la bandeja unida, a cuál casilla llegó.
              if (controller.mailbox == null &&
                  controller.counts.mailboxes.length > 1 &&
                  item.mailbox.isNotEmpty)
                Text(
                  item.direction == 'out'
                      ? 'Desde ${item.mailbox}'
                      : 'Llegó a ${item.mailbox}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: item.archived ? 'Volver a la bandeja' : 'Archivar',
          onPressed: controller.isBusy(item.id)
              ? null
              : () => unawaited(controller.mark(
                  item, item.archived ? 'unarchive' : 'archive')),
          icon: Icon(
            item.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            size: 20,
          ),
          color: scheme.onSurfaceVariant,
        ),
        _MoreMenu(item: item, controller: controller),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.item, required this.controller});

  final MailItem item;
  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Más',
      icon: Icon(Icons.more_horiz, size: 20, color: scheme.onSurfaceVariant),
      onSelected: (value) async {
        if (value == 'unread') {
          await controller.mark(item, 'unread');
        } else if (value == 'reply') {
          await _openReply(context, item);
        } else if (value.startsWith('kind:')) {
          await controller.setKind(item, value.substring(5));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              value == 'kind:promo' || value == 'kind:noise'
                  ? 'Listo. Los próximos correos de ${item.fromAddress} se archivan solos.'
                  : 'Listo: ahora es «${MailWords.kindLabels[value.substring(5)]}».',
            ),
          ));
        }
      },
      itemBuilder: (context) => [
        if (item.direction == 'in')
          const PopupMenuItem(value: 'reply', child: Text('Responder')),
        const PopupMenuItem(
            value: 'unread', child: Text('Marcar como no leído')),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text('Es otra cosa', style: _label(context)),
        ),
        for (final kind in const [
          'promo',
          'noise',
          'customer',
          'supplier_order',
          'supplier_invoice',
          'freight_invoice',
          'service_invoice',
          'transfer',
          'shipment',
          'other',
        ])
          if (kind != item.kind)
            PopupMenuItem(
              value: 'kind:$kind',
              child: Text(MailWords.kindLabels[kind] ?? kind),
            ),
      ],
    );
  }
}

class _RecordBlock extends StatelessWidget {
  const _RecordBlock({required this.link, required this.others});

  final MailLink link;
  final List<MailLink> others;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final route = MailWords.routeFor(link);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          link.certain ? MailWords.linkTitle(link).toUpperCase() : 'PUEDE SER',
          style: _label(context),
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 2,
          children: [
            Text(
              link.label ?? MailWords.linkTitle(link),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (route != null)
              _LinkButton(
                label: MailWords.openLabel(link),
                onPressed: () => MailNavigation.to(context, route),
              ),
          ],
        ),
        if ((link.detail ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            link.detail!,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final other in others)
                if (MailWords.routeFor(other) != null)
                  _LinkButton(
                    label: '${MailWords.linkTitle(other)}: ${other.label ?? ''}'
                        .trim(),
                    onPressed: () =>
                        MailNavigation.to(context, MailWords.routeFor(other)!),
                    muted: true,
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(
      {required this.label, required this.onPressed, this.muted = false});

  final String label;
  final VoidCallback onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = muted ? scheme.onSurfaceVariant : scheme.primary;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 15, color: color),
          ],
        ),
      ),
    );
  }
}

class _FactsBlock extends StatelessWidget {
  const _FactsBlock({required this.facts, required this.compact});

  final List<(String, String)> facts;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEL CORREO', style: _label(context)),
        const SizedBox(height: 8),
        for (final (label, value) in facts)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: compact ? 120 : 150,
                  child: Text(
                    label,
                    style:
                        TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Una advertencia antes de todo lo demás: un pago del que sólo hay un
/// comprobante, o un desconocido que dice ser un banco ([danger]).
class _WarningNote extends StatelessWidget {
  const _WarningNote({required this.text, this.note, this.danger = false});

  final String text;
  final String? note;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final tone = danger ? roles.danger : roles.warning;
    return Semantics(
      container: true,
      label: 'Atención. $text${note == null ? '' : ' $note'}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
                danger ? Icons.report_outlined : Icons.gpp_maybe_outlined,
                size: 20,
                color: tone.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: tone.onContainer,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhyBlock extends StatelessWidget {
  const _WhyBlock({required this.title, required this.text, this.note});

  final String title;
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: _label(context)),
        const SizedBox(height: 6),
        Text(
          text,
          style:
              TextStyle(fontSize: 14.5, height: 1.45, color: scheme.onSurface),
        ),
        if ((note ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            note!,
            style: TextStyle(
                fontSize: 13, height: 1.45, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// La acción del correo. Su estado viene del registro: si otra persona ya lo
/// hizo por otro lado, aquí se ve hecho, con quién y cuándo.
class _ActionBlock extends StatelessWidget {
  const _ActionBlock(
      {required this.item, required this.controller, required this.compact});

  final MailItem item;
  final MailWorkController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = item.state;
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final busy = controller.isBusy(item.id);
    final density = compact ? VbDensity.touch : VbDensity.comfortable;
    if (state.done) {
      final who = [
        if ((state.doneBy ?? '').isNotEmpty) state.doneBy!,
        if (state.doneAt != null) MailWords.longTime(state.doneAt!),
      ].join(' · ');
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.check_rounded,
                size: 20, color: roles.success.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.doneText ?? 'Hecho',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: roles.success.accent,
                  ),
                ),
                if (who.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(who,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (state.markedByPerson)
            VbButton(
              label: 'Deshacer',
              variant: VbButtonVariant.text,
              density: density,
              busy: busy,
              onPressed: () => unawaited(controller.mark(item, 'undone')),
            ),
        ],
      );
    }
    if (state.action == 'register_payment') {
      return _PaymentChoices(
          item: item, controller: controller, compact: compact);
    }
    if (state.action == 'remind') {
      return _ReminderBlock(
          item: item, controller: controller, compact: compact);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        VbButton(
          label: MailWords.actionLabel(item),
          density: density,
          busy: busy,
          expand: compact,
          onPressed: () => unawaited(runMailAction(context, item, controller)),
        ),
        if (state.action != 'review')
          VbButton(
            label: 'Hecho',
            variant: VbButtonVariant.text,
            density: density,
            busy: busy,
            onPressed: () => unawaited(controller.mark(item, 'done')),
          ),
      ],
    );
  }
}

/// Lo que espera respuesta: el recordatorio ya escrito, para revisarlo y
/// mandarlo como respuesta en el mismo hilo, y «Hecho» si se resolvió por
/// otro lado. Mientras no vence, mandarlo es opcional.
class _ReminderBlock extends StatelessWidget {
  const _ReminderBlock(
      {required this.item, required this.controller, required this.compact});

  final MailItem item;
  final MailWorkController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final busy = controller.isBusy(item.id);
    final density = compact ? VbDensity.touch : VbDensity.comfortable;
    final to = item.state.remindTo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (to != null) ...[
          Text('LISTO PARA MANDAR', style: _label(context)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 2, 0, 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: roles.neutral.border, width: 2),
              ),
            ),
            child: SelectableText(
              MailWords.reminderText(item),
              style:
                  TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Para $to',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
        ] else ...[
          Text(
            'Esa dirección no recibe respuestas: sigue el caso por su sitio o su teléfono.',
            style: TextStyle(
                fontSize: 13, height: 1.45, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (to != null)
              VbButton(
                label: MailWords.actionLabel(item),
                variant: item.state.overdue
                    ? VbButtonVariant.primary
                    : VbButtonVariant.secondary,
                density: density,
                busy: busy,
                expand: compact,
                onPressed: () =>
                    unawaited(runMailAction(context, item, controller)),
              ),
            VbButton(
              label: 'Hecho',
              variant: VbButtonVariant.text,
              density: density,
              busy: busy,
              onPressed: () => unawaited(controller.mark(item, 'done')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Una transferencia y los cobros a los que puede corresponder (etapa 3 de
/// Correo que trabaja). El servidor propone las facturas con saldo de quien
/// transfirió y sus pedidos web sin pagar; sin nombre en el aviso, sólo los de
/// saldo exacto. «Registrar aquí» abre el cobro de esa factura con el monto,
/// la transferencia y la fecha del aviso: el operador revisa y confirma. Al
/// volver, el estado se relee del registro.
class _PaymentChoices extends StatefulWidget {
  const _PaymentChoices({
    required this.item,
    required this.controller,
    required this.compact,
  });

  final MailItem item;
  final MailWorkController controller;
  final bool compact;

  @override
  State<_PaymentChoices> createState() => _PaymentChoicesState();
}

class _PaymentChoicesState extends State<_PaymentChoices> {
  List<MailPaymentCandidate>? _candidates;
  String? _opening;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_PaymentChoices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _candidates = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    List<MailPaymentCandidate> found;
    try {
      found = await widget.controller.service.paymentCandidates(widget.item.id);
    } catch (_) {
      found = const [];
    }
    if (mounted) setState(() => _candidates = found);
  }

  String _paymentRoute(MailPaymentCandidate candidate) {
    final item = widget.item;
    final date = item.receivedAt;
    String two(int value) => value.toString().padLeft(2, '0');
    final amount = item.amount;
    final payer = item.payer;
    final operation = MailWords.operationNumber(item.bodyText ?? item.snippet);
    return Uri(
      path: '/sales/invoices/${candidate.id}/payment',
      queryParameters: {
        if (amount != null) 'amount': amount.round().toString(),
        'method': 'transfer',
        if (operation != null) 'reference': operation,
        'date': '${date.year}-${two(date.month)}-${two(date.day)}',
        'note': 'Transferencia${payer == null ? '' : ' de $payer'} · '
            'aviso de ${item.senderTitle}',
      },
    ).toString();
  }

  Future<void> _open(MailPaymentCandidate candidate) async {
    setState(() => _opening = candidate.id);
    try {
      await MailNavigation.to(
        context,
        candidate.isOrder
            ? '/website/orders?order=${candidate.id}'
            : _paymentRoute(candidate),
      );
    } finally {
      if (mounted) setState(() => _opening = null);
    }
    await widget.controller.reloadAfterAction(widget.item.id);
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final item = widget.item;
    final controller = widget.controller;
    final density = widget.compact ? VbDensity.touch : VbDensity.comfortable;
    final busy = controller.isBusy(item.id);
    final candidates = _candidates;
    final muted = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    final done = VbButton(
      label: 'Hecho',
      variant: VbButtonVariant.text,
      density: density,
      busy: busy,
      onPressed: () => unawaited(controller.mark(item, 'done')),
    );
    if (candidates == null) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text('Buscando a qué cobro corresponde…', style: muted),
          ),
        ],
      );
    }
    if (candidates.isEmpty) {
      final payer = item.payer;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            payer == null
                ? 'No hay un cobro pendiente por ese monto.'
                : 'No hay un cobro pendiente de $payer.',
            style: muted,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VbButton(
                label: 'Buscar el cobro',
                density: density,
                busy: busy,
                expand: widget.compact,
                onPressed: () =>
                    unawaited(runMailAction(context, item, controller)),
              ),
              done,
            ],
          ),
        ],
      );
    }
    final named = candidates.any((candidate) => candidate.named);
    final amount = item.amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          named
              ? '¿A qué cobro de ${candidates.first.who} corresponde?'
              : 'Cobros pendientes por el mismo monto: elige a cuál corresponde.',
          style: muted,
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < candidates.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${candidates[index].isOrder ? 'Pedido' : 'Factura'} '
                        '${candidates[index].label}',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (!named) candidates[index].who,
                          if (candidates[index].isOrder)
                            MailWords.money(candidates[index].balance)
                          else if (candidates[index].exact || amount == null)
                            'saldo ${MailWords.money(candidates[index].balance)}'
                          else
                            'saldo ${MailWords.money(candidates[index].balance)}'
                                ' · abona ${MailWords.money(amount)}',
                          if (candidates[index].at != null)
                            MailWords.shortTime(
                                candidates[index].at!, DateTime.now()),
                        ].where((part) => part.isNotEmpty).join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                VbButton(
                  label: candidates[index].isOrder
                      ? 'Abrir pedido'
                      : 'Registrar aquí',
                  variant: index == 0
                      ? VbButtonVariant.primary
                      : VbButtonVariant.text,
                  density: density,
                  busy: _opening == candidates[index].id,
                  onPressed: _opening != null
                      ? null
                      : () => unawaited(_open(candidates[index])),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: roles.hairline)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              done,
              VbButton(
                label: 'Otro cobro',
                variant: VbButtonVariant.text,
                density: density,
                onPressed: () =>
                    unawaited(runMailAction(context, item, controller)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Un correo sin acción (un aviso de envío, un pedido a proveedor): sólo
/// hecho o archivar, sin botones de más.
class _QuietActions extends StatelessWidget {
  const _QuietActions({required this.item, required this.controller});

  final MailItem item;
  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    if (item.archived) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: VbButton(
        label: 'Responder',
        variant: VbButtonVariant.text,
        icon: Icons.reply_outlined,
        onPressed: () => unawaited(_openReply(context, item)),
      ),
    );
  }
}

class _AttachmentsBlock extends StatefulWidget {
  const _AttachmentsBlock({required this.item, required this.controller});

  final MailItem item;
  final MailWorkController controller;

  @override
  State<_AttachmentsBlock> createState() => _AttachmentsBlockState();
}

class _AttachmentsBlockState extends State<_AttachmentsBlock> {
  String? _opening;

  Future<void> _download(MailAttachmentRef ref) async {
    setState(() => _opening = ref.ref);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data =
          await widget.controller.service.attachment(widget.item.id, ref);
      final result = await downloadFile(
        bytes: data.bytes,
        fileName: data.filename,
        mimeType: data.mimeType,
      );
      if (!mounted || result.cancelled) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          result.path == null
              ? 'Descargado: ${data.filename}'
              : 'Guardado en ${result.path}',
        ),
      ));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo traer el adjunto.')));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ADJUNTOS', style: _label(context)),
        const SizedBox(height: 8),
        for (final ref in widget.item.visibleAttachments)
          InkWell(
            onTap: _opening == null ? () => unawaited(_download(ref)) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: roles.hairline)),
              ),
              child: Row(
                children: [
                  Icon(_iconFor(ref), size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ref.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    ),
                  ),
                  Text(
                    MailWords.fileSize(ref.size),
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  if (_opening == ref.ref)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.download_outlined,
                        size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(MailAttachmentRef ref) {
    final name = ref.filename.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.xml')) return Icons.description_outlined;
    if (ref.mimeType.startsWith('image/')) return Icons.image_outlined;
    if (name.endsWith('.xls') ||
        name.endsWith('.xlsx') ||
        name.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    return Icons.attach_file;
  }
}

class _CaseBlock extends StatelessWidget {
  const _CaseBlock({required this.item, required this.controller});

  final MailItem item;
  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('EL MISMO CASO', style: _label(context)),
        const SizedBox(height: 8),
        for (final entry in item.caseEntries)
          InkWell(
            onTap: () => unawaited(controller.select(entry.id)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: roles.hairline)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      MailWords.shortTime(entry.receivedAt, now),
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// El correo tal como llegó: su HTML en una hoja aparte, con sus adjuntos
/// arriba y la opción de abrirlo en un panel más ancho.
class _OriginalPane extends StatelessWidget {
  const _OriginalPane({
    required this.item,
    required this.controller,
    required this.original,
    required this.padding,
    this.showHeader = true,
  });

  final MailItem item;
  final MailWorkController controller;
  final Future<({String? html, String? text})> original;
  final EdgeInsets padding;

  /// Lado a lado lleva su rótulo; con el selector, el selector ya lo dice.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Row(
              children: [
                Icon(Icons.mail_outline_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('CORREO ORIGINAL', style: _label(context)),
                const Spacer(),
                _LinkButton(
                  label: 'Abrir aparte',
                  onPressed: () =>
                      unawaited(_openOriginalAside(context, item, controller)),
                ),
              ],
            ),
          if (item.visibleAttachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AttachmentsBlock(item: item, controller: controller),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: _OriginalBody(item: item, original: original),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalBody extends StatelessWidget {
  const _OriginalBody({required this.item, required this.original});

  final MailItem item;
  final Future<({String? html, String? text})> original;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<({String? html, String? text})>(
      future: original,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final body = snapshot.data;
        final html = body?.html;
        final fallback =
            MailWords.readable(item.bodyText ?? item.snippet ?? '');
        if (snapshot.hasError ||
            body == null ||
            ((html ?? '').isEmpty && (body.text ?? '').isEmpty)) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (fallback.isNotEmpty)
                SelectableText(
                  fallback,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.5, color: scheme.onSurface),
                ),
              if (snapshot.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  'No se pudo traer el original completo; esto es lo que '
                  'quedó guardado. Puede que la casilla necesite volver a '
                  'conectarse.',
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          );
        }
        return EmailBodyWebView(
          key: ValueKey('original-${item.id}'),
          email: _originalEmail(
            item,
            (html ?? '').isNotEmpty
                ? html!
                : '<pre style="white-space:pre-wrap;font-family:inherit">'
                    '${_escapeHtml(body.text ?? '')}</pre>',
          ),
          onNavigateSelection: null,
        );
      },
    );
  }
}

Email _originalEmail(MailItem item, String content) => Email(
      id: item.providerMessageId,
      providerId: item.provider,
      folderId: '',
      subject: item.subject,
      fromAddress: item.fromName == null
          ? item.fromAddress
          : '${item.fromName} <${item.fromAddress}>',
      toAddress: item.to.join(', '),
      receivedTime: item.receivedAt,
      isRead: true,
      hasAttachment: item.hasAttachments,
      content: content,
    );

String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

Future<void> _openOriginalAside(
  BuildContext context,
  MailItem item,
  MailWorkController controller,
) {
  return showRecordPeek(
    context,
    panelWidth: 720,
    builder: (context, close) =>
        _OriginalPeek(item: item, controller: controller, close: close),
  );
}

class _OriginalPeek extends StatefulWidget {
  const _OriginalPeek(
      {required this.item, required this.controller, required this.close});

  final MailItem item;
  final MailWorkController controller;
  final VoidCallback close;

  @override
  State<_OriginalPeek> createState() => _OriginalPeekState();
}

class _OriginalPeekState extends State<_OriginalPeek> {
  late final Future<({String? html, String? text})> _future =
      widget.controller.service.original(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: roles.hairline))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.subject.isEmpty
                        ? 'Correo original'
                        : widget.item.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: widget.close,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<({String? html, String? text})>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2));
                }
                final body = snapshot.data;
                final html = body?.html;
                if (snapshot.hasError ||
                    body == null ||
                    ((html ?? '').isEmpty && (body.text ?? '').isEmpty)) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      snapshot.hasError
                          ? 'No se pudo traer el original. Puede que la conexión de esta casilla necesite volver a conectarse.'
                          : 'Este correo no tiene contenido.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return EmailBodyWebView(
                  email: Email(
                    id: widget.item.providerMessageId,
                    providerId: widget.item.provider,
                    folderId: '',
                    subject: widget.item.subject,
                    fromAddress: widget.item.fromName == null
                        ? widget.item.fromAddress
                        : '${widget.item.fromName} <${widget.item.fromAddress}>',
                    toAddress: widget.item.to.join(', '),
                    receivedTime: widget.item.receivedAt,
                    isRead: true,
                    hasAttachment: widget.item.hasAttachments,
                    content: (html ?? '').isNotEmpty
                        ? html
                        : '<pre style="white-space:pre-wrap;font-family:inherit">${_escape(body.text ?? '')}</pre>',
                  ),
                  onNavigateSelection: null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

// ---------------------------------------------------------------------------
// Acciones
// ---------------------------------------------------------------------------

/// Lo que hace el botón principal. Cada acción lleva a su lugar del ERP con
/// lo leído del correo; al volver, el estado se lee de nuevo del registro.
Future<void> runMailAction(
  BuildContext context,
  MailItem item,
  MailWorkController controller,
) async {
  switch (item.state.action) {
    case 'reply':
      // La respuesta llega escrita para revisarla; si la IA no responde, se
      // abre vacía.
      final draft = await controller.whileBusy(
          item.id, () => MailReplyDrafter().customerReply(item));
      if (!context.mounted) return;
      if (draft == null) {
        _say(context, 'La IA no respondió: escribe la respuesta tú.');
      }
      await _openReply(context, item, draft: draft);
    case 'reply_review':
      // Google no deja responder desde aquí: la respuesta queda copiada para
      // pegarla en la reseña.
      final reply = await controller.whileBusy(
          item.id, () => MailReplyDrafter().reviewReply(item));
      if (reply != null) {
        await Clipboard.setData(ClipboardData(text: reply));
        if (context.mounted) {
          _say(context,
              'Respuesta copiada: pégala en la reseña y revísala antes de publicar.');
        }
      } else if (context.mounted) {
        _say(context, 'La IA no respondió: Google se abre para responder.');
      }
      await launchUrl(
        Uri.parse('https://business.google.com/reviews'),
        mode: LaunchMode.externalApplication,
      );
    case 'review':
      await controller.mark(item, 'done');
    case 'register_purchase':
      // La factura adjunta va al lector de Compras (el mismo OCR del panel de
      // archivos); la compra queda en borrador para revisarla y guardarla.
      final handed = await _handOffInvoice(
        context,
        item,
        controller,
        OcrFileHandoffTarget.purchaseInvoice,
      );
      if (!context.mounted) return;
      if (handed) {
        MailNavigation.replace(context, '/purchases/new');
      } else {
        _say(context,
            'El correo no trae la factura adjunta: se abre una compra vacía.');
        await MailNavigation.to(context, '/purchases/new');
      }
    case 'register_expense':
      final handed = await _handOffInvoice(
        context,
        item,
        controller,
        OcrFileHandoffTarget.quickExpense,
      );
      if (!context.mounted) return;
      if (handed) {
        context.read<RightToolbarService>().openTool(ToolbarTool.expenses);
        _say(context, 'Factura enviada a Gastos rápidos.');
      } else {
        await MailNavigation.to(context, '/accounting/expenses/new');
      }
    case 'import_statement':
      // La cartola en PDF o imagen pasa directo a Conciliación, que la lee
      // apenas hay una cuenta elegida; en otro formato (Excel, CSV) se
      // descarga, porque Conciliación todavía no los lee.
      final file = _bestAttachment(item, allowStructured: true);
      if (file != null) {
        final name = file.filename.toLowerCase();
        final readable = file.mimeType == 'application/pdf' ||
            file.mimeType.startsWith('image/') ||
            name.endsWith('.pdf');
        try {
          final data = await controller.service.attachment(item.id, file);
          if (!context.mounted) return;
          if (readable) {
            final dot = data.filename.lastIndexOf('.');
            context.read<OcrFileHandoffService>().queue(
                  target: OcrFileHandoffTarget.bankStatement,
                  fileName: data.filename,
                  mimeType: data.mimeType,
                  bytes: data.bytes,
                  extension: dot < 0 ? '' : data.filename.substring(dot + 1),
                  sourceLabel: 'Correo de ${item.senderTitle}',
                );
          } else {
            await downloadFile(
              bytes: data.bytes,
              fileName: data.filename,
              mimeType: data.mimeType,
            );
            if (context.mounted) {
              _say(context,
                  'Cartola descargada: Conciliación lee PDF o imagen.');
            }
          }
        } catch (_) {
          if (context.mounted) _say(context, 'No se pudo traer la cartola.');
        }
      }
      if (!context.mounted) return;
      await MailNavigation.to(context, '/accounting/bank-reconciliation');
    case 'register_payment':
      final job = item.links.where((l) => l.type == 'job').firstOrNull;
      final order =
          item.links.where((l) => l.type == 'online_order').firstOrNull;
      await MailNavigation.to(
        context,
        job != null
            ? '/taller/pegas/${job.id}'
            : order != null
                ? '/website/orders?order=${order.id}'
                : '/sales/payments',
      );
    case 'follow_up':
      final first = item.caseEntries.firstOrNull;
      if (first != null) await controller.select(first.id);
    case 'remind':
      final to = item.state.remindTo;
      if (to == null) return;
      await _openReply(context, item,
          draft: MailWords.reminderText(item), to: to);
    default:
      await controller.mark(item, 'done');
  }
  await controller.reloadAfterAction(item.id);
}

/// El adjunto que trae el documento: el PDF primero (lo lee el OCR), una
/// imagen después y, si se acepta, el XML o el HTML.
MailAttachmentRef? _bestAttachment(MailItem item,
    {bool allowStructured = false}) {
  final files = item.visibleAttachments;
  bool isPdf(MailAttachmentRef a) =>
      a.mimeType == 'application/pdf' ||
      a.filename.toLowerCase().endsWith('.pdf');
  bool isImage(MailAttachmentRef a) => a.mimeType.startsWith('image/');
  bool isStructured(MailAttachmentRef a) {
    final name = a.filename.toLowerCase();
    return name.endsWith('.xml') ||
        name.endsWith('.json') ||
        name.endsWith('.html') ||
        name.endsWith('.htm') ||
        name.endsWith('.xls') ||
        name.endsWith('.xlsx') ||
        name.endsWith('.csv');
  }

  return files.where(isPdf).firstOrNull ??
      files.where(isImage).firstOrNull ??
      (allowStructured ? files.where(isStructured).firstOrNull : null);
}

/// Pasa la factura del correo al lector de documentos de Compras o de Gastos
/// rápidos. Devuelve false si el correo no trae un archivo que se pueda leer.
Future<bool> _handOffInvoice(
  BuildContext context,
  MailItem item,
  MailWorkController controller,
  OcrFileHandoffTarget target,
) async {
  final ref = _bestAttachment(
    item,
    allowStructured: target == OcrFileHandoffTarget.purchaseInvoice,
  );
  if (ref == null) return false;
  final handoff = context.read<OcrFileHandoffService>();
  _say(context, 'Preparando ${ref.filename}…');
  try {
    final data = await controller.service.attachment(item.id, ref);
    final name = data.filename;
    final extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final supplier = item.links.where((l) => l.type == 'supplier').firstOrNull;
    handoff.queue(
      target: target,
      fileName: name,
      mimeType: data.mimeType,
      bytes: data.bytes,
      extension: extension,
      sourceLabel: 'Correo de ${item.senderTitle}',
      sourceSupplierId: supplier?.id,
      sourceSupplierName: supplier?.label,
    );
    return true;
  } catch (_) {
    if (context.mounted) {
      _say(context, 'No se pudo traer el adjunto del correo.');
    }
    return false;
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _openReply(BuildContext context, MailItem item,
    {String? draft, String? to}) async {
  final manager = MailAccountManager.instance;
  await manager.initialize();
  if (!context.mounted) return;
  final subject = item.subject.toLowerCase().startsWith('re:')
      ? item.subject
      : 'Re: ${item.subject}';
  await showDialog<void>(
    context: context,
    builder: (context) => ComposeEmailDialog(
      manager: manager,
      initialProviderId: item.provider,
      replyTo: to ?? item.fromAddress,
      replySubject: subject,
      quotedContent: item.bodyText ?? item.snippet,
      initialBody: draft,
      // La respuesta va en el mismo hilo del proveedor: así el correo que
      // trabaja ve que se respondió (cliente respondido, seguimiento al día).
      // Gmail busca el hilo y el Message-ID con el id; Zoho responde por id.
      replySource: Email(
        id: item.providerMessageId,
        providerId: item.provider,
        folderId: '',
        subject: item.subject,
        fromAddress: item.fromAddress,
        toAddress: item.to.join(', '),
        receivedTime: item.receivedAt,
        isRead: item.read,
        hasAttachment: item.hasAttachments,
      ),
    ),
  );
}

/// Redactar desde la casilla de la empresa que se elija en el diálogo.
Future<void> openMailCompose(BuildContext context) async {
  final manager = MailAccountManager.instance;
  await manager.initialize();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ComposeEmailDialog(manager: manager),
  );
}
