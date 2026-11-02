import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/customer_quote.dart';
import '../services/customer_quote_service.dart';
import '../widgets/customer_quote_detail_view.dart';

/// Bandeja de cotizaciones (`/sales/quotes`).
///
/// En escritorio la lista y la cotización elegida conviven: se confirma con
/// los proveedores sin perder la fila. En el teléfono, la fila abre la ruta
/// propia de la cotización y «Volver» regresa aquí con el mismo filtro.
class CustomerQuotesPage extends StatefulWidget {
  const CustomerQuotesPage({super.key, this.initialQuoteId, this.service});

  final String? initialQuoteId;
  final CustomerQuoteService? service;

  @override
  State<CustomerQuotesPage> createState() => _CustomerQuotesPageState();
}

/// Los filtros de la bandeja, en el orden en que el taller los trabaja.
enum _QuoteFilter {
  confirming('Por confirmar'),
  offered('Enviadas'),
  accepted('Aceptadas'),
  closed('Cerradas'),
  all('Todas');

  const _QuoteFilter(this.label);
  final String label;

  bool matches(CustomerQuoteStatus status) => switch (this) {
        _QuoteFilter.confirming => status == CustomerQuoteStatus.confirming,
        _QuoteFilter.offered => status == CustomerQuoteStatus.offered,
        _QuoteFilter.accepted => status == CustomerQuoteStatus.accepted,
        _QuoteFilter.closed =>
          !status.isOpen && status != CustomerQuoteStatus.accepted,
        _QuoteFilter.all => true,
      };
}

class _CustomerQuotesPageState extends State<CustomerQuotesPage>
    with WidgetsBindingObserver {
  late final CustomerQuoteService _service =
      widget.service ?? CustomerQuoteService();
  CustomerQuoteInbox? _inbox;
  Object? _error;
  _QuoteFilter _filter = _QuoteFilter.confirming;
  String? _selectedId;
  Timer? _refreshTimer;

  static const double _splitBreakpoint = 1100;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialQuoteId;
    WidgetsBinding.instance.addObserver(this);
    _load(chooseFilter: true);
    // Una cotización nueva llega sola: la bandeja se pone al día cada minuto.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({bool chooseFilter = false}) async {
    try {
      final inbox = await _service.fetchInbox();
      if (!mounted) return;
      setState(() {
        _inbox = inbox;
        _error = null;
        if (chooseFilter) _filter = _initialFilter(inbox);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// Abre donde hay trabajo: lo que espera confirmación, si no lo enviado.
  _QuoteFilter _initialFilter(CustomerQuoteInbox inbox) {
    final selected = widget.initialQuoteId;
    if (selected != null) {
      for (final quote in inbox.quotes) {
        if (quote.id == selected) {
          return _QuoteFilter.values
              .firstWhere((filter) => filter.matches(quote.status));
        }
      }
      return _QuoteFilter.all;
    }
    if (inbox.count(CustomerQuoteStatus.confirming) > 0) {
      return _QuoteFilter.confirming;
    }
    if (inbox.count(CustomerQuoteStatus.offered) > 0) {
      return _QuoteFilter.offered;
    }
    return _QuoteFilter.all;
  }

  int _countFor(_QuoteFilter filter) {
    final inbox = _inbox;
    if (inbox == null) return 0;
    return inbox.quotes.where((quote) => filter.matches(quote.status)).length;
  }

  void _open(CustomerQuoteSummary quote, {required bool split}) {
    if (split) {
      setState(() => _selectedId = quote.id);
      return;
    }
    context
        .push('/sales/quotes/${Uri.encodeComponent(quote.id)}')
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _inbox?.count(CustomerQuoteStatus.confirming) ?? 0;
    return MainLayout(
      title: 'Cotizaciones',
      compactHeader: MainLayoutCompactHeader(
        title: 'Cotizaciones',
        contextLine: confirming == 0
            ? 'Al día'
            : confirming == 1
                ? '1 por confirmar'
                : '$confirming por confirmar',
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final split = constraints.maxWidth >= _splitBreakpoint;
        final list = _buildList(context, split: split);
        if (!split) return list;
        final roles = VinabikeThemeRoles.of(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 440, child: list),
            VerticalDivider(width: 1, color: roles.hairline),
            Expanded(
              child: _selectedId == null
                  ? const _NothingSelected()
                  : CustomerQuoteDetailView(
                      key: ValueKey(_selectedId),
                      quoteId: _selectedId!,
                      service: _service,
                      onChanged: _load,
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildList(BuildContext context, {required bool split}) {
    final theme = Theme.of(context);
    final inbox = _inbox;
    final quotes = inbox?.quotes
            .where((quote) => _filter.matches(quote.status))
            .toList() ??
        const <CustomerQuoteSummary>[];

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _QuoteFilter.values) ...[
                    _FilterChip(
                      label: filter.label,
                      count: filter == _QuoteFilter.all ||
                              filter == _QuoteFilter.closed
                          ? null
                          : _countFor(filter),
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );

    Widget body;
    if (inbox == null && _error == null) {
      body = const Center(child: BrandedLoading());
    } else if (inbox == null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: VbNotice(
          title: 'No se pudo cargar la bandeja',
          body: CustomerQuoteService.describeError(_error!),
          tone: VbNoticeTone.danger,
          action: VbButton(
              label: 'Reintentar',
              variant: VbButtonVariant.secondary,
              onPressed: _load),
        ),
      );
    } else if (quotes.isEmpty) {
      body = _EmptyInbox(filter: _filter, anyQuote: inbox.quotes.isNotEmpty);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          itemCount: quotes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            final quote = quotes[index];
            return _QuoteRow(
              quote: quote,
              selected: split && quote.id == _selectedId,
              onTap: () => _open(quote, split: split),
            );
          },
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, Expanded(child: body)],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final foreground = selected
        ? roles.onSelectionContainer
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? roles.selectionContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? roles.accentBorder : roles.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
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

class _QuoteRow extends StatelessWidget {
  const _QuoteRow(
      {required this.quote, required this.selected, required this.onTap});

  final CustomerQuoteSummary quote;
  final bool selected;
  final VoidCallback onTap;

  String _age(DateTime value) {
    final diff = DateTime.now().toUtc().difference(value.toUtc());
    if (diff.inMinutes < 1) return 'recién';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);

    final String? workLine;
    if (quote.status == CustomerQuoteStatus.confirming && quote.openTasks > 0) {
      final overdue =
          quote.nextDueAt != null && quote.nextDueAt!.isBefore(DateTime.now());
      workLine =
          '${quote.openTasks == 1 ? '1 proveedor' : '${quote.openTasks} proveedores'} por consultar'
          '${overdue ? ' · atrasado' : ''}';
    } else if (quote.status == CustomerQuoteStatus.confirming) {
      workLine = 'Lista para enviar';
    } else if (quote.status == CustomerQuoteStatus.offered &&
        quote.expiresAt != null) {
      final left = quote.expiresAt!.toUtc().difference(DateTime.now().toUtc());
      workLine = left.isNegative ? 'Venciendo' : 'Vence en ${left.inHours} h';
    } else {
      workLine = null;
    }

    return Material(
      color: selected ? roles.selectionContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            quote.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        VbStatusBadge(
                            label: quote.status.label,
                            tone: quote.status.tone,
                            dense: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${quote.number} · ${quote.lines == 1 ? '1 producto' : '${quote.lines} productos'}'
                      ' · ${quote.channel.label} · ${_age(quote.requestedAt)}',
                      style: faint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (workLine != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        workLine,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              quote.status == CustomerQuoteStatus.confirming &&
                                      quote.openTasks > 0
                                  ? roles.warning.onContainer
                                  : roles.faintForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (quote.total != null) ...[
                const SizedBox(width: 12),
                Text(
                  VbMoneyText.formatClp(quote.total!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({required this.filter, required this.anyQuote});

  final _QuoteFilter filter;
  final bool anyQuote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final text = !anyQuote
        ? 'Todavía no llega ninguna. Las cotizaciones nacen en el sitio, cuando un '
            'cliente arma una lista con productos en stock o a pedido.'
        : switch (filter) {
            _QuoteFilter.confirming => 'Nada por confirmar con proveedores.',
            _QuoteFilter.offered => 'Ninguna oferta esperando respuesta.',
            _QuoteFilter.accepted => 'Ninguna aceptada todavía.',
            _ => 'Nada en esta lista.',
          };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.request_quote_outlined,
                size: 40, color: roles.faintForeground),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    return Center(
      child: Text(
        'Elige una cotización',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: roles.faintForeground),
      ),
    );
  }
}
