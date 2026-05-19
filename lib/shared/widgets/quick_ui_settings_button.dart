import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/settings/services/appearance_service.dart';

class QuickUiSettingsButton extends StatelessWidget {
  const QuickUiSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Configuración rápida',
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Configuración rápida',
        onPressed: () => _showQuickSettings(context),
        icon: Icon(
          Icons.settings_outlined,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
  }

  void _showQuickSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _QuickSettingsDialog(),
    );
  }
}

class _QuickSettingsDialog extends StatelessWidget {
  const _QuickSettingsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(520.0, screenSize.width - 48);
    final dialogHeight = math.min(560.0, screenSize.height - 48);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: DefaultTabController(
        length: 2,
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Configuración rápida',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              TabBar(
                tabs: const [
                  Tab(icon: Icon(Icons.palette_outlined), text: 'UI'),
                  Tab(
                      icon: Icon(Icons.vertical_split_outlined),
                      text: 'Barra derecha'),
                ],
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Consumer<AppearanceService>(
                  builder: (context, appearanceService, _) {
                    return TabBarView(
                      children: [
                        _UiSettingsTab(appearanceService: appearanceService),
                        _ToolbarSettingsTab(
                          appearanceService: appearanceService,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UiSettingsTab extends StatelessWidget {
  final AppearanceService appearanceService;

  const _UiSettingsTab({required this.appearanceService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionLabel(icon: Icons.contrast_outlined, label: 'Tema'),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Claro'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Oscuro'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.settings_brightness_outlined),
                label: Text('Sistema'),
              ),
            ],
            selected: {appearanceService.themeMode},
            onSelectionChanged: (selection) {
              appearanceService.setThemeMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel(
            icon: Icons.dashboard_customize_outlined,
            label: 'Paleta del layout'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final palette in AppearanceService.sidebarPalettes)
              _PaletteChoice(
                palette: palette,
                selected: palette.code == appearanceService.sidebarPaletteCode,
                onTap: () => appearanceService.setSidebarPalette(palette.code),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          appearanceService.sidebarPalette.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ToolbarSettingsTab extends StatelessWidget {
  final AppearanceService appearanceService;

  const _ToolbarSettingsTab({required this.appearanceService});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionLabel(
          icon: Icons.format_color_fill_outlined,
          label: 'Color',
        ),
        const SizedBox(height: 8),
        _SettingsSwitchTile(
          icon: Icons.chat_bubble_outline,
          title: 'Usar paleta en mensajería y barra derecha',
          value: appearanceService.messagingUsesSidebarPalette,
          onChanged: appearanceService.setMessagingUsesSidebarPalette,
        ),
        const SizedBox(height: 18),
        const _SectionLabel(
          icon: Icons.view_sidebar_outlined,
          label: 'Posición',
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.view_column_outlined),
                label: Text('Al lado'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.layers_outlined),
                label: Text('Sobre contenido'),
              ),
            ],
            selected: {appearanceService.rightToolbarOverContent},
            onSelectionChanged: (selection) {
              appearanceService.setRightToolbarOverContent(selection.first);
            },
          ),
        ),
        const SizedBox(height: 18),
        const _SectionLabel(
          icon: Icons.blur_on_outlined,
          label: 'Material',
        ),
        const SizedBox(height: 8),
        _SettingsSwitchTile(
          icon: Icons.blur_on_outlined,
          title: 'Efecto blur matte',
          value: appearanceService.rightToolbarBlurEnabled,
          onChanged: appearanceService.setRightToolbarBlurEnabled,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: SwitchListTile.adaptive(
        dense: true,
        secondary: Icon(
          icon,
          size: 19,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        value: value,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _PaletteChoice extends StatelessWidget {
  final SidebarPaletteOption palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteChoice({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 152,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.12)
                : theme.colorScheme.onSurface.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? palette.accent
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.48),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _PalettePreview(palette: palette),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  palette.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        selected ? palette.accent : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check, size: 14, color: palette.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PalettePreview extends StatelessWidget {
  final SidebarPaletteOption palette;

  const _PalettePreview({required this.palette});

  @override
  Widget build(BuildContext context) {
    final outlineColor = Color.alphaBlend(
      palette.foreground.withValues(alpha: 0.18),
      palette.border,
    );

    return Container(
      width: 36,
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: outlineColor),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: palette.background),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.46,
              child: ColoredBox(color: palette.backgroundAlt),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.24,
              child: ColoredBox(color: palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}
