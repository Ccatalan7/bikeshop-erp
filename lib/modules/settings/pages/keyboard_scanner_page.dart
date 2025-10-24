import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/barcode_scanner_service.dart';

/// Page to manage USB/Keyboard barcode scanner
/// Works on Windows, macOS, Linux, and Web
class KeyboardScannerPage extends StatefulWidget {
  const KeyboardScannerPage({super.key});

  @override
  State<KeyboardScannerPage> createState() => _KeyboardScannerPageState();
}

class _KeyboardScannerPageState extends State<KeyboardScannerPage> {
  late BarcodeScannerService _scannerService;
  final List<String> _recentScans = [];
  final FocusNode _focusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    _scannerService = BarcodeScannerService();
    
    // Listen to barcode scans
    _scannerService.barcodeStream.listen((barcode) {
      setState(() {
        _recentScans.insert(0, barcode);
        if (_recentScans.length > 20) {
          _recentScans.removeLast();
        }
      });
      
      // Show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📦 Código escaneado: $barcode'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
    
    // Auto-start listening
    _scannerService.startListening();
    
    // Request focus after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }
  
  @override
  void dispose() {
    _scannerService.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _scannerService,
      child: MainLayout(
        title: 'Lector USB/Teclado',
        child: RawKeyboardListener(
          focusNode: _focusNode,
          onKey: _scannerService.processKeyEvent,
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Consumer<BarcodeScannerService>(
              builder: (context, service, child) {
                return Column(
                  children: [
                    // Status card
                    Card(
                      margin: const EdgeInsets.all(16),
                      color: service.isListening 
                          ? Colors.green.shade50 
                          : Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  service.isListening 
                                      ? Icons.qr_code_scanner 
                                      : Icons.qr_code_scanner_outlined,
                                  color: service.isListening 
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
                                        service.isListening 
                                            ? '✅ Escuchando' 
                                            : '❌ Detenido',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        service.isListening
                                            ? 'Escanea cualquier código de barras'
                                            : 'Presiona iniciar para comenzar',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (service.isListening) {
                                      service.stopListening();
                                    } else {
                                      service.startListening();
                                      _focusNode.requestFocus();
                                    }
                                  },
                                  icon: Icon(
                                    service.isListening 
                                        ? Icons.stop 
                                        : Icons.play_arrow,
                                  ),
                                  label: Text(
                                    service.isListening 
                                        ? 'Detener' 
                                        : 'Iniciar',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: service.isListening 
                                        ? Colors.red 
                                        : Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              'ℹ️ Instrucciones:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildInstructionRow(
                              '1',
                              'Conecta tu lector USB de código de barras',
                            ),
                            _buildInstructionRow(
                              '2',
                              'Presiona "Iniciar" (se activa automáticamente)',
                            ),
                            _buildInstructionRow(
                              '3',
                              'Escanea cualquier código de barras',
                            ),
                            _buildInstructionRow(
                              '4',
                              'El código aparecerá automáticamente',
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.amber.shade800),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Compatible con cualquier lector USB que emule teclado (HID). '
                                      'Funciona en Windows, macOS, Linux y Web.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Recent scans
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            'Códigos recientes (${_recentScans.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (_recentScans.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                setState(() => _recentScans.clear());
                              },
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: const Text('Limpiar'),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Scans list
                    Expanded(
                      child: _recentScans.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.qr_code_2,
                                    size: 64,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No hay códigos escaneados',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Escanea un código para comenzar',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _recentScans.length,
                              itemBuilder: (context, index) {
                                final barcode = _recentScans[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.green,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      barcode,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 20),
                                          tooltip: 'Copiar',
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(text: barcode),
                                            );
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Código copiado'),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.search, size: 20),
                                          tooltip: 'Buscar producto',
                                          onPressed: () {
                                            // TODO: Navigate to product search with barcode
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Buscando producto: $barcode'),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildInstructionRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue[100],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
