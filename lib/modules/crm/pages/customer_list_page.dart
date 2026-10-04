import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bike_directory_entries.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../bikeshop/widgets/bike_module_style.dart';
import '../../bikeshop/widgets/bike_silhouette.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/models/sales_models.dart';
import '../models/crm_models.dart';
import '../services/customer_directory.dart';
import '../services/customer_service.dart';

final NumberFormat _money =
    NumberFormat.currency(symbol: r'$', decimalDigits: 0);
final NumberFormat _count = NumberFormat.decimalPattern();

/// La lista de clientes (`/clientes`), rediseñada el 2026-10-03 desde el
/// lienzo que aprobó el dueño.
///
/// Abre en **Con actividad** —quien tiene una bici, un trabajo o una
/// factura—, los que vinieron hace menos primero, porque los importados de
/// Zoho sin nada tapaban a los clientes reales. Cada fila dice su bici, si
/// tiene algo en el taller, cuándo vino y cuánto ha pagado. **En el taller**
/// y **Por cobrar** se abren también desde sus contadores de arriba; **Todos**
/// queda por nombre. Usa todo el ancho en escritorio; en teléfono, filas
/// compactas con la búsqueda en la cabecera.
class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  static const int _pageSize = 50;

  final TextEditingController _searchController = TextEditingController();

  List<CustomerDirectoryEntry> _rows = const [];
  bool _loading = true;
  String? _error;

  /// Las facturas no se pudieron leer: lo pagado y lo que se debe no se
  /// muestran como cero.
  bool _invoicesFailed = false;

  /// Lo que se debe en facturas sin cliente (3 el 2026-10-03): no es de
  /// ninguna fila, pero sí del total por cobrar.
  List<Invoice> _unassignedOwed = const [];
  int _generation = 0;

  CustomerListView _view = CustomerListView.active;
  String _query = '';
  int _visible = _pageSize;

  DateTime get _today => DateTime.now();

  @override
  void initState() {
    super.initState();
    // Después del primer frame: leer facturas avisa a SalesService, y avisar
    // mientras se construye la página es un error de Flutter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_generation;
    final customers = context.read<CustomerService>();
    final bikeshop = context.read<BikeshopService>();
    final sales = context.read<SalesService>();
    setState(() {
      _error = null;
      if (_rows.isEmpty) _loading = true;
    });
    try {
      final results = await Future.wait<Object?>([
        customers.getCustomersForList(forceRefresh: forceRefresh),
        bikeshop.getBikes(forceRefresh: forceRefresh),
        bikeshop.getJobs(forceRefresh: forceRefresh),
        bikeshop.getAllJobBikes(
          forceRefresh: forceRefresh,
          rethrowErrors: true,
        ),
        sales.loadInvoices(forceRefresh: forceRefresh),
      ]);
      if (!mounted || generation != _generation) return;
      final invoicesFailed = sales.invoiceError != null;
      final customerList = results[0] as List<Customer>;
      final customerIds = {
        for (final customer in customerList)
          if (customer.id != null) customer.id!,
      };
      setState(() {
        _unassignedOwed = invoicesFailed
            ? const []
            : [
                for (final invoice in sales.cachedInvoices)
                  if (invoiceIsOwed(invoice) &&
                      !customerIds.contains(invoice.customerId))
                    invoice,
              ];
        _rows = buildCustomerDirectory(
          customers: customerList,
          bikes: results[1] as List<Bike>,
          jobs: results[2] as List<MechanicJob>,
          jobBikesByJobId: results[3] as Map<String, List<MechanicJobBike>>,
          invoices: invoicesFailed ? const [] : sales.cachedInvoices,
        );
        _invoicesFailed = invoicesFailed;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Customer list load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = 'No pudimos actualizar los clientes.';
        _loading = false;
      });
    }
  }

  void _setQuery(String value) {
    setState(() {
      _query = value.trim();
      _visible = _pageSize;
    });
  }

  void _clearQuery() {
    _searchController.clear();
    _setQuery('');
  }

  void _setView(CustomerListView view) {
    setState(() {
      _view = view;
      _visible = _pageSize;
    });
  }

  void _openCustomer(CustomerDirectoryEntry row) {
    final id = row.customer.id;
    if (id == null || id.isEmpty) return;
    context.push('/clientes/$id').then((_) {
      if (mounted) _load();
    });
  }

  void _openInvoices() {
    context.push('/sales/invoices').then((_) {
      if (mounted) _load(forceRefresh: true);
    });
  }

  void _newCustomer() {
    context.push('/clientes/nuevo').then((_) {
      if (mounted) _load(forceRefresh: true);
    });
  }

  // ── Lo que se cuenta ─────────────────────────────────────────────────────

  int get _activeCount => _rows.where((row) => row.hasActivity).length;
  int get _workshopCount => _rows.where((row) => row.inWorkshop).length;
  List<CustomerDirectoryEntry> get _owedRows =>
      _rows.where((row) => row.owedInvoices.isNotEmpty).toList();

  int _countOf(CustomerListView view) => switch (view) {
        CustomerListView.active => _activeCount,
        CustomerListView.workshop => _workshopCount,
        CustomerListView.owed => _owedRows.length,
        CustomerListView.all => _rows.length,
      };

  /// Las filas de la vista, o lo que coincide con la búsqueda dentro de ella
  /// y cuántas más coinciden fuera.
  ({List<CustomerDirectoryEntry> rows, int elsewhere}) _shown() {
    final base = customerDirectoryView(_rows, _view);
    if (_query.isEmpty) return (rows: base, elsewhere: 0);
    List<CustomerDirectoryEntry> search(Iterable<CustomerDirectoryEntry> rows) {
      final scored = [
        for (final row in rows)
          (row: row, score: customerDirectorySearchScore(row, _query)),
      ].where((entry) => entry.score > 0).toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      return [for (final entry in scored) entry.row];
    }

    final found = search(base);
    final everywhere =
        _view == CustomerListView.all ? found.length : search(_rows).length;
    return (rows: found, elsewhere: everywhere - found.length);
  }

  String get _summary {
    if (_loading && _rows.isEmpty) return 'Cargando…';
    return '${_count.format(_rows.length)} registrados · '
        '${_count.format(_activeCount)} con actividad';
  }

  String _ago(DateTime date) {
    final days = calendarDaysBetween(date, _today);
    if (days <= 0) return 'hoy';
    if (days == 1) return 'ayer';
    if (days < 31) return 'hace $days días';
    if (days < 365) {
      final months = days ~/ 30;
      return months <= 1 ? 'hace 1 mes' : 'hace $months meses';
    }
    final years = days ~/ 365;
    return years == 1 ? 'hace 1 año' : 'hace $years años';
  }

  // ── Página ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    return MainLayout(
      title: 'Clientes',
      compactHeader: compact
          ? MainLayoutCompactHeader(
              title: 'Clientes',
              contextLine: _summary,
              search: MainLayoutCompactSearch(
                controller: _searchController,
                onChanged: _setQuery,
                onClear: _clearQuery,
                hintText: 'Nombre, teléfono o bici',
              ),
              actions: [
                IconButton(
                  tooltip: 'Nuevo cliente',
                  onPressed: _newCustomer,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
              ],
            )
          : null,
      body: BikeModuleTheme(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: compact ? _buildCompact(context) : _buildWide(context),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final theme = Theme.of(context);
    final owedRows = _owedRows;
    final owedTotal = owedRows.fold(0.0, (sum, row) => sum + row.owed) +
        _unassignedOwed.fold(0.0, (sum, invoice) => sum + invoice.balance);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Clientes',
                          style: BikeModuleText.title(context, size: 40)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _summary,
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _CountTile(
                count: _workshopCount,
                title: 'En el taller',
                detail: 'con trabajo abierto',
                selected: _view == CustomerListView.workshop,
                onTap: () => _setView(CustomerListView.workshop),
              ),
              const SizedBox(width: 12),
              _CountTile(
                count: _invoicesFailed ? null : owedRows.length,
                title: 'Por cobrar',
                detail: _invoicesFailed ? 'sin leer' : _money.format(owedTotal),
                warn: !_invoicesFailed && owedRows.isNotEmpty,
                selected: _view == CustomerListView.owed,
                onTap: () => _setView(CustomerListView.owed),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => _load(forceRefresh: true),
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              VbButton(
                label: 'Nuevo cliente',
                icon: Icons.add,
                density: VbDensity.comfortable,
                onPressed: _newCustomer,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _buildSearchField(context)),
              const SizedBox(width: 12),
              SizedBox(width: 600, child: _buildViewSelector(short: false)),
            ],
          ),
          if (_error != null || _invoicesFailed) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(context),
          ],
          const SizedBox(height: 16),
          Expanded(child: _buildWideList(context)),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      key: const ValueKey('customer-list-search'),
      controller: _searchController,
      onChanged: _setQuery,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Nombre, teléfono, RUT o bicicleta',
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: _clearQuery,
                icon: const Icon(Icons.close, size: 18),
              ),
      ),
    );
  }

  Widget _buildViewSelector({required bool short}) {
    String label(CustomerListView view) {
      final count = view == CustomerListView.owed && _invoicesFailed
          ? '—'
          : _count.format(_countOf(view));
      final name = switch (view) {
        CustomerListView.active => short ? 'Activos' : 'Con actividad',
        CustomerListView.workshop => short ? 'Taller' : 'En el taller',
        CustomerListView.owed => short ? 'Deben' : 'Por cobrar',
        CustomerListView.all => 'Todos',
      };
      return '$name $count';
    }

    return VbSegmented<CustomerListView>(
      groupLabel: 'Mostrar',
      density: short ? null : VbDensity.comfortable,
      value: _view,
      onChanged: _setView,
      options: [
        for (final view in CustomerListView.values)
          VbSegmentedOption(value: view, label: label(view)),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final message = _error != null
        ? (_rows.isEmpty
            ? _error!
            : '${_error!} Lo que ves puede estar desactualizado.')
        : 'No pudimos leer las facturas: lo pagado y lo que se debe no se '
            'muestran.';
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: roles.warning.container,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: roles.warning.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 18, color: roles.warning.onContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: roles.warning.onContainer)),
            ),
            VbButton(
              label: 'Reintentar',
              variant: VbButtonVariant.text,
              icon: Icons.refresh,
              onPressed: () => _load(forceRefresh: true),
            ),
          ],
        ),
      ),
    );
  }

  // ── Escritorio ───────────────────────────────────────────────────────────

  Widget _buildWideList(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _rows.isEmpty) {
      return const Center(child: BrandedLoading());
    }
    final owedView = _view == CustomerListView.owed;
    final shown = _shown();
    final rows = shown.rows;
    final children = <Widget>[];
    final unassigned =
        owedView && _query.isEmpty ? _unassignedOwed : const <Invoice>[];
    if (rows.isEmpty && unassigned.isEmpty) {
      children.add(_buildEmpty(context, elsewhere: shown.elsewhere));
    } else {
      for (final row in rows.take(_visible)) {
        children.add(owedView
            ? _OwedWideRow(
                row: row,
                today: _today,
                ago: _ago,
                onOpen: () => _openCustomer(row),
              )
            : _ActivityWideRow(
                row: row,
                today: _today,
                ago: _ago,
                invoicesKnown: !_invoicesFailed,
                onOpen: () => _openCustomer(row),
              ));
      }
      if (unassigned.isNotEmpty) {
        children.add(_UnassignedOwedRow(
          invoices: unassigned,
          today: _today,
          ago: _ago,
          compact: false,
          onOpen: _openInvoices,
        ));
      }
      children.add(_buildFooter(context,
          shown: rows.length, elsewhere: shown.elsewhere));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (owedView && _query.isEmpty && !_invoicesFailed)
              _OwedSummary(
                  rows: _owedRows, unassigned: _unassignedOwed, today: _today),
            if (rows.isNotEmpty || unassigned.isNotEmpty)
              owedView ? const _OwedHeaderRow() : const _ActivityHeaderRow(),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: children),
            ),
          ],
        ),
      ),
    );
  }

  String _orderText() => switch (_view) {
        CustomerListView.active => 'los que vinieron hace menos, primero',
        CustomerListView.workshop => 'lo que más espera, primero',
        CustomerListView.owed => 'el saldo más alto primero',
        CustomerListView.all => 'por nombre',
      };

  Widget _buildFooter(
    BuildContext context, {
    required int shown,
    required int elsewhere,
  }) {
    final theme = Theme.of(context);
    final visible = _visible < shown ? _visible : shown;
    final parts = [
      _query.isEmpty
          ? '${_count.format(visible)} de ${_count.format(shown)} · ${_orderText()}'
          : '${_count.format(visible)} de ${_count.format(shown)} que coinciden',
      if (_query.isEmpty &&
          _view == CustomerListView.active &&
          _rows.length > _activeCount)
        'Los ${_count.format(_rows.length - _activeCount)} sin bicis, '
            'trabajos ni facturas están en «Todos».',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
            top: BorderSide(color: VinabikeThemeRoles.of(context).hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              parts.join('. '),
              style: TextStyle(
                  fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (elsewhere > 0) ...[
            const SizedBox(width: 12),
            VbButton(
              label: '${_count.format(elsewhere)} más en «Todos»',
              variant: VbButtonVariant.text,
              onPressed: () => _setView(CustomerListView.all),
            ),
          ],
          if (_visible < shown) ...[
            const SizedBox(width: 12),
            VbButton(
              label: 'Ver más',
              variant: VbButtonVariant.secondary,
              onPressed: () => setState(() => _visible += _pageSize),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, {required int elsewhere}) {
    final theme = Theme.of(context);
    final message = _query.isNotEmpty
        ? 'Ningún cliente de esta vista coincide con «$_query».'
        : switch (_view) {
            CustomerListView.active => 'Todavía no hay clientes con actividad.',
            CustomerListView.workshop =>
              'Ningún cliente tiene algo en el taller ahora.',
            CustomerListView.owed => _invoicesFailed
                ? 'No pudimos leer las facturas.'
                : 'Nadie debe nada.',
            CustomerListView.all => 'Todavía no hay clientes.',
          };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16, color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (elsewhere > 0)
                  VbButton(
                    label: 'Ver ${_count.format(elsewhere)} en «Todos»',
                    onPressed: () => _setView(CustomerListView.all),
                  ),
                VbButton(
                  label: 'Limpiar búsqueda',
                  variant: VbButtonVariant.secondary,
                  onPressed: _clearQuery,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Teléfono ─────────────────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _rows.isEmpty) {
      return const Center(child: BrandedLoading());
    }
    final owedView = _view == CustomerListView.owed;
    final shown = _shown();
    final rows = shown.rows;
    final visible = rows.take(_visible).toList();
    final unassigned =
        owedView && _query.isEmpty ? _unassignedOwed : const <Invoice>[];
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildViewSelector(short: true),
          if (_error != null || _invoicesFailed) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(context),
          ],
          if (owedView &&
              _query.isEmpty &&
              !_invoicesFailed &&
              (rows.isNotEmpty || unassigned.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
              child: _OwedSummaryText(
                  rows: _owedRows, unassigned: _unassignedOwed, today: _today),
            ),
          const SizedBox(height: 12),
          if (rows.isEmpty && unassigned.isEmpty)
            _buildEmpty(context, elsewhere: shown.elsewhere)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < visible.length; index++)
                      _CompactRow(
                        row: visible[index],
                        owedView: owedView,
                        divider: index > 0,
                        today: _today,
                        ago: _ago,
                        onOpen: () => _openCustomer(visible[index]),
                      ),
                    if (unassigned.isNotEmpty)
                      _UnassignedOwedRow(
                        invoices: unassigned,
                        today: _today,
                        ago: _ago,
                        compact: true,
                        onOpen: _openInvoices,
                      ),
                    if (_visible < rows.length || shown.elsewhere > 0)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_visible < rows.length)
                              VbButton(
                                label: 'Ver más',
                                variant: VbButtonVariant.secondary,
                                expand: true,
                                onPressed: () =>
                                    setState(() => _visible += _pageSize),
                              ),
                            if (shown.elsewhere > 0)
                              VbButton(
                                label:
                                    '${_count.format(shown.elsewhere)} más en «Todos»',
                                variant: VbButtonVariant.text,
                                expand: true,
                                onPressed: () => _setView(CustomerListView.all),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Piezas ─────────────────────────────────────────────────────────────────

String _initials(String name) {
  final words =
      name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  if (words.isEmpty) return '?';
  return words
      .take(2)
      .map((word) => word.characters.first)
      .join()
      .toUpperCase();
}

String? _phoneOf(CustomerDirectoryEntry row) {
  final phone = row.customer.phone?.trim();
  if (phone == null || phone.isEmpty) return null;
  return ChileanUtils.formatPhone(phone);
}

String _bikeName(Bike bike) {
  final parts = [bike.brand, bike.model]
      .whereType<String>()
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  return parts.isEmpty ? 'Bicicleta sin nombre' : parts.join(' ');
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// «En el taller 15 · con trabajo abierto» y «Por cobrar 11 · $436.550»:
/// cuentan y abren su vista.
class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.count,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.warn = false,
  });

  final int? count;
  final String title;
  final String detail;
  final bool selected;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final background = selected && warn
        ? roles.warning.container
        : selected
            ? roles.selectionContainer
            : theme.colorScheme.surface;
    final border = selected && warn
        ? roles.warning.border
        : selected
            ? roles.accentBorder
            : theme.colorScheme.outlineVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title: ${count ?? 'sin leer'}, $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 150, minHeight: 58),
            padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == null ? '—' : _count.format(count),
                  style: BikeModuleText.figure(context, size: 30)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: warn ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: warn
                            ? roles.warning.onContainer
                            : roles.faintForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Las columnas de «Con actividad», «En el taller» y «Todos».
class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid({
    required this.customer,
    required this.bike,
    required this.now,
    required this.when,
    required this.paid,
    required this.trailing,
  });

  final Widget customer;
  final Widget bike;
  final Widget now;
  final Widget when;
  final Widget paid;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 14, child: customer),
        const SizedBox(width: 20),
        Expanded(flex: 17, child: bike),
        const SizedBox(width: 20),
        Expanded(flex: 15, child: now),
        const SizedBox(width: 20),
        SizedBox(width: 140, child: when),
        const SizedBox(width: 16),
        SizedBox(width: 110, child: paid),
        const SizedBox(width: 12),
        SizedBox(width: 20, child: trailing),
      ],
    );
  }
}

class _ActivityHeaderRow extends StatelessWidget {
  const _ActivityHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = BikeModuleText.label(context);
    Text label(String text, {TextAlign align = TextAlign.start}) =>
        Text(text.toUpperCase(), style: style, textAlign: align);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 13, 24, 13),
        child: _ActivityGrid(
          customer: label('Cliente'),
          bike: label('Bicicleta'),
          now: label('Ahora'),
          when: label('Última visita'),
          paid: label('Pagado', align: TextAlign.end),
          trailing: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ActivityWideRow extends StatelessWidget {
  const _ActivityWideRow({
    required this.row,
    required this.today,
    required this.ago,
    required this.invoicesKnown,
    required this.onOpen,
  });

  final CustomerDirectoryEntry row;
  final DateTime today;
  final String Function(DateTime) ago;
  final bool invoicesKnown;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final customer = row.customer;
    final phone = _phoneOf(row);
    final bike = row.mainBike;
    final job = row.workshopJob;
    final last = row.lastVisitAt;
    final extraBikes = row.bikes.length - 1;
    final bikeMeta = bike == null
        ? null
        : [
            if (bike.color?.trim().isNotEmpty == true)
              bike.color!.trim()[0].toUpperCase() +
                  bike.color!.trim().substring(1),
            if (bike.bikeType != null) bike.bikeType!.displayName,
            if (extraBikes > 0)
              extraBikes == 1 ? '+1 bici' : '+$extraBikes bicis',
          ].join(' · ');
    final name = customer.name.trim().isEmpty
        ? 'Cliente sin nombre'
        : customer.name.trim();
    final semantics = [
      name,
      phone ?? 'sin teléfono',
      bike == null ? 'sin bicicleta' : _bikeName(bike),
      if (job != null)
        'en el taller, ${job.jobNumber ?? ''} ${jobStatusLabel(job)}',
      if (last != null) 'última visita ${bikeFullDate(last)}',
    ].join(', ');

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      onTap: onOpen,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: _ActivityGrid(
              customer: Row(
                children: [
                  _Avatar(name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(
                          phone ?? 'Sin teléfono',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: phone == null
                                ? roles.faintForeground
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              bike: Row(
                children: [
                  _BikeTile(bike: bike),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bike == null)
                          Text('Sin bicicleta',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: roles.faintForeground))
                        else
                          _BikeName(bike: bike),
                        if (bikeMeta != null && bikeMeta.isNotEmpty)
                          Text(bikeMeta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: roles.faintForeground)),
                      ],
                    ),
                  ),
                ],
              ),
              now: job == null
                  ? Text('Sin trabajo abierto',
                      style: TextStyle(
                          fontSize: 13.5, color: roles.faintForeground))
                  : Row(
                      children: [
                        if (job.jobNumber != null) ...[
                          Text(job.jobNumber!,
                              style: BikeModuleText.code(context)),
                          const SizedBox(width: 12),
                        ],
                        Flexible(
                          child: BikeJobStatusDot(
                            label: jobStatusLabel(job),
                            color: jobStatusColor(job),
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
              when: last == null
                  ? Text('Sin visitas',
                      style: TextStyle(
                          fontSize: 13.5, color: roles.faintForeground))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(bikeShortDate(last, today: today),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()])),
                        Text(ago(last),
                            style: TextStyle(
                                fontSize: 12.5, color: roles.faintForeground)),
                      ],
                    ),
              paid: Text(
                !invoicesKnown
                    ? '—'
                    : row.paid > 0.5
                        ? _money.format(row.paid)
                        : '—',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: row.paid > 0.5 && invoicesKnown
                      ? theme.colorScheme.onSurface
                      : roles.faintForeground,
                ),
              ),
              trailing: Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _BikeTile extends StatelessWidget {
  const _BikeTile({required this.bike});

  static const double width = 66;
  static const double height = 44;

  final Bike? bike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bike = this.bike;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(9),
        border: bike == null
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: bike == null
          ? null
          : BikeSilhouette(bikeType: bike.bikeType, colorText: bike.color),
    );
  }
}

class _BikeName extends StatelessWidget {
  const _BikeName({required this.bike});

  final Bike bike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = bike.brand?.trim() ?? '';
    final model = bike.model?.trim() ?? '';
    if (brand.isEmpty && model.isEmpty) {
      return const Text('Bicicleta sin nombre',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
    }
    return Text.rich(
      TextSpan(children: [
        if (brand.isNotEmpty)
          TextSpan(
            text: model.isEmpty ? brand : '$brand ',
            style: TextStyle(
              fontWeight: model.isEmpty ? FontWeight.w600 : FontWeight.w500,
              color: model.isEmpty
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (model.isNotEmpty) TextSpan(text: model),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

// ── Por cobrar ─────────────────────────────────────────────────────────────

/// «$436.550 en 19 facturas de 11 clientes · la más antigua, hace 224 días».
({String total, String detail}) _owedSummary(
  List<CustomerDirectoryEntry> rows,
  List<Invoice> unassigned,
  DateTime today,
) {
  final assigned = rows.expand((row) => row.owedInvoices).toList();
  final invoices = [...assigned, ...unassigned];
  final total = invoices.fold(0.0, (sum, invoice) => sum + invoice.balance);
  final oldest = invoices.isEmpty
      ? null
      : invoices.map((invoice) => invoice.date).reduce(
            (a, b) => a.isBefore(b) ? a : b,
          );
  final facturas =
      invoices.length == 1 ? '1 factura' : '${invoices.length} facturas';
  final clientes = rows.length == 1 ? '1 cliente' : '${rows.length} clientes';
  final age = oldest == null
      ? ''
      : ' · la más antigua, hace ${calendarDaysBetween(oldest, today)} días';
  final detail = unassigned.isEmpty
      ? 'en $facturas de $clientes'
      : 'en $facturas: ${assigned.length} de $clientes y '
          '${unassigned.length} sin cliente';
  return (total: _money.format(total), detail: '$detail$age');
}

class _OwedSummary extends StatelessWidget {
  const _OwedSummary({
    required this.rows,
    required this.unassigned,
    required this.today,
  });

  final List<CustomerDirectoryEntry> rows;
  final List<Invoice> unassigned;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final summary = _owedSummary(rows, unassigned, today);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.hairline)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(
            summary.total,
            style: BikeModuleText.figure(context, size: 28).copyWith(
              fontWeight: FontWeight.w600,
              color: roles.warning.onContainer,
            ),
          ),
          Text(
            summary.detail,
            style: TextStyle(
                fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OwedSummaryText extends StatelessWidget {
  const _OwedSummaryText({
    required this.rows,
    required this.unassigned,
    required this.today,
  });

  final List<CustomerDirectoryEntry> rows;
  final List<Invoice> unassigned;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final summary = _owedSummary(rows, unassigned, today);
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '${summary.total}  ',
          style: BikeModuleText.figure(context, size: 22).copyWith(
            fontWeight: FontWeight.w600,
            color: roles.warning.onContainer,
          ),
        ),
        TextSpan(
          text: summary.detail,
          style: TextStyle(
              fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _OwedGrid extends StatelessWidget {
  const _OwedGrid({
    required this.customer,
    required this.invoices,
    required this.since,
    required this.owed,
    required this.trailing,
  });

  final Widget customer;
  final Widget invoices;
  final Widget since;
  final Widget owed;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 14, child: customer),
        const SizedBox(width: 20),
        Expanded(flex: 20, child: invoices),
        const SizedBox(width: 20),
        SizedBox(width: 170, child: since),
        const SizedBox(width: 16),
        SizedBox(width: 140, child: owed),
        const SizedBox(width: 12),
        SizedBox(width: 20, child: trailing),
      ],
    );
  }
}

class _OwedHeaderRow extends StatelessWidget {
  const _OwedHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = BikeModuleText.label(context);
    Text label(String text, {TextAlign align = TextAlign.start}) =>
        Text(text.toUpperCase(), style: style, textAlign: align);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 13, 24, 13),
        child: _OwedGrid(
          customer: label('Cliente'),
          invoices: label('Facturas'),
          since: label('Debe desde'),
          owed: label('Saldo', align: TextAlign.end),
          trailing: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// «FV-00948 · abonó $45.000 de $90.000», o los números de sus facturas.
String _owedInvoicesText(CustomerDirectoryEntry row) {
  final invoices = row.owedInvoices;
  if (invoices.length == 1) {
    final invoice = invoices.single;
    if (invoice.paidAmount > 0.5) {
      return '${invoice.invoiceNumber} · abonó '
          '${_money.format(invoice.paidAmount)} de '
          '${_money.format(invoice.total)}';
    }
    return invoice.invoiceNumber;
  }
  return invoices.map((invoice) => invoice.invoiceNumber).join(' · ');
}

/// «Bici en el taller · PG-00505» o «3 facturas».
String _owedSubtitle(CustomerDirectoryEntry row) {
  final job = row.workshopJob;
  if (job != null) {
    return job.jobNumber == null
        ? 'Bici en el taller'
        : 'Bici en el taller · ${job.jobNumber}';
  }
  final count = row.owedInvoices.length;
  return count == 1 ? '1 factura' : '$count facturas';
}

class _OwedWideRow extends StatelessWidget {
  const _OwedWideRow({
    required this.row,
    required this.today,
    required this.ago,
    required this.onOpen,
  });

  final CustomerDirectoryEntry row;
  final DateTime today;
  final String Function(DateTime) ago;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final name = row.customer.name.trim().isEmpty
        ? 'Cliente sin nombre'
        : row.customer.name.trim();
    final since = row.owedSince!;
    final days = calendarDaysBetween(since, today);
    return Semantics(
      button: true,
      label: '$name, debe ${_money.format(row.owed)}, '
          '${_owedInvoicesText(row)}, desde ${bikeFullDate(since)}',
      excludeSemantics: true,
      onTap: onOpen,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: _OwedGrid(
              customer: Row(
                children: [
                  _Avatar(name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(_owedSubtitle(row),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: roles.faintForeground)),
                      ],
                    ),
                  ),
                ],
              ),
              invoices: Text(
                _owedInvoicesText(row),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BikeModuleText.code(context),
              ),
              since: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(bikeFullDate(since),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  Text(
                    ago(since),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: days >= 90
                          ? roles.warning.onContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              owed: Text(
                _money.format(row.owed),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: roles.warning.onContainer,
                ),
              ),
              trailing: Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Teléfono ───────────────────────────────────────────────────────────────

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.row,
    required this.owedView,
    required this.divider,
    required this.today,
    required this.ago,
    required this.onOpen,
  });

  final CustomerDirectoryEntry row;
  final bool owedView;
  final bool divider;
  final DateTime today;
  final String Function(DateTime) ago;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final name = row.customer.name.trim().isEmpty
        ? 'Cliente sin nombre'
        : row.customer.name.trim();
    final phone = _phoneOf(row);
    final bike = row.mainBike;
    final job = row.workshopJob;
    final last = row.lastVisitAt;

    final String subtitle;
    final Widget trailing;
    if (owedView) {
      subtitle = _owedInvoicesText(row);
      final since = row.owedSince!;
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_money.format(row.owed),
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: roles.warning.onContainer)),
          Text(ago(since),
              style: TextStyle(fontSize: 12.5, color: roles.faintForeground)),
        ],
      );
    } else {
      final bikeText = bike == null ? null : _bikeName(bike);
      subtitle = [
        bikeText ?? (phone == null ? 'Sin bici ni teléfono' : null),
        phone ?? (bikeText == null ? null : 'sin teléfono'),
      ].whereType<String>().join(' · ');
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            last == null ? '—' : bikeShortDate(last, today: today),
            style: TextStyle(
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          if (job == null)
            Text('Al día',
                style: TextStyle(fontSize: 13, color: roles.faintForeground))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: BikeJobStatusDot(
                label: jobStatusLabel(job),
                color: jobStatusColor(job),
              ),
            ),
        ],
      );
    }

    return Semantics(
      button: true,
      label: owedView
          ? '$name, debe ${_money.format(row.owed)}, $subtitle'
          : [
              name,
              subtitle,
              if (job != null) 'en el taller, ${jobStatusLabel(job)}',
              if (last != null) 'última visita ${bikeFullDate(last)}',
            ].join(', '),
      excludeSemantics: true,
      onTap: onOpen,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: divider
                  ? Border(top: BorderSide(color: roles.hairline))
                  : null,
            ),
            child: Row(
              children: [
                _Avatar(name: name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: roles.faintForeground)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Las facturas por cobrar que no tienen cliente: se ven y abren la lista de
/// facturas, para asignarlas o cobrarlas allá.
class _UnassignedOwedRow extends StatelessWidget {
  const _UnassignedOwedRow({
    required this.invoices,
    required this.today,
    required this.ago,
    required this.compact,
    required this.onOpen,
  });

  final List<Invoice> invoices;
  final DateTime today;
  final String Function(DateTime) ago;
  final bool compact;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final total = invoices.fold(0.0, (sum, invoice) => sum + invoice.balance);
    final oldest = invoices
        .map((invoice) => invoice.date)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final numbers =
        invoices.map((invoice) => invoice.invoiceNumber).join(' · ');
    final title = invoices.length == 1
        ? '1 factura sin cliente'
        : '${invoices.length} facturas sin cliente';
    final icon = ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Icon(Icons.receipt_long_outlined,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
    final amount = Text(
      _money.format(total),
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: compact ? 14.5 : 16,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: roles.warning.onContainer,
      ),
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text(compact ? numbers : 'Ábrelas en Facturas para asignarlas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: roles.faintForeground)),
      ],
    );
    final content = compact
        ? Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(child: name),
              const SizedBox(width: 10),
              amount,
            ],
          )
        : _OwedGrid(
            customer: Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: name),
              ],
            ),
            invoices: Text(numbers,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BikeModuleText.code(context)),
            since: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(bikeFullDate(oldest),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
                Text(ago(oldest),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: calendarDaysBetween(oldest, today) >= 90
                            ? roles.warning.onContainer
                            : theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            owed: amount,
            trailing: Icon(Icons.chevron_right,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
          );
    return Semantics(
      button: true,
      label: '$title, ${_money.format(total)}, $numbers. Abre Facturas.',
      excludeSemantics: true,
      onTap: onOpen,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 64 : 66),
            padding: EdgeInsets.fromLTRB(
                compact ? 14 : 24, 10, compact ? 14 : 24, 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
