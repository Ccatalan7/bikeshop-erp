import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../services/wheel_building_service.dart';
import '../models/wheel_building_models.dart';

class WheelHubsPage extends StatefulWidget {
  const WheelHubsPage({super.key});

  @override
  State<WheelHubsPage> createState() => _WheelHubsPageState();
}

class _WheelHubsPageState extends State<WheelHubsPage> {
  List<WheelHub> _hubs = [];
  List<WheelHub> _filteredHubs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _filterHubType;
  String? _filterBrakeType;
  int? _filterSpokeHoles;

  @override
  void initState() {
    super.initState();
    _loadHubs();
  }

  Future<void> _loadHubs() async {
    setState(() => _isLoading = true);
    try {
      final service = context.read<WheelBuildingService>();
      final hubs = await service.getHubs();
      setState(() {
        _hubs = hubs;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading hubs: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    _filteredHubs = _hubs.where((hub) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!hub.name.toLowerCase().contains(query) &&
            !(hub.manufacturer?.toLowerCase().contains(query) ?? false) &&
            !(hub.model?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }

      // Hub type filter
      if (_filterHubType != null && hub.hubType != _filterHubType) {
        return false;
      }

      // Brake type filter
      if (_filterBrakeType != null && hub.brakeType != _filterBrakeType) {
        return false;
      }

      // Spoke holes filter
      if (_filterSpokeHoles != null && hub.spokeHoles != _filterSpokeHoles) {
        return false;
      }

      return true;
    }).toList();
  }

  void _showHubDialog({WheelHub? hub}) {
    showDialog(
      context: context,
      builder: (context) => _HubFormDialog(
        hub: hub,
        onSave: (hubData) async {
          try {
            final service = context.read<WheelBuildingService>();
            
            // Convert map to WheelHub object
            final hubModel = WheelHub(
              id: hub?.id,
              tenantId: hub?.tenantId ?? '',
              productId: hub?.productId,
              name: hubData['name'],
              manufacturer: hubData['manufacturer'],
              model: hubData['model'],
              hubType: hubData['hub_type'],
              oldMm: hubData['old_mm'],
              spokeHoles: hubData['spoke_holes'],
              leftFlangeDiameterMm: hubData['left_flange_diameter_mm'],
              rightFlangeDiameterMm: hubData['right_flange_diameter_mm'],
              centerToLeftFlangeMm: hubData['center_to_left_flange_mm'],
              centerToRightFlangeMm: hubData['center_to_right_flange_mm'],
              brakeType: hubData['brake_type'],
              driverType: hubData['driver_type'],
              axleType: hubData['axle_type'],
              isActive: hub?.isActive ?? true,
            );
            
            if (hub == null) {
              await service.createHub(hubModel);
            } else {
              await service.updateHub(hubModel);
            }
            _loadHubs();
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(hub == null ? 'Hub created' : 'Hub updated'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving hub: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteHub(WheelHub hub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Hub'),
        content: Text('Are you sure you want to delete "${hub.displayName}"?'),
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
        await service.deleteHub(hub.id!);
        _loadHubs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hub deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting hub: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Wheel Hubs',
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
                          hintText: 'Search hubs...',
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
                      onPressed: () => _showHubDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('New Hub'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Hub Type',
                          border: OutlineInputBorder(),
                        ),
                        value: _filterHubType,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 'front', child: Text('Front')),
                          DropdownMenuItem(value: 'rear', child: Text('Rear')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterHubType = value;
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
                        value: _filterBrakeType,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 'rim', child: Text('Rim')),
                          DropdownMenuItem(value: 'disc_6bolt', child: Text('Disc 6-bolt')),
                          DropdownMenuItem(value: 'disc_centerlock', child: Text('Disc Centerlock')),
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
                        value: _filterSpokeHoles,
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
              '${_filteredHubs.length} hubs',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),

          // Hub list
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _filteredHubs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.hub, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No hubs found. Add your first hub!'
                                  : 'No hubs match your search.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredHubs.length,
                        itemBuilder: (context, index) {
                          final hub = _filteredHubs[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(hub.hubType == 'front' ? 'F' : 'R'),
                              ),
                              title: Text(hub.displayName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('OLD: ${hub.oldMm}mm • ${hub.spokeHoles}H'),
                                  Text(
                                    'Brake: ${hub.brakeType.replaceAll('_', ' ')} • '
                                    'Driver: ${hub.driverType.replaceAll('_', ' ')}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _showHubDialog(hub: hub),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteHub(hub),
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

class _HubFormDialog extends StatefulWidget {
  final WheelHub? hub;
  final Function(Map<String, dynamic>) onSave;

  const _HubFormDialog({this.hub, required this.onSave});

  @override
  State<_HubFormDialog> createState() => _HubFormDialogState();
}

class _HubFormDialogState extends State<_HubFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;
  late TextEditingController _oldController;
  late TextEditingController _leftFlangeController;
  late TextEditingController _rightFlangeController;
  late TextEditingController _centerToLeftController;
  late TextEditingController _centerToRightController;
  
  String _hubType = 'front';
  int _spokeHoles = 32;
  String _brakeType = 'disc_6bolt';
  String _driverType = 'none';
  String _axleType = 'quick_release';

  @override
  void initState() {
    super.initState();
    final hub = widget.hub;
    _nameController = TextEditingController(text: hub?.name ?? '');
    _manufacturerController = TextEditingController(text: hub?.manufacturer ?? '');
    _modelController = TextEditingController(text: hub?.model ?? '');
    _oldController = TextEditingController(text: hub?.oldMm.toString() ?? '135');
    _leftFlangeController = TextEditingController(text: hub?.leftFlangeDiameterMm.toString() ?? '50');
    _rightFlangeController = TextEditingController(text: hub?.rightFlangeDiameterMm.toString() ?? '50');
    _centerToLeftController = TextEditingController(text: hub?.centerToLeftFlangeMm.toString() ?? '30');
    _centerToRightController = TextEditingController(text: hub?.centerToRightFlangeMm.toString() ?? '30');
    
    if (hub != null) {
      _hubType = hub.hubType;
      _spokeHoles = hub.spokeHoles;
      _brakeType = hub.brakeType;
      _driverType = hub.driverType;
      _axleType = hub.axleType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    _oldController.dispose();
    _leftFlangeController.dispose();
    _rightFlangeController.dispose();
    _centerToLeftController.dispose();
    _centerToRightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.hub == null ? 'New Hub' : 'Edit Hub',
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
                                labelText: 'Hub Type *',
                                border: OutlineInputBorder(),
                              ),
                              value: _hubType,
                              items: const [
                                DropdownMenuItem(value: 'front', child: Text('Front')),
                                DropdownMenuItem(value: 'rear', child: Text('Rear')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _hubType = value;
                                    if (value == 'front') {
                                      _driverType = 'none';
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Technical specs
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _oldController,
                              decoration: const InputDecoration(
                                labelText: 'OLD (mm) *',
                                hintText: '135',
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
                              value: _spokeHoles,
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
                      
                      // Flange measurements
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _leftFlangeController,
                              decoration: const InputDecoration(
                                labelText: 'Left Flange Ø (mm) *',
                                hintText: '50',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _rightFlangeController,
                              decoration: const InputDecoration(
                                labelText: 'Right Flange Ø (mm) *',
                                hintText: '50',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
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
                              controller: _centerToLeftController,
                              decoration: const InputDecoration(
                                labelText: 'Center to Left Flange (mm) *',
                                hintText: '30',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _centerToRightController,
                              decoration: const InputDecoration(
                                labelText: 'Center to Right Flange (mm) *',
                                hintText: '30',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
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
                              value: _brakeType,
                              items: const [
                                DropdownMenuItem(value: 'rim', child: Text('Rim')),
                                DropdownMenuItem(value: 'disc_6bolt', child: Text('Disc 6-bolt')),
                                DropdownMenuItem(value: 'disc_centerlock', child: Text('Disc Centerlock')),
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
                                labelText: 'Driver Type *',
                                border: OutlineInputBorder(),
                              ),
                              value: _driverType,
                              items: [
                                const DropdownMenuItem(value: 'none', child: Text('None (Front)')),
                                if (_hubType == 'rear') ...[
                                  const DropdownMenuItem(value: 'freewheel', child: Text('Freewheel')),
                                  const DropdownMenuItem(value: 'cassette', child: Text('Cassette')),
                                  const DropdownMenuItem(value: 'fixed', child: Text('Fixed Gear')),
                                ],
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _driverType = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Axle Type *',
                          border: OutlineInputBorder(),
                        ),
                        value: _axleType,
                        items: const [
                          DropdownMenuItem(value: 'quick_release', child: Text('Quick Release')),
                          DropdownMenuItem(value: 'thru_axle_12mm', child: Text('Thru-axle 12mm')),
                          DropdownMenuItem(value: 'thru_axle_15mm', child: Text('Thru-axle 15mm')),
                          DropdownMenuItem(value: 'thru_axle_20mm', child: Text('Thru-axle 20mm')),
                          DropdownMenuItem(value: 'bolt_on', child: Text('Bolt-on')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _axleType = value);
                        },
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
                          'hub_type': _hubType,
                          'old_mm': double.parse(_oldController.text),
                          'spoke_holes': _spokeHoles,
                          'left_flange_diameter_mm': double.parse(_leftFlangeController.text),
                          'right_flange_diameter_mm': double.parse(_rightFlangeController.text),
                          'center_to_left_flange_mm': double.parse(_centerToLeftController.text),
                          'center_to_right_flange_mm': double.parse(_centerToRightController.text),
                          'brake_type': _brakeType,
                          'driver_type': _driverType,
                          'axle_type': _axleType,
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
