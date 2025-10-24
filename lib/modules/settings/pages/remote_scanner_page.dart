import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/config/supabase_config.dart';
import '../../../shared/services/remote_scanner_service.dart';
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
  bool _isListening = false;
  final List<BarcodeScanEvent> _recentScans = [];

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
    _remoteScannerService.scanStream.listen((scan) {
      setState(() {
        _recentScans.insert(0, scan);
        if (_recentScans.length > 20) {
          _recentScans.removeLast();
        }
      });
      
      // Show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 Escaneado: ${scan.barcode}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Future<void> _toggleListening() async {
    try {
      if (_isListening) {
        await _remoteScannerService.stopListening();
      } else {
        await _remoteScannerService.startListening();
      }
      setState(() => _isListening = !_isListening);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
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
    _remoteScannerService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📱 Escáner Remoto (Celular)'),
      ),
      body: _deviceId == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            _isListening ? Icons.phone_android : Icons.phone_disabled,
                            size: 64,
                            color: _isListening ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isListening
                                ? '✅ Escuchando escaneos remotos'
                                : '⏸️ Escáner remoto detenido',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _toggleListening,
                            icon: Icon(_isListening ? Icons.stop : Icons.play_arrow),
                            label: Text(_isListening ? 'Detener' : 'Iniciar'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR Code for pairing
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            '📲 Conecta tu celular',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Escanea este código QR con la app móvil.\n¡Se configurará automáticamente!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: _generateQrData(),
                              version: QrVersions.auto,
                              size: 200,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text(
                            'O ingresa manualmente el ID del dispositivo:',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SelectableText(
                                    _deviceId!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _copyDeviceId,
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copiar ID',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Recent scans
                  Text(
                    '📋 Escaneos recientes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_recentScans.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.qr_code_scanner,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No hay escaneos aún',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._recentScans.map((scan) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.qr_code, color: Colors.blue),
                            title: Text(
                              scan.barcode,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            subtitle: Text(
                              '${scan.deviceName} • ${_formatTime(scan.timestamp)}',
                            ),
                            trailing: scan.targetModule != null
                                ? Chip(
                                    label: Text(scan.targetModule!),
                                    backgroundColor: Colors.blue[100],
                                  )
                                : null,
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'Justo ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return 'Hace ${diff.inDays}d';
  }

  String _generateQrData() {
    // Embed Supabase config + device ID in QR
    final config = {
      'url': SupabaseConfig.url,
      'key': SupabaseConfig.anonKey,
      'deviceId': _deviceId,
    };
    return jsonEncode(config);
  }
}
