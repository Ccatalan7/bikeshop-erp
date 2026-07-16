import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/wheel_building_service.dart';
import '../services/bikeshop_service.dart';
import '../models/wheel_building_models.dart';
import '../models/bikeshop_models.dart';
import '../../../scripts/seed_bikes_and_wheels.dart';

class WheelBuilderWizardPage extends StatefulWidget {
  const WheelBuilderWizardPage({super.key});

  @override
  State<WheelBuilderWizardPage> createState() => _WheelBuilderWizardPageState();
}

enum BuildType { fullWheel, replaceHub, replaceRim }

class _WheelBuilderWizardPageState extends State<WheelBuilderWizardPage> {
  int _currentStep = 0;
  
  // Step 0: Bike selection
  Bike? _selectedBike;
  BuildType _buildType = BuildType.fullWheel;
  String _wheelPosition = 'rear'; // 'front' or 'rear'
  
  // Pre-filled specs from bike
  String? _wheelSize; // 29", 27.5", 26", 700c
  int _spokeCount = 32; // Default 32
  double? _frontHubSpacing; // From bike (e.g., 100mm, 110mm)
  double? _rearHubSpacing; // From bike (e.g., 142mm, 148mm)
  
  // Selected components
  WheelHub? _selectedHub;
  WheelRim? _selectedRim;
  int _crossPattern = 3; // Default to 3-cross
  
  // Available components (filtered)
  List<Bike> _bikes = [];
  List<WheelHub> _allHubs = [];
  List<WheelRim> _allRims = [];
  
  // Calculated results
  Map<String, dynamic>? _buildResult;
  bool _isCalculating = false;
  
  @override
  void initState() {
    super.initState();
    _loadBikes();
    _loadAllComponents();
  }

  Future<void> _loadBikes() async {
    final bikeService = context.read<BikeshopService>();
    final bikes = await bikeService.getBikes();
    
    setState(() {
      _bikes = bikes;
    });
  }

  Future<void> _loadAllComponents() async {
    final service = context.read<WheelBuildingService>();
    
    final hubs = await service.getHubs();
    final rims = await service.getRims();
    
    setState(() {
      _allHubs = hubs;
      _allRims = rims;
    });
  }

  void _onBikeSelected(Bike? bike) {
    setState(() {
      _selectedBike = bike;
      if (bike != null) {
        _wheelSize = bike.wheelSize; // e.g., "29"", "27.5"", "700c"
        // Populate hub spacing from bike (critical for filtering)
        _frontHubSpacing = bike.frontHubSpacingMm;
        _rearHubSpacing = bike.rearHubSpacingMm;
        _spokeCount = bike.spokeCount ?? 32; // Default to 32 if not set
      }
      // Reset selections when bike changes
      _selectedHub = null;
      _selectedRim = null;
    });
  }

  // Get filtered hubs based on bike specs and build type
  List<WheelHub> get _filteredHubs {
    if (_buildType == BuildType.replaceRim) {
      // If only replacing rim, we're keeping existing hub - show all hubs (user won't select)
      return _allHubs;
    }
    
    // For fullWheel and replaceHub: filter hubs by spoke count, position, AND OLD measurement
    return _allHubs.where((h) {
      bool matchesSpokes = h.spokeHoles == _spokeCount;
      bool matchesPosition = h.hubType == _wheelPosition;
      
      // Filter by OLD (Over Locknut Dimension) based on wheel position
      bool matchesOLD = true;
      if (_wheelPosition == 'front' && _frontHubSpacing != null) {
        matchesOLD = h.oldMm == _frontHubSpacing;
      } else if (_wheelPosition == 'rear' && _rearHubSpacing != null) {
        matchesOLD = h.oldMm == _rearHubSpacing;
      }
      
      return matchesSpokes && matchesPosition && matchesOLD;
    }).toList();
  }

  // Get filtered rims based on bike specs and build type
  List<WheelRim> get _filteredRims {
    // ALWAYS filter rims by wheel size and spoke count
    // (Even for "Replace Hub Only" - we need to show compatible rims)
    return _allRims.where((r) {
      bool matchesSize = _wheelSize == null || r.wheelSize == _wheelSize;
      bool matchesSpokes = r.spokeHoles == _spokeCount;
      return matchesSize && matchesSpokes;
    }).toList();
  }

  Future<void> _calculateBuild() async {
    if (_selectedHub == null || _selectedRim == null) return;
    
    setState(() => _isCalculating = true);
    
    try {
      final service = context.read<WheelBuildingService>();
      final result = await service.calculateWheelBuild(
        hub: _selectedHub!,
        rim: _selectedRim!,
        crossPattern: _crossPattern,
      );
      
      setState(() {
        _buildResult = result;
        _isCalculating = false;
      });
    } catch (e) {
      setState(() => _isCalculating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error calculating build: $e')),
        );
      }
    }
  }

  void _nextStep() {
    // Step 0: Bike & Build Type
    if (_currentStep == 0) {
      if (_selectedBike == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a bicycle')),
        );
        return;
      }
    }
    
    // Step 1: Hub
    if (_currentStep == 1 && _selectedHub == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a hub')),
      );
      return;
    }
    
    // Auto-select factory rim when entering rim step (if replacing hub only)
    if (_currentStep == 1 &&
        _buildType == BuildType.replaceHub &&
        _selectedRim == null) {
      setState(() {
        // Use factory rim if bike has one, otherwise first matching rim
        if (_selectedBike?.factoryRimId != null) {
          _selectedRim = _allRims.firstWhere(
            (r) => r.id == _selectedBike!.factoryRimId,
            orElse: () =>
                _filteredRims.isNotEmpty ? _filteredRims.first : _allRims.first,
          );
          debugPrint('🎯 Auto-selected FACTORY rim: ${_selectedRim?.name}');
        } else {
          // Fallback: use first matching rim
          final matchingRims = _filteredRims;
          if (matchingRims.isNotEmpty) {
            _selectedRim = matchingRims.first;
            debugPrint(
                '⚠️ No factory rim defined, using first match: ${_selectedRim?.name}');
          }
        }
      });
    }
    
    // Step 2: Rim
    if (_currentStep == 2 && _selectedRim == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rim')),
      );
      return;
    }
    
    // Step 3: Lacing - calculate
    if (_currentStep == 3) {
      _calculateBuild();
    }
    
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _reset() {
    setState(() {
      _currentStep = 0;
      _selectedBike = null;
      _selectedHub = null;
      _selectedRim = null;
      _crossPattern = 3;
      _buildResult = null;
    });
  }

  Future<void> _runSeed() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🚀 Seeding test data...')),
      );
      
      await seedBikesAndWheels();
      
      // Reload data
      await _loadBikes();
      await _loadAllComponents();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Test data seeded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error seeding data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: '🔧 Wheel Builder Wizard',
      body: Row(
        children: [
          // Steps sidebar
          Container(
            width: 250,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Build Steps',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _StepIndicator(
                  step: 1,
                  title: 'Select Bicycle',
                  isActive: _currentStep == 0,
                  isCompleted: _currentStep > 0,
                  icon: Icons.pedal_bike,
                ),
                _StepIndicator(
                  step: 2,
                  title: 'Select Hub',
                  isActive: _currentStep == 1,
                  isCompleted: _selectedHub != null,
                  icon: Icons.hub,
                ),
                _StepIndicator(
                  step: 3,
                  title: 'Select Rim',
                  isActive: _currentStep == 2,
                  isCompleted: _selectedRim != null,
                  icon: Icons.album,
                ),
                _StepIndicator(
                  step: 4,
                  title: 'Lacing Pattern',
                  isActive: _currentStep == 3,
                  isCompleted: _crossPattern >= 0,
                  icon: Icons.hub_outlined,
                ),
                _StepIndicator(
                  step: 5,
                  title: 'Results',
                  isActive: _currentStep == 4,
                  isCompleted: _buildResult != null,
                  icon: Icons.check_circle,
                ),
                const Spacer(),
                // Debug seed button (remove in production)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _runSeed,
                    icon: const Icon(Icons.upload),
                    label: const Text('Seed Test Data'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 36),
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ),
                if (_selectedHub != null || _selectedRim != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Start Over'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Main content area
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _currentStep,
                    children: [
                      _buildBikeSelectionStep(),
                      _buildHubSelectionStep(),
                      _buildRimSelectionStep(),
                      _buildLacingPatternStep(),
                      _buildResultsStep(),
                    ],
                  ),
                ),
                
                // Navigation buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton.icon(
                          onPressed: _previousStep,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                        )
                      else
                        const SizedBox(),
                      ElevatedButton.icon(
                        onPressed: _currentStep < 4 ? _nextStep : null,
                        icon: Icon(_currentStep == 3
                            ? Icons.calculate
                            : Icons.arrow_forward),
                        label: Text(_currentStep == 3 ? 'Calculate' : 'Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikeSelectionStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 1: Select Bicycle',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the bike and what you\'re building or replacing',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 32),
          
          // Bike Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pedal_bike, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Bicycle',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_bikes.isEmpty)
                    const Text(
                        'No bikes found. Add bikes in the Bikeshop module first.')
                  else
                    DropdownButtonFormField<Bike>(
                      initialValue: _selectedBike,
                      decoration: const InputDecoration(
                        labelText: 'Select Bike',
                        border: OutlineInputBorder(),
                      ),
                      items: _bikes.map((bike) {
                        return DropdownMenuItem(
                          value: bike,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${bike.brand} ${bike.model}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                bike.wheelSize ?? 'Unknown size',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _onBikeSelected,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Build Type Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.build, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'What are you building?',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<BuildType>(
                    title: const Text('Full Wheel Build'),
                    subtitle:
                        const Text('Building a complete wheel from scratch'),
                    value: BuildType.fullWheel,
                    groupValue: _buildType,
                    onChanged: (value) {
                      setState(() => _buildType = value!);
                    },
                  ),
                  RadioListTile<BuildType>(
                    title: const Text('Replace Hub Only'),
                    subtitle:
                        const Text('Keeping the existing rim, replacing hub'),
                    value: BuildType.replaceHub,
                    groupValue: _buildType,
                    onChanged: (value) {
                      setState(() => _buildType = value!);
                    },
                  ),
                  RadioListTile<BuildType>(
                    title: const Text('Replace Rim Only'),
                    subtitle:
                        const Text('Keeping the existing hub, replacing rim'),
                    value: BuildType.replaceRim,
                    groupValue: _buildType,
                    onChanged: (value) {
                      setState(() => _buildType = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Wheel Position Selection (Front or Rear)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Wheel Position',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Front Wheel'),
                          value: 'front',
                          groupValue: _wheelPosition,
                          onChanged: (value) {
                            setState(() {
                              _wheelPosition = value!;
                              _selectedHub = null; // Reset hub selection
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Rear Wheel'),
                          value: 'rear',
                          groupValue: _wheelPosition,
                          onChanged: (value) {
                            setState(() {
                              _wheelPosition = value!;
                              _selectedHub = null; // Reset hub selection
                            });
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
          
          // Pre-filled Specs (if bike selected)
          if (_selectedBike != null)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 24, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Pre-filled Specifications',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSpecRow('Wheel Size:', _wheelSize ?? 'Not specified'),
                    _buildSpecRow('Spoke Count:', '${_spokeCount}H'),
                    const SizedBox(height: 8),
                    Text(
                      _buildType == BuildType.replaceHub
                          ? '✓ Components will be filtered to match your existing rim'
                          : _buildType == BuildType.replaceRim
                              ? '✓ Components will be filtered to match your existing hub'
                              : '✓ Components will be filtered to match these specs',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHubSelectionStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 2: Select Hub',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the hub for your wheel build',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          if (_filteredHubs.isEmpty)
            Center(
              child: Column(
                children: [
                  const Icon(Icons.hub, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No compatible hubs found for ${_spokeCount}H wheels',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 350,
                childAspectRatio: 1.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _filteredHubs.length,
              itemBuilder: (context, index) {
                final hub = _filteredHubs[index];
                final isSelected = _selectedHub?.id == hub.id;
                
                return Card(
                  elevation: isSelected ? 8 : 2,
                  color: isSelected
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : null,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedHub = hub);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.hub,
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  hub.displayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight:
                                            isSelected ? FontWeight.bold : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).primaryColor,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _InfoChip(label: 'OLD: ${hub.oldMm}mm'),
                          const SizedBox(height: 4),
                          _InfoChip(label: '${hub.spokeHoles}H'),
                          const SizedBox(height: 4),
                          _InfoChip(label: hub.brakeType.replaceAll('_', ' ')),
                          const SizedBox(height: 4),
                          _InfoChip(label: hub.driverType.replaceAll('_', ' ')),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRimSelectionStep() {
    // Use pre-filtered rims from getter (already filtered by wheel size and spoke count)
    final compatibleRims = _filteredRims;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 3: Select Rim',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _wheelSize != null
                ? 'Showing $_wheelSize rims compatible with ${_spokeCount}H hubs'
                : 'Choose the rim for your wheel build',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          if (compatibleRims.isEmpty)
            Center(
              child: Column(
                children: [
                  const Icon(Icons.album, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    _selectedHub != null
                        ? 'No compatible rims found for ${_selectedHub!.spokeHoles}H hub'
                        : 'No rims found. Add rims first!',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 350,
                childAspectRatio: 1.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: compatibleRims.length,
              itemBuilder: (context, index) {
                final rim = compatibleRims[index];
                final isSelected = _selectedRim?.id == rim.id;
                
                return Card(
                  elevation: isSelected ? 8 : 2,
                  color: isSelected
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : null,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedRim = rim);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.album,
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  rim.displayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight:
                                            isSelected ? FontWeight.bold : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).primaryColor,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _InfoChip(label: 'ERD: ${rim.erdMm}mm'),
                          const SizedBox(height: 4),
                          _InfoChip(label: '${rim.spokeHoles}H'),
                          const SizedBox(height: 4),
                          _InfoChip(label: rim.wheelSize),
                          const SizedBox(height: 4),
                          _InfoChip(label: 'Width: ${rim.internalWidthMm}mm'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLacingPatternStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 3: Choose Lacing Pattern',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Select how the spokes will cross each other',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          
          // Lacing pattern options
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _LacingPatternCard(
                pattern: 0,
                name: 'Radial',
                description:
                    'Spokes go straight from hub to rim. Lightest, stiffest laterally.',
                icon: Icons.brightness_1_outlined,
                isSelected: _crossPattern == 0,
                onTap: () => setState(() => _crossPattern = 0),
              ),
              _LacingPatternCard(
                pattern: 1,
                name: '1-Cross',
                description:
                    'Each spoke crosses one other spoke. Light and responsive.',
                icon: Icons.close,
                isSelected: _crossPattern == 1,
                onTap: () => setState(() => _crossPattern = 1),
              ),
              _LacingPatternCard(
                pattern: 2,
                name: '2-Cross',
                description: 'Each spoke crosses two others. Good balance.',
                icon: Icons.close,
                isSelected: _crossPattern == 2,
                onTap: () => setState(() => _crossPattern = 2),
              ),
              _LacingPatternCard(
                pattern: 3,
                name: '3-Cross',
                description:
                    'Each spoke crosses three others. Most common, durable.',
                icon: Icons.close,
                isSelected: _crossPattern == 3,
                onTap: () => setState(() => _crossPattern = 3),
              ),
              _LacingPatternCard(
                pattern: 4,
                name: '4-Cross',
                description:
                    'Each spoke crosses four others. Maximum strength.',
                icon: Icons.close,
                isSelected: _crossPattern == 4,
                onTap: () => setState(() => _crossPattern = 4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsStep() {
    if (_isCalculating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Calculating spoke lengths...'),
          ],
        ),
      );
    }
    
    if (_buildResult == null) {
      return const Center(
        child: Text('Click Calculate to see results'),
      );
    }
    
    final error = _buildResult!['error'];
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Compatibility Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }
    
    final leftLength = _buildResult!['left_spoke_length_mm'] as double;
    final rightLength = _buildResult!['right_spoke_length_mm'] as double;
    final compatibleLeftSpokes =
        _buildResult!['compatible_left_spokes'] as List;
    final compatibleRightSpokes =
        _buildResult!['compatible_right_spokes'] as List;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Text(
                'Build Calculated!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Build summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Build Summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(height: 24),
                  _SummaryRow(label: 'Hub', value: _selectedHub!.displayName),
                  _SummaryRow(label: 'Rim', value: _selectedRim!.displayName),
                  _SummaryRow(
                    label: 'Lacing',
                    value:
                        _crossPattern == 0 ? 'Radial' : '$_crossPattern-Cross',
                  ),
                  _SummaryRow(
                      label: 'Spoke Holes',
                      value: '${_selectedHub!.spokeHoles}H'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Spoke lengths
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.arrow_back, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Left Side (Non-Drive)',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${leftLength.toStringAsFixed(1)} mm',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.arrow_forward,
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(
                              'Right Side (Drive)',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${rightLength.toStringAsFixed(1)} mm',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Compatible spokes
          Text(
            'Recommended Spokes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          
          if (compatibleLeftSpokes.isEmpty && compatibleRightSpokes.isEmpty)
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No compatible spokes found in inventory. Add spokes close to the calculated lengths.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                if (compatibleLeftSpokes.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Left Side Spokes',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Divider(height: 16),
                          ...compatibleLeftSpokes.map((spoke) {
                            final spokeModel = WheelSpoke.fromJson(spoke);
                            final stock = spoke['inventory_qty'] as int? ??
                                spoke['stock_quantity'] as int? ??
                                0;
                            final diff =
                                spoke['length_difference_mm'] as double;
                            
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    stock > 0 ? Colors.green : Colors.red,
                                child: Text(
                                  '$stock',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(spokeModel.displayName),
                              subtitle: Text(
                                '${spokeModel.manufacturer ?? 'Unknown'} • '
                                'Difference: ${diff.abs().toStringAsFixed(1)}mm',
                              ),
                              trailing: stock > 0
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : const Icon(Icons.error, color: Colors.red),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (compatibleRightSpokes.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Right Side Spokes',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Divider(height: 16),
                          ...compatibleRightSpokes.map((spoke) {
                            final spokeModel = WheelSpoke.fromJson(spoke);
                            final stock = spoke['inventory_qty'] as int? ??
                                spoke['stock_quantity'] as int? ??
                                0;
                            final diff =
                                spoke['length_difference_mm'] as double;
                            
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    stock > 0 ? Colors.green : Colors.red,
                                child: Text(
                                  '$stock',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(spokeModel.displayName),
                              subtitle: Text(
                                '${spokeModel.manufacturer ?? 'Unknown'} • '
                                'Difference: ${diff.abs().toStringAsFixed(1)}mm',
                              ),
                              trailing: stock > 0
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : const Icon(Icons.error, color: Colors.red),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final String title;
  final bool isActive;
  final bool isCompleted;
  final IconData icon;

  const _StepIndicator({
    required this.step,
    required this.title,
    required this.isActive,
    required this.isCompleted,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isActive
          ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
          : null,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isCompleted
                ? Colors.green
                : isActive
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade300,
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Theme.of(context).primaryColor : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _LacingPatternCard extends StatelessWidget {
  final int pattern;
  final String name;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _LacingPatternCard({
    required this.pattern,
    required this.name,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Card(
        elevation: isSelected ? 8 : 2,
        color: isSelected
            ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
            : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      color: isSelected ? Theme.of(context).primaryColor : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).primaryColor,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
