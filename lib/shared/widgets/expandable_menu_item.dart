import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/workspace_manager.dart';
import 'modern_context_menu.dart';

class ExpandableMenuItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final List<MenuSubItem> subItems;
  final String currentLocation;
  final bool enabled;
  final bool isExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final bool isSingleItem;
  final int badgeCount; // For unread notification badge
  final Map<String, int> subItemBadgeCounts;
  final VoidCallback? onBadgeTap;
  final void Function(String route)?
      onNavigate; // Optional custom navigation handler

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
    this.isSingleItem = false,
    this.badgeCount = 0,
    this.subItemBadgeCounts = const {},
    this.onBadgeTap,
    this.onNavigate,
  });

  String _routePath(String route) {
    return Uri.tryParse(route)?.path ?? route.split('?').first;
  }

  String _routeIdentity(String route) {
    final uri = Uri.tryParse(route);
    if (uri == null) return route;
    final params = Map<String, String>.from(uri.queryParameters);
    final sortedKeys = params.keys.toList()..sort();
    final query = sortedKeys.map((key) => '$key=${params[key]}').join('&');
    return query.isEmpty ? uri.path : '${uri.path}?$query';
  }

  bool _isCurrentRoute(String route) {
    return _routeIdentity(currentLocation) == _routeIdentity(route);
  }

  MenuSubItem? _resolveSelectedSubItem(String location) {
    final locationPath = _routePath(location);

    for (final subItem in subItems) {
      if (locationPath == _routePath(subItem.route)) {
        return subItem;
      }
    }

    MenuSubItem? bestMatch;
    for (final subItem in subItems) {
      final routePath = _routePath(subItem.route);
      final prefix = '$routePath/';
      if (locationPath.startsWith(prefix)) {
        if (bestMatch == null ||
            routePath.length > _routePath(bestMatch.route).length) {
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
    // For single item, the main item is selected if any subitem (usually just one) matches
    final isSelected = selectedSubItem != null;
    final isAnySubItemSelected = isSelected;

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
                  ? () {
                      if (isSingleItem) {
                        if (subItems.isNotEmpty && !isSelected) {
                          if (onNavigate != null) {
                            onNavigate!(subItems.first.route);
                          } else {
                            context.go(subItems.first.route);
                          }
                        }
                      } else {
                        onExpansionChanged?.call(!isExpanded);
                      }
                    }
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isAnySubItemSelected
                      ? theme.primaryColor.withValues(alpha: 0.1)
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
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7))
                          : theme.disabledColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isAnySubItemSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: enabled
                              ? (isAnySubItemSelected
                                  ? theme.primaryColor
                                  : theme.colorScheme.onSurface)
                              : theme.disabledColor,
                        ),
                      ),
                    ),
                    // Unread badge
                    if (badgeCount > 0)
                      GestureDetector(
                        onTap: onBadgeTap,
                        child: Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    if (!isSingleItem)
                      RotatedBox(
                        quarterTurns: isExpanded ? 2 : 0,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: enabled
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5)
                              : theme.disabledColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isExpanded && !isSingleItem)
          Column(
            children: subItems.map((subItem) {
              final isSelected = selectedSubItem?.route == subItem.route;
              final isCurrentRoute = _isCurrentRoute(subItem.route);
              final subItemBadgeCount = subItemBadgeCounts[subItem.route] ?? 0;

              // Render as header (non-clickable)
              if (subItem.isHeader) {
                return Container(
                  margin: const EdgeInsets.only(left: 48, top: 12, bottom: 4),
                  child: Text(
                    subItem.title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }

              return Container(
                margin: const EdgeInsets.only(left: 36, right: 8, bottom: 2),
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onSecondaryTapDown: enabled
                        ? (details) async {
                            final value = await showModernContextMenu<String>(
                              context: context,
                              globalPosition: details.globalPosition,
                              title: subItem.title,
                              actions: [
                                const ModernContextMenuAction(
                                  value: 'current_tab',
                                  icon: Icons.tab,
                                  label: 'Abrir en esta pestaña',
                                  subtitle: 'Usar el espacio activo',
                                  iconColor: Color(0xFF475569),
                                ),
                                ModernContextMenuAction(
                                  value: 'new_tab',
                                  icon: Icons.open_in_new,
                                  label: 'Abrir en nueva pestaña',
                                  subtitle: 'Mantener esta vista abierta',
                                  iconColor: theme.colorScheme.primary,
                                ),
                              ],
                            );

                            if (!context.mounted) return;

                            if (value == 'current_tab') {
                              if (!isCurrentRoute) {
                                if (onNavigate != null) {
                                  onNavigate!(subItem.route);
                                } else {
                                  context.go(subItem.route);
                                }
                              }
                            } else if (value == 'new_tab') {
                              try {
                                final workspaceManager =
                                    context.read<WorkspaceManager>();
                                final existingFound = workspaceManager
                                    .switchToExistingWorkspaceWithRoute(
                                        subItem.route);
                                if (!existingFound) {
                                  workspaceManager.addWorkspace(
                                    title: subItem.title,
                                    initialRoute: subItem.route,
                                  );
                                }
                              } catch (e) {
                                // Fallback if WorkspaceManager isn't available
                                context.go(subItem.route);
                              }
                            }
                          }
                        : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      onTap: enabled
                          ? () {
                              if (!isCurrentRoute) {
                                if (onNavigate != null) {
                                  onNavigate!(subItem.route);
                                } else {
                                  context.go(subItem.route);
                                }
                              }
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: isSelected
                              ? theme.primaryColor.withValues(alpha: 0.08)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              subItem.icon,
                              size: 16,
                              color: isSelected
                                  ? theme.primaryColor
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                subItem.title,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? theme.primaryColor
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                            if (subItemBadgeCount > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  subItemBadgeCount > 99
                                      ? '99+'
                                      : '$subItemBadgeCount',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
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
  final bool isHeader; // For visual grouping

  const MenuSubItem({
    required this.icon,
    required this.title,
    required this.route,
    this.isHeader = false,
  });
}
