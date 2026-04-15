import 'package:flutter/material.dart';

import '../services/service_wizard_service.dart';

List<ServiceQuestionOption> serviceQuestionOptionsFromMap(
  Map<String, String> options,
) {
  return options.entries
      .map(
        (entry) => ServiceQuestionOption(
          value: entry.key,
          label: entry.value,
        ),
      )
      .toList(growable: false);
}

class BikeshopSingleSelectDropdownField extends StatelessWidget {
  final List<ServiceQuestionOption> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? labelText;
  final IconData? icon;
  final bool includeEmptyOption;
  final String emptyOptionLabel;
  final String? hintText;

  const BikeshopSingleSelectDropdownField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelText,
    this.icon,
    this.includeEmptyOption = false,
    this.emptyOptionLabel = 'Sin definir',
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        prefixIcon: icon == null ? null : Icon(icon),
      ),
      hint: hintText == null ? null : Text(hintText!),
      items: [
        if (includeEmptyOption)
          DropdownMenuItem<String>(
            value: null,
            child: Text(emptyOptionLabel),
          ),
        ...options.map(
          (option) => DropdownMenuItem<String>(
            value: option.value,
            child: Text(option.label),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class BikeshopMultiSelectPickerField extends StatelessWidget {
  final List<ServiceQuestionOption> options;
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final String dialogTitle;
  final String placeholder;

  const BikeshopMultiSelectPickerField({
    super.key,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    required this.dialogTitle,
    this.placeholder = 'Selecciona una o más opciones',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOpen = options.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: !canOpen
          ? null
          : () async {
              final updatedValues = await showBikeshopMultiSelectPicker(
                context: context,
                title: dialogTitle,
                options: options,
                selectedValues: selectedValues,
              );
              if (updatedValues == null) {
                return;
              }
              onChanged(updatedValues);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        isEmpty: selectedValues.isEmpty,
        child: Text(
          buildBikeshopMultiSelectSummary(
            options: options,
            values: selectedValues,
            placeholder: placeholder,
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selectedValues.isEmpty
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

String buildBikeshopMultiSelectSummary({
  required List<ServiceQuestionOption> options,
  required List<String> values,
  String placeholder = 'Selecciona una o más opciones',
}) {
  if (values.isEmpty) {
    return placeholder;
  }

  final orderedLabels = options
      .where((opt) => values.contains(opt.value))
      .map((opt) => opt.label)
      .toList(growable: false);
  if (orderedLabels.isEmpty) {
    return placeholder;
  }
  if (orderedLabels.length <= 2) {
    return orderedLabels.join(', ');
  }
  return '${orderedLabels.take(2).join(', ')} +${orderedLabels.length - 2}';
}

Future<List<String>?> showBikeshopMultiSelectPicker({
  required BuildContext context,
  required String title,
  required List<ServiceQuestionOption> options,
  required List<String> selectedValues,
}) async {
  if (options.isEmpty) {
    return null;
  }

  final workingSelection = selectedValues.toSet();
  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setModalState) {
          return AlertDialog(
            title: Text(title),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options.map((opt) {
                    final isSelected = workingSelection.contains(opt.value);
                    return CheckboxListTile(
                      value: isSelected,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(opt.label),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) {
                        setModalState(() {
                          if (checked == true) {
                            workingSelection.add(opt.value);
                          } else {
                            workingSelection.remove(opt.value);
                          }
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setModalState(() => workingSelection.clear());
                },
                child: const Text('Limpiar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  options
                      .where((opt) => workingSelection.contains(opt.value))
                      .map((opt) => opt.value)
                      .toList(growable: false),
                ),
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      );
    },
  );
}
