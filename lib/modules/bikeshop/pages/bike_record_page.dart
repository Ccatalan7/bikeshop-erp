import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/return_navigation.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../crm/services/customer_service.dart';
import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';
import '../widgets/bike_record_panel.dart';
import 'bike_form_dialog.dart';

/// La página propia de una bici (`/taller/bicicletas/:id`).
///
/// La abre el directorio de bicicletas con `push` y vuelve con
/// [ReturnNavigation.close]: el directorio conserva su búsqueda, su vista y
/// su desplazamiento. La ficha es la misma [BikeRecordPanel] de la pestaña
/// Bicicletas del cliente.
class BikeRecordPage extends StatefulWidget {
  const BikeRecordPage({super.key, required this.bikeId});

  final String bikeId;

  @override
  State<BikeRecordPage> createState() => _BikeRecordPageState();
}

class _BikeRecordPageState extends State<BikeRecordPage> {
  static const _fallbackRoute = '/taller/bicicletas';

  BikeRecordSnapshot? _snapshot;
  String _ownerName = '';
  bool _isLoading = true;
  bool _notFound = false;
  String? _error;

  /// Sólo la carga más reciente publica: una anterior que termina después
  /// (guardar dos ediciones seguidas) no pisa la ficha nueva.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    bool isCurrent() => mounted && generation == _loadGeneration;
    setState(() {
      _isLoading = _snapshot == null;
      _error = null;
    });
    try {
      final snapshot = await context
          .read<BikeshopService>()
          .getBikeRecordSnapshot(widget.bikeId);
      if (!isCurrent()) return;
      if (snapshot == null) {
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
        return;
      }
      final owner = await context
          .read<CustomerService>()
          .getCustomerById(snapshot.bike.customerId);
      if (!isCurrent()) return;
      setState(() {
        _snapshot = snapshot;
        _ownerName = owner?.name ?? '';
        _notFound = false;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Bike record page load failed: $error');
      if (!isCurrent()) return;
      setState(() {
        _error = 'No pudimos abrir esta bicicleta.';
        _isLoading = false;
      });
    }
  }

  /// La ficha, para preguntarle antes de salir si quedó a medio editar.
  final GlobalKey _panelKey = GlobalKey();

  Future<void> _close() async {
    final Object? guard = _panelKey.currentState;
    if (guard is BikeRecordPanelLeaveGuard && !await guard.confirmLeave()) {
      return;
    }
    if (!mounted) return;
    ReturnNavigation.close(context, fallbackRoute: _fallbackRoute);
  }

  /// La bici se edita en su lugar; el formulario queda para un panel que
  /// no lo sabe hacer.
  Future<void> _edit() async {
    final Object? editor = _panelKey.currentState;
    if (editor is BikeRecordPanelEditor) {
      await editor.startBikeEdit();
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final saved = await showDialog<Bike?>(
      context: context,
      builder: (_) => BikeFormDialog(
        customerId: snapshot.bike.customerId,
        bike: snapshot.bike,
      ),
    );
    if (saved != null && mounted) await _load();
  }

  void _newJob() {
    final bike = _snapshot?.bike;
    if (bike == null) return;
    final route = Uri(
      path: '/taller/pegas/nueva',
      queryParameters: {
        'customer_id': bike.customerId,
        if (bike.id != null) 'bike_id': bike.id!,
      },
    ).toString();
    context.push(route);
  }

  void _openOwner() {
    final customerId = _snapshot?.bike.customerId.trim();
    if (customerId == null || customerId.isEmpty) return;
    context.push('/clientes/$customerId');
  }

  String get _title {
    final bike = _snapshot?.bike;
    if (bike == null) return 'Bicicleta';
    final name = [bike.brand, bike.model]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    return name.isEmpty ? 'Bicicleta' : name;
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    return MainLayout(
      title: _title,
      onBackPressed: compact ? _close : null,
      compactHeader: compact
          ? MainLayoutCompactHeader(
              title: _title,
              contextLine: _ownerName.isEmpty ? null : _ownerName,
              actions: [
                if (_snapshot != null)
                  IconButton(
                    tooltip: 'Editar bicicleta',
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            )
          : null,
      body: _buildBody(context, compact: compact),
    );
  }

  Widget _buildBody(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: BrandedLoading());
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _notFound
                    ? 'Esta bicicleta no existe o ya no está registrada.'
                    : (_error ?? 'No pudimos abrir esta bicicleta.'),
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
                    label: 'Volver a bicicletas',
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
    final panel = BikeRecordPanel(
      key: _panelKey,
      snapshot: snapshot,
      ownerName: _ownerName,
      onEdit: _edit,
      onNewJob: _newJob,
      onClose: _close,
      onOpenOwner: _openOwner,
      closeLabel: 'Bicicletas',
      showBackRow: !compact,
      onRecordSaved: _load,
    );
    final error = _error;
    if (error == null) return panel;
    // Falló la recarga después de editar: la ficha que se ve es la anterior
    // y se dice, con la forma de reintentar.
    return Column(
      children: [
        Material(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 20, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$error Lo que ves puede no tener el último cambio.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _load,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onErrorContainer,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: panel),
      ],
    );
  }
}
