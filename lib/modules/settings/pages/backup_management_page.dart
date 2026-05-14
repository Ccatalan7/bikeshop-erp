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
        _buildInfoRow(theme, 'Mantener últimos',
            '${schedule.keepLastNBackups} respaldos'),
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
    final chatCount = backups.fold<int>(
        0, (sum, b) => sum + b.getSummaryCount('conversations'));

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
            Expanded(
              child: _buildStatItem(
                theme,
                Icons.forum_outlined,
                const Color(0xFF0F766E),
                '$chatCount',
                'Chats',
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
        backgroundColor: statusColor.withValues(alpha: 0.1),
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
              Icon(Icons.storage,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                backup.sizeMB,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.inventory,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${backup.getSummaryCount('products')} productos',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.forum_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${backup.getSummaryCount('conversations')} chats',
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
    _backupNameController.text =
        'Respaldo ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}';
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
          content:
              Text('Respaldo creado: ${result.sizeMB?.toStringAsFixed(2)} MB'),
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
              _buildDetailRow(
                  theme, 'Productos', '${backup.getSummaryCount('products')}'),
              _buildDetailRow(theme, 'Categorías Productos',
                  '${backup.getSummaryCount('product_categories')}'),
              _buildDetailRow(
                  theme, 'Clientes', '${backup.getSummaryCount('customers')}'),
              _buildDetailRow(theme, 'Proveedores',
                  '${backup.getSummaryCount('suppliers')}'),
              _buildDetailRow(theme, 'Facturas Venta',
                  '${backup.getSummaryCount('sales_invoices')}'),
              _buildDetailRow(theme, 'Facturas Compra',
                  '${backup.getSummaryCount('purchase_invoices')}'),
              _buildDetailRow(theme, 'Trabajadores',
                  '${backup.getSummaryCount('employees')}'),
              _buildDetailRow(theme, 'Asientos Contables',
                  '${backup.getSummaryCount('journal_entries')}'),
              _buildDetailRow(theme, 'Trabajos (Trabajos)',
                  '${backup.getSummaryCount('mechanic_jobs')}'),
              _buildDetailRow(
                  theme, 'Bicicletas', '${backup.getSummaryCount('bikes')}'),
              _buildDetailRow(theme, 'Marcas Productos',
                  '${backup.getSummaryCount('product_brands')}'),
              _buildDetailRow(theme, 'Marcas Bicicletas',
                  '${backup.getSummaryCount('bike_brands')}'),
              _buildDetailRow(theme, 'Modelos Bicicletas',
                  '${backup.getSummaryCount('bike_models')}'),
              const Divider(),
              Text('Mensajería',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              _buildDetailRow(theme, 'Conversaciones',
                  '${backup.getSummaryCount('conversations')}'),
              _buildDetailRow(
                  theme, 'Mensajes', '${backup.getSummaryCount('messages')}'),
              _buildDetailRow(theme, 'Archivos de Chat',
                  '${backup.getSummaryCount('chat_attachments')}'),
              _buildDetailRow(theme, 'Canales WhatsApp',
                  '${backup.getSummaryCount('whatsapp_channels')}'),
              _buildDetailRow(theme, 'Vínculos WhatsApp',
                  '${backup.getSummaryCount('whatsapp_conversation_bindings')}'),
              const Divider(),
              Text('Tienda Online',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              _buildDetailRow(theme, 'Pedidos Online',
                  '${backup.getSummaryCount('online_orders')}'),
              _buildDetailRow(theme, 'Banners Web',
                  '${backup.getSummaryCount('website_banners')}'),
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
            Text(
                'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(backup.createdAt)}'),
            const SizedBox(height: 8),
            const Text('El sistema volverá a este estado:'),
            Text('• ${backup.getSummaryCount('products')} productos'),
            Text(
                '• ${backup.getSummaryCount('product_categories')} categorías de productos'),
            Text('• ${backup.getSummaryCount('customers')} clientes'),
            Text(
                '• ${backup.getSummaryCount('sales_invoices')} facturas de venta'),
            Text(
                '• ${backup.getSummaryCount('purchase_invoices')} facturas de compra'),
            Text(
                '• ${backup.getSummaryCount('mechanic_jobs')} trabajos mecánicos'),
            Text('• ${backup.getSummaryCount('bikes')} bicicletas registradas'),
            Text(
                '• ${backup.getSummaryCount('product_brands')} marcas de productos'),
            Text(
                '• ${backup.getSummaryCount('bike_brands')} marcas de bicicletas'),
            Text(
                '• ${backup.getSummaryCount('bike_models')} modelos de bicicletas'),
            Text('• ${backup.getSummaryCount('conversations')} conversaciones'),
            Text('• ${backup.getSummaryCount('messages')} mensajes'),
            Text('• ${backup.getSummaryCount('online_orders')} pedidos online'),
            Text(
                '• ${backup.getSummaryCount('website_banners')} banners de la tienda web'),
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
      final fileName =
          'backup_${backup.backupName.replaceAll(' ', '_').replaceAll(':', '-')}_${DateFormat('yyyyMMdd_HHmmss').format(backup.createdAt)}.json';

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

    try {
      await _backupService.updateSchedule(schedule.copyWith(enabled: enabled));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled
              ? 'Respaldos automáticos activados'
              : 'Respaldos automáticos desactivados'),
          backgroundColor: enabled ? Colors.green : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar la agenda: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showScheduleSettingsDialog() {
    final current = _backupService.schedule;
    if (current == null) return;

    var enabled = current.enabled;
    var frequency = current.frequency;
    var selectedTime = _parseBackupTime(current.timeOfDay) ??
        const TimeOfDay(hour: 2, minute: 0);
    var dayOfWeek = current.dayOfWeek ?? 0;
    var dayOfMonth = current.dayOfMonth ?? 1;
    var keepLastNBackups = current.keepLastNBackups;
    var autoDeleteOld = current.autoDeleteOld;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> pickTime() async {
            final picked = await showTimePicker(
              context: dialogContext,
              initialTime: selectedTime,
            );
            if (picked != null) {
              setDialogState(() => selectedTime = picked);
            }
          }

          return AlertDialog(
            title: const Text('Respaldos automáticos'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activar agenda del servidor'),
                      subtitle: const Text(
                        'Crea respaldos completos aunque el ERP esté cerrado.',
                      ),
                      value: enabled,
                      onChanged: (value) {
                        setDialogState(() => enabled = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      decoration: const InputDecoration(
                        labelText: 'Frecuencia',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'hourly',
                          child: Text('Cada hora'),
                        ),
                        DropdownMenuItem(
                          value: 'daily',
                          child: Text('Diario'),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Semanal'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Mensual'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => frequency = value);
                      },
                    ),
                    if (frequency != 'hourly') ...[
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Hora'),
                        subtitle: Text(selectedTime.format(dialogContext)),
                        trailing: OutlinedButton(
                          onPressed: pickTime,
                          child: const Text('Cambiar'),
                        ),
                      ),
                    ],
                    if (frequency == 'weekly') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: dayOfWeek,
                        decoration: const InputDecoration(
                          labelText: 'Día de la semana',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Domingo')),
                          DropdownMenuItem(value: 1, child: Text('Lunes')),
                          DropdownMenuItem(value: 2, child: Text('Martes')),
                          DropdownMenuItem(value: 3, child: Text('Miércoles')),
                          DropdownMenuItem(value: 4, child: Text('Jueves')),
                          DropdownMenuItem(value: 5, child: Text('Viernes')),
                          DropdownMenuItem(value: 6, child: Text('Sábado')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => dayOfWeek = value);
                        },
                      ),
                    ],
                    if (frequency == 'monthly') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: dayOfMonth.clamp(1, 28).toInt(),
                        decoration: const InputDecoration(
                          labelText: 'Día del mes',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var day = 1; day <= 28; day++)
                            DropdownMenuItem(
                              value: day,
                              child: Text('$day'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => dayOfMonth = value);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: keepLastNBackups,
                      decoration: const InputDecoration(
                        labelText: 'Mantener respaldos automáticos',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('Últimos 3')),
                        DropdownMenuItem(value: 7, child: Text('Últimos 7')),
                        DropdownMenuItem(value: 14, child: Text('Últimos 14')),
                        DropdownMenuItem(value: 30, child: Text('Últimos 30')),
                        DropdownMenuItem(value: 60, child: Text('Últimos 60')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => keepLastNBackups = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          const Text('Limpiar respaldos automáticos antiguos'),
                      subtitle: const Text(
                        'Nunca elimina los respaldos manuales que crees tú.',
                      ),
                      value: autoDeleteOld,
                      onChanged: (value) {
                        setDialogState(() => autoDeleteOld = value ?? true);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Incluye conversaciones, mensajes, estados de WhatsApp y referencias a archivos multimedia del chat.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final updated = BackupSchedule(
                    id: current.id,
                    tenantId: current.tenantId,
                    enabled: enabled,
                    frequency: frequency,
                    timeOfDay: frequency == 'hourly'
                        ? null
                        : _formatBackupTime(selectedTime),
                    dayOfWeek: frequency == 'weekly' ? dayOfWeek : null,
                    dayOfMonth: frequency == 'monthly' ? dayOfMonth : null,
                    keepLastNBackups: keepLastNBackups,
                    autoDeleteOld: autoDeleteOld,
                    lastRunAt: current.lastRunAt,
                  );

                  try {
                    await _backupService.updateSchedule(updated);
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Agenda de respaldos actualizada'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  TimeOfDay? _parseBackupTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatBackupTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }
}
