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

      // Get tenant info
      final profileData = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id, role')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profileData != null) {
        _tenantId = profileData['tenant_id'];
        _role = profileData['role'];

        // Get subdomain
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
      ),
      body: ListView(
        children: [
          // User/Tenant Info Section
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: BrandedLoading()),
            )
          else
            _buildSection(
              context,
              title: 'Información de Cuenta',
              icon: Icons.account_circle,
              children: [
                ListTile(
                  leading: const Icon(Icons.email, color: Colors.blue),
                  title: const Text('Email'),
                  subtitle: Text(_userEmail ?? 'No disponible'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        _copyToClipboard(_userEmail ?? '', 'Email'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.store, color: Colors.orange),
                  title: const Text('Tienda (Subdomain)'),
                  subtitle: Text(_subdomain ?? 'No disponible'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        _copyToClipboard(_subdomain ?? '', 'Subdomain'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.badge, color: Colors.purple),
                  title: const Text('Rol'),
                  subtitle: Text(_role ?? 'No disponible'),
                ),
                ListTile(
                  leading: const Icon(Icons.vpn_key, color: Colors.green),
                  title: const Text('Tenant ID'),
                  subtitle: Text(_tenantId ?? 'No disponible'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        _copyToClipboard(_tenantId ?? '', 'Tenant ID'),
                  ),
                ),
              ],
            ),
          _buildSection(
            context,
            title: 'Sistema',
            icon: Icons.settings_backup_restore,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.backup,
                title: 'Respaldo y Restauración',
                subtitle: 'Crear respaldos automáticos y restaurar datos',
                iconColor: Colors.blue,
                onTap: () => context.push('/settings/backup'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.notifications,
                title: 'Notificaciones',
                subtitle: 'Configurar alertas y dispositivos',
                iconColor: Colors.orange,
                onTap: () => context.push('/settings/notifications'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.delete_forever,
                title: 'Reiniciar Sistema',
                subtitle: 'Eliminar todos los datos y comenzar de nuevo',
                iconColor: Colors.red,
                onTap: () => context.push('/settings/factory-reset'),
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Empresa',
            icon: Icons.business,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.people,
                title: 'Gestión de Usuarios',
                subtitle: 'Invitar usuarios, roles y permisos',
                iconColor: Colors.blue,
                onTap: () => context.push('/settings/users'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.info,
                title: 'Información de la Empresa',
                subtitle: 'Nombre, RUT, dirección, logo',
                iconColor: Colors.orange,
                onTap: () {
                  // TODO: Implement company info
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
              ),
              _buildSettingTile(
                context,
                icon: Icons.attach_money,
                title: 'Moneda y Región',
                subtitle: 'CLP, zona horaria, formato de fecha',
                iconColor: Colors.green,
                onTap: () {
                  // TODO: Implement currency settings
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Apariencia',
            icon: Icons.palette,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.image_outlined,
                title: 'Logo de la Empresa',
                subtitle: 'Subir logo personalizado para el encabezado',
                iconColor: Colors.blue,
                onTap: () => context.push('/settings/appearance'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.dark_mode,
                title: 'Tema',
                subtitle: 'Claro, oscuro, automático',
                iconColor: Colors.purple,
                onTap: () => context.push('/settings/appearance'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.language,
                title: 'Idioma',
                subtitle: 'Español, English',
                iconColor: Colors.indigo,
                onTap: () {
                  // TODO: Implement language selector
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Dispositivos',
            icon: Icons.devices,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.usb,
                title: 'Lector USB/Teclado',
                subtitle: 'Lector de código de barras USB (Windows/Desktop)',
                iconColor: Colors.green,
                onTap: () => context.push('/settings/keyboard-scanner'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.bluetooth,
                title: 'Lector Bluetooth',
                subtitle: 'Conectar lector Bluetooth (Windows/Android/iOS)',
                iconColor: Colors.blue,
                onTap: () => context.push('/settings/bluetooth-scanner'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.phone_android,
                title: 'Escáner Remoto (Celular)',
                subtitle: 'Usar tu celular como escáner de código de barras',
                iconColor: Colors.deepPurple,
                onTap: () => context.push('/settings/remote-scanner'),
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Contabilidad',
            icon: Icons.account_balance,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.payment,
                title: 'Métodos de Pago',
                subtitle: 'Configurar efectivo, transferencia, tarjetas',
                iconColor: Colors.green,
                onTap: () => context.push('/settings/payment-methods'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.receipt,
                title: 'Impuestos',
                subtitle: 'Configurar IVA y otros impuestos',
                iconColor: Colors.teal,
                onTap: () {
                  // TODO: Implement tax settings
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
              ),
              _buildSettingTile(
                context,
                icon: Icons.account_tree,
                title: 'Plan de Cuentas',
                subtitle: 'Gestionar cuentas contables',
                iconColor: Colors.brown,
                onTap: () => context.push('/accounting/chart-of-accounts'),
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Usuarios y Seguridad',
            icon: Icons.security,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.people,
                title: 'Usuarios',
                subtitle: 'Gestionar usuarios del sistema',
                iconColor: Colors.cyan,
                onTap: () {
                  // TODO: Implement user management
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
              ),
              _buildSettingTile(
                context,
                icon: Icons.lock,
                title: 'Permisos',
                subtitle: 'Control de acceso por módulo',
                iconColor: Colors.deepOrange,
                onTap: () {
                  // TODO: Implement permissions
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Acerca de',
            icon: Icons.info_outline,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.info,
                title: 'Versión',
                subtitle: 'v1.0.0 - Vinabike ERP',
                iconColor: Colors.grey,
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Vinabike ERP',
                    applicationVersion: '1.0.0',
                    applicationIcon:
                        const Icon(Icons.directions_bike, size: 48),
                    children: [
                      const Text(
                          'Sistema ERP completo para gestión de bikeshop'),
                      const SizedBox(height: 8),
                      const Text('Incluye: Contabilidad, Inventario, Ventas, '
                          'Compras, POS, CRM, Mantención, RR.HH. y más.'),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withOpacity(0.1),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
