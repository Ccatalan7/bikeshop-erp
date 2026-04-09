import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/inventory/models/inventory_models.dart';

// ─────────────────────────────────────────────
// Status enum
// ─────────────────────────────────────────────
enum NiimbotPrinterStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  printing,
  error,
}

// ─────────────────────────────────────────────
// Device record
// ─────────────────────────────────────────────
class NiimbotPrinterDevice {
  final String deviceId;
  final String name;
  const NiimbotPrinterDevice({required this.deviceId, required this.name});
}

// ─────────────────────────────────────────────
// Label size presets  (8 px/mm = 203 DPI)
// ─────────────────────────────────────────────
class NiimbotLabelSize {
  final String key;
  final String label;
  final double widthMm;
  final double heightMm;

  int get widthPx => (widthMm * 8).round();
  int get heightPx => (heightMm * 8).round();

  const NiimbotLabelSize({
    required this.key,
    required this.label,
    required this.widthMm,
    required this.heightMm,
  });

  static const List<NiimbotLabelSize> presets = [
    NiimbotLabelSize(
        key: '40x30', label: '40×30 mm', widthMm: 40, heightMm: 30),
    NiimbotLabelSize(
        key: '50x30', label: '50×30 mm', widthMm: 50, heightMm: 30),
    NiimbotLabelSize(
        key: '40x20', label: '40×20 mm', widthMm: 40, heightMm: 20),
    NiimbotLabelSize(
        key: '60x40', label: '60×40 mm', widthMm: 60, heightMm: 40),
  ];

  static NiimbotLabelSize fromKey(String k) =>
      presets.firstWhere((p) => p.key == k, orElse: () => presets.first);
}

// ─────────────────────────────────────────────
// NIIMBOT BLE protocol constants
// Reverse-engineered from https://github.com/MultiMote/niimbluelib
// Packet: [0x55, 0x55, CMD, LEN, ...DATA, XOR_CHECKSUM, 0xAA, 0xAA]
// ─────────────────────────────────────────────
abstract class _Cmd {
  static const connect = 0xC1;
  static const startPrint = 0x01;
  static const endPrint = 0xF3;
  static const pageStart = 0x03;
  static const pageEnd = 0xE3;
  static const printClear = 0x20;
  static const setPageSize = 0x13;
  static const setQuantity = 0x15;
  static const setLabelDensity = 0x21;
  static const setLabelType = 0x23;
  static const writeBitmapRow = 0x85;
}

enum _NiimbotProtocolFamily { b1, d110 }

// Primary UUID set — 0xFF00 service  (D101 / D11 / B1 / B21 common firmware)
const _kSvc1 = '0000ff00-0000-1000-8000-00805f9b34fb';
const _kTx1 = '0000ff02-0000-1000-8000-00805f9b34fb';

// Secondary UUID set — e781 service  (some newer firmware)
const _kSvc2 = 'e7810a71-73ae-499d-8c15-faa9aef0c3f2';
const _kTx2 = 'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f';

// ─────────────────────────────────────────────
// NiimbotPrinterService
// ─────────────────────────────────────────────
// Label media type codes
enum NiimbotLabelType {
  gap(0x01, 'Con separador (gap)'),
  continuous(0x03, 'Continua (sin gap)'),
  blackMark(0x02, 'Marca negra');

  final int code;
  final String label;
  const NiimbotLabelType(this.code, this.label);

  static NiimbotLabelType fromCode(int c) => NiimbotLabelType.values
      .firstWhere((t) => t.code == c, orElse: () => NiimbotLabelType.gap);
}

class NiimbotPrinterService extends ChangeNotifier {
  static const _prefKeyDeviceId = 'niimbot_device_id';
  static const _prefKeyLabelSize = 'niimbot_label_size';
  static const _prefKeyDensity = 'niimbot_density';
  static const _prefKeyLabelType = 'niimbot_label_type';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  _NiimbotProtocolFamily _protocolFamily = _NiimbotProtocolFamily.b1;
  int _printheadPixels = 384;

  NiimbotPrinterStatus _status = NiimbotPrinterStatus.disconnected;
  NiimbotPrinterStatus get status => _status;

  String? _connectedDeviceId;
  String? _connectedDeviceName;
  String? get connectedDeviceId => _connectedDeviceId;
  String? get connectedDeviceName => _connectedDeviceName;

  List<NiimbotPrinterDevice> _scannedDevices = [];
  List<NiimbotPrinterDevice> get scannedDevices => _scannedDevices;

  NiimbotLabelSize _labelSize = NiimbotLabelSize.presets.first;
  NiimbotLabelSize get labelSize => _labelSize;

  NiimbotLabelType _labelType = NiimbotLabelType.gap;
  NiimbotLabelType get labelType => _labelType;

  int _density = 3;
  int get density => _density;
  String? _lastError;
  String? get lastError => _lastError;

  bool get isConnected =>
      _status == NiimbotPrinterStatus.connected ||
      _status == NiimbotPrinterStatus.printing;
  bool get isScanning => _status == NiimbotPrinterStatus.scanning;

  NiimbotPrinterService() {
    _loadPrefs();
  }

  // ── Preferences ──────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _labelSize =
        NiimbotLabelSize.fromKey(p.getString(_prefKeyLabelSize) ?? '40x30');
    _density = p.getInt(_prefKeyDensity) ?? 3;
    _labelType = NiimbotLabelType.fromCode(p.getInt(_prefKeyLabelType) ?? 0x01);
    notifyListeners();
  }

  Future<void> _saveDeviceId(String? id) async {
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      p.remove(_prefKeyDeviceId);
    } else {
      p.setString(_prefKeyDeviceId, id);
    }
  }

  Future<void> saveLabelSize(NiimbotLabelSize s) async {
    _labelSize = s;
    (await SharedPreferences.getInstance()).setString(_prefKeyLabelSize, s.key);
    notifyListeners();
  }

  Future<void> saveDensity(int v) async {
    _density = v.clamp(1, 5);
    (await SharedPreferences.getInstance()).setInt(_prefKeyDensity, _density);
    notifyListeners();
  }

  Future<void> saveLabelType(NiimbotLabelType t) async {
    _labelType = t;
    (await SharedPreferences.getInstance()).setInt(_prefKeyLabelType, t.code);
    notifyListeners();
  }

  // ── Scan ─────────────────────────────────────────────────────

  Future<List<NiimbotPrinterDevice>> scanForPrinters({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _setStatus(NiimbotPrinterStatus.scanning);
    _scannedDevices = [];
    _lastError = null;
    notifyListeners();
    try {
      final found = <String, NiimbotPrinterDevice>{};
      final sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final id = r.device.remoteId.str;
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.device.advName;
          if (!found.containsKey(id)) {
            found[id] = NiimbotPrinterDevice(
              deviceId: id,
              name: name.isNotEmpty ? name : 'BLE ($id)',
            );
            _scannedDevices = found.values.toList();
            notifyListeners();
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout + const Duration(milliseconds: 300));
      await sub.cancel();
      _setStatus(NiimbotPrinterStatus.disconnected);
      debugPrint('🖨️ [Niimbot] Found ${_scannedDevices.length} devices');
      return _scannedDevices;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(NiimbotPrinterStatus.error);
      debugPrint('❌ [Niimbot] Scan error: $e');
      return [];
    }
  }

  // ── Connect / Disconnect ─────────────────────────────────────

  Future<bool> connectToDevice(NiimbotPrinterDevice dev) async {
    _setStatus(NiimbotPrinterStatus.connecting);
    _lastError = null;
    try {
      await _cleanup();
      _device = BluetoothDevice.fromId(dev.deviceId);
      await _device!.connect(timeout: const Duration(seconds: 15));
      // Request large MTU so bitmap rows (up to ~80 bytes each) fit comfortably
      try {
        await _device!.requestMtu(512);
      } catch (_) {}
      _connStateSub = _device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          debugPrint('🖨️ [Niimbot] Disconnected');
          _txChar = null;
          _connectedDeviceId = null;
          _connectedDeviceName = null;
          _setStatus(NiimbotPrinterStatus.disconnected);
        }
      });
      final services = await _device!.discoverServices();
      for (final svc in services) {
        debugPrint('🔵 [Niimbot] Service: ${svc.serviceUuid}');
        for (final c in svc.characteristics) {
          debugPrint('   Char: ${c.characteristicUuid} '
              'write=${c.properties.write} '
              'writeNR=${c.properties.writeWithoutResponse} '
              'notify=${c.properties.notify}');
        }
      }
      _txChar = _findTx(services);
      if (_txChar == null) {
        throw Exception(
          'Printer BLE service not found. Supported: D101, D11, B1, B21, B110',
        );
      }
      debugPrint('✅ [Niimbot] Using TX char: ${_txChar!.characteristicUuid}');
      _protocolFamily = _detectProtocolFamily(dev.name);
      _printheadPixels = _detectPrintheadPixels(dev.name);
      debugPrint(
        '🖨️ [Niimbot] Model=${dev.name} family=${_protocolFamily.name} '
        'printhead=$_printheadPixels',
      );
      _connectedDeviceId = dev.deviceId;
      _connectedDeviceName = dev.name;
      _setStatus(NiimbotPrinterStatus.connected);
      await _saveDeviceId(dev.deviceId);
      debugPrint('✅ [Niimbot] Connected to ${dev.name}');
      return true;
    } catch (e) {
      _lastError = e.toString();
      await _cleanup();
      _setStatus(NiimbotPrinterStatus.error);
      debugPrint('❌ [Niimbot] Connect error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    await _cleanup();
    await _saveDeviceId(null);
    _setStatus(NiimbotPrinterStatus.disconnected);
  }

  Future<void> _cleanup() async {
    try {
      await _connStateSub?.cancel();
      _connStateSub = null;
      if (_device != null) {
        final s = await _device!.connectionState.first;
        if (s == BluetoothConnectionState.connected) {
          await _device!.disconnect();
        }
      }
    } catch (_) {}
    _device = null;
    _txChar = null;
    _connectedDeviceId = null;
    _connectedDeviceName = null;
  }

  BluetoothCharacteristic? _findTx(List<BluetoothService> svcs) {
    // Variant 1: 0xFF00 service
    for (final svc in svcs) {
      final sid = svc.serviceUuid.str.toLowerCase();
      if (sid == _kSvc1 || sid.contains('ff00')) {
        for (final c in svc.characteristics) {
          final cid = c.characteristicUuid.str.toLowerCase();
          if (cid == _kTx1 || cid.contains('ff02')) return c;
        }
      }
    }
    // Variant 2: e7810a71 service
    for (final svc in svcs) {
      final sid = svc.serviceUuid.str.toLowerCase();
      if (sid == _kSvc2 || sid.startsWith('e7810a71')) {
        for (final c in svc.characteristics) {
          final cid = c.characteristicUuid.str.toLowerCase();
          if (cid == _kTx2 || cid.startsWith('bef8d6c9')) return c;
        }
      }
    }
    // Fallback: first writable characteristic
    for (final svc in svcs) {
      for (final c in svc.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) return c;
      }
    }
    return null;
  }

  _NiimbotProtocolFamily _detectProtocolFamily(String deviceName) {
    final upper = deviceName.toUpperCase();
    if (upper.contains('D110_M') ||
        upper.startsWith('D101') ||
        upper.startsWith('B1') ||
        upper.startsWith('B21_C2B') ||
        upper.startsWith('M2_H') ||
        upper.startsWith('N1')) {
      return _NiimbotProtocolFamily.b1;
    }
    if (upper.startsWith('D110') ||
        upper.startsWith('D11') ||
        upper.startsWith('B21S')) {
      return _NiimbotProtocolFamily.d110;
    }
    return _NiimbotProtocolFamily.b1;
  }

  int _detectPrintheadPixels(String deviceName) {
    final upper = deviceName.toUpperCase();
    if (upper.contains('D110_M') ||
        upper.startsWith('D110') ||
        upper.startsWith('D11')) {
      return 96;
    }
    if (upper.startsWith('D101')) {
      return 192;
    }
    if (upper.startsWith('B1') || upper.startsWith('B21')) {
      return 384;
    }
    return 384;
  }

  // ── Label PDF generation ─────────────────────────────────────

  Future<pw.Document> _buildDoc(Product product) async {
    final wMm = _labelSize.widthMm;
    final hMm = _labelSize.heightMm;
    final fmt = PdfPageFormat(
      wMm * PdfPageFormat.mm,
      hMm * PdfPageFormat.mm,
      marginAll: 1.5 * PdfPageFormat.mm,
    );

    // Barcode value: GTIN > barcode > SKU
    final bv = (product.gtin != null && product.gtin!.isNotEmpty
            ? product.gtin!
            : null) ??
        (product.barcode != null && product.barcode!.isNotEmpty
            ? product.barcode!
            : null) ??
        product.sku;
    final isE13 = bv.length == 13 && RegExp(r'^\d+$').hasMatch(bv);
    final isE12 = bv.length == 12 && RegExp(r'^\d+$').hasMatch(bv);
    final isE8 = bv.length == 8 && RegExp(r'^\d+$').hasMatch(bv);

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: fmt,
      build: (pw.Context ctx) => pw.Container(
        width: double.infinity,
        height: double.infinity,
        color: PdfColors.white,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              _trunc(product.name, 50),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: wMm > 45 ? 9.0 : 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
            pw.Divider(thickness: 0.4),
            pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
            if (bv.isNotEmpty) ...[
              pw.BarcodeWidget(
                barcode: (isE13 || isE12)
                    ? pw.Barcode.ean13()
                    : isE8
                        ? pw.Barcode.ean8()
                        : pw.Barcode.code128(),
                data: (isE13 || isE12) ? bv.padLeft(13, '0') : bv,
                width: (wMm - 6) * PdfPageFormat.mm,
                height: (hMm * 0.38) * PdfPageFormat.mm,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 5.5),
              ),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
            ],
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _price(product.price),
                  style: pw.TextStyle(
                    fontSize: wMm > 45 ? 10.0 : 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'SKU: ${product.sku}',
                  style: const pw.TextStyle(fontSize: 5.5),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
    return doc;
  }

  Future<pw.Document> _buildTestDoc() async {
    final wMm = _labelSize.widthMm;
    final hMm = _labelSize.heightMm;
    final fmt = PdfPageFormat(
      wMm * PdfPageFormat.mm,
      hMm * PdfPageFormat.mm,
      marginAll: 1.5 * PdfPageFormat.mm,
    );
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: fmt,
      build: (pw.Context ctx) => pw.Container(
        width: double.infinity,
        height: double.infinity,
        color: PdfColors.white,
        child: pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'PRUEBA DE IMPRESIÓN',
                style: pw.TextStyle(
                  fontSize: wMm > 45 ? 10.0 : 8.0,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
              pw.Divider(),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
              pw.Text('Viñabike ERP', style: const pw.TextStyle(fontSize: 7)),
              pw.Text('Impresora NIIMBOT',
                  style: const pw.TextStyle(fontSize: 6)),
            ],
          ),
        ),
      ),
    ));
    return doc;
  }

  // ── Public API ────────────────────────────────────────────────

  /// Returns a PNG thumbnail of the label for preview, or null on error.
  Future<Uint8List?> previewProductLabel(Product p) async {
    try {
      final doc = await _buildDoc(p);
      final bytes = await doc.save();
      final raster =
          await Printing.raster(bytes, pages: const [0], dpi: 203.0).first;
      return await raster.toPng();
    } catch (e) {
      debugPrint('❌ [Niimbot] Preview: $e');
      return null;
    }
  }

  Future<bool> printProductLabel(Product p, {int quantity = 1}) async {
    if (!isConnected || _txChar == null) {
      _lastError = 'No hay impresora conectada';
      notifyListeners();
      return false;
    }
    _setStatus(NiimbotPrinterStatus.printing);
    _lastError = null;
    try {
      final doc = await _buildDoc(p);
      final bytes = await doc.save();
      return await _doPrint(bytes, quantity);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(NiimbotPrinterStatus.connected);
      return false;
    }
  }

  Future<bool> printTestLabel() async {
    if (!isConnected || _txChar == null) {
      _lastError = 'No hay impresora conectada';
      notifyListeners();
      return false;
    }
    _setStatus(NiimbotPrinterStatus.printing);
    _lastError = null;
    try {
      final doc = await _buildTestDoc();
      final bytes = await doc.save();
      return await _doPrint(bytes, 1);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(NiimbotPrinterStatus.connected);
      return false;
    }
  }

  // ── NIIMBOT binary protocol ───────────────────────────────────
  // niimbluelib uses different print tasks by printer family:
  //   B1 family (B1/D101/D110_M): density → label type → printStart7b
  //     → pageStart → setPageSize6b → bitmap rows → pageEnd → printEnd
  //   D110 family (D110/D11): density → label type → printStart1b
  //     → printClear → pageStart → setPageSize4b → setQuantity
  //     → bitmap rows → pageEnd → printEnd

  Future<bool> _doPrint(Uint8List pdfBytes, int quantity) async {
    try {
      final raster =
          await Printing.raster(pdfBytes, pages: const [0], dpi: 203.0).first;
      final w = raster.width;
      final h = raster.height;
      final rgba = raster.pixels; // RGBA, 4 bytes per pixel
      final rows = _encodeRows(rgba, w, h);

      final qty = quantity.clamp(1, 255);

      debugPrint(
        '🖨️ [Niimbot] family=${_protocolFamily.name} '
        'labelType=${_labelType.name}(${_labelType.code}) '
        'size=${w}x${h}px density=$_density rows=${rows.length}',
      );

      await _pkt(_Cmd.connect, [0x01],
          forceWithResponse: true, ignoreErrors: true);
      await Future.delayed(const Duration(milliseconds: 80));

      if (_protocolFamily == _NiimbotProtocolFamily.d110) {
        await _printWithD110Protocol(rows, w, h, qty);
      } else {
        await _printWithB1Protocol(rows, w, h, qty);
      }

      _setStatus(NiimbotPrinterStatus.connected);
      debugPrint('✅ [Niimbot] Printed $qty × ${w}x${h}px');
      return true;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(NiimbotPrinterStatus.connected);
      debugPrint('❌ [Niimbot] _doPrint: $e');
      return false;
    }
  }

  Future<void> _printWithB1Protocol(
    List<Uint8List> rows,
    int width,
    int height,
    int quantity,
  ) async {
    await _pkt(_Cmd.setLabelDensity, [_density.clamp(1, 5)]);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.setLabelType, [_labelType.code]);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.startPrint, [0x00, quantity, 0x00, 0x00, 0x00, 0x00, 0x00]);
    await Future.delayed(const Duration(milliseconds: 60));
    await _pkt(_Cmd.pageStart, []);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.setPageSize, [
      (height >> 8) & 0xFF,
      height & 0xFF,
      (width >> 8) & 0xFF,
      width & 0xFF,
      0x00,
      quantity,
    ]);
    await Future.delayed(const Duration(milliseconds: 60));

    for (final row in rows) {
      await _pkt(_Cmd.writeBitmapRow, row);
    }

    await Future.delayed(const Duration(milliseconds: 60));
    await _pkt(_Cmd.pageEnd, []);
    await Future.delayed(const Duration(milliseconds: 180));
    await _pkt(_Cmd.endPrint, [], ignoreErrors: true);
  }

  Future<void> _printWithD110Protocol(
    List<Uint8List> rows,
    int width,
    int height,
    int quantity,
  ) async {
    await _pkt(_Cmd.setLabelDensity, [_density.clamp(1, 5)]);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.setLabelType, [_labelType.code]);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.startPrint, [0x01]);
    await Future.delayed(const Duration(milliseconds: 60));
    await _pkt(_Cmd.printClear, [0x01], ignoreErrors: true);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.pageStart, []);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.setPageSize, [
      (height >> 8) & 0xFF,
      height & 0xFF,
      (width >> 8) & 0xFF,
      width & 0xFF,
    ]);
    await Future.delayed(const Duration(milliseconds: 40));
    await _pkt(_Cmd.setQuantity, [0x00, quantity]);
    await Future.delayed(const Duration(milliseconds: 60));

    for (final row in rows) {
      await _pkt(_Cmd.writeBitmapRow, row);
    }

    await Future.delayed(const Duration(milliseconds: 60));
    await _pkt(_Cmd.pageEnd, []);
    await Future.delayed(const Duration(milliseconds: 180));
    await _pkt(_Cmd.endPrint, [], ignoreErrors: true);
  }

  List<Uint8List> _encodeRows(Uint8List rgba, int width, int height) {
    final rowLen = (width + 7) ~/ 8;
    final out = <Uint8List>[];

    for (int y = 0; y < height; y++) {
      final row = Uint8List(rowLen);
      for (int x = 0; x < width; x++) {
        final base = (y * width + x) * 4;
        final alpha = rgba[base + 3] / 255.0;
        final red = (rgba[base] * alpha) + (255 * (1 - alpha));
        final green = (rgba[base + 1] * alpha) + (255 * (1 - alpha));
        final blue = (rgba[base + 2] * alpha) + (255 * (1 - alpha));
        final grey = (0.299 * red + 0.587 * green + 0.114 * blue).round();
        if (grey < 128) {
          row[x ~/ 8] |= (0x80 >> (x % 8));
        }
      }

      final counts = _countPixelsForBitmapPacket(row, _printheadPixels);
      out.add(Uint8List.fromList([
        (y >> 8) & 0xFF,
        y & 0xFF,
        counts[0],
        counts[1],
        counts[2],
        0x01,
        ...row,
      ]));
    }

    return out;
  }

  List<int> _countPixelsForBitmapPacket(Uint8List row, int printheadPixels) {
    int total = 0;
    final parts = [0, 0, 0];
    final chunkSize = (printheadPixels / 8 / 3).floor();
    final split = row.length <= chunkSize * 3 && chunkSize > 0;

    for (int byteIndex = 0; byteIndex < row.length; byteIndex++) {
      final value = row[byteIndex];
      final chunkIndex = chunkSize == 0 ? 0 : (byteIndex / chunkSize).floor();
      for (int bit = 0; bit < 8; bit++) {
        if ((value & (1 << bit)) != 0) {
          total++;
          if (split && chunkIndex <= 2) {
            parts[chunkIndex]++;
          }
        }
      }
    }

    if (split) {
      return parts;
    }

    return [0, total & 0xFF, (total >> 8) & 0xFF];
  }

  /// Build and send one NIIMBOT packet.
  Future<void> _pkt(
    int cmd,
    List<int> data, {
    bool? forceWithResponse,
    bool ignoreErrors = false,
  }) async {
    final len = data.length;
    int cs = cmd ^ len;
    for (final b in data) {
      cs ^= b;
    }
    final pkt = [0x55, 0x55, cmd, len, ...data, cs & 0xFF, 0xAA, 0xAA];
    try {
      final withoutResponse = forceWithResponse == true
          ? false
          : (_txChar!.properties.writeWithoutResponse &&
              !_txChar!.properties.write);
      await _txChar!.write(pkt, withoutResponse: withoutResponse);
      if (kDebugMode) {
        debugPrint('➡️ [Niimbot] cmd=0x${cmd.toRadixString(16)} len=$len '
            'mode=${withoutResponse ? 'writeNR' : 'write'}');
      }
    } catch (e) {
      if (!ignoreErrors) rethrow;
      debugPrint(
          '⚠️ [Niimbot] Ignored packet error cmd=0x${cmd.toRadixString(16)}: $e');
    }
  }

  // ── Utils ─────────────────────────────────────────────────────

  void _setStatus(NiimbotPrinterStatus s) {
    _status = s;
    notifyListeners();
  }

  /// Formats a CLP price: 15990 → "\$15.990"
  String _price(double p) {
    if (p == 0) return 'Sin precio';
    final s = p.toStringAsFixed(0);
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  String _trunc(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n - 1)}…';

  @override
  void dispose() {
    _cleanup().catchError((_) {});
    super.dispose();
  }
}
