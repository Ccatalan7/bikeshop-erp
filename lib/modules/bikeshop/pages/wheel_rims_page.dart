import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../services/wheel_building_service.dart';
import '../models/wheel_building_models.dart';

class WheelRimsPage extends StatefulWidget {
  const WheelRimsPage({super.key});

  @override
  State<WheelRimsPage> createState() => _WheelRimsPageState();
}

class _WheelRimsPageState extends State<WheelRimsPage> {
  List<WheelRim> _rims = [];
  List<WheelRim> _filteredRims = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _filterWheelSize;
  String? _filterBrakeType;
  int? _filterSpokeHoles;

  @override
  void initState() {
    super.initState();
    _loadRims();
  }

  Future<void> _loadRims() async {
    setState(() => _isLoading = true);
    try {
      final service = context.read<WheelBuildingService>();
      final rims = await service.getRims();
      setState(() {
        _rims = rims;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rims: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    _filteredRims = _rims.where((rim) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!rim.name.toLowerCase().contains(query) &&
            !(rim.manufacturer?.toLowerCase().contains(query) ?? false) &&
            !(rim.model?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }

      // Wheel size filter
      if (_filterWheelSize != null && rim.wheelSize != _filterWheelSize) {
        return false;
      }

      // Brake type filter
      if (_filterBrakeType != null && rim.brakeType != _filterBrakeType) {
        return false;
      }

      // Spoke holes filter
      if (_filterSpokeHoles != null && rim.spokeHoles != _filterSpokeHoles) {
        return false;
      }

      return true;
    }).toList();
  }

  void _showRimDialog({WheelRim? rim}) {
    showDialog(
      context: context,
      builder: (context) => _RimFormDialog(
        rim: rim,
        onSave: (rimData) async {
          try {
            final service = context.read<WheelBuildingService>();
            
            // Convert map to WheelRim object
            final rimModel = WheelRim(
              id: rim?.id,
              tenantId: rim?.tenantId ?? '',
              productId: rim?.productId,
              name: rimData['name'],
              manufacturer: rimData['manufacturer'],
              model: rimData['model'],
              wheelSize: rimData['wheel_size'],
              erdMm: rimData['erd_mm'],
              spokeHoles: rimData['spoke_holes'],
              internalWidthMm: rimData['internal_width_mm'],
              externalWidthMm: rimData['external_width_mm'],
              rimDepthMm: rimData['rim_depth_mm'],
              brakeType: rimData['brake_type'],
              rimType: rimData['rim_type'],
              isActive: rim?.isActive ?? true,
            );
            
            if (rim == null) {
              await service.createRim(rimModel);
            } else {
              await service.updateRim(rimModel);
            }
            _loadRims();
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(rim == null ? 'Rim created' : 'Rim updated'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving rim: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteRim(WheelRim rim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rim'),
        content: Text('Are you sure you want to delete "${rim.displayName}"?'),
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
        await service.deleteRim(rim.id!);
        _loadRims();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rim deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting rim: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Wheel Rims',
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
                          hintText: 'Search rims...',
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
                      onPressed: () => _showRimDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('New Rim'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Wheel Size',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _filterWheelSize,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: '26"', child: Text('26"')),
                          DropdownMenuItem(value: '27.5"', child: Text('27.5"')),
                          DropdownMenuItem(value: '29"', child: Text('29"')),
                          DropdownMenuItem(value: '700c', child: Text('700c')),
                          DropdownMenuItem(value: '650b', child: Text('650b')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterWheelSize = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Brake Type',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _filterBrakeType,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 'rim', child: Text('Rim')),
                          DropdownMenuItem(value: 'disc', child: Text('Disc')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterBrakeType = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Spoke Holes',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _filterSpokeHoles,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 24, child: Text('24H')),
                          DropdownMenuItem(value: 28, child: Text('28H')),
                          DropdownMenuItem(value: 32, child: Text('32H')),
                          DropdownMenuItem(value: 36, child: Text('36H')),
                          DropdownMenuItem(value: 40, child: Text('40H')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterSpokeHoles = value;
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
              '${_filteredRims.length} rims',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),

          // Rim list
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _filteredRims.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.album, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No rims found. Add your first rim!'
                                  : 'No rims match your search.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredRims.length,
                        itemBuilder: (context, index) {
                          final rim = _filteredRims[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(rim.wheelSize),
                              ),
                              title: Text(rim.displayName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ERD: ${rim.erdMm}mm • ${rim.spokeHoles}H'),
                                  Text(
                                    '${rim.wheelSize} • Width: ${rim.internalWidthMm}mm • ${rim.brakeType}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _showRimDialog(rim: rim),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteRim(rim),
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

class _RimFormDialog extends StatefulWidget {
  final WheelRim? rim;
  final Function(Map<String, dynamic>) onSave;

  const _RimFormDialog({this.rim, required this.onSave});

  @override
  State<_RimFormDialog> createState() => _RimFormDialogState();
}

class _RimFormDialogState extends State<_RimFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;
  late TextEditingController _erdController;
  late TextEditingController _internalWidthController;
  late TextEditingController _externalWidthController;
  late TextEditingController _rimDepthController;
  
  String _wheelSize = '700c';
  int _spokeHoles = 32;
  String _brakeType = 'disc';
  String _rimType = 'clincher';

  @override
  void initState() {
    super.initState();
    final rim = widget.rim;
    _nameController = TextEditingController(text: rim?.name ?? '');
    _manufacturerController = TextEditingController(text: rim?.manufacturer ?? '');
    _modelController = TextEditingController(text: rim?.model ?? '');
    _erdController = TextEditingController(text: rim?.erdMm.toString() ?? '622');
    _internalWidthController = TextEditingController(text: rim?.internalWidthMm.toString() ?? '19');
    _externalWidthController = TextEditingController(text: rim?.externalWidthMm?.toString() ?? '');
    _rimDepthController = TextEditingController(text: rim?.rimDepthMm?.toString() ?? '');
    
    if (rim != null) {
      _wheelSize = rim.wheelSize;
      _spokeHoles = rim.spokeHoles;
      _brakeType = rim.brakeType;
      _rimType = rim.rimType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    _erdController.dispose();
    _internalWidthController.dispose();
    _externalWidthController.dispose();
    _rimDepthController.dispose();
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
                widget.rim == null ? 'New Rim' : 'Edit Rim',
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
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _manufacturerController,
                              decoration: const InputDecoration(
                                labelText: 'Manufacturer *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
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
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Wheel Size *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _wheelSize,
                              items: const [
                                DropdownMenuItem(value: '26"', child: Text('26"')),
                                DropdownMenuItem(value: '27.5"', child: Text('27.5" (650b)')),
                                DropdownMenuItem(value: '29"', child: Text('29"')),
                                DropdownMenuItem(value: '700c', child: Text('700c')),
                                DropdownMenuItem(value: '650b', child: Text('650b')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _wheelSize = value;
                                    // Set typical ERD for common sizes
                                    if (value == '700c') {
                                      _erdController.text = '622';
                                    } else if (value == '29"') {
                                      _erdController.text = '602';
                                    } else if (value == '27.5"' || value == '650b') {
                                      _erdController.text = '584';
                                    } else if (value == '26"') {
                                      _erdController.text = '559';
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Critical measurement
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _erdController,
                              decoration: const InputDecoration(
                                labelText: 'ERD (mm) *',
                                hintText: '622 for 700c',
                                helperText: 'Effective Rim Diameter - CRITICAL for spoke calc!',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                labelText: 'Spoke Holes *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _spokeHoles,
                              items: const [
                                DropdownMenuItem(value: 24, child: Text('24H')),
                                DropdownMenuItem(value: 28, child: Text('28H')),
                                DropdownMenuItem(value: 32, child: Text('32H')),
                                DropdownMenuItem(value: 36, child: Text('36H')),
                                DropdownMenuItem(value: 40, child: Text('40H')),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _spokeHoles = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Width measurements
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _internalWidthController,
                              decoration: const InputDecoration(
                                labelText: 'Internal Width (mm) *',
                                hintText: '19',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _externalWidthController,
                              decoration: const InputDecoration(
                                labelText: 'External Width (mm)',
                                hintText: '23',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _rimDepthController,
                              decoration: const InputDecoration(
                                labelText: 'Rim Depth (mm)',
                                hintText: '20',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Compatibility
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Brake Type *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _brakeType,
                              items: const [
                                DropdownMenuItem(value: 'rim', child: Text('Rim')),
                                DropdownMenuItem(value: 'disc', child: Text('Disc')),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _brakeType = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Rim Type *',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: _rimType,
                              items: const [
                                DropdownMenuItem(value: 'clincher', child: Text('Clincher')),
                                DropdownMenuItem(value: 'tubular', child: Text('Tubular')),
                                DropdownMenuItem(value: 'tubeless_ready', child: Text('Tubeless Ready')),
                                DropdownMenuItem(value: 'hookless', child: Text('Hookless')),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _rimType = value);
                              },
                            ),
                          ),
                        ],
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
                          'manufacturer': _manufacturerController.text,
                          'model': _modelController.text.isEmpty ? null : _modelController.text,
                          'wheel_size': _wheelSize,
                          'erd_mm': double.parse(_erdController.text),
                          'spoke_holes': _spokeHoles,
                          'internal_width_mm': double.parse(_internalWidthController.text),
                          'external_width_mm': _externalWidthController.text.isEmpty 
                              ? null 
                              : double.parse(_externalWidthController.text),
                          'rim_depth_mm': _rimDepthController.text.isEmpty 
                              ? null 
                              : double.parse(_rimDepthController.text),
                          'brake_type': _brakeType,
                          'rim_type': _rimType,
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
