import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';

import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/models/bike_catalog_models.dart';
import '../../../shared/services/bike_catalog_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/branded_loading.dart';

const Map<String, String> _brakeTypeOptions = {
  'rim': 'Llanta',
  'mechanical_disc': 'Disco mecanico',
  'hydraulic_disc': 'Disco hidraulico',
};

const Map<String, String> _freehubTypeOptions = {
  'shimano_hg': 'Shimano HG',
  'microspline': 'Micro Spline',
  'sram_xd': 'SRAM XD',
  'campagnolo': 'Campagnolo',
};

const Map<String, String> _acquisitionConditionOptions = {
  'new': 'Nueva',
  'used': 'Usada',
  'rebuilt': 'Rearmada',
  'unknown': 'Desconocido',
};

const Map<String, String> _maintenanceHistoryOptions = {
  'regular': 'Regular',
  'occasional': 'Ocasional',
  'poor': 'Deficiente',
  'unknown': 'Desconocido',
};

const Map<String, String> _primaryUseOptions = {
  'urban': 'Urbano',
  'commute': 'Traslado',
  'sport': 'Deportivo',
  'trail': 'Trail',
  'downhill': 'Downhill',
  'gravel': 'Gravel',
  'delivery': 'Delivery',
  'mixed': 'Mixto',
  'unknown': 'Desconocido',
};

const Map<String, String> _usageFrequencyOptions = {
  'daily': 'Diario',
  'weekly': 'Semanal',
  'occasional': 'Ocasional',
  'inactive': 'En desuso',
  'unknown': 'Desconocido',
};

const Map<String, String> _yesNoUnknownOptions = {
  'yes': 'Si',
  'no': 'No',
  'unknown': 'Desconocido',
};

const Map<String, String> _storageConditionOptions = {
  'indoor': 'Interior',
  'covered_outdoor': 'Exterior cubierto',
  'outdoor': 'Exterior',
  'unknown': 'Desconocido',
};

const Map<String, String> _weatherExposureOptions = {
  'low': 'Baja',
  'medium': 'Media',
  'high': 'Alta',
  'unknown': 'Desconocido',
};

const Map<String, String> _transportMethodOptions = {
  'none': 'Sin transporte externo',
  'car_rack': 'Portabicicletas auto',
  'truck': 'Camioneta',
  'public_transport': 'Transporte publico',
  'mixed': 'Mixto',
  'unknown': 'Desconocido',
};

const List<String> _frameSizeOptions = [
  'XXS',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
  '48cm',
  '50cm',
  '52cm',
  '54cm',
  '56cm',
  '58cm',
  '60cm',
  'Otra'
];

const List<String> _wheelSizeOptions = [
  '12"',
  '16"',
  '20"',
  '24"',
  '26"',
  '27.5"',
  '29"',
  '700c',
  '650b',
  'Otra'
];

class BikeFormDialog extends StatefulWidget {
  final String customerId;
  final Bike? bike; // Null for new bike, existing bike for edit
  final bool isEmbedded;
  final ValueChanged<Bike>? onSaved;
  final VoidCallback? onCanceled;

  const BikeFormDialog({
    super.key,
    required this.customerId,
    this.bike,
    this.isEmbedded = false,
    this.onSaved,
    this.onCanceled,
  });

  @override
  State<BikeFormDialog> createState() => _BikeFormDialogState();
}

class _BikeFormDialogState extends State<BikeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final BikeCatalogService _bikeCatalogService = BikeCatalogService();

  // Controllers
  late TextEditingController _yearController;
  late TextEditingController _serialNumberController;
  late TextEditingController _colorController;
  late TextEditingController _frameSizeController;
  late TextEditingController _wheelSizeController;
  late TextEditingController _frontHubSpacingController;
  late TextEditingController _rearHubSpacingController;
  late TextEditingController _spokeCountController;
  late TextEditingController _frontRotorSizeController;
  late TextEditingController _rearRotorSizeController;
  late TextEditingController _drivetrainSpeedsController;
  late TextEditingController _drivetrainConfigController;
  late TextEditingController _notesController;

  // Brand and model selection
  BikeBrand? _selectedBrand;
  BikeModel? _selectedModel;
  List<BikeBrand> _brands = [];
  List<BikeModel> _models = [];
  bool _loadingBrands = false;
  bool _loadingModels = false;

  // Keys for resetting fields programmatically
  final Key _brandFieldKey =
      UniqueKey(); // Used if we need to reset brand field
  Key _modelFieldKey =
      UniqueKey(); // Used to reset model field when brand changes

  BikeType _selectedType = BikeType.mountain;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;

  // Image handling
  List<String> _imageUrls = [];
  final List<({Uint8List bytes, String name})> _newImages = [];
  bool _isUploadingImage = false;

  BikeProfile? _existingProfile;
  BikeCatalogEntry? _selectedCatalogBike;
  List<BikeCatalogEntry> _catalogMatches = [];
  bool _isLoadingProfile = false;
  bool _isLoadingCatalogMatches = false;

  String? _brakeType;
  String? _freehubType;
  String? _acquisitionCondition;
  String? _maintenanceHistory;
  String? _primaryUse;
  String? _usageFrequency;
  String? _accidentHistory;
  String? _storageCondition;
  String? _weatherExposure;
  String? _transportMethod;
  Map<String, String> _technicalSources = {};
  Map<String, bool> _technicalConfirmed = {};

  bool _isSaving = false;
  int _currentStep = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing bike data if editing
    _yearController =
        TextEditingController(text: widget.bike?.year?.toString() ?? '');
    _serialNumberController =
        TextEditingController(text: widget.bike?.serialNumber);
    _colorController = TextEditingController(text: widget.bike?.color);
    _frameSizeController = TextEditingController(text: widget.bike?.frameSize);
    _wheelSizeController = TextEditingController(text: widget.bike?.wheelSize);
    _frontHubSpacingController = TextEditingController(
        text: widget.bike?.frontHubSpacingMm?.toString() ?? '');
    _rearHubSpacingController = TextEditingController(
        text: widget.bike?.rearHubSpacingMm?.toString() ?? '');
    _spokeCountController =
        TextEditingController(text: widget.bike?.spokeCount?.toString() ?? '');
    _frontRotorSizeController = TextEditingController();
    _rearRotorSizeController = TextEditingController();
    _drivetrainSpeedsController = TextEditingController();
    _drivetrainConfigController = TextEditingController();
    _notesController = TextEditingController(text: widget.bike?.notes);

    if (widget.bike != null) {
      _selectedType = widget.bike!.bikeType ?? BikeType.mountain;
      _purchaseDate = widget.bike!.purchaseDate;
      _warrantyUntil = widget.bike!.warrantyUntil;
      _imageUrls = List.from(widget.bike!.imageUrls);
    }

    // Load brands and initialize selection
    _loadBrands();

    if (widget.bike?.id != null) {
      _loadBikeProfile();
    }
  }

  Future<void> _loadBikeProfile() async {
    if (widget.bike?.id == null) return;

    setState(() => _isLoadingProfile = true);
    try {
      final service = context.read<BikeshopService>();
      final profile = await service.getBikeProfile(widget.bike!.id!);
      if (profile == null || !mounted) return;

      final technicalValues = profile.technicalValues;
      final intakeValues = profile.intakeProfile;

      BikeCatalogEntry? catalogBike;
      if (profile.catalogBikeId != null && profile.catalogBikeId!.isNotEmpty) {
        catalogBike =
            await _bikeCatalogService.getBikeById(profile.catalogBikeId!);
      }

      setState(() {
        _existingProfile = profile;
        _selectedCatalogBike = catalogBike;
        _brakeType = technicalValues['brakeType']?.toString();
        _freehubType = technicalValues['freehubType']?.toString();
        _frontRotorSizeController.text =
            technicalValues['frontRotorSizeMm']?.toString() ?? '';
        _rearRotorSizeController.text =
            technicalValues['rearRotorSizeMm']?.toString() ?? '';
        _drivetrainSpeedsController.text =
            technicalValues['drivetrainSpeeds']?.toString() ?? '';
        _drivetrainConfigController.text =
            technicalValues['drivetrainConfig']?.toString() ?? '';
        _acquisitionCondition =
            intakeValues['acquisitionCondition']?.toString();
        _maintenanceHistory =
            intakeValues['declaredMaintenanceHistory']?.toString();
        _primaryUse = intakeValues['primaryUse']?.toString();
        _usageFrequency = intakeValues['usageFrequency']?.toString();
        _accidentHistory = intakeValues['accidentHistory']?.toString();
        _storageCondition = intakeValues['storageCondition']?.toString();
        _weatherExposure = intakeValues['weatherExposure']?.toString();
        _transportMethod = intakeValues['transportMethod']?.toString();
        _technicalSources = profile.technicalSources.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
        _technicalConfirmed = profile.technicalConfirmed.map(
          (key, value) => MapEntry(key.toString(), value == true),
        );
      });
    } catch (e) {
      debugPrint('Error loading bike profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  Future<void> _searchCatalogMatches() async {
    final brand = _selectedBrand?.name.trim();
    final model = _selectedModel?.name.trim();
    final year = int.tryParse(_yearController.text.trim());

    if (brand == null || brand.isEmpty || model == null || model.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecciona marca y modelo para buscar en catalogo'),
          ),
        );
      }
      return;
    }

    setState(() => _isLoadingCatalogMatches = true);
    try {
      final matches = await _bikeCatalogService.searchBikes(
        brand: brand,
        model: model,
        year: year,
      );
      if (!mounted) return;
      setState(() {
        _catalogMatches = matches.take(6).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error buscando catalogo: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingCatalogMatches = false);
      }
    }
  }

  void _markTechnicalFieldManual(String key) {
    _technicalSources[key] = 'mechanic';
    _technicalConfirmed[key] = true;
  }

  BikeType? _mapCatalogBikeType(String? value) {
    switch (value) {
      case 'road':
        return BikeType.road;
      case 'mountain_hardtail':
        return BikeType.mountainHardtail;
      case 'mountain':
        return BikeType.mountain;
      case 'hybrid':
        return BikeType.hybrid;
      case 'electric':
        return BikeType.electric;
      case 'bmx':
        return BikeType.bmx;
      case 'gravel':
        return BikeType.gravel;
      default:
        return null;
    }
  }

  void _applyCatalogMatch(BikeCatalogEntry entry) {
    setState(() {
      _selectedCatalogBike = entry;
      _catalogMatches = _catalogMatches.isEmpty ? [entry] : _catalogMatches;

      if (_yearController.text.trim().isEmpty) {
        _yearController.text = entry.modelYear.toString();
      }
      if (_wheelSizeController.text.trim().isEmpty && entry.wheelSize != null) {
        _wheelSizeController.text = entry.wheelSize!;
      }
      if ((_selectedType == BikeType.other || widget.bike == null) &&
          entry.bikeType != null) {
        _selectedType = _mapCatalogBikeType(entry.bikeType) ?? _selectedType;
      }
      if (entry.frontHubSpacingMm != null) {
        _frontHubSpacingController.text = entry.frontHubSpacingMm!.toString();
      }
      if (entry.rearHubSpacingMm != null) {
        _rearHubSpacingController.text = entry.rearHubSpacingMm!.toString();
      }
      if (entry.spokeCount != null) {
        _spokeCountController.text = entry.spokeCount!.toString();
      }

      if (entry.brakeType != null) {
        _brakeType = entry.brakeType;
        _technicalSources['brakeType'] = 'catalog';
        _technicalConfirmed['brakeType'] = false;
      }
      if (entry.brakeRotorSizeFrontMm != null) {
        _frontRotorSizeController.text =
            entry.brakeRotorSizeFrontMm!.toString();
        _technicalSources['frontRotorSizeMm'] = 'catalog';
        _technicalConfirmed['frontRotorSizeMm'] = false;
      }
      if (entry.brakeRotorSizeRearMm != null) {
        _rearRotorSizeController.text = entry.brakeRotorSizeRearMm!.toString();
        _technicalSources['rearRotorSizeMm'] = 'catalog';
        _technicalConfirmed['rearRotorSizeMm'] = false;
      }
      if (entry.drivetrainSpeeds != null) {
        _drivetrainSpeedsController.text = entry.drivetrainSpeeds!.toString();
        _technicalSources['drivetrainSpeeds'] = 'catalog';
        _technicalConfirmed['drivetrainSpeeds'] = false;
      }
      if (entry.drivetrainConfig != null) {
        _drivetrainConfigController.text = entry.drivetrainConfig!;
        _technicalSources['drivetrainConfig'] = 'catalog';
        _technicalConfirmed['drivetrainConfig'] = false;
      }
      if (entry.freehubType != null) {
        _freehubType = entry.freehubType;
        _technicalSources['freehubType'] = 'catalog';
        _technicalConfirmed['freehubType'] = false;
      }
    });
  }

  Future<void> _loadBrands() async {
    setState(() => _loadingBrands = true);
    try {
      final service = context.read<BikeshopService>();
      _brands = await service.getBikeBrands(activeOnly: true);

      // If editing, find and set the selected brand by name
      if (widget.bike != null &&
          widget.bike!.brand != null &&
          widget.bike!.brand!.isNotEmpty) {
        try {
          _selectedBrand = _brands.firstWhere(
            (b) => b.name.toLowerCase() == widget.bike!.brand!.toLowerCase(),
          );
          if (_selectedBrand != null) {
            await _loadModels(_selectedBrand!.id!);
            // Find and set the selected model by name
            if (widget.bike!.model != null && widget.bike!.model!.isNotEmpty) {
              try {
                _selectedModel = _models.firstWhere(
                  (m) =>
                      m.name.toLowerCase() == widget.bike!.model!.toLowerCase(),
                );
              } catch (e) {
                // Model not found, leave null
              }
            }
          }
        } catch (e) {
          // Brand not found, leave null
        }
      }
    } catch (e) {
      debugPrint('Error loading brands: $e');
    } finally {
      setState(() => _loadingBrands = false);
    }
  }

  Future<void> _loadModels(String brandId) async {
    setState(() => _loadingModels = true);
    try {
      final service = context.read<BikeshopService>();
      _models = await service.getBikeModels(brandId: brandId, activeOnly: true);
    } catch (e) {
      debugPrint('Error loading models: $e');
    } finally {
      setState(() => _loadingModels = false);
    }
  }

  // Quick-add brand dialog
  Future<void> _showQuickAddBrandDialog() async {
    final nameController = TextEditingController();
    final service = context.read<BikeshopService>();
    final tenantService = context.read<TenantService>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Marca'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre de la marca',
            hintText: 'Trek, Giant, Specialized...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final tenantId = await tenantService.getTenantId();
        if (!mounted) return;
        if (tenantId == null || tenantId.isEmpty) {
          throw Exception('No se pudo obtener el tenant_id del usuario');
        }

        // Check if brand already exists
        final brandName = nameController.text.trim();
        final existingBrand = _brands.firstWhere(
          (b) => b.name.toLowerCase() == brandName.toLowerCase(),
          orElse: () => BikeBrand(tenantId: tenantId, name: '', isActive: true),
        );

        if (existingBrand.id != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('La marca "$brandName" ya existe'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        final newBrand = BikeBrand(
          tenantId: tenantId,
          name: brandName,
          isActive: true,
        );

        final created = await service.createBikeBrand(newBrand);

        // Reload brands and find the created one
        await _loadBrands();
        final createdBrand = _brands.firstWhere(
          (b) => b.id == created.id,
          orElse: () => created,
        );

        setState(() {
          _selectedBrand = createdBrand;
          _selectedModel = null;
          _models = [];
        });

        if (createdBrand.id != null) {
          await _loadModels(createdBrand.id!);
        }

        messenger.showSnackBar(
          SnackBar(content: Text('Marca "${created.name}" creada')),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Error: ${e.toString().contains('duplicate') ? 'La marca ya existe' : e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Quick-add model dialog
  Future<void> _showQuickAddModelDialog() async {
    if (_selectedBrand == null) return;

    final nameController = TextEditingController();
    final service = context.read<BikeshopService>();
    final tenantService = context.read<TenantService>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nuevo Modelo - ${_selectedBrand!.name}'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre del modelo',
            hintText: 'Marlin 7, Escape 3...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final tenantId = await tenantService.getTenantId();
        if (!mounted) return;
        if (tenantId == null || tenantId.isEmpty) {
          throw Exception('No se pudo obtener el tenant_id del usuario');
        }

        // Check if model already exists
        final modelName = nameController.text.trim();
        final existingModel = _models.firstWhere(
          (m) => m.name.toLowerCase() == modelName.toLowerCase(),
          orElse: () => BikeModel(
              tenantId: tenantId, brandId: '', name: '', isActive: true),
        );

        if (existingModel.id != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('El modelo "$modelName" ya existe'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        final newModel = BikeModel(
          tenantId: tenantId,
          brandId: _selectedBrand!.id!,
          name: modelName,
          isActive: true,
        );

        final created = await service.createBikeModel(newModel);

        // Reload models and find the created one
        await _loadModels(_selectedBrand!.id!);
        final createdModel = _models.firstWhere(
          (m) => m.id == created.id,
          orElse: () => created,
        );

        setState(() {
          _selectedModel = createdModel;
        });

        messenger.showSnackBar(
          SnackBar(content: Text('Modelo "${created.name}" creado')),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Error: ${e.toString().contains('duplicate') ? 'El modelo ya existe' : e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    _serialNumberController.dispose();
    _colorController.dispose();
    _frameSizeController.dispose();
    _wheelSizeController.dispose();
    _frontHubSpacingController.dispose();
    _rearHubSpacingController.dispose();
    _spokeCountController.dispose();
    _frontRotorSizeController.dispose();
    _rearRotorSizeController.dispose();
    _drivetrainSpeedsController.dispose();
    _drivetrainConfigController.dispose();
    _notesController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _hasProfileData() {
    return _selectedCatalogBike != null ||
        _brakeType != null ||
        _freehubType != null ||
        _frontRotorSizeController.text.trim().isNotEmpty ||
        _rearRotorSizeController.text.trim().isNotEmpty ||
        _drivetrainSpeedsController.text.trim().isNotEmpty ||
        _drivetrainConfigController.text.trim().isNotEmpty ||
        _acquisitionCondition != null ||
        _maintenanceHistory != null ||
        _primaryUse != null ||
        _usageFrequency != null ||
        _accidentHistory != null ||
        _storageCondition != null ||
        _weatherExposure != null ||
        _transportMethod != null;
  }

  Future<void> _saveBikeProfile(Bike savedBike, String tenantId) async {
    if (!_hasProfileData() && _existingProfile == null) {
      return;
    }

    final intakeProfile = <String, dynamic>{
      if (_acquisitionCondition != null)
        'acquisitionCondition': _acquisitionCondition,
      if (_maintenanceHistory != null)
        'declaredMaintenanceHistory': _maintenanceHistory,
      if (_primaryUse != null) 'primaryUse': _primaryUse,
      if (_usageFrequency != null) 'usageFrequency': _usageFrequency,
      if (_accidentHistory != null) 'accidentHistory': _accidentHistory,
      if (_storageCondition != null) 'storageCondition': _storageCondition,
      if (_weatherExposure != null) 'weatherExposure': _weatherExposure,
      if (_transportMethod != null) 'transportMethod': _transportMethod,
    };

    final technicalValues = <String, dynamic>{
      if (_brakeType != null) 'brakeType': _brakeType,
      if (_freehubType != null) 'freehubType': _freehubType,
      if (_frontRotorSizeController.text.trim().isNotEmpty)
        'frontRotorSizeMm': int.tryParse(_frontRotorSizeController.text.trim()),
      if (_rearRotorSizeController.text.trim().isNotEmpty)
        'rearRotorSizeMm': int.tryParse(_rearRotorSizeController.text.trim()),
      if (_drivetrainSpeedsController.text.trim().isNotEmpty)
        'drivetrainSpeeds':
            int.tryParse(_drivetrainSpeedsController.text.trim()),
      if (_drivetrainConfigController.text.trim().isNotEmpty)
        'drivetrainConfig': _drivetrainConfigController.text.trim(),
    };

    final summarySnapshot = BikeProfileSummaryBuilder.buildSummarySnapshot(
      bike: savedBike,
      intakeProfile: intakeProfile,
      technicalValues: technicalValues,
      lastConfirmedAt: DateTime.now(),
    );

    final profile = BikeProfile(
      id: _existingProfile?.id,
      tenantId: tenantId,
      bikeId: savedBike.id!,
      catalogBikeId: _selectedCatalogBike?.id,
      intakeProfile: intakeProfile,
      technicalProfile: {
        'values': technicalValues,
        'sources': _technicalSources,
        'confirmed': _technicalConfirmed,
      },
      summarySnapshot: summarySnapshot,
      lastConfirmedAt: DateTime.now(),
      createdAt: _existingProfile?.createdAt,
    );

    final service = context.read<BikeshopService>();
    final savedProfile = await service.upsertBikeProfile(profile);
    _existingProfile = savedProfile;
  }

  Future<void> _selectDate(BuildContext context, bool isPurchaseDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isPurchaseDate
          ? (_purchaseDate ?? DateTime.now())
          : (_warrantyUntil ?? DateTime.now().add(const Duration(days: 365))),
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
      // Removed locale parameter - it can cause freezes on web
    );

    if (picked != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            if (isPurchaseDate) {
              _purchaseDate = picked;
            } else {
              _warrantyUntil = picked;
            }
          });
        }
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      final result = await ImageService.pickImage();

      setState(() {
        _isUploadingImage = false;
      });

      if (result != null) {
        setState(() {
          _newImages.add(result);
        });
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  void _removeImage(int index, bool isNew) {
    setState(() {
      if (isNew) {
        _newImages.removeAt(index);
      } else {
        _imageUrls.removeAt(index);
      }
    });
  }

  Future<void> _saveBike() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bikeshopService =
        Provider.of<BikeshopService>(context, listen: false);
    final tenantService = Provider.of<TenantService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isSaving = true;
    });

    try {
      // Upload new images to Supabase Storage
      List<String> uploadedUrls = List.from(_imageUrls);

      if (_newImages.isNotEmpty) {
        setState(() {
          _isUploadingImage = true;
        });

        for (var imageData in _newImages) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'bike_${widget.customerId}_$timestamp.jpg';

            final url = await ImageService.uploadBytes(
              bytes: imageData.bytes,
              fileName: fileName,
              bucket: 'bike-images',
              folder: widget.customerId,
            );

            if (url != null) {
              uploadedUrls.add(url);
            }
          } catch (e) {
            debugPrint('Error uploading image: $e');
            // Continue with other images even if one fails
          }
        }

        setState(() {
          _isUploadingImage = false;
        });
      }

      // Get tenant ID from auth context
      final tenantId = await tenantService.getTenantId();
      if (!mounted) return;

      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('User does not have a tenant_id. Cannot create bike.');
      }

      final bike = Bike(
        id: widget.bike?.id,
        tenantId: tenantId,
        customerId: widget.customerId,
        brandId: _selectedBrand?.id,
        modelId: _selectedModel?.id,
        brand: _selectedBrand?.name ?? '',
        model: _selectedModel?.name ?? '',
        year: int.tryParse(_yearController.text.trim()),
        bikeType: _selectedType,
        serialNumber: _serialNumberController.text.trim().isEmpty
            ? null
            : _serialNumberController.text.trim(),
        color: _colorController.text.trim().isEmpty
            ? null
            : _colorController.text.trim(),
        frameSize: _frameSizeController.text.trim().isEmpty
            ? null
            : _frameSizeController.text.trim(),
        wheelSize: _wheelSizeController.text.trim().isEmpty
            ? null
            : _wheelSizeController.text.trim(),
        frontHubSpacingMm: _frontHubSpacingController.text.trim().isEmpty
            ? null
            : double.tryParse(_frontHubSpacingController.text.trim()),
        rearHubSpacingMm: _rearHubSpacingController.text.trim().isEmpty
            ? null
            : double.tryParse(_rearHubSpacingController.text.trim()),
        spokeCount: _spokeCountController.text.trim().isEmpty
            ? null
            : int.tryParse(_spokeCountController.text.trim()),
        purchaseDate: _purchaseDate,
        warrantyUntil: _warrantyUntil,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        imageUrls: uploadedUrls,
      );

      Bike savedBike;
      if (widget.bike == null) {
        // Create new bike
        savedBike = await bikeshopService.createBike(bike);
      } else {
        // Update existing bike
        savedBike = await bikeshopService.updateBike(bike);
      }

      await _saveBikeProfile(savedBike, tenantId);

      if (widget.isEmbedded) {
        widget.onSaved?.call(savedBike);
      } else {
        navigator.pop(savedBike); // Return the saved bike
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(widget.bike == null
              ? 'Bicicleta creada exitosamente'
              : 'Bicicleta actualizada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isUploadingImage = false;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al guardar bicicleta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
            '¿Está seguro que desea eliminar la bicicleta "${_selectedBrand?.name ?? ''} ${_selectedModel?.name ?? ''}"?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && widget.bike?.id != null) {
      if (!mounted) return;

      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);

      setState(() => _isSaving = true);

      try {
        await bikeshopService.deleteBike(widget.bike!.id!);
        if (!mounted) return;

        if (widget.isEmbedded) {
          widget.onSaved?.call(widget.bike!);
        } else {
          navigator.pop(null); // Return null to indicate deletion
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Bicicleta eliminada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSaving = false);

        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al eliminar bicicleta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    String? description,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding:
                  const EdgeInsets.only(bottom: 24.0, right: 8.0, left: 4.0),
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdaptiveFields(
    List<Widget> children, {
    double minItemWidth = 240,
    double spacing = 16,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = (maxWidth / minItemWidth).floor().clamp(1, 4);
        final itemWidth =
            (maxWidth - (spacing * (columns - 1))) / columns.toDouble();

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required IconData icon,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        child: Text(
          value != null
              ? DateFormat('dd/MM/yyyy').format(value)
              : 'Seleccionar fecha',
          style: TextStyle(color: value != null ? null : Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _buildBrandField() {
    if (_loadingBrands) {
      return const Center(child: BrandedLoading());
    }

    return Autocomplete<BikeBrand>(
      key: _brandFieldKey,
      initialValue: TextEditingValue(text: _selectedBrand?.name ?? ''),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          return const Iterable<BikeBrand>.empty();
        }
        return _brands.where((BikeBrand option) {
          return option.name
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      displayStringForOption: (BikeBrand option) => option.name,
      onSelected: (BikeBrand selection) async {
        setState(() {
          _selectedBrand = selection;
          _selectedModel = null;
          _models = [];
          _modelFieldKey = UniqueKey();
        });
        if (selection.id != null) {
          await _loadModels(selection.id!);
        }
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController fieldTextEditingController,
        FocusNode fieldFocusNode,
        VoidCallback onFieldSubmitted,
      ) {
        if (_selectedBrand != null &&
            fieldTextEditingController.text != _selectedBrand!.name) {
          fieldTextEditingController.text = _selectedBrand!.name;
        }

        return TextFormField(
          controller: fieldTextEditingController,
          focusNode: fieldFocusNode,
          decoration: InputDecoration(
            labelText: 'Marca *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.branding_watermark_outlined),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Agregar nueva marca',
              onPressed: _showQuickAddBrandDialog,
            ),
          ),
          validator: (value) {
            if (_selectedBrand == null) {
              return 'Seleccione una marca de la lista';
            }
            if (value == null || value.isEmpty) {
              return 'La marca es requerida';
            }
            if (value != _selectedBrand!.name) {
              return 'Seleccione una marca valida';
            }
            return null;
          },
          onChanged: (text) {
            if (_selectedBrand != null && text != _selectedBrand!.name) {
              setState(() {
                _selectedBrand = null;
                _selectedModel = null;
                _models = [];
                _modelFieldKey = UniqueKey();
              });
            }
          },
        );
      },
    );
  }

  Widget _buildModelField() {
    if (_loadingModels) {
      return const Center(child: BrandedLoading());
    }

    return Autocomplete<BikeModel>(
      key: _modelFieldKey,
      initialValue: TextEditingValue(text: _selectedModel?.name ?? ''),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          return const Iterable<BikeModel>.empty();
        }
        return _models.where((BikeModel option) {
          return option.name
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      displayStringForOption: (BikeModel option) => option.name,
      onSelected: (BikeModel selection) {
        setState(() {
          _selectedModel = selection;
        });
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController fieldTextEditingController,
        FocusNode fieldFocusNode,
        VoidCallback onFieldSubmitted,
      ) {
        if (_selectedModel != null &&
            fieldTextEditingController.text != _selectedModel!.name) {
          fieldTextEditingController.text = _selectedModel!.name;
        }

        return TextFormField(
          controller: fieldTextEditingController,
          focusNode: fieldFocusNode,
          enabled: _selectedBrand != null,
          decoration: InputDecoration(
            labelText: 'Modelo *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.directions_bike_outlined),
            suffixIcon: _selectedBrand != null
                ? IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Agregar nuevo modelo',
                    onPressed: _showQuickAddModelDialog,
                  )
                : null,
          ),
          validator: (value) {
            if (_selectedBrand == null) return null;
            if (_selectedModel == null) {
              return 'Seleccione un modelo';
            }
            if (value == null || value.isEmpty) {
              return 'El modelo es requerido';
            }
            if (value != _selectedModel!.name) {
              return 'Seleccione un modelo valido';
            }
            return null;
          },
          onChanged: (text) {
            if (_selectedModel != null && text != _selectedModel!.name) {
              setState(() {
                _selectedModel = null;
              });
            }
          },
        );
      },
    );
  }

  Widget _buildFieldGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 20),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildFrameSizeField() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _frameSizeController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _frameSizeOptions;
        }
        return _frameSizeOptions.where((String option) {
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        _frameSizeController.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (controller.text != _frameSizeController.text) {
          controller.text = _frameSizeController.text;
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Talla del cuadro',
            hintText: 'M, L, 54 cm...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.straighten_outlined),
          ),
          onChanged: (val) => _frameSizeController.text = val,
        );
      },
    );
  }

  Widget _buildWheelSizeField() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _wheelSizeController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _wheelSizeOptions;
        }
        return _wheelSizeOptions.where((String option) {
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        _wheelSizeController.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (controller.text != _wheelSizeController.text) {
          controller.text = _wheelSizeController.text;
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Aro',
            hintText: '29", 27.5", 700c...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.tire_repair_outlined),
          ),
          onChanged: (val) => _wheelSizeController.text = val,
        );
      },
    );
  }

  Widget _buildIdentitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldGroupHeader('Ficha Principal'),
        _buildAdaptiveFields(
          [
            _buildBrandField(),
            _buildModelField(),
            TextFormField(
              controller: _yearController,
              decoration: const InputDecoration(
                labelText: 'Año',
                hintText: '2024',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final year = int.tryParse(value);
                  if (year == null ||
                      year < 1900 ||
                      year > DateTime.now().year + 1) {
                    return 'Año inválido';
                  }
                }
                return null;
              },
            ),
          ],
          minItemWidth: 220,
        ),
        const SizedBox(height: 16),
        _buildCatalogMatchSection(),
        _buildFieldGroupHeader('Características Básicas'),
        _buildAdaptiveFields(
          [
            DropdownButtonFormField<BikeType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Tipo de bicicleta',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: BikeType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                  });
                }
              },
            ),
            _buildFrameSizeField(),
            _buildWheelSizeField(),
            TextFormField(
              controller: _colorController,
              decoration: const InputDecoration(
                labelText: 'Color',
                hintText: 'Negro, rojo, verde...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.palette_outlined),
              ),
            ),
          ],
          minItemWidth: 220,
        ),
        _buildFieldGroupHeader('Registro y Garantía'),
        _buildAdaptiveFields(
          [
            TextFormField(
              controller: _serialNumberController,
              decoration: const InputDecoration(
                labelText: 'Número de serie',
                hintText: 'ABC-12345',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_2_outlined),
              ),
            ),
            _buildDateField(
              label: 'Fecha de compra',
              icon: Icons.shopping_cart_outlined,
              value: _purchaseDate,
              onTap: () => _selectDate(context, true),
            ),
            _buildDateField(
              label: 'Garantía hasta',
              icon: Icons.verified_user_outlined,
              value: _warrantyUntil,
              onTap: () => _selectDate(context, false),
            ),
          ],
          minItemWidth: 220,
        ),
      ],
    );
  }

  Widget _buildTechnicalSection() {
    return _buildSectionCard(
      title: 'Línea base técnica',
      description:
          'Solo los datos que realmente ayudan a servicio, compatibilidad y seguimiento.',
      icon: Icons.tune,
      child: _buildAdaptiveFields(
        [
          _buildCodeDropdown(
            value: _brakeType,
            label: 'Tipo de freno',
            options: _brakeTypeOptions,
            icon: Icons.disc_full,
            onChanged: (value) {
              setState(() {
                _brakeType = value;
                _markTechnicalFieldManual('brakeType');
              });
            },
          ),
          TextFormField(
            controller: _drivetrainSpeedsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Velocidades',
              hintText: '11',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.speed_outlined),
            ),
            onChanged: (_) => setState(
              () => _markTechnicalFieldManual('drivetrainSpeeds'),
            ),
          ),
          TextFormField(
            controller: _drivetrainConfigController,
            decoration: const InputDecoration(
              labelText: 'Configuracion de transmision',
              hintText: '1x11, 2x10...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.settings_input_component_outlined),
            ),
            onChanged: (_) => setState(
              () => _markTechnicalFieldManual('drivetrainConfig'),
            ),
          ),
          _buildCodeDropdown(
            value: _freehubType,
            label: 'Freehub',
            options: _freehubTypeOptions,
            icon: Icons.hub_outlined,
            onChanged: (value) {
              setState(() {
                _freehubType = value;
                _markTechnicalFieldManual('freehubType');
              });
            },
          ),
          TextFormField(
            controller: _frontRotorSizeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Rotor delantero (mm)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.radio_button_checked),
            ),
            onChanged: (_) => setState(
              () => _markTechnicalFieldManual('frontRotorSizeMm'),
            ),
          ),
          TextFormField(
            controller: _rearRotorSizeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Rotor trasero (mm)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.radio_button_checked),
            ),
            onChanged: (_) => setState(
              () => _markTechnicalFieldManual('rearRotorSizeMm'),
            ),
          ),
          TextFormField(
            controller: _frontHubSpacingController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Espaciado maza delantera (mm)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.swap_horiz_outlined),
            ),
          ),
          TextFormField(
            controller: _rearHubSpacingController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Espaciado maza trasera (mm)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.swap_horiz_outlined),
            ),
          ),
          TextFormField(
            controller: _spokeCountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad de rayos',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.blur_on_outlined),
            ),
          ),
        ],
        minItemWidth: 220,
      ),
    );
  }

  Widget _buildIntakeSection() {
    return _buildSectionCard(
      title: 'Ingreso inicial',
      description:
          'Haz estas breves preguntas al cliente para entender el contexto histórico de la bicicleta.',
      icon: Icons.assignment_outlined,
      child: _buildAdaptiveFields(
        [
          _buildCodeDropdown(
            value: _acquisitionCondition,
            label: '¿Fue comprada nueva o usada?',
            options: _acquisitionConditionOptions,
            icon: Icons.sell_outlined,
            onChanged: (value) => setState(() => _acquisitionCondition = value),
          ),
          _buildCodeDropdown(
            value: _maintenanceHistory,
            label: '¿Se le han hecho mantenciones?',
            options: _maintenanceHistoryOptions,
            icon: Icons.build_circle_outlined,
            onChanged: (value) => setState(() => _maintenanceHistory = value),
          ),
          _buildCodeDropdown(
            value: _primaryUse,
            label: '¿Para qué la usas principalmente?',
            options: _primaryUseOptions,
            icon: Icons.route_outlined,
            onChanged: (value) => setState(() => _primaryUse = value),
          ),
          _buildCodeDropdown(
            value: _usageFrequency,
            label: '¿Con qué frecuencia la usas?',
            options: _usageFrequencyOptions,
            icon: Icons.event_repeat_outlined,
            onChanged: (value) => setState(() => _usageFrequency = value),
          ),
          _buildCodeDropdown(
            value: _accidentHistory,
            label: '¿Ha tenido choques fuertes?',
            options: _yesNoUnknownOptions,
            icon: Icons.warning_amber_outlined,
            onChanged: (value) => setState(() => _accidentHistory = value),
          ),
          _buildCodeDropdown(
            value: _storageCondition,
            label: '¿Dónde se guarda habitualmente?',
            options: _storageConditionOptions,
            icon: Icons.home_work_outlined,
            onChanged: (value) => setState(() => _storageCondition = value),
          ),
          _buildCodeDropdown(
            value: _weatherExposure,
            label: '¿Se expone a lluvia o sol?',
            options: _weatherExposureOptions,
            icon: Icons.cloud_outlined,
            onChanged: (value) => setState(() => _weatherExposure = value),
          ),
          _buildCodeDropdown(
            value: _transportMethod,
            label: '¿Cómo la transportas usualmente?',
            options: _transportMethodOptions,
            icon: Icons.emoji_transportation,
            onChanged: (value) => setState(() => _transportMethod = value),
          ),
        ],
        minItemWidth: 260,
      ),
    );
  }

  Widget _buildNotesAndPhotosSection() {
    final theme = Theme.of(context);

    return _buildSectionCard(
      title: 'Notas y fotos',
      description:
          'Memoria visual y observaciones generales de la bicicleta, no del trabajo puntual.',
      icon: Icons.note_alt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_imageUrls.isNotEmpty || _newImages.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.18),
                ),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ..._imageUrls.asMap().entries.map((entry) {
                    final index = entry.key;
                    final url = entry.value;
                    return Stack(
                      children: [
                        Container(
                          width: 124,
                          height: 124,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey[300]!),
                            image: DecorationImage(
                              image: NetworkImage(url),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: InkWell(
                            onTap: () => _removeImage(index, false),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  ..._newImages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final imageData = entry.value;
                    return Stack(
                      children: [
                        Container(
                          width: 124,
                          height: 124,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: Colors.blue[300]!, width: 2),
                            image: DecorationImage(
                              image: MemoryImage(imageData.bytes),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: InkWell(
                            onTap: () => _removeImage(index, true),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'NUEVA',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          if (_imageUrls.isNotEmpty || _newImages.isNotEmpty)
            const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _isUploadingImage ? null : _pickImage,
            icon: _isUploadingImage
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_isUploadingImage ? 'Subiendo...' : 'Agregar foto'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notas generales de la bicicleta',
              hintText:
                  'Estado visual, particularidades, piezas montadas o antecedentes que conviene recordar para futuras visitas.',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note_outlined),
            ),
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeDropdown({
    required String? value,
    required String label,
    required Map<String, String> options,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      items: options.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildCatalogMatchSection() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Búsqueda en catálogo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              if (_catalogMatches.isEmpty && _selectedCatalogBike == null)
                FilledButton.tonalIcon(
                  onPressed:
                      _isLoadingCatalogMatches ? null : _searchCatalogMatches,
                  icon: _isLoadingCatalogMatches
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 16),
                  label: const Text('Buscar'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (_selectedCatalogBike != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coincidencia seleccionada:',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedCatalogBike!.displayName,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (_selectedCatalogBike!.bikeType != null)
                              _selectedCatalogBike!.bikeType!,
                            if (_selectedCatalogBike!.wheelSize != null)
                              _selectedCatalogBike!.wheelSize!,
                          ].join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _selectedCatalogBike = null),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Limpiar'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
          ] else if (_catalogMatches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Se encontraron opciones. Selecciona una para prellenar los datos:',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ..._catalogMatches.map(
              (match) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _applyCatalogMatch(match),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Icon(Icons.directions_bike,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(match.displayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                          const Icon(Icons.chevron_right, size: 18),
                        ]),
                      ),
                    ),
                  )),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => setState(() => _catalogMatches.clear()),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Ocultar'),
            ),
          ] else if (!_isLoadingCatalogMatches) ...[
            const SizedBox(height: 6),
            Text(
              'Usa la marca, modelo y año para prellenar datos técnicos.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.bike != null;
    final theme = Theme.of(context);

    final steps = [
      {
        'title': 'Identidad y Base',
        'icon': Icons.pedal_bike,
        'builder': () => _buildSectionCard(
              title: 'Identidad de la bicicleta',
              description:
                  'Lo esencial para reconocer la bici y vincularla al cliente.',
              icon: Icons.pedal_bike,
              child: _buildIdentitySection(),
            ),
      },
      {
        'title': 'Ingreso',
        'icon': Icons.assignment_outlined,
        'builder': () => _buildIntakeSection(),
      },
      {
        'title': 'Ficha Técnica',
        'icon': Icons.tune,
        'builder': () => _buildTechnicalSection(),
      },
      {
        'title': 'Notas y Fotos',
        'icon': Icons.note_alt_outlined,
        'builder': () => _buildNotesAndPhotosSection(),
      },
    ];

    Widget buildNavigationRail() {
      return Container(
        width: 260,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(
            right: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      isEditing
                          ? Icons.edit_outlined
                          : Icons.add_circle_outline,
                      color: theme.colorScheme.onPrimary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing ? 'Editar bicicleta' : 'Nueva bicicleta',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Registro base y contexto estable.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Expanded(
              child: ListView.builder(
                itemCount: steps.length,
                itemBuilder: (context, index) {
                  final isActive = _currentStep == index;
                  final step = steps[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6, right: 16),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                        onTap: () {
                          setState(() {
                            _currentStep = index;
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                            );
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 4,
                              ),
                            ),
                            color: isActive
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                step['icon'] as IconData,
                                size: 22,
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  step['title'] as String,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isActive
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

    Widget buildStepTabs() {
      // Mobile horizontal tabs equivalent if space is tight
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: steps.length,
          itemBuilder: (context, index) {
            final isActive = _currentStep == index;
            final step = steps[index];
            return InkWell(
              onTap: () {
                setState(() {
                  _currentStep = index;
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  color: isActive
                      ? theme.colorScheme.primary.withValues(alpha: 0.04)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      step['icon'] as IconData,
                      size: 18,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      step['title'] as String,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isMobile) buildNavigationRail(),
            Expanded(
              child: Column(
                children: [
                  if (!widget.isEmbedded && !isMobile)
                    // Dialog close button for wide screens
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, right: 16),
                        child: IconButton(
                          icon: Icon(Icons.close,
                              color: theme.colorScheme.onSurfaceVariant),
                          onPressed: () {
                            if (widget.isEmbedded) {
                              widget.onCanceled?.call();
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                    ),

                  if (isMobile)
                    Stack(
                      children: [
                        if (!widget.isEmbedded)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: Icon(Icons.close,
                                  color: theme.colorScheme.onSurfaceVariant),
                              onPressed: () {
                                if (widget.isEmbedded) {
                                  widget.onCanceled?.call();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 24, 48, 16),
                              child: Text(
                                isEditing
                                    ? 'Editar bicicleta'
                                    : 'Nueva bicicleta',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            buildStepTabs(),
                          ],
                        ),
                      ],
                    ),

                  if (_isLoadingProfile) const LinearProgressIndicator(),

                  // Content Area
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(isMobile ? 24 : 48,
                          isMobile ? 24 : 12, isMobile ? 24 : 48, 0),
                      child: Form(
                        key: _formKey,
                        child: PageView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          controller: _pageController,
                          itemCount: steps.length,
                          itemBuilder: (context, index) {
                            final builder =
                                steps[index]['builder'] as Widget Function();
                            return builder();
                          },
                        ),
                      ),
                    ),
                  ),

                  // Bottom Action Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.12),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 16,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left side buttons
                        Row(
                          children: [
                            if (widget.bike != null)
                              TextButton.icon(
                                onPressed: _isSaving ? null : _confirmDelete,
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                label: const Text('Eliminar',
                                    style: TextStyle(color: Colors.red)),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                        // Right side buttons
                        Row(
                          children: [
                            if (_currentStep > 0)
                              TextButton(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          _currentStep--;
                                          _pageController.previousPage(
                                            duration: const Duration(
                                                milliseconds: 350),
                                            curve: Curves.easeOutCubic,
                                          );
                                        });
                                      },
                                child: const Text('Atrás',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                              )
                            else
                              TextButton(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        if (widget.isEmbedded) {
                                          widget.onCanceled?.call();
                                        } else {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                child: const Text('Cancelar',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(width: 16),
                            if (_currentStep < steps.length - 1) ...[
                              FilledButton.tonalIcon(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        // Validate before proceeding to save early
                                        if (!_formKey.currentState!
                                            .validate()) {
                                          return;
                                        }
                                        _saveBike();
                                      },
                                icon: const Icon(Icons.flash_on),
                                label: const Text('Guardar rápido',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        // Validate before proceeding from Identidad
                                        if (_currentStep == 0) {
                                          if (!_formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                        }
                                        setState(() {
                                          _currentStep++;
                                          _pageController.nextPage(
                                            duration: const Duration(
                                                milliseconds: 350),
                                            curve: Curves.easeOutCubic,
                                          );
                                        });
                                      },
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text('Siguiente',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              )
                            ] else
                              FilledButton.icon(
                                onPressed: _isSaving ? null : _saveBike,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.save),
                                label: Text(
                                    _isSaving ? 'Guardando...' : 'Guardar',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (widget.isEmbedded) {
      return Material(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 100,
                spreadRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: content,
          ),
        ),
      ),
    );
  }
}
