import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/branded_loading.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _userEmail;
  String? _tenantId;
  String? _subdomain;
  String? _role;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      _userEmail = user.email;

      final profileData = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id, role')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profileData != null) {
        _tenantId = profileData['tenant_id'];
        _role = profileData['role'];

        final tenantData = await Supabase.instance.client
            .from('tenants')
            .select('subdomain')
            .eq('id', _tenantId!)
            .maybeSingle();

        if (tenantData != null) {
          _subdomain = tenantData['subdomain'];
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading user info: $e');
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado al portapapeles')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sections = <_SettingsSectionData>[
      _SettingsSectionData(
        title: 'Empresa y acceso',
        description: 'Usuarios, roles y apariencia base del entorno.',
        icon: Icons.apartment_rounded,
        color: colorScheme.primary,
        entries: const [
          _SettingsEntry(
            icon: Icons.people_outline,
            title: 'Usuarios y roles',
            subtitle: 'Invitaciones, permisos y estado de acceso',
            route: '/settings/users',
          ),
          _SettingsEntry(
            icon: Icons.palette_outlined,
            title: 'Apariencia',
            subtitle: 'Tema, logo e icono de inicio',
            route: '/settings/appearance',
          ),
        ],
      ),
      const _SettingsSectionData(
        title: 'Canales y alertas',
        description: 'Comunicacion operativa y avisos del sistema.',
        icon: Icons.campaign_outlined,
        color: Color(0xFF9A6A18),
        entries: [
          _SettingsEntry(
            icon: Icons.forum_outlined,
            title: 'WhatsApp',
            subtitle: 'Canales, plantilla inicial y costos Meta',
            route: '/settings/whatsapp',
          ),
          _SettingsEntry(
            icon: Icons.notifications_outlined,
            title: 'Notificaciones',
            subtitle: 'Preferencias del dispositivo y pruebas',
            route: '/settings/notifications',
          ),
        ],
      ),
      const _SettingsSectionData(
        title: 'Operacion y dispositivos',
        description: 'Lectores, escaner movil e impresion de etiquetas.',
        icon: Icons.precision_manufacturing_outlined,
        color: Color(0xFF0F766E),
        entries: [
          _SettingsEntry(
            icon: Icons.usb_outlined,
            title: 'Lector USB/teclado',
            subtitle: 'Captura de codigos desde lector tipo teclado',
            route: '/settings/keyboard-scanner',
          ),
          _SettingsEntry(
            icon: Icons.bluetooth_outlined,
            title: 'Lector Bluetooth',
            subtitle: 'Conexion de lector inalambrico compatible',
            route: '/settings/bluetooth-scanner',
          ),
          _SettingsEntry(
            icon: Icons.phone_android_outlined,
            title: 'Escaner movil',
            subtitle: 'Usar un celular como lector remoto',
            route: '/settings/remote-scanner',
          ),
          _SettingsEntry(
            icon: Icons.label_outline,
            title: 'Impresora de etiquetas',
            subtitle: 'NIIMBOT y ajustes de impresion termica',
            route: '/settings/label-printer',
          ),
        ],
      ),
      const _SettingsSectionData(
        title: 'Finanzas',
        description: 'Pagos y estructura contable del sistema.',
        icon: Icons.account_balance_wallet_outlined,
        color: Color(0xFF4456C5),
        entries: [
          _SettingsEntry(
            icon: Icons.payment_outlined,
            title: 'Metodos de pago',
            subtitle: 'Efectivo, transferencias, tarjetas y cuentas',
            route: '/settings/payment-methods',
          ),
          _SettingsEntry(
            icon: Icons.account_tree_outlined,
            title: 'Plan de cuentas',
            subtitle: 'Cuentas contables usadas por ventas y pagos',
            route: '/accounting/accounts',
          ),
        ],
      ),
      const _SettingsSectionData(
        title: 'Sistema y datos',
        description: 'Respaldo, restauracion y acciones criticas.',
        icon: Icons.shield_outlined,
        color: Color(0xFFA24D3B),
        entries: [
          _SettingsEntry(
            icon: Icons.backup_outlined,
            title: 'Respaldo y restauracion',
            subtitle: 'Copias, agenda de respaldo y recuperacion',
            route: '/settings/backup',
          ),
          _SettingsEntry(
            icon: Icons.delete_forever_outlined,
            title: 'Reinicio de datos',
            subtitle: 'Eliminacion controlada por modulo',
            route: '/settings/factory-reset',
            isDestructive: true,
          ),
        ],
      ),
    ];
    final totalEntries = sections.fold<int>(
      0,
      (sum, section) => sum + section.entries.length,
    );

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _blendSurface(
                accent: colorScheme.primary,
                surface: colorScheme.surfaceContainerLowest,
                alpha: 0.05,
              ),
              colorScheme.surfaceContainerLowest,
              colorScheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: BrandedLoading())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1080;

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 32 : 20,
                        isWide ? 28 : 20,
                        isWide ? 32 : 20,
                        40,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeroBanner(
                            context,
                            sectionCount: sections.length,
                            totalEntries: totalEntries,
                          ),
                          const SizedBox(height: 24),
                          if (isWide)
                            LayoutBuilder(
                              builder: (ctx, lc) {
                                final leftW =
                                    (lc.maxWidth * 0.30).clamp(320.0, 420.0);
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: leftW,
                                      child: Column(
                                        children: [
                                          _buildAccountPanel(context),
                                          const SizedBox(height: 18),
                                          _buildAboutFooter(context),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: _buildSettingsGrid(
                                        context,
                                        sections: sections,
                                        columns: 2,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            )
                          else ...[
                            _buildAccountPanel(context),
                            const SizedBox(height: 20),
                            _buildSettingsGrid(
                              context,
                              sections: sections,
                              columns: 1,
                            ),
                            const SizedBox(height: 20),
                            _buildAboutFooter(context),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(
    BuildContext context, {
    required int sectionCount,
    required int totalEntries,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final supportColor =
        Color.lerp(colorScheme.primary, const Color(0xFF0F766E), 0.55)!;
    final roleLabel = _formatRole(_role);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 940;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isWide ? 28 : 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(colorScheme.primary, supportColor, 0.18)!,
                supportColor,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: supportColor.withValues(alpha: 0.18),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildHeroCopy(context)),
                    const SizedBox(width: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildHeroStat(
                          context,
                          icon: Icons.widgets_outlined,
                          label: 'Areas',
                          value: '$sectionCount',
                        ),
                        _buildHeroStat(
                          context,
                          icon: Icons.tune_outlined,
                          label: 'Accesos',
                          value: '$totalEntries',
                        ),
                        _buildHeroStat(
                          context,
                          icon: Icons.verified_user_outlined,
                          label: 'Sesion',
                          value: roleLabel == 'No disponible'
                              ? 'Activa'
                              : roleLabel,
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroCopy(context),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildHeroStat(
                          context,
                          icon: Icons.widgets_outlined,
                          label: 'Areas',
                          value: '$sectionCount',
                        ),
                        _buildHeroStat(
                          context,
                          icon: Icons.tune_outlined,
                          label: 'Accesos',
                          value: '$totalEntries',
                        ),
                        _buildHeroStat(
                          context,
                          icon: Icons.verified_user_outlined,
                          label: 'Sesion',
                          value: roleLabel == 'No disponible'
                              ? 'Activa'
                              : roleLabel,
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildHeroCopy(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Text(
            'Centro de control',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Configuracion',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Ajusta permisos, canales, finanzas y herramientas del taller desde una vista mas clara, mas util y con mejor jerarquia visual.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroStat(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGrid(
    BuildContext context, {
    required List<_SettingsSectionData> sections,
    required int columns,
  }) {
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) const SizedBox(height: 18),
            _buildSettingsSection(context, sections[index]),
          ],
        ],
      );
    }

    const spacing = 18.0;
    final rows = <Widget>[];
    for (var i = 0; i < sections.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: spacing));
      final isLastOdd = sections.length.isOdd && i == sections.length - 1;
      if (isLastOdd) {
        rows.add(_buildSettingsSection(context, sections[i]));
      } else {
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSettingsSection(context, sections[i]),
                ),
                const SizedBox(width: spacing),
                Expanded(
                  child: _buildSettingsSection(context, sections[i + 1]),
                ),
              ],
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildAccountPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roleLabel = _formatRole(_role);
    final primaryAccent =
        Color.lerp(colorScheme.primary, const Color(0xFF0F766E), 0.35)!;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  primaryAccent,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.manage_accounts_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    if ((_userEmail ?? '').isNotEmpty)
                      IconButton(
                        tooltip: 'Copiar Email',
                        onPressed: () => _copyToClipboard(_userEmail!, 'Email'),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Cuenta activa',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _userEmail ?? 'No disponible',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (roleLabel != 'No disponible')
                      _buildAccountChip(
                        context,
                        icon: Icons.verified_user_outlined,
                        label: roleLabel,
                      ),
                    if ((_subdomain ?? '').isNotEmpty)
                      _buildAccountChip(
                        context,
                        icon: Icons.public_outlined,
                        label: _subdomain!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              children: [
                _buildInfoItem(
                  context,
                  label: 'Acceso',
                  value: roleLabel,
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                _buildInfoItem(
                  context,
                  label: 'Subdominio',
                  value: _subdomain ?? 'No disponible',
                  copyValue: _subdomain,
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                _buildInfoItem(
                  context,
                  label: 'Tenant ID',
                  value: _compactUuid(_tenantId),
                  copyValue: _tenantId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context, {
    required String label,
    required String value,
    String? copyValue,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canCopy = copyValue != null && copyValue.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          if (canCopy)
            IconButton(
              tooltip: 'Copiar $label',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyToClipboard(copyValue, label),
              icon: Icon(
                Icons.copy_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    _SettingsSectionData section,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceTint = _blendSurface(
      accent: section.color,
      surface: colorScheme.surface,
      alpha: 0.085,
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surfaceTint,
            colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: section.color.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: section.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(section.icon, size: 22, color: section.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: section.color.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  '${section.entries.length} accesos',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: section.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < section.entries.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _buildSettingRow(
              context,
              section.entries[index],
              accentColor: section.color,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingRow(
    BuildContext context,
    _SettingsEntry entry, {
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedAccent =
        entry.isDestructive ? colorScheme.error : accentColor;
    final rowSurface = _blendSurface(
      accent: resolvedAccent,
      surface: colorScheme.surface,
      alpha: 0.06,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(entry.route),
        child: Ink(
          decoration: BoxDecoration(
            color: rowSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: resolvedAccent.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: resolvedAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    entry.icon,
                    size: 18,
                    color: resolvedAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: entry.isDestructive
                              ? colorScheme.error
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: resolvedAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutFooter(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceTint = _blendSurface(
      accent: colorScheme.primary,
      surface: colorScheme.surface,
      alpha: 0.07,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: surfaceTint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.layers_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vinabike ERP',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Version 1.0.1+3',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Entorno central para ventas, inventario, taller, contabilidad y configuracion operativa del negocio.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Vinabike ERP',
                applicationVersion: '1.0.1+3',
                applicationIcon: const Icon(Icons.directions_bike, size: 42),
                children: const [
                  Text('Sistema ERP para operacion de bikeshop.'),
                ],
              );
            },
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('Acerca de la plataforma'),
          ),
        ],
      ),
    );
  }

  static Color _blendSurface({
    required Color accent,
    required Color surface,
    required double alpha,
  }) {
    return Color.alphaBlend(accent.withValues(alpha: alpha), surface);
  }

  String _formatRole(String? role) {
    return switch (role) {
      'owner' => 'Propietario',
      'admin' => 'Administrador',
      'manager' => 'Encargado',
      'employee' => 'Colaborador',
      'mechanic' => 'Mecanico',
      null || '' => 'No disponible',
      _ => role,
    };
  }

  String _compactUuid(String? value) {
    if (value == null || value.isEmpty) return 'No disponible';
    return value;
  }
}

class _SettingsSectionData {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<_SettingsEntry> entries;

  const _SettingsSectionData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.entries,
  });
}

class _SettingsEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool isDestructive;

  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.isDestructive = false,
  });
}
