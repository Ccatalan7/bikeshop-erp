import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/scanner_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  final _manualController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _onQrCodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _isProcessing = true);

    try {
      final rawValue = barcode!.rawValue!;

      // Try to parse as JSON (New unified config + pairing flow)
      try {
        if (rawValue.trim().startsWith('{')) {
          await _configureAndPair(rawValue);
          return;
        }
      } catch (_) {
        // Not JSON, fall back to simple Device ID pairing
      }

      // Legacy/Manual pairing (simple ID)
      await _pairDevice(rawValue);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Parse JSON config and Pair
  Future<void> _configureAndPair(String jsonString) async {
    final Map<String, dynamic> data = jsonDecode(jsonString);

    final url = data['url'];
    final key = data['key'];
    final deviceId = data['deviceId'];

    if (url == null || key == null || deviceId == null) {
      throw Exception('Invalid QR format. Missing config fields.');
    }

    final scannerService = context.read<ScannerService>();

    // 1. Stop camera to release resources before navigation
    await _controller.stop();

    // 2. Configure Supabase
    await scannerService.configure(url, key);

    // 2. Pair Device
    await scannerService.pairDevice(deviceId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ ¡Configurado y Conectado!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _pairDevice(String deviceId) async {
    final scannerService = context.read<ScannerService>();

    // Ensure service is configured first
    if (!scannerService.isConfigured) {
      throw Exception(
          'App no configurada. Escanea el QR de configuración primero.');
    }

    // Stop camera if manual pairing triggers navigation
    await _controller.stop();
    await scannerService.pairDevice(deviceId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dispositivo emparejado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _onManualPair() async {
    final deviceId = _manualController.text.trim();
    if (deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un ID de dispositivo válido')),
      );
      return;
    }

    try {
      await _pairDevice(deviceId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📲 Emparejar Dispositivo'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onQrCodeDetected,
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '📸 Escanea el código QR mostrado en tu ERP de Windows',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'O ingresa manualmente el ID',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'ID del Dispositivo',
                      hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _onManualPair,
                    icon: const Icon(Icons.link),
                    label: const Text('Emparejar'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200, 50),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
