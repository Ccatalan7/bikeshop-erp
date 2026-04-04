import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/niimbot_printer_service.dart';
import '../../../shared/widgets/main_layout.dart';

// ══════════════════════════════════════════════════════════════════════════════
// NiimbotSettingsPage — Configure NIIMBOT BLE thermal label printer
// ══════════════════════════════════════════════════════════════════════════════

class NiimbotSettingsPage extends StatefulWidget {
  const NiimbotSettingsPage({super.key});

  @override
  State<NiimbotSettingsPage> createState() => _NiimbotSettingsPageState();
}

class _NiimbotSettingsPageState extends State<NiimbotSettingsPage> {
  bool _isTestPrinting = false;

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Impresora de Etiquetas',
      child: Consumer<NiimbotPrinterService>(
        builder: (context, printer, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionSection(context, printer),
                const SizedBox(height: 20),
                if (printer.isConnected) ...[
                  _buildOpenLabelPrinterSection(context),
                  const SizedBox(height: 20),
                  _buildLabelTypeSection(context, printer),
                  const SizedBox(height: 20),
                  _buildLabelSizeSection(context, printer),
                  const SizedBox(height: 20),
                  _buildDensitySection(context, printer),
                  const SizedBox(height: 20),
                  _buildTestPrintSection(context, printer),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Connection section ────────────────────────────────────────────────────

  Widget _buildOpenLabelPrinterSection(BuildContext context) {
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
            _sectionTitle(context, Icons.local_printshop_outlined,
                'Impresión de Productos'),
            const SizedBox(height: 4),
            Text(
              'Abre la pantalla para buscar productos y mandar imprimir etiquetas reales.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.push('/label-printer'),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Abrir impresora de productos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSection(
      BuildContext context, NiimbotPrinterService printer) {
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
            _sectionTitle(context, Icons.bluetooth, 'Conexión Bluetooth'),
            const SizedBox(height: 16),

            // Status indicator
            _buildStatusPill(printer),
            const SizedBox(height: 16),

            // Scan & device list
            if (printer.isConnected) ...[
              _buildConnectedDevice(printer),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.bluetooth_disabled, size: 18),
                label: const Text('Desconectar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () async {
                  await printer.disconnect();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Impresora desconectada')),
                    );
                  }
                },
              ),
            ] else ...[
              FilledButton.icon(
                icon: printer.isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bluetooth_searching, size: 18),
                label: Text(printer.isScanning
                    ? 'Buscando impresoras…'
                    : 'Buscar impresoras NIIMBOT'),
                onPressed:
                    printer.isScanning ? null : () => printer.scanForPrinters(),
              ),
              if (printer.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  printer.lastError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              if (printer.scannedDevices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Dispositivos encontrados:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...printer.scannedDevices.map(
                    (device) => _buildDeviceTile(context, printer, device)),
              ],
            ],

            // Hint text
            const SizedBox(height: 12),
            Text(
              'Asegúrate de que la impresora NIIMBOT esté encendida y en modo Bluetooth.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(NiimbotPrinterService printer) {
    final Color bg;
    final Color fg;
    final String text;
    final IconData icon;

    switch (printer.status) {
      case NiimbotPrinterStatus.connected:
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        text = 'Conectada';
        icon = Icons.check_circle;
        break;
      case NiimbotPrinterStatus.printing:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        text = 'Imprimiendo';
        icon = Icons.print;
        break;
      case NiimbotPrinterStatus.connecting:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
        text = 'Conectando…';
        icon = Icons.bluetooth_searching;
        break;
      case NiimbotPrinterStatus.scanning:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade700;
        text = 'Buscando…';
        icon = Icons.bluetooth_searching;
        break;
      case NiimbotPrinterStatus.error:
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        text = 'Error';
        icon = Icons.error_outline;
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade600;
        text = 'Sin conexión';
        icon = Icons.bluetooth_disabled;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildConnectedDevice(NiimbotPrinterService printer) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.print, color: Colors.green.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  printer.connectedDeviceName ?? 'Impresora NIIMBOT',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  printer.connectedDeviceId ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(
    BuildContext context,
    NiimbotPrinterService printer,
    NiimbotPrinterDevice device,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.print_outlined, color: Colors.blue),
        title: Text(device.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(device.deviceId, style: const TextStyle(fontSize: 11)),
        trailing: FilledButton(
          onPressed: printer.status == NiimbotPrinterStatus.connecting
              ? null
              : () async {
                  final success = await printer.connectToDevice(device);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? '✅ Conectado a ${device.name}'
                            : '❌ Error: ${printer.lastError}'),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: const Text('Conectar', style: TextStyle(fontSize: 12)),
        ),
        dense: true,
      ),
    );
  }

  // ── Label size section ────────────────────────────────────────────────────

  Widget _buildLabelTypeSection(
      BuildContext context, NiimbotPrinterService printer) {
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
            _sectionTitle(context, Icons.settings_input_component_outlined,
                'Tipo de Etiqueta'),
            const SizedBox(height: 4),
            Text(
              'D101/D11 → Con separador. B110/continua → Sin separador.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NiimbotLabelType.values.map((t) {
                final selected = printer.labelType == t;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: selected,
                  onSelected: (_) => printer.saveLabelType(t),
                  selectedColor: Colors.blue.shade100,
                  labelStyle: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.blue.shade800 : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Label size section ────────────────────────────────────────────────────

  Widget _buildLabelSizeSection(
      BuildContext context, NiimbotPrinterService printer) {
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
            _sectionTitle(context, Icons.label_outline, 'Tamaño de Etiqueta'),
            const SizedBox(height: 4),
            Text(
              'Selecciona el tamaño del rollo de etiquetas que has cargado.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NiimbotLabelSize.presets.map((size) {
                final selected = printer.labelSize.key == size.key;
                return ChoiceChip(
                  label: Text(size.label),
                  selected: selected,
                  onSelected: (_) => printer.saveLabelSize(size),
                  selectedColor: Colors.blue.shade100,
                  labelStyle: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.blue.shade800 : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Density section ───────────────────────────────────────────────────────

  Widget _buildDensitySection(
      BuildContext context, NiimbotPrinterService printer) {
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
            _sectionTitle(context, Icons.opacity, 'Densidad de Impresión'),
            const SizedBox(height: 4),
            Text(
              'Más densidad = más oscuro. Recomendado: 3.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Claro', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: printer.density.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: printer.density.toString(),
                    onChanged: (v) => printer.saveDensity(v.round()),
                  ),
                ),
                const Text('Oscuro', style: TextStyle(fontSize: 12)),
              ],
            ),
            Center(
              child: Text(
                'Densidad: ${printer.density}/5',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Test print section ────────────────────────────────────────────────────

  Widget _buildTestPrintSection(
      BuildContext context, NiimbotPrinterService printer) {
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
            _sectionTitle(context, Icons.print_outlined, 'Prueba de Impresión'),
            const SizedBox(height: 4),
            Text(
              'Imprime una etiqueta de prueba para verificar la conexión y la calidad.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _isTestPrinting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: Text(_isTestPrinting
                    ? 'Imprimiendo…'
                    : 'Imprimir etiqueta de prueba'),
                onPressed: (_isTestPrinting ||
                        printer.status == NiimbotPrinterStatus.printing)
                    ? null
                    : () async {
                        setState(() => _isTestPrinting = true);
                        final ok = await printer.printTestLabel();
                        if (mounted) {
                          setState(() => _isTestPrinting = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? '✅ Etiqueta de prueba impresa'
                                  : '❌ Error: ${printer.lastError}'),
                              backgroundColor: ok ? Colors.green : Colors.red,
                            ),
                          );
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
