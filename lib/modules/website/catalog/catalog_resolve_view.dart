import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import 'catalog_item_detail.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// «Por resolver»: what keeps a product from selling or loses money,
/// grouped by kind of problem, each group with the fix it needs.
class CatalogResolveView extends StatefulWidget {
  const CatalogResolveView({super.key, required this.controller});

  final CatalogWebController controller;

  @override
  State<CatalogResolveView> createState() => _CatalogResolveViewState();
}

class _CatalogResolveViewState extends State<CatalogResolveView> {
  final Set<String> _expanded = {};

  CatalogWebController get _c => widget.controller;

  Future<void> _run(Future<Object?> Function() action,
      {String? done, SnackBarAction? undo}) async {
    try {
      final result = await action();
      if (!mounted) return;
      final message = result is String ? result : done;
      if (message != null) showCatalogMessage(context, message, action: undo);
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  void _openDetail(CatalogWebItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (context, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: CatalogItemDetail(
                item: _c.itemById(item.id) ?? item,
                controller: _c,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final issues = _c.issues;
        final codes = [
          for (final code in CatalogReasons.issueOrder)
            if (issues[code]?.isNotEmpty ?? false) code,
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final side = compact ? 12.0 : 20.0;
            if (codes.isEmpty) {
              return const CatalogEmpty(
                title: 'Nada por resolver',
                body: 'Todo lo marcado para la web cumple la regla.',
              );
            }
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(side, 16, side, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Index(
                    codes: codes,
                    issues: issues,
                    onTap: (code) {
                      final target = _keys[code]?.currentContext;
                      if (target != null) {
                        Scrollable.ensureVisible(
                          target,
                          duration: const Duration(milliseconds: 250),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  for (final code in codes) ...[
                    _Group(
                      key: _keys.putIfAbsent(code, GlobalKey.new),
                      code: code,
                      items: issues[code]!,
                      compact: compact,
                      expanded: _expanded.contains(code),
                      busy: _c.busy,
                      onExpand: () => setState(() {
                        if (!_expanded.remove(code)) _expanded.add(code);
                      }),
                      groupActions: _groupActions(code, issues[code]!),
                      rowActions: (item) => _rowActions(code, item),
                      facts: (item) => _facts(code, item),
                      onOpen: _openDetail,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  final Map<String, GlobalKey> _keys = {};

  List<Widget> _groupActions(String code, List<CatalogWebItem> items) {
    final ids = [for (final item in items) item.id];
    final busy = _c.busy;
    return switch (code) {
      'gtin_in_sku' => [
          VbButton(
            label: 'Copiar los ${items.length} a GTIN',
            busy: busy,
            onPressed: () => _run(
              () async {
                final copied = await _c.copySkuToGtin(ids);
                if (!mounted) return null;
                showCatalogMessage(
                  context,
                  '${copied.length} códigos de barra copiados al GTIN.',
                  action: SnackBarAction(
                    label: 'Deshacer',
                    onPressed: () => _run(
                      () => _c.undoSkuToGtin(copied),
                      done: 'GTIN copiados deshechos.',
                    ),
                  ),
                );
                return null;
              },
            ),
          ),
        ],
      'missing_tax' => [
          VbButton(
            label: 'Todos afectos a IVA 19 %',
            busy: busy,
            onPressed: () => _run(
              () async =>
                  '${await _c.classifyTax(ids, rate: 19)} clasificados como afectos a IVA.',
            ),
          ),
        ],
      'empty_record' => [
          VbButton(
            label: 'Archivar los ${items.length}',
            variant: VbButtonVariant.secondary,
            busy: busy,
            onPressed: () => _run(
              () async =>
                  '${await _c.archiveEmptyRecords(ids)} fichas archivadas.',
            ),
          ),
        ],
      _ => const [],
    };
  }

  List<Widget> _rowActions(String code, CatalogWebItem item) {
    final busy = _c.busy;
    Widget edit(String label) => _RowButton(
          of: item.displayName,
          label: label,
          onPressed: () => openCatalogItemEditor(context, _c, item),
        );
    return switch (code) {
      'missing_image' => [edit('Subir foto')],
      'below_cost' => [
          edit('Cambiar precio'),
          _RowButton(
            of: item.displayName,
            label: 'Liquidar 30 días',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(
                      () => _c.setClearance(
                        item.id,
                        DateUtils.dateOnly(DateTime.now())
                            .add(const Duration(days: 30)),
                      ),
                      done: 'En liquidación por 30 días.',
                    ),
          ),
        ],
      'missing_tax' => [
          _RowButton(
            of: item.displayName,
            label: 'Afecto 19 %',
            onPressed: busy
                ? null
                : () => _run(() => _c.classifyTax([item.id], rate: 19),
                    done: 'Afecto a IVA.'),
          ),
          _RowButton(
            of: item.displayName,
            label: 'Exento',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(() => _c.classifyTax([item.id], rate: 0),
                    done: 'Exento.'),
          ),
        ],
      'counter_consumable' => [
          _RowButton(
            of: item.displayName,
            label: 'Convertir',
            onPressed: busy
                ? null
                : () => _run(
                      () => _c.convertItem(item.id, toConsumable: false),
                      done:
                          'Ahora es producto de venta. Cuenta su stock para venderlo en la web.',
                    ),
          ),
          _RowButton(
            of: item.displayName,
            label: 'Dejar como consumible',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(() => _c.dismissIssue(item.id, code),
                    done: 'Queda como consumible.'),
          ),
        ],
      'gtin_in_sku' => [
          _RowButton(
            of: item.displayName,
            label: 'Copiar',
            onPressed: busy
                ? null
                : () => _run(() => _c.copySkuToGtin([item.id]),
                    done: 'Copiado al GTIN.'),
          ),
          _RowButton(
            of: item.displayName,
            label: 'No es código de barras',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(() => _c.dismissIssue(item.id, code),
                    done: 'Anotado.'),
          ),
        ],
      'bulk_pack' => [
          _RowButton(
            of: item.displayName,
            label: 'Se vende así',
            onPressed: busy
                ? null
                : () => _run(() => _c.dismissIssue(item.id, code),
                    done: 'Queda a la venta como paquete.'),
          ),
          _RowButton(
            of: item.displayName,
            label: 'Es insumo',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(
                      () => _c.convertItem(item.id, toConsumable: true),
                      done: 'Ahora es consumible del taller y salió de la web.',
                    ),
          ),
        ],
      'no_web_name' || 'no_brand' => [
          edit('Completar ficha'),
          _RowButton(
            of: item.displayName,
            label: 'Dejar así',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(() => _c.dismissIssue(item.id, code),
                    done: 'Anotado.'),
          ),
        ],
      'empty_record' => [
          _RowButton(
            of: item.displayName,
            label: 'Archivar',
            onPressed: busy
                ? null
                : () => _run(() => _c.archiveEmptyRecords([item.id]),
                    done: 'Archivado.'),
          ),
          _RowButton(
            of: item.displayName,
            label: 'Es un producto',
            quiet: true,
            onPressed: busy
                ? null
                : () => _run(() => _c.dismissIssue(item.id, code),
                    done: 'Anotado.'),
          ),
        ],
      _ => [edit('Completar ficha')],
    };
  }

  String _facts(String code, CatalogWebItem item) {
    final stock = item.kind == CatalogItemKind.consumable
        ? null
        : item.sellable > 0
            ? '${item.sellable} en stock'
            : 'sin stock';
    final parts = <String?>[
      item.sku.isEmpty ? null : item.sku,
      switch (code) {
        'below_cost' => [
            catalogMoney(item.webPrice),
            if (item.minWebPrice != null)
              'mínimo ${catalogMoney(item.minWebPrice!)}',
            stock,
          ].whereType<String>().join(' · '),
        'counter_consumable' =>
          '${catalogMoney(item.webPrice)} · ${item.soldCounter12m} al mesón · ${item.usedJobs12m} en trabajos',
        'gtin_in_sku' =>
          'código ${item.sku} · ${item.state.label.toLowerCase()}',
        'empty_record' => item.name,
        _ =>
          [catalogMoney(item.webPrice), stock].whereType<String>().join(' · '),
      },
    ];
    return parts.whereType<String>().where((p) => p.isNotEmpty).join(' · ');
  }
}

class _Index extends StatelessWidget {
  const _Index(
      {required this.codes, required this.issues, required this.onTap});

  final List<String> codes;
  final Map<String, List<CatalogWebItem>> issues;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Por resolver',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Lo que impide vender o hace perder plata, ordenado por lo que está en juego. '
          'Cada aviso desaparece cuando queda resuelto.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final code in codes)
              ActionChip(
                label: Text(
                    '${CatalogReasons.issueShort(code)} · ${issues[code]!.length}'),
                onPressed: () => onTap(code),
              ),
          ],
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    super.key,
    required this.code,
    required this.items,
    required this.compact,
    required this.expanded,
    required this.busy,
    required this.onExpand,
    required this.groupActions,
    required this.rowActions,
    required this.facts,
    required this.onOpen,
  });

  final String code;
  final List<CatalogWebItem> items;
  final bool compact;
  final bool expanded;
  final bool busy;
  final VoidCallback onExpand;
  final List<Widget> groupActions;
  final List<Widget> Function(CatalogWebItem item) rowActions;
  final String Function(CatalogWebItem item) facts;
  final ValueChanged<CatalogWebItem> onOpen;

  static const _preview = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final money = code == 'missing_image' || code == 'below_cost';
    final atStake = items.fold<double>(0, (sum, item) => sum + item.stockValue);
    final withStock = items.where((item) => item.sellable > 0).length;
    final shown = expanded ? items : items.take(_preview).toList();
    final countColor = switch (code) {
      'below_cost' || 'missing_tax' => roles.danger.accent,
      'missing_image' || 'missing_price' || 'bulk_pack' => roles.warning.accent,
      'counter_consumable' => scheme.tertiary,
      _ => scheme.primary,
    };

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Wrap(
              spacing: 18,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 520 : 720),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${items.length}',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: countColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(CatalogReasons.issueTitle(code),
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(CatalogReasons.issueExplanation(code),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                            if (money && withStock > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '$withStock con stock · ${catalogMoney(atStake)} a precio web',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (groupActions.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: groupActions),
              ],
            ),
          ),
          for (final item in shown)
            _IssueRow(
              item: item,
              facts: facts(item),
              compact: compact,
              actions: rowActions(item),
              onOpen: () => onOpen(item),
            ),
          if (items.length > _preview)
            TextButton(
              onPressed: onExpand,
              child: Text(expanded ? 'Ver menos' : 'Ver los ${items.length}'),
            ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    required this.item,
    required this.facts,
    required this.compact,
    required this.actions,
    required this.onOpen,
  });

  final CatalogWebItem item;
  final String facts;
  final bool compact;
  final List<Widget> actions;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final scheme = theme.colorScheme;
    final name = InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CatalogThumb(item: item, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(facts,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: roles.hairline))),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: name),
                const SizedBox(width: 12),
                Wrap(spacing: 6, children: actions),
              ],
            ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.of,
    required this.onPressed,
    this.quiet = false,
  });

  final String label;

  /// The item it acts on: every row repeats the same buttons, so a screen
  /// reader hears «Copiar: Cámara Maxxis…», not eight «Copiar».
  final String of;
  final VoidCallback? onPressed;
  final bool quiet;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onPressed != null,
        label: '$label: $of',
        onTap: onPressed,
        excludeSemantics: true,
        child: quiet
            ? TextButton(onPressed: onPressed, child: Text(label))
            : OutlinedButton(onPressed: onPressed, child: Text(label)),
      );
}
