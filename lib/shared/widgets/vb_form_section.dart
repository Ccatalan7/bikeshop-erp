import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Form composition of GUÍA GENERAL F-02/F-04 and S-04 panel anatomy.
/// Source: DesignSync get_file copy dated 2026-08-27, read 2026-09-05;
/// evidence: docs/development/product-specs-research-2026-09-05/implementation-plan.md.
/// Panel radius 10, hairline 1, body 16 x 18, section title 13.5/600.
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.ibmPlexSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }
}
