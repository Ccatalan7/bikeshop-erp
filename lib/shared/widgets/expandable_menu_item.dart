import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ExpandableMenuItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final List<MenuSubItem> subItems;
  final String currentLocation;
  final bool enabled;
  final bool isExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const ExpandableMenuItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.subItems,
    required this.currentLocation,
    this.enabled = true,
    this.isExpanded = false,
    this.onExpansionChanged,
  });

  MenuSubItem? _resolveSelectedSubItem(String location) {
    for (final subItem in subItems) {
      if (location == subItem.route) {
        return subItem;
      }
    }

    MenuSubItem? bestMatch;
    for (final subItem in subItems) {
      final prefix = '${subItem.route}/';
      if (location.startsWith(prefix)) {
        if (bestMatch == null || subItem.route.length > bestMatch.route.length) {
          bestMatch = subItem;
        }
      }
    }
    return bestMatch;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedSubItem = _resolveSelectedSubItem(currentLocation);
    final isAnySubItemSelected = selectedSubItem != null;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              onTap: enabled
                  ? () => onExpansionChanged?.call(!isExpanded)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isAnySubItemSelected
                      ? theme.primaryColor.withOpacity(0.1)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      isAnySubItemSelected ? activeIcon : icon,
                      size: 20,
                      color: enabled
                          ? (isAnySubItemSelected
                              ? theme.primaryColor
                              : theme.colorScheme.onSurface.withOpacity(0.7))
                          : theme.disabledColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isAnySubItemSelected ? FontWeight.w600 : FontWeight.normal,
                          color: enabled
                              ? (isAnySubItemSelected
                                  ? theme.primaryColor
                                  : theme.colorScheme.onSurface)
                              : theme.disabledColor,
                        ),
                      ),
                    ),
                    RotatedBox(
                      quarterTurns: isExpanded ? 2 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: enabled
                            ? theme.colorScheme.onSurface.withOpacity(0.5)
                            : theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isExpanded)
          Column(
            children: subItems.map((subItem) {
              final isSelected = selectedSubItem?.route == subItem.route;
              return Container(
                margin: const EdgeInsets.only(left: 36, right: 8, bottom: 2),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    onTap: enabled
                        ? () {
                            if (!isSelected) {
                              context.go(subItem.route);
                            }
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: isSelected
                            ? theme.primaryColor.withOpacity(0.08)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            subItem.icon,
                            size: 16,
                            color: isSelected
                                ? theme.primaryColor
                                : theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              subItem.title,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected
                                    ? theme.primaryColor
                                    : theme.colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class MenuSubItem {
  final IconData icon;
  final String title;
  final String route;

  const MenuSubItem({
    required this.icon,
    required this.title,
    required this.route,
  });
}
