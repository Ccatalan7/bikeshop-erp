import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/global_search/global_search_entry.dart';
import '../../../shared/services/global_search/global_search_index.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/bike_finder_search.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/global_search/received_attachment_preview.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_edit_dock.dart';
import '../../../shared/widgets/vb_search_field.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_view_tabs.dart';
import '../../purchases/widgets/brand_mark.dart';
import '../../purchases/widgets/supplier_avatar.dart';
import '../models/brand_data_draft.dart';
import '../models/brand_directory.dart';
import '../services/brand_directory_service.dart';
import '../services/brand_logo_upload.dart';
import '../services/brand_service.dart';
import '../widgets/brand_directory_parts.dart';

/// Qué productos de la marca se ven.
enum BrandProductFilter {
  all,
  inStock,
  noStock;

  String get label => switch (this) {
        BrandProductFilter.all => 'Todos',
        BrandProductFilter.inStock => 'Con stock',
        BrandProductFilter.noStock => 'Sin stock',
      };

  bool includes(BrandPageProduct product) => switch (this) {
        BrandProductFilter.all => true,
        BrandProductFilter.inStock => product.hasStock,
        BrandProductFilter.noStock => !product.hasStock,
      };
}

/// La página de una marca (2026-11-15, lienzo UGbrLwz7St2n7hcP3cBvvf): sus
/// productos con foto, quién la trae y a quién se le compró, los archivos
/// recibidos que la nombran, los trabajos que usaron sus productos y sus
/// datos, que se editan ahí mismo. Se llega desde la lista de marcas, desde el
/// buscador («maxxis» → la marca) y desde la ficha de un proveedor.
///
/// Reemplaza a la «página de la marca» que era el formulario de editar: lo que
/// ese formulario hacía —datos, logo, proveedores— sigue acá. Una marca del
/// catálogo compartido se muestra igual, pero sus datos y su logo los cuida
/// Viñabike (RLS de `product_brands`).
class BrandPage extends StatefulWidget {
  const BrandPage({
    super.key,
    required this.brandId,
    this.source,
    this.brandService,
    this.startEditing = false,
    this.includeWorkspaceShell = true,
  });

  final String brandId;

  /// Para pruebas: de dónde lee la página.
  final BrandDirectorySource? source;

  /// Para pruebas: con qué guarda los datos de la marca.
  final BrandService? brandService;

  /// `/inventory/brands/:id/edit` abre la página con sus datos en edición.
  final bool startEditing;

  /// Para pruebas: la página sin el marco del ERP (menú y encabezado).
  final bool includeWorkspaceShell;

  @override
  State<BrandPage> createState() => _BrandPageState();
}

class _BrandPageState extends State<BrandPage> {
  static const int _productPage = 50;
  static const int _compactProducts = 8;
  static const int _railRecent = 5;
  static const String _fallbackRoute = '/inventory/brands';

  late final BrandDirectorySource _source =
      widget.source ?? BrandDirectoryService();
  BrandService? _brandServiceCache;
  BrandService get _brandService =>
      _brandServiceCache ??= widget.brandService ?? context.read<BrandService>();

  BrandPageData? _data;
  bool _loading = true;
  bool _notFound = false;
  String? _error;
  int _generation = 0;
  bool _startedFromRoute = false;

  BrandProductFilter _filter = BrandProductFilter.all;
  final TextEditingController _productSearch = TextEditingController();
  String _productQuery = '';
  int _visibleProducts = _productPage;
  int _compactVisibleProducts = _compactProducts;
  bool _allJobs = false;
  bool _allFiles = false;

  BrandDataDraft? _draft;
  final Map<BrandDataField, TextEditingController> _text = {};
  final Map<BrandDataField, FocusNode> _focus = {
    for (final field in BrandDataField.values) field: FocusNode(),
  };
  bool _saving = false;
  bool _showProblems = false;
  String? _dockNotice;
  bool _logoBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _productSearch.dispose();
    for (final controller in _text.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _error = null;
      if (_data == null) _loading = true;
    });
    try {
      final data = await _source.page(widget.brandId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _notFound = data == null;
        _loading = false;
      });
      if (data != null &&
          widget.startEditing &&
          !_startedFromRoute &&
          !data.shared) {
        _startedFromRoute = true;
        _startEdit();
      }
    } catch (error) {
      debugPrint('Brand page load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = 'No pudimos leer esta marca.';
        _loading = false;
      });
    }
  }

  // ── Volver ───────────────────────────────────────────────────────────────

  void _close() =>
      ReturnNavigation.close(context, fallbackRoute: _fallbackRoute);

  Future<void> _back() async {
    if (_saving) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(_leaveEdit);
    _close();
  }

  bool get _hasUnsavedChanges => (_draft?.changeCount ?? 0) > 0;

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: const Text('Los datos de la marca quedan como estaban.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ── Registros relacionados ───────────────────────────────────────────────

  /// Un registro relacionado se empuja en el espacio activo, para que su
  /// página vuelva a esta marca; al volver se relee por si cambió algo.
  Future<void> _pushRelated(String route) async {
    WorkspaceManager? workspace;
    try {
      workspace = context.read<WorkspaceManager>();
    } on ProviderNotFoundException {
      workspace = null;
    }
    if (workspace != null) {
      await workspace.pushActiveWorkspace<void>(route);
    } else {
      await context.push<void>(route);
    }
    if (mounted) await _load();
  }

  Future<void> _openProduct(BrandPageProduct product) =>
      _pushRelated('/inventory/products/${product.id}/edit');

  Future<void> _openSupplier(BrandPageSupplier supplier) =>
      _pushRelated('/purchases/suppliers/${supplier.supplierId}');

  Future<void> _openJob(BrandPageJob job) =>
      _pushRelated('/taller/pegas/${job.id}');

  Future<void> _newProduct() => _pushRelated(
        Uri(
          path: '/inventory/products/new',
          queryParameters: {'brand': widget.brandId},
        ).toString(),
      );

  Future<void> _openFile(GlobalSearchAttachment attachment) =>
      showReceivedAttachment(context, attachment);

  // ── Edición en su lugar ──────────────────────────────────────────────────

  void _startEdit([BrandDataField? focus]) {
    final data = _data;
    if (data == null || data.shared || _saving) return;
    if (_draft == null) {
      final draft = BrandDataDraft(data.brand);
      for (final field in BrandDataField.values) {
        if (field == BrandDataField.active) continue;
        final value = draft.text(field);
        final controller = _text[field];
        if (controller == null) {
          _text[field] = TextEditingController(text: value);
        } else {
          controller.text = value;
        }
      }
      setState(() {
        _draft = draft;
        _showProblems = false;
        _dockNotice = null;
      });
    }
    if (focus != null && focus != BrandDataField.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus[focus]?.requestFocus();
      });
    }
  }

  void _leaveEdit() {
    _draft = null;
    _saving = false;
    _showProblems = false;
    _dockNotice = null;
  }

  void _onText(BrandDataField field, String value) {
    final draft = _draft;
    if (draft == null) return;
    draft.setText(field, value);
    setState(() => _dockNotice = null);
  }

  void _onActive(bool value) {
    final draft = _draft;
    if (draft == null) return;
    draft.setActive(value);
    setState(() => _dockNotice = null);
  }

  void _undo(BrandDataField field) {
    final draft = _draft;
    if (draft == null) return;
    draft.revert(field);
    _text[field]?.text = draft.text(field);
    setState(() {});
  }

  Future<void> _cancelEdit() async {
    if (_saving) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(_leaveEdit);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final problems = draft.problems;
    if (problems.isNotEmpty) {
      setState(() {
        _showProblems = true;
        _dockNotice = 'Revisa ${problems.keys.map((f) => f.phrase).join(' y ')}'
            ' antes de guardar.';
      });
      _focus[problems.keys.first]?.requestFocus();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _dockNotice = null;
    });
    try {
      await _brandService.updateBrand(draft.toBrand());
      if (!mounted || !identical(_draft, draft)) return;
      await _load();
      if (!mounted) return;
      setState(_leaveEdit);
      messenger.showSnackBar(
        const SnackBar(content: Text('Datos de la marca guardados.')),
      );
    } catch (error) {
      debugPrint('Brand save failed: $error');
      if (!mounted || !identical(_draft, draft)) return;
      setState(() {
        _saving = false;
        _dockNotice = _saveProblem(error);
      });
    }
  }

  String _saveProblem(Object error) {
    final text = '$error'.replaceFirst('Exception: ', '');
    if (text.contains('Ya existe una marca')) {
      return 'Ya existe una marca con ese nombre. Usa otro, o abre esa.';
    }
    return 'No se pudo guardar. Revisa la conexión y vuelve a intentar; '
        'tus cambios siguen aquí.';
  }

  // ── Logo y eliminar ──────────────────────────────────────────────────────

  Future<void> _changeLogo({bool remove = false}) async {
    final data = _data;
    final id = data?.brand.id;
    if (data == null || id == null || data.shared || _logoBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _logoBusy = true);
    try {
      String? url;
      if (!remove) {
        url = await pickAndUploadBrandLogo(data.brand);
        if (url == null) return;
      }
      await _brandService.updateBrandLogo(id, url);
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(remove ? 'Logo quitado.' : 'Logo actualizado.')),
      );
    } catch (error) {
      debugPrint('Brand logo failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el logo. Vuelve a intentar.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _delete() async {
    final data = _data;
    final id = data?.brand.id;
    if (data == null || id == null || data.shared) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar ${data.brand.name}?'),
        content: const Text(
          'La marca deja de existir en el catálogo. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _brandService.deleteBrand(id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${data.brand.name} se eliminó.')),
      );
      _close();
    } catch (error) {
      debugPrint('Brand delete failed: $error');
      // El comando cuenta también los productos archivados, que la página no
      // muestra: se dice cuántos para que el «no» se entienda.
      final linked = RegExp(r'asociada a (\d+)').firstMatch('$error');
      messenger.showSnackBar(SnackBar(
        content: Text(linked != null
            ? 'No se puede eliminar: la usan '
                '${brandPlural(int.parse(linked.group(1)!), 'producto')}, '
                'contando los archivados.'
            : 'No se pudo eliminar. Vuelve a intentar.'),
      ));
    }
  }

  // ── Lo que se muestra ────────────────────────────────────────────────────

  List<BrandPageProduct> _productsShown(BrandPageData data) {
    final rows = [
      for (final product in data.products)
        if (_filter.includes(product)) product,
    ];
    // Sin tildes y por palabras: «neumatico 29» encuentra «Neumático Maxxis
    // Ardent 29x2.40».
    final words = normalizeBikeFinderSearch(_productQuery)
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return rows;
    return [
      for (final product in rows)
        if (words.every(normalizeBikeFinderSearch(
                '${product.name} ${product.sku ?? ''}')
            .contains))
          product,
    ];
  }

  int _countFor(BrandPageData data, BrandProductFilter filter) =>
      data.products.where(filter.includes).length;

  String _facts(BrandDirectoryEntry totals, {bool withProducts = true}) {
    final lastSale = totals.lastSale;
    return [
      if (withProducts) brandPlural(totals.products, 'producto'),
      '${brandCount(totals.units)} '
          '${totals.units == 1 ? 'unidad' : 'unidades'} en stock',
      if (totals.stockCost > 0) '${brandMoney(totals.stockCost)} a costo',
      '${brandCount(totals.sold12m)} vendidas en 12 meses',
      if (lastSale != null) 'última venta ${brandDayLabel(lastSale)}',
    ].join(' · ');
  }

  // ── Página ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    final data = _data;
    final title = data?.brand.name ?? 'Marca';
    final body = PopScope(
      canPop: !_hasUnsavedChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (!await _confirmDiscard() || !mounted) return;
        setState(_leaveEdit);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _close();
        });
      },
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: _buildBody(context, compact: compact),
      ),
    );
    if (!widget.includeWorkspaceShell) return Material(child: body);
    return MainLayout(
      title: title,
      onBackPressed: compact ? _back : null,
      compactHeader: compact
          ? MainLayoutCompactHeader(
              title: title,
              contextLine: data == null ? null : brandStockLine(data.totals),
              actions: [
                if (data != null)
                  IconButton(
                    tooltip: 'Nuevo producto de ${data.brand.name}',
                    onPressed: _newProduct,
                    icon: const Icon(Icons.add),
                  ),
                if (data != null && !data.shared && _draft == null)
                  IconButton(
                    tooltip: 'Editar datos de la marca',
                    onPressed: () => _startEdit(),
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            )
          : null,
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, {required bool compact}) {
    final data = _data;
    if (_loading && data == null) {
      return const Center(child: BrandedLoading());
    }
    if (data == null) return _buildMissing(context);
    final dock = _draft == null
        ? null
        : VbEditDock(
            changeCount: _draft?.changeCount ?? 0,
            saveLabel: 'Guardar datos',
            saveSemanticLabel: 'Guardar los datos de la marca',
            busy: _saving,
            notice: _dockNotice,
            onCancel: _cancelEdit,
            onSave: _save,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = !compact && constraints.maxWidth >= 1000;
        final content = wide
            ? _buildWide(context, data)
            : _buildNarrow(context, data, phone: compact);
        return VbEditDockLayer(dock: dock, child: content);
      },
    );
  }

  Widget _buildMissing(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _notFound
                  ? 'Esta marca no existe o ya no está en el catálogo.'
                  : (_error ?? 'No pudimos abrir esta marca.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (!_notFound)
                  VbButton(
                    label: 'Reintentar',
                    icon: Icons.refresh,
                    onPressed: _load,
                  ),
                VbButton(
                  label: 'Volver a marcas',
                  variant: VbButtonVariant.secondary,
                  onPressed: _close,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context, BrandPageData data) {
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, data, phone: false),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildProductsPane(context, data)),
              VerticalDivider(width: 1, thickness: 1, color: roles.hairline),
              SizedBox(
                width: 400,
                child: ListView(
                  padding: EdgeInsets.only(bottom: _draft == null ? 24 : 140),
                  children: _railSections(context, data, phone: false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(
    BuildContext context,
    BrandPageData data, {
    required bool phone,
  }) {
    final roles = VinabikeThemeRoles.of(context);
    final shown = _productsShown(data);
    final visible = shown.take(_compactVisibleProducts).toList();
    return ListView(
      padding: EdgeInsets.only(bottom: _draft == null ? 32 : 160),
      children: [
        _buildHeader(context, data, phone: phone),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        _buildProductToolbar(context, data, phone: true),
        if (visible.isEmpty)
          _buildProductsEmpty(context, data)
        else
          for (final product in visible)
            _ProductRow(
              product: product,
              compact: true,
              onOpen: () => _openProduct(product),
            ),
        if (shown.length > visible.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: VbButton(
              label: 'Ver ${brandCount(shown.length - visible.length)} '
                  'productos más',
              variant: VbButtonVariant.secondary,
              expand: true,
              onPressed: () =>
                  setState(() => _compactVisibleProducts += _productPage),
            ),
          ),
        const SizedBox(height: 8),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        ..._railSections(context, data, phone: phone),
      ],
    );
  }

  // ── Cabecera ─────────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    BrandPageData data, {
    required bool phone,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final factsStyle = TextStyle(
      fontSize: phone ? 13 : 14,
      height: 1.35,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (phone) {
      // En teléfono el nombre, cuántos productos y «Nuevo producto» van en la
      // barra (título, línea de contexto y «+»): el cuerpo sólo dice el resto
      // de las cifras y la lista empieza ~150 px antes. Repetir el nombre
      // grande abajo era cromo, no información.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            BrandMark(
              name: data.brand.name,
              logoUrl: data.brand.logoUrl,
              size: 44,
              solid: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                [
                  if (!data.brand.isActive) 'Inactiva',
                  _facts(data.totals, withProducts: false),
                ].join(' · '),
                style: factsStyle,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 20, 14),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          BrandMark(
            name: data.brand.name,
            logoUrl: data.brand.logoUrl,
            size: 56,
            solid: true,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          data.brand.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (!data.brand.isActive) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Inactiva',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(_facts(data.totals), style: factsStyle),
              ],
            ),
          ),
          const SizedBox(width: 16),
          VbButton(
            label: 'Nuevo producto',
            icon: Icons.add,
            onPressed: _newProduct,
          ),
        ],
      ),
    );
  }

  // ── Productos ────────────────────────────────────────────────────────────

  Widget _buildProductToolbar(
    BuildContext context,
    BrandPageData data, {
    required bool phone,
  }) {
    final roles = VinabikeThemeRoles.of(context);
    final tabs = VbViewTabs<BrandProductFilter>(
      tabs: [
        for (final filter in BrandProductFilter.values)
          VbViewTab(
            value: filter,
            label: filter.label,
            count: _countFor(data, filter),
          ),
      ],
      value: _filter,
      onChanged: (filter) => setState(() {
        _filter = filter;
        _visibleProducts = _productPage;
        _compactVisibleProducts = _compactProducts;
      }),
    );
    final search = VbSearchField(
      fieldKey: const ValueKey('brand-page-product-search'),
      controller: _productSearch,
      hint: 'Buscar en ${data.brand.name}',
      semanticLabel: 'Buscar productos de ${data.brand.name}',
      onChanged: (value) => setState(() {
        _productQuery = value.trim();
        _visibleProducts = _productPage;
        _compactVisibleProducts = _compactProducts;
      }),
      onClear: () => setState(() => _productQuery = ''),
    );
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: tabs,
          ),
          Divider(height: 1, thickness: 1, color: roles.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: search,
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: tabs,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 260, child: search),
        ],
      ),
    );
  }

  Widget _buildProductsPane(BuildContext context, BrandPageData data) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final shown = _productsShown(data);
    final visible = shown.take(_visibleProducts).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProductToolbar(context, data, phone: false),
        if (visible.isNotEmpty) const _ProductHeader(),
        Expanded(
          child: visible.isEmpty
              ? _buildProductsEmpty(context, data)
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: _draft == null ? 0 : 120),
                  itemCount: visible.length + 1,
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Text(
                              '${brandCount(visible.length)} de '
                              '${brandPlural(shown.length, 'producto')} · '
                              'lo más vendido primero',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.onSurfaceVariant),
                            ),
                            if (visible.length < shown.length)
                              VbButton(
                                label: 'Ver más',
                                variant: VbButtonVariant.secondary,
                                onPressed: () => setState(
                                    () => _visibleProducts += _productPage),
                              ),
                          ],
                        ),
                      );
                    }
                    final product = visible[index];
                    return _ProductRow(
                      product: product,
                      compact: false,
                      divider: roles.hairline,
                      onOpen: () => _openProduct(product),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductsEmpty(BuildContext context, BrandPageData data) {
    final scheme = Theme.of(context).colorScheme;
    final message = data.products.isEmpty
        ? 'Todavía no hay productos de ${data.brand.name}.'
        : _productQuery.isNotEmpty
            ? 'Ningún producto coincide con «$_productQuery».'
            : switch (_filter) {
                BrandProductFilter.inStock => 'Ningún producto tiene stock.',
                BrandProductFilter.noStock => 'Todos tienen stock.',
                BrandProductFilter.all => 'Sin productos.',
              };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
      ),
    );
  }

  // ── Riel: proveedores, archivos, trabajos y datos ────────────────────────

  List<Widget> _railSections(
    BuildContext context,
    BrandPageData data, {
    required bool phone,
  }) {
    final roles = VinabikeThemeRoles.of(context);
    final gutter = phone ? 16.0 : 20.0;
    Widget divider() => Divider(height: 1, thickness: 1, color: roles.hairline);
    return [
      _RailSection(
        title: 'Proveedores',
        count: data.suppliers.length,
        gutter: gutter,
        children: data.suppliers.isEmpty
            ? const [
                _RailNote(
                  text: 'Nadie la trae todavía. Se agrega desde la ficha del '
                      'proveedor, en su pestaña Marcas.',
                ),
              ]
            : [
                for (final supplier in data.suppliers)
                  _SupplierRow(
                    supplier: supplier,
                    onOpen: () => _openSupplier(supplier),
                  ),
              ],
      ),
      if (data.filesTotal > 0) ...[
        divider(),
        _buildFiles(context, data, gutter: gutter),
      ],
      divider(),
      _buildJobs(context, data, gutter: gutter),
      divider(),
      _buildData(context, data, gutter: gutter),
    ];
  }

  Widget _buildFiles(
    BuildContext context,
    BrandPageData data, {
    required double gutter,
  }) {
    final entries = [
      for (final row in data.recentFiles)
        if (globalSearchAttachmentEntry(row) case final entry?) entry,
    ];
    final shown = _allFiles ? entries : entries.take(_railRecent).toList();
    return _RailSection(
      title: 'Archivos recibidos',
      count: data.filesTotal,
      gutter: gutter,
      children: [
        for (final entry in shown)
          _FileRow(
            entry: entry,
            onOpen: entry.attachment == null
                ? null
                : () => _openFile(entry.attachment!),
          ),
        if (!_allFiles && entries.length > shown.length)
          _RailMore(
            label: 'Ver los ${brandCount(entries.length)} archivos',
            onTap: () => setState(() => _allFiles = true),
          ),
      ],
    );
  }

  Widget _buildJobs(
    BuildContext context,
    BrandPageData data, {
    required double gutter,
  }) {
    final shown =
        _allJobs ? data.recentJobs : data.recentJobs.take(_railRecent).toList();
    return _RailSection(
      title: 'En trabajos',
      count: data.jobsTotal,
      gutter: gutter,
      children: data.recentJobs.isEmpty
          ? [
              const _RailNote(
                  text: 'Ningún trabajo ha usado productos de esta marca.'),
            ]
          : [
              for (final job in shown)
                _JobRow(job: job, onOpen: () => _openJob(job)),
              if (!_allJobs && data.recentJobs.length > shown.length)
                _RailMore(
                  label: 'Ver los ${brandCount(data.recentJobs.length)} '
                      'trabajos',
                  onTap: () => setState(() => _allJobs = true),
                ),
              if (data.jobsTotal > data.recentJobs.length)
                _RailNote(
                  text: 'Se muestran los '
                      '${brandCount(data.recentJobs.length)} más recientes.',
                ),
            ],
    );
  }

  Widget _buildData(
    BuildContext context,
    BrandPageData data, {
    required double gutter,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final draft = _draft;
    final brand = data.brand;
    final editable = !data.shared;
    if (draft != null) {
      return _RailSection(
        title: 'Datos de la marca',
        gutter: gutter,
        children: [
          for (final field in const [
            BrandDataField.name,
            BrandDataField.website,
            BrandDataField.country,
            BrandDataField.description,
          ])
            _EditField(
              field: field,
              controller: _text[field]!,
              focusNode: _focus[field]!,
              changed: draft.isChanged(field),
              before: draft.before(field),
              problem: _showProblems ? draft.problems[field] : null,
              onChanged: (value) => _onText(field, value),
              onUndo: () => _undo(field),
            ),
          const SizedBox(height: 8),
          Text(
            'Estado',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          VbSegmented<bool>(
            groupLabel: 'Estado de la marca',
            value: draft.isActive,
            onChanged: _onActive,
            options: const [
              VbSegmentedOption(value: true, label: 'Activa'),
              VbSegmentedOption(value: false, label: 'Inactiva'),
            ],
          ),
          if (draft.isChanged(BrandDataField.active))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                draft.isActive
                    ? 'Vuelve a ofrecerse al crear productos.'
                    : 'Deja de ofrecerse al crear productos; conserva su '
                        'historia.',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      );
    }
    final website = brand.website?.trim() ?? '';
    final country = brand.country?.trim() ?? '';
    final description = brand.description?.trim() ?? '';
    return _RailSection(
      title: 'Datos de la marca',
      gutter: gutter,
      action: editable
          ? VbButton(
              label: 'Editar',
              variant: VbButtonVariant.text,
              icon: Icons.edit_outlined,
              onPressed: () => _startEdit(),
            )
          : null,
      children: [
        _DataRow(
          label: 'Sitio web',
          value: website.isEmpty ? null : website,
          addLabel: editable ? '+ Agregar sitio web' : null,
          onAdd: () => _startEdit(BrandDataField.website),
        ),
        _DataRow(
          label: 'País',
          value: country.isEmpty ? null : country,
          addLabel: editable ? '+ Agregar país' : null,
          onAdd: () => _startEdit(BrandDataField.country),
        ),
        _DataRow(
          label: 'Descripción',
          value: description.isEmpty ? null : description,
          addLabel: editable ? '+ Agregar descripción' : null,
          onAdd: () => _startEdit(BrandDataField.description),
        ),
        _DataRow(
          label: 'Logo',
          valueWidget: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              BrandMark(
                name: brand.name,
                logoUrl: brand.logoUrl,
                size: 32,
                solid: true,
              ),
              if (editable) ...[
                VbButton(
                  label: brand.logoUrl == null ? 'Agregar logo' : 'Cambiar logo',
                  variant: VbButtonVariant.text,
                  busy: _logoBusy,
                  onPressed: _logoBusy ? null : () => _changeLogo(),
                ),
                if (brand.logoUrl != null)
                  VbButton(
                    label: 'Quitar',
                    variant: VbButtonVariant.text,
                    onPressed: _logoBusy ? null : () => _changeLogo(remove: true),
                  ),
              ] else if (brand.logoUrl == null)
                Text(
                  'Sin logo',
                  style:
                      TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        _DataRow(
          label: 'Estado',
          value: brand.isActive ? 'Activa' : 'Inactiva',
        ),
        const SizedBox(height: 8),
        if (data.shared)
          const _RailNote(
            text: 'Marca del catálogo compartido: sus datos y su logo los '
                'cuida Viñabike.',
          )
        else
          // El botón dice por qué no se puede: no se repite debajo.
          Align(
            alignment: Alignment.centerLeft,
            child: VbButton(
              label: 'Eliminar marca',
              variant: VbButtonVariant.text,
              disabledReason: data.totals.products > 0
                  ? 'Tiene productos: primero muévelos a otra marca.'
                  : null,
              onPressed: data.totals.products > 0 ? null : _delete,
            ),
          ),
      ],
    );
  }
}

// ── Piezas de la página ────────────────────────────────────────────────────

class _ProductHeader extends StatelessWidget {
  const _ProductHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    TextStyle style(bool active) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: active ? scheme.onSurface : scheme.onSurfaceVariant,
        );
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('PRODUCTO', style: style(false))),
          SizedBox(
            width: _ProductRow.stockWidth,
            child: Text('STOCK', textAlign: TextAlign.right, style: style(false)),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: _ProductRow.priceWidth,
            child:
                Text('PRECIO', textAlign: TextAlign.right, style: style(false)),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: _ProductRow.soldWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text('VENDIDAS 12 M',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(true)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_downward, size: 13, color: scheme.onSurface),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.compact,
    required this.onOpen,
    this.divider,
  });

  static const double stockWidth = 64;
  static const double priceWidth = 92;

  /// Cabe «VENDIDAS 12 M» con su flecha: con 112 se cortaba en «VENDIDAS 12 …».
  static const double soldWidth = 136;

  final BrandPageProduct product;
  final bool compact;
  final VoidCallback onOpen;
  final Color? divider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final stock = product.stock ?? 0;
    final stockColor = stock < 0
        ? roles.warning.accent
        : stock == 0
            ? roles.faintForeground
            : scheme.onSurface;
    final price = product.price;
    final identity = Row(
      children: [
        BrandProductPhoto(url: product.image, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                compact
                    ? [
                        if (product.sku != null) 'SKU ${product.sku}',
                        stock > 0
                            ? '${brandCount(stock)} en stock'
                            : stock < 0
                                ? 'stock ${brandCount(stock)}'
                                : 'sin stock',
                        if (price != null) brandMoney(price),
                      ].join(' · ')
                    : (product.sku == null ? 'Sin SKU' : 'SKU ${product.sku}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final figures = TextStyle(
      fontSize: 14,
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      button: true,
      label: 'Abrir ${product.name}',
      child: InkWell(
        key: ValueKey('brand-product-${product.id}'),
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 20, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: divider ?? roles.hairline),
            ),
          ),
          child: compact
              ? Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          brandCount(product.sold12m),
                          style: figures.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'vendidas',
                          style: TextStyle(
                              fontSize: 11.5, color: roles.faintForeground),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    SizedBox(
                      width: stockWidth,
                      child: Text(
                        brandCount(stock),
                        textAlign: TextAlign.right,
                        style: figures.copyWith(color: stockColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: priceWidth,
                      child: Text(
                        price == null ? '—' : brandMoney(price),
                        textAlign: TextAlign.right,
                        style: figures,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: soldWidth,
                      child: Text(
                        brandCount(product.sold12m),
                        textAlign: TextAlign.right,
                        style: figures.copyWith(
                          color: product.sold12m > 0
                              ? scheme.onSurface
                              : roles.faintForeground,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.title,
    required this.children,
    required this.gutter,
    this.count,
    this.action,
  });

  final String title;
  final int? count;
  final List<Widget> children;
  final double gutter;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final count = this.count;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: roles.faintForeground,
                    ),
                  ),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    brandCount(count),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const Spacer(),
                if (action != null) action!,
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _RailNote extends StatelessWidget {
  const _RailNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RailMore extends StatelessWidget {
  const _RailMore({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: VbButton(
          label: label,
          variant: VbButtonVariant.text,
          onPressed: onTap,
        ),
      );
}

/// Una fila del riel: su cara, dos líneas y lo que abre.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    this.onOpen,
    this.trailing,
    this.subtitleLines = 1,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback? onOpen;
  final Widget? trailing;
  final int subtitleLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: subtitleLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    if (onOpen == null) return row;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: row,
      ),
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.supplier, required this.onOpen});

  final BrandPageSupplier supplier;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastPurchase = supplier.lastPurchase;
    final bought = supplier.purchases > 0
        ? [
            brandPlural(supplier.purchases, 'compra'),
            if (supplier.units > 0)
              '${brandCount(supplier.units)} '
                  '${supplier.units == 1 ? 'unidad' : 'unidades'}',
            if (lastPurchase != null)
              'última ${brandDayLabel(lastPurchase)}',
          ].join(' · ')
        : 'La trae · sin compras todavía';
    final subtitle = [
      if (supplier.official) 'Representante oficial',
      if (!supplier.isActive) 'Inactivo',
      bought,
    ].join(' · ');
    return _RailRow(
      leading: SupplierAvatar(
        name: supplier.name,
        size: 34,
        imageUrl: supplier.imageUrl,
      ),
      title: supplier.name,
      subtitle: subtitle,
      semanticLabel: 'Abrir el proveedor ${supplier.name}',
      onOpen: onOpen,
      trailing: Icon(Icons.chevron_right, size: 18, color: scheme.outline),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.entry, required this.onOpen});

  final GlobalSearchEntry entry;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final attachment = entry.attachment;
    final isPdf = attachment?.isPdf ?? false;
    return _RailRow(
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: roles.danger.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isPdf
            ? Text(
                'PDF',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: roles.danger.onAccent,
                ),
              )
            : Icon(entry.resolvedIcon, size: 18, color: roles.danger.onAccent),
      ),
      title: entry.title,
      subtitle: entry.subtitle ?? '',
      // De quién vino y cuándo: dos líneas, para que la fecha no se corte.
      subtitleLines: 2,
      semanticLabel: 'Abrir el archivo ${entry.title}',
      onOpen: onOpen,
      trailing: onOpen == null
          ? null
          : Icon(Icons.chevron_right,
              size: 18, color: Theme.of(context).colorScheme.outline),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.onOpen});

  final BrandPageJob job;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final delivered = job.deliveredAt;
    final arrival = job.arrivalDate;
    final when = delivered != null
        ? 'entregado ${brandDayLabel(delivered)}'
        : [
            if (job.statusLabel != null) job.statusLabel!,
            if (arrival != null) 'llegó ${brandDayLabel(arrival)}',
          ].join(' · ');
    final subtitle = [
      if (job.customerName != null) job.customerName!,
      if (when.isNotEmpty) when,
      if (job.firstItem != null)
        job.lines > 1
            ? '${job.firstItem!} y ${job.lines - 1} más'
            : job.firstItem!,
    ].join(' · ');
    return _RailRow(
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: roles.avatarC,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.pedal_bike_outlined,
            size: 18, color: roles.onAvatarC),
      ),
      title: job.bike == null ? job.number : '${job.number} · ${job.bike}',
      subtitle: subtitle,
      semanticLabel: 'Abrir el trabajo ${job.number}',
      onOpen: onOpen,
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.addLabel,
    this.onAdd,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;

  /// «+ Agregar país»: un dato vacío se completa ahí mismo.
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final Widget content = valueWidget ??
        (value != null
            ? SelectableText(
                value!,
                style: TextStyle(fontSize: 14, color: scheme.onSurface),
              )
            : addLabel != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: VbButton(
                      label: addLabel!,
                      variant: VbButtonVariant.text,
                      onPressed: onAdd,
                    ),
                  )
                : Text(
                    'Sin dato',
                    style: TextStyle(fontSize: 14, color: roles.faintForeground),
                  ));
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.field,
    required this.controller,
    required this.focusNode,
    required this.changed,
    required this.before,
    required this.problem,
    required this.onChanged,
    required this.onUndo,
  });

  final BrandDataField field;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool changed;
  final String before;
  final String? problem;
  final ValueChanged<String> onChanged;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final multiline = field == BrandDataField.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: ValueKey('brand-edit-${field.name}'),
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            minLines: multiline ? 2 : 1,
            maxLines: multiline ? 5 : 1,
            keyboardType: field == BrandDataField.website
                ? TextInputType.url
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: field.label,
              hintText: switch (field) {
                BrandDataField.website => 'https://www.maxxis.com',
                BrandDataField.country => 'Ej. Taiwán',
                BrandDataField.description => 'Qué hace y para qué se usa',
                _ => null,
              },
              errorText: problem,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (changed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      before.isEmpty ? 'Nuevo' : 'Antes: $before',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: roles.faintForeground,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onUndo,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 36),
                      foregroundColor: scheme.primary,
                    ),
                    child: const Text('Deshacer'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
