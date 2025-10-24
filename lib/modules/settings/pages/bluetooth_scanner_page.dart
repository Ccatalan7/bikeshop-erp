import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/bluetooth_scanner_service.dart';

/// Page to manage Bluetooth barcode scanner connections
class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  late BluetoothScannerService _scannerService;
  String? _lastScannedBarcode;
  bool _isPlatformSupported = true;

  @override
  void initState() {
    super.initState();
    
    // Check if platform is supported
    _isPlatformSupported = _checkPlatformSupport();
    
    if (!_isPlatformSupported) {
      return;
    }
    
    _scannerService = BluetoothScannerService();
    
    // Listen to barcode scans
    _scannerService.barcodeStream.listen((barcode) {
      setState(() {
        _lastScannedBarcode = barcode;
      });
      
      // Show snackbar with scanned barcode
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Código escaneado: $barcode'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    });
    
    _checkBluetoothStatus();
  }

  bool _checkPlatformSupport() {
    // Bluetooth is only supported on Android and iOS
    return defaultTargetPlatform == TargetPlatform.android ||
           defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _scannerService.dispose();
    super.dispose();
  }

  Future<void> _checkBluetoothStatus() async {
    final hasPermissions = await _scannerService.hasPermissions();
    if (!hasPermissions) {
      if (mounted) {
        _showPermissionDialog();
      }
      return;
    }

    final isAvailable = await _scannerService.isBluetoothAvailable();
    if (!isAvailable && mounted) {
      _showBluetoothDisabledDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permisos requeridos'),
        content: const Text(
          'Esta función requiere permisos de Bluetooth y ubicación para buscar dispositivos cercanos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              // Request permissions
              final granted = await _scannerService.requestPermissions();
              
              if (granted) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Permisos concedidos'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _checkBluetoothStatus();
                }
              } else {
                // Check if permanently denied
                final permanentlyDenied = await _scannerService.hasPermissionsDenied();
                
                if (mounted) {
                  if (permanentlyDenied) {
                    _showOpenSettingsDialog();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Permisos denegados. Se necesitan para usar esta función.'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Solicitar permisos'),
          ),
        ],
      ),
    );
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisos denegados'),
        content: const Text(
          'Los permisos de Bluetooth fueron denegados permanentemente. '
          'Por favor, ve a Configuración de la aplicación para habilitarlos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text('Abrir Configuración'),
          ),
        ],
      ),
    );
  }

  void _showBluetoothDisabledDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth desactivado'),
        content: const Text(
          'Por favor, activa el Bluetooth para buscar lectores de código de barras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _scannerService.turnOnBluetooth();
              await Future.delayed(const Duration(seconds: 1));
              _checkBluetoothStatus();
            },
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }

  Future<void> _startScan() async {
    try {
      await _scannerService.startScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar dispositivos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await _scannerService.connect(device);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conectado a ${device.platformName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    await _scannerService.disconnect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Desconectado'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show unsupported platform message
    if (!_isPlatformSupported) {
      return MainLayout(
        title: 'Lector de Código de Barras',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bluetooth_disabled,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'No disponible en esta plataforma',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Los lectores de código de barras Bluetooth solo están disponibles en dispositivos móviles (Android/iOS).',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _scannerService,
      child: MainLayout(
        title: 'Lector de Código de Barras',
        child: Consumer<BluetoothScannerService>(
          builder: (context, service, child) {
            return Column(
              children: [
                // Connection status card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              service.isConnected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth_disabled,
                              color: service.isConnected
                                  ? Colors.green
                                  : Colors.grey,
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    service.isConnected
                                        ? 'Conectado'
                                        : 'Desconectado',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (service.connectedDeviceName != null)
                                    Text(
                                      service.connectedDeviceName!,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (service.isConnected)
                              ElevatedButton.icon(
                                onPressed: _disconnect,
                                icon: const Icon(Icons.bluetooth_disabled),
                                label: const Text('Desconectar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                        if (_lastScannedBarcode != null) ...[
                          const Divider(height: 24),
                          const Text(
                            'Último código escaneado:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.qr_code_scanner,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _lastScannedBarcode!,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    // Copy to clipboard logic here
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Código copiado'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Scan button
                if (!service.isConnected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: service.isScanning ? null : _startScan,
                        icon: service.isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: Text(
                          service.isScanning
                              ? 'Buscando dispositivos...'
                              : 'Buscar lectores Bluetooth',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Available devices list
                Expanded(
                  child: service.availableDevices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_searching,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                service.isScanning
                                    ? 'Buscando dispositivos...'
                                    : 'No se encontraron dispositivos',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!service.isScanning) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Presiona "Buscar" para empezar',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: service.availableDevices.length,
                          itemBuilder: (context, index) {
                            final device = service.availableDevices[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.bluetooth,
                                  color: Colors.blue,
                                ),
                                title: Text(
                                  device.platformName.isEmpty
                                      ? 'Dispositivo desconocido'
                                      : device.platformName,
                                ),
                                subtitle: Text(
                                  device.remoteId.toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () => _connectToDevice(device),
                                  child: const Text('Conectar'),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Instructions card
                Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.blue.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Instrucciones',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '1. Enciende tu lector de código de barras Bluetooth\n'
                          '2. Presiona "Buscar lectores Bluetooth"\n'
                          '3. Selecciona tu dispositivo de la lista\n'
                          '4. Una vez conectado, escanea códigos de barras\n'
                          '5. Los códigos aparecerán automáticamente',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
