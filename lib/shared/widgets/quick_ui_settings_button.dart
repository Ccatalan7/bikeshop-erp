import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/settings/services/appearance_service.dart';
import '../services/notification_service.dart';

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
        length: 3,
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
                  Tab(
                    icon: Icon(Icons.notifications_active_outlined),
                    text: 'Notificaciones',
                  ),
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
                        const _NotificationsSettingsTab(),
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

class _NotificationsSettingsTab extends StatefulWidget {
  const _NotificationsSettingsTab();

  @override
  State<_NotificationsSettingsTab> createState() =>
      _NotificationsSettingsTabState();
}

class _NotificationsSettingsTabState extends State<_NotificationsSettingsTab> {
  final _notificationService = NotificationService();

  bool _loading = true;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _messageNotificationsEnabled = true;
  bool _emailNotificationsEnabled = true;
  String _messageSoundId = NotificationService.defaultMessageSoundId;
  String _emailSoundId = NotificationService.defaultEmailSoundId;
  double _soundVolume = 0.56;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _notificationService.loadSettingsForUi();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = _notificationService.notificationsEnabled;
      _soundEnabled = _notificationService.soundEnabled;
      _vibrationEnabled = _notificationService.vibrationEnabled;
      _messageNotificationsEnabled =
          _notificationService.messageNotificationsEnabled;
      _emailNotificationsEnabled =
          _notificationService.emailNotificationsEnabled;
      _messageSoundId = _notificationService.messageSoundId;
      _emailSoundId = _notificationService.emailSoundId;
      _soundVolume = _notificationService.soundVolume;
      _loading = false;
    });
  }

  Future<void> _setNotificationsEnabled(bool value) async {
    setState(() => _notificationsEnabled = value);
    await _notificationService.setNotificationsEnabled(value);
  }

  Future<void> _setSoundEnabled(bool value) async {
    setState(() => _soundEnabled = value);
    await _notificationService.setSoundEnabled(value);
  }

  Future<void> _setVibrationEnabled(bool value) async {
    setState(() => _vibrationEnabled = value);
    await _notificationService.setVibrationEnabled(value);
  }

  Future<void> _setChannelEnabled(
    NotificationCategory category,
    bool value,
  ) async {
    setState(() {
      switch (category) {
        case NotificationCategory.general:
          _notificationsEnabled = value;
          break;
        case NotificationCategory.message:
          _messageNotificationsEnabled = value;
          break;
        case NotificationCategory.email:
          _emailNotificationsEnabled = value;
          break;
      }
    });
    await _notificationService.setCategoryNotificationsEnabled(category, value);
  }

  Future<void> _setChannelSound(
    NotificationCategory category,
    String soundId,
  ) async {
    setState(() {
      switch (category) {
        case NotificationCategory.general:
          break;
        case NotificationCategory.message:
          _messageSoundId = soundId;
          break;
        case NotificationCategory.email:
          _emailSoundId = soundId;
          break;
      }
    });
    await _notificationService.setSoundForCategory(category, soundId);
  }

  Future<void> _setSoundVolume(double value) async {
    setState(() => _soundVolume = value);
    await _notificationService.setSoundVolume(value);
  }

  Future<void> _previewSound(
    NotificationCategory category,
    String soundId,
  ) {
    return _notificationService.playNotificationSound(
      category: category,
      soundId: soundId,
      preview: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionLabel(
          icon: Icons.notifications_active_outlined,
          label: 'General',
        ),
        const SizedBox(height: 8),
        _SettingsSwitchTile(
          icon: Icons.notifications_none_outlined,
          title: 'Activar notificaciones',
          value: _notificationsEnabled,
          onChanged: _setNotificationsEnabled,
        ),
        const SizedBox(height: 8),
        _SettingsSwitchTile(
          icon: Icons.volume_up_outlined,
          title: 'Sonidos',
          value: _soundEnabled,
          onChanged: _setSoundEnabled,
        ),
        const SizedBox(height: 8),
        _SettingsSwitchTile(
          icon: Icons.vibration_outlined,
          title: 'Vibración',
          value: _vibrationEnabled,
          onChanged: _setVibrationEnabled,
        ),
        const SizedBox(height: 16),
        Material(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.tune_outlined,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Volumen',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${(_soundVolume * 100).round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _soundVolume,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: _soundEnabled
                      ? (value) => setState(() => _soundVolume = value)
                      : null,
                  onChangeEnd: _soundEnabled ? _setSoundVolume : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel(
          icon: Icons.mark_chat_unread_outlined,
          label: 'Canales',
        ),
        const SizedBox(height: 10),
        _NotificationChannelCard(
          category: NotificationCategory.message,
          icon: Icons.chat_bubble_outline,
          title: 'Mensajes',
          subtitle: 'WhatsApp, chats internos y soporte',
          enabled: _messageNotificationsEnabled,
          soundId: _messageSoundId,
          onEnabledChanged: (value) => _setChannelEnabled(
            NotificationCategory.message,
            value,
          ),
          onSoundChanged: (soundId) => _setChannelSound(
            NotificationCategory.message,
            soundId,
          ),
          onPreview: () => _previewSound(
            NotificationCategory.message,
            _messageSoundId,
          ),
        ),
        const SizedBox(height: 10),
        _NotificationChannelCard(
          category: NotificationCategory.email,
          icon: Icons.email_outlined,
          title: 'Correo',
          subtitle: 'Gmail, Zoho y bandeja unificada',
          enabled: _emailNotificationsEnabled,
          soundId: _emailSoundId,
          onEnabledChanged: (value) => _setChannelEnabled(
            NotificationCategory.email,
            value,
          ),
          onSoundChanged: (soundId) => _setChannelSound(
            NotificationCategory.email,
            soundId,
          ),
          onPreview: () => _previewSound(
            NotificationCategory.email,
            _emailSoundId,
          ),
        ),
      ],
    );
  }
}

class _NotificationChannelCard extends StatelessWidget {
  final NotificationCategory category;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String soundId;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onSoundChanged;
  final VoidCallback onPreview;

  const _NotificationChannelCard({
    required this.category,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.soundId,
    required this.onEnabledChanged,
    required this.onSoundChanged,
    required this.onPreview,
  });

  Future<void> _openSoundPicker(BuildContext context) async {
    final selectedSoundId = await showDialog<String>(
      context: context,
      builder: (context) => _NotificationSoundPickerDialog(
        category: category,
        selectedSoundId: soundId,
      ),
    );
    if (selectedSoundId == null) return;
    onSoundChanged(selectedSoundId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedOption = NotificationService.soundOptionById(soundId);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: onEnabledChanged,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openSoundPicker(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sonido',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    selectedOption.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Probar sonido',
                  onPressed: onPreview,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectedOption.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationSoundPickerDialog extends StatelessWidget {
  final NotificationCategory category;
  final String selectedSoundId;

  const _NotificationSoundPickerDialog({
    required this.category,
    required this.selectedSoundId,
  });

  static const _groups = [
    _NotificationSoundGroupTab(
      group: NotificationSoundGroup.mountainBike,
      label: 'MTB',
      icon: Icons.directions_bike_outlined,
    ),
    _NotificationSoundGroupTab(
      group: NotificationSoundGroup.workshop,
      label: 'Taller',
      icon: Icons.build_outlined,
    ),
    _NotificationSoundGroupTab(
      group: NotificationSoundGroup.pointOfSale,
      label: 'Caja',
      icon: Icons.qr_code_scanner_outlined,
    ),
    _NotificationSoundGroupTab(
      group: NotificationSoundGroup.digital,
      label: 'Digital',
      icon: Icons.graphic_eq_outlined,
    ),
    _NotificationSoundGroupTab(
      group: NotificationSoundGroup.desk,
      label: 'Escritorio',
      icon: Icons.keyboard_outlined,
    ),
    _NotificationSoundGroupTab(
      group: NotificationSoundGroup.regular,
      label: 'Regular',
      icon: Icons.tune_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedOption = NotificationService.soundOptionById(selectedSoundId);
    final selectedGroupIndex = _groups.indexWhere(
      (group) => group.group == selectedOption.group,
    );
    final initialIndex = selectedGroupIndex == -1 ? 0 : selectedGroupIndex;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: DefaultTabController(
        length: _groups.length,
        initialIndex: initialIndex,
        child: SizedBox(
          width: 560,
          height: 480,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.volume_up_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Elegir sonido',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabs: [
                  for (final group in _groups)
                    Tab(
                      icon: Icon(group.icon),
                      text: group.label,
                    ),
                ],
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final group in _groups)
                      _NotificationSoundOptionList(
                        category: category,
                        group: group.group,
                        selectedSoundId: selectedSoundId,
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

class _NotificationSoundGroupTab {
  final NotificationSoundGroup group;
  final String label;
  final IconData icon;

  const _NotificationSoundGroupTab({
    required this.group,
    required this.label,
    required this.icon,
  });
}

class _NotificationSoundOptionList extends StatelessWidget {
  final NotificationCategory category;
  final NotificationSoundGroup group;
  final String selectedSoundId;

  const _NotificationSoundOptionList({
    required this.category,
    required this.group,
    required this.selectedSoundId,
  });

  @override
  Widget build(BuildContext context) {
    final options = NotificationService.soundOptionsForGroup(group);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      itemCount: options.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final option = options[index];
        return _NotificationSoundOptionTile(
          category: category,
          option: option,
          selected: option.id == selectedSoundId,
        );
      },
    );
  }
}

class _NotificationSoundOptionTile extends StatelessWidget {
  final NotificationCategory category;
  final NotificationSoundOption option;
  final bool selected;

  const _NotificationSoundOptionTile({
    required this.category,
    required this.option,
    required this.selected,
  });

  Future<void> _preview() {
    return NotificationService().playNotificationSound(
      category: category,
      soundId: option.id,
      preview: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(option.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Probar sonido',
                onPressed: _preview,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              SizedBox(
                width: 30,
                child: selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
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
