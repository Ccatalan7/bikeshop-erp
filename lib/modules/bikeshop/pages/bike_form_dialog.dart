import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/brake_canonical_data.dart';
import '../config/bottom_bracket_canonical_data.dart';
import '../config/drivetrain_canonical_data.dart';
import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';
import '../widgets/bike_diagram_illustration.dart';
import '../widgets/bike_system_controller.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/models/bike_catalog_models.dart';
import '../../../shared/services/bike_catalog_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/branded_loading.dart';

enum _BikeAggregateLoadState {
  creating,
  loading,
  loadedWithoutProfile,
  loadedWithProfile,
  failed,
  conflicted,
  outcomeUnknown,
}

const Map<String, String> _suspensionLayoutOptions = {
  'rigid': 'Rigida',
  'front_suspension': 'Suspension delantera',
  'full_suspension': 'Doble suspension',
  'unknown': 'Desconocido',
};

const Map<String, String> _valveTypeOptions = {
  'presta': 'Presta',
  'schrader': 'Schrader',
  'dunlop': 'Dunlop',
  'other': 'Otra',
  'unknown': 'Desconocido',
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

const List<int> _rotorSizeOptions = [140, 160, 180, 203, 220];
const List<int> _frontChainringCountOptions = [1, 2, 3];
const List<int> _rearCogCountOptions = [
  1,
  3,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14
];
const List<int> _frontHubSpacingOptions = [74, 100, 110, 135, 150];
const List<int> _rearHubSpacingOptions = [
  110,
  120,
  126,
  130,
  135,
  142,
  148,
  150,
  157,
  170,
  177,
  190,
  197,
];
const List<int> _spokeHoleOptions = [20, 24, 28, 32, 36, 40, 48];

class _DrivetrainBreakdown {
  final int frontChainringCount;
  final int rearCogCount;

  const _DrivetrainBreakdown({
    required this.frontChainringCount,
    required this.rearCogCount,
  });

  int get totalSpeeds => frontChainringCount * rearCogCount;

  String get configValue {
    if (frontChainringCount == 1 && rearCogCount == 1) {
      return 'singlespeed';
    }
    return '${frontChainringCount}x$rearCogCount';
  }
}

class _BikeTypeKernelDefaults {
  final String? suspensionLayout;
  final List<String>? allowedSuspensionLayouts;
  final String? drivetrainConfig;
  final String? freehubType;

  const _BikeTypeKernelDefaults({
    this.suspensionLayout,
    this.allowedSuspensionLayouts,
    this.drivetrainConfig,
    this.freehubType,
  });
}

class BikeFormDialog extends StatefulWidget {
  final String customerId;
  final Bike? bike; // Null for new bike, existing bike for edit
  final bool isEmbedded;
  final ValueChanged<Bike>? onSaved;
  final VoidCallback? onCanceled;
  final List<Bike> bikePickerOptions;
  final Future<bool> Function(Bike bike)? onBikePickerSelected;

  const BikeFormDialog({
    super.key,
    required this.customerId,
    this.bike,
    this.isEmbedded = false,
    this.onSaved,
    this.onCanceled,
    this.bikePickerOptions = const [],
    this.onBikePickerSelected,
  });

  @override
  State<BikeFormDialog> createState() => _BikeFormDialogState();
}

class _BikeFormDialogState extends State<BikeFormDialog> {
  static const int _technicalStepIndex = 2;

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
  late TextEditingController _frontSpokeHolesController;
  late TextEditingController _rearSpokeHolesController;
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

  BikeType _selectedType = BikeType.mountainHardtail;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;

  // Image handling
  List<String> _imageUrls = [];
  final List<({Uint8List bytes, String name})> _newImages = [];
  final Set<String> _pendingUploadedImageUrls = {};
  bool _isUploadingImage = false;

  BikeProfile? _existingProfile;
  Bike? _authoritativeBike;
  BikeCatalogEntry? _selectedCatalogBike;
  bool _catalogLinkExplicitlyCleared = false;
  List<BikeCatalogEntry> _catalogMatches = [];
  _BikeAggregateLoadState _aggregateLoadState =
      _BikeAggregateLoadState.creating;
  late final String _draftBikeId;
  String? _pendingSaveOperationKey;
  String? _pendingSaveContentSignature;
  DateTime? _pendingSaveConfirmedAt;
  bool _pendingSaveAllowsIncompleteTechnicalKernel = false;
  bool _isLoadingCatalogMatches = false;
  bool _isChangingJobBike = false;

  String? _suspensionLayout;
  String? _brakeType;
  String? _rimBrakeFamily;
  String? _freehubType;
  String? _valveType;
  String? _bottomBracketFamily;
  String? _bbShellWidthValue;
  String? _bbShellDiameterValue;
  String? _spindleInterface;
  int? _frontRotorSizeMm;
  int? _rearRotorSizeMm;
  int? _frontChainringCount;
  int? _rearCogCount;
  String? _legacyDrivetrainConfig;
  int? _legacyDrivetrainSpeeds;
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
  String? _selectedTechnicalSystemKey;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();

    _draftBikeId = widget.bike?.id ?? const Uuid().v4();
    _authoritativeBike = widget.bike;
    _aggregateLoadState = widget.bike?.id == null
        ? _BikeAggregateLoadState.creating
        : _BikeAggregateLoadState.loading;

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
    final spokeCountText = widget.bike?.spokeCount?.toString() ?? '';
    _frontSpokeHolesController = TextEditingController(text: spokeCountText);
    _rearSpokeHolesController = TextEditingController(text: spokeCountText);
    _notesController = TextEditingController(text: widget.bike?.notes);

    if (widget.bike != null) {
      _selectedType = widget.bike!.bikeType ?? BikeType.mountainHardtail;
      _purchaseDate = widget.bike!.purchaseDate;
      _warrantyUntil = widget.bike!.warrantyUntil;
      _imageUrls = List.from(widget.bike!.imageUrls);
      _applyBikeTypeDefaults();
    } else {
      _applyBikeTypeDefaults();
    }

    if (widget.bike?.id != null) {
      _loadBikeAggregate();
    } else {
      // New bicycles have no aggregate to hydrate before reference data loads.
      _loadNewBikeReferences();
    }
  }

  bool get _aggregateLoadBlocksEditing =>
      _aggregateLoadState == _BikeAggregateLoadState.loading ||
      _aggregateLoadState == _BikeAggregateLoadState.failed ||
      _aggregateLoadState == _BikeAggregateLoadState.conflicted ||
      _aggregateLoadState == _BikeAggregateLoadState.outcomeUnknown;

  Future<void> _loadBikeAggregate() async {
    if (widget.bike?.id == null) return;

    setState(() {
      _aggregateLoadState = _BikeAggregateLoadState.loading;
    });
    try {
      final service = context.read<BikeshopService>();
      final aggregate = await service.getBikeAggregate(widget.bike!.id!);
      if (!mounted) return;

      final profile = aggregate.profile;
      if (profile == null) {
        setState(() {
          _authoritativeBike = aggregate.bike;
          _hydrateBikeIdentity(aggregate.bike);
          _existingProfile = null;
          _selectedCatalogBike = null;
          _catalogMatches = [];
          _catalogLinkExplicitlyCleared = false;
        });
        await _loadBrands(
          propagateErrors: true,
          resetSelection: true,
        );
        if (!mounted) return;
        setState(() {
          _aggregateLoadState = _BikeAggregateLoadState.loadedWithoutProfile;
        });
        return;
      }

      final technicalValues = profile.technicalValues;
      final intakeValues = profile.intakeProfile;

      setState(() {
        _authoritativeBike = aggregate.bike;
        _hydrateBikeIdentity(aggregate.bike);
        _existingProfile = profile;
        _selectedCatalogBike = null;
        _catalogMatches = [];
        _catalogLinkExplicitlyCleared = false;
        _suspensionLayout = technicalValues['suspensionLayout']?.toString();
        _brakeType = technicalValues['brakeType']?.toString();
        _rimBrakeFamily = _brakeType == 'rim'
            ? technicalValues['rimBrakeFamily']?.toString()
            : null;
        _freehubType = technicalValues['freehubType']?.toString();
        _valveType = technicalValues['valveType']?.toString();
        _bottomBracketFamily = canonicalBottomBracketFamilyValue(
              technicalValues['bottomBracketFamily']?.toString(),
            ) ??
            technicalValues['bottomBracketFamily']?.toString();
        _bbShellWidthValue = _formatMeasurementSelection(
          technicalValues['bbShellWidthMm'] ??
              technicalValues['bb_shell_width_mm'],
        );
        _bbShellDiameterValue = _formatMeasurementSelection(
          technicalValues['bbShellDiameterMm'] ??
              technicalValues['bb_shell_diameter_mm'],
        );
        _spindleInterface = canonicalBottomBracketSpindleInterfaceValue(
              technicalValues['spindleInterface']?.toString() ??
                  technicalValues['spindle_interface']?.toString(),
            ) ??
            technicalValues['spindleInterface']?.toString() ??
            technicalValues['spindle_interface']?.toString();
        _frontRotorSizeMm = !_isDiscBrakeType(_brakeType)
            ? null
            : _parseNullableIntValue(technicalValues['frontRotorSizeMm']);
        _rearRotorSizeMm = !_isDiscBrakeType(_brakeType)
            ? null
            : _parseNullableIntValue(technicalValues['rearRotorSizeMm']);
        _frontSpokeHolesController.text =
            technicalValues['frontSpokeHoles']?.toString() ??
                aggregate.bike.spokeCount?.toString() ??
                '';
        _rearSpokeHolesController.text =
            technicalValues['rearSpokeHoles']?.toString() ??
                aggregate.bike.spokeCount?.toString() ??
                '';
        _hydrateDrivetrainState(
          configRaw: technicalValues['drivetrainConfig']?.toString(),
          totalSpeeds:
              _parseNullableIntValue(technicalValues['drivetrainSpeeds']),
        );
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
        _applyBikeTypeDefaults();
      });

      await _loadBrands(
        propagateErrors: true,
        resetSelection: true,
      );
      if (!mounted) return;
      setState(() {
        _aggregateLoadState = _BikeAggregateLoadState.loadedWithProfile;
      });

      // Catalog enrichment is optional. The persisted profile is authoritative
      // and has already been hydrated, so a catalog/network failure cannot make
      // the technical sheet appear empty.
      if (profile.catalogBikeId != null && profile.catalogBikeId!.isNotEmpty) {
        try {
          final catalogBike =
              await _bikeCatalogService.getBikeById(profile.catalogBikeId!);
          if (mounted &&
              _selectedCatalogBike == null &&
              !_catalogLinkExplicitlyCleared) {
            setState(() {
              _selectedCatalogBike = catalogBike;
              _catalogLinkExplicitlyCleared = false;
            });
          }
        } catch (e) {
          debugPrint('Error enriching bike profile from catalog: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aggregateLoadState = _BikeAggregateLoadState.failed;
        });
      }
      debugPrint('Error loading bike aggregate: $e');
    }
  }

  Future<void> _loadNewBikeReferences() async {
    setState(() {
      _aggregateLoadState = _BikeAggregateLoadState.loading;
    });
    try {
      await _loadBrands(
        propagateErrors: true,
        resetSelection: true,
      );
      if (!mounted) return;
      setState(() {
        _aggregateLoadState = _BikeAggregateLoadState.creating;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aggregateLoadState = _BikeAggregateLoadState.failed;
      });
      debugPrint('Error loading new bicycle reference data: $e');
    }
  }

  void _hydrateBikeIdentity(Bike bike) {
    _yearController.text = bike.year?.toString() ?? '';
    _serialNumberController.text = bike.serialNumber ?? '';
    _colorController.text = bike.color ?? '';
    _frameSizeController.text = bike.frameSize ?? '';
    _wheelSizeController.text = bike.wheelSize ?? '';
    _frontHubSpacingController.text = bike.frontHubSpacingMm?.toString() ?? '';
    _rearHubSpacingController.text = bike.rearHubSpacingMm?.toString() ?? '';
    final spokeCountText = bike.spokeCount?.toString() ?? '';
    _frontSpokeHolesController.text = spokeCountText;
    _rearSpokeHolesController.text = spokeCountText;
    _notesController.text = bike.notes ?? '';
    _selectedType = bike.bikeType ?? BikeType.mountainHardtail;
    _purchaseDate = bike.purchaseDate;
    _warrantyUntil = bike.warrantyUntil;
    _imageUrls = <String>{
      ...bike.imageUrls,
      ..._pendingUploadedImageUrls,
    }.toList();
    _applyBikeTypeDefaults();
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
      _catalogLinkExplicitlyCleared = false;
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
        _frontSpokeHolesController.text = entry.spokeCount!.toString();
        _rearSpokeHolesController.text = entry.spokeCount!.toString();
        _technicalSources['frontSpokeHoles'] = 'catalog';
        _technicalConfirmed['frontSpokeHoles'] = false;
        _technicalSources['rearSpokeHoles'] = 'catalog';
        _technicalConfirmed['rearSpokeHoles'] = false;
      }

      if (entry.brakeType != null) {
        _brakeType = entry.brakeType;
        _technicalSources['brakeType'] = 'catalog';
        _technicalConfirmed['brakeType'] = false;
      }
      if (_brakeType == 'rim') {
        _frontRotorSizeMm = null;
        _rearRotorSizeMm = null;
        _technicalSources.remove('rimBrakeFamily');
        _technicalConfirmed.remove('rimBrakeFamily');
      } else if (_isDiscBrakeType(_brakeType) &&
          entry.brakeRotorSizeFrontMm != null) {
        _clearRimBrakeFamilyTechnicalValue();
        _frontRotorSizeMm = entry.brakeRotorSizeFrontMm;
        _technicalSources['frontRotorSizeMm'] = 'catalog';
        _technicalConfirmed['frontRotorSizeMm'] = false;
      } else {
        _clearRotorSizeTechnicalValues();
        _clearRimBrakeFamilyTechnicalValue();
      }
      if (_isDiscBrakeType(_brakeType) && entry.brakeRotorSizeRearMm != null) {
        _rearRotorSizeMm = entry.brakeRotorSizeRearMm;
        _technicalSources['rearRotorSizeMm'] = 'catalog';
        _technicalConfirmed['rearRotorSizeMm'] = false;
      }
      if (entry.drivetrainConfig != null || entry.drivetrainSpeeds != null) {
        _hydrateDrivetrainState(
          configRaw: entry.drivetrainConfig,
          totalSpeeds: entry.drivetrainSpeeds,
        );
        _technicalSources['drivetrainConfig'] = 'catalog';
        _technicalConfirmed['drivetrainConfig'] = false;
        _technicalSources['drivetrainSpeeds'] = 'catalog';
        _technicalConfirmed['drivetrainSpeeds'] = false;
      }
      if (entry.freehubType != null) {
        _freehubType = entry.freehubType;
        _technicalSources['freehubType'] = 'catalog';
        _technicalConfirmed['freehubType'] = false;
      }

      _applyBikeTypeDefaults();
    });
  }

  _BikeTypeKernelDefaults _kernelDefaultsForBikeType(BikeType type) {
    switch (type) {
      case BikeType.mountain:
        return const _BikeTypeKernelDefaults(
          suspensionLayout: 'full_suspension',
        );
      case BikeType.mountainHardtail:
        return const _BikeTypeKernelDefaults(
          suspensionLayout: 'front_suspension',
          allowedSuspensionLayouts: ['front_suspension', 'rigid'],
        );
      case BikeType.road:
      case BikeType.gravel:
      case BikeType.hybrid:
      case BikeType.folding:
      case BikeType.cruiser:
      case BikeType.paseo:
        return const _BikeTypeKernelDefaults(
          suspensionLayout: 'rigid',
        );
      case BikeType.bmx:
        return const _BikeTypeKernelDefaults(
          suspensionLayout: 'rigid',
          allowedSuspensionLayouts: ['rigid'],
          drivetrainConfig: 'singlespeed',
          freehubType: 'bmx_driver',
        );
      case BikeType.electric:
      case BikeType.other:
        return const _BikeTypeKernelDefaults();
    }
  }

  bool _canReplaceBikeTypeSuggestion(String key, String currentValue) {
    if (currentValue.trim().isEmpty) return true;
    final source = _technicalSources[key];
    final confirmed = _technicalConfirmed[key] == true;
    return !confirmed && source == 'bike_type';
  }

  Map<String, String> _suspensionLayoutOptionsForBikeType(BikeType type) {
    final allowed = _kernelDefaultsForBikeType(type).allowedSuspensionLayouts;
    if (allowed == null || allowed.isEmpty) {
      return _suspensionLayoutOptions;
    }

    return Map.fromEntries(
      _suspensionLayoutOptions.entries.where(
        (entry) => allowed.contains(entry.key),
      ),
    );
  }

  bool _isSuspensionLayoutAllowedForBikeType(BikeType type, String? value) {
    if (value == null || value.trim().isEmpty) {
      return true;
    }

    final allowed = _kernelDefaultsForBikeType(type).allowedSuspensionLayouts;
    if (allowed == null || allowed.isEmpty) {
      return true;
    }

    return allowed.contains(value);
  }

  void _enforceBikeTypeTechnicalConstraints() {
    final defaults = _kernelDefaultsForBikeType(_selectedType);
    if (!_isSuspensionLayoutAllowedForBikeType(
      _selectedType,
      _suspensionLayout,
    )) {
      final fallbackValue = defaults.suspensionLayout ??
          (defaults.allowedSuspensionLayouts?.isNotEmpty == true
              ? defaults.allowedSuspensionLayouts!.first
              : null);
      _suspensionLayout = fallbackValue;
      if (fallbackValue == null) {
        _technicalSources.remove('suspensionLayout');
        _technicalConfirmed.remove('suspensionLayout');
      } else {
        _technicalSources['suspensionLayout'] = 'bike_type';
        _technicalConfirmed['suspensionLayout'] = false;
      }
    }
  }

  void _applySuggestedTechnicalValue({
    required String key,
    required String? suggestedValue,
    required String currentValue,
    required ValueChanged<String?> apply,
  }) {
    final source = _technicalSources[key];
    final confirmed = _technicalConfirmed[key] == true;
    final normalizedCurrent = currentValue.trim();

    if (suggestedValue == null || suggestedValue.isEmpty) {
      if (!confirmed && source == 'bike_type' && normalizedCurrent.isNotEmpty) {
        apply(null);
        _technicalSources.remove(key);
        _technicalConfirmed.remove(key);
      }
      return;
    }

    if (_canReplaceBikeTypeSuggestion(key, normalizedCurrent)) {
      apply(suggestedValue);
      _technicalSources[key] = 'bike_type';
      _technicalConfirmed[key] = false;
    }
  }

  void _applyBikeTypeDefaults() {
    final defaults = _kernelDefaultsForBikeType(_selectedType);

    _applySuggestedTechnicalValue(
      key: 'suspensionLayout',
      suggestedValue: defaults.suspensionLayout,
      currentValue: _suspensionLayout?.trim() ?? '',
      apply: (value) => _suspensionLayout = value,
    );

    _applySuggestedDrivetrainConfig(defaults.drivetrainConfig);
    _applySuggestedTechnicalValue(
      key: 'freehubType',
      suggestedValue: defaults.freehubType,
      currentValue: _freehubType?.trim() ?? '',
      apply: (value) => _freehubType = value,
    );

    _enforceBikeTypeTechnicalConstraints();
  }

  void _clearRotorSizeTechnicalValues() {
    _frontRotorSizeMm = null;
    _rearRotorSizeMm = null;
    _technicalSources.remove('frontRotorSizeMm');
    _technicalConfirmed.remove('frontRotorSizeMm');
    _technicalSources.remove('rearRotorSizeMm');
    _technicalConfirmed.remove('rearRotorSizeMm');
  }

  void _clearRimBrakeFamilyTechnicalValue() {
    _rimBrakeFamily = null;
    _technicalSources.remove('rimBrakeFamily');
    _technicalConfirmed.remove('rimBrakeFamily');
  }

  void _handleBikeTypeChanged(BikeType value) {
    setState(() {
      _selectedType = value;
      _applyBikeTypeDefaults();
    });
  }

  void _handleBrakeTypeChanged(String? value) {
    setState(() {
      _brakeType = value;
      _markTechnicalFieldManual('brakeType');
      if (value == 'rim') {
        _clearRotorSizeTechnicalValues();
      } else if (_isDiscBrakeType(value)) {
        _clearRimBrakeFamilyTechnicalValue();
      } else {
        _clearRotorSizeTechnicalValues();
        _clearRimBrakeFamilyTechnicalValue();
      }
    });
  }

  int? _parseNullableIntText(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) return null;
    return int.tryParse(normalized);
  }

  int? _parseNullableIntValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  double? _parseNullableDoubleValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  String? _formatMeasurementSelection(dynamic value) {
    final parsedValue = _parseNullableDoubleValue(value);
    if (parsedValue == null) {
      return null;
    }

    if (parsedValue == parsedValue.roundToDouble()) {
      return parsedValue.toInt().toString();
    }

    return parsedValue.toStringAsFixed(1);
  }

  _DrivetrainBreakdown? _parseDrivetrainBreakdown({
    String? configRaw,
    int? totalSpeeds,
  }) {
    final normalized = configRaw?.trim().toLowerCase().replaceAll(' ', '');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    if (normalized == 'singlespeed' ||
        normalized == 'single_speed' ||
        normalized == 'single-speed' ||
        normalized.contains('fixie')) {
      return const _DrivetrainBreakdown(
        frontChainringCount: 1,
        rearCogCount: 1,
      );
    }

    final fullMatch = RegExp(r'^(\d+)x(\d+)$').firstMatch(normalized);
    if (fullMatch != null) {
      return _DrivetrainBreakdown(
        frontChainringCount: int.parse(fullMatch.group(1)!),
        rearCogCount: int.parse(fullMatch.group(2)!),
      );
    }

    final partialMatch = RegExp(r'^(\d+)x$').firstMatch(normalized);
    if (partialMatch != null && totalSpeeds != null) {
      final frontCount = int.parse(partialMatch.group(1)!);
      if (frontCount > 0 && totalSpeeds % frontCount == 0) {
        return _DrivetrainBreakdown(
          frontChainringCount: frontCount,
          rearCogCount: totalSpeeds ~/ frontCount,
        );
      }
    }

    return null;
  }

  void _hydrateDrivetrainState({
    String? configRaw,
    int? totalSpeeds,
  }) {
    final parsed = _parseDrivetrainBreakdown(
      configRaw: configRaw,
      totalSpeeds: totalSpeeds,
    );

    _frontChainringCount = parsed?.frontChainringCount;
    _rearCogCount = parsed?.rearCogCount;
    _legacyDrivetrainConfig = parsed == null
        ? (configRaw?.trim().isEmpty ?? true ? null : configRaw?.trim())
        : null;
    _legacyDrivetrainSpeeds = parsed == null ? totalSpeeds : null;
  }

  _DrivetrainBreakdown? get _currentDrivetrainBreakdown {
    if (_frontChainringCount == null || _rearCogCount == null) {
      return null;
    }

    return _DrivetrainBreakdown(
      frontChainringCount: _frontChainringCount!,
      rearCogCount: _rearCogCount!,
    );
  }

  String? get _effectiveDrivetrainConfig {
    return _currentDrivetrainBreakdown?.configValue ??
        (_legacyDrivetrainConfig?.trim().isEmpty ?? true
            ? null
            : _legacyDrivetrainConfig?.trim());
  }

  int? get _effectiveDrivetrainSpeeds {
    return _currentDrivetrainBreakdown?.totalSpeeds ?? _legacyDrivetrainSpeeds;
  }

  void _setDrivetrainTechnicalSource(
    String source, {
    required bool confirmed,
  }) {
    _technicalSources['drivetrainConfig'] = source;
    _technicalConfirmed['drivetrainConfig'] = confirmed;
    _technicalSources['drivetrainSpeeds'] = source;
    _technicalConfirmed['drivetrainSpeeds'] = confirmed;
  }

  void _clearDrivetrainTechnicalSource() {
    _technicalSources.remove('drivetrainConfig');
    _technicalConfirmed.remove('drivetrainConfig');
    _technicalSources.remove('drivetrainSpeeds');
    _technicalConfirmed.remove('drivetrainSpeeds');
  }

  bool _canReplaceDrivetrainSuggestion() {
    final currentConfig = _effectiveDrivetrainConfig?.trim() ?? '';
    final currentSpeeds = _effectiveDrivetrainSpeeds;
    if (currentConfig.isEmpty && currentSpeeds == null) {
      return true;
    }

    final source = _technicalSources['drivetrainConfig'] ??
        _technicalSources['drivetrainSpeeds'];
    final confirmed = _technicalConfirmed['drivetrainConfig'] == true ||
        _technicalConfirmed['drivetrainSpeeds'] == true;
    return !confirmed && source == 'bike_type';
  }

  void _applySuggestedDrivetrainConfig(String? suggestedValue) {
    if (suggestedValue == null || suggestedValue.isEmpty) {
      if (_canReplaceDrivetrainSuggestion()) {
        _frontChainringCount = null;
        _rearCogCount = null;
        _legacyDrivetrainConfig = null;
        _legacyDrivetrainSpeeds = null;
        _clearDrivetrainTechnicalSource();
      }
      return;
    }

    if (!_canReplaceDrivetrainSuggestion()) {
      return;
    }

    _hydrateDrivetrainState(configRaw: suggestedValue);
    _setDrivetrainTechnicalSource('bike_type', confirmed: false);
  }

  void _commitDrivetrainBreakdownEdit() {
    if (_currentDrivetrainBreakdown != null) {
      _legacyDrivetrainConfig = null;
      _legacyDrivetrainSpeeds = null;
      _setDrivetrainTechnicalSource('mechanic', confirmed: true);
      return;
    }

    if (_legacyDrivetrainConfig == null && _legacyDrivetrainSpeeds == null) {
      _clearDrivetrainTechnicalSource();
    }
  }

  void _handleFrontChainringCountChanged(int? value) {
    setState(() {
      _frontChainringCount = value;
      _commitDrivetrainBreakdownEdit();
    });
  }

  void _handleRearCogCountChanged(int? value) {
    setState(() {
      _rearCogCount = value;
      _commitDrivetrainBreakdownEdit();
    });
  }

  List<int> _resolvedRotorSizeOptions(int? currentValue) {
    return _resolvedIntOptions(_rotorSizeOptions, currentValue);
  }

  List<int> _resolvedIntOptions(List<int> defaults, int? currentValue) {
    final values = {
      ...defaults,
      if (currentValue != null) currentValue,
    }.toList()
      ..sort();
    return values;
  }

  int? _parseNullableWholeNumberText(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) return null;
    final numericValue = double.tryParse(normalized);
    if (numericValue == null) return null;
    return numericValue.round();
  }

  int? _deriveBikeSpokeCount() {
    final front = _parseNullableIntText(_frontSpokeHolesController.text);
    final rear = _parseNullableIntText(_rearSpokeHolesController.text);
    if (front != null && rear != null && front == rear) {
      return front;
    }
    return front ?? rear;
  }

  bool get _hasBrakeTypeSelection =>
      _brakeType != null && _brakeType!.trim().isNotEmpty;

  bool _isDiscBrakeType(String? rawValue) {
    return rawValue == 'mechanical_disc' || rawValue == 'hydraulic_disc';
  }

  bool get _showRimBrakeFamilyField => _brakeType == 'rim';

  bool get _showRotorSizeFields => _isDiscBrakeType(_brakeType);

  bool get _hasExplicitFreehubSelection =>
      _freehubType != null && _freehubType!.trim().isNotEmpty;

  bool get _hasExplicitBottomBracketSelection =>
      _bottomBracketFamily != null && _bottomBracketFamily!.trim().isNotEmpty;

  bool get _showBottomBracketShellWidthField =>
      isKnownBottomBracketFamily(_bottomBracketFamily);

  bool get _showBottomBracketShellDiameterField =>
      bottomBracketFamilyUsesShellDiameter(_bottomBracketFamily);

  bool get _showBottomBracketSpindleInterfaceField =>
      isKnownBottomBracketFamily(_bottomBracketFamily);

  Map<String, String> _resolvedLabeledOptions(
    Map<String, String> defaults,
    String? currentValue,
  ) {
    final resolved = Map<String, String>.from(defaults);
    if (currentValue != null &&
        currentValue.trim().isNotEmpty &&
        !resolved.containsKey(currentValue)) {
      resolved[currentValue] = currentValue;
    }
    return resolved;
  }

  void _clearBottomBracketTechnicalField(String key, VoidCallback clearValue) {
    clearValue();
    _technicalSources.remove(key);
    _technicalConfirmed.remove(key);
  }

  void _sanitizeBottomBracketTechnicalState() {
    final allowedShellWidthOptions =
        bottomBracketShellWidthOptionsForFamily(_bottomBracketFamily);
    final allowedShellDiameterOptions =
        bottomBracketShellDiameterOptionsForFamily(_bottomBracketFamily);
    final allowedSpindleOptions =
        bottomBracketSpindleInterfaceOptionsForFamily(_bottomBracketFamily);

    if (!_showBottomBracketShellWidthField ||
        (_bbShellWidthValue != null &&
            !allowedShellWidthOptions.containsKey(_bbShellWidthValue))) {
      _clearBottomBracketTechnicalField(
        'bbShellWidthMm',
        () => _bbShellWidthValue = null,
      );
    }

    if (!_showBottomBracketShellDiameterField ||
        (_bbShellDiameterValue != null &&
            !allowedShellDiameterOptions.containsKey(_bbShellDiameterValue))) {
      _clearBottomBracketTechnicalField(
        'bbShellDiameterMm',
        () => _bbShellDiameterValue = null,
      );
    }

    if (!_showBottomBracketSpindleInterfaceField ||
        (_spindleInterface != null &&
            !allowedSpindleOptions.containsKey(_spindleInterface))) {
      _clearBottomBracketTechnicalField(
        'spindleInterface',
        () => _spindleInterface = null,
      );
    }
  }

  String _bottomBracketKernelFooterText() {
    final familyLabel = bottomBracketFamilyLabel(_bottomBracketFamily);
    if (familyLabel == null) {
      return 'Confirma primero la familia del shell pedalier. Luego captura el ancho de caja y la interfaz real del eje para que compatibilidad no se quede en una etiqueta vacia.';
    }

    if (_showBottomBracketShellDiameterField) {
      return 'En $familyLabel el bore/caja manda. Confirma ancho, diametro del shell y la interfaz del eje en vez de tratarlo como si fuera una caja roscada generica.';
    }

    return 'En $familyLabel confirma el ancho de caja y la interfaz real del eje. Eso evita que el pedalier quede reducido a una familia demasiado amplia.';
  }

  bool get _hasAnyDrivetrainTruth {
    return _currentDrivetrainBreakdown != null ||
        (_legacyDrivetrainConfig?.trim().isNotEmpty ?? false) ||
        _legacyDrivetrainSpeeds != null;
  }

  String? _formatRimBrakeFamily(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }
    return kRimBrakeFamilyOptions[rawValue] ?? rawValue;
  }

  String _technicalKernelHint() {
    switch (_selectedType) {
      case BikeType.mountain:
        return 'La plataforma MTB doble suspension se toma como baseline. Si es hardtail, cambia el tipo para que downstream no asuma shock trasero.';
      case BikeType.mountainHardtail:
        return 'La plataforma hardtail sesga la bicicleta a suspension delantera y evita tratarla como doble suspension.';
      case BikeType.road:
      case BikeType.gravel:
      case BikeType.hybrid:
      case BikeType.folding:
      case BikeType.cruiser:
      case BikeType.paseo:
        return 'Esta familia sesga la bici a una base rigida. Confirma solo las excepciones reales.';
      case BikeType.bmx:
        return 'BMX se sesga a rigida, singlespeed y driver BMX. La transmisión se captura como platos x piñones, no como texto libre.';
      case BikeType.electric:
        return 'Electrica no simplifica la plataforma por si sola. Confirma la base fisica real antes de asumir suspension o transmision.';
      case BikeType.other:
        return 'En "Otra" captura solo el kernel base y deja el resto como desconocido hasta confirmar la plataforma real.';
    }
  }

  String? _technicalConstraintHint() {
    switch (_selectedType) {
      case BikeType.mountainHardtail:
        return 'Hardtail no puede quedar como doble suspensión. Solo se permiten rigida o suspension delantera.';
      case BikeType.bmx:
        return 'BMX se restringe a rigida y singlespeed para evitar combinaciones tecnicas imposibles en el intake base.';
      default:
        return null;
    }
  }

  String? _brakeConstraintHint() {
    if (!_hasBrakeTypeSelection) {
      return 'Las medidas de rotor quedan bloqueadas hasta confirmar si el sistema es de llanta o disco.';
    }
    if (_brakeType == 'rim') {
      final rimBrakeFamilyLabel = _formatRimBrakeFamily(_rimBrakeFamily);
      if (rimBrakeFamilyLabel == null) {
        return 'Ahora confirma qué familia de freno de llanta usa la bici: V-Brake, Cantilever, Caliper corto/largo, U-Brake u otro equivalente.';
      }
      return 'Se ocultan los rotores porque el sistema confirmado es freno de llanta ($rimBrakeFamilyLabel).';
    }
    if (!_isDiscBrakeType(_brakeType)) {
      return 'Se ocultan rotores y familia de freno de llanta porque el sistema confirmado no usa ni rotor ni zapata de llanta directa.';
    }
    return null;
  }

  String _brakeKernelFooterText() {
    if (!_hasBrakeTypeSelection) {
      return 'Primero confirma el tipo de freno. Solo los sistemas de disco habilitan medidas de rotor y solo los de llanta habilitan la familia de freno de llanta.';
    }

    if (_showRimBrakeFamilyField) {
      final rimBrakeFamilyLabel = _formatRimBrakeFamily(_rimBrakeFamily);
      if (rimBrakeFamilyLabel == null) {
        return 'Confirma la familia de freno de llanta para que el sistema no colapse V-Brake, Cantilever y Caliper de ruta en una sola categoría.';
      }
      return 'La ficha técnica ya distingue un freno de llanta $rimBrakeFamilyLabel, así que diagnóstico y servicio no deberían volver a adivinar ese sistema.';
    }

    if (!_isDiscBrakeType(_brakeType)) {
      final brakeLabel = kBikeProfileBrakeTypeOptions[_brakeType] ??
          _brakeType ??
          'desconocido';
      return 'La ficha técnica marca esta bicicleta como $brakeLabel. Por eso no se piden rotores ni familia de freno de llanta.';
    }

    return 'Los diámetros se eligen desde medidas estándar para poder enlazarlos con compatibilidad de rotor upstream.';
  }

  String _drivetrainKernelFooterText() {
    final explicitRearDriverNote = !_hasExplicitFreehubSelection
        ? ' No dejes el driver/freehub vacío: si todavía no se conoce, guárdalo explícitamente como Desconocido.'
        : (_freehubType == 'unknown'
            ? ' El driver/freehub quedó marcado explícitamente como desconocido hasta una confirmación posterior.'
            : '');

    final rearDriverNote = switch (_rearCogCount) {
      1 =>
        ' Con un solo piñón trasero, este campo se interpreta como driver o rueda libre singlespeed.',
      null =>
        ' El campo de driver trasero queda más preciso cuando confirmas cuántos piñones lleva atrás.',
      _ =>
        ' Con varios piñones traseros, este campo se interpreta como la familia de freehub del cassette.',
    };

    if (_currentDrivetrainBreakdown != null) {
      return 'La configuración y las velocidades se derivan automáticamente desde platos x piñones para mantener compatibilidad real upstream. El pedalier se confirma ahora en su propio sistema para no perderlo dentro de una transmisión genérica.$rearDriverNote$explicitRearDriverNote';
    }

    final legacyParts = <String>[];
    if (_legacyDrivetrainConfig != null &&
        _legacyDrivetrainConfig!.isNotEmpty) {
      legacyParts.add(_legacyDrivetrainConfig!);
    }
    if (_legacyDrivetrainSpeeds != null) {
      legacyParts.add('${_legacyDrivetrainSpeeds}v');
    }

    if (legacyParts.isNotEmpty) {
      return 'El perfil heredado todavía guarda ${legacyParts.join(' · ')} sin desglose canónico. Confirma platos y piñones para que compatibilidad, diagnóstico y wizard no dependan de texto libre. El pedalier queda fuera de este bloque y se valida como unidad propia.$rearDriverNote$explicitRearDriverNote';
    }

    return 'Confirma platos delanteros y piñones traseros. La multiplicación genera las velocidades totales y la configuración upstream. El pedalier se registra aparte como sistema de rodamientos propio.$rearDriverNote$explicitRearDriverNote';
  }

  String? _drivetrainKernelAttentionText() {
    final pending = <String>[];

    if (!_hasAnyDrivetrainTruth) {
      pending.add(
        'La transmisión todavía no tiene un desglose upstream usable. Si conoces platos y piñones, confírmalos aquí para derivar la configuración canónica.',
      );
    }

    if (!_hasExplicitFreehubSelection) {
      pending.add(
        'El driver/freehub trasero sigue vacío. Confírmalo ahora o márcalo como Desconocido para no perder esa ausencia de confirmación.',
      );
    }

    if (pending.isEmpty) {
      return null;
    }

    return pending.join(' ');
  }

  String? _identityMinimumValidationMessage() {
    if (_selectedBrand == null) {
      return 'Guardar rapido solo usa la identidad minima. Vuelve a Identidad y Base y selecciona una marca valida.';
    }

    if (_selectedModel == null) {
      return 'Guardar rapido solo usa la identidad minima. Vuelve a Identidad y Base y selecciona un modelo valido.';
    }

    final yearError = _yearValidationMessage(_yearController.text);
    if (yearError != null) {
      return 'Corrige el año en Identidad y Base antes de usar Guardar rapido.';
    }

    return null;
  }

  String? _yearValidationMessage(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }

    final year = int.tryParse(normalized);
    if (year == null || year < 1900 || year > DateTime.now().year + 1) {
      return 'Año inválido';
    }

    return null;
  }

  void _focusStepWithMessage(int stepIndex, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (_currentStep != stepIndex) {
      setState(() {
        _currentStep = stepIndex;
      });
      _pageController.animateToPage(
        stepIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _focusIdentityStepWithMessage(String message) {
    _focusStepWithMessage(0, message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentStep != 0) {
        return;
      }
      _formKey.currentState?.validate();
    });
  }

  void _focusTechnicalStepWithMessage(String message) {
    _focusStepWithMessage(_technicalStepIndex, message);
  }

  bool _ensureTechnicalKernelReadyForSave() {
    if (!_hasAnyDrivetrainTruth) {
      _focusTechnicalStepWithMessage(
        'Antes de guardar, revisa la Ficha Técnica y confirma la base de transmisión. Si conoces platos y piñones, ingrésalos para derivar la configuración upstream.',
      );
      return false;
    }

    if (!_hasExplicitFreehubSelection) {
      _focusTechnicalStepWithMessage(
        'Antes de guardar, confirma el driver/freehub trasero. Si aún no lo sabes, selecciónalo como Desconocido en la Ficha Técnica.',
      );
      return false;
    }

    if (!_hasExplicitBottomBracketSelection) {
      _focusTechnicalStepWithMessage(
        'Antes de guardar, confirma la familia de pedalier / BB. Si todavía no la sabes, márcala explícitamente como Desconocido en la Ficha Técnica.',
      );
      return false;
    }

    return true;
  }

  String get _rearDriverFieldLabel {
    return _rearCogCount == 1
        ? 'Driver / rueda libre'
        : 'Driver / freehub trasero';
  }

  Future<void> _loadBrands({
    bool propagateErrors = false,
    bool resetSelection = false,
  }) async {
    setState(() => _loadingBrands = true);
    try {
      final service = context.read<BikeshopService>();
      final sourceBike = _authoritativeBike ?? widget.bike;
      if (resetSelection) {
        _selectedBrand = null;
        _selectedModel = null;
        _models = [];
      }

      _brands = await service.getBikeBrands(activeOnly: true);
      if (!mounted) return;

      final sourceBrandId = sourceBike?.brandId;
      if (sourceBrandId != null &&
          !_brands.any((brand) => brand.id == sourceBrandId)) {
        final persistedBrand = await service.getBikeBrandById(sourceBrandId);
        if (!mounted) return;
        if (persistedBrand != null) {
          _brands.add(persistedBrand);
          _brands.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        }
      }

      // Existing editors resolve selections from the authoritative aggregate,
      // never from the potentially stale list-row snapshot passed by a host.
      if (sourceBike != null) {
        for (final brand in _brands) {
          final matches = sourceBike.brandId != null
              ? brand.id == sourceBike.brandId
              : sourceBike.brand != null &&
                  brand.name.toLowerCase() == sourceBike.brand!.toLowerCase();
          if (matches) {
            _selectedBrand = brand;
            break;
          }
        }

        if (_selectedBrand?.id != null) {
          await _loadModels(
            _selectedBrand!.id!,
            persistedModelId: sourceBike.modelId,
            propagateErrors: propagateErrors,
          );
          if (!mounted) return;
          for (final model in _models) {
            final matches = sourceBike.modelId != null
                ? model.id == sourceBike.modelId
                : sourceBike.model != null &&
                    model.name.toLowerCase() == sourceBike.model!.toLowerCase();
            if (matches) {
              _selectedModel = model;
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading brands: $e');
      if (propagateErrors) rethrow;
    } finally {
      if (mounted) {
        setState(() => _loadingBrands = false);
      }
    }
  }

  Future<void> _loadModels(
    String brandId, {
    String? persistedModelId,
    bool propagateErrors = false,
  }) async {
    setState(() => _loadingModels = true);
    try {
      final service = context.read<BikeshopService>();
      _models = await service.getBikeModels(brandId: brandId, activeOnly: true);
      if (persistedModelId != null &&
          !_models.any((model) => model.id == persistedModelId)) {
        final persistedModel = await service.getBikeModelById(persistedModelId);
        if (persistedModel != null && persistedModel.brandId == brandId) {
          _models.add(persistedModel);
          _models.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading models: $e');
      if (propagateErrors) rethrow;
    } finally {
      if (mounted) {
        setState(() => _loadingModels = false);
      }
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
    _frontSpokeHolesController.dispose();
    _rearSpokeHolesController.dispose();
    _notesController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _hasProfileData() {
    return _selectedCatalogBike != null ||
        _suspensionLayout != null ||
        _brakeType != null ||
        _rimBrakeFamily != null ||
        _freehubType != null ||
        _valveType != null ||
        _bottomBracketFamily != null ||
        (_bbShellWidthValue?.trim().isNotEmpty ?? false) ||
        (_bbShellDiameterValue?.trim().isNotEmpty ?? false) ||
        (_spindleInterface?.trim().isNotEmpty ?? false) ||
        _frontSpokeHolesController.text.trim().isNotEmpty ||
        _rearSpokeHolesController.text.trim().isNotEmpty ||
        _frontRotorSizeMm != null ||
        _rearRotorSizeMm != null ||
        _effectiveDrivetrainSpeeds != null ||
        (_effectiveDrivetrainConfig?.isNotEmpty ?? false) ||
        _acquisitionCondition != null ||
        _maintenanceHistory != null ||
        _primaryUse != null ||
        _usageFrequency != null ||
        _accidentHistory != null ||
        _storageCondition != null ||
        _weatherExposure != null ||
        _transportMethod != null;
  }

  BikeProfile? _buildBikeProfileForSave(
    Bike savedBike,
    String tenantId, {
    required DateTime confirmedAt,
  }) {
    if (!_hasProfileData() && _existingProfile == null) {
      return null;
    }

    const managedIntakeKeys = <String>{
      'acquisitionCondition',
      'declaredMaintenanceHistory',
      'primaryUse',
      'usageFrequency',
      'accidentHistory',
      'storageCondition',
      'weatherExposure',
      'transportMethod',
    };
    final intakeProfile = Map<String, dynamic>.from(
      _existingProfile?.intakeProfile ?? const {},
    )..removeWhere((key, _) => managedIntakeKeys.contains(key));
    intakeProfile.addAll(<String, dynamic>{
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
    });

    const managedTechnicalKeys = <String>{
      'suspensionLayout',
      'brakeType',
      'rimBrakeFamily',
      'freehubType',
      'valveType',
      'bottomBracketFamily',
      'bbShellWidthMm',
      'bb_shell_width_mm',
      'bbShellDiameterMm',
      'bb_shell_diameter_mm',
      'spindleInterface',
      'spindle_interface',
      'frontSpokeHoles',
      'rearSpokeHoles',
      'frontRotorSizeMm',
      'rearRotorSizeMm',
      'drivetrainSpeeds',
      'drivetrainConfig',
    };
    final technicalValues = Map<String, dynamic>.from(
      _existingProfile?.technicalValues ?? const {},
    )..removeWhere((key, _) => managedTechnicalKeys.contains(key));
    technicalValues.addAll(<String, dynamic>{
      if (_suspensionLayout != null) 'suspensionLayout': _suspensionLayout,
      if (_brakeType != null) 'brakeType': _brakeType,
      if (_showRimBrakeFamilyField && _rimBrakeFamily != null)
        'rimBrakeFamily': _rimBrakeFamily,
      if (_freehubType != null) 'freehubType': _freehubType,
      if (_valveType != null) 'valveType': _valveType,
      if (_bottomBracketFamily != null)
        'bottomBracketFamily': _bottomBracketFamily,
      if (_showBottomBracketShellWidthField &&
          _parseNullableDoubleValue(_bbShellWidthValue) != null)
        'bbShellWidthMm': _parseNullableDoubleValue(_bbShellWidthValue),
      if (_showBottomBracketShellDiameterField &&
          _parseNullableDoubleValue(_bbShellDiameterValue) != null)
        'bbShellDiameterMm': _parseNullableDoubleValue(_bbShellDiameterValue),
      if (_showBottomBracketSpindleInterfaceField && _spindleInterface != null)
        'spindleInterface': _spindleInterface,
      if (_frontSpokeHolesController.text.trim().isNotEmpty)
        'frontSpokeHoles': int.tryParse(_frontSpokeHolesController.text.trim()),
      if (_rearSpokeHolesController.text.trim().isNotEmpty)
        'rearSpokeHoles': int.tryParse(_rearSpokeHolesController.text.trim()),
      if (_showRotorSizeFields && _frontRotorSizeMm != null)
        'frontRotorSizeMm': _frontRotorSizeMm,
      if (_showRotorSizeFields && _rearRotorSizeMm != null)
        'rearRotorSizeMm': _rearRotorSizeMm,
      if (_effectiveDrivetrainSpeeds != null)
        'drivetrainSpeeds': _effectiveDrivetrainSpeeds,
      if (_effectiveDrivetrainConfig != null &&
          _effectiveDrivetrainConfig!.isNotEmpty)
        'drivetrainConfig': _effectiveDrivetrainConfig,
    });

    final technicalSources = Map<String, dynamic>.from(_technicalSources)
      ..removeWhere((key, _) =>
          managedTechnicalKeys.contains(key) &&
          !technicalValues.containsKey(key));
    final technicalConfirmed = Map<String, dynamic>.from(_technicalConfirmed)
      ..removeWhere((key, _) =>
          managedTechnicalKeys.contains(key) &&
          !technicalValues.containsKey(key));

    final summarySnapshot = <String, dynamic>{
      ...?_existingProfile?.summarySnapshot,
      ...BikeProfileSummaryBuilder.buildSummarySnapshot(
        bike: savedBike,
        intakeProfile: intakeProfile,
        technicalValues: technicalValues,
        lastConfirmedAt: confirmedAt,
      ),
    };

    final technicalProfile = Map<String, dynamic>.from(
      _existingProfile?.technicalProfile ?? const {},
    )
      ..['values'] = technicalValues
      ..['sources'] = technicalSources
      ..['confirmed'] = technicalConfirmed;

    return BikeProfile(
      id: _existingProfile?.id,
      tenantId: tenantId,
      bikeId: savedBike.id!,
      catalogBikeId: _catalogLinkExplicitlyCleared
          ? null
          : _selectedCatalogBike?.id ?? _existingProfile?.catalogBikeId,
      intakeProfile: intakeProfile,
      technicalProfile: technicalProfile,
      summarySnapshot: summarySnapshot,
      lastConfirmedAt: confirmedAt,
      createdAt: _existingProfile?.createdAt,
      updatedAt: _existingProfile?.updatedAt,
    );
  }

  String _operationKeyForSave(Bike bike, BikeProfile? profile) {
    final bikePayload = Map<String, dynamic>.from(bike.toJson())
      ..remove('id')
      ..remove('tenant_id')
      ..remove('customer_id')
      ..remove('created_at')
      ..remove('updated_at');
    final profileSignature = profile == null
        ? null
        : <String, dynamic>{
            'id': profile.id,
            'catalog_bike_id': profile.catalogBikeId,
            'intake_profile': profile.intakeProfile,
            'technical_profile': profile.technicalProfile,
          };
    final signature = jsonEncode(<String, dynamic>{
      'bike_id': bike.id,
      'customer_id': bike.customerId,
      'expected_bike_updated_at':
          _authoritativeBike?.updatedAt.toUtc().toIso8601String(),
      'expected_profile_updated_at':
          _existingProfile?.updatedAt.toUtc().toIso8601String(),
      'bike': bikePayload,
      'profile': profileSignature,
    });

    if (_pendingSaveOperationKey == null ||
        _pendingSaveContentSignature != signature) {
      _pendingSaveOperationKey = const Uuid().v4();
      _pendingSaveContentSignature = signature;
      _pendingSaveConfirmedAt = profile?.lastConfirmedAt;
    }
    return _pendingSaveOperationKey!;
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
        final removedUrl = _imageUrls.removeAt(index);
        _pendingUploadedImageUrls.remove(removedUrl);
      }
    });
  }

  Future<void> _saveBike({bool allowIncompleteTechnicalKernel = false}) async {
    if (_aggregateLoadBlocksEditing) {
      final message = switch (_aggregateLoadState) {
        _BikeAggregateLoadState.loading =>
          'Espera a que termine de cargar la ficha antes de guardar.',
        _BikeAggregateLoadState.conflicted =>
          'La bicicleta cambió desde que abriste el formulario. Recarga los datos antes de volver a guardar.',
        _BikeAggregateLoadState.outcomeUnknown =>
          'Primero confirma la operación pendiente; no cambies los datos mientras su resultado sea incierto.',
        _ =>
          'No se puede guardar porque la ficha no se cargó. Reintenta la carga primero.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.orange[800]),
      );
      return;
    }

    if (allowIncompleteTechnicalKernel) {
      final identityValidationMessage = _identityMinimumValidationMessage();
      if (identityValidationMessage != null) {
        _focusIdentityStepWithMessage(identityValidationMessage);
        return;
      }
    } else if (!_formKey.currentState!.validate()) {
      if (_currentStep != 0) {
        _focusIdentityStepWithMessage(
          'Antes de guardar, revisa Identidad y Base y corrige los campos obligatorios.',
        );
      }
      return;
    }

    if (!allowIncompleteTechnicalKernel &&
        !_ensureTechnicalKernelReadyForSave()) {
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

    var aggregateCommandWasSent = false;
    try {
      // Upload new images to Supabase Storage
      List<String> uploadedUrls = List.from(_imageUrls);

      if (_newImages.isNotEmpty) {
        setState(() {
          _isUploadingImage = true;
        });

        final pendingImages = List.of(_newImages);
        for (final imageData in pendingImages) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'bike_${widget.customerId}_$timestamp.jpg';

            final url = await ImageService.uploadBytes(
              bytes: imageData.bytes,
              fileName: fileName,
              bucket: 'bike-images',
              folder: widget.customerId,
            );

            if (url == null) {
              throw Exception(
                  'El servidor no confirmó la foto ${imageData.name}');
            }

            uploadedUrls.add(url);
            if (mounted) {
              setState(() {
                _imageUrls.add(url);
                _pendingUploadedImageUrls.add(url);
                _newImages.remove(imageData);
              });
            }
          } catch (e) {
            debugPrint('Error uploading image: $e');
            throw Exception(
              'No se pudo guardar la foto ${imageData.name}. La bicicleta aún no fue enviada.',
            );
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

      final derivedSpokeCount = _deriveBikeSpokeCount();

      final baseBike = _authoritativeBike ?? widget.bike;
      final bike = Bike(
        id: _draftBikeId,
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
        spokeCount: derivedSpokeCount,
        factoryRimId: baseBike?.factoryRimId,
        purchaseDate: _purchaseDate,
        purchasePrice: baseBike?.purchasePrice,
        warrantyUntil: _warrantyUntil,
        qrCode: baseBike?.qrCode,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        imageUrl: baseBike?.imageUrl,
        imageUrls: uploadedUrls,
        isActive: baseBike?.isActive ?? true,
        createdAt: baseBike?.createdAt,
        updatedAt: baseBike?.updatedAt,
      );

      var profile = _buildBikeProfileForSave(
        bike,
        tenantId,
        confirmedAt: DateTime.now().toUtc(),
      );
      final operationKey = _operationKeyForSave(bike, profile);
      if (profile != null) {
        // A transport retry must resend byte-for-byte equivalent persisted
        // profile truth for the same operation key. Keep the confirmation
        // timestamp stable until this command is confirmed or the form content
        // changes and a new operation key is minted.
        profile = _buildBikeProfileForSave(
          bike,
          tenantId,
          confirmedAt: _pendingSaveConfirmedAt ?? profile.lastConfirmedAt!,
        );
      }
      _pendingSaveAllowsIncompleteTechnicalKernel =
          allowIncompleteTechnicalKernel;

      BikeAggregateSaveResult? saveResult;
      Object? saveError;
      try {
        aggregateCommandWasSent = true;
        saveResult = await bikeshopService.saveBikeAggregate(
          bike: bike,
          profile: profile,
          operationKey: operationKey,
          expectedBikeUpdatedAt: _authoritativeBike?.updatedAt,
          expectedProfileUpdatedAt: _existingProfile?.updatedAt,
        );
      } catch (e) {
        saveError = e;
        if (_isTransportAmbiguity(e)) {
          // A connection can disappear after PostgreSQL commits but before the
          // response arrives. Resolve only transport ambiguity through the
          // durable command receipt; server rejections have no committed result.
          try {
            saveResult = await bikeshopService.getBikeAggregateSaveOperation(
              operationKey,
            );
          } catch (receiptError) {
            debugPrint(
                'Could not reconcile bicycle save receipt: $receiptError');
          }
        }
      }

      if (saveResult == null) {
        throw saveError ?? Exception('No se pudo confirmar el guardado');
      }

      final savedBike = saveResult.bike;
      _authoritativeBike = savedBike;
      _existingProfile = saveResult.profile;
      _pendingUploadedImageUrls.clear();
      _pendingSaveOperationKey = null;
      _pendingSaveContentSignature = null;
      _pendingSaveConfirmedAt = null;

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
      final isConflict = _isAggregateConflict(e);
      final isOutcomeUnknown =
          aggregateCommandWasSent && _isTransportAmbiguity(e);
      setState(() {
        _isSaving = false;
        _isUploadingImage = false;
        if (isConflict) {
          _aggregateLoadState = _BikeAggregateLoadState.conflicted;
        } else if (isOutcomeUnknown) {
          _aggregateLoadState = _BikeAggregateLoadState.outcomeUnknown;
        }
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(isConflict
              ? 'Otra persona o proceso cambió esta bicicleta. El guardado fue rechazado para proteger la ficha; recarga los datos antes de intentarlo otra vez.'
              : e is PostgrestException
                  ? 'El servidor rechazó el guardado y no aplicó cambios. ${e.message}'
                  : isOutcomeUnknown
                      ? 'No se pudo confirmar el guardado. Revisa la conexión y usa Confirmar guardado; se reutilizará la misma operación sin duplicar la bicicleta.\n$e'
                      : 'No se pudo completar el guardado. $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  bool _isTransportAmbiguity(Object error) {
    return error is! PostgrestException ||
        error.code == null ||
        error.code!.isEmpty;
  }

  bool _isAggregateConflict(Object error) {
    return error is PostgrestException &&
        (error.code == '40001' ||
            error.message.contains('changed since it was loaded'));
  }

  void _retryUnknownSaveOutcome() {
    setState(() {
      _aggregateLoadState = widget.bike?.id == null
          ? _BikeAggregateLoadState.creating
          : _existingProfile == null
              ? _BikeAggregateLoadState.loadedWithoutProfile
              : _BikeAggregateLoadState.loadedWithProfile;
    });
    _saveBike(
      allowIncompleteTechnicalKernel:
          _pendingSaveAllowsIncompleteTechnicalKernel,
    );
  }

  Future<void> _confirmConflictReload() async {
    final shouldReload = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recargar datos más nuevos'),
        content: const Text(
          'Recargar reemplazará los cambios locales que todavía no se guardaron. La operación rechazada no modificó la base de datos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Conservar por ahora'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Recargar'),
          ),
        ],
      ),
    );
    if (shouldReload == true && mounted) {
      await _loadBikeAggregate();
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
          try {
            await _loadModels(
              selection.id!,
              propagateErrors: true,
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No se pudieron cargar los modelos. Revisa la conexión e intenta seleccionar la marca nuevamente. $e',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
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

  Widget _buildTechnicalKernelGroup({
    required String title,
    required String description,
    required IconData icon,
    required List<Widget> fields,
    double minItemWidth = 220,
    String? attentionText,
    String? footerText,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (attentionText != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 18,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      attentionText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildAdaptiveFields(fields, minItemWidth: minItemWidth),
          if (footerText != null) ...[
            const SizedBox(height: 12),
            Text(
              footerText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ],
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
    final currentValue = _wheelSizeController.text.trim();
    final resolvedOptions = {
      ..._wheelSizeOptions,
      if (currentValue.isNotEmpty) currentValue,
    }.toList();

    return _buildStringValueDropdown(
      value: currentValue.isEmpty ? null : currentValue,
      label: 'Aro',
      icon: Icons.tire_repair_outlined,
      options: resolvedOptions,
      onChanged: (value) {
        setState(() {
          _wheelSizeController.text = value ?? '';
        });
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
              validator: _yearValidationMessage,
            ),
          ],
          minItemWidth: 220,
        ),
        const SizedBox(height: 16),
        _buildCatalogMatchSection(),
        _buildFieldGroupHeader('Características Básicas'),
        _buildAdaptiveFields(
          [
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

  Bike _buildTechnicalPreviewBike() {
    final year = int.tryParse(_yearController.text.trim());
    final frontSpacing = _parseNullableWholeNumberText(
      _frontHubSpacingController.text,
    );
    final rearSpacing = _parseNullableWholeNumberText(
      _rearHubSpacingController.text,
    );
    final frontSpokes = _parseNullableIntText(_frontSpokeHolesController.text);
    final rearSpokes = _parseNullableIntText(_rearSpokeHolesController.text);
    final resolvedSpokeCount =
        frontSpokes != null && rearSpokes != null && frontSpokes == rearSpokes
            ? frontSpokes
            : widget.bike?.spokeCount;

    return Bike(
      id: widget.bike?.id,
      tenantId: widget.bike?.tenantId ?? '',
      customerId: widget.customerId,
      brandId: _selectedBrand?.id ?? widget.bike?.brandId,
      modelId: _selectedModel?.id ?? widget.bike?.modelId,
      brand: _selectedBrand?.name ?? widget.bike?.brand,
      model: _selectedModel?.name ?? widget.bike?.model,
      year: year ?? widget.bike?.year,
      serialNumber: _serialNumberController.text.trim().isEmpty
          ? widget.bike?.serialNumber
          : _serialNumberController.text.trim(),
      color: _colorController.text.trim().isEmpty
          ? widget.bike?.color
          : _colorController.text.trim(),
      frameSize: _frameSizeController.text.trim().isEmpty
          ? widget.bike?.frameSize
          : _frameSizeController.text.trim(),
      wheelSize: _wheelSizeController.text.trim().isEmpty
          ? widget.bike?.wheelSize
          : _wheelSizeController.text.trim(),
      bikeType: _selectedType,
      frontHubSpacingMm:
          frontSpacing?.toDouble() ?? widget.bike?.frontHubSpacingMm,
      rearHubSpacingMm:
          rearSpacing?.toDouble() ?? widget.bike?.rearHubSpacingMm,
      spokeCount: resolvedSpokeCount,
      imageUrl: widget.bike?.imageUrl,
      imageUrls: widget.bike?.imageUrls ?? const [],
    );
  }

  BikeSystemOverallStatus _statusFromCompleteness({
    required int knownCount,
    required int totalCount,
  }) {
    if (knownCount <= 0) {
      return BikeSystemOverallStatus.critical;
    }
    if (knownCount < totalCount) {
      return BikeSystemOverallStatus.attention;
    }
    return BikeSystemOverallStatus.ok;
  }

  BikeSystemOverallStatus _technicalBrakeSystemStatus({
    required bool isFront,
  }) {
    final brakeTypeKnown = _brakeType != null && _brakeType!.isNotEmpty;
    final rimFamilyResolved = _brakeType != 'rim' ||
        (_rimBrakeFamily != null &&
            _rimBrakeFamily!.isNotEmpty &&
            _rimBrakeFamily != 'unknown');
    final rotorResolved = !_isDiscBrakeType(_brakeType) ||
        (isFront ? _frontRotorSizeMm != null : _rearRotorSizeMm != null);

    final knownCount = [brakeTypeKnown, rimFamilyResolved, rotorResolved]
        .where((value) => value)
        .length;

    return _statusFromCompleteness(knownCount: knownCount, totalCount: 3);
  }

  BikeSystemOverallStatus _technicalSystemStatus(String systemKey) {
    switch (systemKey) {
      case 'cockpit':
        return BikeSystemOverallStatus.unknown;
      case 'suspension':
        return _statusFromCompleteness(
          knownCount:
              (_suspensionLayout != null && _suspensionLayout!.isNotEmpty)
                  ? 1
                  : 0,
          totalCount: 1,
        );
      case 'front_brake':
        return _technicalBrakeSystemStatus(isFront: true);
      case 'rear_brake':
        return _technicalBrakeSystemStatus(isFront: false);
      case 'front_wheel':
        final knownCount = [
          _wheelSizeController.text.trim().isNotEmpty,
          _parseNullableWholeNumberText(_frontHubSpacingController.text) !=
              null,
          _parseNullableIntText(_frontSpokeHolesController.text) != null,
          _valveType != null && _valveType!.isNotEmpty,
        ].where((value) => value).length;
        return _statusFromCompleteness(knownCount: knownCount, totalCount: 4);
      case 'drivetrain':
        final knownCount = [
          _effectiveDrivetrainConfig != null &&
              _effectiveDrivetrainConfig!.isNotEmpty,
          _effectiveDrivetrainSpeeds != null,
          _freehubType != null && _freehubType!.isNotEmpty,
        ].where((value) => value).length;
        return _statusFromCompleteness(knownCount: knownCount, totalCount: 3);
      case 'bottom_bracket':
        final knownCount = [
          _bottomBracketFamily != null && _bottomBracketFamily!.isNotEmpty,
          !_showBottomBracketShellWidthField ||
              (_bbShellWidthValue != null && _bbShellWidthValue!.isNotEmpty),
          !_showBottomBracketShellDiameterField ||
              (_bbShellDiameterValue != null &&
                  _bbShellDiameterValue!.isNotEmpty),
          !_showBottomBracketSpindleInterfaceField ||
              (_spindleInterface != null && _spindleInterface!.isNotEmpty),
        ].where((value) => value).length;
        final totalCount = 1 +
            (_showBottomBracketShellWidthField ? 1 : 0) +
            (_showBottomBracketShellDiameterField ? 1 : 0) +
            (_showBottomBracketSpindleInterfaceField ? 1 : 0);
        return _statusFromCompleteness(
          knownCount: knownCount,
          totalCount: totalCount,
        );
      case 'rear_wheel':
        final knownCount = [
          _wheelSizeController.text.trim().isNotEmpty,
          _parseNullableWholeNumberText(_rearHubSpacingController.text) != null,
          _parseNullableIntText(_rearSpokeHolesController.text) != null,
          _valveType != null && _valveType!.isNotEmpty,
        ].where((value) => value).length;
        return _statusFromCompleteness(knownCount: knownCount, totalCount: 4);
      case 'wheels':
        final knownCount = [
          _wheelSizeController.text.trim().isNotEmpty,
          _parseNullableWholeNumberText(_frontHubSpacingController.text) !=
              null,
          _parseNullableWholeNumberText(_rearHubSpacingController.text) != null,
          _parseNullableIntText(_frontSpokeHolesController.text) != null,
          _parseNullableIntText(_rearSpokeHolesController.text) != null,
          _valveType != null && _valveType!.isNotEmpty,
        ].where((value) => value).length;
        return _statusFromCompleteness(knownCount: knownCount, totalCount: 6);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  String _activeTechnicalSystemKey() {
    final selected = _selectedTechnicalSystemKey;
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    const preferredOrder = <String>[
      'suspension',
      'front_brake',
      'front_wheel',
      'drivetrain',
      'bottom_bracket',
      'rear_wheel',
      'rear_brake',
      'cockpit',
    ];

    for (final key in preferredOrder) {
      if (_technicalSystemStatus(key) != BikeSystemOverallStatus.ok) {
        return key;
      }
    }

    return 'drivetrain';
  }

  Widget _buildTechnicalSchemaNavigator(
    ThemeData theme, {
    required String activeSystemKey,
  }) {
    final previewBike = _buildTechnicalPreviewBike();
    final activeSpec = bikeSystemControllerSpecFor(activeSystemKey);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapa técnico upstream',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'La misma navegación visual del diagnóstico ahora guía la ficha técnica upstream. Aquí eliges el sistema y completas la verdad duradera de la bici, no un hallazgo de una visita puntual.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1,
            child: BikeSystemController(
              bike: previewBike,
              entries: kBikeSystemControllerSpecs
                  .map(
                    (spec) => BikeSystemControllerEntry(
                      spec: spec,
                      status: _technicalSystemStatus(spec.systemKey),
                    ),
                  )
                  .toList(growable: false),
              selectedSystemKey: activeSystemKey,
              onSystemSelected: (systemKey) {
                setState(() {
                  _selectedTechnicalSystemKey = systemKey;
                });
              },
              idleHintText:
                  'Haz clic en un sistema para editar su verdad upstream.',
              selectedHintText:
                  'La vista expandida usa el mismo backbone visual del taller.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_bike_outlined,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedType.displayName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_wheelSizeController.text.trim().isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle_outlined,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Aro ${_wheelSizeController.text.trim()}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_brakeType != null && _brakeType!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.disc_full,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Freno ${_formatBrakeSystemDetail(_brakeType, _rimBrakeFamily)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (activeSpec != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        activeSpec.icon,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Sistema activo: ${activeSpec.label}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalPlaceholderCard(
    ThemeData theme, {
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBrakeSystemDetail(String? brakeType, String? rimBrakeFamily) {
    if (brakeType == null || brakeType.isEmpty) {
      return 'sin confirmar';
    }

    if (brakeType == 'rim') {
      final rimLabel = rimBrakeFamily == null || rimBrakeFamily.isEmpty
          ? null
          : kRimBrakeFamilyOptions[rimBrakeFamily] ?? rimBrakeFamily;
      if (rimLabel != null && rimLabel.isNotEmpty) {
        return 'de llanta ($rimLabel)';
      }
    }

    return kBikeProfileBrakeTypeOptions[brakeType] ?? brakeType;
  }

  String _bikePreviewTitle(bool isEditing) {
    if (_selectedCatalogBike != null) {
      return _selectedCatalogBike!.shortName;
    }

    final identityParts = <String>[
      if (_selectedBrand?.name.isNotEmpty == true) _selectedBrand!.name,
      if (_selectedModel?.name.isNotEmpty == true) _selectedModel!.name,
    ];

    if (identityParts.isNotEmpty) {
      return identityParts.join(' ');
    }

    return isEditing ? 'Editar bicicleta' : 'Nueva bicicleta';
  }

  List<Bike> _bikePickerOptions() {
    final unique = <String, Bike>{};
    final currentBike = widget.bike;
    if (currentBike?.id != null && currentBike!.id!.isNotEmpty) {
      unique[currentBike.id!] = currentBike;
    }

    for (final bike in widget.bikePickerOptions) {
      final id = bike.id;
      if (id == null || id.isEmpty) continue;
      unique[id] = bike;
    }

    final options = unique.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    if (currentBike?.id != null && currentBike!.id!.isNotEmpty) {
      final currentIndex =
          options.indexWhere((bike) => bike.id == currentBike.id);
      if (currentIndex > 0) {
        final current = options.removeAt(currentIndex);
        options.insert(0, current);
      }
    }
    return options;
  }

  String _bikePickerSubtitle(Bike bike) {
    final details = <String>[];
    if (bike.serialNumber != null && bike.serialNumber!.trim().isNotEmpty) {
      details.add('Serie ${bike.serialNumber!.trim()}');
    }
    if (bike.color != null && bike.color!.trim().isNotEmpty) {
      details.add(bike.color!.trim());
    }
    if (bike.year != null) {
      details.add(bike.year.toString());
    }
    return details.join(' · ');
  }

  Future<void> _handleBikePickerChanged(String? bikeId) async {
    final onBikePickerSelected = widget.onBikePickerSelected;
    final currentBikeId = widget.bike?.id;
    if (bikeId == null ||
        bikeId.isEmpty ||
        bikeId == currentBikeId ||
        onBikePickerSelected == null) {
      return;
    }

    Bike? selectedBike;
    for (final bike in _bikePickerOptions()) {
      if (bike.id == bikeId) {
        selectedBike = bike;
        break;
      }
    }
    if (selectedBike == null) return;
    final confirmedBike = selectedBike;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Deseas cambiar la bicicleta para este trabajo?'),
        content: Text(
          'El trabajo quedará vinculado a ${confirmedBike.displayName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isChangingJobBike = true);
    try {
      final changed = await onBikePickerSelected(confirmedBike);
      if (!mounted) return;
      if (changed) {
        Navigator.of(context).pop(confirmedBike);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cambiar bicicleta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isChangingJobBike = false);
      }
    }
  }

  Widget _buildBikePreviewTitleControl(
    ThemeData theme, {
    required bool isEditing,
  }) {
    final pickerOptions = _bikePickerOptions();
    final canPickBike = widget.onBikePickerSelected != null &&
        widget.bike?.id != null &&
        pickerOptions.length > 1;

    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      height: 1.05,
    );

    if (!canPickBike) {
      return Text(
        _bikePreviewTitle(isEditing),
        style: titleStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: widget.bike!.id,
        isExpanded: true,
        borderRadius: BorderRadius.circular(12),
        icon: _isChangingJobBike
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        selectedItemBuilder: (context) => pickerOptions
            .map(
              (bike) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  bike.displayName,
                  style: titleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        items: pickerOptions.map((bike) {
          final subtitle = _bikePickerSubtitle(bike);
          return DropdownMenuItem<String>(
            value: bike.id,
            child: Row(
              children: [
                const Icon(Icons.pedal_bike, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bike.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: _isChangingJobBike ? null : _handleBikePickerChanged,
      ),
    );
  }

  String _bikePreviewSubtitle({required bool showTechnicalControls}) {
    if (showTechnicalControls) {
      final activeSpec =
          bikeSystemControllerSpecFor(_activeTechnicalSystemKey());
      final systemLabel = activeSpec?.label ?? 'ficha técnica';
      return 'Usa el mapa para editar $systemLabel sin abandonar la vista general de la bici.';
    }

    if (_selectedCatalogBike != null) {
      return 'Vista previa del modelo seleccionado en el catálogo compartido.';
    }

    return 'Vista previa visual. Los controles técnicos aparecen cuando abres Ficha Técnica.';
  }

  Uint8List? _resolvedPreviewImageBytes() {
    if (_newImages.isEmpty) {
      return null;
    }
    return _newImages.first.bytes;
  }

  String? _resolvedPreviewImageUrl() {
    if (_imageUrls.isNotEmpty) {
      return _imageUrls.first;
    }
    if (widget.bike?.imageUrl != null && widget.bike!.imageUrl!.isNotEmpty) {
      return widget.bike!.imageUrl;
    }
    return _selectedCatalogBike?.imageUrl;
  }

  Widget _buildBikeTypePreviewDropdown() {
    return DropdownButtonFormField<BikeType>(
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
          _handleBikeTypeChanged(value);
        }
      },
    );
  }

  Widget _buildStaticBikePreviewSurface(ThemeData theme) {
    final previewBike = _buildTechnicalPreviewBike();
    final previewImageBytes = _resolvedPreviewImageBytes();
    final previewImageUrl = _resolvedPreviewImageUrl();
    final variant = resolveBikeDiagramVariant(bike: previewBike);

    Widget buildScaledPreview(Widget child, {double scale = 1.18}) {
      return ClipRect(
        child: Center(
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: previewImageBytes != null
                  ? buildScaledPreview(
                      Image.memory(
                        previewImageBytes,
                        fit: BoxFit.contain,
                      ),
                      scale: 1.2,
                    )
                  : previewImageUrl != null && previewImageUrl.isNotEmpty
                      ? buildScaledPreview(
                          Image.network(
                            previewImageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                BikeDiagramIllustration(variant: variant),
                          ),
                          scale: 1.2,
                        )
                      : buildScaledPreview(
                          BikeDiagramIllustration(variant: variant),
                          scale: 1.18,
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBikePreviewPane(
    ThemeData theme, {
    required bool isEditing,
    required bool showTechnicalControls,
  }) {
    final activeSpec = bikeSystemControllerSpecFor(_activeTechnicalSystemKey());

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBikePreviewTitleControl(
            theme,
            isEditing: isEditing,
          ),
          const SizedBox(height: 8),
          Text(
            _bikePreviewSubtitle(showTechnicalControls: showTechnicalControls),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          _buildBikeTypePreviewDropdown(),
          const SizedBox(height: 18),
          Expanded(
            child: showTechnicalControls
                ? SingleChildScrollView(
                    child: _buildTechnicalSchemaNavigator(
                      theme,
                      activeSystemKey: _activeTechnicalSystemKey(),
                    ),
                  )
                : _buildStaticBikePreviewSurface(theme),
          ),
          if (showTechnicalControls && activeSpec != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    activeSpec.icon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sistema activo: ${activeSpec.label}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTechnicalSection({bool showInlineNavigator = true}) {
    final theme = Theme.of(context);
    final suspensionField = _buildCodeDropdown(
      value: _suspensionLayout,
      label: 'Layout de suspension',
      options: _suspensionLayoutOptionsForBikeType(_selectedType),
      icon: Icons.timeline_outlined,
      onChanged: (value) {
        setState(() {
          _suspensionLayout = value;
          _markTechnicalFieldManual('suspensionLayout');
        });
      },
    );

    final brakeTypeField = _buildCodeDropdown(
      value: _brakeType,
      label: 'Tipo de freno',
      options: kBikeProfileBrakeTypeOptions,
      icon: Icons.disc_full,
      onChanged: _handleBrakeTypeChanged,
    );

    final rimBrakeFamilyField = _buildCodeDropdown(
      value: _rimBrakeFamily,
      label: 'Familia freno de llanta',
      options: kRimBrakeFamilyOptions,
      icon: Icons.settings_input_component_outlined,
      onChanged: (value) {
        setState(() {
          _rimBrakeFamily = value;
          _markTechnicalFieldManual('rimBrakeFamily');
        });
      },
    );

    final frontRotorField = _buildIntDropdown(
      value: _frontRotorSizeMm,
      label: 'Rotor delantero',
      icon: Icons.radio_button_checked,
      unit: 'mm',
      options: _resolvedRotorSizeOptions(_frontRotorSizeMm),
      onChanged: (value) {
        setState(() {
          _frontRotorSizeMm = value;
          _markTechnicalFieldManual('frontRotorSizeMm');
        });
      },
    );

    final rearRotorField = _buildIntDropdown(
      value: _rearRotorSizeMm,
      label: 'Rotor trasero',
      icon: Icons.radio_button_checked,
      unit: 'mm',
      options: _resolvedRotorSizeOptions(_rearRotorSizeMm),
      onChanged: (value) {
        setState(() {
          _rearRotorSizeMm = value;
          _markTechnicalFieldManual('rearRotorSizeMm');
        });
      },
    );

    final frontChainringField = _buildIntDropdown(
      value: _frontChainringCount,
      label: 'Platos delanteros',
      icon: Icons.tune_outlined,
      options: _frontChainringCountOptions,
      onChanged: _handleFrontChainringCountChanged,
    );

    final rearCogField = _buildIntDropdown(
      value: _rearCogCount,
      label: 'Piñones traseros',
      icon: Icons.linear_scale_outlined,
      options: _rearCogCountOptions,
      onChanged: _handleRearCogCountChanged,
    );

    final drivetrainSpeedsField = _buildDerivedTechnicalField(
      label: 'Velocidades totales',
      icon: Icons.speed_outlined,
      value: _effectiveDrivetrainSpeeds != null
          ? '${_effectiveDrivetrainSpeeds}v'
          : 'Pendiente',
      supportingText: _currentDrivetrainBreakdown != null
          ? 'Resultado de $_frontChainringCount × $_rearCogCount.'
          : (_legacyDrivetrainSpeeds != null
              ? 'Valor heredado. Confirma ambos selectores para recalcularlo.'
              : 'Se calcula automáticamente desde el desglose delantero y trasero.'),
    );

    final drivetrainConfigField = _buildDerivedTechnicalField(
      label: 'Configuración derivada',
      icon: Icons.settings_input_component_outlined,
      value: _effectiveDrivetrainConfig ?? 'Pendiente',
      supportingText: _currentDrivetrainBreakdown != null
          ? 'Se genera automáticamente desde platos x piñones.'
          : (_legacyDrivetrainConfig != null &&
                  _legacyDrivetrainConfig!.isNotEmpty
              ? 'Valor heredado. Confirma ambos selectores para reemplazarlo.'
              : 'Se calculará cuando confirmes ambos selectores.'),
    );

    final freehubField = _buildCodeDropdown(
      value: _freehubType,
      label: _rearDriverFieldLabel,
      options: kDrivetrainFreehubTypeOptions,
      icon: Icons.hub_outlined,
      onChanged: (value) {
        setState(() {
          _freehubType = value;
          _markTechnicalFieldManual('freehubType');
        });
      },
    );

    final bottomBracketField = _buildCodeDropdown(
      value: _bottomBracketFamily,
      label: 'Familia pedalier / BB',
      options: kBottomBracketFamilyOptions,
      icon: Icons.settings_input_component_outlined,
      onChanged: (value) {
        setState(() {
          _bottomBracketFamily = canonicalBottomBracketFamilyValue(value);
          _markTechnicalFieldManual('bottomBracketFamily');
          _sanitizeBottomBracketTechnicalState();
        });
      },
    );

    final bottomBracketShellWidthField = _buildCodeDropdown(
      value: _bbShellWidthValue,
      label: 'Ancho caja pedalier',
      options: _resolvedLabeledOptions(
        bottomBracketShellWidthOptionsForFamily(_bottomBracketFamily),
        _bbShellWidthValue,
      ),
      icon: Icons.straighten_outlined,
      onChanged: (value) {
        setState(() {
          _bbShellWidthValue = value;
          _markTechnicalFieldManual('bbShellWidthMm');
        });
      },
    );

    final bottomBracketShellDiameterField = _buildCodeDropdown(
      value: _bbShellDiameterValue,
      label: 'Diametro shell / bore',
      options: _resolvedLabeledOptions(
        bottomBracketShellDiameterOptionsForFamily(_bottomBracketFamily),
        _bbShellDiameterValue,
      ),
      icon: Icons.donut_large_outlined,
      onChanged: (value) {
        setState(() {
          _bbShellDiameterValue = value;
          _markTechnicalFieldManual('bbShellDiameterMm');
        });
      },
    );

    final spindleInterfaceField = _buildCodeDropdown(
      value: _spindleInterface,
      label: 'Interfaz del eje',
      options: _resolvedLabeledOptions(
        bottomBracketSpindleInterfaceOptionsForFamily(_bottomBracketFamily),
        _spindleInterface,
      ),
      icon: Icons.settings_ethernet_outlined,
      onChanged: (value) {
        setState(() {
          _spindleInterface =
              canonicalBottomBracketSpindleInterfaceValue(value);
          _markTechnicalFieldManual('spindleInterface');
        });
      },
    );

    final frontHubSpacingField = _buildIntDropdown(
      value: _parseNullableWholeNumberText(_frontHubSpacingController.text),
      label: 'Espaciado maza delantera',
      icon: Icons.swap_horiz_outlined,
      unit: 'mm',
      options: _resolvedIntOptions(
        _frontHubSpacingOptions,
        _parseNullableWholeNumberText(_frontHubSpacingController.text),
      ),
      onChanged: (value) {
        setState(() {
          _frontHubSpacingController.text = value?.toString() ?? '';
        });
      },
    );

    final rearHubSpacingField = _buildIntDropdown(
      value: _parseNullableWholeNumberText(_rearHubSpacingController.text),
      label: 'Espaciado maza trasera',
      icon: Icons.swap_horiz_outlined,
      unit: 'mm',
      options: _resolvedIntOptions(
        _rearHubSpacingOptions,
        _parseNullableWholeNumberText(_rearHubSpacingController.text),
      ),
      onChanged: (value) {
        setState(() {
          _rearHubSpacingController.text = value?.toString() ?? '';
        });
      },
    );

    final frontSpokeHolesField = _buildIntDropdown(
      value: _parseNullableIntText(_frontSpokeHolesController.text),
      label: 'Rayos delanteros',
      icon: Icons.blur_on_outlined,
      options: _resolvedIntOptions(
        _spokeHoleOptions,
        _parseNullableIntText(_frontSpokeHolesController.text),
      ),
      onChanged: (value) {
        setState(() {
          _frontSpokeHolesController.text = value?.toString() ?? '';
          _markTechnicalFieldManual('frontSpokeHoles');
        });
      },
    );

    final rearSpokeHolesField = _buildIntDropdown(
      value: _parseNullableIntText(_rearSpokeHolesController.text),
      label: 'Rayos traseros',
      icon: Icons.blur_on_outlined,
      options: _resolvedIntOptions(
        _spokeHoleOptions,
        _parseNullableIntText(_rearSpokeHolesController.text),
      ),
      onChanged: (value) {
        setState(() {
          _rearSpokeHolesController.text = value?.toString() ?? '';
          _markTechnicalFieldManual('rearSpokeHoles');
        });
      },
    );

    final valveTypeField = _buildCodeDropdown(
      value: _valveType,
      label: 'Tipo de valvula',
      options: _valveTypeOptions,
      icon: Icons.radio_button_checked,
      onChanged: (value) {
        setState(() {
          _valveType = value;
          _markTechnicalFieldManual('valveType');
        });
      },
    );

    final activeSystemKey = _activeTechnicalSystemKey();

    final activeSystemCard = switch (activeSystemKey) {
      'suspension' => _buildTechnicalKernelGroup(
          title: 'Suspensión',
          description:
              'Base estructural que define qué componentes y diagnósticos tienen sentido downstream.',
          icon: Icons.timeline_outlined,
          fields: [suspensionField],
          minItemWidth: 260,
          footerText: _technicalConstraintHint(),
        ),
      'front_brake' => _buildTechnicalKernelGroup(
          title: 'Freno delantero',
          description:
              'La plataforma/familia del freno es verdad upstream compartida. Este panel además fija el rotor delantero cuando aplica.',
          icon: Icons.radio_button_checked,
          fields: [
            brakeTypeField,
            if (_showRimBrakeFamilyField) rimBrakeFamilyField,
            if (_showRotorSizeFields) frontRotorField,
          ],
          minItemWidth: 220,
          footerText: _brakeKernelFooterText(),
        ),
      'rear_brake' => _buildTechnicalKernelGroup(
          title: 'Freno trasero',
          description:
              'La plataforma/familia del freno es verdad upstream compartida. Este panel además fija el rotor trasero cuando aplica.',
          icon: Icons.adjust,
          fields: [
            brakeTypeField,
            if (_showRimBrakeFamilyField) rimBrakeFamilyField,
            if (_showRotorSizeFields) rearRotorField,
          ],
          minItemWidth: 220,
          footerText: _brakeKernelFooterText(),
        ),
      'drivetrain' => _buildTechnicalKernelGroup(
          title: 'Transmisión',
          description:
              'Núcleo de compatibilidad para servicio de drivetrain, repuestos y futuros wizards guiados. La configuración se deriva desde el desglose delantero/trasero y el pedalier ya no queda escondido aquí.',
          icon: Icons.settings_input_component_outlined,
          attentionText: _drivetrainKernelAttentionText(),
          fields: [
            frontChainringField,
            rearCogField,
            drivetrainSpeedsField,
            drivetrainConfigField,
            freehubField,
          ],
          minItemWidth: 220,
          footerText: _drivetrainKernelFooterText(),
        ),
      'front_wheel' => _buildTechnicalKernelGroup(
          title: 'Rueda delantera',
          description:
              'Unidad delantera de ruedas y mazas. Aquí viven el ancho de maza, el rayado y el mismo baseline compartido de aro/válvula que downstream reutiliza.',
          icon: Icons.tire_repair_outlined,
          fields: [
            _buildWheelSizeField(),
            frontHubSpacingField,
            frontSpokeHolesField,
            valveTypeField,
          ],
          minItemWidth: 220,
          footerText:
              'Aro y válvula siguen siendo verdad upstream compartida del wheelset, pero la maza y el rayado delantero ya no deben mezclarse con la unidad trasera.',
        ),
      'bottom_bracket' => _buildTechnicalKernelGroup(
          title: 'Pedalier / BB',
          description:
              'Los rodamientos y el estándar del eje pedalier son una unidad propia del backbone. No deben perderse como un detalle secundario de transmisión.',
          icon: Icons.hub_outlined,
          fields: [
            bottomBracketField,
            if (_showBottomBracketShellWidthField) bottomBracketShellWidthField,
            if (_showBottomBracketShellDiameterField)
              bottomBracketShellDiameterField,
            if (_showBottomBracketSpindleInterfaceField) spindleInterfaceField,
          ],
          minItemWidth: 220,
          footerText: _bottomBracketKernelFooterText(),
        ),
      'rear_wheel' => _buildTechnicalKernelGroup(
          title: 'Rueda trasera',
          description:
              'Unidad trasera de ruedas y mazas. Aquí viven el ancho de maza, el rayado y el mismo baseline compartido de aro/válvula que downstream reutiliza.',
          icon: Icons.tire_repair_outlined,
          fields: [
            _buildWheelSizeField(),
            rearHubSpacingField,
            rearSpokeHolesField,
            valveTypeField,
          ],
          minItemWidth: 220,
          footerText:
              'Aro y válvula siguen siendo verdad upstream compartida del wheelset, pero la maza y el rayado trasero ya no deben mezclarse con la unidad delantera.',
        ),
      'wheels' => _buildTechnicalKernelGroup(
          title: 'Wheelset agregado',
          description:
              'Vista de compatibilidad heredada. Se mantiene solo como respaldo de lectura mientras el backbone migra a rueda delantera y rueda trasera como unidades explícitas.',
          icon: Icons.tire_repair_outlined,
          fields: [
            _buildWheelSizeField(),
            frontHubSpacingField,
            rearHubSpacingField,
            frontSpokeHolesField,
            rearSpokeHolesField,
            valveTypeField,
          ],
          minItemWidth: 220,
          footerText:
              'No uses esta vista agregada como destino nuevo. La navegación real del backbone ahora distingue rueda delantera y rueda trasera.',
        ),
      'cockpit' => _buildTechnicalPlaceholderCard(
          theme,
          title: 'Cockpit / dirección',
          body:
              'Headset y dirección quedan dentro de cockpit como sistema de steering, no escondidos en notas libres. El shared bike map ya los reserva aquí, pero el kernel upstream todavía no define campos obligatorios para headset, stem, handlebar o controles. Cuando esos specs pasen a ser durables, este mismo panel será el lugar correcto para capturarlos.',
        ),
      _ => _buildTechnicalPlaceholderCard(
          theme,
          title: 'Sistema sin panel',
          body:
              'Este sistema todavía no tiene una ficha técnica upstream específica en el wizard de creación.',
        ),
    };

    return _buildSectionCard(
      title: 'Línea base técnica',
      description:
          'Solo los datos que realmente ayudan a servicio, compatibilidad y seguimiento. Agrupados por los mismos sistemas que usan el perfil técnico, el diagnóstico y los wizards.',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.rule_folder_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reglas activas del tipo de bicicleta',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _technicalKernelHint(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                if (_brakeConstraintHint() != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _brakeConstraintHint()!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (showInlineNavigator) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                'En esta vista el mapa técnico queda inline. En pantallas amplias se mueve al panel lateral para que no tengas que bajar cada vez que cambias de sistema.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTechnicalSchemaNavigator(
              theme,
              activeSystemKey: activeSystemKey,
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.west_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La navegación visual de la bici quedó en el panel izquierdo. Cambia de sistema ahí y este panel se actualiza sin sacarte del contexto.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          activeSystemCard,
        ],
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
      key: ValueKey<String>(
        'code-dropdown:$label:${value ?? ''}:${options.keys.join('|')}',
      ),
      isExpanded: true,
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

  Widget _buildStringValueDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'string-dropdown:$label:${value ?? ''}:${options.join('|')}',
      ),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(option),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildIntDropdown({
    required int? value,
    required String label,
    required IconData icon,
    required List<int> options,
    required ValueChanged<int?> onChanged,
    String? unit,
  }) {
    return DropdownButtonFormField<int>(
      key: ValueKey<String>(
        'int-dropdown:$label:${value?.toString() ?? ''}:${options.join('|')}',
      ),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        suffixText: unit,
      ),
      items: options
          .map(
            (option) => DropdownMenuItem<int>(
              value: option,
              child: Text(unit == null ? '$option' : '$option $unit'),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDerivedTechnicalField({
    required String label,
    required IconData icon,
    required String value,
    String? supportingText,
  }) {
    final theme = Theme.of(context);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: value == 'Pendiente'
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          if (supportingText != null && supportingText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              supportingText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
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
                    onPressed: () => setState(() {
                      _selectedCatalogBike = null;
                      _catalogLinkExplicitlyCleared = true;
                    }),
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

  Widget _buildAggregateLoadStatus(ThemeData theme) {
    switch (_aggregateLoadState) {
      case _BikeAggregateLoadState.loading:
        return const LinearProgressIndicator();
      case _BikeAggregateLoadState.failed:
      case _BikeAggregateLoadState.conflicted:
        final isConflict =
            _aggregateLoadState == _BikeAggregateLoadState.conflicted;
        final isNewBikeReferenceFailure =
            !isConflict && widget.bike?.id == null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.errorContainer,
          child: Row(
            children: [
              Icon(
                isConflict
                    ? Icons.sync_problem_outlined
                    : Icons.cloud_off_outlined,
                size: 20,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isConflict
                      ? 'La bicicleta cambió mientras este formulario estaba abierto. El guardado fue bloqueado para no sobrescribir datos más nuevos; recarga antes de continuar.'
                      : isNewBikeReferenceFailure
                          ? 'No se pudieron cargar las marcas y modelos. El formulario queda bloqueado para no confundir una falla de conexión con listas vacías.'
                          : 'No se pudo cargar la ficha técnica. Los campos no se muestran como vacíos y el guardado queda bloqueado hasta recuperar la información.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: isConflict
                    ? _confirmConflictReload
                    : isNewBikeReferenceFailure
                        ? _loadNewBikeReferences
                        : _loadBikeAggregate,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(isConflict ? 'Recargar' : 'Reintentar'),
              ),
            ],
          ),
        );
      case _BikeAggregateLoadState.outcomeUnknown:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.tertiaryContainer,
          child: Row(
            children: [
              Icon(
                Icons.cloud_sync_outlined,
                size: 20,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La conexión se perdió durante el guardado y todavía no sabemos si el servidor alcanzó a confirmar la operación. Los campos quedan bloqueados para conservar exactamente el mismo reintento.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _retryUnknownSaveOutcome,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Confirmar guardado'),
              ),
            ],
          ),
        );
      case _BikeAggregateLoadState.loadedWithoutProfile:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Text(
            'Esta bicicleta todavía no tiene ficha técnica guardada. Al guardar se creará junto con los datos ingresados.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      case _BikeAggregateLoadState.creating:
      case _BikeAggregateLoadState.loadedWithProfile:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.bike != null;
    final theme = Theme.of(context);
    final useDesktopPreviewShell = MediaQuery.sizeOf(context).width >= 1100;

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
        'builder': () => _buildTechnicalSection(
              showInlineNavigator: !useDesktopPreviewShell,
            ),
      },
      {
        'title': 'Notas y Fotos',
        'icon': Icons.note_alt_outlined,
        'builder': () => _buildNotesAndPhotosSection(),
      },
    ];

    Widget buildStepTabs({bool desktop = false}) {
      return Container(
        height: desktop ? 72 : 64,
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
                padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 20),
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
                    if (!desktop) ...[
                      Icon(
                        step['icon'] as IconData,
                        size: 18,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      step['title'] as String,
                      style: (desktop
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleSmall)
                          ?.copyWith(
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
        final showDesktopPreviewPane = !isMobile && useDesktopPreviewShell;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDesktopPreviewPane)
              Expanded(
                flex: 4,
                child: _buildBikePreviewPane(
                  theme,
                  isEditing: isEditing,
                  showTechnicalControls: _currentStep == _technicalStepIndex,
                ),
              ),
            Expanded(
              flex: showDesktopPreviewPane ? 6 : 1,
              child: Column(
                children: [
                  if (!isMobile)
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        showDesktopPreviewPane ? 24 : 32,
                        12,
                        12,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: buildStepTabs(desktop: true)),
                          if (!widget.isEmbedded)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 6),
                              child: IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                onPressed: _aggregateLoadState ==
                                        _BikeAggregateLoadState.outcomeUnknown
                                    ? null
                                    : () {
                                        if (widget.isEmbedded) {
                                          widget.onCanceled?.call();
                                        } else {
                                          Navigator.of(context).pop();
                                        }
                                      },
                              ),
                            ),
                        ],
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
                              onPressed: _aggregateLoadState ==
                                      _BikeAggregateLoadState.outcomeUnknown
                                  ? null
                                  : () {
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
                              child: _buildBikePreviewTitleControl(
                                theme,
                                isEditing: isEditing,
                              ),
                            ),
                            buildStepTabs(desktop: false),
                          ],
                        ),
                      ],
                    ),

                  _buildAggregateLoadStatus(theme),

                  // Content Area
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? 24 : (showDesktopPreviewPane ? 24 : 40),
                        isMobile ? 24 : 20,
                        isMobile ? 24 : 36,
                        0,
                      ),
                      child: AbsorbPointer(
                        absorbing: _aggregateLoadBlocksEditing,
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
                                onPressed:
                                    _isSaving || _aggregateLoadBlocksEditing
                                        ? null
                                        : _confirmDelete,
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
                                onPressed:
                                    _isSaving || _aggregateLoadBlocksEditing
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
                                onPressed: _isSaving ||
                                        _aggregateLoadState ==
                                            _BikeAggregateLoadState
                                                .outcomeUnknown
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
                                onPressed: _isSaving ||
                                        _aggregateLoadBlocksEditing
                                    ? null
                                    : () {
                                        _saveBike(
                                          allowIncompleteTechnicalKernel: true,
                                        );
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
                                onPressed:
                                    _isSaving || _aggregateLoadBlocksEditing
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
                                onPressed:
                                    _isSaving || _aggregateLoadBlocksEditing
                                        ? null
                                        : _saveBike,
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

    return PopScope(
      canPop: _aggregateLoadState != _BikeAggregateLoadState.outcomeUnknown,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240, maxHeight: 860),
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
      ),
    );
  }
}
