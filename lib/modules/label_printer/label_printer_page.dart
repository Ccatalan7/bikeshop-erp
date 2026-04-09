import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../modules/inventory/models/inventory_models.dart';
import '../../modules/inventory/services/inventory_service.dart';
import '../../shared/services/niimbot_printer_service.dart';
import '../../shared/services/ocr_service.dart';
import '../../shared/widgets/main_layout.dart';

// ══════════════════════════════════════════════════════════════════════════════
// LabelPrinterPage
// ══════════════════════════════════════════════════════════════════════════════

class LabelPrinterPage extends StatefulWidget {
  const LabelPrinterPage({super.key});

  @override
  State<LabelPrinterPage> createState() => _LabelPrinterPageState();
}

class _LabelPrinterPageState extends State<LabelPrinterPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  late NiimbotPrinterService _printerService;
  late InventoryService _inventoryService;

  // ── State ─────────────────────────────────────────────────────────────────
  List<Product> _searchResults = [];
  bool _isSearching = false;
  bool _isOcrScanning = false;
  String? _ocrRawText;

  Product? _selectedProduct;
  Uint8List? _labelPreview;
  bool _isGeneratingPreview = false;

  int _printQuantity = 1;
  bool _isPrinting = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _printerService = context.read<NiimbotPrinterService>();
    _inventoryService = context.read<InventoryService>();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final products = await _inventoryService.getProducts(
        searchTerm: query.trim(),
      );
      if (mounted) {
        setState(() {
          _searchResults = products.take(20).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _searchResults = [];
      _searchController.text = product.name;
      _ocrRawText = null;
      _labelPreview = null;
    });
    _focusNode.unfocus();
    _generatePreview(product);
  }

  // ── OCR ───────────────────────────────────────────────────────────────────

  Future<void> _scanPackagingWithCamera() async {
    final picker = ImagePicker();
    XFile? image;

    try {
      image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara: $e')),
        );
      }
      return;
    }

    if (image == null) return;

    setState(() {
      _isOcrScanning = true;
      _ocrRawText = null;
      _selectedProduct = null;
      _labelPreview = null;
      _searchResults = [];
    });

    try {
      final ocrService = OCRService();
      final text = await ocrService.extractText(image.path);
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final rawText = lines.join(' ');

      setState(() {
        _ocrRawText = rawText;
        _searchController.text =
            rawText.length > 60 ? rawText.substring(0, 60) : rawText;
      });

      // Search with the best candidate tokens
      final bestQuery = _buildSearchQueryFromOcr(lines);
      await _onSearchChanged(bestQuery);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error OCR: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOcrScanning = false);
    }
  }

  /// Picks the best 2-3 tokens from OCR lines for a product search query.
  String _buildSearchQueryFromOcr(List<String> lines) {
    // Skip very short lines and common non-product words
    final skipPatterns = RegExp(
      r'^(ref|sku|cod|ean|barcode|precio|price|neto|\d{8,}|\$|#)',
      caseSensitive: false,
    );

    final candidates = lines
        .where((l) => l.length > 3 && !skipPatterns.hasMatch(l))
        .take(4)
        .toList();

    if (candidates.isEmpty) return lines.first;

    // Pick the longest line as the primary product name
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  // ── Label preview ─────────────────────────────────────────────────────────

  Future<void> _generatePreview(Product product) async {
    setState(() => _isGeneratingPreview = true);

    final bytes = await _printerService.previewProductLabel(product);
    if (mounted) {
      setState(() {
        _labelPreview = bytes;
        _isGeneratingPreview = false;
      });
    }
  }

  // ── Print ─────────────────────────────────────────────────────────────────

  Future<void> _print() async {
    final product = _selectedProduct;
    if (product == null) return;

    if (!_printerService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Impresora no conectada. Configura la impresora primero.'),
          action: SnackBarAction(
            label: 'Configurar',
            onPressed: () => context.push('/settings/label-printer'),
          ),
        ),
      );
      return;
    }

    setState(() => _isPrinting = true);

    final success = await _printerService.printProductLabel(
      product,
      quantity: _printQuantity,
    );

    if (mounted) {
      setState(() => _isPrinting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '✅ Impreso: $_printQuantity etiqueta(s) de ${product.name}'
              : '❌ Error al imprimir: ${_printerService.lastError}'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Impresora de Etiquetas',
      child: Consumer<NiimbotPrinterService>(
        builder: (context, printer, _) {
          return Column(
            children: [
              _buildPrinterStatusBar(printer),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSearchSection(),
                      if (_searchResults.isNotEmpty) _buildSearchResults(),
                      if (_isOcrScanning) _buildOcrLoadingCard(),
                      if (_ocrRawText != null &&
                          _searchResults.isEmpty &&
                          !_isOcrScanning)
                        _buildOcrResultCard(),
                      if (_selectedProduct != null) ...[
                        const SizedBox(height: 20),
                        _buildProductCard(_selectedProduct!),
                        const SizedBox(height: 16),
                        _buildLabelPreviewCard(),
                        const SizedBox(height: 16),
                        _buildPrintControls(printer),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Printer status bar ────────────────────────────────────────────────────

  Widget _buildPrinterStatusBar(NiimbotPrinterService printer) {
    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    switch (printer.status) {
      case NiimbotPrinterStatus.connected:
        bgColor = Colors.green.shade50;
        fgColor = Colors.green.shade800;
        icon = Icons.print;
        label = '${printer.connectedDeviceName ?? 'Impresora'} — conectada';
        break;
      case NiimbotPrinterStatus.printing:
        bgColor = Colors.blue.shade50;
        fgColor = Colors.blue.shade800;
        icon = Icons.hourglass_top;
        label = 'Imprimiendo…';
        break;
      case NiimbotPrinterStatus.connecting:
        bgColor = Colors.orange.shade50;
        fgColor = Colors.orange.shade800;
        icon = Icons.bluetooth_searching;
        label = 'Conectando…';
        break;
      case NiimbotPrinterStatus.error:
        bgColor = Colors.red.shade50;
        fgColor = Colors.red.shade800;
        icon = Icons.error_outline;
        label = 'Error: ${printer.lastError ?? 'desconocido'}';
        break;
      default:
        bgColor = Colors.grey.shade100;
        fgColor = Colors.grey.shade700;
        icon = Icons.print_disabled;
        label = 'Sin impresora — toca ⚙ para configurar';
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: fgColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: fgColor, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: 'Configurar impresora',
            color: fgColor,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => context.push('/settings/label-printer'),
          ),
        ],
      ),
    );
  }

  // ── Search section ────────────────────────────────────────────────────────

  Widget _buildSearchSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buscar producto',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: 'Nombre, SKU o código de barras…',
                      prefixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 10),
                // Camera OCR button (Android/iOS only)
                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                  Tooltip(
                    message: 'Escanear packaging con cámara (OCR)',
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        backgroundColor: Colors.indigo,
                      ),
                      icon: _isOcrScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt, size: 20),
                      label: const Text('OCR'),
                      onPressed:
                          _isOcrScanning ? null : _scanPackagingWithCamera,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Search results dropdown ───────────────────────────────────────────────

  Widget _buildSearchResults() {
    return Card(
      margin: const EdgeInsets.only(top: 4),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _searchResults.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final p = _searchResults[i];
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue.shade50,
                child: Text(
                  p.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(p.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                'SKU: ${p.sku}${p.brand != null ? ' • ${p.brand}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                _formatPrice(p.price),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              onTap: () => _selectProduct(p),
            );
          },
        ),
      ),
    );
  }

  // ── OCR cards ─────────────────────────────────────────────────────────────

  Widget _buildOcrLoadingCard() {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Analizando imagen…',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('OCR en proceso',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrResultCard() {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.document_scanner, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Texto extraído (sin coincidencias)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _ocrRawText ?? '',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Intenta ajustar la búsqueda manualmente o captura otra imagen.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // ── Product card ──────────────────────────────────────────────────────────

  Widget _buildProductCard(Product product) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.inventory_2, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('SKU: ${product.sku}', Colors.grey),
                      if (product.brand != null)
                        _chip(product.brand!, Colors.blue),
                      if (product.gtin != null)
                        _chip('EAN: ${product.gtin}', Colors.green),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(product.price),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Stock: ${product.inventoryQty}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Label preview ─────────────────────────────────────────────────────────

  Widget _buildLabelPreviewCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vista previa',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label:
                      const Text('Regenerar', style: TextStyle(fontSize: 12)),
                  onPressed: _selectedProduct != null
                      ? () => _generatePreview(_selectedProduct!)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: _isGeneratingPreview
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    )
                  : _labelPreview != null
                      ? Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade200,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.memory(
                            _labelPreview!,
                            fit: BoxFit.contain,
                          ),
                        )
                      : Text(
                          'No disponible',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Print controls ────────────────────────────────────────────────────────

  Widget _buildPrintControls(NiimbotPrinterService printer) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Quantity row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Cantidad:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                _quantityButton(
                  icon: Icons.remove,
                  onTap: () {
                    if (_printQuantity > 1) setState(() => _printQuantity--);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '$_printQuantity',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _quantityButton(
                  icon: Icons.add,
                  onTap: () => setState(() => _printQuantity++),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Print button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      printer.isConnected ? Colors.green.shade700 : Colors.grey,
                ),
                icon: _isPrinting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print),
                label: Text(
                  _isPrinting
                      ? 'Imprimiendo…'
                      : printer.isConnected
                          ? 'Imprimir $_printQuantity etiqueta(s)'
                          : 'Sin impresora conectada',
                  style: const TextStyle(fontSize: 15),
                ),
                onPressed:
                    (_isPrinting || _selectedProduct == null) ? null : _print,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _quantityButton(
      {required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _chip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    if (price == 0) return 'Sin precio';
    final formatted = price.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return '\$$formatted';
  }
}
