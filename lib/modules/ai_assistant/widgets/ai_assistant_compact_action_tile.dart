import 'package:flutter/material.dart';

import '../models/ai_assistant_turn_contracts.dart';

/// A compact, navigation-only assistant result.
///
/// Conversation surfaces use this instead of repeating the richer preview
/// cards used for governed write proposals. It keeps one clear destination in
/// view and leaves secondary filter evidence in normal text, never as a wall
/// of decorative chips.
class AIAssistantCompactActionTile extends StatelessWidget {
  const AIAssistantCompactActionTile({
    super.key,
    required this.card,
    required this.onTap,
    this.includeFilterSummary = true,
  });

  final AIAssistantActionCard card;
  final VoidCallback onTap;
  final bool includeFilterSummary;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if ((card.subtitle ?? '').isNotEmpty) card.subtitle!,
      if (includeFilterSummary) ...card.chips,
    ].join(' · ');
    final cardKey = 'ai-action-card-${card.kind}-${card.destination.name}';

    return Semantics(
      button: true,
      label: '${card.ctaLabel}: ${card.title}',
      child: ListTile(
        key: ValueKey<String>(cardKey),
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: Icon(
          card.inventoryListRef == null
              ? Icons.arrow_outward_rounded
              : Icons.inventory_2_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(card.title),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: const Icon(Icons.arrow_forward_rounded),
        onTap: onTap,
      ),
    );
  }
}
