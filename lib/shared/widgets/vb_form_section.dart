import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A titled panel of a form (the technical sheet's sections).
///
/// The title is the strongest text of the panel: 16/600 above 14/600 field
/// names (2026-10-01). At 13.5 it read weaker than the data it groups once
/// the sheet's field names got their own column, and the page lost its
/// hierarchy. Panel radius 10, hairline 1, body 18 x 20.
/// This is shared form containment, not a product-specific visual variant.
class VbFormSection extends StatelessWidget {
  const VbFormSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          header: true,
          child: Text(title,
              style: GoogleFonts.ibmPlexSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: scheme.onSurface)),
        ),
        const SizedBox(height: 18),
        ...children,
      ]),
    );
  }
}
