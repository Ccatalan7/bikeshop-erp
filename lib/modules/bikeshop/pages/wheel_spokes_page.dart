import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../services/wheel_building_service.dart';
import '../models/wheel_building_models.dart';

class WheelSpokesPage extends StatefulWidget {
  const WheelSpokesPage({super.key});

  @override
  State<WheelSpokesPage> createState() => _WheelSpokesPageState();
}

class _WheelSpokesPageState extends State<WheelSpokesPage> {
  List<WheelSpoke> _spokes = [];
  List<WheelSpoke> _filteredSpokes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _filterLength;
  double? _filterGauge;
  bool? _filterButted;

  @override
  void initState() {
    super.initState();
    _loadSpokes();
  }

  Future<void> _loadSpokes() async {
    setState(() => _isLoading = true);
    try {
      final service = context.read<WheelBuildingService>();
      final spokes = await service.getSpokes();
      setState(() {
        _spokes = spokes;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading spokes: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    _filteredSpokes = _spokes.where((spoke) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!spoke.name.toLowerCase().contains(query) &&
            !(spoke.manufacturer?.toLowerCase().contains(query) ?? false) &&
            !(spoke.model?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }

      // Length filter
      if (_filterLength != null && spoke.lengthMm != _filterLength) {
        return false;
      }

      // Gauge filter
      if (_filterGauge != null && spoke.gauge != _filterGauge) {
        return false;
      }

      // Butted filter
      if (_filterButted != null && spoke.isButted != _filterButted) {
        return false;
      }

      return true;
    }).toList();
  }

  void _showSpokeDialog({WheelSpoke? spoke}) {
    showDialog(
      context: context,
      builder: (context) => _SpokeFormDialog(
        spoke: spoke,
        onSave: (spokeData) async {
          try {
            final service = context.read<WheelBuildingService>();
            
            // Convert map to WheelSpoke object
            final spokeModel = WheelSpoke(
              id: spoke?.id,
              tenantId: spoke?.tenantId ?? '',
              productId: spoke?.productId,
              name: spokeData['name'],
              manufacturer: spokeData['manufacturer'],
              model: spokeData['model'],
              lengthMm: spokeData['length_mm'],
              gauge: spokeData['gauge'],
              isButted: spokeData['is_butted'],
              material: spokeData['material'],
              finish: spokeData['finish'],
              headType: spokeData['head_type'],
              tensileStrengthN: spokeData['tensile_strength_n'],
              weightGrams: spokeData['weight_grams'],
              isActive: spoke?.isActive ?? true,
            );
            
            if (spoke == null) {
              await service.createSpoke(spokeModel);
            } else {
              await service.updateSpoke(spokeModel);
            }
            _loadSpokes();
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(spoke == null ? 'Spoke created' : 'Spoke updated'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving spoke: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteSpoke(WheelSpoke spoke) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Spoke'),
        content:
            Text('Are you sure you want to delete "${spoke.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final service = context.read<WheelBuildingService>();
        await service.deleteSpoke(spoke.id!);
        _loadSpokes();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Spoke deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting spoke: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Wheel Spokes',
      body: Column(
        children: [
          // Search and filters
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search spokes...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showSpokeDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('New Spoke'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Length',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _filterLength,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All')),
                          ...List.generate(20, (i) => 284 + i * 2).map(
                            (length) => DropdownMenuItem(
                              value: length,
                              child: Text('${length}mm'),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterLength = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        decoration: const InputDecoration(
                          labelText: 'Gauge',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _filterGauge,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 2.0, child: Text('2.0mm')),
                          DropdownMenuItem(value: 1.8, child: Text('1.8mm')),
                          DropdownMenuItem(
                              value: 2.34, child: Text('2.34mm (13g)')),
                          DropdownMenuItem(
                              value: 2.6, child: Text('2.6mm (12g)')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterGauge = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        decoration: const InputDecoration(
                          labelText: 'Butted',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _filterButted,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: true, child: Text('Butted')),
                          DropdownMenuItem(
                              value: false, child: Text('Straight')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterButted = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              '${_filteredSpokes.length} spokes',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),

          // Spoke list
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _filteredSpokes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.linear_scale,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No spokes found. Add your first spoke!'
                                  : 'No spokes match your search.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredSpokes.length,
                        itemBuilder: (context, index) {
                          final spoke = _filteredSpokes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text('${spoke.lengthMm}'),
                              ),
                              title: Text(spoke.displayName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${spoke.manufacturer ?? 'Unknown'} ${spoke.model ?? ''}',
                                  ),
                                  Text(
                                    '${spoke.gauge}mm • ${spoke.isButted ? 'Butted' : 'Straight'} • '
                                    '${spoke.headType.replaceAll('_', ' ')}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () =>
                                        _showSpokeDialog(spoke: spoke),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _deleteSpoke(spoke),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SpokeFormDialog extends StatefulWidget {
  final WheelSpoke? spoke;
  final Function(Map<String, dynamic>) onSave;

  const _SpokeFormDialog({this.spoke, required this.onSave});

  @override
  State<_SpokeFormDialog> createState() => _SpokeFormDialogState();
}

class _SpokeFormDialogState extends State<_SpokeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;
  late TextEditingController _lengthController;
  late TextEditingController _tensileStrengthController;
  late TextEditingController _weightController;
  
  double _gauge = 2.0;
  bool _isButted = false;
  String _material = 'stainless_steel';
  String _finish = 'plain';
  String _headType = 'j_bend';

  @override
  void initState() {
    super.initState();
    final spoke = widget.spoke;
    _nameController = TextEditingController(text: spoke?.name ?? '');
    _manufacturerController =
        TextEditingController(text: spoke?.manufacturer ?? '');
    _modelController = TextEditingController(text: spoke?.model ?? '');
    _lengthController =
        TextEditingController(text: spoke?.lengthMm.toString() ?? '292');
    _tensileStrengthController =
        TextEditingController(text: spoke?.tensileStrengthN?.toString() ?? '');
    _weightController =
        TextEditingController(text: spoke?.weightGrams?.toString() ?? '');
    
    if (spoke != null) {
      _gauge = spoke.gauge;
      _isButted = spoke.isButted;
      _material = spoke.material;
      _finish = spoke.finish ?? 'plain';
      _headType = spoke.headType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    _lengthController.dispose();
    _tensileStrengthController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.spoke == null ? 'New Spoke' : 'Edit Spoke',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Basic info
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Name *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _manufacturerController,
                              decoration: const InputDecoration(
                                labelText: 'Manufacturer',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _modelController,
                              decoration: const InputDecoration(
                                labelText: 'Model',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _lengthController,
                              decoration: const InputDecoration(
                                labelText: 'Length (mm) *',
                                hintText: '292',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Gauge and butted
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              decoration: const InputDecoration(
                                labelText: 'Gauge *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _gauge,
                              items: const [
                                DropdownMenuItem(
                                    value: 2.0, child: Text('2.0mm (15g)')),
                                DropdownMenuItem(
                                    value: 1.8, child: Text('1.8mm (16g)')),
                                DropdownMenuItem(
                                    value: 2.34, child: Text('2.34mm (13g)')),
                                DropdownMenuItem(
                                    value: 2.6, child: Text('2.6mm (12g)')),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _gauge = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Butted'),
                              subtitle: const Text('Double or triple butted'),
                              value: _isButted,
                              onChanged: (value) {
                                setState(() => _isButted = value ?? false);
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Material and head type
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Material *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _material,
                              items: const [
                                DropdownMenuItem(
                                    value: 'stainless_steel',
                                    child: Text('Stainless Steel')),
                                DropdownMenuItem(
                                    value: 'brass', child: Text('Brass')),
                                DropdownMenuItem(
                                    value: 'titanium', child: Text('Titanium')),
                                DropdownMenuItem(
                                    value: 'aluminum', child: Text('Aluminum')),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _material = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Head Type *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _headType,
                              items: const [
                                DropdownMenuItem(
                                    value: 'j_bend', child: Text('J-Bend')),
                                DropdownMenuItem(
                                    value: 'straight_pull',
                                    child: Text('Straight Pull')),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _headType = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Finish and optional specs
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Finish',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _finish,
                              items: const [
                                DropdownMenuItem(
                                    value: 'plain', child: Text('Plain')),
                                DropdownMenuItem(
                                    value: 'black', child: Text('Black')),
                                DropdownMenuItem(
                                    value: 'silver', child: Text('Silver')),
                                DropdownMenuItem(
                                    value: 'colored', child: Text('Colored')),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _finish = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _tensileStrengthController,
                              decoration: const InputDecoration(
                                labelText: 'Tensile Strength (N)',
                                hintText: '1200',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _weightController,
                        decoration: const InputDecoration(
                          labelText: 'Weight (grams)',
                          hintText: '5.5',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSave({
                          'name': _nameController.text,
                          'manufacturer': _manufacturerController.text.isEmpty 
                              ? null 
                              : _manufacturerController.text,
                          'model': _modelController.text.isEmpty 
                              ? null 
                              : _modelController.text,
                          'length_mm': int.parse(_lengthController.text),
                          'gauge': _gauge,
                          'is_butted': _isButted,
                          'material': _material,
                          'finish': _finish,
                          'head_type': _headType,
                          'tensile_strength_n':
                              _tensileStrengthController.text.isEmpty
                              ? null 
                              : int.parse(_tensileStrengthController.text),
                          'weight_grams': _weightController.text.isEmpty 
                              ? null 
                              : double.parse(_weightController.text),
                        });
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
