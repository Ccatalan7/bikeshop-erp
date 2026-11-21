import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/contact_greeting.dart';

/// «Cómo saludarle»: cada forma de saludar a la vista con el nombre que da
/// («María», «María José», «José»), el texto propio cuando se elige
/// «Personalizado» y el saludo tal como lo va a leer la persona.
///
/// Es el control de la ficha del contacto de proveedor y de la hoja del
/// cliente; el cliente elige lo mismo en «Mi cuenta» de la tienda. Las
/// opciones se eligen mirando el nombre, no la etiqueta, y cada nombre sale
/// una sola vez (`contactGreetingChoices`).
class ContactGreetingPicker extends StatelessWidget {
  const ContactGreetingPicker({
    super.key,
    required this.fullName,
    required this.style,
    required this.customController,
    required this.onStyleChanged,
    this.customFocusNode,
    this.styles = ContactGreetingStyle.values,
    this.keyPrefix = 'contact-greeting',
    this.enabled = true,
    this.showLabel = true,
  });

  /// El nombre con que se calcula cada opción, tal como está escrito ahora.
  final String fullName;
  final ContactGreetingStyle style;
  final TextEditingController customController;
  final FocusNode? customFocusNode;
  final ValueChanged<ContactGreetingStyle> onStyleChanged;

  /// Las opciones que admite la ficha: un contacto de proveedor tiene tres.
  final List<ContactGreetingStyle> styles;

  /// Prefijo de las llaves de prueba: `<prefijo>-option-<estilo>` para cada
  /// opción, `-custom` para el campo del texto propio y `-preview`.
  /// (La opción y el campo de «Personalizado» compartían `-custom`.)
  final String keyPrefix;
  final bool enabled;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choices = contactGreetingChoices(fullName, styles: styles);
    final shown = shownContactGreetingStyle(fullName, style, styles: styles);
    final greeting = contactGreetingName(
      fullName: fullName,
      style: style,
      customName: customController.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabel) ...[
          Text(
            'Cómo saludarle',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Semantics(
          container: true,
          label: 'Cómo saludarle',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in choices)
                Semantics(
                  label: choice.style == ContactGreetingStyle.custom
                      ? null
                      : '${choice.style.label}: ${choice.greeting}',
                  child: ChoiceChip(
                    key: ValueKey(
                      '$keyPrefix-option-${choice.style.wireValue}',
                    ),
                    label: Text(
                      choice.style == ContactGreetingStyle.custom
                          ? ContactGreetingStyle.custom.label
                          : choice.greeting,
                    ),
                    avatar: choice.style == ContactGreetingStyle.custom
                        ? const Icon(Icons.edit_outlined, size: 16)
                        : null,
                    tooltip: choice.style.label,
                    selected: shown == choice.style,
                    showCheckmark: false,
                    onSelected:
                        enabled ? (_) => onStyleChanged(choice.style) : null,
                  ),
                ),
            ],
          ),
        ),
        if (style == ContactGreetingStyle.custom) ...[
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('$keyPrefix-custom'),
            controller: customController,
            focusNode: customFocusNode,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            maxLength: contactGreetingCustomMaxLength,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\n\r\t]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Nombre en el saludo',
              hintText: 'Majo, Don Pedro…',
              counterText: '',
            ),
            validator: (value) => normalizeContactGreeting(value ?? '').isEmpty
                ? 'Escribe cómo saludarle'
                : null,
          ),
        ],
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            greeting.isEmpty
                ? 'Escribe el nombre para ver el saludo.'
                : 'Le llega: «Hola $greeting, buen día.»',
            key: ValueKey('$keyPrefix-preview'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
