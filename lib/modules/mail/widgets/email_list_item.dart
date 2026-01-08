import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/zoho_email.dart';

class EmailListItem extends StatelessWidget {
  final ZohoEmail email;
  final bool isSelected;
  final VoidCallback onTap;

  const EmailListItem({
    super.key,
    required this.email,
    required this.isSelected,
    required this.onTap,
  });

  Color _getAvatarColor(String name) {
    if (name.isEmpty) return Colors.grey;
    final colors = [
      Colors.red.shade400,
      Colors.pink.shade400,
      Colors.purple.shade400,
      Colors.deepPurple.shade400,
      Colors.indigo.shade400,
      Colors.blue.shade400,
      Colors.teal.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.brown.shade400,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final emailDate = DateTime(date.year, date.month, date.day);

    if (emailDate == today) {
      return DateFormat('HH:mm').format(date);
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('E').format(date); // Day name like Mon, Tue
    } else {
      return DateFormat('d MMM').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Typography styles
    final senderStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: email.isRead ? FontWeight.normal : FontWeight.bold,
      color: colorScheme.onSurface,
    );

    final subjectStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
      color: colorScheme.onSurface,
    );

    final snippetStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withOpacity(0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: _getAvatarColor(email.senderEmail),
                foregroundColor: Colors.white,
                child: Text(
                  email.senderName.isNotEmpty
                      ? email.senderName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender and Date Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            email.senderName,
                            style: senderStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(email.receivedTime),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: email.isRead
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                            fontWeight: email.isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Subject
                    Text(
                      email.subject,
                      style: subjectStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Snippet
                    Text(
                      email.summary ?? email.subject,
                      style: snippetStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
