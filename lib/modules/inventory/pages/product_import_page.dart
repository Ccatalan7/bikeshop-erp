import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/product_import_service.dart';

class ProductImportPage extends StatefulWidget {
  const ProductImportPage({super.key});

  @override
  State<ProductImportPage> createState() => _ProductImportPageState();
}

class _ProductImportPageState extends State<ProductImportPage> {
  late ProductImportService _importService;
  bool _initialized = false;
  late List<String> _recommendedColumns;

  ProductImportParseResult? _parseResult;
  Map<String, String?> _mapping = {};
  bool _isParsing = false;
  bool _isImporting = false;
  bool _isDownloadingCsvTemplate = false;
  bool _isDownloadingExcelTemplate = false;
  bool _allowUpdates = true;
  bool _createMissingSuppliers = true;
  ProductImportSummary? _summary;
  String? _errorMessage;
  PlatformFile? _selectedFile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final db = Provider.of<DatabaseService>(context, listen: false);
    _importService = ProductImportService(db);
    _recommendedColumns = _importService.recommendedColumnLabels;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainLayout(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 16),
            _buildInstructions(theme),
            const SizedBox(height: 16),
            _buildActionsRow(theme),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorBanner(theme),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 16),
              _buildSummaryCard(theme, _summary!),
            ],
            if (_parseResult != null) ...[
              const SizedBox(height: 16),
              _buildFileInfoCard(theme),
              const SizedBox(height: 16),
              _buildMappingCard(theme),
              const SizedBox(height: 16),
              _buildOptionsCard(theme),
              const SizedBox(height: 16),
              _buildPreviewCard(theme),
              const SizedBox(height: 24),
              _buildImportButton(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Importar productos',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Carga catálogos completos desde otros ERP o planillas (CSV, Excel).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_parseResult != null)
          Chip(
            avatar: const Icon(Icons.table_rows_outlined),
            label: Text('${_parseResult!.rows.length} filas listas'),
          ),
      ],
    );
  }

  Widget _buildInstructions(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Columnas sugeridas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recommendedColumns
                  .map((column) => Chip(label: Text(column)))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Puedes incluir columnas adicionales; las no mapeadas se guardarán en "Especificaciones".',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(
              'La plantilla CSV incluye una fila de ejemplo que puedes reemplazar o eliminar antes de importar.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  text: 'Descargar plantilla CSV',
                  icon: Icons.download_outlined,
                  type: ButtonType.outline,
                  isLoading: _isDownloadingCsvTemplate,
                  onPressed:
                      _isDownloadingCsvTemplate ? null : _downloadTemplateCsv,
                ),
                AppButton(
                  text: 'Descargar plantilla Excel',
                  icon: Icons.grid_on_outlined,
                  type: ButtonType.outline,
                  isLoading: _isDownloadingExcelTemplate,
                  onPressed: _isDownloadingExcelTemplate
                      ? null
                      : _downloadTemplateExcel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsRow(ThemeData theme) {
    return Row(
      children: [
        AppButton(
          text: _parseResult == null
              ? 'Seleccionar archivo'
              : 'Reemplazar archivo',
          icon: Icons.upload_file_outlined,
          isLoading: _isParsing,
          onPressed: _isParsing || _isImporting ? null : _pickFile,
        ),
        if (_parseResult != null) ...[
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _isImporting
                ? null
                : () {
                    setState(() {
                      _parseResult = null;
                      _mapping.clear();
                      _summary = null;
                      _selectedFile = null;
                    });
                  },
            icon: const Icon(Icons.clear_all),
            label: const Text('Limpiar carga'),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: theme.colorScheme.onErrorContainer),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfoCard(ThemeData theme) {
    final parseResult = _parseResult!;
    final fileName = _selectedFile?.name ?? parseResult.sourceName;
    final rowCount = parseResult.rows.length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(fileName),
        subtitle: Text(
            '${parseResult.headers.length} columnas · $rowCount filas con datos'),
        trailing: IconButton(
          icon: const Icon(Icons.visibility_outlined),
          tooltip: 'Ver primeras filas',
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Vista previa rápida'),
                content: SizedBox(
                  width: 480,
                  child: _buildPreviewTable(parseResult, limit: 10),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMappingCard(ThemeData theme) {
    final parseResult = _parseResult!;
    final missing = _missingRequiredFields;
    final sampleRow =
        parseResult.rows.isNotEmpty ? parseResult.rows.first : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Asigna cada columna a un campo del ERP',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (missing.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.warning_amber_outlined),
                    label: Text(
                      'Faltan: ${missing.map((field) => field.label).join(', ')}',
                    ),
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: parseResult.headers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final header = parseResult.headers[index];
                final selection = _mapping[header];
                final sample = sampleRow != null ? sampleRow[header] ?? '' : '';
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            header,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (sample.isNotEmpty)
                            Text(
                              sample,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String?>(
                        value: selection,
                        items: _buildDropdownItems(header),
                        onChanged: (value) => _updateMapping(header, value),
                        decoration: const InputDecoration(
                          labelText: 'Campo destino',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard(ThemeData theme) {
    return Card(
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _allowUpdates,
            onChanged: _isImporting
                ? null
                : (value) => setState(() => _allowUpdates = value),
            title: const Text('Actualizar productos existentes (según SKU)'),
            subtitle: const Text(
                'Si el SKU ya existe, se actualizarán los datos en lugar de crear un duplicado.'),
          ),
          const Divider(height: 0),
          SwitchListTile.adaptive(
            value: _createMissingSuppliers,
            onChanged: _isImporting
                ? null
                : (value) => setState(() => _createMissingSuppliers = value),
            title: const Text('Crear proveedores faltantes automáticamente'),
            subtitle: const Text(
                'Si el nombre del proveedor no existe, se dará de alta con datos mínimos.'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme) {
    final parseResult = _parseResult!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vista previa (primeras 5 filas)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildPreviewTable(parseResult, limit: 5),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable(ProductImportParseResult parseResult,
      {int limit = 5}) {
    final headers = parseResult.headers;
    final rows = parseResult.rows.take(limit).toList();
    if (rows.isEmpty) {
      return const Text('No hay filas para mostrar.');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headers
            .map((header) => DataColumn(
                  label: Text(
                    header,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ))
            .toList(),
        rows: rows
            .map(
              (row) => DataRow(
                cells: headers
                    .map((header) => DataCell(Text(row[header] ?? '')))
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildImportButton(ThemeData theme) {
    final missing = _missingRequiredFields;
    return Align(
      alignment: Alignment.centerRight,
      child: AppButton(
        text: 'Importar ${_parseResult!.rows.length} productos',
        icon: Icons.playlist_add_check_outlined,
        isLoading: _isImporting,
        onPressed: _isImporting || missing.isNotEmpty ? null : _runImport,
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, ProductImportSummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Importación completada',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSummaryChip(
                  theme,
                  icon: Icons.add_circle_outline,
                  label: 'Nuevos',
                  value: summary.inserted,
                  color: theme.colorScheme.primary,
                ),
                _buildSummaryChip(
                  theme,
                  icon: Icons.update,
                  label: 'Actualizados',
                  value: summary.updated,
                  color: theme.colorScheme.tertiary,
                ),
                _buildSummaryChip(
                  theme,
                  icon: Icons.error_outline,
                  label: 'Con errores',
                  value: summary.errors.length,
                  color: theme.colorScheme.error,
                ),
                _buildSummaryChip(
                  theme,
                  icon: Icons.timer_outlined,
                  label: 'Tiempo',
                  valueLabel:
                      '${summary.elapsed.inSeconds}.${summary.elapsed.inMilliseconds % 1000 ~/ 100}s',
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
            if (summary.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text('Ver errores (${summary.errors.length})'),
                children: summary.errors
                    .take(50)
                    .map(
                      (error) => ListTile(
                        leading: const Icon(Icons.warning_amber_outlined),
                        title:
                            Text('Fila ${error.rowNumber}: ${error.message}'),
                        subtitle: Text(
                          error.rowSnapshot.entries
                              .map((entry) => '${entry.key}="${entry.value}"')
                              .join(' · '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (summary.errors.length > 50)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text(
                    'Mostrando primeros 50 errores.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    int? value,
    String? valueLabel,
    required Color color,
  }) {
    final text = valueLabel ?? value?.toString() ?? '0';
    return Chip(
      avatar: Icon(icon, color: color),
      label: Text('$label: $text'),
    );
  }

  List<ProductImportFieldDefinition> get _missingRequiredFields {
    final requiredKeys =
        _importService.requiredFields.map((field) => field.key).toSet();
    final selectedKeys = _mapping.entries
        .where((entry) =>
            entry.value != null && !entry.value!.startsWith('specification:'))
        .map((entry) => entry.value!)
        .toSet();
    final missingKeys = requiredKeys.difference(selectedKeys);
    return _importService.requiredFields
        .where((field) => missingKeys.contains(field.key))
        .toList(growable: false);
  }

  List<DropdownMenuItem<String?>> _buildDropdownItems(String header) {
    final current = _mapping[header];
    final entries = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Ignorar columna'),
      ),
    ];

    for (final definition in _importService.fieldDefinitions) {
      final isAssignedElsewhere = _mapping.entries.any(
        (entry) =>
            entry.key != header &&
            entry.value == definition.key &&
            !definition.key.startsWith('specification:'),
      );
      entries.add(
        DropdownMenuItem<String?>(
          value: definition.key,
          enabled: !isAssignedElsewhere || current == definition.key,
          child: Text(
            definition.required ? '${definition.label} *' : definition.label,
          ),
        ),
      );
    }

    final specKey = 'specification:${_specKeyForHeader(header)}';
    entries.add(
      DropdownMenuItem<String?>(
        value: specKey,
        child: const Text('Especificación (guardar como atributo)'),
      ),
    );

    return entries;
  }

  Future<void> _pickFile() async {
    setState(() {
      _errorMessage = null;
      _summary = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['csv', 'tsv', 'txt', 'xlsx', 'xls'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw ProductImportException(
            'No se pudo leer el archivo seleccionado.');
      }
      await _parseFile(fileName: file.name, bytes: bytes, file: file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _parseFile({
    required String fileName,
    required Uint8List bytes,
    PlatformFile? file,
  }) async {
    if (!mounted) return;
    setState(() {
      _isParsing = true;
      _errorMessage = null;
      _summary = null;
    });

    try {
      final parseResult = await _importService.parseBytes(
        bytes: bytes,
        fileName: fileName,
      );
      if (!mounted) return;
      setState(() {
        _parseResult = parseResult;
        _mapping = _importService.buildInitialMapping(parseResult.headers);
        _selectedFile = file;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _parseResult = null;
        _mapping.clear();
        _selectedFile = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isParsing = false);
      }
    }
  }

  Future<void> _runImport() async {
    final parseResult = _parseResult;
    if (parseResult == null) {
      return;
    }

    final missing = _missingRequiredFields;
    if (missing.isNotEmpty) {
      setState(() {
        _errorMessage =
            'Faltan asignar campos obligatorios: ${missing.map((f) => f.label).join(', ')}';
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _summary = null;
    });

    try {
      final summary = await _importService.importProducts(
        rows: parseResult.rows,
        mapping: _mapping,
        allowUpdates: _allowUpdates,
        createMissingSuppliers: _createMissingSuppliers,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
      });
      _showSnack(
          message:
              'Importación completada: ${summary.inserted} nuevos, ${summary.updated} actualizados.');
      _refreshInventoryCaches();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _downloadTemplateCsv() async {
    setState(() => _isDownloadingCsvTemplate = true);
    try {
      final bytes = await _importService.buildTemplateBytes();
      await FileSaver.instance.saveFile(
        name: 'plantilla_productos',
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.text,
      );
      _showSnack(message: 'Plantilla CSV descargada.');
    } catch (error) {
      _showSnack(message: 'No se pudo descargar la plantilla: $error');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingCsvTemplate = false);
      }
    }
  }

  Future<void> _downloadTemplateExcel() async {
    setState(() => _isDownloadingExcelTemplate = true);
    try {
      final bytes = await _importService.buildTemplateExcelBytes();
      await FileSaver.instance.saveFile(
        name: 'plantilla_productos',
        bytes: bytes,
        ext: 'xlsx',
        mimeType: MimeType.other,
        customMimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      _showSnack(message: 'Plantilla Excel descargada.');
    } catch (error) {
      _showSnack(message: 'No se pudo descargar la plantilla en Excel: $error');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingExcelTemplate = false);
      }
    }
  }

  void _refreshInventoryCaches() {
    try {
      final inventory = context.read<shared_inventory.InventoryService>();
      unawaited(inventory.getProducts(forceRefresh: true));
    } catch (_) {
      // Ignored: service might not be available in some contexts.
    }
  }

  void _showSnack({required String message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _updateMapping(String header, String? newValue) {
    setState(() {
      final updated = Map<String, String?>.from(_mapping);
      if (newValue != null && !newValue.startsWith('specification:')) {
        updated.updateAll((key, value) {
          if (key != header && value == newValue) {
            return null;
          }
          return value;
        });
      }
      updated[header] = newValue;
      _mapping = updated;
    });
  }

  String _specKeyForHeader(String header) {
    final normalized = header
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'atributo' : normalized;
  }
}
