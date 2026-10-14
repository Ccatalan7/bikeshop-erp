import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/current_user_profile.dart';
import '../../../shared/services/current_user_profile_navigation.dart';
import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/shop_time.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/module_start_page.dart';
import '../services/meta_settings_service.dart';
import '../services/settings_overview_service.dart';

/// Configuración's start page: who is signed in, the state of the shop's
/// setup in four figures, and the settings pages in three columns.
///
/// Rebuilt 2026-10-14 on the start-page pieces Sitio web uses («esa sí que es
/// horrible», the owner, of the hero with a slogan, floating cards and a
/// hard-coded «1.0.1+3»). The band says what needs the owner's eye — a backup
/// ten months old, Meta's authorization run out — and each figure opens the
/// page where it is fixed.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.overviewService, this.readVersion});

  /// Test seams.
  final SettingsOverviewService? overviewService;
  final Future<String> Function()? readVersion;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsOverview? _overview;
  String? _overviewTenant;
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final read = widget.readVersion ??
          () async {
            final info = await PackageInfo.fromPlatform();
            return info.buildNumber.isEmpty
                ? info.version
                : '${info.version}+${info.buildNumber}';
          };
      final version = await read();
      if (mounted) setState(() => _version = version);
    } catch (_) {
      // Without the platform's answer the page says nothing rather than a
      // number nobody shipped.
    }
  }

  void _loadOverviewFor(String tenantId) {
    if (tenantId.isEmpty || tenantId == _overviewTenant) return;
    _overviewTenant = tenantId;
    final service = widget.overviewService ?? SettingsOverviewService();
    service.load(tenantId).then((overview) {
      if (mounted && _overviewTenant == tenantId) {
        setState(() => _overview = overview);
      }
    });
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Viñabike ERP',
      applicationVersion: _version == null ? null : 'Versión $_version',
      applicationIcon: const Icon(Icons.directions_bike_rounded, size: 40),
      children: const [
        Text('Ventas, taller, inventario, contabilidad y sitio web de la '
            'tienda en un solo sistema.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileService = context.watch<CurrentUserProfileService>();
    final profile = profileService.profile;
    final phone = MediaQuery.sizeOf(context).width < 600;
    if (profile != null) _loadOverviewFor(profile.tenantId);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(phone: phone, version: _versionLabel),
            Expanded(
              child: profileService.isLoading && profile == null
                  ? const Center(child: BrandedLoading())
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _band(context, profile: profile, phone: phone),
                          ModuleStartWorkspaces(
                            phone: phone,
                            groups: _groups(context, profile),
                            wideColumns: const [
                              [0, 4],
                              [1, 3],
                              [2, 5],
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// «1.0.35» for the eye; the build number goes in «Acerca de».
  String? get _versionLabel => _version?.split('+').first;

  Widget _band(
    BuildContext context, {
    required CurrentUserProfile? profile,
    required bool phone,
  }) {
    final shell = VinabikeThemeRoles.of(context).shell;
    final now = DateTime.now();
    final overview = _overview;
    final company = overview?.company;
    final users = overview?.users;
    final backup = overview?.backup;
    final channels = overview?.channels;
    final loaded = overview != null;

    final email = profile?.email ?? '';
    final role = _roleLabel(profile?.role);
    final tenant = profile?.tenantName.trim() ?? '';
    final subdomain = profile?.tenantSubdomain?.trim() ?? '';
    final tenantId = profile?.tenantId ?? '';

    final lead = Row(
      children: [
        Container(
          width: phone ? 34 : 42,
          height: phone ? 34 : 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: shell.foreground,
            shape: BoxShape.circle,
          ),
          child: Text(
            (profile?.initials ?? '').isEmpty ? '·' : profile!.initials,
            style: TextStyle(
              color: shell.canvas,
              fontSize: phone ? 14 : 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: phone ? 12 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email.isEmpty ? 'Sin sesión' : email,
                key: const ValueKey('settings-account-email'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: shell.foreground,
                  fontSize: phone ? 14.5 : 16.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                [role, if (tenant.isNotEmpty) tenant].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: shell.mutedForeground,
                  fontSize: phone ? 12 : 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    void openProfile() => CurrentUserProfileNavigation.open(context);

    final actions = <Widget>[
      if (!phone && subdomain.isNotEmpty)
        _CopyChip(
          key: const ValueKey('settings-copy-subdomain'),
          label: 'Subdominio',
          value: subdomain,
          onCopy: () => _copy(subdomain, 'Subdominio'),
        ),
      if (!phone && tenantId.isNotEmpty)
        _CopyChip(
          key: const ValueKey('settings-copy-tenant-id'),
          label: 'ID de la empresa',
          value: tenantId.length > 13
              ? '${tenantId.substring(0, 8)}…${tenantId.substring(tenantId.length - 4)}'
              : tenantId,
          semanticValue: tenantId,
          onCopy: () => _copy(tenantId, 'ID de la empresa'),
        ),
      if (phone)
        IconButton(
          key: const ValueKey('settings-open-profile'),
          onPressed: openProfile,
          tooltip: 'Mi perfil',
          style: IconButton.styleFrom(
            foregroundColor: shell.foreground,
            side: BorderSide(color: shell.edge),
            fixedSize: const Size(44, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.person_outline_rounded, size: 20),
        )
      else
        FilledButton.icon(
          key: const ValueKey('settings-open-profile'),
          onPressed: openProfile,
          style: ModuleStartBand.primaryStyle(context, phone: phone),
          icon: const Icon(Icons.person_outline_rounded, size: 18),
          label: const Text('Mi perfil'),
        ),
    ];

    final backupStale = backup?.isStale(now) ?? false;
    final backupCaption = backup == null
        ? (loaded ? 'no se pudo leer' : null)
        : [
            if (backup.lastBackupAt == null)
              'nunca se ha respaldado'
            else
              _age(now.difference(backup.lastBackupAt!)),
            backup.scheduled
                ? 'respaldo automático'
                : 'sin respaldo automático',
          ].join(' · ');
    final expired = channels?.expiredAt(now) ?? const <MetaChannelProvider>[];
    final channelsCaption = channels == null
        ? (loaded ? 'no se pudo leer' : null)
        : expired.isNotEmpty
            ? '${_providerNames(expired)}: autorización vencida'
            : 'conectados';
    final usersCaption = users == null
        ? (loaded ? 'sin acceso a la lista' : null)
        : _usersCaption(users);

    void open(String route) => context.push(route);

    final figureUsers = ModuleStartFigure(
      key: const ValueKey('settings-figure-users'),
      label: 'Usuarios con acceso',
      shortLabel: 'Usuarios',
      value: users == null ? null : '${users.active}',
      caption: usersCaption,
      onTap: () => open('/settings/users'),
    );
    final figureBackup = ModuleStartFigure(
      key: const ValueKey('settings-figure-backup'),
      label: 'Último respaldo',
      shortLabel: 'Último respaldo',
      value: backup == null
          ? null
          : backup.lastBackupAt == null
              ? 'Nunca'
              : _date(backup.lastBackupAt!),
      caption: backupCaption,
      captionTone: backupStale || backup?.scheduled == false
          ? ModuleStartCaptionTone.attention
          : ModuleStartCaptionTone.muted,
      kind: ModuleStartValueKind.text,
      onTap: () => open('/settings/backup'),
    );
    final figureChannels = ModuleStartFigure(
      key: const ValueKey('settings-figure-channels'),
      label: 'Canales de mensajes',
      shortLabel: 'Canales conectados',
      value: channels == null
          ? null
          : '${channels.connectedAt(now)} de ${channels.total}',
      caption: channelsCaption,
      captionTone: expired.isNotEmpty
          ? ModuleStartCaptionTone.attention
          : ModuleStartCaptionTone.muted,
      kind: ModuleStartValueKind.text,
      onTap: () => open('/settings/meta'),
    );

    return ModuleStartBand(
      phone: phone,
      lead: lead,
      actions: actions,
      figures: [
        ModuleStartFigure(
          key: const ValueKey('settings-figure-company'),
          label: 'Empresa',
          shortLabel: 'Empresa',
          value: company == null
              ? null
              : (company.legalName.trim().isNotEmpty
                  ? company.legalName.trim()
                  : company.displayName),
          caption: company == null
              ? (loaded ? 'sin datos de la empresa' : null)
              : [
                  if (company.taxId.trim().isNotEmpty)
                    'RUT ${company.taxId.trim()}',
                  if (company.comuna.trim().isNotEmpty)
                    company.comuna.trim()
                  else if (company.city.trim().isNotEmpty)
                    company.city.trim(),
                ].join(' · '),
          kind: ModuleStartValueKind.text,
          onTap: () => open('/settings/company'),
        ),
        figureUsers,
        figureBackup,
        figureChannels,
      ],
      phoneFigures: [figureUsers, figureBackup, figureChannels],
    );
  }

  List<ModuleStartGroup> _groups(
    BuildContext context,
    CurrentUserProfile? profile,
  ) {
    final now = DateTime.now();
    final backup = _overview?.backup;
    final channels = _overview?.channels;
    final expired = channels?.expiredAt(now) ?? const <MetaChannelProvider>[];
    DateTime? expiredSince;
    for (final channel in channels?.meta ?? const <MetaChannelStatus>[]) {
      final at = channel.authorizationExpiresAt;
      if (channel.isActive &&
          channel.authorizationExpiredAt(now) &&
          at != null) {
        if (expiredSince == null || at.isBefore(expiredSince)) {
          expiredSince = at;
        }
      }
    }

    ModuleStartEntry entry(
      String title,
      String description,
      IconData icon,
      String route, {
      bool destructive = false,
      String? compactAttention,
    }) =>
        ModuleStartEntry(
          key: ValueKey('settings-entry-$route'),
          title: title,
          description: description,
          icon: icon,
          destructive: destructive,
          compactAttention: compactAttention,
          onTap: () => context.push(route),
        );

    return [
      ModuleStartGroup(
        title: 'Empresa y acceso',
        description: 'Datos, horario, usuarios y apariencia',
        icon: Icons.apartment_rounded,
        tone: ModuleStartTone.a,
        entries: [
          entry(
              'Datos de la empresa',
              'Razón social, RUT, giro, contacto y dirección',
              Icons.badge_outlined,
              '/settings/company'),
          entry('Horario de atención', 'Semana laboral, tienda y nóminas',
              Icons.schedule_rounded, '/settings/business-hours'),
          if (profile?.canManageUsers == true)
            entry(
                'Usuarios y roles',
                'Invitaciones, permisos y estado de acceso',
                Icons.group_outlined,
                '/settings/users'),
          entry('Apariencia', 'Tema, logo e ícono de inicio',
              Icons.contrast_rounded, '/settings/appearance'),
        ],
      ),
      ModuleStartGroup(
        title: 'Canales y avisos',
        description: 'WhatsApp, Meta y notificaciones',
        icon: Icons.chat_bubble_outline_rounded,
        tone: ModuleStartTone.d,
        entries: [
          entry('WhatsApp', 'Canales, plantilla inicial y costos de Meta',
              Icons.forum_outlined, '/settings/whatsapp'),
          entry(
            'Instagram y Messenger',
            'Conexión, permisos y estado de los canales',
            Icons.camera_alt_outlined,
            '/settings/meta',
            compactAttention: expired.isEmpty
                ? null
                : expiredSince == null
                    ? 'Autorización vencida'
                    : 'Autorización vencida el ${_date(expiredSince, year: false)}',
          ),
          entry('Notificaciones', 'Preferencias del dispositivo y pruebas',
              Icons.notifications_none_rounded, '/settings/notifications'),
        ],
      ),
      ModuleStartGroup(
        title: 'Operación y dispositivos',
        description: 'Lectores, escáner e impresora',
        icon: Icons.qr_code_scanner_rounded,
        tone: ModuleStartTone.c,
        entries: [
          entry(
              'Lector USB o teclado',
              'Captura de códigos desde un lector tipo teclado',
              Icons.keyboard_outlined,
              '/settings/keyboard-scanner'),
          entry(
              'Lector Bluetooth',
              'Conexión de un lector inalámbrico compatible',
              Icons.bluetooth_rounded,
              '/settings/bluetooth-scanner'),
          entry('Escáner móvil', 'Usa un celular como lector remoto',
              Icons.phone_android_rounded, '/settings/remote-scanner'),
          entry(
              'Impresora de etiquetas',
              'NIIMBOT y ajustes de impresión térmica',
              Icons.print_outlined,
              '/settings/label-printer'),
        ],
      ),
      ModuleStartGroup(
        title: 'Finanzas',
        description: 'Pagos, terminales y cuentas',
        icon: Icons.account_balance_wallet_outlined,
        tone: ModuleStartTone.b,
        entries: [
          entry(
              'Métodos de pago',
              'Efectivo, transferencias, tarjetas y cuentas',
              Icons.payments_outlined,
              '/settings/payment-methods'),
          entry(
              'Terminales y abonos',
              'Débito, crédito, comisiones y plazos por terminal',
              Icons.point_of_sale_rounded,
              '/settings/payment-terminals'),
          entry('Plan de cuentas', 'Cuentas contables que usan ventas y pagos',
              Icons.menu_book_outlined, '/accounting/accounts'),
        ],
      ),
      ModuleStartGroup(
        title: 'Sistema y datos',
        description: 'Respaldo y reinicio',
        icon: Icons.storage_rounded,
        tone: ModuleStartTone.danger,
        entries: [
          entry(
            'Respaldo y restauración',
            'Copias, agenda y recuperación',
            Icons.cloud_upload_outlined,
            '/settings/backup',
            compactAttention:
                backup == null || !(backup.isStale(now) || !backup.scheduled)
                    ? null
                    : [
                        if (backup.lastBackupAt == null)
                          'Sin respaldos'
                        else
                          'Último ${_age(now.difference(backup.lastBackupAt!))}',
                        if (!backup.scheduled) 'sin agenda',
                      ].join(' · '),
          ),
          entry('Reinicio de datos', 'Eliminación controlada por módulo',
              Icons.restart_alt_rounded, '/settings/factory-reset',
              destructive: true),
        ],
      ),
      ModuleStartGroup(
        title: 'Plataforma',
        tone: ModuleStartTone.neutral,
        entries: [
          ModuleStartEntry(
            key: const ValueKey('settings-about'),
            title: 'Acerca de Viñabike ERP',
            description: _version == null
                ? 'Versión instalada'
                : _version!.contains('+')
                    ? 'Versión ${_version!.split('+').first} · compilación '
                        '${_version!.split('+').last}'
                    : 'Versión $_version',
            icon: Icons.info_outline_rounded,
            onTap: _showAbout,
          ),
        ],
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.phone, required this.version});

  final bool phone;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: moduleStartGutter(phone),
        vertical: phone ? 8 : 14,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Configuración',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: phone ? 19 : null,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          if (!phone && version != null)
            Text(
              'Viñabike ERP $version',
              key: const ValueKey('settings-version'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// A value on the band the operator copies for support: the subdomain and
/// the company's ID.
class _CopyChip extends StatelessWidget {
  const _CopyChip({
    super.key,
    required this.label,
    required this.value,
    required this.onCopy,
    this.semanticValue,
  });

  final String label;
  final String value;
  final String? semanticValue;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final shell = VinabikeThemeRoles.of(context).shell;
    return Tooltip(
      message: 'Copiar ${label.toLowerCase()}',
      child: Material(
        color: shell.raised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(10),
          child: Semantics(
            button: true,
            label: 'Copiar $label ${semanticValue ?? value}',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: shell.mutedForeground,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: TextStyle(
                        color: shell.foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: shell.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _roleLabel(String? role) => switch (role) {
      'owner' => 'Propietario',
      'admin' => 'Administrador',
      'manager' => 'Encargado',
      'employee' => 'Colaborador',
      'mechanic' => 'Mecánico',
      null || '' => 'Sin rol',
      _ => role,
    };

String _rolePlural(String role) => switch (role) {
      'owner' => 'propietarios',
      'admin' => 'administradores',
      'manager' => 'encargados',
      'employee' => 'colaboradores',
      'mechanic' => 'mecánicos',
      _ => role,
    };

String _usersCaption(SettingsUsersOverview users) {
  if (users.active == 0) return 'nadie activo';
  if (users.roles.length == 1) {
    final role = users.roles.single;
    return users.active == 1
        ? _roleLabel(role).toLowerCase()
        : 'todos ${_rolePlural(role)}';
  }
  return '${users.roles.length} roles distintos';
}

String _providerNames(List<MetaChannelProvider> providers) {
  final names = [
    for (final provider in providers)
      provider == MetaChannelProvider.facebookMessenger
          ? 'Messenger'
          : provider.label,
  ];
  return names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
}

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// On the shop's clock, whatever zone the device runs on.
String _date(DateTime value, {bool year = true}) {
  final local = shopTime(value);
  final day = '${local.day} ${_months[local.month - 1]}';
  return year ? '$day ${local.year}' : day;
}

String _age(Duration elapsed) {
  final days = elapsed.inDays;
  if (days < 1) return 'hoy';
  if (days == 1) return 'ayer';
  if (days < 30) return 'hace $days días';
  if (days >= 365) return 'hace más de un año';
  final months = days ~/ 30;
  return months == 1 ? 'hace un mes' : 'hace $months meses';
}
