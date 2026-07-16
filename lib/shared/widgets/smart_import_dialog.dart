import 'package:flutter/material.dart';
import '../models/import_options.dart';

/// Dialog to configure smart import options
class SmartImportOptionsDialog extends StatefulWidget {
  final List<String> availableMatchFields;
  final String defaultMatchField;
  final List<String>? availableUpdateFields;

  const SmartImportOptionsDialog({
    super.key,
    required this.availableMatchFields,
    this.defaultMatchField = 'sku',
    this.availableUpdateFields,
  });

  @override
  State<SmartImportOptionsDialog> createState() =>
      _SmartImportOptionsDialogState();
}

class _SmartImportOptionsDialogState extends State<SmartImportOptionsDialog> {
  late ImportMode _selectedMode;
  late String _matchField;
  Set<String> _selectedFields = {};
  bool _selectAllFields = true;

  @override
  void initState() {
    super.initState();
    _selectedMode = ImportMode.upsert;
    _matchField = widget.defaultMatchField;
    if (widget.availableUpdateFields != null) {
      _selectedFields = Set.from(widget.availableUpdateFields!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings, color: Colors.blue),
          SizedBox(width: 8),
          Text('Opciones de Importación'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mode selection
              const Text(
                'Modo de Importación',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...ImportMode.values.map((mode) => RadioListTile<ImportMode>(
                    title: Text(mode.label),
                    subtitle: Text(
                      mode.description,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: mode,
                    groupValue: _selectedMode,
                    onChanged: (value) {
                      setState(() => _selectedMode = value!);
                    },
                  )),
              
              const Divider(height: 32),
              
              // Match field selection
              const Text(
                'Campo de Coincidencia',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Usar este campo para identificar registros existentes:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _matchField,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Campo',
                ),
                items: widget.availableMatchFields.map((field) {
                  return DropdownMenuItem(
                    value: field,
                    child: Text(field.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _matchField = value!);
                },
              ),
              
              if (widget.availableUpdateFields != null) ...[
                const Divider(height: 32),
                
                // Fields to update
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Campos a Actualizar',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _selectAllFields,
                          onChanged: (value) {
                            setState(() {
                              _selectAllFields = value!;
                              if (_selectAllFields) {
                                _selectedFields =
                                    Set.from(widget.availableUpdateFields!);
                              } else {
                                _selectedFields.clear();
                              }
                            });
                          },
                        ),
                        const Text('Todos', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    children: widget.availableUpdateFields!.map((field) {
                      return CheckboxListTile(
                        title: Text(field),
                        value: _selectedFields.contains(field),
                        onChanged: (value) {
                          setState(() {
                            if (value!) {
                              _selectedFields.add(field);
                            } else {
                              _selectedFields.remove(field);
                              _selectAllFields = false;
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Los campos protegidos (id, tenant_id, created_at) nunca se actualizarán',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final options = ImportOptions(
              mode: _selectedMode,
              matchField: _matchField,
              fieldsToUpdate:
                  _selectAllFields ? null : _selectedFields.toList(),
              skipErrors: true,
            );
            Navigator.pop(context, options);
          },
          child: const Text('Importar'),
        ),
      ],
    );
  }
}

/// Preview conflicts before applying import
class ImportConflictPreviewDialog extends StatelessWidget {
  final ImportResult result;
  final VoidCallback onConfirm;

  const ImportConflictPreviewDialog({
    super.key,
    required this.result,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vista Previa de Cambios'),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Nuevos', result.inserted, Colors.green),
                  _buildStat(
                      'Actualizados', result.conflicts.length, Colors.orange),
                  _buildStat('Omitidos', result.skipped, Colors.grey),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Conflicts list
            if (result.conflicts.isNotEmpty) ...[
              const Text(
                'Cambios Detectados:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: result.conflicts.length,
                  itemBuilder: (context, index) {
                    final conflict = result.conflicts[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text(conflict.matchValue),
                        subtitle: Text(
                          '${conflict.changedFields.length} campo(s) modificado(s)',
                          style: const TextStyle(fontSize: 12),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Table(
                              border:
                                  TableBorder.all(color: Colors.grey.shade300),
                              columnWidths: const {
                                0: FlexColumnWidth(2),
                                1: FlexColumnWidth(3),
                                2: FlexColumnWidth(3),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                      color: Colors.grey.shade200),
                                  children: const [
                                    Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text('Campo',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text('Actual',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text('Nuevo',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                ...conflict.changes.entries.map((entry) {
                                  final change = entry.value;
                                  return TableRow(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(change.field),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          '${change.oldValue ?? "null"}',
                                          style: const TextStyle(
                                              color: Colors.red),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          '${change.newValue ?? "null"}',
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ] else
              const Center(
                child: Text('No se detectaron cambios'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Aplicar Cambios'),
        ),
      ],
    );
  }

  Widget _buildStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
