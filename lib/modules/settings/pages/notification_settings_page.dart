import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/services/notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  String? _fcmToken;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final service = NotificationService();
    setState(() {
      _fcmToken = service.fcmToken;
      _notificationsEnabled = service.notificationsEnabled;
      _soundEnabled = service.soundEnabled;
      _vibrationEnabled = service.vibrationEnabled;
    });
  }

  Future<void> _setNotificationsEnabled(bool value) async {
    setState(() => _notificationsEnabled = value);
    await NotificationService().setNotificationsEnabled(value);
    if (value) {
      await _reRequestPermission();
    }
  }

  void _copyToken() {
    if (_fcmToken == null) return;
    Clipboard.setData(ClipboardData(text: _fcmToken!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token copiado al portapapeles')),
    );
  }

  void _sendTestNotification() {
    if (!_notificationsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activa las notificaciones antes de probarlas'),
        ),
      );
      return;
    }

    NotificationService().showLocalNotification(
      'Notificación de Prueba',
      '¡Si estás viendo esto, las notificaciones funcionan!',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notificación de prueba enviada')),
    );
  }

  Future<void> _reRequestPermission() async {
    await NotificationService().init();
    _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permisos solicitados nuevamente')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader(context, 'Configuración General'),
          ListTile(
            leading: const Icon(Icons.notifications_active, color: Colors.blue),
            title: const Text('Habilitar Notificaciones'),
            subtitle: const Text('Recibir alertas de nuevos mensajes'),
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: _setNotificationsEnabled,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up, color: Colors.purple),
            title: const Text('Sonido'),
            subtitle: const Text('Reproducir sonido con cada mensaje'),
            trailing: Switch(
              value: _soundEnabled,
              onChanged: _notificationsEnabled
                  ? (val) {
                      setState(() => _soundEnabled = val);
                      NotificationService().setSoundEnabled(val);
                    }
                  : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.vibration, color: Colors.teal),
            title: const Text('Vibración'),
            subtitle: const Text('Vibrar con cada mensaje'),
            trailing: Switch(
              value: _vibrationEnabled,
              onChanged: _notificationsEnabled
                  ? (val) {
                      setState(() => _vibrationEnabled = val);
                      NotificationService().setVibrationEnabled(val);
                    }
                  : null,
            ),
          ),
          const Divider(),
          _buildSectionHeader(context, 'Diagnóstico (Debug)'),
          ListTile(
            leading: const Icon(Icons.token, color: Colors.orange),
            title: const Text('FCM Token'),
            subtitle: Text(
              _fcmToken != null
                  ? '${_fcmToken!.substring(0, 10)}...${_fcmToken!.substring(_fcmToken!.length - 5)}'
                  : 'No disponible (Desktop o Sin Permiso)',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _fcmToken != null ? _copyToken : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report, color: Colors.green),
            title: const Text('Probar Notificación Local'),
            subtitle:
                const Text('Envía una alerta inmediata en este dispositivo'),
            trailing: OutlinedButton(
              onPressed: _notificationsEnabled ? _sendTestNotification : null,
              child: const Text('Probar'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.music_note, color: Colors.blueAccent),
            title: const Text('Probar Sonido'),
            subtitle: const Text('Reproduce el sonido de alerta'),
            trailing: OutlinedButton(
              onPressed: _notificationsEnabled && _soundEnabled
                  ? () {
                      NotificationService().playNotificationSound(
                        category: NotificationCategory.message,
                        preview: true,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reproduciendo sonido...'),
                        ),
                      );
                    }
                  : null,
              child: const Text('Sonar'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Nota: En macOS/Windows las notificaciones son locales. En Android/iOS/Web usan Firebase Cloud Messaging.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
