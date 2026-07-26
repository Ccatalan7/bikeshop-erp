import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_viewport.dart';

class ResponsiveInvoiceSectionCard extends StatelessWidget {
  const ResponsiveInvoiceSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usesPhoneLayout = ResponsiveViewport.widthOf(context) <
        ResponsiveViewport.phoneMaxExclusive;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(usesPhoneLayout ? 16 : 20),
      ),
      child: Padding(
        padding: usesPhoneLayout
            ? const EdgeInsets.fromLTRB(14, 14, 14, 18)
            : const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(
                    icon,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: usesPhoneLayout ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!usesPhoneLayout && trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
            if (usesPhoneLayout && trailing != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                key: const ValueKey('invoice-section-phone-trailing'),
                width: double.infinity,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: trailing,
                ),
              ),
            ],
            SizedBox(height: usesPhoneLayout ? 14 : 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
