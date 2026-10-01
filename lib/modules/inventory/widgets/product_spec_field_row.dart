import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';

/// What the short line under a spec control is saying.
enum ProductSpecFieldNoteTone {
  /// A fact about the value (its unit, where it came from).
  neutral,

  /// Something to finish: a missing answer or a field waiting on another.
  pending,

  /// The value contradicts its requirements and blocks saving.
  blocking,
}

/// One datum of a product's technical sheet.
///
/// The owner could not read the old sheet (2026-10-01): every control carried
/// its own 11 px label and a paragraph of help, all full width, so a chain's
/// pitch got a 1,300 px box and the page read as one grey wall. Here the name
/// of the datum is the strongest text of the row and sits in its own column
/// (above the control on narrow hosts); the explanation lives behind the info
/// icon; and the only text under the control is a short [note] when something
/// is missing or wrong. A [compact] control keeps the width its value needs.
class ProductSpecFieldRow extends StatelessWidget {
  const ProductSpecFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.info,
    this.note,
    this.noteTone = ProductSpecFieldNoteTone.neutral,
    this.compact = true,
    this.dependent = false,
  });

  final String label;
  final Widget child;

  /// The long explanation: what the datum means and how to read it.
  final String? info;
  final String? note;
  final ProductSpecFieldNoteTone noteTone;

  /// Short values (a number, a choice, yes/no) do not stretch to the row.
  final bool compact;

  /// The datum refines the one right above it (a measurement and the
  /// reference it is measured from); it is drawn hanging from it.
  final bool dependent;

  /// Under this width the label goes above the control.
  static const double sideBySideMinWidth = 560;
  static const double labelColumnWidth = 210;
  static const double compactControlMaxWidth = 340;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);

    final labelBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              height: 1.3,
            ),
          ),
        ),
        if (info != null && info!.trim().isNotEmpty)
          Tooltip(
            message: info!,
            triggerMode: TooltipTriggerMode.tap,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 250),
            showDuration: const Duration(seconds: 8),
            constraints: const BoxConstraints(maxWidth: 360),
            child: Semantics(
              button: true,
              label: 'Qué significa $label',
              child: SizedBox(
                width: 28,
                height: 22,
                child: Icon(Icons.info_outline,
                    size: 16, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );

    final noteColor = switch (noteTone) {
      ProductSpecFieldNoteTone.neutral => scheme.onSurfaceVariant,
      ProductSpecFieldNoteTone.pending => roles.warning.onContainer,
      ProductSpecFieldNoteTone.blocking => scheme.error,
    };
    final noteLine = note == null || note!.trim().isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (noteTone != ProductSpecFieldNoteTone.neutral)
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: noteTone == ProductSpecFieldNoteTone.blocking
                            ? scheme.error
                            : roles.warning.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Flexible(
                  child: Text(
                    note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: noteColor,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          );

    final control = compact
        ? Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: compactControlMaxWidth),
              child: child,
            ),
          )
        : child;

    final body = LayoutBuilder(builder: (context, constraints) {
      final sideBySide = constraints.maxWidth >= sideBySideMinWidth;
      if (!sideBySide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            labelBlock,
            const SizedBox(height: 8),
            control,
            if (noteLine != null) noteLine,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: labelBlock,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [control, if (noteLine != null) noteLine],
            ),
          ),
        ],
      );
    });

    if (!dependent) return body;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: roles.hairline, width: 2)),
      ),
      child: body,
    );
  }
}
