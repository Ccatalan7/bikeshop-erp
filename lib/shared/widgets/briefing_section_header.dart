import 'package:flutter/material.dart';

/// The heading every section of the daily briefing opens with: a short bar in
/// the section's tone, its name, and what the section wants at its right edge
/// (a count, a control, nothing).
///
/// One piece for all of them, so a section that lives in its own file reads
/// as part of the same panel.
class BriefingSectionHeader extends StatelessWidget {
  const BriefingSectionHeader({
    super.key,
    required this.title,
    required this.accent,
    this.trailing,
  });

  final String title;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = this.trailing;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          // Its own node: without the boundary the heading flag climbs to the
          // section and swallows every plain text in it.
          child: Semantics(
            container: true,
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}
