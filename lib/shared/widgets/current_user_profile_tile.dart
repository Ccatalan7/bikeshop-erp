import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/current_user_profile.dart';
import '../services/current_user_profile_service.dart';

class CurrentUserProfileTile extends StatelessWidget {
  const CurrentUserProfileTile({
    required this.onTap,
    this.selected = false,
    this.compact = false,
    super.key,
  });

  final VoidCallback onTap;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<CurrentUserProfileService>().profile;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 8,
        vertical: compact ? 2 : 4,
      ),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const ValueKey('erp-profile-navigation-tile'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  _NavigationAvatar(profile: profile),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.displayName ?? 'Mi perfil',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: selected
                                        ? colors.primary
                                        : colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile?.email ?? 'Cuenta y seguridad',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationAvatar extends StatelessWidget {
  const _NavigationAvatar({required this.profile});

  final CurrentUserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 18,
      backgroundColor: colors.primaryContainer,
      child: profile == null
          ? Icon(
              Icons.person_outline,
              size: 20,
              color: colors.onPrimaryContainer,
            )
          : Text(
              profile!.initials,
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final photoUrl = profile?.employee?.photoUrl;
    if (photoUrl == null) return fallback;

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
