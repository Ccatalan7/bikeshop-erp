import 'package:flutter/material.dart';

import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_short_select.dart';

/// A catalogue observation has three states. An unanswered field cannot look
/// like a confirmed negative, and changing it does not save the product.
class ProductSpecBooleanField extends StatelessWidget {
  const ProductSpecBooleanField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.allowedValues,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final String? helperText;
  final String? errorText;
  final Set<bool>? allowedValues;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicWidth(
              child: VbShortSelect.labelled(
            context,
            label,
            VbSegmented<bool?>(
              value: value,
              groupLabel: label,
              options: [
                const VbSegmentedOption(value: null, label: 'Sin dato'),
                VbSegmentedOption(
                    value: true,
                    label: 'Sí',
                    enabled:
                        allowedValues == null || allowedValues!.contains(true),
                    disabledReason: 'Los requisitos elegidos no admiten Sí.'),
                VbSegmentedOption(
                    value: false,
                    label: 'No',
                    enabled:
                        allowedValues == null || allowedValues!.contains(false),
                    disabledReason: 'Los requisitos elegidos no admiten No.'),
              ],
              onChanged: onChanged,
              groupDisabledReason: onChanged == null
                  ? helperText ?? 'Completa primero los requisitos.'
                  : null,
            ),
          )),
          if (errorText != null ||
              (helperText != null && onChanged != null)) ...[
            const SizedBox(height: 5), // I-01 label/control/help stack.
            Text(errorText ?? helperText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: errorText != null
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      );
}
