import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// Opens the store's rules, read as sentences.
Future<void> showCatalogRules(
    BuildContext context, CatalogWebController controller) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 700) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: CatalogRulesForm(controller: controller),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CatalogRulesForm(controller: controller),
        ),
      ),
    ),
  );
}

/// The rules of the store as the owner says them. What protects the
/// business (consumables, price over cost) is shown locked.
class CatalogRulesForm extends StatefulWidget {
  const CatalogRulesForm({super.key, required this.controller});

  final CatalogWebController controller;

  @override
  State<CatalogRulesForm> createState() => _CatalogRulesFormState();
}

class _CatalogRulesFormState extends State<CatalogRulesForm> {
  late CatalogRules _rules = widget.controller.rules;
  bool _saving = false;

  bool get _dirty {
    final saved = widget.controller.rules.toSettings();
    final now = _rules.toSettings();
    return saved.keys.any((key) => saved[key] != now[key]);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.controller.saveRules(_rules);
      if (!mounted) return;
      showCatalogMessage(context, 'Reglas guardadas: la tienda ya las sigue.');
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// How many would stop selling with the draft rules.
  int _wouldStop() {
    var count = 0;
    for (final item in widget.controller.goods) {
      if (item.state != CatalogItemState.selling) continue;
      if (_rules.requireImage && !item.hasPhoto ||
          _rules.requireWebName && !item.hasWebName ||
          _rules.requireDescription && !item.hasDescription ||
          _rules.requireBrand && item.brandId == null) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stop = _wouldStop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Reglas de la tienda',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Valen para todo: la tienda, el buscador, Google y el checkout. Lo que protege al negocio no se puede apagar.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _Sentence(
          parts: [
            const Text('Los productos agotados'),
            DropdownButton<String>(
              value: _rules.stockPolicy,
              onChanged: (value) =>
                  setState(() => _rules = _rules.copyWith(stockPolicy: value)),
              items: const [
                DropdownMenuItem(
                  value: 'available_only',
                  child: Text('conservan su ficha, fuera de los listados'),
                ),
                DropdownMenuItem(
                  value: 'all',
                  child: Text('aparecen en los listados con «Agotado»'),
                ),
              ],
            ),
          ],
          hint:
              'Recomendado: conservan su ficha. Mantienen su lugar en Google y vuelven solos a venta.',
        ),
        _Sentence(
          parts: [
            const Text('Para salir a la venta, un producto necesita'),
            _Check(
              label: 'foto',
              value: _rules.requireImage,
              onChanged: (v) =>
                  setState(() => _rules = _rules.copyWith(requireImage: v)),
            ),
            _Check(
              label: 'nombre para la tienda',
              value: _rules.requireWebName,
              onChanged: (v) =>
                  setState(() => _rules = _rules.copyWith(requireWebName: v)),
            ),
            _Check(
              label: 'descripción',
              value: _rules.requireDescription,
              onChanged: (v) => setState(
                  () => _rules = _rules.copyWith(requireDescription: v)),
            ),
            _Check(
              label: 'marca',
              value: _rules.requireBrand,
              onChanged: (v) =>
                  setState(() => _rules = _rules.copyWith(requireBrand: v)),
            ),
          ],
          hint: stop > 0
              ? 'Con esto dejarían de venderse $stop productos que hoy están a la venta.'
              : null,
          warn: stop > 0,
        ),
        _Sentence(
          parts: [
            const Text('Un producto en una categoría que no se muestra'),
            DropdownButton<bool>(
              value: _rules.requireVisibleCategory,
              onChanged: (value) => setState(() =>
                  _rules = _rules.copyWith(requireVisibleCategory: value)),
              items: const [
                DropdownMenuItem(
                    value: false,
                    child: Text('se vende igual (se encuentra buscando)')),
                DropdownMenuItem(
                    value: true, child: Text('no sale a la venta')),
              ],
            ),
          ],
        ),
        const _Locked(
            text:
                'El precio cubre el costo con IVA, salvo una liquidación con fecha de término.'),
        const _Locked(
            text:
                'Un servicio a \$0 no se publica, salvo que diga «A cotizar».'),
        const _Locked(
          text: 'Los consumibles del taller nunca se venden online.',
          detail:
              'Para vender uno en la web, se convierte en producto de venta desde su ficha.',
          workshop: true,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            VbButton(
              label: 'Cancelar',
              variant: VbButtonVariant.text,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            VbButton(
              label: 'Guardar reglas',
              busy: _saving,
              onPressed: _dirty ? _save : null,
              disabledReason: _dirty ? null : 'No hay cambios',
            ),
          ],
        ),
      ],
    );
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence({required this.parts, this.hint, this.warn = false});

  final List<Widget> parts;
  final String? hint;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: roles.hairline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyLarge,
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: parts,
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: warn
                      ? roles.warning.accent
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: warn ? FontWeight.w600 : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.text, this.detail, this.workshop = false});

  final String text;
  final String? detail;
  final bool workshop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final foreground = workshop ? scheme.onTertiaryContainer : scheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: workshop ? scheme.tertiaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: roles.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: foreground)),
                if (detail != null)
                  Text(detail!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: foreground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
