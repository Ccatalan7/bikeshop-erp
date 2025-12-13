import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/backup_service.dart';
import '../../../shared/models/backup.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/file_download.dart';

class BackupManagementPage extends StatefulWidget {
  const BackupManagementPage({super.key});

  @override
  State<BackupManagementPage> createState() => _BackupManagementPageState();
}

class _BackupManagementPageState extends State<BackupManagementPage> {
  late BackupService _backupService;
  final TextEditingController _backupNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _backupService = Provider.of<BackupService>(context, listen: false);
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _backupService.loadBackups(),
      _backupService.loadSchedule(),
    ]);
  }

  @override
  void dispose() {
    _backupNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainLayout(
      title: 'Respaldo y Restauración',
      body: Consumer<BackupService>(
        builder: (context, service, _) {
          if (service.isLoading && service.backups.isEmpty) {
            return const Center(child: BrandedLoading());
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Header with create backup button
                _buildHeader(theme),
                const SizedBox(height: 24),

                // Backup schedule card
                _buildScheduleCard(theme, service),
                const SizedBox(height: 24),

                // Statistics card
                _buildStatisticsCard(theme, service),
                const SizedBox(height: 24),

                // Backups list
                _buildBackupsList(theme, service),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gestión de Respaldos',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Crea copias de seguridad y restaura datos',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: _showCreateBackupDialog,
          icon: const Icon(Icons.backup),
          label: const Text('Crear Respaldo'),
        ),
      ],
    );
  }

  Widget _buildScheduleCard(ThemeData theme, BackupService service) {
    final schedule = service.schedule;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Respaldos Automáticos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: schedule?.enabled ?? false,
                  onChanged: (value) => _toggleSchedule(value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (schedule != null && schedule.enabled) ...[
              _buildScheduleInfo(theme, schedule),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _showScheduleSettingsDialog,
                icon: const Icon(Icons.settings),
                label: const Text('Configurar'),
              ),
            ] else ...[
              Text(
                'Los respaldos automáticos están desactivados',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _showScheduleSettingsDialog,
                icon: const Icon(Icons.add),
                label: const Text('Configurar Respaldos Automáticos'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleInfo(ThemeData theme, BackupSchedule schedule) {
    String frequencyText = '';
    switch (schedule.frequency) {
      case 'hourly':
        frequencyText = 'Cada hora';
        break;
      case 'daily':
        frequencyText = 'Diario';
        break;
      case 'weekly':
        frequencyText = 'Semanal';
        break;
      case 'monthly':
        frequencyText = 'Mensual';
        break;
    }

    return Column(
      children: [
        _buildInfoRow(theme, 'Frecuencia', frequencyText),
        _buildInfoRow(theme, 'Mantener últimos', '${schedule.keepLastNBackups} respaldos'),
        if (schedule.lastRunAt != null)
          _buildInfoRow(
            theme,
            'Último respaldo',
            DateFormat('dd/MM/yyyy HH:mm').format(schedule.lastRunAt!),
          ),
        if (schedule.nextRunAt != null)
          _buildInfoRow(
            theme,
            'Próximo respaldo',
            DateFormat('dd/MM/yyyy HH:mm').format(schedule.nextRunAt!),
          ),
      ],
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(ThemeData theme, BackupService service) {
    final backups = service.backups;
    final completedCount = backups.where((b) => b.status == 'completed').length;
    final failedCount = backups.where((b) => b.status == 'failed').length;
    final totalSize = backups.fold<int>(
      0,
      (sum, b) => sum + (b.backupSizeBytes ?? 0),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                theme,
                Icons.check_circle,
                Colors.green,
                '$completedCount',
                'Completados',
              ),
            ),
            Expanded(
              child: _buildStatItem(
                theme,
                Icons.error,
                Colors.red,
                '$failedCount',
                'Fallidos',
              ),
            ),
            Expanded(
              child: _buildStatItem(
                theme,
                Icons.storage,
                Colors.blue,
                '${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB',
                'Espacio Total',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildBackupsList(ThemeData theme, BackupService service) {
    final backups = service.backups;

    if (backups.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.backup_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No hay respaldos',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Crea tu primer respaldo para proteger tus datos',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Historial de Respaldos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: backups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final backup = backups[index];
              return _buildBackupTile(theme, backup);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackupTile(ThemeData theme, DatabaseBackup backup) {
    Color statusColor;
    IconData statusIcon;
    
    switch (backup.status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'restored':
        statusColor = Colors.blue;
        statusIcon = Icons.restore;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.1),
        child: Icon(statusIcon, color: statusColor),
      ),
      title: Text(
        backup.backupName,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            DateFormat('dd/MM/yyyy HH:mm').format(backup.createdAt),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.storage, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                backup.sizeMB,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.inventory, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${backup.getSummaryCount('products')} productos',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton(
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'view',
            child: Row(
              children: [
                Icon(Icons.info_outline),
                SizedBox(width: 12),
                Text('Ver Detalles'),
              ],
            ),
          ),
          if (backup.status == 'completed')
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('Descargar JSON', style: TextStyle(color: Colors.blue)),
                ],
              ),
            ),
          if (backup.status == 'completed')
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore),
                  SizedBox(width: 12),
                  Text('Restaurar'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 12),
                Text('Eliminar', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          switch (value) {
            case 'view':
              _showBackupDetails(backup);
              break;
            case 'download':
              _downloadBackup(backup);
              break;
            case 'restore':
              _confirmRestore(backup);
              break;
            case 'delete':
              _confirmDelete(backup);
              break;
          }
        },
      ),
    );
  }

  // Dialogs and actions
  void _showCreateBackupDialog() {
    _backupNameController.text = 'Respaldo ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}';
    _notesController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nuevo Respaldo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _backupNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del respaldo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _createBackup();
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Creando respaldo...')),
    );

    final result = await _backupService.createBackup(
      backupName: _backupNameController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    if (result.success) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Respaldo creado: ${result.sizeMB?.toStringAsFixed(2)} MB'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showBackupDetails(DatabaseBackup backup) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(backup.backupName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(theme, 'Estado', backup.status.toUpperCase()),
              _buildDetailRow(theme, 'Tipo', backup.backupType),
              _buildDetailRow(theme, 'Tamaño', backup.sizeMB),
              _buildDetailRow(
                theme,
                'Creado',
                DateFormat('dd/MM/yyyy HH:mm').format(backup.createdAt),
              ),
              if (backup.restoredAt != null)
                _buildDetailRow(
                  theme,
                  'Restaurado',
                  DateFormat('dd/MM/yyyy HH:mm').format(backup.restoredAt!),
                ),
              if (backup.notes != null && backup.notes!.isNotEmpty)
                _buildDetailRow(theme, 'Notas', backup.notes!),
              const Divider(),
              Text(
                'Resumen de Datos:',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(theme, 'Productos', '${backup.getSummaryCount('products')}'),
                  _buildDetailRow(theme, 'Categorías Productos', '${backup.getSummaryCount('product_categories')}'),
                  _buildDetailRow(theme, 'Clientes', '${backup.getSummaryCount('customers')}'),
                  _buildDetailRow(theme, 'Proveedores', '${backup.getSummaryCount('suppliers')}'),
                  _buildDetailRow(theme, 'Facturas Venta', '${backup.getSummaryCount('sales_invoices')}'),
                  _buildDetailRow(theme, 'Facturas Compra', '${backup.getSummaryCount('purchase_invoices')}'),
                  _buildDetailRow(theme, 'Empleados', '${backup.getSummaryCount('employees')}'),
                  _buildDetailRow(theme, 'Asientos Contables', '${backup.getSummaryCount('journal_entries')}'),
                  _buildDetailRow(theme, 'Pegas (Trabajos)', '${backup.getSummaryCount('mechanic_jobs')}'),
                  _buildDetailRow(theme, 'Bicicletas', '${backup.getSummaryCount('bikes')}'),
                  _buildDetailRow(theme, 'Marcas Productos', '${backup.getSummaryCount('product_brands')}'),
                  _buildDetailRow(theme, 'Marcas Bicicletas', '${backup.getSummaryCount('bike_brands')}'),
                  _buildDetailRow(theme, 'Modelos Bicicletas', '${backup.getSummaryCount('bike_models')}'),
                  const Divider(),
                  Text('Tienda Online', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  _buildDetailRow(theme, 'Pedidos Online', '${backup.getSummaryCount('online_orders')}'),
                  _buildDetailRow(theme, 'Banners Web', '${backup.getSummaryCount('website_banners')}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRestore(DatabaseBackup backup) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 12),
            Text('Confirmar Restauración'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ ADVERTENCIA: Esta acción eliminará TODOS los datos actuales y los reemplazará con el respaldo.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text('Respaldo: ${backup.backupName}'),
            Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(backup.createdAt)}'),
            const SizedBox(height: 8),
            const Text('El sistema volverá a este estado:'),
            Text('• ${backup.getSummaryCount('products')} productos'),
            Text('• ${backup.getSummaryCount('product_categories')} categorías de productos'),
            Text('• ${backup.getSummaryCount('customers')} clientes'),
            Text('• ${backup.getSummaryCount('sales_invoices')} facturas de venta'),
            Text('• ${backup.getSummaryCount('purchase_invoices')} facturas de compra'),
            Text('• ${backup.getSummaryCount('mechanic_jobs')} pegas (trabajos mecánicos)'),
            Text('• ${backup.getSummaryCount('bikes')} bicicletas registradas'),
            Text('• ${backup.getSummaryCount('product_brands')} marcas de productos'),
            Text('• ${backup.getSummaryCount('bike_brands')} marcas de bicicletas'),
            Text('• ${backup.getSummaryCount('bike_models')} modelos de bicicletas'),
            Text('• ${backup.getSummaryCount('online_orders')} pedidos online'),
            Text('• ${backup.getSummaryCount('website_banners')} banners de la tienda web'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _restoreBackup(backup);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup(DatabaseBackup backup) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Restaurando respaldo...')),
    );

    final result = await _backupService.restoreBackup(backup.id);

    if (result.success) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Respaldo restaurado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmDelete(DatabaseBackup backup) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Eliminar el respaldo "${backup.backupName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteBackup(backup);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadBackup(DatabaseBackup backup) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Preparando descarga...')),
    );

    try {
      // Get backup data from service
      final backupData = await _backupService.getBackupData(backup.id);
      
      if (backupData == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Error: No se pudo obtener los datos del respaldo'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Convert to JSON string
      final jsonString = _backupService.backupToJsonString(backupData);
      
      if (jsonString == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Error: No se pudo convertir el respaldo a JSON'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Create download file name
      final fileName = 'backup_${backup.backupName.replaceAll(' ', '_').replaceAll(':', '-')}_${DateFormat('yyyyMMdd_HHmmss').format(backup.createdAt)}.json';

      // Trigger download using cross-platform utility
      final bytes = utf8.encode(jsonString);
      await downloadFile(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'application/json',
      );

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Respaldo descargado: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error al descargar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteBackup(DatabaseBackup backup) async {
    try {
      await _backupService.deleteBackup(backup.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Respaldo eliminado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleSchedule(bool enabled) async {
    final schedule = _backupService.schedule;
    if (schedule == null) return;

    await _backupService.updateSchedule(
      schedule.copyWith(enabled: enabled),
    );
  }

  void _showScheduleSettingsDialog() {
    // TODO: Implement schedule configuration dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración de respaldos automáticos próximamente')),
    );
  }
}
