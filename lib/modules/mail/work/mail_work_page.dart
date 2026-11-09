import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../widgets/mail_chrome.dart';
import 'mail_mailbox_controls.dart';
import 'mail_mode.dart';
import 'mail_work_controller.dart';
import 'mail_work_detail.dart';
import 'mail_work_models.dart';
import 'mail_work_words.dart';

/// Correo: el de las casillas de la empresa, guardado una vez para todo el
/// equipo y ligado a sus registros. «Para hoy» es lo que pide algo; las
/// promociones y el ruido se archivan solos. Diseño aprobado por el dueño el
/// 2026-11-06 (lienzo «Correo que trabaja · modelos»): una superficie con
/// divisores, sin bloques de cifras ni tarjetas flotantes.
class MailWorkPage extends StatefulWidget {
  const MailWorkPage({
    super.key,
    this.initialProviderMessageId,
    this.initialMessageId,
  });

  /// Un aviso push abre su correo (id del proveedor).
  final String? initialProviderMessageId;

  /// «Abrir en Correo» desde la historia de un registro (`?mail=<id>`): abre
  /// ese correo aunque no esté en la vista de hoy.
  final String? initialMessageId;

  @override
  State<MailWorkPage> createState() => _MailWorkPageState();
}

class _MailWorkPageState extends State<MailWorkPage> {
  static const double _splitMinWidth = 860;

  final MailWorkController _controller = MailWorkController();
  final TextEditingController _search = TextEditingController();
  bool _openedInitial = false;
  bool _wide = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    unawaited(_controller.start());
  }

  void _onChange() {
    if (!mounted) return;
    _openInitialIfReady();
    if (_wide && _controller.selectedId == null && !_controller.loading) {
      // El primero que se ve en la lista (en «Para hoy» va por grupos, no
      // por fecha).
      final first = _MailList.firstShown(_controller);
      if (first != null) unawaited(_controller.select(first.id));
    }
    setState(() {});
  }

  void _openInitialIfReady() {
    if (_openedInitial || _controller.loading) return;
    final direct = widget.initialMessageId;
    if (direct != null && direct.isNotEmpty) {
      _openedInitial = true;
      unawaited(_controller.select(direct));
      return;
    }
    final wanted = widget.initialProviderMessageId;
    if (wanted == null) return;
    _openedInitial = true;
    final match = _controller.items
        .where((item) => item.providerMessageId == wanted)
        .firstOrNull;
    if (match != null) unawaited(_controller.select(match.id));
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MainLayout(
      child: ColoredBox(
        color: scheme.surface,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _wide = constraints.maxWidth >= _splitMinWidth;
            return _wide ? _buildWide(context) : _buildNarrow(context);
          },
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final detail = _controller.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(controller: _controller, search: _search),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final listWidth =
                  (constraints.maxWidth * 0.4).clamp(380.0, 540.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: listWidth,
                    child: _MailList(controller: _controller),
                  ),
                  VerticalDivider(
                      width: 1, thickness: 1, color: roles.hairline),
                  Expanded(
                    child: detail == null
                        ? _EmptyDetail(controller: _controller)
                        : MailWorkDetail(
                            key: ValueKey(detail.id),
                            item: detail,
                            controller: _controller,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(BuildContext context) {
    final detail = _controller.detail;
    final roles = VinabikeThemeRoles.of(context);
    if (detail != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _controller.clearSelection();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _controller.clearSelection,
                    icon: const Icon(Icons.arrow_back, size: 20),
                    label: Text(_controller.view.label),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: roles.hairline),
            Expanded(
              child: MailWorkDetail(
                key: ValueKey(detail.id),
                item: detail,
                controller: _controller,
                compact: true,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompactHeader(controller: _controller, search: _search),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        MailboxFilterStrip(controller: _controller),
        Expanded(child: _MailList(controller: _controller, compact: true)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.search});

  final MailWorkController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final open = controller.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 24,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // El modo va donde estaba el título: «Correo» ya lo dicen la
              // pestaña y el menú, y así el encabezado cabe en una línea.
              MailModeSwitch(
                current: MailMode.smart,
                providerId: open?.provider,
                messageId: open?.providerMessageId,
              ),
              const SizedBox(width: 12),
              MailboxSelector(controller: controller),
            ],
          ),
          _ViewTabs(controller: controller),
          _HeaderTools(controller: controller, search: search),
        ],
      ),
    );
  }
}

class _HeaderTools extends StatelessWidget {
  const _HeaderTools({required this.controller, required this.search});

  final MailWorkController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 300,
            child: _SearchField(controller: controller, search: search),
          ),
          const SizedBox(width: 10),
          VbButton(
            label: 'Redactar',
            icon: Icons.edit_outlined,
            onPressed: () => unawaited(openMailCompose(context)),
          ),
        ],
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.controller, required this.search});

  final MailWorkController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MailModeSwitch(current: MailMode.smart, expand: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _SearchField(controller: controller, search: search)),
              const SizedBox(width: 4),
              MailboxCompactButton(controller: controller),
              IconButton(
                tooltip: 'Redactar',
                onPressed: () => unawaited(openMailCompose(context)),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _ViewTabs(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.search});

  final MailWorkController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => MailSearchField(
        controller: search,
        hint: 'Trabajo, proveedor, folio o monto',
        onChanged: controller.setQuery,
        onClear: () => controller.setQuery(''),
      );
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.controller});

  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final view in MailView.values) ...[
          _ViewTab(
            label: view.label,
            count: controller.counts.countFor(view),
            selected: controller.view == view,
            onTap: () => controller.setView(view),
          ),
          if (view != MailView.values.last) const SizedBox(width: 22),
        ],
      ],
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 15, 2, 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
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
    );
  }
}

// ---------------------------------------------------------------------------
// Lista
// ---------------------------------------------------------------------------

sealed class _Entry {
  const _Entry();
}

class _SectionEntry extends _Entry {
  const _SectionEntry(this.title, this.count);
  final String title;
  final int count;
}

class _ItemEntry extends _Entry {
  const _ItemEntry(this.item);
  final MailItem item;
}

class _MailList extends StatelessWidget {
  const _MailList({required this.controller, this.compact = false});

  final MailWorkController controller;
  final bool compact;

  static MailItem? firstShown(MailWorkController controller) {
    for (final entry in _entriesFor(controller)) {
      if (entry is _ItemEntry) return entry.item;
    }
    return null;
  }

  List<_Entry> _entries() => _entriesFor(controller);

  static List<_Entry> _entriesFor(MailWorkController controller) {
    final items = controller.items;
    final entries = <_Entry>[];
    if (controller.view == MailView.today) {
      final byGroup = <String, List<MailItem>>{};
      for (final item in items) {
        byGroup.putIfAbsent(MailWords.todayGroupOf(item), () => []).add(item);
      }
      final order = [
        for (final (code, _, _) in MailWords.todayGroups) code,
        'otros'
      ];
      for (final code in order) {
        final group = byGroup[code];
        if (group == null || group.isEmpty) continue;
        entries
            .add(_SectionEntry(MailWords.todayGroupTitle(code), group.length));
        entries.addAll(group.map(_ItemEntry.new));
      }
      return entries;
    }
    if (controller.view == MailView.waiting && controller.query.isEmpty) {
      // Lo que lleva más tiempo esperando, primero; lo vencido arriba.
      DateTime since(MailItem item) =>
          item.state.waitingSince ?? item.receivedAt;
      final sorted = [...items]..sort((a, b) => since(a).compareTo(since(b)));
      final overdue = sorted.where((item) => item.state.overdue).toList();
      final waiting = sorted.where((item) => !item.state.overdue).toList();
      if (overdue.isNotEmpty) {
        entries.add(_SectionEntry(MailWords.overdueGroup, overdue.length));
        entries.addAll(overdue.map(_ItemEntry.new));
      }
      if (waiting.isNotEmpty) {
        entries.add(_SectionEntry(MailWords.waitingGroup, waiting.length));
        entries.addAll(waiting.map(_ItemEntry.new));
      }
      return entries;
    }
    final now = DateTime.now();
    String? current;
    for (final item in items) {
      final title = MailWords.dayGroup(item.receivedAt, now);
      if (title != current) {
        current = title;
        entries.add(_SectionEntry(title, 0));
      }
      entries.add(_ItemEntry(item));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    if (controller.loading && controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (controller.error != null && controller.items.isEmpty) {
      return _Message(
        title: 'No se pudo leer el correo.',
        body: 'Revisa la conexión y vuelve a intentar.',
        action: VbButton(
          label: 'Reintentar',
          variant: VbButtonVariant.text,
          onPressed: () => unawaited(controller.refresh()),
        ),
      );
    }
    final entries = _entries();
    if (entries.isEmpty) {
      return _Message(
        title: controller.query.isNotEmpty
            ? 'Nada calza con «${controller.query}».'
            : controller.view == MailView.today
                ? controller.mailbox == null
                    ? 'Nada pendiente.'
                    : 'Nada pendiente en ${controller.mailbox}.'
                : controller.view == MailView.waiting
                    ? 'Nada espera respuesta.'
                    : 'No hay correos aquí.',
        body: controller.query.isNotEmpty
            ? null
            : controller.view == MailView.today
                ? 'Lo que pida algo aparece aquí: facturas por registrar, pagos por confirmar, clientes por responder.'
                : controller.view == MailView.waiting
                    ? 'Lo que mandes pidiendo algo y los reclamos abiertos quedan aquí con su fecha; si no responden, vuelven a «Para hoy» con un recordatorio.'
                    : null,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.syncNow,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: entries.length + 1,
        itemBuilder: (context, index) {
          if (index == entries.length) {
            return _SyncFooter(controller: controller);
          }
          final entry = entries[index];
          return switch (entry) {
            _SectionEntry(:final title, :final count) => _SectionHeader(
                title: title,
                count: count,
                compact: compact,
              ),
            _ItemEntry(:final item) => _MailRow(
                item: item,
                selected: !compact && controller.selectedId == item.id,
                compact: compact,
                showAccount: controller.mailbox == null &&
                    controller.counts.mailboxes.length > 1,
                onTap: () => unawaited(controller.select(item.id)),
              ),
          };
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.count, required this.compact});

  final String title;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
      color: scheme.onSurfaceVariant,
    );
    return Semantics(
      header: true,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(compact ? 16 : 20, 18, compact ? 16 : 20, 6),
        child: Row(
          children: [
            Text(title.toUpperCase(), style: style),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Text('$count', style: style),
            ],
          ],
        ),
      ),
    );
  }
}

class _MailRow extends StatelessWidget {
  const _MailRow({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.showAccount,
  });

  final MailItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  /// En la bandeja unida de varias casillas: el logo de la cuenta.
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final done = item.state.actionable && item.state.done;
    final link = item.primaryLink;
    return MailListRow(
      title: item.direction == 'out'
          ? 'Para ${item.recipientTitle}'
          : item.senderTitle,
      markName: item.otherSideTitle,
      markLogoUrl: item.otherSideImageUrl,
      accountBadge: showAccount ? mailAccountLogo(item.provider) : null,
      time: MailWords.shortTime(item.receivedAt, DateTime.now()),
      subject: item.subject,
      detail: MailWords.rowDetail(item),
      detailIcon: link != null ? Icons.link : null,
      status: MailWords.rowStatus(item),
      statusDone: done,
      unread: !item.read,
      dimmed: done,
      selected: selected,
      compact: compact,
      onTap: onTap,
    );
  }
}

class _SyncFooter extends StatelessWidget {
  const _SyncFooter({required this.controller});

  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final chosen = controller.mailbox;
    final mailboxes = [
      for (final mailbox in controller.counts.mailboxes)
        if (chosen == null || mailbox.address == chosen) mailbox,
    ];
    String text;
    if (controller.syncing) {
      text = 'Trayendo correo nuevo…';
    } else if (mailboxes.isEmpty) {
      text = 'Ninguna casilla de la empresa encendida.';
    } else if (mailboxes.any((m) => m.hasError)) {
      final failing =
          mailboxes.where((m) => m.hasError).map((m) => m.address).join(', ');
      text = 'No se pudo leer $failing.';
    } else {
      final last = mailboxes
          .map((m) => m.lastSyncedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
      final minutes =
          last == null ? null : DateTime.now().difference(last).inMinutes;
      final when = minutes == null
          ? ''
          : minutes < 1
              ? ' · al día'
              : ' · al día hace $minutes min';
      text = '${mailboxes.map((m) => m.address).join(' y ')}$when';
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: roles.hairline))),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.body, this.action});

  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: scheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({required this.controller});

  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (controller.detailLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            controller.items.isEmpty ? 'Nada que abrir.' : 'Elige un correo.',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
