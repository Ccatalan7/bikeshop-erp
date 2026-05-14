import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/f29_declaration.dart';
import '../services/f29_service.dart';

class F29DetailPage extends StatefulWidget {
  final F29Declaration f29;

  const F29DetailPage({super.key, required this.f29});

  @override
  State<F29DetailPage> createState() => _F29DetailPageState();
}

class _F29DetailPageState extends State<F29DetailPage> {
  final _currencyFormat = NumberFormat.currency(locale: 'es_CL', symbol: '\$');
  late F29Declaration _f29;

  @override
  void initState() {
    super.initState();
    _f29 = widget.f29;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('F29 - ${_f29.monthName} ${_f29.periodYear}'),
        actions: [
          if (_f29.isDraft)
            TextButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Presentar al SII'),
              onPressed: () => _submitToSII(),
            ),
          if (_f29.isSubmitted)
            TextButton.icon(
              icon: const Icon(Icons.payment),
              label: const Text('Marcar como pagado'),
              onPressed: () => _markAsPaid(),
            ),
          IconButton(
            icon: const Icon(Icons.note_add),
            tooltip: 'Notas',
            onPressed: () => _editNotes(),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Exportar PDF',
            onPressed: () => _exportPDF(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildIVASection(),
            const SizedBox(height: 24),
            _buildPPMSection(),
            const SizedBox(height: 24),
            _buildRetencionesSection(),
            const SizedBox(height: 24),
            _buildTotalsSection(),
            if (_f29.notes != null && _f29.notes!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildNotesSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (_f29.status) {
      case 'draft':
        statusColor = Colors.orange;
        statusIcon = Icons.edit;
        statusText = 'Borrador';
        break;
      case 'submitted':
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        statusText = 'Presentado al SII';
        break;
      case 'paid':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Pagado';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        statusText = _f29.status;
    }

    return Card(
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  if (_f29.filedAt != null)
                    Text(
                      'Presentado: ${DateFormat('dd/MM/yyyy HH:mm').format(_f29.filedAt!)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  if (_f29.folioNumber != null)
                    Text(
                      'Folio: ${_f29.folioNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (_f29.dueDate != null)
                    Text(
                      'Vencimiento: ${DateFormat('dd/MM/yyyy').format(_f29.dueDate!)}',
                      style: TextStyle(
                        color: _f29.dueDate!.isBefore(DateTime.now()) &&
                                !_f29.isPaid
                            ? Colors.red
                            : Colors.grey,
                        fontWeight: _f29.dueDate!.isBefore(DateTime.now()) &&
                                !_f29.isPaid
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIVASection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IVA - Impuesto al Valor Agregado',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildLineItem(
              'IVA Débito - Ventas (Línea 3)',
              _f29.ivaDebitoVentas,
              isCredit: true,
            ),
            if (_f29.ivaDebitoExportaciones > 0)
              _buildLineItem(
                'IVA Débito - Exportaciones (Línea 5)',
                _f29.ivaDebitoExportaciones,
                isCredit: true,
              ),
            if (_f29.ivaDebitoActivosFijos > 0)
              _buildLineItem(
                'IVA Débito - Activos Fijos (Línea 7)',
                _f29.ivaDebitoActivosFijos,
                isCredit: true,
              ),
            const Divider(),
            _buildLineItem(
              'Total IVA Débito (Línea 15)',
              _f29.ivaDebitoTotal,
              isTotal: true,
              isCredit: true,
            ),
            const SizedBox(height: 16),
            _buildLineItem(
              'IVA Crédito - Compras (Línea 30)',
              _f29.ivaCreditoCompras,
              isDebit: true,
            ),
            if (_f29.ivaCreditoImportaciones > 0)
              _buildLineItem(
                'IVA Crédito - Importaciones (Línea 31)',
                _f29.ivaCreditoImportaciones,
                isDebit: true,
              ),
            if (_f29.ivaCreditoActivosFijos > 0)
              _buildLineItem(
                'IVA Crédito - Activos Fijos (Línea 32)',
                _f29.ivaCreditoActivosFijos,
                isDebit: true,
              ),
            if (_f29.ivaRemanenteMesAnterior > 0)
              _buildLineItem(
                'Remanente Mes Anterior (Línea 35)',
                _f29.ivaRemanenteMesAnterior,
                isDebit: true,
              ),
            const Divider(),
            _buildLineItem(
              'Total IVA Crédito (Línea 40)',
              _f29.ivaCreditoTotal,
              isTotal: true,
              isDebit: true,
            ),
            const Divider(),
            _buildLineItem(
              'IVA Neto (Línea 43)',
              _f29.ivaNeto.abs(),
              isTotal: true,
              isHighlight: true,
              isCredit: _f29.ivaNeto > 0,
              isDebit: _f29.ivaNeto < 0,
            ),
            if (_f29.ivaNeto < 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Crédito a favor para el próximo período',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPPMSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PPM - Pago Provisional Mensual',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildLineItem(
              'Ventas Netas del Período (Línea 50)',
              _f29.ppmVentasNetas,
            ),
            _buildLineItem(
              'Tasa PPM (Línea 52)',
              _f29.ppmTasaPorcentaje,
              isPercentage: true,
            ),
            const Divider(),
            _buildLineItem(
              'Monto PPM a Pagar (Línea 54)',
              _f29.ppmMonto,
              isTotal: true,
              isCredit: true,
            ),
            if (_f29.ppmRemanente > 0) ...[
              const SizedBox(height: 8),
              _buildLineItem(
                'Remanente PPM (Línea 56)',
                _f29.ppmRemanente,
                isDebit: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRetencionesSection() {
    if (_f29.retencionSegundaCategoria == 0 &&
        _f29.retencionHonorarios == 0 &&
        _f29.retencionArrendamiento == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Retenciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_f29.retencionSegundaCategoria > 0)
              _buildLineItem(
                'Retención 2da Categoría - Trabajadores (Línea 72)',
                _f29.retencionSegundaCategoria,
                isCredit: true,
              ),
            if (_f29.retencionHonorarios > 0)
              _buildLineItem(
                'Retención Honorarios - 10% (Línea 74)',
                _f29.retencionHonorarios,
                isCredit: true,
              ),
            if (_f29.retencionArrendamiento > 0)
              _buildLineItem(
                'Retención Arrendamiento (Línea 76)',
                _f29.retencionArrendamiento,
                isCredit: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection() {
    return Card(
      color: _f29.hasDebt ? Colors.red[50] : Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen Final',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_f29.hasDebt)
              _buildLineItem(
                'Total a Pagar al SII',
                _f29.totalAPagar,
                isTotal: true,
                isHighlight: true,
                isCredit: true,
                color: Colors.red,
              ),
            if (_f29.hasCredit)
              _buildLineItem(
                'Total a Favor del Contribuyente',
                _f29.totalAFavor,
                isTotal: true,
                isHighlight: true,
                isDebit: true,
                color: Colors.green,
              ),
            if (!_f29.hasDebt && !_f29.hasCredit)
              const Center(
                child: Text(
                  'Sin saldo a pagar ni a favor',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _f29.notes!,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItem(
    String label,
    double value, {
    bool isTotal = false,
    bool isHighlight = false,
    bool isPercentage = false,
    bool isCredit = false,
    bool isDebit = false,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isTotal ? 8 : 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
          Row(
            children: [
              if (isCredit)
                Icon(Icons.arrow_upward,
                    size: 16, color: Colors.red.withValues(alpha: 0.7)),
              if (isDebit)
                Icon(Icons.arrow_downward,
                    size: 16, color: Colors.green.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                isPercentage
                    ? '${value.toStringAsFixed(2)}%'
                    : _currencyFormat.format(value),
                style: TextStyle(
                  fontSize: isTotal ? 18 : 14,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submitToSII() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Presentar al SII'),
        content: Text(
          '¿Confirmas que deseas marcar esta declaración como presentada al SII?\n\n'
          'Período: ${_f29.monthName} ${_f29.periodYear}\n'
          'Total a pagar: ${_currencyFormat.format(_f29.totalAPagar)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Presentar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Ask for folio number
    final folioController = TextEditingController();
    final folio = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Número de Folio'),
        content: TextField(
          controller: folioController,
          decoration: const InputDecoration(
            labelText: 'Folio del SII',
            hintText: 'Ej: 1234567890',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Omitir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, folioController.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final service = context.read<F29Service>();
    final success = await service.updateStatus(
      _f29.id,
      'submitted',
      folioNumber: folio,
    );

    if (!mounted) return;

    if (success) {
      // Reload F29
      final updated = await service.getDeclarationForPeriod(
          _f29.periodYear, _f29.periodMonth);
      if (updated != null) {
        setState(() => _f29 = updated);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('F29 marcado como presentado'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar estado'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _markAsPaid() async {
    final paymentRefController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como Pagado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Monto pagado: ${_currencyFormat.format(_f29.totalAPagar)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: paymentRefController,
              decoration: const InputDecoration(
                labelText: 'Referencia de pago (opcional)',
                hintText: 'Ej: Comprobante #123',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar Pago'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = context.read<F29Service>();
    final success = await service.updateStatus(
      _f29.id,
      'paid',
      paymentReference: paymentRefController.text.isNotEmpty
          ? paymentRefController.text
          : null,
    );

    if (!mounted) return;

    if (success) {
      // Reload F29
      final updated = await service.getDeclarationForPeriod(
          _f29.periodYear, _f29.periodMonth);
      if (updated != null) {
        setState(() => _f29 = updated);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('F29 marcado como pagado'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar estado'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editNotes() async {
    final notesController = TextEditingController(text: _f29.notes);

    final newNotes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notas de la Declaración'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: notesController,
            decoration: const InputDecoration(
              labelText: 'Notas',
              hintText: 'Agrega observaciones o comentarios...',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, notesController.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newNotes == null) return;

    final service = context.read<F29Service>();
    final success = await service.updateNotes(_f29.id, newNotes);

    if (!mounted) return;

    if (success) {
      // Reload F29
      final updated = await service.getDeclarationForPeriod(
          _f29.periodYear, _f29.periodMonth);
      if (updated != null) {
        setState(() => _f29 = updated);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notas actualizadas')),
      );
    }
  }

  Future<void> _exportPDF() async {
    // TODO: Implement PDF export using pdf package
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exportación PDF próximamente'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
