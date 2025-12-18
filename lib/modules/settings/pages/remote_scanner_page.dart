import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/config/supabase_config.dart';
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/barcode_scan_event.dart';

/// Page to manage remote phone scanner connections
class RemoteScannerPage extends StatefulWidget {
  const RemoteScannerPage({super.key});

  @override
  State<RemoteScannerPage> createState() => _RemoteScannerPageState();
}

class _RemoteScannerPageState extends State<RemoteScannerPage> {
  final _remoteScannerService = RemoteScannerService();
  String? _deviceId;
  final List<BarcodeScanEvent> _recentScans = [];
  bool _hasActivity = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    _listenToScans();
  }

  Future<void> _loadDeviceId() async {
    final id = await _remoteScannerService.getDeviceId();
    setState(() => _deviceId = id);
  }

  void _listenToScans() {
    // Just listen to update the UI list, do not manage lifecycle here
    _remoteScannerService.scanStream.listen((scan) {
      if (!mounted) return;
      setState(() {
        _hasActivity = true; // Mark as active on first scan
        _recentScans.insert(0, scan);
        if (_recentScans.length > 20) {
          _recentScans.removeLast();
        }
      });
      // No snackbar here, as it might be annoying if scanning rapidly
    });
  }

  void _copyDeviceId() {
    if (_deviceId != null) {
      Clipboard.setData(ClipboardData(text: _deviceId!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 ID copiado al portapapeles'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    // IMPORTANT: Do NOT stop the service here. It must remain active for the global app.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Escáner Móvil'),
        elevation: 0,
      ),
      body: _deviceId == null
          ? const Center(child: BrandedLoading())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 1. Hero Connection Card
                  _buildConnectionCard(),

                  const SizedBox(height: 32),
                  // 2. Recent Scans Title
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Última Actividad',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Scans List
                  _buildRecentScansList(),
                ],
              ),
            ),
    );
  }

  Widget _buildConnectionCard() {
    final isConnected = _hasActivity;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              color: isConnected
                  ? Colors.green[50]
                  : Colors.orange[50], // Dynamic Color
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green
                        : Colors.orange, // Dynamic Dot
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected
                      ? 'Dispositivo Conectado'
                      : 'Esperando Conexión...', // Dynamic Text
                  style: TextStyle(
                    color: isConnected ? Colors.green[800] : Colors.orange[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Text(
                  'Conecta tu Celular',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Abre la app Vinabike Scanner y apunta aquí',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),

                // QR Code
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.1),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _generateQrData(),
                    version: QrVersions.auto,
                    size: 220,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Manual Code Copy
                InkWell(
                  onTap: _copyDeviceId,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'ID: ${_deviceId?.substring(0, 8)}...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Disconnect Button
                TextButton.icon(
                  onPressed: _resetConnection,
                  icon: Icon(Icons.link_off, color: Colors.red[300], size: 20),
                  label: Text(
                    'Desconectar todos los dispositivos',
                    style: TextStyle(color: Colors.red[300]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetConnection() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desconectar todo?'),
        content: const Text(
          'Esto cambiará el ID de conexión.\n'
          'Todos los celulares conectados dejarán de funcionar y tendrás que volver a escanear el QR.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _remoteScannerService.resetDeviceId();
      _loadDeviceId(); // Reload new ID to update QR

      setState(() {
        _hasActivity = false; // Reset UI state to "Waiting"
        _recentScans.clear(); // Clear old history
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Conexión reiniciada. Nuevo QR generado.')),
        );
      }
    }
  }

  Widget _buildRecentScansList() {
    if (_recentScans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.qr_code_2, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text(
                'Esperando escaneos...',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _recentScans.map((scan) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[100]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.qr_code, color: Colors.blue, size: 20),
            ),
            title: Text(
              scan.barcode,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _formatTime(scan.timestamp),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing:
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
          ),
        );
      }).toList(),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return 'Hace ${diff.inDays}d';
  }

  String _generateQrData() {
    final config = {
      'url': SupabaseConfig.url,
      'key': SupabaseConfig.anonKey,
      'deviceId': _deviceId,
    };
    return jsonEncode(config);
  }
}
