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
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.35)
              : colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
            left: BorderSide(
              color: isUnread
                  ? colorScheme.primary
                  : (isSelected ? colorScheme.primary : Colors.transparent),
              width: isUnread || isSelected ? 3 : 0,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 18,
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 17,
                      height: 17,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: _getProviderLogo(email.providerId),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
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
                              fontWeight:
                                  isUnread ? FontWeight.w700 : FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(email.receivedTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isUnread
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            fontWeight:
                                isUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            email.subject.isEmpty
                                ? '(sin asunto)'
                                : email.subject,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  isUnread ? FontWeight.w600 : FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (email.hasAttachment) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.attach_file,
                            size: 15,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    if (email.summary != null &&
                        email.summary!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email.summary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 5),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
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
