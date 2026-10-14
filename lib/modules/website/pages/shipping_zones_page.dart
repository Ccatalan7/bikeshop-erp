import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/clp_amount_input_formatter.dart';
import '../models/shipping_zone.dart';
import '../services/shipping_zones_service.dart';
import '../widgets/website_admin_ui.dart';

/// «Envíos»: what home delivery costs by destination (owner, 2026-10-14:
/// «revisa cómo lo hacen nuestros competidores más importantes y haz lo
/// mismo» — they charge at checkout by destination and size). Each zone is
/// a set of regions with its price bands by purchase amount (the size stand-
/// in: the catalog has no weights). The checkout quotes with the region of
/// the address; pickup in store is always free.
class ShippingZonesPage extends StatefulWidget {
  const ShippingZonesPage({super.key, this.embedded = false, this.store});

  final bool embedded;
  final ShippingZonesStore? store;

  @override
  State<ShippingZonesPage> createState() => _ShippingZonesPageState();
}

class _BandDraft {
  _BandDraft(ShippingBand band)
      : upTo = TextEditingController(text: _clp(band.maxOrderGross)),
        price = TextEditingController(text: _clp(band.shippingGross)),
        minDays = TextEditingController(text: '${band.minDays}'),
        maxDays = TextEditingController(text: '${band.maxDays}');

  final TextEditingController upTo;
  final TextEditingController price;
  final TextEditingController minDays;
  final TextEditingController maxDays;

  List<TextEditingController> get controllers =>
      [upTo, price, minDays, maxDays];

  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

class _ZoneDraft {
  _ZoneDraft(ShippingZone zone)
      : name = TextEditingController(text: zone.name),
        regions = {...zone.regionCodes},
        bands = [for (final band in zone.bands) _BandDraft(band)];

  final TextEditingController name;
  final Set<String> regions;
  final List<_BandDraft> bands;

  void dispose() {
    name.dispose();
    for (final band in bands) {
      band.dispose();
    }
  }
}

String _clp(int? value) {
  if (value == null) return '';
  final digits = '$value';
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

int? _whole(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.parse(digits);
}

class _ShippingZonesPageState extends State<ShippingZonesPage> {
  late final ShippingZonesStore _store = widget.store ?? ShippingZonesService();
  final List<_ZoneDraft> _zones = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final zone in _zones) {
      zone.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final zones = await _store.load();
      if (!mounted) return;
      _replace(zones);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron leer las zonas: $error';
      });
    }
  }

  void _replace(List<ShippingZone> zones) {
    for (final zone in _zones) {
      zone.dispose();
    }
    _zones
      ..clear()
      ..addAll(zones.map(_ZoneDraft.new));
    for (final zone in _zones) {
      _listen(zone);
    }
    _dirty = false;
  }

  void _listen(_ZoneDraft zone) {
    zone.name.addListener(_changed);
    for (final band in zone.bands) {
      for (final controller in band.controllers) {
        controller.addListener(_changed);
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() => _dirty = true);
  }

  /// The zones as they would be saved: each band starts where the previous
  /// one ends, and the last one has no cap.
  List<ShippingZone> get _edited => [
        for (final zone in _zones)
          ShippingZone(
            name: zone.name.text,
            regionCodes: [
              for (final region in chileanShippingRegions)
                if (zone.regions.contains(region.code)) region.code,
            ],
            bands: () {
              final bands = <ShippingBand>[];
              var start = 0;
              for (final (index, band) in zone.bands.indexed) {
                final last = index == zone.bands.length - 1;
                final upTo = last ? null : _whole(band.upTo.text);
                bands.add(ShippingBand(
                  minOrderGross: start,
                  maxOrderGross: upTo,
                  shippingGross: _whole(band.price.text) ?? -1,
                  minDays: _whole(band.minDays.text) ?? 0,
                  maxDays: _whole(band.maxDays.text) ?? 0,
                ));
                start = upTo ?? start;
              }
              return bands;
            }(),
          ),
      ];

  String? get _problem => shippingZonesProblem(_edited);

  Map<String, String> get _owners => {
        for (final zone in _zones)
          for (final code in zone.regions) code: zone.name.text.trim(),
      };

  Future<void> _save() async {
    final zones = _edited;
    if (shippingZonesProblem(zones) != null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _store.save(zones);
      if (!mounted) return;
      _replace(saved);
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Envíos guardados: el checkout ya cobra con estas tarifas.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is PostgrestException ? error.message : '$error';
      });
    }
  }

  void _addZone() {
    final previous = _zones.lastOrNull;
    final zone = _ZoneDraft(ShippingZone(
      name: 'Zona ${_zones.length + 1}',
      regionCodes: const [],
      bands: [
        if (previous == null)
          const ShippingBand(minOrderGross: 0, shippingGross: 0)
        else
          for (final band in _edited.last.bands)
            ShippingBand(
              minOrderGross: band.minOrderGross,
              maxOrderGross: band.maxOrderGross,
              shippingGross: band.shippingGross < 0 ? 0 : band.shippingGross,
              minDays: band.minDays,
              maxDays: band.maxDays,
            ),
      ],
    ));
    _listen(zone);
    setState(() {
      _zones.add(zone);
      _dirty = true;
    });
  }

  void _removeZone(_ZoneDraft zone) {
    setState(() {
      _zones.remove(zone);
      zone.dispose();
      _dirty = true;
    });
  }

  void _addBand(_ZoneDraft zone) {
    final last = zone.bands.last;
    final band = _BandDraft(ShippingBand(
      minOrderGross: 0,
      shippingGross: _whole(last.price.text) ?? 0,
      minDays: _whole(last.minDays.text) ?? 3,
      maxDays: _whole(last.maxDays.text) ?? 7,
    ));
    for (final controller in band.controllers) {
      controller.addListener(_changed);
    }
    setState(() {
      zone.bands.add(band);
      _dirty = true;
    });
  }

  void _removeBand(_ZoneDraft zone, _BandDraft band) {
    setState(() {
      zone.bands.remove(band);
      band.dispose();
      if (zone.bands.isNotEmpty) zone.bands.last.upTo.clear();
      _dirty = true;
    });
  }

  void _toggleRegion(_ZoneDraft zone, String code, bool selected) {
    setState(() {
      selected ? zone.regions.add(code) : zone.regions.remove(code);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final problem = _dirty ? _problem : null;
    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Envíos',
      description: 'Lo que cuesta el despacho según la región de destino.',
      actions: [
        if (_dirty)
          TextButton(
            onPressed: _saving ? null : _load,
            child: const Text('Descartar'),
          ),
        FilledButton.icon(
          key: const ValueKey('shipping-zones-save'),
          onPressed: _dirty && problem == null && !_saving ? _save : null,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 19),
          label: const Text('Guardar'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : WebsiteAdminBody(
              maxWidth: 1080,
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null || problem != null) ...[
                    _Notice(
                      text: _error ?? problem!,
                      danger: _error != null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _Summary(zones: _zones, owners: _owners),
                  const SizedBox(height: 16),
                  for (final zone in _zones) ...[
                    _ZoneCard(
                      key: ObjectKey(zone),
                      zone: zone,
                      owners: _owners,
                      canRemove: _zones.length > 1,
                      onRemove: () => _removeZone(zone),
                      onToggleRegion: (code, selected) =>
                          _toggleRegion(zone, code, selected),
                      onAddBand: () => _addBand(zone),
                      onRemoveBand: (band) => _removeBand(zone, band),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('shipping-zones-add'),
                      onPressed: _saving ? null : _addZone,
                      icon:
                          const Icon(Icons.add_location_alt_outlined, size: 19),
                      label: const Text('Agregar zona'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.danger});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final tone = danger ? roles.danger : roles.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        children: [
          Icon(
            danger ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 20,
            color: tone.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tone.onContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How the checkout uses the zones, and which regions it does not ship to.
class _Summary extends StatelessWidget {
  const _Summary({required this.zones, required this.owners});

  final List<_ZoneDraft> zones;
  final Map<String, String> owners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final uncovered = [
      for (final region in chileanShippingRegions)
        if (!owners.containsKey(region.code)) region.name,
    ];
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        );
    return WebsiteAdminSurface(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(
            Icons.local_shipping_outlined,
            'El checkout cobra el despacho con la región de la dirección y el '
            'monto de la compra. Lo pagado al transportista queda como gasto '
            'al registrar el despacho.',
          ),
          line(Icons.storefront_outlined, 'Retiro en tienda: sin costo.'),
          if (uncovered.isNotEmpty)
            line(
              Icons.block_outlined,
              'Sin zona: ${uncovered.join(', ')}. El checkout dice que por '
              'ahora no se despacha ahí.',
            ),
        ],
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    super.key,
    required this.zone,
    required this.owners,
    required this.canRemove,
    required this.onRemove,
    required this.onToggleRegion,
    required this.onAddBand,
    required this.onRemoveBand,
  });

  final _ZoneDraft zone;
  final Map<String, String> owners;
  final bool canRemove;
  final VoidCallback onRemove;
  final void Function(String code, bool selected) onToggleRegion;
  final VoidCallback onAddBand;
  final ValueChanged<_BandDraft> onRemoveBand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final label = theme.textTheme.labelMedium?.copyWith(
      color: muted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );
    return WebsiteAdminSurface(
      accent: theme.colorScheme.primary,
      padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 14, phone ? 12 : 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: zone.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la zona',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Quitar zona',
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('REGIONES', style: label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final region in chileanShippingRegions)
                () {
                  final owner = owners[region.code];
                  final mine = zone.regions.contains(region.code);
                  final taken = owner != null && !mine;
                  final chip = FilterChip(
                    label: Text(region.name),
                    selected: mine,
                    showCheckmark: false,
                    onSelected: taken
                        ? null
                        : (selected) => onToggleRegion(region.code, selected),
                  );
                  return taken
                      ? Tooltip(message: 'Está en «$owner»', child: chip)
                      : chip;
                }(),
            ],
          ),
          const SizedBox(height: 16),
          Text('TARIFAS POR MONTO DE LA COMPRA', style: label),
          const SizedBox(height: 4),
          for (final (index, band) in zone.bands.indexed)
            _BandRow(
              band: band,
              start: () {
                var start = 0;
                for (final previous in zone.bands.take(index)) {
                  start = _whole(previous.upTo.text) ?? start;
                }
                return start;
              }(),
              last: index == zone.bands.length - 1,
              canRemove: zone.bands.length > 1,
              onRemove: () => onRemoveBand(band),
              phone: phone,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: zone.bands.length < 10 ? onAddBand : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar tramo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.band,
    required this.start,
    required this.last,
    required this.canRemove,
    required this.onRemove,
    required this.phone,
  });

  final _BandDraft band;
  final int start;
  final bool last;
  final bool canRemove;
  final VoidCallback onRemove;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget amount(TextEditingController controller, String label) => TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: const [ClpAmountInputFormatter()],
          decoration: InputDecoration(
            labelText: label,
            prefixText: r'$ ',
            isDense: true,
          ),
        );
    Widget days(TextEditingController controller, String label) => TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: InputDecoration(labelText: label, isDense: true),
        );

    final from = Text(
      last
          ? 'Desde ${ChileanUtils.formatCurrency(start.toDouble())} · sin tope'
          : 'Desde ${ChileanUtils.formatCurrency(start.toDouble())}',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: muted,
        fontWeight: FontWeight.w600,
      ),
    );
    final upTo = last
        ? const SizedBox.shrink()
        : amount(band.upTo, 'Hasta (sin incluir)');
    final price = amount(band.price, 'Despacho');
    final window = Row(
      children: [
        Expanded(child: days(band.minDays, 'Días mín.')),
        const SizedBox(width: 8),
        Expanded(child: days(band.maxDays, 'Días máx.')),
      ],
    );
    final remove = IconButton(
      tooltip: 'Quitar tramo',
      onPressed: canRemove ? onRemove : null,
      icon: const Icon(Icons.close_rounded, size: 19),
    );

    if (phone) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Expanded(child: from), remove]),
            if (!last) ...[upTo, const SizedBox(height: 8)],
            price,
            const SizedBox(height: 8),
            window,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 200, child: from),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: upTo),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: price),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: window),
          const SizedBox(width: 4),
          remove,
        ],
      ),
    );
  }
}
