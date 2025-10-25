import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
      ),
      body: ListView(
        children: [
          _buildSection(
            context,
            title: 'Sistema',
            icon: Icons.settings_backup_restore,
            children: [
              _buildSettingTile(
                context,
                icon: Icons.delete_forever,
                title: 'Reiniciar Sistema',
                subtitle: 'Eliminar todos los datos y comenzar de nuevo',
                iconColor: Colors.red,
                onTap: () => context.push('/settings/factory-reset'),
              ),
              _buildSettingTile(
                context,
                icon: Icons.backup,
                title: 'Respaldo de Datos',
                subtitle: 'Exportar todos los datos del sistema',
                iconColor: Colors.blue,
                onTap: () {
                  // TODO: Implement backup
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
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
                onTap: () {
                  // TODO: Implement theme selector
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente...')),
                  );
                },
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
