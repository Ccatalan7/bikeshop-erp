import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/spreadsheet_file_handoff_service.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../storage/models/app_stored_file.dart';
import '../models/spreadsheet_model.dart';
import '../services/spreadsheet_service.dart';

class SpreadsheetDashboardPage extends StatefulWidget {
  const SpreadsheetDashboardPage({super.key, this.storeOverride});

  final SpreadsheetStore? storeOverride;

  @override
  State<SpreadsheetDashboardPage> createState() =>
      _SpreadsheetDashboardPageState();
}

class _SpreadsheetDashboardPageState extends State<SpreadsheetDashboardPage> {
  final TextEditingController _searchController = TextEditingController();
  late SpreadsheetStore _store;
  bool _initialized = false;
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isImporting = false;
  String? _loadError;
  String _query = '';
  final Set<String> _busyIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _store = widget.storeOverride ?? context.read<SpreadsheetService>();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SpreadsheetModel> get _visibleSheets {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) return List.unmodifiable(_store.spreadsheets);
    return _store.spreadsheets
        .where((sheet) => sheet.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      await _store.fetchSpreadsheets();
      if (mounted) setState(() => _isLoading = false);
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet dashboard load error: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError =
            'No se pudieron cargar las planillas. Revisa la conexión e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _createNew() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);
    try {
      final sheet = await _store.createSpreadsheet();
      if (mounted && sheet.id != null) {
        context.go('/tools/spreadsheets/${sheet.id}');
      }
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet create error: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear la planilla.')),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _importFromFiles() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);

    try {
      final handoff = SpreadsheetFileHandoffService.instance;
      final files = await handoff.listImportableFiles();
      if (!mounted) return;

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay archivos .xlsx o .csv en Archivos. Los .xls antiguos deben convertirse a .xlsx.',
            ),
          ),
        );
        return;
      }

      final selected = await _chooseImportFile(files);
      if (selected == null || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importando ${selected.fileName}...')),
      );
      final sheet = await handoff.importStoredFile(
        file: selected,
        store: _store,
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted && sheet.id != null) {
        context.go('/tools/spreadsheets/${sheet.id}');
      }
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet file import error: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo importar el archivo: $error')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<AppStoredFile?> _chooseImportFile(List<AppStoredFile> files) {
    return showDialog<AppStoredFile>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importar desde Archivos'),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 560,
          height: 360,
          child: ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final file = files[index];
              return ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                    '${file.extension.toUpperCase()} · ${file.displaySize}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(dialogContext).pop(file),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(SpreadsheetModel sheet) async {
    if (sheet.id == null || _busyIds.contains(sheet.id)) return;
    final controller = TextEditingController(text: sheet.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar planilla'),
        content: TextField(
          key: const ValueKey('dashboard-spreadsheet-name-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim() ?? '';
    if (!mounted || trimmed.isEmpty || trimmed == sheet.name) return;

    setState(() => _busyIds.add(sheet.id!));
    try {
      await _store.renameSpreadsheet(sheet.id!, trimmed);
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet rename error: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar el nombre.')),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(sheet.id));
    }
  }

  Future<void> _delete(SpreadsheetModel sheet) async {
    if (sheet.id == null || _busyIds.contains(sheet.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar planilla?'),
        content: Text(
          'Se eliminará “${sheet.name}” y todas sus celdas. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyIds.add(sheet.id!));
    try {
      await _store.deleteSpreadsheet(sheet.id!);
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet delete error: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la planilla.')),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(sheet.id));
    }
  }

  void _open(SpreadsheetModel sheet) {
    if (sheet.id == null || _busyIds.contains(sheet.id)) return;
    context.go('/tools/spreadsheets/${sheet.id}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainLayout(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? _buildLoadError()
                      : _buildSheetList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planillas',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_store.spreadsheets.length} planilla${_store.spreadsheets.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('import-spreadsheet-action'),
                    onPressed: _isImporting ? null : _importFromFiles,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Importar'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('new-spreadsheet-action'),
                    onPressed: _isCreating ? null : _createNew,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: const Text('Nueva planilla'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: TextField(
              key: const ValueKey('spreadsheet-search-field'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre',
                prefixIcon: const Icon(Icons.search, size: 19),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 38),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetList() {
    final sheets = _visibleSheets;
    if (sheets.isEmpty) {
      final isSearching = _query.trim().isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.table_chart_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              isSearching
                  ? 'No hay planillas que coincidan'
                  : 'Todavía no hay planillas',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              isSearching
                  ? 'Prueba con otro nombre.'
                  : 'Crea una para empezar a trabajar.',
            ),
            if (!isSearching) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _importFromFiles,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Importar archivo'),
                  ),
                  FilledButton.icon(
                    onPressed: _isCreating ? null : _createNew,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Crear planilla'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Column(
          children: [
            if (!compact) _buildColumnHeader(),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('spreadsheet-list'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                itemCount: sheets.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _buildSheetRow(sheets[index], compact: compact),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColumnHeader() {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 12, 60, 6),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('NOMBRE', style: style)),
          SizedBox(width: 120, child: Text('TAMAÑO', style: style)),
          SizedBox(
              width: 180, child: Text('ÚLTIMA ACTUALIZACIÓN', style: style)),
        ],
      ),
    );
  }

  Widget _buildSheetRow(SpreadsheetModel sheet, {required bool compact}) {
    final theme = Theme.of(context);
    final isBusy = sheet.id != null && _busyIds.contains(sheet.id);
    final date = sheet.updatedAt ?? sheet.createdAt;
    final dateLabel = date == null
        ? 'Sin fecha'
        : DateFormat('dd MMM yyyy, HH:mm').format(date.toLocal());
    final sizeLabel = '${sheet.rowCount} × ${sheet.colCount}';

    return InkWell(
      onTap: isBusy ? null : () => _open(sheet),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: isBusy
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(
                      Icons.grid_on_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sheet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '$sizeLabel · $dateLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!compact) ...[
              SizedBox(
                width: 120,
                child: Text(sizeLabel, style: theme.textTheme.bodySmall),
              ),
              SizedBox(
                width: 180,
                child: Text(dateLabel, style: theme.textTheme.bodySmall),
              ),
            ],
            SizedBox(
              width: 48,
              child: PopupMenuButton<String>(
                tooltip: 'Acciones',
                enabled: !isBusy,
                onSelected: (value) {
                  if (value == 'rename') _rename(sheet);
                  if (value == 'delete') _delete(sheet);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
