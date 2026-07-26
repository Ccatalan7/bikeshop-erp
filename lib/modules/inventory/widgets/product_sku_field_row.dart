import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_viewport.dart';

/// Responsive presentation for the canonical product SKU controller and
/// generation command.
///
/// Phone layouts stack the command below the field so neither control is
/// compressed. Tablet and desktop layouts keep the familiar inline workflow.
class ProductSkuFieldRow extends StatelessWidget {
  const ProductSkuFieldRow({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.buttonLabel,
    required this.isGenerating,
    required this.onGenerate,
    this.helperText,
    this.validator,
  });

  static const fieldKey = ValueKey<String>('product-sku-field');
  static const generateButtonKey =
      ValueKey<String>('product-sku-generate-button');

  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final String? helperText;
  final String buttonLabel;
  final bool isGenerating;
  final VoidCallback onGenerate;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final isPhone = ResponsiveViewport.widthOf(context) <
        ResponsiveViewport.phoneMaxExclusive;

    return LayoutBuilder(
      builder: (context, constraints) {
        final field = TextFormField(
          key: fieldKey,
          controller: controller,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText,
            helperText: helperText,
          ),
          validator: validator,
        );
        final generateButton = OutlinedButton(
          key: generateButtonKey,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: isGenerating ? null : onGenerate,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isGenerating)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.auto_fix_high_outlined, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  buttonLabel,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );

        if (isPhone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 12),
              generateButton,
            ],
          );
        }

        final buttonWidth = (constraints.maxWidth * 0.38).clamp(168.0, 220.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 12),
            SizedBox(
              width: buttonWidth,
              child: generateButton,
            ),
          ],
        );
      },
    );
  }
}
