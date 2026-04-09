import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/wheel_building_service.dart';
// import 'dart:math' as math; // Unused

class SpokeLengthCalculatorPage extends StatefulWidget {
  const SpokeLengthCalculatorPage({super.key});

  @override
  State<SpokeLengthCalculatorPage> createState() => _SpokeLengthCalculatorPageState();
}

class _SpokeLengthCalculatorPageState extends State<SpokeLengthCalculatorPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Rim inputs
  final _erdController = TextEditingController();
  final _spokeHolesController = TextEditingController(text: '32');
  
  // Hub inputs
  final _leftFlangeDiameterController = TextEditingController();
  final _rightFlangeDiameterController = TextEditingController();
  final _leftFlangeToCenter = TextEditingController();
  final _rightFlangeToCenter = TextEditingController();
  
  // Lacing
  int _crossPattern = 3;
  
  // Results
  double? _leftSpokeLength;
  double? _rightSpokeLength;
  
  @override
  void dispose() {
    _erdController.dispose();
    _spokeHolesController.dispose();
    _leftFlangeDiameterController.dispose();
    _rightFlangeDiameterController.dispose();
    _leftFlangeToCenter.dispose();
    _rightFlangeToCenter.dispose();
    super.dispose();
  }
  
  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    
    final service = context.read<WheelBuildingService>();
    
    final erdMm = double.parse(_erdController.text);
    final spokeHoles = int.parse(_spokeHolesController.text);
    final leftFlangeDiameter = double.parse(_leftFlangeDiameterController.text);
    final rightFlangeDiameter = double.parse(_rightFlangeDiameterController.text);
    final leftToCenter = double.parse(_leftFlangeToCenter.text);
    final rightToCenter = double.parse(_rightFlangeToCenter.text);
    
    final leftLength = service.calculateSpokeLength(
      erdMm: erdMm,
      flangeDiameterMm: leftFlangeDiameter,
      centerToFlangeMm: leftToCenter,
      spokeHoles: spokeHoles,
      crossPattern: _crossPattern,
    );
    
    final rightLength = service.calculateSpokeLength(
      erdMm: erdMm,
      flangeDiameterMm: rightFlangeDiameter,
      centerToFlangeMm: rightToCenter,
      spokeHoles: spokeHoles,
      crossPattern: _crossPattern,
    );
    
    setState(() {
      _leftSpokeLength = leftLength;
      _rightSpokeLength = rightLength;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Manual Spoke Length Calculator',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter measurements manually',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              
              // Rim section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rim Measurements',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _erdController,
                              decoration: const InputDecoration(
                                labelText: 'ERD (Effective Rim Diameter)',
                                suffixText: 'mm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _spokeHolesController,
                              decoration: const InputDecoration(
                                labelText: 'Number of Spokes',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Hub section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hub Measurements',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      
                      // Left side
                      Text(
                        'Left Side (Non-Drive)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _leftFlangeDiameterController,
                              decoration: const InputDecoration(
                                labelText: 'Flange Diameter (PCD)',
                                suffixText: 'mm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _leftFlangeToCenter,
                              decoration: const InputDecoration(
                                labelText: 'Flange to Center',
                                suffixText: 'mm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Right side
                      Text(
                        'Right Side (Drive)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _rightFlangeDiameterController,
                              decoration: const InputDecoration(
                                labelText: 'Flange Diameter (PCD)',
                                suffixText: 'mm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _rightFlangeToCenter,
                              decoration: const InputDecoration(
                                labelText: 'Flange to Center',
                                suffixText: 'mm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Lacing pattern
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lacing Pattern',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _crossPattern,
                        decoration: const InputDecoration(
                          labelText: 'Cross Pattern',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Radial (0-cross)')),
                          DropdownMenuItem(value: 1, child: Text('1-Cross')),
                          DropdownMenuItem(value: 2, child: Text('2-Cross')),
                          DropdownMenuItem(value: 3, child: Text('3-Cross')),
                          DropdownMenuItem(value: 4, child: Text('4-Cross')),
                        ],
                        onChanged: (v) => setState(() => _crossPattern = v!),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Calculate button
              Center(
                child: ElevatedButton.icon(
                  onPressed: _calculate,
                  icon: const Icon(Icons.calculate),
                  label: const Text('Calculate Spoke Length'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Results
              if (_leftSpokeLength != null && _rightSpokeLength != null)
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Results',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.arrow_back, color: Colors.blue),
                                    const SizedBox(height: 8),
                                    const Text('Left Side (Non-Drive)'),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_leftSpokeLength!.toStringAsFixed(1)} mm',
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.arrow_forward, color: Colors.orange),
                                    const SizedBox(height: 8),
                                    const Text('Right Side (Drive)'),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_rightSpokeLength!.toStringAsFixed(1)} mm',
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
