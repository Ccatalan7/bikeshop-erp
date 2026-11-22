import 'package:flutter/material.dart';

import '../../inventory/models/brand_directory.dart';
import '../../inventory/services/brand_directory_service.dart';

/// The brands a menu item can lead to (2026-11-21, «Navegación» › «Marca»):
/// every active brand of the shop and of the shared catalog, with its logo
/// and how many products it has in the store, the ones on sale first. A
/// search narrows the list. With [multiple] a tap adds or removes a brand
/// (a new item adds every brand checked, in the order they were checked);
/// without it a tap chooses the one brand.
///
/// The logo is the one «Inventario › Marcas» keeps: a brand without one
/// shows its initials here and in the store's menu.
class NavigationBrandPicker extends StatefulWidget {
  const NavigationBrandPicker({
    super.key,
    required this.selected,
    required this.multiple,
    required this.onToggle,
    this.source,
  });

  /// The chosen brands' ids, in the order they were chosen.
  final List<String> selected;
  final bool multiple;
  final ValueChanged<BrandDirectoryEntry> onToggle;

  /// Where the brands come from; the shop's brand directory by default.
  final BrandDirectorySource? source;

  static const searchKey = ValueKey<String>('navigation-brand-search');
  static ValueKey<String> rowKey(String id) =>
      ValueKey<String>('navigation-brand-$id');

  @override
  State<NavigationBrandPicker> createState() => _NavigationBrandPickerState();
}

class _NavigationBrandPickerState extends State<NavigationBrandPicker> {
  final _search = TextEditingController();
  late Future<List<BrandDirectoryEntry>> _brands;

  @override
  void initState() {
    super.initState();
    _brands = _load();
  }

  Future<List<BrandDirectoryEntry>> _load() async {
    final all = await (widget.source ?? BrandDirectoryService()).directory();
    return [
      for (final brand in all)
        if (brand.isActive) brand,
    ]..sort((a, b) {
        final byWeb = b.onWeb.compareTo(a.onWeb);
        return byWeb != 0
            ? byWeb
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: NavigationBrandPicker.searchKey,
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Buscar marca',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          widget.multiple
              ? 'Toca las marcas que quieres en el menú, en el orden en '
                  'que van. Cada una lleva a sus productos.'
              : 'La marca a cuyos productos lleva este enlace.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: FutureBuilder<List<BrandDirectoryEntry>>(
              future: _brands,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No se pudieron leer las marcas. Cierra y vuelve a '
                      'abrir el enlace.',
                      style: TextStyle(color: scheme.error),
                    ),
                  );
                }
                final brands = snapshot.data;
                if (brands == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final query = _search.text.trim().toLowerCase();
                final shown = [
                  for (final brand in brands)
                    if (query.isEmpty ||
                        brand.name.toLowerCase().contains(query))
                      brand,
                ];
                if (shown.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Ninguna marca se llama así.'),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (context, index) => _row(shown[index]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BrandDirectoryEntry brand) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final position = widget.selected.indexOf(brand.id);
    final chosen = position >= 0;
    final detail = brand.onWeb > 0
        ? '${brand.onWeb} en la tienda'
        : 'Sin productos en la tienda';
    return ListTile(
      key: NavigationBrandPicker.rowKey(brand.id),
      dense: true,
      selected: chosen,
      leading: _BrandLogo(brand: brand),
      title: Text(brand.name),
      subtitle: Text(detail),
      trailing: !chosen
          ? null
          : widget.multiple
              ? CircleAvatar(
                  radius: 12,
                  backgroundColor: scheme.primary,
                  child: Text(
                    '${position + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimary,
                    ),
                  ),
                )
              : Icon(Icons.check_circle, color: scheme.primary),
      onTap: () => widget.onToggle(brand),
    );
  }
}

/// The brand's logo on a white tile, as the store's menu shows it, or its
/// initials.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.brand});

  final BrandDirectoryEntry brand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = brand.logoUrl?.trim() ?? '';
    final initials = brand.name.trim().isEmpty
        ? '?'
        : brand.name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: 48,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // The logos are drawn for a light ground, in both themes.
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: logo.isEmpty
          ? Text(
              initials,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            )
          : Image.network(
              logo,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text(
                initials,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
    );
  }
}
