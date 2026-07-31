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
  final bool compactTouch;
  final VoidCallback? onCurrentTap;
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
    this.compactTouch = false,
    this.onCurrentTap,
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
          margin: EdgeInsets.symmetric(
            horizontal: compactTouch ? 8 : 6,
            vertical: compactTouch ? 0 : 1,
          ),
          child: Material(
            color: isAnySubItemSelected
                ? theme.primaryColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.07),
              focusColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              mouseCursor:
                  enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              onTap: enabled
                  ? () {
                      if (isSingleItem) {
                        if (subItems.isEmpty) return;
                        if (isSelected) {
                          onCurrentTap?.call();
                        } else if (onNavigate != null) {
                          onNavigate!(subItems.first.route);
                        } else {
                          context.go(subItems.first.route);
                        }
                      } else {
                        onExpansionChanged?.call(!isExpanded);
                      }
                    }
                  : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: compactTouch ? 52 : 30,
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compactTouch ? 12 : 9,
                    vertical: compactTouch ? 8 : 5,
                  ),
                  decoration: BoxDecoration(
                    border: isAnySubItemSelected
                        ? Border(
                            left: BorderSide(
                              color: theme.primaryColor,
                              width: 2,
                            ),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isAnySubItemSelected ? activeIcon : icon,
                        size: compactTouch ? 20 : 16,
                        color: enabled
                            ? (isAnySubItemSelected
                                ? theme.primaryColor
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7))
                            : theme.disabledColor,
                      ),
                      SizedBox(width: compactTouch ? 12 : 9),
                      Expanded(
                        child: Text(
                          title,
                          style: (compactTouch
                                  ? theme.textTheme.bodyMedium
                                  : theme.textTheme.bodySmall)
                              ?.copyWith(
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
                        Semantics(
                          button: onBadgeTap != null,
                          enabled: onBadgeTap != null,
                          label: onBadgeTap == null
                              ? '$badgeCount pendientes en $title'
                              : 'Abrir $badgeCount pendientes en $title',
                          child: Tooltip(
                            message: '$badgeCount pendientes en $title',
                            child: MouseRegion(
                              cursor: onBadgeTap == null
                                  ? MouseCursor.defer
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onBadgeTap,
                                child: SizedBox(
                                  width: onBadgeTap == null
                                      ? 32
                                      : (compactTouch ? 48 : 32),
                                  height: onBadgeTap == null
                                      ? 28
                                      : (compactTouch ? 48 : 28),
                                  child: Center(
                                    child: ExcludeSemantics(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          badgeCount > 99
                                              ? '99+'
                                              : '$badgeCount',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme.colorScheme.onPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!isSingleItem)
                        RotatedBox(
                          quarterTurns: isExpanded ? 2 : 0,
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: compactTouch ? 20 : 15,
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
                  margin: const EdgeInsets.only(left: 41, top: 8, bottom: 3),
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
                margin: EdgeInsets.only(
                  left: compactTouch ? 30 : 24,
                  right: compactTouch ? 8 : 6,
                  bottom: compactTouch ? 0 : 1,
                ),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  enabled: enabled,
                  label: subItem.title,
                  child: Material(
                    color: isSelected
                        ? theme.primaryColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
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
                        borderRadius: BorderRadius.circular(5),
                        splashFactory: NoSplash.splashFactory,
                        highlightColor: Colors.transparent,
                        hoverColor:
                            theme.colorScheme.onSurface.withValues(alpha: 0.07),
                        focusColor:
                            theme.colorScheme.onSurface.withValues(alpha: 0.08),
                        mouseCursor: enabled
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onTap: enabled
                            ? () {
                                if (isCurrentRoute) {
                                  onCurrentTap?.call();
                                } else {
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
                            horizontal: 8,
                            vertical: 5,
                          ),
                          constraints: BoxConstraints(
                            minHeight: compactTouch ? 48 : 0,
                          ),
                          decoration: BoxDecoration(
                            border: isSelected
                                ? Border(
                                    left: BorderSide(
                                      color: theme.primaryColor,
                                      width: 2,
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                subItem.icon,
                                size: compactTouch ? 18 : 14,
                                color: isSelected
                                    ? theme.primaryColor
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                              ),
                              SizedBox(width: compactTouch ? 10 : 8),
                              Expanded(
                                child: Text(
                                  subItem.title,
                                  style: (compactTouch
                                          ? theme.textTheme.bodyMedium
                                          : theme.textTheme.bodySmall)
                                      ?.copyWith(
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
