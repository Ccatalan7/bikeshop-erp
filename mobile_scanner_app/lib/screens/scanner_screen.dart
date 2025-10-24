import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/scanner_service.dart';
import 'package:intl/intl.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController();
  bool _isScanning = true;
  bool _isProcessing = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing || !_isScanning) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final code = barcode!.rawValue!;

    // Prevent duplicate scans within 2 seconds
    if (_lastScannedCode == code &&
        _lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastScannedCode = code;
      _lastScanTime = DateTime.now();
    });

    try {
      final scannerService = context.read<ScannerService>();
      await scannerService.sendScan(code);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Enviado: $code'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _unpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desemparejar Dispositivo'),
        content: const Text('¿Estás seguro de que quieres desemparejar este dispositivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Desemparejar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scannerService = context.read<ScannerService>();
      await scannerService.unpairDevice();
    }
  }

  void _showModuleSelector() {
    final scannerService = context.read<ScannerService>();
    
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text(
              'Seleccionar Módulo Objetivo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          _buildModuleTile('Todos (Auto)', null, scannerService),
          _buildModuleTile('🛒 POS', 'pos', scannerService),
          _buildModuleTile('📦 Inventario', 'inventory', scannerService),
          _buildModuleTile('🧾 Ventas', 'sales', scannerService),
          _buildModuleTile('📥 Compras', 'purchases', scannerService),
          _buildModuleTile('🔧 Mantenimiento', 'maintenance', scannerService),
        ],
      ),
    );
  }

  Widget _buildModuleTile(String label, String? module, ScannerService service) {
    final isSelected = service.targetModule == module;
    
    return ListTile(
      title: Text(label),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
      selected: isSelected,
      onTap: () {
        service.setTargetModule(module);
        Navigator.pop(context);
      },
    );
  }

  void _showHistory() {
    final scannerService = context.read<ScannerService>();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            AppBar(
              title: const Text('📋 Historial'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () {
                    scannerService.clearHistory();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Limpiar',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: scannerService.scanHistory.isEmpty
                  ? const Center(
                      child: Text('No hay escaneos aún'),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: scannerService.scanHistory.length,
                      itemBuilder: (context, index) {
                        final scan = scannerService.scanHistory[index];
                        return ListTile(
                          leading: Icon(
                            scan.sent ? Icons.check_circle : Icons.error,
                            color: scan.sent ? Colors.green : Colors.red,
                          ),
                          title: Text(
                            scan.barcode,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            '${DateFormat('HH:mm:ss').format(scan.timestamp)}${scan.targetModule != null ? ' → ${scan.targetModule}' : ''}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📷 Vinabike Scanner'),
        actions: [
          IconButton(
            onPressed: _showModuleSelector,
            icon: const Icon(Icons.tune),
            tooltip: 'Módulo objetivo',
          ),
          IconButton(
            onPressed: _showHistory,
            icon: const Icon(Icons.history),
            tooltip: 'Historial',
          ),
          IconButton(
            onPressed: _unpair,
            icon: const Icon(Icons.link_off),
            tooltip: 'Desemparejar',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onBarcodeDetected,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Consumer<ScannerService>(
              builder: (context, service, _) => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    if (service.targetModule != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Módulo: ${service.targetModule}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionButton(
                          icon: _isScanning ? Icons.pause : Icons.play_arrow,
                          label: _isScanning ? 'Pausar' : 'Reanudar',
                          onPressed: () {
                            setState(() => _isScanning = !_isScanning);
                            if (_isScanning) {
                              _controller.start();
                            } else {
                              _controller.stop();
                            }
                          },
                        ),
                        _buildActionButton(
                          icon: Icons.flip_camera_android,
                          label: 'Voltear',
                          onPressed: () => _controller.switchCamera(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }
}
