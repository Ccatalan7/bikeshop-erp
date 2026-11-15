import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// El buscador de una lista: relleno neutro, 40 de alto, lupa y «Limpiar».
///
/// Nació como el buscador de Correo (2026-11-08, el mismo en sus dos vistas) y
/// pasó acá cuando Marcas lo necesitó (2026-11-15): dos listas que se buscan
/// igual se ven igual.
class VbSearchField extends StatelessWidget {
  const VbSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onClear,
    this.fieldKey,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final Key? fieldKey;

  /// Lo que se busca, dicho para un lector de pantalla («Buscar marcas»).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final field = SizedBox(
      height: 40,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          key: fieldKey,
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: roles.neutral.container,
            hintText: hint,
            hintStyle:
                TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            prefixIcon:
                Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      controller.clear();
                      onClear?.call();
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
    final label = semanticLabel;
    return label == null
        ? field
        : Semantics(textField: true, label: label, child: field);
  }
}
