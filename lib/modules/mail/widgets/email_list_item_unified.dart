import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/email_provider.dart';

/// Email list item for unified inbox - shows provider badge
class EmailListItemUnified extends StatelessWidget {
  final Email email;
  final bool isSelected;
  final VoidCallback onTap;

  const EmailListItemUnified({
    super.key,
    required this.email,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUnread = !email.isRead;

    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withOpacity(0.3)
                : (isUnread ? colorScheme.surface : null),
            border: Border(
              bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.3)),
              // Left border for unread
              left: isUnread
                  ? const BorderSide(color: Color(0xFF0078D4), width: 4)
                  : BorderSide.none,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider badge + Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isUnread
                          ? _getProviderColor(email.providerId)
                          : colorScheme.surfaceContainerHighest,
                      child: Text(
                        email.senderName.isNotEmpty
                            ? email.senderName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: isUnread
                              ? Colors.white
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Provider badge
                    // Provider badge
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 1,
                          ),
                          // No shadow for cleaner look
                        ),
                        child: Center(
                          child: _getProviderLogo(email.providerId),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              email.senderName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: isUnread ? Colors.black : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatDate(email.receivedTime),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isUnread
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: isUnread ? FontWeight.w600 : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.subject,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isUnread ? FontWeight.w600 : FontWeight.normal,
                          color: isUnread ? const Color(0xFF0078D4) : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.summary != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          email.summary!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (email.hasAttachment)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.attach_file,
                        size: 16, color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getProviderColor(String providerId) {
    switch (providerId) {
      case 'gmail':
        return Colors.red;
      case 'zoho':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  Widget _getProviderLogo(String providerId) {
    switch (providerId) {
      case 'gmail':
        return Image.asset(
          'assets/icons/gmail_logo.webp',
          fit: BoxFit.contain,
        );
      case 'zoho':
        return Image.asset(
          'assets/icons/zoho_logo.png',
          fit: BoxFit.contain,
        );
      default:
        return const Icon(Icons.email_outlined, size: 14, color: Colors.grey);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final emailDate = DateTime(date.year, date.month, date.day);

    if (emailDate == today) {
      return DateFormat('HH:mm').format(date);
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('E', 'es').format(date);
    } else {
      return DateFormat('d MMM', 'es').format(date);
    }
  }
}
