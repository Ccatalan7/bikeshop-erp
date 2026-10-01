import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../modules/ai_assistant/services/ai_service.dart';
import '../../../modules/crm/models/crm_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_compatibility.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../../shared/widgets/workshop_asset_content.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../tasks/models/smart_task_service_note.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../../modules/crm/services/customer_service.dart';
import '../config/brake_canonical_data.dart';
import '../config/bottom_bracket_canonical_data.dart';
import '../config/diagnosis_field_definitions.dart';
import '../config/drivetrain_canonical_data.dart';
import '../config/service_question_contract.dart';
import '../services/bike_product_compatibility_service.dart';
import '../services/bikeshop_service.dart';
import '../services/mechanic_job_form_persistence_policy.dart';
import '../services/bike_technical_fact_patch.dart';
import '../services/job_form_lines.dart';
import '../services/part_bike_fact_change.dart';
import '../services/job_line_save.dart';
import '../services/workshop_command_notices.dart';
import '../services/job_attachments.dart';
import '../services/mechanic_job_status_transition_coordinator.dart';
import '../services/job_completion_blocked.dart';
import '../services/mechanic_job_warranty_command_coordinator.dart';
import '../services/workshop_command_outbox.dart';
import '../services/bearing_symptom_findings.dart';
import '../services/service_answer_changes.dart';
import '../services/wheel_service_facts.dart';
import '../services/service_wizard_service.dart';
import '../widgets/bikeshop_multi_select_picker_field.dart';
import '../widgets/job_line_row.dart';
import '../services/job_line_systems.dart';
import '../../inventory/services/category_service.dart';
import '../widgets/service_wizard_dialog.dart';
import '../widgets/warranty_decision_pending_notice.dart';
import '../widgets/job_completion_blocked_dialog.dart';
import '../../../shared/services/image_service.dart'; // Add ImageService import
import '../services/job_status_service.dart';
import '../models/bikeshop_models.dart';
import '../../messaging/providers/chat_provider.dart';
import '../../messaging/services/messaging_service.dart';
import '../../messaging/widgets/entity_chat_sidebar.dart';
import 'bike_form_dialog.dart';
import '../widgets/bike_diagram_illustration.dart';
import '../widgets/bike_system_controller.dart';

// ============================================================
// Per-Bike Data Container (Multi-bike support)
// ============================================================
class _BikeTabData {
  final String tabId; // Unique ID for this tab
  Bike? bike;
  String? jobBikeId; // Database ID from mechanic_job_bikes (null for new)
  String? diagnosisSheetKey;
  MechanicJobDiagnosisSheet diagnosisSheet;
  DateTime? diagnosisSheetUpdatedAt;

  // Per-bike text controllers
  final TextEditingController clientRequestController = TextEditingController();
  final TextEditingController diagnosisController = TextEditingController();
  final TextEditingController workRequestedController = TextEditingController();
  final TextEditingController technicianNotesController =
      TextEditingController();

  // Per-bike items
  final List<JobPartItem> partItems = [];

  // Per-bike flags
  bool isWarrantyWork = false;
  bool requiresApproval = false;
  bool approvedByCustomer = false;

  final bool isGeneralTab;

  _BikeTabData({
    String? tabId,
    this.bike,
    this.jobBikeId,
    this.isGeneralTab = false,
  })  : diagnosisSheet = const MechanicJobDiagnosisSheet(),
        tabId = tabId ?? DateTime.now().microsecondsSinceEpoch.toString();

  void dispose() {
    clientRequestController.dispose();
    diagnosisController.dispose();
    workRequestedController.dispose();
    technicianNotesController.dispose();
  }

  String get displayName {
    if (isGeneralTab) return 'General / Venta';
    return bike?.displayName ?? 'Nueva Bicicleta';
  }

  double get subtotal =>
      partItems.fold(0, (sum, item) => sum + item.quantity * item.unitPrice);
}

enum _JobWorkbenchTab { general, diagnosis, products }

enum _DiagnosisWorkbenchTab { narrative, structured }

enum _NarrativeDraftInsertMode { replace, append }

enum _MechanicJobFormIssueOwner { customer, general, products, costSummary }

final List<BikeSystemControllerSpec> _kStructuredDiagnosisEditableSystems =
    kBikeSystemControllerSpecs
        .where((spec) => spec.supportsStructuredDiagnosis)
        .toList(growable: false);

class _StructuredDiagnosisComponentSpec {
  final String systemKey;
  final String componentKey;
  final String label;
  final IconData icon;

  const _StructuredDiagnosisComponentSpec({
    required this.systemKey,
    required this.componentKey,
    required this.label,
    required this.icon,
  });
}

class _DiagnosisComponentSelectorStrip extends StatefulWidget {
  const _DiagnosisComponentSelectorStrip({
    super.key,
    required this.specs,
    required this.selectedComponentKey,
    required this.statusForComponent,
    required this.onSelected,
    required this.colorForStatus,
  });

  final List<_StructuredDiagnosisComponentSpec> specs;
  final String? selectedComponentKey;
  final BikeSystemOverallStatus Function(String componentKey)
      statusForComponent;
  final ValueChanged<String> onSelected;
  final Color Function(BikeSystemOverallStatus status) colorForStatus;

  @override
  State<_DiagnosisComponentSelectorStrip> createState() =>
      _DiagnosisComponentSelectorStripState();
}

class _DiagnosisComponentSelectorStripState
    extends State<_DiagnosisComponentSelectorStrip> {
  static const double _desktopControlWidth = 32;
  static const double _desktopScrollStep = 280;

  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncScrollAffordances);
    _scheduleScrollAffordanceSync();
  }

  @override
  void didUpdateWidget(covariant _DiagnosisComponentSelectorStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScrollAffordanceSync();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncScrollAffordances);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollAffordanceSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncScrollAffordances();
      }
    });
  }

  void _syncScrollAffordances() {
    if (!_scrollController.hasClients) {
      if (_canScrollLeft || _canScrollRight) {
        setState(() {
          _canScrollLeft = false;
          _canScrollRight = false;
        });
      }
      return;
    }

    final position = _scrollController.position;
    final canScrollLeft = position.pixels > 8;
    final canScrollRight = position.maxScrollExtent - position.pixels > 8;

    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }

    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  Future<void> _scrollBy(double delta) async {
    if (!_scrollController.hasClients) return;

    final target = (_scrollController.offset + delta)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();

    if ((target - _scrollController.offset).abs() < 1) {
      return;
    }

    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildDesktopScrollControl(
    ThemeData theme, {
    required bool isLeft,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final surfaceColor =
        theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.96);
    final fadeStart = theme.colorScheme.surface.withValues(alpha: 0.72);
    final fadeEnd = theme.colorScheme.surface.withValues(alpha: 0.0);

    return Positioned(
      left: isLeft ? 4 : null,
      right: isLeft ? null : 4,
      top: 0,
      bottom: 0,
      child: Container(
        width: _desktopControlWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [fadeStart, fadeEnd],
          ),
        ),
        child: Tooltip(
          message: tooltip,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            style: IconButton.styleFrom(
              backgroundColor: surfaceColor,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
              shape: const CircleBorder(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = defaultTargetPlatform;
    final isDesktop = MediaQuery.sizeOf(context).width > 720 &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleScrollAffordanceSync();
        return false;
      },
      child: Stack(
        children: [
          ClipRect(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.specs.map((spec) {
                    final status = widget.statusForComponent(spec.componentKey);
                    final isSelected =
                        spec.componentKey == widget.selectedComponentKey;
                    final tint = widget.colorForStatus(status);

                    return Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 4),
                      child: InkWell(
                        onTap: () => widget.onSelected(spec.componentKey),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 140,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.surface
                                : theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.dividerColor.withValues(alpha: 0.1),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.02),
                                blurRadius: isSelected ? 12 : 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                height: 90,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerLow
                                      .withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(18),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(18),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Image.asset(
                                      'assets/images/${spec.componentKey}_icon.png',
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Icon(
                                          spec.icon,
                                          color:
                                              theme.colorScheme.outlineVariant,
                                          size: 32,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              // Removed divider for a cleaner look
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      spec.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? theme.colorScheme.onSurface
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tint.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        status.displayName,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          if (isDesktop && _canScrollLeft)
            _buildDesktopScrollControl(
              theme,
              isLeft: true,
              icon: Icons.chevron_left,
              tooltip: 'Ver componentes anteriores',
              onPressed: () => _scrollBy(-_desktopScrollStep),
            ),
          if (isDesktop && _canScrollRight)
            _buildDesktopScrollControl(
              theme,
              isLeft: false,
              icon: Icons.chevron_right,
              tooltip: 'Ver componentes siguientes',
              onPressed: () => _scrollBy(_desktopScrollStep),
            ),
        ],
      ),
    );
  }
}

const List<_StructuredDiagnosisComponentSpec>
    _kStructuredDiagnosisComponentSpecs = [
  _StructuredDiagnosisComponentSpec(
    systemKey: 'suspension',
    componentKey: 'fork',
    label: 'Horquilla',
    icon: Icons.waves_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'suspension',
    componentKey: 'rear_shock',
    label: 'Amortiguador',
    icon: Icons.linear_scale,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_brake',
    componentKey: 'brake_pad',
    label: 'Pastillas / zapatas',
    icon: Icons.stop_circle_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_brake',
    componentKey: 'rotor',
    label: 'Rotor',
    icon: Icons.album_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_brake',
    componentKey: 'brake_pad',
    label: 'Pastillas / zapatas',
    icon: Icons.stop_circle_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_brake',
    componentKey: 'rotor',
    label: 'Rotor',
    icon: Icons.album_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'chain',
    label: 'Cadena',
    icon: Icons.link,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'cassette',
    label: 'Cassette',
    icon: Icons.album_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'chainring',
    label: 'Plato',
    icon: Icons.adjust,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'rear_derailleur',
    label: 'Cambio trasero',
    icon: Icons.alt_route_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'front_derailleur',
    label: 'Cambio delantero',
    icon: Icons.call_split_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'shifter',
    label: 'Shifter',
    icon: Icons.touch_app_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_wheel',
    componentKey: 'tire',
    label: 'Neumático',
    icon: Icons.trip_origin,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_wheel',
    componentKey: 'rim',
    label: 'Aro',
    icon: Icons.circle_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_wheel',
    componentKey: 'spokes',
    label: 'Rayos',
    icon: Icons.blur_circular_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_wheel',
    componentKey: 'hub',
    label: 'Maza',
    icon: Icons.settings_input_component_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_wheel',
    componentKey: 'tire',
    label: 'Neumático',
    icon: Icons.trip_origin,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_wheel',
    componentKey: 'rim',
    label: 'Aro',
    icon: Icons.circle_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_wheel',
    componentKey: 'spokes',
    label: 'Rayos',
    icon: Icons.blur_circular_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_wheel',
    componentKey: 'hub',
    label: 'Maza',
    icon: Icons.settings_input_component_outlined,
  ),
];

const Map<String, String> _kChainLubricationOptions = {
  'ok': 'Lubricada',
  'dry': 'Seca',
  'dirty': 'Suciedad excesiva',
  'contaminated': 'Contaminada',
};

const Map<String, String> _kDrivetrainWearConditionOptions = {
  'ok': 'Correcto',
  'attention': 'Con desgaste',
  'worn': 'Gastado',
  'replace': 'Reemplazar',
};

const Map<String, String> _kDerailleurConditionOptions = {
  'ok': 'Correcto',
  'attention': 'Requiere ajuste',
  'bent': 'Desalineado / doblado',
  'replace': 'Reemplazar',
};

const Map<String, String> _kShifterConditionOptions = {
  'ok': 'Correcto',
  'sticky': 'Pegado / duro',
  'attention': 'Impreciso',
  'replace': 'Reemplazar',
};

const Map<String, String> _kWheelTireConditionOptions = {
  'ok': 'Buen estado',
  'worn': 'Desgastada',
  'damaged': 'Danada / cortada',
  'replace': 'Reemplazar',
};

const Map<String, String> _kWheelRimConditionOptions = {
  'ok': 'Recto / sin dano',
  'attention': 'Descentrado leve',
  'bent': 'Golpeado / desviado',
  'cracked': 'Fisurado',
  'replace': 'Reemplazar',
};

const Map<String, String> _kWheelSpokeConditionOptions = {
  'ok': 'Tension pareja',
  'loose': 'Rayos sueltos',
  'uneven': 'Tension dispareja',
  'broken': 'Rayos cortados',
};

const Map<String, String> _kWheelHubBearingConditionOptions = {
  'ok': 'Gira suave',
  'rough': 'Aspero',
  'play': 'Con juego',
  'service': 'Requiere servicio',
  'replace': 'Reemplazar',
};

const Map<String, String> _kWheelTubelessStatusOptions = {
  'ok': 'Sellado correcto',
  'leaking': 'Pierde aire',
  'dry_sealant': 'Liquido seco',
  'not_applicable': 'No aplica',
};

const Map<String, String> _kBearingConditionOptions = {
  'ok': 'Gira suave',
  'rough': 'Aspero',
  'play': 'Con juego',
  'service': 'Requiere servicio',
  'replace': 'Reemplazar',
};

const Map<String, String> _kMechanicalNoiseStatusOptions = {
  'ok': 'Sin ruido anormal',
  'creaking': 'Crujido / chirrido',
  'clicking': 'Click / golpeteo',
  'knocking': 'Golpe / clunk',
  'service': 'Requiere revision',
};

const Map<String, String> _kSuspensionConditionOptions = {
  'ok': 'Funcionamiento correcto',
  'rough': 'Recorrido aspero',
  'sticky': 'Recorrido duro / pegado',
  'leaking': 'Perdida de aire / aceite',
  'play': 'Con juego',
  'service': 'Requiere servicio',
  'replace': 'Reemplazar',
};

final List<ServiceQuestionOption> _kBrakeSymptomOptions =
    serviceQuestionOptionsFromMap(kBrakeSymptomLabels);

typedef _BrakeDiagnosisSheetUpdater = void Function(
  BrakeDiagnosisSheet Function(BrakeDiagnosisSheet current) transform, {
  bool refresh,
});

typedef _WheelDiagnosisSheetUpdater = void Function(
  WheelDiagnosisSheet Function(WheelDiagnosisSheet current) transform, {
  bool refresh,
});

typedef _BottomBracketDiagnosisSheetUpdater = void Function(
  BottomBracketDiagnosisSheet Function(BottomBracketDiagnosisSheet current)
      transform, {
  bool refresh,
});

typedef _CockpitDiagnosisSheetUpdater = void Function(
  CockpitDiagnosisSheet Function(CockpitDiagnosisSheet current) transform, {
  bool refresh,
});

typedef _SuspensionDiagnosisSheetUpdater = void Function(
  SuspensionDiagnosisSheet Function(SuspensionDiagnosisSheet current)
      transform, {
  bool refresh,
});

class _DiagnosisNarrativeSource {
  const _DiagnosisNarrativeSource({
    required this.sections,
    required this.recommendationHints,
    required this.hasCriticalRisk,
  });

  final List<_DiagnosisNarrativeSection> sections;
  final List<String> recommendationHints;
  final bool hasCriticalRisk;

  bool get hasContent => sections.isNotEmpty || recommendationHints.isNotEmpty;
}

class _DiagnosisNarrativeSection {
  const _DiagnosisNarrativeSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

class _ServiceWizardDialogConfig {
  final Map<String, dynamic> initialAnswers;
  final Set<String> hiddenQuestionKeys;
  final String? helperText;
  final ServiceWizardContextSummary? contextSummary;
  final Map<String, ServiceWizardQuestionOverride> questionOverrides;
  final Set<String> diagnosisLinkedQuestionKeys;

  const _ServiceWizardDialogConfig({
    required this.initialAnswers,
    required this.hiddenQuestionKeys,
    required this.helperText,
    this.contextSummary,
    this.questionOverrides = const <String, ServiceWizardQuestionOverride>{},
    this.diagnosisLinkedQuestionKeys = const <String>{},
  });
}

@visibleForTesting
abstract final class MechanicJobResponsivePolicy {
  static bool usesCompactComposition(double viewportWidth) =>
      viewportWidth < ResponsiveViewport.desktopMin;
}

@visibleForTesting
class MechanicJobCompactWorkbenchNavigation extends StatelessWidget {
  const MechanicJobCompactWorkbenchNavigation({
    super.key,
    required this.selectedIndex,
    required this.showDiagnosis,
    required this.productsLabel,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool showDiagnosis;
  final String productsLabel;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destinations = <({int index, String label, String semanticsLabel})>[
      (index: 0, label: 'General', semanticsLabel: 'General'),
      if (showDiagnosis)
        (
          index: 1,
          label: 'Diagnóstico',
          semanticsLabel: 'Diagnóstico',
        ),
      (
        index: 2,
        label: productsLabel,
        semanticsLabel: productsLabel == 'Cobro'
            ? 'Productos y cobro'
            : 'Productos y servicios',
      ),
    ];

    return Container(
      key: const ValueKey('mechanic-job-compact-workbench-navigation'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var position = 0;
              position < destinations.length;
              position++) ...[
            if (position > 0) const SizedBox(width: 3),
            Expanded(
              child: _MechanicJobCompactWorkbenchDestination(
                index: destinations[position].index,
                label: destinations[position].label,
                semanticsLabel: destinations[position].semanticsLabel,
                selected: selectedIndex == destinations[position].index,
                onTap: onSelected,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MechanicJobCompactWorkbenchDestination extends StatelessWidget {
  const _MechanicJobCompactWorkbenchDestination({
    required this.index,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final String semanticsLabel;
  final bool selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            key: ValueKey('mechanic-job-workbench-tab-$index'),
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(9),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class MechanicJobCompactChoice {
  const MechanicJobCompactChoice({
    required this.id,
    required this.label,
    required this.icon,
    required this.statusLabel,
    required this.statusColor,
  });

  final String id;
  final String label;
  final IconData icon;
  final String statusLabel;
  final Color statusColor;
}

@visibleForTesting
class MechanicJobCompactChoiceMenu extends StatelessWidget {
  const MechanicJobCompactChoiceMenu({
    super.key,
    required this.controlLabel,
    required this.selectedId,
    required this.choices,
    required this.onSelected,
  });

  final String controlLabel;
  final String selectedId;
  final List<MechanicJobCompactChoice> choices;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = choices.firstWhere(
      (choice) => choice.id == selectedId,
      orElse: () => choices.first,
    );

    return MenuAnchor(
      menuChildren: choices
          .map(
            (choice) => MenuItemButton(
              key: ValueKey('mechanic-job-choice-${choice.id}'),
              onPressed: () => onSelected(choice.id),
              leadingIcon: Icon(choice.icon, size: 19),
              trailingIcon: Semantics(
                label: 'Estado ${choice.statusLabel}',
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: choice.statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              style: MenuItemButton.styleFrom(
                minimumSize: const Size(240, 48),
              ),
              child: Text(choice.label),
            ),
          )
          .toList(growable: false),
      builder: (context, controller, _) {
        final actionLabel = controller.isOpen ? 'Cerrar opciones' : 'Cambiar';
        return Semantics(
          button: true,
          expanded: controller.isOpen,
          label:
              '$controlLabel. ${selected.label}. Estado ${selected.statusLabel}. $actionLabel',
          child: ExcludeSemantics(
            child: OutlinedButton(
              key: ValueKey(
                'mechanic-job-compact-${controlLabel.toLowerCase()}-menu',
              ),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  Icon(selected.icon, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controlLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          selected.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: selected.statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      selected.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

@visibleForTesting
class MechanicJobDiscardDialog extends StatelessWidget {
  const MechanicJobDiscardDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      namesRoute: true,
      label: 'Confirmar descarte de cambios',
      child: AlertDialog(
        key: const ValueKey('mechanic-job-inline-discard-dialog'),
        title: const Text('¿Descartar cambios?'),
        content: const Text(
          'Los cambios de este trabajo todavía no se han guardado.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('mechanic-job-inline-discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            key: const ValueKey('mechanic-job-inline-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
  }
}

/// Responsive presentation for the bicycle context used by the canonical job
/// form. The compact disclosure changes composition only; the snapshot and every
/// command still belong to the same job-form owners used on larger surfaces.
@visibleForTesting
class MechanicJobBikeContextCard extends StatefulWidget {
  final BikeRecordSnapshot snapshot;
  final bool isLoading;
  final bool loadFailed;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenProfile;
  final VoidCallback onEditProfile;
  final String editActionLabel;

  const MechanicJobBikeContextCard({
    super.key,
    required this.snapshot,
    required this.isLoading,
    required this.loadFailed,
    required this.onRetry,
    required this.onOpenProfile,
    required this.onEditProfile,
    required this.editActionLabel,
  });

  @override
  State<MechanicJobBikeContextCard> createState() =>
      _MechanicJobBikeContextCardState();
}

class _MechanicJobBikeContextCardState
    extends State<MechanicJobBikeContextCard> {
  bool _phoneExpanded = false;

  String get _bikeIdentity =>
      widget.snapshot.profile?.identityLine ??
      BikeProfileSummaryBuilder.buildIdentityLine(widget.snapshot.bike);

  @override
  void didUpdateWidget(MechanicJobBikeContextCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIdentity =
        oldWidget.snapshot.bike.id ?? oldWidget.snapshot.identityTitle;
    final currentIdentity =
        widget.snapshot.bike.id ?? widget.snapshot.identityTitle;
    if (previousIdentity != currentIdentity) {
      _phoneExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    final theme = Theme.of(context);

    if (!isCompact) {
      return _buildExpandedCard(theme);
    }

    return Container(
      key: const ValueKey('mechanic-job-bike-context-card'),
      margin: const EdgeInsets.only(top: 16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPhoneDisclosure(theme),
          if (_phoneExpanded) ...[
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: _buildPhoneExpandedDetails(theme),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(ThemeData theme) {
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: theme.dividerColor.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildPhoneDisclosure(ThemeData theme) {
    final warnings = widget.snapshot.warnings;
    final firstException = widget.loadFailed
        ? 'No se pudo cargar la ficha técnica'
        : warnings.isEmpty
            ? null
            : warnings.first;
    final remainingWarningCount =
        widget.loadFailed || warnings.length <= 1 ? 0 : warnings.length - 1;
    final actionLabel = _phoneExpanded ? 'Ocultar contexto' : 'Ver contexto';
    final semanticsParts = <String>[
      'Contexto de la bicicleta',
      _bikeIdentity,
      if (firstException != null) firstException,
      if (remainingWarningCount > 0)
        '$remainingWarningCount advertencia adicional',
      actionLabel,
    ];

    return Semantics(
      key: const ValueKey('mechanic-job-bike-context-disclosure'),
      container: true,
      button: true,
      expanded: _phoneExpanded,
      label: semanticsParts.join('. '),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => setState(() => _phoneExpanded = !_phoneExpanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Icon(
                        Icons.summarize_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contexto de la bicicleta',
                              maxLines: 2,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _bikeIdentity,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _phoneExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    actionLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.isLoading) ...[
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(),
                ] else if (firstException != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        widget.loadFailed
                            ? Icons.cloud_off_outlined
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          firstException,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (remainingWarningCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '+$remainingWarningCount '
                          '${remainingWarningCount == 1 ? 'pendiente' : 'pendientes'}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneExpandedDetails(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProfileDetails(theme, compact: true),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.onOpenProfile != null)
              OutlinedButton.icon(
                key: const ValueKey(
                  'mechanic-job-bike-context-open-profile',
                ),
                onPressed: widget.onOpenProfile,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('Ver perfil completo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
              ),
            TextButton.icon(
              key: const ValueKey('mechanic-job-bike-context-edit-profile'),
              onPressed: widget.onEditProfile,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(widget.editActionLabel),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpandedCard(ThemeData theme) {
    return Container(
      key: const ValueKey('mechanic-job-bike-context-card'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.summarize_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contexto de la bicicleta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Tooltip(
                message: 'Ver perfil completo',
                child: IconButton(
                  onPressed: widget.onOpenProfile,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  visualDensity: VisualDensity.standard,
                  splashRadius: 18,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              TextButton.icon(
                onPressed: widget.onEditProfile,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(widget.editActionLabel),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.standard,
                  minimumSize: const Size(0, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _bikeIdentity,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _buildProfileDetails(theme, compact: false),
        ],
      ),
    );
  }

  Widget _buildProfileDetails(
    ThemeData theme, {
    required bool compact,
  }) {
    final snapshot = widget.snapshot;
    final highlights = snapshot.summaryHighlights;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isLoading)
          const LinearProgressIndicator()
        else if (widget.loadFailed)
          _buildLoadFailure(theme, compact: compact)
        else ...[
          if (!snapshot.hasStructuredProfile)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Aun no hay perfil estructurado guardado para esta bicicleta.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (highlights.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Aun no hay resumen disponible para esta bicicleta.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (highlights.isNotEmpty)
            if (compact)
              Text(
                highlights.join(' · '),
                key: const ValueKey(
                  'mechanic-job-bike-context-highlight-text',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: highlights
                    .map(
                      (line) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(line, style: theme.textTheme.bodySmall),
                      ),
                    )
                    .toList(),
              ),
        ],
        if (snapshot.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...snapshot.warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      warning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (snapshot.lastConfirmedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Ultima confirmacion: ${DateFormat('dd/MM/yyyy').format(snapshot.lastConfirmedAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoadFailure(
    ThemeData theme, {
    required bool compact,
  }) {
    final message = Text(
      'No se pudo cargar la ficha. No se tratará como vacía.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onErrorContainer,
        fontWeight: FontWeight.w600,
      ),
    );
    final retry = TextButton(
      onPressed: widget.onRetry,
      child: const Text('Reintentar'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 18,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: message),
                  ],
                ),
                Align(alignment: Alignment.centerRight, child: retry),
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(child: message),
                retry,
              ],
            ),
    );
  }
}

class MechanicJobFormPage extends StatefulWidget {
  final String? jobId; // Null for new job, ID for editing
  final String? customerId; // Pre-select customer if provided
  final String? initialBikeId; // Pre-select an active bike owned by customer
  final String?
      initialJobType; // Pre-select type: 'service'|'warranty'|'quotation'|'item_service'
  final String? initialTab; // 'general'|'diagnosis'|'products'
  final bool isEmbedded;
  final bool isInlineWorkspace;
  final VoidCallback? onSaved;
  final VoidCallback? onCanceled;

  const MechanicJobFormPage({
    super.key,
    this.jobId,
    this.customerId,
    this.initialBikeId,
    this.initialJobType,
    this.initialTab,
    this.isEmbedded = false,
    this.isInlineWorkspace = false,
    this.onSaved,
    this.onCanceled,
  }) : assert(
          !isInlineWorkspace || isEmbedded,
          'isInlineWorkspace requires isEmbedded.',
        );

  @override
  State<MechanicJobFormPage> createState() => _MechanicJobFormPageState();
}

class _MechanicJobFormPageState extends State<MechanicJobFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Column widths for parts table (same as invoice)
  static const double _colIndexWidth = 40.0;
  static const double _colQuantityWidth = 120.0;
  static const double _colPriceWidth = 130.0;
  static const double _colTotalWidth = 130.0;
  static const double _colActionsWidth = 48.0;

  // Column widths for labor table
  static const double _colDateWidth = 120.0;
  static const double _colHoursWidth = 100.0;
  static const double _colRateWidth = 120.0;

  // Form controllers (job-level)
  final _discountController = TextEditingController(text: '0');
  final _estimatedDurationController = TextEditingController();
  final _actualLaborHoursController = TextEditingController();

  // ============================================================
  // MULTI-BIKE STATE
  // ============================================================
  final List<_BikeTabData> _bikeTabs = [];
  int _selectedBikeTabIndex = 0;
  _JobWorkbenchTab _selectedWorkbenchTab = _JobWorkbenchTab.general;
  _DiagnosisWorkbenchTab _selectedDiagnosisWorkbenchTab =
      _DiagnosisWorkbenchTab.structured;
  String? _selectedStructuredDiagnosisSystemKey;
  final Map<String, String> _selectedStructuredDiagnosisComponentKeys = {};

  /// Currently selected bike tab
  _BikeTabData? get _currentBikeTab =>
      _bikeTabs.isNotEmpty && _selectedBikeTabIndex < _bikeTabs.length
          ? _bikeTabs[_selectedBikeTabIndex]
          : null;

  MechanicJobDiagnosisSheet get _currentDiagnosisSheet =>
      _currentBikeTab?.diagnosisSheet ?? const MechanicJobDiagnosisSheet();

  // Legacy single-bike state (for backward compatibility during migration)
  // TODO: Remove once multi-bike is fully implemented
  final _clientRequestController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _workSummaryController = TextEditingController();
  final _technicianNotesController = TextEditingController();

  // Form state
  Customer? _selectedCustomer;
  Bike? _selectedBike; // Legacy - now use _bikeTabs
  BikeProfile? _selectedBikeProfile;
  bool _selectedBikeProfileLoadFailed = false;
  final Map<String, BikeProfile> _pendingBikeProfileOverrides = {};
  // La ficha tal como se cargó antes de la primera promoción pendiente de cada
  // bici: es el `expected` de cada dato que se manda al servidor.
  final Map<String, BikeProfile?> _pendingBikeProfileBaselines = {};
  // Una llave por contenido pendiente: se reusa al reintentar una respuesta
  // perdida y se renueva cuando otra promoción cambia lo pendiente.
  final Map<String, String> _pendingBikeProfileOperationKeys = {};
  // La versión de cada línea del trabajo tal como el formulario la cargó (o
  // la recibió del último guardado). El guardado la manda de vuelta: si otra
  // persona tocó las líneas mientras tanto, el servidor lo rechaza en vez de
  // pisarlas (`save_mechanic_job_lines_v1`).
  final Map<String, String> _seenLineVersions = {};
  // El guardado de líneas que se envió y quedó sin respuesta. El comando
  // completo y su llave viven en la bandeja del equipo (sobreviven al cierre
  // de la app); aquí queda lo que el formulario necesita para adoptar su
  // recibo. El próximo guardado lo resuelve antes de escribir nada.
  _PendingLineSave? _pendingLineSave;
  // La cabecera tal como la mandó el servidor al cargar (o en el último
  // recibo): el valor visto de cada campo que el guardado cambia.
  Map<String, dynamic> _headerBaseline = {};
  // El id del trabajo nuevo, elegido una vez por formulario, y la llave de su
  // alta: el alta que llegó y perdió su respuesta devuelve su recibo en vez
  // de crear otro trabajo ([BikeshopService.jobCreationCommand]).
  final String _newJobId = const Uuid().v4();

  /// El trabajo nuevo de este formulario, con el recibo de su alta: desde
  /// entonces cada guardado es el de un trabajo guardado, y lo editado
  /// después del alta viaja con él (cierre del Master Schema, 2026-09-29).
  MechanicJob? _createdJob;

  /// El trabajo guardado de este formulario: el que abrió, o el nuevo cuya
  /// alta ya tiene recibo. Null mientras el alta no llegue.
  String? get _savedJobId => widget.jobId ?? _createdJob?.id;

  /// El formulario dueño de los adjuntos que sube: al cerrarse sin guardar,
  /// libera sólo los suyos (los de otro formulario abierto no).
  final String _formInstanceId = const Uuid().v4();
  WorkshopCommandScope? _imageScope;
  bool _uploadedAttachments = false;
  // Lo que el formulario mostró de los campos de la cabecera que repiten la
  // primera bici ([_headerMirror]). Un campo cuenta como editado si difiere
  // de esto, no de la cabecera: con la bici vacía y la cabecera escrita, un
  // guardado sin tocar el diagnóstico lo borraba (20 trabajos así en
  // producción al 2026-09-28), y uno ajeno se veía como conflicto (revisión
  // de Codex).
  Map<String, dynamic> _headerShown = {};
  // Cada bici del trabajo como la mandó el servidor al cargar (o en el último
  // recibo): lo visto de cada campo que el guardado cambia. Y las que el
  // formulario mostraba en sus pestañas: sólo ésas salen si se quitan; una
  // que otra persona agregó mientras tanto no se toca (segunda revisión de
  // Codex, 2026-09-28).
  final Map<String, Map<String, dynamic>> _jobBikeBaseline = {};
  final Set<String> _shownJobBikeIds = {};
  // Bicis cuya ficha no tomó lo de «Configurar» en el último guardado, con el
  // aviso: el trabajo no se guarda hasta reconfirmarlo (o quitar sus servicios
  // configurados), para que ninguna línea quede diciendo otra cosa que la
  // ficha.
  final Map<String, String> _bikeFactsAwaitingReconfirmation = {};
  // El id con que quedó guardada cada línea de mano de obra de esta sesión del
  // formulario: el siguiente guardado la actualiza en vez de crearla de nuevo
  // (y perder sus tareas).
  final Map<String, String> _laborLinePersistedIds = {};
  final Map<String, Map<String, dynamic>> _pendingServiceWizardAnswers = {};
  JobPriority _selectedPriority = JobPriority.normal;
  JobStatus _selectedStatus = JobStatus.pendiente;
  JobStatusCustom?
      _selectedCustomStatus; // Custom status from job_statuses table
  List<JobStatusCustom> _customStatuses = []; // All available custom statuses
  DateTime? _selectedDeadline;
  DateTime _selectedArrivalDate = DateTime.now(); // Arrival date (editable)
  bool _requiresApproval = false;
  TaxTreatment _taxTreatment =
      TaxTreatment.noTax; // Default: no tax (matches sales invoice)

  // Job type and subject (for non-bike jobs: warranty, quotation, item_service)
  JobType _jobType = JobType.service;
  ServiceCommercialPath _serviceCommercialPath =
      ServiceCommercialPath.budgetFirst;
  JobSubject? _selectedSubject;
  List<JobSubject> _availableSubjects = [];
  final _subjectNotesController = TextEditingController();
  final _warrantyDecisionReasonController = TextEditingController();
  WarrantyOutcome? _warrantyOutcome;
  List<MechanicJobServiceWarranty> _warrantySources = [];
  MechanicJobServiceWarranty? _selectedWarrantySource;
  MechanicJobWarrantyClaim? _warrantyClaim;
  bool _isLoadingWarrantySourceObject = false;
  String? _warrantySourceObjectError;
  int _warrantySourceSelectionEpoch = 0;
  String? _pendingWarrantyRegistrationOperationKey;
  String? _pendingWarrantyDecisionOperationKey;
  String? _pendingWarrantyDecisionFingerprint;

  /// La decisión de garantía de este trabajo que sigue en la bandeja del
  /// equipo: el panel la dice pendiente, nunca aplicada.
  ({
    WarrantyOutcome outcome,
    String? reason,
    String operationKey
  })? _pendingWarrantyDecision;
  String? _pendingStatusTransitionOperationKey;
  String? _pendingStatusTransitionFingerprint;
  final _warrantySaveCheckpoint = MechanicJobWarrantySaveCheckpoint();
  bool _isLoadingWarrantySources = false;
  String? _warrantySourcesLoadError;
  String? _warrantyClaimLoadError;
  String? _exactWarrantySourceLoadError;
  bool _warrantyClaimLoadCompleted = false;
  QuotationStatus? _quotationStatus = QuotationStatus.pending;
  DateTime? _quotationValidUntil = DateTime.now().add(const Duration(days: 30));

  bool get _isServiceBudget =>
      _jobType == JobType.service &&
      _serviceCommercialPath == ServiceCommercialPath.budgetFirst;

  bool get _isProposalWorkflow =>
      _jobType == JobType.quotation || _isServiceBudget;

  String get _proposalDocumentLabel =>
      _isServiceBudget ? 'Presupuesto' : 'Cotización';

  String get _proposalDocumentLabelLower =>
      _isServiceBudget ? 'presupuesto' : 'cotización';

  // Parts and services
  final List<JobPartItem> _partItems = [];
  final List<_JobServiceItem> _serviceItems = [];

  // Service wizard
  final _aiAssistantService = AIAssistantService();
  final _serviceWizardService = ServiceWizardService();
  final _bikeProductCompatibilityService = BikeProductCompatibilityService();
  int? _selectedServiceIndex; // Index into _currentPartItems for sidebar detail

  /// La relación única concepto + posición (`bike_fact_spec_links`) y la
  /// ficha técnica de los repuestos de las líneas: con ellas cada línea dice
  /// el cambio de ficha que propone. Nula mientras no se pudo leer.
  List<BikeFactSpecLink>? _bikeFactSpecLinks = BikeFactSpecLinks.loaded;
  final Map<String, Map<String, dynamic>> _partSpecValues = {};

  /// Lo que cada línea escribió en la ficha y la ficha todavía dice como
  /// suyo, según el servidor (`job_part_change_writers_v1`, por id de
  /// línea; una marca o varias): un neumático sólo reemplaza el BSD que
  /// escribió su propia línea (20260928110000). Vacío hasta leerlo, o si no
  /// se pudo.
  Map<String, Object> _partChangeWriters = const {};

  // Key to reset autocomplete field after adding product
  int _partAutocompleteKey = 0;
  final FocusNode _partAutocompleteFocus = FocusNode();
  final FocusNode _discountFocusNode = FocusNode();

  // Data
  List<Customer> _customers = [];
  List<Bike> _bikes = [];
  List<Product> _products = [];
  List<Product> _serviceProducts = [];
  bool _hasLoadedCustomerCatalog = false;

  // Loading states
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingSelectedBikeProfile = false;
  String? _generatingNarrativeDraftTabId;
  String? _inlineDraftBaselineFingerprint;
  bool _isInlineDiscardPromptOpen = false;
  bool _allowRoutePop = false;
  bool _hasAttemptedSave = false;
  int _initialLoadGeneration = 0;
  final GlobalKey _workbenchSectionKey =
      GlobalKey(debugLabel: 'mechanic-job-workbench');
  final GlobalKey _customerSectionKey =
      GlobalKey(debugLabel: 'mechanic-job-customer');
  final GlobalKey _costSummarySectionKey =
      GlobalKey(debugLabel: 'mechanic-job-cost-summary');

  // Image handling
  List<String> _imageUrls = [];
  final List<({Uint8List bytes, String name})> _newImages = [];
  bool _isUploadingImage = false;
  String? _linkedInvoiceNumber;
  bool _linkedInvoiceHasActivePayments = false;
  bool _linkedInvoicePaymentStateUnknown = false;

  /// La factura vinculada está confirmada y sin pagos: lo que se cobra se
  /// corrige desde ella (el comando rechaza cambiarlo desde aquí).
  bool _linkedInvoiceIsPosted = false;

  // Edit mode
  MechanicJob? _existingJob;
  String? _existingJobLoadError;

  QuotationStatus get _effectiveQuotationStatus =>
      _existingJob?.effectiveQuotationStatus ??
      _quotationStatus ??
      QuotationStatus.pending;

  /// Once a quotation leaves pending, its accepted/rejected commercial
  /// snapshot is changed only through the audited table actions. This keeps a
  /// normal form save from silently rewriting the proposal that was shown to
  /// the customer.
  bool get _isFinalQuotationReadOnly =>
      widget.jobId != null && (_existingJob?.hasFinalProposalDecision ?? false);

  /// The accepted quotation itself is immutable. Once the audited conversion
  /// has produced a normal billable service, that service remains editable;
  /// the original accepted values live in the append-only event snapshot.
  bool get _isPaymentProtectedCommercialSnapshotLocked =>
      shouldProtectJobCommercialSnapshot(
        existingJob: _existingJob,
        linkedInvoiceHasActivePayments: _linkedInvoiceHasActivePayments,
        linkedInvoicePaymentStateUnknown: _linkedInvoicePaymentStateUnknown,
        linkedInvoiceIsPosted: _linkedInvoiceIsPosted,
      );

  bool get _isCommercialSnapshotLocked =>
      _isFinalQuotationReadOnly || _isPaymentProtectedCommercialSnapshotLocked;

  /// Paid normal services may still move through their operational lifecycle.
  /// Only a final quotation or a covered warranty whose settlement cannot be
  /// proven safe blocks the status control; the server repeats this guard.
  bool get _isStatusTransitionLocked =>
      _jobType == JobType.sale ||
      _jobType == JobType.quotation ||
      _isFinalQuotationReadOnly ||
      (_jobType == JobType.warranty &&
          (_warrantyOutcome ?? _existingJob?.warrantyOutcome) ==
              WarrantyOutcome.covered &&
          _warrantyCoverageNeedsFinancialReview);

  bool get _hasConvertedQuotationHistory => _existingJob?.convertedAt != null;

  bool get _hasBlockingWarrantyLoadFailure =>
      _jobType == JobType.warranty &&
      (_isLoadingWarrantySources ||
          !_warrantyClaimLoadCompleted ||
          _warrantySourcesLoadError != null ||
          _warrantyClaimLoadError != null ||
          _exactWarrantySourceLoadError != null);

  bool _warrantyCoverageNeedsReason(
    MechanicJobServiceWarranty? selectedSource,
  ) {
    final claim = _warrantyClaim;
    if (claim != null &&
        claim.sourceJobId != null &&
        claim.sourceJobId == selectedSource?.jobId) {
      // Eligibility is frozen when the claim is registered. A later extension
      // or expiry of the source warranty must not rewrite that historical
      // decision contract in the form.
      return claim.eligibility != WarrantyEligibility.withinWindow;
    }
    return selectedSource?.state != ServiceWarrantyState.active;
  }

  bool get _warrantyCoverageNeedsFinancialReview =>
      _linkedInvoiceHasActivePayments || _linkedInvoicePaymentStateUnknown;

  bool get _canSaveJob =>
      !_isLoading &&
      !_isSaving &&
      !_isFinalQuotationReadOnly &&
      _existingJobLoadError == null &&
      !_hasBlockingWarrantyLoadFailure;

  @override
  void initState() {
    super.initState();
    _selectedWorkbenchTab = switch (widget.initialTab) {
      'diagnosis' => _JobWorkbenchTab.diagnosis,
      'products' => _JobWorkbenchTab.products,
      _ => _JobWorkbenchTab.general,
    };
    // Prevent a blank/partial form from flashing before the async edit load starts.
    // This avoids the "form opens fast, then shows loader again" flicker.
    _isLoading = true;
    _warrantyClaimLoadCompleted = widget.jobId == null;
    // Defer initialization to avoid "setState() or markNeedsBuild() called during build"
    // when services trigger notifyListeners() synchronously
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
      _loadCategoryPaths();
    });
  }

  /// La ruta de cada categoría («Componentes / Ruedas / Mazas / Maza»): su
  /// segundo nivel es el sistema de un repuesto al agrupar las líneas (G1).
  Map<String, String> _categoryPathById = const {};

  Future<void> _loadCategoryPaths() async {
    try {
      final categories = await context.read<CategoryService>().getCategories();
      if (!mounted) return;
      setState(() {
        _categoryPathById = {
          for (final category in categories)
            if (category.id != null) category.id!: category.fullPath,
        };
      });
    } on ProviderNotFoundException {
      // Sin el servicio (una prueba o un host embebido) las líneas no se
      // agrupan por repuesto; los servicios igual por su familia.
    } catch (error) {
      debugPrint('⚠️ Category paths for line groups: $error');
    }
  }

  JobLineSystem _systemOfLine(JobPartItem item) => jobLineSystem(
        serviceFamily: item.wizardProfile?.serviceFamily,
        categoryPath: _categoryPathById[item.product?.categoryId] ??
            item.product?.categoryName,
        location: item.location,
      );

  /// Las líneas agrupadas por sistema (G1), numeradas en el orden en que se
  /// ven. Con un solo sistema no hay encabezados: no dirían nada.
  List<Widget> _buildGroupedPartRows(
    ThemeData theme, {
    bool mobileLayout = false,
  }) {
    final items = _currentPartItems;
    final groups = groupJobLinesBySystem<int>(
      List<int>.generate(items.length, (index) => index),
      (index) => _systemOfLine(items[index]),
    );
    final showHeaders = groups.length > 1;
    final money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    var number = 0;
    Widget spaced(Widget child) => mobileLayout
        ? Padding(padding: const EdgeInsets.only(bottom: 10), child: child)
        : child;
    return [
      for (final group in groups) ...[
        if (showHeaders)
          JobLineGroupHeader(
            key: ValueKey('job_line_group_${group.system.name}'),
            label: group.system.label,
            lineCount: group.lines.length,
            subtotal: money.format(group.lines.fold<double>(
              0,
              (sum, index) =>
                  sum + items[index].quantity * items[index].unitPrice,
            )),
            mobileLayout: mobileLayout,
          ),
        for (final index in group.lines)
          spaced(_buildPartRow(
            theme,
            ++number,
            items[index],
            index,
            mobileLayout: mobileLayout,
            // Subir y Bajar mueven dentro del grupo que se ve.
            neighbors: jobLineGroupNeighbors(groups, index),
          )),
      ],
    ];
  }

  @override
  void dispose() {
    // Adjuntos subidos que ningún guardado se llevó: nadie más los reclama.
    // Los que van en un guardado pendiente se quedan con él en la bandeja, y
    // los que algún trabajo ya muestra nunca se borran.
    final imageScope = _imageScope;
    if (imageScope != null && _uploadedAttachments) {
      unawaited(
        WorkshopCommandOutbox.shared
            .releaseImages(imageScope, ownerForm: _formInstanceId)
            .catchError((Object error) {
          debugPrint('No se liberaron los adjuntos sin guardar: $error');
        }),
      );
    }
    _initialLoadGeneration++;
    _clientRequestController.dispose();
    _diagnosisController.dispose();
    _workSummaryController.dispose();
    _technicianNotesController.dispose();
    _discountController.dispose();
    _estimatedDurationController.dispose();
    _actualLaborHoursController.dispose();
    _subjectNotesController.dispose();
    _warrantyDecisionReasonController.dispose();
    _partAutocompleteFocus.dispose();
    _discountFocusNode.dispose();
    for (final tab in _bikeTabs) {
      tab.dispose();
    }
    super.dispose();
  }

  void _completeSuccessfulInitialLoad(int loadGeneration) {
    if (!mounted || loadGeneration != _initialLoadGeneration) return;
    setState(() => _isLoading = false);
    if (widget.jobId == null || _existingJobLoadError == null) {
      _captureInlineDraftBaseline();
    }
  }

  Future<void> _loadInitialData() async {
    final loadGeneration = ++_initialLoadGeneration;
    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final jobStatusService =
          Provider.of<JobStatusService>(context, listen: false);
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      if (mounted) {
        setState(() {
          if (customerService.hasListCustomersCache) {
            _hasLoadedCustomerCatalog = true;
            if (_customers.isEmpty) {
              _customers =
                  List<Customer>.from(customerService.cachedListCustomers);
            }
          }
          if (inventoryService.hasLoaded && _products.isEmpty) {
            _products = List<Product>.from(inventoryService.products.take(50));
            _serviceProducts = inventoryService.products
                .where((p) => p.productType == ProductType.service)
                .toList();
          }
        });
      }

      // An existing editor needs the exact job aggregate, linked financial
      // state, customer, bicycles, lines and service metadata. Broad customer,
      // product, status and subject catalogs are selector data; loading them
      // here made every open wait for thousands of unrelated rows.
      if (widget.jobId != null) {
        await _loadExistingJob();
        _completeSuccessfulInitialLoad(loadGeneration);
        return;
      }

      final results = await Future.wait<dynamic>([
        customerService.getCustomersForList(),
        inventoryService.searchProducts('', limit: 50),
        jobStatusService.loadStatuses(),
        bikeshopService.getJobSubjects(),
        inventoryService.hasLoaded
            ? Future<List<Product>>.value(
                inventoryService.products
                    .where((p) => p.productType == ProductType.service)
                    .toList(),
              )
            : inventoryService.getProductsByType(ProductType.service),
      ]);
      if (!mounted || loadGeneration != _initialLoadGeneration) return;

      List<Customer> customers = results[0] as List<Customer>;
      List<Product> products = results[1] as List<Product>;
      final subjects = results[3] as List<JobSubject>;

      final targetCustomerId = widget.customerId;
      if (targetCustomerId != null) {
        final hasCustomer = customers.any((c) => c.id == targetCustomerId);
        if (!hasCustomer) {
          final specificCustomer =
              await customerService.getCustomerById(targetCustomerId);
          if (specificCustomer != null) {
            customers = [specificCustomer, ...customers];
          }
        }
      }

      final serviceProducts = results[4] as List<Product>;

      final customStatuses = jobStatusService.activeStatuses;
      debugPrint('📋 Loaded ${customStatuses.length} custom statuses');

      if (mounted) {
        setState(() {
          _customers = customers;
          _hasLoadedCustomerCatalog = true;
          _products = products;
          _serviceProducts = serviceProducts;
          _customStatuses = customStatuses;
          _availableSubjects = subjects;
          if (_customStatuses.isNotEmpty && _selectedCustomStatus == null) {
            _selectedCustomStatus = _customStatuses.firstWhere(
              (s) => s.phase == StatusPhase.todo,
              orElse: () => _customStatuses.first,
            );
          }
          if (widget.initialJobType != null && widget.jobId == null) {
            _jobType = JobType.fromDbValue(widget.initialJobType!);
            if (_jobType == JobType.service) {
              _serviceCommercialPath = ServiceCommercialPath.budgetFirst;
            }
            if (_jobType == JobType.quotation || _isServiceBudget) {
              _quotationStatus = QuotationStatus.pending;
              _quotationValidUntil =
                  DateTime.now().add(const Duration(days: 30));
            } else {
              _quotationStatus = null;
              _quotationValidUntil = null;
            }
          }
        });
      }

      if (widget.customerId != null) {
        final customer =
            _customers.where((c) => c.id == widget.customerId).firstOrNull;
        if (customer != null) {
          await _selectCustomer(customer);
          final initialBike = _findBikeById(widget.initialBikeId);
          if (initialBike != null &&
              initialBike.isActive &&
              initialBike.customerId == customer.id) {
            _addBikeTab(initialBike);
          }
        }
      }

      _completeSuccessfulInitialLoad(loadGeneration);
    } catch (e) {
      if (mounted && loadGeneration == _initialLoadGeneration) {
        setState(() {
          _isLoading = false;
          if (widget.jobId != null) {
            _existingJobLoadError =
                'No se pudieron cargar los catálogos y datos necesarios para editar esta ficha con seguridad.';
          }
        });
        if (widget.jobId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar datos: $e')),
          );
        }
      }
    }
  }

  Future<
      ({
        String? invoiceNumber,
        bool hasActivePayments,
        bool paymentStateUnknown,
        bool isPosted,
      })> _readLinkedInvoiceFinancialState({
    required DatabaseService databaseService,
    required MechanicJob job,
  }) async {
    final invoiceId = job.invoiceId?.trim();
    if (invoiceId == null || invoiceId.isEmpty) {
      return (
        invoiceNumber: null,
        hasActivePayments: false,
        paymentStateUnknown: false,
        isPosted: false,
      );
    }

    var hasActivePayments = job.isPaid;
    try {
      final financialRows = await Future.wait<dynamic>([
        databaseService.selectById('sales_invoices', invoiceId),
        databaseService.supabase
            .from('sales_payments')
            .select('id')
            .eq('invoice_id', invoiceId)
            .isFilter('deleted_at', null)
            .gt('amount', 0)
            .limit(1),
      ]);
      final invoiceData = financialRows[0] as Map<String, dynamic>?;
      if (invoiceData == null) {
        return (
          invoiceNumber: null,
          hasActivePayments: hasActivePayments,
          paymentStateUnknown: true,
          isPosted: false,
        );
      }

      final invoiceNumber = invoiceData['invoice_number']?.toString();
      final rawPaidAmount = invoiceData['paid_amount'];
      final paidAmount = rawPaidAmount is num
          ? rawPaidAmount.toDouble()
          : double.tryParse(rawPaidAmount?.toString() ?? '') ?? 0;
      hasActivePayments = hasActivePayments ||
          invoiceData['status']?.toString().toLowerCase() == 'paid' ||
          paidAmount > 0.01;

      // Invoice mirrors can lag behind the payment ledger. The active rows are
      // queried directly both on load and again immediately before saving.
      final activePayments = financialRows[1] as List;
      hasActivePayments = hasActivePayments || activePayments.isNotEmpty;

      return (
        invoiceNumber: invoiceNumber,
        hasActivePayments: hasActivePayments,
        paymentStateUnknown: false,
        // Confirmada, o con nota de crédito (cuya guardia no deja cambiar
        // sus líneas): lo que se cobra se corrige desde la factura.
        isPosted: !hasActivePayments &&
            (isPostedSalesInvoiceStatus(invoiceData['status']?.toString()) ||
                (num.tryParse('${invoiceData['credited_amount'] ?? 0}') ?? 0) >
                    0),
      );
    } catch (error) {
      debugPrint(
        '⚠️ Could not prove linked invoice/payment state for $invoiceId: $error',
      );
      return (
        invoiceNumber: null,
        hasActivePayments: hasActivePayments,
        paymentStateUnknown: true,
        isPosted: false,
      );
    }
  }

  /// Best-effort recovery for the narrow race where a payment commits after
  /// the form preflight but before all multi-request job writes finish.
  ///
  /// Never run this for an unconfirmed/unpaid failure. This recovery only
  /// confirms that financial evidence now exists; paid invoice and job
  /// commercial rows remain guarded and are not projected over one another.
  Future<bool> _reconcileConfirmedPaymentRaceAfterSaveFailure(
    String jobId,
  ) async {
    if (!mounted || jobId.isEmpty) return false;
    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      final latestJob = await bikeshopService.getJobById(jobId);
      if (latestJob?.invoiceId == null) return false;
      final state = await _readLinkedInvoiceFinancialState(
        databaseService: databaseService,
        job: latestJob!,
      );
      if (state.paymentStateUnknown || !state.hasActivePayments) return false;

      await bikeshopService.syncJobToInvoice(jobId);
      await bikeshopService.syncBikeMemoryFromJob(jobId);
      _linkedInvoiceNumber = state.invoiceNumber;
      _linkedInvoiceHasActivePayments = state.hasActivePayments;
      _linkedInvoicePaymentStateUnknown = false;
      _linkedInvoiceIsPosted = false;
      return true;
    } catch (reconcileError) {
      debugPrint(
        '⚠️ Could not reconcile confirmed payment race for $jobId: $reconcileError',
      );
      return false;
    }
  }

  Future<void> _loadExistingJob() async {
    if (mounted) {
      setState(() {
        _existingJobLoadError = null;
        _warrantyClaimLoadError = null;
        _exactWarrantySourceLoadError = null;
        _warrantyClaimLoadCompleted = false;
      });
    }
    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      final customerService =
          Provider.of<CustomerService>(context, listen: false);

      // Lo que quedó en la bandeja del equipo para este trabajo (la app se
      // cerró o perdió la red antes de la respuesta) se reenvía antes de leer
      // las líneas: si llega, lo cargado ya lo tiene.
      final pendingLineSaves =
          await _resumePendingLineSaves(bikeshopService, widget.jobId!);
      // Una decisión de garantía que sigue en la bandeja se muestra como
      // pendiente: la cobertura a la vista es la del servidor.
      try {
        _pendingWarrantyDecision =
            await bikeshopService.pendingWarrantyDecision(widget.jobId!);
      } catch (error) {
        debugPrint('⚠️ No se pudo leer la decisión de garantía pendiente: '
            '$error');
      }

      debugPrint('🔍 Loading job with ID: ${widget.jobId}');
      final job = await bikeshopService.getJobById(
        widget.jobId!,
        includeOperationalProjections: false,
      );

      if (job == null) {
        debugPrint('❌ Job not found: ${widget.jobId}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trabajo no encontrado')),
          );
          context.pop();
        }
        return;
      }

      debugPrint('✅ Job loaded: ${job.jobNumber}');

      Future<Customer?> loadExactCustomer() async {
        final cached = _customers
            .where((candidate) => candidate.id == job.customerId)
            .firstOrNull;
        if (cached != null) return cached;
        return customerService.getCustomerById(job.customerId);
      }

      // These reads depend only on the exact job header and do not depend on
      // one another. Starting them together removes the former invoice ->
      // customer -> customer bikes -> lines/bikes waterfall.
      final exactResults = await Future.wait<dynamic>([
        _readLinkedInvoiceFinancialState(
          databaseService: databaseService,
          job: job,
        ),
        loadExactCustomer(),
        bikeshopService.getBikes(customerId: job.customerId),
        bikeshopService.getJobItems(job.id!),
        bikeshopService.getJobBikes(job.id!, forceRefresh: true),
      ]);

      final linkedInvoiceState = exactResults[0] as ({
        String? invoiceNumber,
        bool hasActivePayments,
        bool paymentStateUnknown,
        bool isPosted,
      });
      final customer = exactResults[1] as Customer?;
      final customerBikes = exactResults[2] as List<Bike>;
      final allItems = exactResults[3] as List<MechanicJobItem>;
      final jobBikes = exactResults[4] as List<MechanicJobBike>;

      if (customer == null) {
        throw StateError(
          'No se pudo cargar el cliente exacto asociado al trabajo.',
        );
      }

      if (!_customers.any((candidate) => candidate.id == customer.id)) {
        _customers = [customer, ..._customers];
      }

      await _selectCustomer(
        customer,
        loadWarrantySources: job.jobType == JobType.warranty,
        preloadedBikes: customerBikes,
      );

      // Warranty claim reads stay isolated so a projection outage cannot
      // break ordinary service, quotation, or component editing.
      MechanicJobWarrantyClaim? warrantyClaim;
      if (job.jobType == JobType.warranty) {
        try {
          warrantyClaim = await bikeshopService.getWarrantyClaim(job.id!);
          _warrantyClaimLoadCompleted = true;
        } catch (error) {
          _warrantyClaimLoadError =
              'No se pudo confirmar el vínculo histórico de esta garantía.';
          debugPrint('Error loading warranty claim ${job.id}: $error');
        }
      } else {
        _warrantyClaimLoadCompleted = true;
      }

      MechanicJobServiceWarranty? exactWarrantySource;
      final sourceJobId = warrantyClaim?.sourceJobId;
      if (sourceJobId != null && sourceJobId.trim().isNotEmpty) {
        exactWarrantySource = _warrantySources
            .where((source) => source.jobId == sourceJobId)
            .firstOrNull;
        if (exactWarrantySource == null) {
          try {
            exactWarrantySource = await bikeshopService
                .getServiceWarrantySourceByJobId(sourceJobId);
            if (exactWarrantySource == null ||
                exactWarrantySource.customerId != job.customerId) {
              _exactWarrantySourceLoadError =
                  'No se pudo recuperar el trabajo original exacto de esta garantía.';
              exactWarrantySource = null;
            }
          } catch (error) {
            _exactWarrantySourceLoadError =
                'No se pudo recuperar el trabajo original exacto de esta garantía.';
            debugPrint(
                'Error loading exact warranty source $sourceJobId: $error');
          }
        }
        if (exactWarrantySource != null &&
            !_warrantySources
                .any((source) => source.jobId == exactWarrantySource!.jobId)) {
          _warrantySources = [exactWarrantySource, ..._warrantySources];
        }
        if (exactWarrantySource != null) {
          // A linked claim needs its exact immutable source, not the optional
          // list of other candidates. Do not block normal editing merely
          // because that broader selector query failed after exact readback
          // succeeded; the source is locked and cannot be changed anyway.
          _warrantySourcesLoadError = null;
        }
      }
      debugPrint('📦 Loaded ${jobBikes.length} job bikes');

      // Load tax treatment from job
      TaxTreatment loadedTaxTreatment = job.taxTreatment;
      debugPrint('✅ Tax treatment loaded: $loadedTaxTreatment');

      final Map<String, Product?> productCache = {
        for (final product in [..._products, ..._serviceProducts])
          product.id: product,
      };

      String normalizeCatalogText(String? rawValue) {
        return (rawValue ?? '')
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
      }

      String? catalogProductIdForItem(MechanicJobItem item) {
        final directProductId = item.productId;
        if (directProductId != null && directProductId.isNotEmpty) {
          return directProductId;
        }

        final legacyServiceProductId = item.serviceProductId;
        if (legacyServiceProductId != null &&
            legacyServiceProductId.isNotEmpty) {
          return legacyServiceProductId;
        }

        return null;
      }

      final missingProductIds = allItems
          .map(catalogProductIdForItem)
          .whereType<String>()
          .where((id) => !productCache.containsKey(id))
          .toSet()
          .toList();

      final directCatalogProductIds = allItems
          .map(catalogProductIdForItem)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      final catalogHydration = await Future.wait<dynamic>([
        Future.wait<MapEntry<String, Product?>>(
          missingProductIds.map((id) async {
            try {
              return MapEntry(id, await inventoryService.getProductById(id));
            } catch (e) {
              debugPrint('⚠️ Could not fetch product $id: $e');
              return MapEntry<String, Product?>(id, null);
            }
          }),
        ),
        _serviceWizardService.getProfilesForProducts(directCatalogProductIds),
      ]);

      for (final entry
          in catalogHydration[0] as List<MapEntry<String, Product?>>) {
        productCache[entry.key] = entry.value;
      }
      final wizardProfilesByProductId = Map<String, ServiceWizardProfile?>.from(
        catalogHydration[1] as Map<String, ServiceWizardProfile?>,
      );

      // Helper to find/create product for an item
      Product? getProductForItem(MechanicJobItem item) {
        final catalogProductId = catalogProductIdForItem(item);
        if (catalogProductId != null) {
          final cached = productCache[catalogProductId];
          if (cached != null) {
            return cached;
          }

          final fallbackProductType =
              item.itemType == 'service' || item.serviceProductId != null
                  ? ProductType.service
                  : ProductType.product;

          return Product(
            id: catalogProductId,
            name: item.productName,
            sku: item.productSku ?? 'N/A',
            price: item.unitPrice,
            cost: 0,
            stockQuantity: 0,
            category: ProductCategory.other,
            productType: fallbackProductType,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }

        final normalizedSku = normalizeCatalogText(item.productSku);
        if (normalizedSku.isNotEmpty) {
          final skuMatches = productCache.values
              .whereType<Product>()
              .where(
                (product) => normalizeCatalogText(product.sku) == normalizedSku,
              )
              .toList();
          if (skuMatches.length == 1) {
            return skuMatches.first;
          }
        }

        final normalizedName = normalizeCatalogText(item.productName);
        if (normalizedName.isEmpty) {
          return null;
        }

        final serviceLikeItem =
            item.itemType == 'service' || item.serviceProductId != null;
        final candidatePool = serviceLikeItem
            ? (_serviceProducts.isNotEmpty
                ? _serviceProducts
                : productCache.values.whereType<Product>().toList())
            : productCache.values.whereType<Product>().toList();

        final exactNameMatches = candidatePool
            .where(
              (product) => normalizeCatalogText(product.name) == normalizedName,
            )
            .toList();

        if (exactNameMatches.length == 1) {
          return exactNameMatches.first;
        }

        if (exactNameMatches.length > 1) {
          const priceTolerance = 0.01;
          final exactPriceMatches = exactNameMatches
              .where(
                (product) =>
                    (product.price - item.unitPrice).abs() <= priceTolerance,
              )
              .toList();
          if (exactPriceMatches.length == 1) {
            return exactPriceMatches.first;
          }
        }

        return null;
      }

      final productByItem = <MechanicJobItem, Product?>{
        for (final item in allItems) item: getProductForItem(item),
      };
      final legacyResolvedServiceProductIds = allItems
          .where((item) {
            final product = productByItem[item];
            return catalogProductIdForItem(item) == null &&
                (item.itemType == 'service' ||
                    item.serviceProductId != null ||
                    product?.isService == true) &&
                product?.id != null &&
                !wizardProfilesByProductId.containsKey(product!.id);
          })
          .map((item) => productByItem[item]!.id)
          .whereType<String>()
          .toSet();
      if (legacyResolvedServiceProductIds.isNotEmpty) {
        wizardProfilesByProductId.addAll(
          await _serviceWizardService.getProfilesForProducts(
            legacyResolvedServiceProductIds,
          ),
        );
      }

      ServiceWizardProfile? getWizardProfileForLoadedItem(
        MechanicJobItem item,
        Product? product,
      ) {
        final isServiceItem = item.itemType == 'service' ||
            item.serviceProductId != null ||
            product?.isService == true;
        if (!isServiceItem || product?.id == null) {
          return null;
        }

        return wizardProfilesByProductId[product!.id];
      }

      JobPartItem buildLoadedPartItem(MechanicJobItem item) {
        final product = productByItem[item];
        return JobPartItem.fromPersisted(
          item,
          product: product,
          wizardProfile: getWizardProfileForLoadedItem(item, product),
        );
      }

      JobSubject? loadedSubject = job.subjectData;
      if (loadedSubject == null && job.subjectId != null) {
        loadedSubject = await bikeshopService.getJobSubjectById(job.subjectId!);
        if (loadedSubject == null) {
          throw StateError(
            'No se pudo cargar el componente exacto asociado al trabajo.',
          );
        }
      }

      // Build bike tabs from job bikes data
      final List<_BikeTabData> loadedBikeTabs = [];

      if (jobBikes.isNotEmpty) {
        // Multi-bike job: create tab for each job bike
        for (final jobBike in jobBikes) {
          // Use bike from local cache, or from the joined data loaded by getJobBikes()
          Bike? bike = _findBikeById(jobBike.bikeId);
          bike ??= jobBike.bike; // Fall back to bike loaded from join
          bike ??= await bikeshopService.getBikeById(jobBike.bikeId);

          if (bike == null) {
            throw StateError(
              'No se pudo cargar la bicicleta ${jobBike.bikeId} asociada al trabajo.',
            );
          }

          // Make sure this bike is in _bikes for UI consistency
          if (!_bikes.any((b) => b.id == bike!.id)) {
            _bikes.add(bike);
          }

          final tab = _BikeTabData(
            bike: bike,
            jobBikeId: jobBike.id,
          );

          // Set per-bike fields
          tab.clientRequestController.text = jobBike.workRequested ?? '';
          tab.diagnosisController.text = jobBike.diagnosis ?? '';
          tab.workRequestedController.text = jobBike.workPerformed ?? '';
          tab.technicianNotesController.text = jobBike.technicianNotes ?? '';
          tab.diagnosisSheetKey = jobBike.diagnosisSheetKey;
          tab.diagnosisSheet = jobBike.diagnosisSheet;
          tab.diagnosisSheetUpdatedAt = jobBike.diagnosisSheetUpdatedAt;
          tab.isWarrantyWork = jobBike.isWarrantyWork;
          tab.requiresApproval = jobBike.requiresApproval;
          tab.approvedByCustomer = jobBike.approvedByCustomer;

          // Load items for this specific bike
          // Load items for this specific bike
          final bikeItems =
              allItems.where((item) => item.jobBikeId == jobBike.id).toList();

          for (final item in bikeItems) {
            tab.partItems.add(buildLoadedPartItem(item));
          }

          loadedBikeTabs.add(tab);
          debugPrint(
              '✅ Loaded bike tab: ${bike.displayName} with ${tab.partItems.length} items');
        }

        // Add General Tab for orphan items
        final generalTab =
            _BikeTabData(isGeneralTab: true, tabId: 'general_tab');
        final orphanItems =
            allItems.where((item) => item.jobBikeId == null).toList();
        for (final item in orphanItems) {
          generalTab.partItems.add(buildLoadedPartItem(item));
        }
        loadedBikeTabs.add(generalTab);
      } else {
        // Legacy single-bike job: create one tab from job data
        Bike? bike = _findBikeById(job.bikeId);
        if (bike == null && job.bikeId != null) {
          bike = await bikeshopService.getBikeById(job.bikeId!);
        }
        if (bike != null) {
          if (!_bikes.any((candidate) => candidate.id == bike!.id)) {
            _bikes.add(bike);
          }
          final tab = _BikeTabData(bike: bike);

          // Use job-level fields for the single bike
          tab.clientRequestController.text = job.clientRequest ?? '';
          tab.diagnosisController.text = job.diagnosis ?? '';
          tab.workRequestedController.text = job.workPerformed ?? '';
          tab.technicianNotesController.text = job.notes ?? '';
          tab.isWarrantyWork = job.isWarrantyJob;
          tab.requiresApproval = job.requiresApproval;
          tab.approvedByCustomer = job.approvedByCustomer;

          loadedBikeTabs.add(tab);

          // A legacy job has no mechanic_job_bikes ownership record, so its
          // lines cannot be truthfully attributed to this bicycle tab. Keep
          // each row exactly once in General until staff explicitly changes
          // it; duplicating the same stable id in both tabs caused the second
          // save pass to silently reassign it back to job_bike_id = null.
          final legacyGeneralTab =
              _BikeTabData(isGeneralTab: true, tabId: 'general_tab');
          for (final item in allItems) {
            legacyGeneralTab.partItems.add(buildLoadedPartItem(item));
          }
          loadedBikeTabs.add(legacyGeneralTab);
          debugPrint(
              '✅ Loaded legacy single-bike tab: ${bike.displayName}; preserved ${legacyGeneralTab.partItems.length} unowned items once in General');
        } else if (job.bikeId != null) {
          throw StateError(
            'No se pudo cargar la bicicleta exacta asociada al trabajo.',
          );
        }
      }

      final standalonePersistedItems = mechanicJobStandaloneItemsForForm(
        persistedItems: allItems,
        hasPhysicalBikeTabs: loadedBikeTabs.any((tab) => !tab.isGeneralTab),
      );
      final loadedStandaloneItems = <JobPartItem>[];
      for (final item in standalonePersistedItems) {
        loadedStandaloneItems.add(buildLoadedPartItem(item));
      }

      // Quotation conversion keeps the accepted narrative on mechanic_jobs and
      // creates the first mechanic_job_bikes row as the new physical anchor.
      // Hydrate only empty bike fields from that job-level history so the
      // diagnosis remains visible without overwriting later bike-specific work.
      if (job.convertedAt != null) {
        final convertedPrimaryTab =
            loadedBikeTabs.where((tab) => !tab.isGeneralTab).firstOrNull;
        if (convertedPrimaryTab != null) {
          convertedPrimaryTab.clientRequestController.text =
              mechanicJobConvertedBikeNarrativeValue(
            bikeValue: convertedPrimaryTab.clientRequestController.text,
            jobValue: job.clientRequest,
          );
          convertedPrimaryTab.diagnosisController.text =
              mechanicJobConvertedBikeNarrativeValue(
            bikeValue: convertedPrimaryTab.diagnosisController.text,
            jobValue: job.diagnosis,
          );
          convertedPrimaryTab.workRequestedController.text =
              mechanicJobConvertedBikeNarrativeValue(
            bikeValue: convertedPrimaryTab.workRequestedController.text,
            jobValue: job.workPerformed,
          );
          convertedPrimaryTab.technicianNotesController.text =
              mechanicJobConvertedBikeNarrativeValue(
            bikeValue: convertedPrimaryTab.technicianNotesController.text,
            jobValue: job.notes,
          );
        }
      }

      if (mounted) {
        for (final previousTab in _bikeTabs) {
          if (!loadedBikeTabs.contains(previousTab)) {
            previousTab.dispose();
          }
        }
        setState(() {
          _existingJob = job;
          _selectedCustomer = customer;
          _selectedPriority = job.priority;
          _selectedStatus = job.status;

          // Load custom status
          if (job.customStatus != null) {
            _selectedCustomStatus = job.customStatus;
          } else if (job.statusId != null && _customStatuses.isNotEmpty) {
            final found = _customStatuses.where((s) => s.id == job.statusId);
            if (found.isNotEmpty) {
              _selectedCustomStatus = found.first;
            }
          }

          _selectedDeadline = job.deliveryDeadline;
          _selectedArrivalDate = job.arrivalDate;
          _taxTreatment = loadedTaxTreatment;
          _linkedInvoiceNumber = linkedInvoiceState.invoiceNumber;
          _linkedInvoiceHasActivePayments =
              linkedInvoiceState.hasActivePayments;
          _linkedInvoicePaymentStateUnknown =
              linkedInvoiceState.paymentStateUnknown;
          _linkedInvoiceIsPosted = linkedInvoiceState.isPosted;
          _discountController.text = job.discountAmount.toString();
          _estimatedDurationController.text =
              job.estimatedDurationHours?.toString() ?? '';
          _actualLaborHoursController.text =
              job.actualLaborHours?.toString() ?? '';

          // Set bike tabs (multi-bike or legacy single-bike)
          _bikeTabs.clear();
          _bikeTabs.addAll(loadedBikeTabs);
          _selectedBikeTabIndex = 0;

          // Hydrate the authoritative job-level narrative first. Component,
          // quotation, and subject-based warranty jobs intentionally have no
          // bike tabs, so keeping this inside the bike-only branch would show
          // an empty diagnosis on edit and a later save could erase it.
          _clientRequestController.text = job.clientRequest ?? '';
          _diagnosisController.text = job.diagnosis ?? '';
          _workSummaryController.text = job.workPerformed ?? '';
          _technicianNotesController.text = job.notes ?? '';

          // Bike tabs remain the compatibility source for bicycle jobs.
          if (loadedBikeTabs.isNotEmpty) {
            _selectedBike = loadedBikeTabs.first.bike;
            _clientRequestController.text =
                loadedBikeTabs.first.clientRequestController.text;
            _diagnosisController.text =
                loadedBikeTabs.first.diagnosisController.text;
            _workSummaryController.text =
                loadedBikeTabs.first.workRequestedController.text;
            _technicianNotesController.text =
                loadedBikeTabs.first.technicianNotesController.text;
            _requiresApproval = loadedBikeTabs.first.requiresApproval;
          }

          // Load new job type fields
          // The database deliberately keeps `job_type = quotation` so older
          // clients cannot accidentally invoice a non-posting proposal. The
          // canonical axes let this client restore a bicycle budget to the
          // familiar Servicio form with its ficha and diagnosis intact.
          _jobType = job.isServiceBudget ? JobType.service : job.jobType;
          _serviceCommercialPath =
              mechanicJobServiceCommercialPathForExisting(job);
          if (loadedSubject != null) {
            _selectedSubject = loadedSubject;
            if (!_availableSubjects.any((s) => s.id == loadedSubject!.id)) {
              _availableSubjects = [loadedSubject, ..._availableSubjects];
            }
          }
          if (job.subjectNotes != null && job.subjectNotes!.isNotEmpty) {
            _subjectNotesController.text = job.subjectNotes!;
          }
          _warrantyOutcome = job.warrantyOutcome;
          _warrantyClaim = warrantyClaim;
          _selectedWarrantySource = exactWarrantySource;
          _warrantySaveCheckpoint.hydrate(
            claim: warrantyClaim,
            persistedOutcome: job.warrantyOutcome,
          );
          _warrantyDecisionReasonController.text = warrantyClaim?.reason ?? '';
          _quotationStatus = job.quotationStatus;
          _quotationValidUntil = job.quotationValidUntil;

          // Subject-only quotation/component/warranty modes have no bicycle
          // tabs. Keep their stable persisted line ids and full configuration
          // in the job-level workbench so Save updates rather than deletes.
          _partItems
            ..clear()
            ..addAll(loadedStandaloneItems);
          _serviceItems.clear();
          _seenLineVersions
            ..clear()
            ..addAll({
              for (final item in allItems)
                if (item.id != null && item.version != null)
                  item.id!: item.version!,
            });
          // Uno que sigue sin respuesta es de un formulario anterior: las
          // líneas a la vista son las del servidor, sin él.
          _pendingLineSave = pendingLineSaves.isEmpty
              ? null
              : _PendingLineSave.restored(pendingLineSaves);
          _headerBaseline = Map<String, dynamic>.of(job.persistedHeader ?? {});
          _jobBikeBaseline
            ..clear()
            ..addAll({
              for (final jobBike in jobBikes)
                if (jobBike.id != null)
                  jobBike.id!:
                      Map<String, dynamic>.of(jobBike.persisted ?? const {}),
            });
          _shownJobBikeIds
            ..clear()
            ..addAll({
              for (final tab in loadedBikeTabs)
                if (tab.jobBikeId != null) tab.jobBikeId!,
            });
          _headerShown = _headerMirror(
            protect: _isPaymentProtectedCommercialSnapshotLocked,
          );
          _bikeFactsAwaitingReconfirmation.clear();
          _laborLinePersistedIds.clear();

          // Image URLs
          _imageUrls = List.from(job.imageUrls);
        });

        unawaited(_loadSelectedBikeProfile(loadedBikeTabs.firstOrNull?.bike));
        unawaited(_loadPartChangeContext());
        if (pendingLineSaves.isNotEmpty) {
          _showBikeFactOutcome(
            'Este trabajo tiene un guardado de líneas que quedó en este equipo '
            'sin respuesta del servidor; se envía solo al volver la conexión. '
            'Las líneas a la vista son las del servidor, sin ese cambio: '
            'espera a que llegue antes de cambiarlas.',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading job: $e');
      if (mounted) {
        setState(() {
          _existingJobLoadError =
              'No se pudo cargar la ficha completa. No se habilitó la edición para proteger sus datos.';
        });
      }
    }
  }

  Future<void> _selectCustomer(
    Customer customer, {
    bool loadWarrantySources = false,
    List<Bike>? preloadedBikes,
  }) async {
    final bikeshopService =
        Provider.of<BikeshopService>(context, listen: false);
    final customerChanged = _selectedCustomer?.id != customer.id;

    // Bicycle/customer loading is part of every job flow. Warranty history is
    // deliberately separate: an unavailable warranty projection must not
    // blank or block an ordinary service, quotation, or component form.
    final bikes = preloadedBikes ??
        await bikeshopService.getBikes(customerId: customer.id);
    if (!mounted) return;

    if (customerChanged) {
      for (final tab in _bikeTabs) {
        tab.dispose();
      }
    }

    setState(() {
      _selectedCustomer = customer;
      _bikes = bikes;
      _selectedBike = null; // Reset bike selection
      _selectedBikeProfile = null;
      if (customerChanged) {
        // Every related object must belong to the selected customer. Keeping a
        // source job, bike, or component from the previous customer can create
        // an invalid warranty link even when the field looks visually empty.
        _warrantySourceSelectionEpoch++;
        _selectedWarrantySource = null;
        _selectedSubject = null;
        _warrantyOutcome = WarrantyOutcome.pending;
        _warrantyDecisionReasonController.clear();
        _isLoadingWarrantySourceObject = false;
        _warrantySourceObjectError = null;
        _warrantySourcesLoadError = null;
        _warrantyClaimLoadError = null;
        _exactWarrantySourceLoadError = null;
        _warrantySources = [];
        _warrantySaveCheckpoint.reset();
        _pendingWarrantyRegistrationOperationKey = null;
        _pendingWarrantyDecisionOperationKey = null;
        _pendingWarrantyDecisionFingerprint = null;
        _bikeTabs.clear();
        _selectedBikeTabIndex = 0;
      }
    });

    if (loadWarrantySources || _jobType == JobType.warranty) {
      await _loadWarrantySourcesForSelectedCustomer();
    }
  }

  Future<void> _loadWarrantySourcesForSelectedCustomer() async {
    final customer = _selectedCustomer;
    final customerId = customer?.id;
    if (customerId == null || customerId.isEmpty) return;

    setState(() {
      _isLoadingWarrantySources = true;
      _warrantySourcesLoadError = null;
    });

    try {
      final sources = await Provider.of<BikeshopService>(
        context,
        listen: false,
      ).getServiceWarrantySources(customerId);
      if (!mounted || _selectedCustomer?.id != customerId) return;

      setState(() {
        final lockedSource = _warrantyClaim?.sourceJobId == null
            ? null
            : _selectedWarrantySource;
        _warrantySources =
            sources.where((source) => source.jobId != widget.jobId).toList();
        if (lockedSource != null &&
            !_warrantySources
                .any((source) => source.jobId == lockedSource.jobId)) {
          _warrantySources = [lockedSource, ..._warrantySources];
        }
      });
    } catch (error) {
      if (!mounted || _selectedCustomer?.id != customerId) return;
      setState(() {
        _warrantySourcesLoadError =
            'No se pudieron cargar los trabajos originales disponibles.';
      });
      debugPrint('Error loading warranty sources: $error');
    } finally {
      if (mounted && _selectedCustomer?.id == customerId) {
        setState(() => _isLoadingWarrantySources = false);
      }
    }
  }

  Future<Customer?> _createQuickCustomer(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final customer = Customer(
        tenantId: tenantId,
        name: name.trim(),
        rut: '',
      );

      final created = await customerService.createCustomer(customer);
      if (!mounted) return created;

      // Add to cached list
      setState(() {
        _customers.add(created);
      });

      return created;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear cliente: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  Future<void> _showCustomerSelector() async {
    final customerService =
        Provider.of<CustomerService>(context, listen: false);

    if (!_hasLoadedCustomerCatalog) {
      try {
        final customers = await customerService.getCustomersForList();
        if (!mounted) return;
        setState(() {
          _customers = List<Customer>.from(customers);
          final selectedCustomer = _selectedCustomer;
          if (selectedCustomer != null &&
              !_customers.any((item) => item.id == selectedCustomer.id)) {
            _customers.insert(0, selectedCustomer);
          }
          _hasLoadedCustomerCatalog = true;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudieron cargar los clientes: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final selected = await showDialog<Customer>(
      context: context,
      builder: (context) {
        return _CustomerSelector(
          initialCustomers: List<Customer>.from(_customers),
          onCreateCustomer: _createQuickCustomer,
        );
      },
    );

    if (selected != null && mounted) {
      await _selectCustomer(selected);
      final exists = _customers.any((customer) => customer.id == selected.id);
      if (!exists) {
        setState(() {
          _customers.add(selected);
        });
      }
    }
  }

  // ============================================================
  // BIKE TAB MANAGEMENT
  // ============================================================

  bool get _hasPhysicalBikeTabs =>
      _bikeTabs.any((tab) => !tab.isGeneralTab && tab.bike != null);

  /// Moves every commercial line out of bicycle tabs before their
  /// ficha/diagnosis context is intentionally removed. Stable instances and
  /// IDs keep wizard answers and future invoice linkage intact.
  void _moveBikeTabLinesToStandalone() {
    final preserved = preserveMechanicJobModeLines<JobPartItem>(
      collections: <Iterable<JobPartItem>>[
        _partItems,
        ..._bikeTabs.map((tab) => tab.partItems),
      ],
      stableIdOf: (item) => item.id,
    );
    for (final tab in _bikeTabs) {
      tab.partItems.clear();
    }
    _partItems
      ..clear()
      ..addAll(preserved);
    _selectedServiceIndex = null;
  }

  /// A physical bicycle uses its own diagnosis tab, while unassigned
  /// products/services belong to the General tab. This is called whenever the
  /// first bicycle is added so Quote/Component -> Service cannot strand lines
  /// in the legacy standalone collection that the save path would ignore.
  void _moveStandaloneLinesToGeneralTab() {
    if (_partItems.isEmpty) return;
    final generalTab = _bikeTabs.where((tab) => tab.isGeneralTab).firstOrNull;
    if (generalTab == null) return;
    final preserved = preserveMechanicJobModeLines<JobPartItem>(
      collections: <Iterable<JobPartItem>>[
        generalTab.partItems,
        _partItems,
      ],
      stableIdOf: (item) => item.id,
    );
    generalTab.partItems
      ..clear()
      ..addAll(preserved);
    _partItems.clear();
    _selectedServiceIndex = null;
  }

  /// Lo que el guardado deja en los campos de la cabecera que repiten algo
  /// del trabajo: con bicis, el relato y las marcas de la primera
  /// (compatibilidad); sin bicis, los del propio trabajo. Al cargar es lo que
  /// el formulario mostró de esos campos ([_headerShown]), que puede no ser
  /// la cabecera: la primera bici puede decir otra cosa.
  Map<String, dynamic> _headerMirror({required bool protect}) {
    // Under payment protection, only an already-persisted physical tab may
    // contribute diagnosis to the legacy job mirror. A bike added during a
    // payment race must not silently become the invoiced object's narrative.
    final firstTab = protect
        ? _bikeTabs
            .where((tab) =>
                !tab.isGeneralTab &&
                tab.jobBikeId != null &&
                tab.jobBikeId!.isNotEmpty)
            .firstOrNull
        : (_bikeTabs.isNotEmpty ? _bikeTabs.first : null);
    String? narrative(
      TextEditingController? bike,
      TextEditingController job,
    ) {
      final bikeText = bike?.text.trim() ?? '';
      if (bikeText.isNotEmpty) return bikeText;
      final jobText = job.text.trim();
      return jobText.isEmpty ? null : jobText;
    }

    return {
      'client_request': narrative(
          firstTab?.clientRequestController, _clientRequestController),
      'diagnosis':
          narrative(firstTab?.diagnosisController, _diagnosisController),
      'work_performed':
          narrative(firstTab?.workRequestedController, _workSummaryController),
      'notes': narrative(
          firstTab?.technicianNotesController, _technicianNotesController),
      'requires_approval': firstTab?.requiresApproval ?? _requiresApproval,
      'is_warranty_job':
          firstTab?.isWarrantyWork ?? (_jobType == JobType.warranty),
    };
  }

  /// Quote/component intake keeps narrative at job level. When the user turns
  /// that unsaved draft into a bicycle service, seed the first physical tab so
  /// the same diagnosis remains visible after save/reload.
  void _hydrateFirstBikeNarrativeFromStandalone(_BikeTabData tab) {
    tab.clientRequestController.text = mechanicJobFirstBikeNarrativeValue(
      bikeValue: tab.clientRequestController.text,
      standaloneValue: _clientRequestController.text,
    );
    tab.diagnosisController.text = mechanicJobFirstBikeNarrativeValue(
      bikeValue: tab.diagnosisController.text,
      standaloneValue: _diagnosisController.text,
    );
    tab.workRequestedController.text = mechanicJobFirstBikeNarrativeValue(
      bikeValue: tab.workRequestedController.text,
      standaloneValue: _workSummaryController.text,
    );
    tab.technicianNotesController.text = mechanicJobFirstBikeNarrativeValue(
      bikeValue: tab.technicianNotesController.text,
      standaloneValue: _technicianNotesController.text,
    );
  }

  void _clearSelectedBikeObject({bool discardPendingProfileEdits = false}) {
    final removedBikeIds =
        _bikeTabs.map((tab) => tab.bike?.id).whereType<String>().toSet();
    final removedItemIds =
        _bikeTabs.expand((tab) => tab.partItems).map((item) => item.id).toSet();

    for (final tab in _bikeTabs) {
      tab.dispose();
    }
    _bikeTabs.clear();
    _selectedBike = null;
    _selectedBikeTabIndex = 0;
    _selectedBikeProfile = null;
    _selectedBikeProfileLoadFailed = false;
    _isLoadingSelectedBikeProfile = false;

    for (final itemId in removedItemIds) {
      _pendingServiceWizardAnswers.remove(itemId);
    }
    if (discardPendingProfileEdits) {
      for (final bikeId in removedBikeIds) {
        _discardPendingBikeProfilePromotion(bikeId);
      }
    }
  }

  List<String> get _selectedPhysicalBikeIds => _bikeTabs
      .where((tab) => !tab.isGeneralTab)
      .map((tab) => tab.bike?.id)
      .whereType<String>()
      .toList(growable: false);

  bool _warrantySourceObjectMatchesForm(
    MechanicJobServiceWarranty source,
  ) {
    return source.physicalObject.matchesSelection(
      selectedBikeIds: _selectedPhysicalBikeIds,
      selectedSubjectId: _selectedSubject?.id,
      selectedSubjectNotes: _subjectNotesController.text,
    );
  }

  /// Add a bike to the job (creates a new tab)
  void _addBikeTab(Bike bike) {
    if (_isSaving || _isCommercialSnapshotLocked) return;
    // Check if bike already exists in tabs
    if (_bikeTabs.any((tab) => tab.bike?.id == bike.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${bike.displayName} ya está en este trabajo')),
      );
      return;
    }

    final isFirstPhysicalBike = !_hasPhysicalBikeTabs;
    setState(() {
      final newTab = _BikeTabData(bike: bike);
      if (isFirstPhysicalBike) {
        _hydrateFirstBikeNarrativeFromStandalone(newTab);
      }
      final generalTabIndex = _bikeTabs.indexWhere((t) => t.isGeneralTab);

      if (generalTabIndex != -1) {
        // Insert before general tab
        _bikeTabs.insert(generalTabIndex, newTab);
        _selectedBikeTabIndex = generalTabIndex;
      } else {
        _bikeTabs.add(newTab);
        if (_bikeTabs.length == 1) {
          _bikeTabs.add(_BikeTabData(isGeneralTab: true, tabId: 'general_tab'));
        }
        _selectedBikeTabIndex = _bikeTabs.length - 2;
      }

      _moveStandaloneLinesToGeneralTab();

      // Also set legacy single bike (for backward compat)
      _selectedBike = bike;
    });

    unawaited(_loadSelectedBikeProfile(bike));
  }

  Bike? _findBikeById(String? bikeId) {
    if (bikeId == null) return null;

    for (final bike in _bikes) {
      if (bike.id == bikeId) {
        return bike;
      }
    }

    return null;
  }

  Future<void> _refreshCustomerBikes({String? selectedBikeId}) async {
    final customerId = _selectedCustomer?.id;
    if (customerId == null) return;

    final bikeshopService =
        Provider.of<BikeshopService>(context, listen: false);
    final bikes = await bikeshopService.getBikes(customerId: customerId);

    if (!mounted) return;

    final bikesById = <String, Bike>{
      for (final bike in bikes)
        if (bike.id != null) bike.id!: bike,
    };
    final resolvedSelectedBikeId = selectedBikeId ?? _selectedBike?.id;

    setState(() {
      _bikes = bikes;

      for (final tab in _bikeTabs) {
        final tabBikeId = tab.bike?.id;
        if (tabBikeId != null && bikesById.containsKey(tabBikeId)) {
          tab.bike = bikesById[tabBikeId];
        }
      }

      _selectedBike = resolvedSelectedBikeId != null
          ? bikesById[resolvedSelectedBikeId]
          : null;

      if (_selectedBike == null) {
        _selectedBikeProfile = null;
      }
    });

    if (_selectedBike != null) {
      unawaited(_loadSelectedBikeProfile(_selectedBike));
    }
  }

  Future<Bike?> _openBikeDialog({
    Bike? bike,
    bool selectSavedBike = false,
  }) async {
    final customerId = _selectedCustomer?.id;
    if (customerId == null) return null;

    final result = await showDialog<Bike?>(
      context: context,
      builder: (dialogContext) => BikeFormDialog(
        customerId: customerId,
        bike: bike,
      ),
    );

    if (!mounted) return result;

    if (bike != null || result != null) {
      await _refreshCustomerBikes(
        selectedBikeId:
            selectSavedBike ? (result?.id ?? bike?.id) : _selectedBike?.id,
      );
    }

    if (result?.id == null) {
      return null;
    }

    return _findBikeById(result!.id) ?? result;
  }

  /// Remove a bike tab
  void _removeBikeTab(int index) {
    if (_isSaving || _isCommercialSnapshotLocked) return;
    if (_bikeTabs[index].isGeneralTab) {
      return; // Prevent removing the General tab
    }

    final regularTabsCount = _bikeTabs.where((t) => !t.isGeneralTab).length;
    if (regularTabsCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe haber al menos una bicicleta')),
      );
      return;
    }

    final removedBikeId = _bikeTabs[index].bike?.id;
    setState(() {
      _bikeTabs[index].dispose();
      _bikeTabs.removeAt(index);
      if (removedBikeId != null &&
          !_bikeTabs.any((tab) => tab.bike?.id == removedBikeId)) {
        _discardPendingBikeProfilePromotion(removedBikeId);
      }
      if (_selectedBikeTabIndex >= _bikeTabs.length) {
        _selectedBikeTabIndex = _bikeTabs.length - 1;
      }
      // Update legacy single bike
      _selectedBike = _bikeTabs[_selectedBikeTabIndex].bike;
    });

    unawaited(_loadSelectedBikeProfile(_selectedBike));
  }

  Future<void> _loadSelectedBikeProfile(Bike? bike) async {
    if (!mounted) return;

    if (bike?.id == null) {
      setState(() {
        _selectedBikeProfile = null;
        _isLoadingSelectedBikeProfile = false;
        _selectedBikeProfileLoadFailed = false;
      });
      return;
    }

    setState(() {
      _selectedBikeProfile = null;
      _isLoadingSelectedBikeProfile = true;
      _selectedBikeProfileLoadFailed = false;
    });

    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final aggregate = await bikeshopService.getBikeAggregate(bike!.id!);
      final profile = aggregate.profile;
      final effectiveProfile =
          _pendingBikeProfileOverrides[bike.id!] ?? profile;
      final tabForBike = _bikeTabForBike(bike);
      final hydrations = tabForBike == null
          ? null
          : await _hydrateDefaultServiceLocationsForTab(
              tabForBike,
              effectiveProfile,
            );

      if (!mounted || _selectedBike?.id != bike.id) {
        return;
      }

      setState(() {
        _selectedBikeProfile = effectiveProfile;
        _selectedBikeProfileLoadFailed = false;
        if (tabForBike != null && hydrations != null) {
          _applyServiceLocationHydrations(tabForBike, hydrations);
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error loading selected bike profile: $e');
      if (mounted && _selectedBike?.id == bike?.id) {
        setState(() => _selectedBikeProfileLoadFailed = true);
      }
    } finally {
      if (mounted && _selectedBike?.id == bike?.id) {
        setState(() => _isLoadingSelectedBikeProfile = false);
      }
    }
  }

  Object? get _partCompatibilityContextKey {
    final currentTab = _currentBikeTab;
    final profile = _selectedBikeProfile;
    final bike = currentTab?.bike;
    if (currentTab == null ||
        currentTab.isGeneralTab ||
        bike == null ||
        profile == null) {
      return null;
    }

    final technicalValues = profile.technicalValues;
    return [
      profile.bikeId,
      profile.updatedAt.toIso8601String(),
      bike.bikeType?.dbValue ?? '',
      bike.wheelSize ?? '',
      bike.frontHubSpacingMm?.toString() ?? '',
      bike.rearHubSpacingMm?.toString() ?? '',
      bike.spokeCount?.toString() ?? '',
      technicalValues['brakeType']?.toString() ?? '',
      technicalValues['rimBrakeFamily']?.toString() ?? '',
      technicalValues['frontRotorSizeMm']?.toString() ?? '',
      technicalValues['rearRotorSizeMm']?.toString() ?? '',
      technicalValues['drivetrainConfig']?.toString() ?? '',
      technicalValues['drivetrainSpeeds']?.toString() ?? '',
      technicalValues['freehubType']?.toString() ?? '',
      technicalValues['frontSpokeHoles']?.toString() ?? '',
      technicalValues['rearSpokeHoles']?.toString() ?? '',
      technicalValues['valveType']?.toString() ?? '',
      technicalValues['bottomBracketFamily']?.toString() ?? '',
    ].join('|');
  }

  Future<Map<String, ProductCompatibilityAssessment>>
      _resolveCurrentBikePartCompatibility(List<Product> products) async {
    final currentTab = _currentBikeTab;
    final profile = _selectedBikeProfile;
    final bike = currentTab?.bike;
    if (currentTab == null ||
        currentTab.isGeneralTab ||
        bike == null ||
        profile == null) {
      return const {};
    }

    return _bikeProductCompatibilityService.buildAutocompleteAssessments(
      bike: bike,
      profile: profile,
      products: products,
    );
  }

  Future<void> _openSelectedBikeRecord() async {
    final customerId = _selectedCustomer?.id;
    final bikeId = _selectedBike?.id;
    if (customerId == null || bikeId == null) return;

    final route = Uri(
      path: '/clientes/$customerId',
      queryParameters: {
        'bike_id': bikeId,
      },
    ).toString();

    await context.push(route);

    if (!mounted) return;
    await _refreshCustomerBikes(selectedBikeId: bikeId);
  }

  Widget _buildBikeProfileSummaryCard() {
    if (_selectedBike == null) return const SizedBox.shrink();

    final snapshot = BikeRecordSnapshot.fromBikeAndProfile(
      bike: _selectedBike!,
      profile: _selectedBikeProfile,
    );
    final canOpenProfile =
        _selectedCustomer?.id != null && _selectedBike?.id != null;
    final actionLabel =
        snapshot.hasStructuredProfile ? 'Editar ficha' : 'Completar ficha';
    return MechanicJobBikeContextCard(
      snapshot: snapshot,
      isLoading: _isLoadingSelectedBikeProfile,
      loadFailed: _selectedBikeProfileLoadFailed,
      onRetry: () => _loadSelectedBikeProfile(_selectedBike),
      onOpenProfile:
          canOpenProfile ? () => unawaited(_openSelectedBikeRecord()) : null,
      onEditProfile: () => unawaited(
        _openBikeDialog(
          bike: _selectedBike,
          selectSavedBike: true,
        ),
      ),
      editActionLabel: actionLabel,
    );
  }

  /// Show bike selector to add a bike
  Future<void> _showAddBikeSelector() async {
    if (_isSaving || _isCommercialSnapshotLocked) return;
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero seleccione un cliente')),
      );
      return;
    }

    // Get customer bikes that aren't already in tabs
    final availableBikes = _bikes
        .where((bike) => !_bikeTabs.any((tab) => tab.bike?.id == bike.id))
        .toList();

    if (availableBikes.isEmpty) {
      // Show option to create new bike
      final newBike = await _openBikeDialog(selectSavedBike: true);

      if (newBike != null && mounted) {
        _addBikeTab(newBike);
      }
      return;
    }

    // Show bike selection popup
    final selected = await showDialog<Bike?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Bicicleta'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...availableBikes.map((bike) => ListTile(
                    leading: const Icon(Icons.pedal_bike),
                    title: Text(bike.displayName),
                    subtitle: bike.serialNumber != null
                        ? Text('S/N: ${bike.serialNumber}')
                        : null,
                    onTap: () => Navigator.pop(context, bike),
                  )),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Nueva bicicleta'),
                onTap: () async {
                  Navigator.pop(context); // Close selector
                  final newBike = await _openBikeDialog(selectSavedBike: true);
                  if (newBike != null && mounted) {
                    _addBikeTab(newBike);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      _addBikeTab(selected);
    }
  }

  /// Get the current part items list (from bike tab or legacy)
  List<JobPartItem> get _currentPartItems {
    final tab = _currentBikeTab;
    return tab != null ? tab.partItems : _partItems;
  }

  Map<String, dynamic>? _effectiveWizardAnswersForItem(JobPartItem item) {
    final answers = item.wizardAnswers ?? _pendingServiceWizardAnswers[item.id];
    if (answers == null || answers.isEmpty) {
      return null;
    }
    return Map<String, dynamic>.from(answers);
  }

  void _syncPendingWizardAnswerCache(JobPartItem item) {
    final answers = item.wizardAnswers;
    if (answers == null || answers.isEmpty) {
      _pendingServiceWizardAnswers.remove(item.id);
      return;
    }
    _pendingServiceWizardAnswers[item.id] = Map<String, dynamic>.from(answers);
  }

  Future<void> _addCatalogPart(Product product) async {
    if (!mounted) return;
    final wizardProfile = await _loadServiceWizardProfileForProduct(
      product,
      isServiceItem: product.isService,
    );
    final defaultLocation = _defaultServiceLocationForProfile(
      wizardProfile,
      bikeProfile: _bikeProfileForCurrentTab(),
    );

    if (!mounted) return;

    setState(() {
      _currentPartItems.add(JobPartItem(
        product: product,
        name: product.name,
        isCatalogProduct: true,
        isServiceItem: product.isService,
        quantity: 1,
        unitPrice: product.price,
        location: defaultLocation,
        notes: null,
        wizardProfile: wizardProfile,
      ));
      _partAutocompleteKey++; // Reset autocomplete field
    });
    unawaited(_loadPartChangeContext(products: [product]));
  }

  /// Qué escribió cada línea del trabajo en la ficha, según el servidor.
  Future<void> _loadPartChangeWriters() async {
    final jobId = _existingJob?.id;
    if (jobId == null || jobId.isEmpty) return;
    final writers = await loadPartChangeWriters(jobId);
    if (!mounted || _existingJob?.id != jobId) return;
    setState(() => _partChangeWriters = writers);
  }

  /// Lee la relación (una vez por sesión) y la ficha técnica de los
  /// repuestos que faltan: los de [products], o los de todas las líneas.
  Future<void> _loadPartChangeContext({Iterable<Product?>? products}) async {
    final links = await BikeFactSpecLinks.load();
    if (!mounted) return;
    if (!identical(links, _bikeFactSpecLinks)) {
      setState(() => _bikeFactSpecLinks = links);
    }
    if (links == null || links.isEmpty) return;
    if (products == null) unawaited(_loadPartChangeWriters());

    final candidates = products ??
        [
          for (final tab in _bikeTabs)
            for (final item in tab.partItems)
              if (!item.isServiceItem) item.product,
          for (final item in _partItems)
            if (!item.isServiceItem) item.product,
        ];
    final missing = <String, Product>{
      for (final product in candidates)
        if (product != null &&
            !product.isService &&
            !_partSpecValues.containsKey(product.id))
          product.id: product,
    };
    if (missing.isEmpty) return;
    try {
      final values = await _bikeProductCompatibilityService.productSpecValues(
        products: missing.values.toList(growable: false),
        tenantId: await TenantService().getTenantId() ?? '',
      );
      if (!mounted) return;
      setState(() => _partSpecValues.addAll(values));
    } catch (error) {
      // Sin la ficha técnica la línea no propone nada y, al guardar,
      // conserva la marca que tenía.
      debugPrint(
          '⚠️ Ficha técnica de repuestos para la ficha de la bici: $error');
    }
  }

  /// Los cambios de ficha que propone una línea de repuesto, con la ficha de
  /// la bici de la línea y las marcas que el mecánico ya confirmó en ella. La
  /// bici es la de `job_line_bike_internal`: la de su pestaña; en General, la
  /// única bici del trabajo; con varias (o sin bicis), ninguna: el chip pide
  /// asignar la línea a su bici («Asignar a…») y no deja marca, porque al
  /// terminar el servidor no escribiría (`line_without_bike`). Así el chip no
  /// promete lo que el servidor rechazará (revisión de Codex, 2026-09-28).
  /// Lo que el mismo trabajo instala en esa bici (la maza, el Enrayado o la
  /// llanta de cada rueda) manda sobre la ficha, como en el servidor
  /// (20260928130000).
  List<PartBikeFactChange> _partChangesFor(JobPartItem item) {
    final links = _bikeFactSpecLinks;
    final product = item.product;
    if (links == null ||
        links.isEmpty ||
        item.isServiceItem ||
        product == null) {
      return const [];
    }
    final specs = _partSpecValues[product.id];
    if (specs == null) return const [];
    final physicalTabs =
        _bikeTabs.where((tab) => !tab.isGeneralTab).toList(growable: false);
    final currentTab = _currentBikeTab;
    final tab = currentTab != null &&
            currentTab.isGeneralTab &&
            physicalTabs.length == 1
        ? physicalTabs.single
        : currentTab;
    final profile = tab == null || tab.isGeneralTab
        ? null
        : _pendingBikeProfileForBike(tab.bike) ??
            (_selectedBike?.id == tab.bike?.id ? _selectedBikeProfile : null);
    final bike = tab == null || tab.isGeneralTab ? null : tab.bike;
    // Las otras líneas de esa bici: las de su pestaña y, cuando el trabajo
    // tiene una sola bici, las de General.
    final others = [
      if (tab != null && !tab.isGeneralTab) ...tab.partItems,
      if (physicalTabs.length == 1 || tab == null || tab.isGeneralTab)
        for (final general in _bikeTabs.where((t) => t.isGeneralTab))
          ...general.partItems,
      if (_bikeTabs.isEmpty) ..._partItems,
    ].where((other) => other.id != item.id);
    return partBikeFactChanges(
      links: links,
      productSpecValues: specs,
      location: item.location,
      confirmedMarker: item.partChange,
      writtenMarker: _partChangeWriters[item.id],
      bikeValues: profile?.technicalValues ?? const {},
      bikeConfirmed: profile?.technicalConfirmed ?? const {},
      bikeSources: profile?.technicalSources ?? const {},
      bikeWheelSize: bike?.wheelSize,
      bikeHubSpacingMm: {
        if (bike?.frontHubSpacingMm case final front?)
          BikeMemoryLocation.front: front,
        if (bike?.rearHubSpacingMm case final rear?)
          BikeMemoryLocation.rear: rear,
      },
      // Una maza o un mando trasero en las líneas de esa bici deciden el
      // driver o la transmisión; la maza, el Enrayado o la llanta de una
      // rueda, lo que se cruza con ella.
      job: jobWheelParts([
        for (final other in others)
          if (other.isServiceItem)
            (
              location: other.location,
              specs: null,
              holeCount: _enrayadoHoles(other),
              buildWheel: switch (other.wizardAnswers?['which_wheel']) {
                'front' => BikeMemoryLocation.front,
                'rear' => BikeMemoryLocation.rear,
                _ => null,
              },
            )
          else if (other.product != null)
            (
              location: other.location,
              specs: _partSpecValues[other.product!.id],
              holeCount: null,
              buildWheel: null,
            ),
      ], links),
      lineBike: partLineBike(
        inBikeTab: currentTab != null && !currentTab.isGeneralTab,
        bikeCount: physicalTabs.length,
      ),
      jobFinished: _existingJob?.status == JobStatus.finalizado ||
          _existingJob?.status == JobStatus.entregado,
    );
  }

  /// Las perforaciones que armó un Enrayado (`hole_count`), como las lee el
  /// servidor: el texto tal cual, un entero de 12 a 48 (fuera de ese rango es
  /// un error de tipeo, y un texto con espacios el servidor no lo lee).
  static int? _enrayadoHoles(JobPartItem item) {
    final text = item.wizardAnswers?['hole_count']?.toString();
    if (text == null || !RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(text)) {
      return null;
    }
    final holes = int.parse(text);
    return holes >= 12 && holes <= 48 ? holes : null;
  }

  /// «Asignar a <bici>» para una línea de General en un trabajo con varias
  /// bicis: ahí no es de ninguna y al terminar no cambiaría ninguna ficha
  /// (`line_without_bike`). Una protegida no tiene menú; una que se está
  /// configurando espera a que se cierre «Configurar», y mientras se guarda
  /// espera al recibo: el comando ya lleva la línea donde estaba (revisión de
  /// Codex, 2026-09-28).
  List<({String label, VoidCallback? onSelected})> _assignTargetsFor(
    JobPartItem item,
  ) {
    final currentTab = _currentBikeTab;
    if (currentTab == null ||
        !currentTab.isGeneralTab ||
        _isCommercialSnapshotLocked) {
      return const [];
    }
    final targets = [
      for (final (index, tab) in _bikeTabs.indexed)
        if (!tab.isGeneralTab) (index: index, tab: tab),
    ];
    if (targets.length < 2) return const [];
    final waiting = _configuringItemId == item.id || _isSaving;
    return [
      for (final target in targets)
        (
          label: 'Asignar a ${target.tab.displayName}',
          onSelected:
              waiting ? null : () => _assignLineToBike(item.id, target.index),
        ),
    ];
  }

  /// Pasa la misma línea (su id, precio y datos) a la pestaña de la bici; lo
  /// que había confirmado para la ficha se vuelve a confirmar ahí.
  void _assignLineToBike(String itemId, int tabIndex) {
    final general = _currentBikeTab;
    if (_isSaving ||
        general == null ||
        !general.isGeneralTab ||
        _isCommercialSnapshotLocked ||
        tabIndex < 0 ||
        tabIndex >= _bikeTabs.length ||
        _bikeTabs[tabIndex].isGeneralTab) {
      return;
    }
    final target = _bikeTabs[tabIndex];
    final hadPartChange = general.partItems
        .any((item) => item.id == itemId && item.partChange != null);
    JobPartItem? moved;
    setState(() {
      moved = assignJobLineToBike(
        general: general.partItems,
        bikeLines: target.partItems,
        itemId: itemId,
      );
      // Los índices de General cambiaron: el detalle lateral se cierra.
      _selectedServiceIndex = null;
    });
    final line = moved;
    if (line == null || !mounted) return;
    void showTarget() {
      final index = _bikeTabs.indexOf(target);
      if (!mounted || index < 0) return;
      setState(() {
        _selectedBikeTabIndex = index;
        _selectedBike = target.bike;
      });
      unawaited(_loadSelectedBikeProfile(_selectedBike));
    }

    // General vacía se esconde: quedarse ahí dejaba la vista sin pestaña
    // (visto en la app, 2026-09-28). Con otras líneas se sigue en General
    // para asignar las demás, y el aviso lleva a la bici.
    final generalEmptied = general.partItems.isEmpty;
    if (generalEmptied) showTarget();
    // Asignar varias seguidas: cada aviso reemplaza a los anteriores (el
    // visible y los en cola), que ya no dicen dónde está la vista.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          '«${line.name}» quedó en ${target.displayName}.'
          '${hadPartChange ? ' Confirma ahí su cambio de ficha.' : ''}',
        ),
        action: generalEmptied
            ? null
            : SnackBarAction(
                label: 'Ver ${target.displayName}',
                onPressed: showTarget,
              ),
        // Con acción, Flutter 3.38 lo deja fijo hasta cerrarlo: seguía
        // abajo después de salir del trabajo.
        persist: false,
      ));
  }

  /// El mecánico elige (o vuelve a elegir) la rueda de un repuesto que
  /// cambia la ficha: eso confirma el cambio y deja la marca en la línea.
  void _choosePartWheel(int itemIndex, BikeMemoryLocation location) {
    final moved = _currentPartItems[itemIndex].copyWith(
      location: location,
      clearPartChange: true,
    );
    // Todos los datos que la pieza cambia en esa rueda (una maza trasera, su
    // driver y su anclaje), cada uno con su marca.
    final marker = partChangeMarkerJson([
      for (final change in _partChangesFor(moved)) change.marker,
    ]);
    setState(() {
      _currentPartItems[itemIndex] = moved.copyWith(partChange: marker);
    });
  }

  /// La marca que guarda la línea: la que confirmó el mecánico, mientras
  /// siga calzando con el repuesto y la rueda de la línea. Si ya no calza (se
  /// corrigió la ficha técnica del producto) se suelta y la línea vuelve a
  /// pedir confirmación; si no se pudo leer la relación o la ficha técnica,
  /// o la línea está protegida, se conserva tal cual. Una marca que ya tenía
  /// una línea que quedó en General de un trabajo con varias bicis también se
  /// conserva: al terminar, el servidor la informa (`line_without_bike`) en
  /// vez de callar; lo que no hace el formulario es crear una nueva ahí.
  Object? _partChangeMarkerForSave(JobPartItem item) {
    if (item.isServiceItem) return null;
    final marker = item.partChange;
    if (marker == null || _isCommercialSnapshotLocked) return marker;
    final links = _bikeFactSpecLinks;
    final product = item.product;
    final specs = product == null ? null : _partSpecValues[product.id];
    if (links == null || links.isEmpty || specs == null) return marker;
    // Cada marca por su clave: se conserva la que todavía calza.
    final current = [
      for (final change in partBikeFactChanges(
        links: links,
        productSpecValues: specs,
        location: item.location,
      ))
        if (change.marker case final mark?) mark,
    ];
    return partChangeMarkerJson([
      for (final mark in partChangeMarks(marker))
        if (current.any((valid) => samePartChangeMarker(valid, mark))) mark,
    ]);
  }

  void _addCustomPart(String description) {
    // Ad-hoc part with no product reference
    setState(() {
      _currentPartItems.add(JobPartItem(
        product: null,
        name: description,
        isCatalogProduct: false,
        isServiceItem: false,
        quantity: 1,
        unitPrice: 0, // User must enter price manually
        notes: null,
      ));
      _partAutocompleteKey++; // Reset autocomplete field
    });
  }

  // ignore: unused_element
  void _addEmptyPartLine() {
    // Add an empty line for the user to fill in
    setState(() {
      _currentPartItems.add(JobPartItem(
        product: null,
        name: '',
        isCatalogProduct: false,
        isServiceItem: false,
        quantity: 1,
        unitPrice: 0,
        notes: null,
      ));
    });
  }

  void _addServiceItem() {
    showDialog(
      context: context,
      builder: (context) => _ServiceEntryDialog(
        serviceProducts: _serviceProducts,
        onServiceAdded: (serviceProduct, description, hours, rate, date) {
          setState(() {
            final trimmedDescription = description.trim();
            _serviceItems.add(_JobServiceItem(
              serviceProduct: serviceProduct,
              description: trimmedDescription.isNotEmpty
                  ? trimmedDescription
                  : serviceProduct?.name ?? '',
              hours: hours,
              hourlyRate: rate,
              date: date,
            ));
          });
        },
      ),
    );
  }

  // ignore: unused_element
  void _focusPartAutocomplete() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_partAutocompleteFocus);
    });
  }

  /// Total parts cost across all bikes (multi-bike support)
  double get _partsCost {
    // If using multi-bike tabs, sum from all bike tabs
    if (_bikeTabs.isNotEmpty) {
      return _bikeTabs.fold(0.0, (sum, tab) {
        return sum +
            tab.partItems.fold(0.0,
                (itemSum, item) => itemSum + (item.quantity * item.unitPrice));
      });
    }
    // Legacy single-bike mode
    return _partItems.fold(
        0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }

  /// Get subtotal for current bike tab only (for display in chip)
  // ignore: unused_element
  double get _currentBikeSubtotal {
    final tab = _currentBikeTab;
    if (tab != null) {
      return tab.partItems
          .fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
    }
    return _partItems.fold(
        0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }

  double get _serviceCost {
    return _serviceItems.fold(0.0, (sum, item) => sum + item.total);
  }

  double get _subtotal {
    return _partsCost + _serviceCost;
  }

  double get _discountAmount {
    return double.tryParse(_discountController.text) ?? 0.0;
  }

  double get _total {
    // Total is ALWAYS subtotal - discount (customer pays this)
    return _subtotal - _discountAmount;
  }

  bool get _hasSaleCatalogProduct => _partItems.any(
        (item) =>
            item.isCatalogProduct &&
            !item.isServiceItem &&
            item.product?.id.isNotEmpty == true,
      );

  bool get _saleHasUnsupportedLines =>
      _serviceItems.isNotEmpty ||
      _partItems.any(
        (item) =>
            item.isServiceItem ||
            !item.isCatalogProduct ||
            item.product?.id.isNotEmpty != true,
      );

  int get _debugLocalPersistablePartCount {
    return _bikeTabs.fold<int>(0, (sum, tab) {
      return sum +
          tab.partItems
              .where((item) => item.displayName.trim().isNotEmpty)
              .length;
    });
  }

  int get _debugLocalPersistableServiceCount {
    return _serviceItems
        .where((item) => item.displayName.trim().isNotEmpty)
        .length;
  }

  String _debugSummarizeLabels(Iterable<String> labels) {
    final cleaned = labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    if (cleaned.isEmpty) {
      return '-';
    }

    const maxLabels = 5;
    if (cleaned.length <= maxLabels) {
      return cleaned.join(' | ');
    }

    final remaining = cleaned.length - maxLabels;
    return '${cleaned.take(maxLabels).join(' | ')} | +$remaining más';
  }

  Future<void> _debugLogPegaInvoiceSnapshot(
    String stage, {
    required String jobId,
    String? invoiceId,
  }) async {
    if (!kDebugMode) {
      return;
    }

    try {
      final bikeshopService = Provider.of<BikeshopService>(
        context,
        listen: false,
      );
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );

      final savedJob = await bikeshopService.getJobById(jobId);
      final persistedItems = await bikeshopService.getJobItems(jobId);
      final effectiveInvoiceId = invoiceId ?? savedJob?.invoiceId;

      List<dynamic> invoiceItems = const [];
      dynamic invoiceSubtotal;
      dynamic invoiceTotal;

      if (effectiveInvoiceId != null) {
        final invoiceData = await databaseService.selectById(
          'sales_invoices',
          effectiveInvoiceId,
        );
        if (invoiceData != null) {
          final rawItems = invoiceData['items'];
          if (rawItems is List) {
            invoiceItems = rawItems;
          }
          invoiceSubtotal = invoiceData['subtotal'];
          invoiceTotal = invoiceData['total'];
        }
      }

      final localLabels = <String>[
        ..._bikeTabs.expand(
          (tab) => tab.partItems.map((item) => item.displayName),
        ),
        ..._serviceItems.map((item) => item.displayName),
      ];
      final persistedLabels = persistedItems.map((item) => item.productName);
      final invoiceLabels = invoiceItems.map((item) {
        if (item is Map) {
          return (item['product_name'] ?? '').toString();
        }
        return '';
      });

      debugPrint(
        '🧪 [PEGA SAVE][$stage] '
        'job=$jobId '
        'invoice=${effectiveInvoiceId ?? '-'} '
        'local_parts=$_debugLocalPersistablePartCount '
        'local_services=$_debugLocalPersistableServiceCount '
        'persisted_items=${persistedItems.length} '
        'job_total=${savedJob?.totalCost} '
        'invoice_items=${invoiceItems.length} '
        'invoice_subtotal=$invoiceSubtotal '
        'invoice_total=$invoiceTotal',
      );
      debugPrint(
        '🧪 [PEGA SAVE][$stage] local_labels=${_debugSummarizeLabels(localLabels)}',
      );
      debugPrint(
        '🧪 [PEGA SAVE][$stage] persisted_labels=${_debugSummarizeLabels(persistedLabels)}',
      );
      debugPrint(
        '🧪 [PEGA SAVE][$stage] invoice_labels=${_debugSummarizeLabels(invoiceLabels)}',
      );
    } catch (e) {
      debugPrint('🧪 [PEGA SAVE][$stage] debug snapshot failed: $e');
    }
  }

  void _handleCancel() {
    if (_isSaving) return;
    unawaited(_handleInlineWorkspaceCancel());
  }

  void _captureInlineDraftBaseline() {
    if (_isLoading || _existingJobLoadError != null) {
      return;
    }
    _inlineDraftBaselineFingerprint = _buildInlineDraftFingerprint();
  }

  bool get _inlineDraftHasUnsavedChanges {
    final baseline = _inlineDraftBaselineFingerprint;
    return baseline != null && baseline != _buildInlineDraftFingerprint();
  }

  Future<void> _handleInlineWorkspaceCancel() async {
    if (_isSaving || _isInlineDiscardPromptOpen) return;

    if (_inlineDraftHasUnsavedChanges) {
      _isInlineDiscardPromptOpen = true;
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (_) => const MechanicJobDiscardDialog(),
      );
      _isInlineDiscardPromptOpen = false;
      if (!mounted || shouldDiscard != true || _isSaving) return;
    }

    await _completeCancelNavigation();
  }

  Future<void> _completeCancelNavigation() async {
    if (widget.isEmbedded) {
      widget.onCanceled?.call();
      return;
    }
    await _leaveRoutedForm();
  }

  Future<void> _leaveRoutedForm({Object? result}) async {
    if (!mounted) return;
    if (!context.canPop()) {
      context.go('/taller/pegas');
      return;
    }

    setState(() {
      _allowRoutePop = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    context.pop(result);
  }

  String _buildInlineDraftFingerprint() {
    final draft = <String, Object?>{
      'customer_id': _selectedCustomer?.id,
      'selected_bike_id': _selectedBike?.id,
      'job_type': _jobType.name,
      'service_commercial_path': _serviceCommercialPath.name,
      'subject_id': _selectedSubject?.id,
      'subject_notes': _subjectNotesController.text.trim(),
      'warranty_source_job_id': _selectedWarrantySource?.jobId,
      'warranty_outcome': _warrantyOutcome?.name,
      'warranty_reason': _warrantyDecisionReasonController.text.trim(),
      'quotation_status': _quotationStatus?.name,
      'quotation_valid_until': _quotationValidUntil,
      'priority': _selectedPriority.name,
      'status': _selectedStatus.name,
      'custom_status_id': _selectedCustomStatus?.id,
      'arrival_date': _selectedArrivalDate,
      'delivery_deadline': _selectedDeadline,
      'requires_approval': _requiresApproval,
      'tax_treatment': _taxTreatment.name,
      'discount': _discountAmount,
      'estimated_duration_hours':
          _inlineDraftNumber(_estimatedDurationController),
      'actual_labor_hours': _inlineDraftNumber(_actualLaborHoursController),
      'legacy_narrative': {
        'client_request': _clientRequestController.text.trim(),
        'diagnosis': _diagnosisController.text.trim(),
        'work_summary': _workSummaryController.text.trim(),
        'technician_notes': _technicianNotesController.text.trim(),
      },
      'bike_tabs': _bikeTabs.map(_inlineBikeTabDraft).toList(growable: false),
      'standalone_items':
          _partItems.map(_inlinePartDraft).toList(growable: false),
      'services':
          _serviceItems.map(_inlineServiceDraft).toList(growable: false),
      'image_urls': List<String>.from(_imageUrls),
      'new_images': _newImages
          .map(
            (image) => {
              'name': image.name,
              'length': image.bytes.length,
            },
          )
          .toList(growable: false),
      'pending_bike_profiles': _pendingBikeProfileOverrides.map(
        (bikeId, profile) => MapEntry(bikeId, profile.toJson()),
      ),
      'pending_wizard_answers': _pendingServiceWizardAnswers,
    };

    return jsonEncode(_canonicalInlineDraftValue(draft));
  }

  double? _inlineDraftNumber(TextEditingController controller) {
    return double.tryParse(
      controller.text.trim().replaceAll(',', '.'),
    );
  }

  Map<String, Object?> _inlineBikeTabDraft(_BikeTabData tab) {
    return {
      'tab_id': tab.tabId,
      'job_bike_id': tab.jobBikeId,
      'bike_id': tab.bike?.id,
      'is_general': tab.isGeneralTab,
      'client_request': tab.clientRequestController.text.trim(),
      'diagnosis': tab.diagnosisController.text.trim(),
      'work_requested': tab.workRequestedController.text.trim(),
      'technician_notes': tab.technicianNotesController.text.trim(),
      'diagnosis_sheet': tab.diagnosisSheet.toJson(),
      'is_warranty_work': tab.isWarrantyWork,
      'requires_approval': tab.requiresApproval,
      'approved_by_customer': tab.approvedByCustomer,
      'items': tab.partItems.map(_inlinePartDraft).toList(growable: false),
    };
  }

  Map<String, Object?> _inlinePartDraft(JobPartItem item) {
    return {
      'id': item.id,
      'product_id': item.product?.id,
      'name': item.name.trim(),
      'is_catalog_product': item.isCatalogProduct,
      'is_service_item': item.isServiceItem,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'location': item.location.name,
      'notes': item.notes?.trim(),
      'wizard_answers': _effectiveWizardAnswersForItem(item),
    };
  }

  Map<String, Object?> _inlineServiceDraft(_JobServiceItem item) {
    return {
      'id': item.id,
      'product_id': item.serviceProduct?.id,
      'description': item.description.trim(),
      'hours': item.hours,
      'hourly_rate': item.hourlyRate,
      'date': item.date,
    };
  }

  Object? _canonicalInlineDraftValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Enum) {
      return value.name;
    }
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return <String, Object?>{
        for (final entry in entries)
          entry.key: _canonicalInlineDraftValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value
          .map<Object?>((item) => _canonicalInlineDraftValue(item))
          .toList(growable: false);
    }
    return value.toString();
  }

  Future<bool> _confirmDiagnosisOnlyAfterFinancialStateChange() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('La factura cambió mientras editabas'),
        content: Text(
          _jobType == JobType.sale
              ? _linkedInvoiceHasActivePayments
                  ? 'Se registró un abono en la factura vinculada. Para proteger el historial financiero no se guardarán cambios de productos, precios ni descuento. Sí puedes guardar la nota del acuerdo de pago.'
                  : 'No se pudo verificar de forma confiable el estado de pago. Por seguridad no se guardarán cambios comerciales. Sí puedes guardar la nota del acuerdo de pago.'
              : _linkedInvoiceHasActivePayments
                  ? 'Se registró un pago en la factura vinculada. Para proteger el historial financiero no se guardarán cambios de productos, precios, descuento, estado ni objeto físico. Sí puedes guardar el diagnóstico y las notas operativas.'
                  : _linkedInvoiceIsPosted
                      ? 'La factura ${_linkedInvoiceNumber ?? 'vinculada'} se confirmó mientras editabas. Lo que se cobra (productos, precios, descuento) se corrige ahora desde la factura, que rehace stock y contabilidad. Sí puedes guardar el diagnóstico y las notas operativas.'
                      : 'No se pudo verificar de forma confiable el estado de pago. Por seguridad no se guardarán cambios comerciales ni de ciclo. Sí puedes guardar el diagnóstico y las notas operativas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Volver sin guardar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _jobType == JobType.sale
                  ? 'Guardar solo nota'
                  : 'Guardar solo diagnóstico',
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _revealFormIssue(
    _MechanicJobFormIssueOwner owner,
    String message,
  ) {
    final nextWorkbenchTab = switch (owner) {
      _MechanicJobFormIssueOwner.general => _JobWorkbenchTab.general,
      _MechanicJobFormIssueOwner.products => _JobWorkbenchTab.products,
      _MechanicJobFormIssueOwner.customer ||
      _MechanicJobFormIssueOwner.costSummary =>
        null,
    };
    if (nextWorkbenchTab != null && nextWorkbenchTab != _selectedWorkbenchTab) {
      setState(() {
        _selectedWorkbenchTab = nextWorkbenchTab;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final targetContext = switch (owner) {
        _MechanicJobFormIssueOwner.customer =>
          _customerSectionKey.currentContext,
        _MechanicJobFormIssueOwner.general ||
        _MechanicJobFormIssueOwner.products =>
          _workbenchSectionKey.currentContext,
        _MechanicJobFormIssueOwner.costSummary =>
          _costSummarySectionKey.currentContext,
      };
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: 0.04,
        );
      }
      if (!mounted) return;
      switch (owner) {
        case _MechanicJobFormIssueOwner.products:
          _partAutocompleteFocus.requestFocus();
        case _MechanicJobFormIssueOwner.costSummary:
          _discountFocusNode.requestFocus();
        case _MechanicJobFormIssueOwner.customer:
        case _MechanicJobFormIssueOwner.general:
          break;
      }
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _saveJob() async {
    if (_canSaveJob &&
        _configuringItemId != null &&
        _configuringDraft != null) {
      final keepEditing = await _confirmUnappliedConfiguration(
        continueLabel: 'Guardar sin aplicarla',
      );
      if (!mounted || keepEditing) return;
    }
    if (!_canSaveJob) {
      if (_hasBlockingWarrantyLoadFailure || _existingJobLoadError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La ficha todavía no tiene una lectura completa y confiable. Reintenta la carga antes de guardar.',
            ),
          ),
        );
      }
      return;
    }

    if (_isFinalQuotationReadOnly) {
      final proposalLabel =
          _existingJob?.proposalDocumentLabel ?? _proposalDocumentLabel;
      final proposalSubject = proposalLabel == 'Presupuesto'
          ? 'Este presupuesto'
          : 'Esta cotización';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$proposalSubject está en solo lectura. Gestiona su estado desde la tabla de trabajos.',
          ),
        ),
      );
      return;
    }

    if (_selectedCustomer == null) {
      setState(() {
        _hasAttemptedSave = true;
      });
      _revealFormIssue(
        _MechanicJobFormIssueOwner.customer,
        'Selecciona un cliente para continuar.',
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _hasAttemptedSave = true;
      });
      _revealFormIssue(
        _MechanicJobFormIssueOwner.costSummary,
        'Revisa el descuento antes de guardar.',
      );
      return;
    }

    final selectedWarrantyObject = _selectedWarrantySource?.physicalObject;
    final warrantyBikeId = selectedWarrantyObject?.isBike == true
        ? selectedWarrantyObject?.bikeId
        : (_selectedWarrantySource == null ? _existingJob?.bikeId : null);
    final requiresBike = _jobType == JobType.service ||
        (_jobType == JobType.warranty && warrantyBikeId != null);

    // Bike-based service/warranty jobs require a bicycle. Component-only
    // warranty claims inherit their subject from the original work instead.
    if (requiresBike && _bikeTabs.isEmpty) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.customer,
        'Selecciona al menos una bicicleta para continuar.',
      );
      return;
    }

    if (_jobType == JobType.warranty &&
        _warrantySaveCheckpoint.requiresSourceSelection &&
        _selectedWarrantySource == null) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.general,
        'Selecciona el trabajo original de la garantía.',
      );
      return;
    }

    final warrantySource = _selectedWarrantySource;
    if (_jobType == JobType.warranty && warrantySource != null) {
      final object = warrantySource.physicalObject;
      if (_isLoadingWarrantySourceObject) {
        _revealFormIssue(
          _MechanicJobFormIssueOwner.general,
          'Espera a que se confirme el objeto del trabajo original.',
        );
        return;
      }
      if (_warrantySourceObjectError != null || !object.isValid) {
        _revealFormIssue(
          _MechanicJobFormIssueOwner.general,
          _warrantySourceObjectError ??
              'Clasifica primero la recepción del trabajo original.',
        );
        return;
      }
      if (!_warrantySourceObjectMatchesForm(warrantySource)) {
        _revealFormIssue(
          _MechanicJobFormIssueOwner.general,
          'El objeto de la garantía no coincide con el trabajo original. Vuelve a seleccionarlo.',
        );
        return;
      }
    }

    final desiredWarrantyOutcome = _warrantyOutcome ?? WarrantyOutcome.pending;
    final willRegisterWarrantyClaim = _jobType == JobType.warranty &&
        _warrantySaveCheckpoint.needsRegistration(
          _selectedWarrantySource?.jobId,
        );
    // Registration atomically normalizes the persisted outcome to pending.
    // Use that authoritative post-registration state for reason validation;
    // otherwise a legacy covered/not-covered mirror with no claim event could
    // skip the decision that must be re-issued after linking its source.
    final persistedWarrantyOutcome = willRegisterWarrantyClaim
        ? WarrantyOutcome.pending
        : _warrantySaveCheckpoint.confirmedOutcome ??
            _existingJob?.warrantyOutcome ??
            _warrantyClaim?.outcome ??
            WarrantyOutcome.pending;
    final warrantyDecisionNeedsReason =
        desiredWarrantyOutcome != persistedWarrantyOutcome &&
            (desiredWarrantyOutcome == WarrantyOutcome.notCovered ||
                (desiredWarrantyOutcome == WarrantyOutcome.covered &&
                    _warrantyCoverageNeedsReason(_selectedWarrantySource)));
    if (_jobType == JobType.warranty &&
        warrantyDecisionNeedsReason &&
        _warrantyDecisionReasonController.text.trim().isEmpty) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.general,
        'Ingresa la justificación de la decisión de garantía.',
      );
      return;
    }

    if (_jobType == JobType.itemService &&
        _selectedSubject == null &&
        _subjectNotesController.text.trim().isEmpty) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.customer,
        'Selecciona un componente del catálogo o descríbelo manualmente.',
      );
      return;
    }

    if (_jobType == JobType.quotation &&
        _subjectNotesController.text.trim().isEmpty) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.customer,
        'Describe qué producto o servicio deseas cotizar.',
      );
      return;
    }

    if (_jobType == JobType.sale && !_hasSaleCatalogProduct) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.products,
        'Agrega al menos un producto del catálogo para registrar la venta.',
      );
      return;
    }
    if (_jobType == JobType.sale && _saleHasUnsupportedLines) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.products,
        'La venta solo admite productos del catálogo; quita servicios o líneas personalizadas.',
      );
      return;
    }

    // Guardar las líneas de esa bici sin su dato dejaría la línea configurada
    // y la ficha diciendo otra cosa (revisión de Codex, 2026-09-28).
    final awaitingReconfirmation = _bikesAwaitingReconfirmation();
    if (awaitingReconfirmation.isNotEmpty) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.products,
        awaitingReconfirmation.join(' '),
      );
      return;
    }

    // Una cantidad borrada o a medio escribir no se guarda como otra.
    final incompleteQuantities = _linesWithIncompleteQuantity();
    if (incompleteQuantities.isNotEmpty) {
      _revealFormIssue(
        _MechanicJobFormIssueOwner.products,
        'Escribe la cantidad de ${incompleteQuantities.join(', ')}.',
      );
      return;
    }

    var protectPaymentCommercialSnapshot =
        _isPaymentProtectedCommercialSnapshotLocked;
    final wasPaymentProtectedAtSaveStart = protectPaymentCommercialSnapshot;
    var requestedDiscountAmount = protectPaymentCommercialSnapshot
        ? (_existingJob?.discountAmount ?? 0)
        : _discountAmount;

    String? persistedJobId;
    var warrantyDecisionManagedDocument = false;

    setState(() {
      _isSaving = true;
    });

    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      // Un guardado de líneas anterior que quedó sin respuesta se resuelve
      // antes de escribir nada: si llegó, este guardado parte de su recibo; si
      // sigue sin respuesta, no se escribe encima (ítem 4).
      await _settlePendingLineSave(bikeshopService);
      if (!mounted) return;
      // Y una decisión de garantía de este trabajo que sigue en la bandeja
      // (de este formulario o de la tabla): va antes que las líneas nuevas,
      // y si se aplica, este guardado lleva su factura al día (punto 2 del
      // cierre, 2026-09-29).
      await _settlePendingWarrantyDecision(bikeshopService);
      if (!mounted) return;
      // El trabajo guardado: el que se abrió, o el nuevo cuya alta ya tiene
      // recibo (también la de un intento anterior de este formulario).
      final savedJobId = _savedJobId;

      // Una promoción a la ficha sólo viaja con una bici que este guardado deja
      // en el trabajo. La de una pestaña retirada haría fallar la ficha después
      // de guardar el trabajo (Codex, 2026-09-27).
      final keptBikeIds = {
        for (final tab in _bikeTabs)
          if (!tab.isGeneralTab && tab.bike?.id != null) tab.bike!.id!,
      };
      for (final bikeId in _pendingBikeProfileOverrides.keys.toList()) {
        if (!keptBikeIds.contains(bikeId)) {
          _discardPendingBikeProfilePromotion(bikeId);
        }
      }

      // Close the load-to-save race as much as the client can: payments may be
      // registered by another worker while this form remains open. Re-read the
      // invoice and active payment ledger after the save button is disabled and
      // before any profile, job, line, invoice, stock or journal-affecting write.
      final existingJob = _existingJob;
      if (existingJob?.invoiceId != null) {
        final databaseService =
            Provider.of<DatabaseService>(context, listen: false);
        final linkedInvoiceState = await _readLinkedInvoiceFinancialState(
          databaseService: databaseService,
          job: existingJob!,
        );
        if (!mounted) return;
        _linkedInvoiceNumber = linkedInvoiceState.invoiceNumber;
        _linkedInvoiceHasActivePayments = linkedInvoiceState.hasActivePayments;
        _linkedInvoicePaymentStateUnknown =
            linkedInvoiceState.paymentStateUnknown;
        _linkedInvoiceIsPosted = linkedInvoiceState.isPosted;
        protectPaymentCommercialSnapshot =
            _isPaymentProtectedCommercialSnapshotLocked;
        requestedDiscountAmount = protectPaymentCommercialSnapshot
            ? (existingJob.discountAmount)
            : _discountAmount;
      }

      if (!wasPaymentProtectedAtSaveStart &&
          protectPaymentCommercialSnapshot &&
          !await _confirmDiagnosisOnlyAfterFinancialStateChange()) {
        return;
      }
      if (!mounted) return;

      if (_jobType == JobType.warranty &&
          desiredWarrantyOutcome == WarrantyOutcome.covered &&
          desiredWarrantyOutcome != persistedWarrantyOutcome &&
          _warrantyCoverageNeedsFinancialReview) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _linkedInvoiceHasActivePayments
                  ? 'Esta garantía tiene pagos vigentes. Revisa, revierte o reembolsa el pago desde la factura antes de marcarla como cubierta.'
                  : 'No se pudo confirmar el estado de pago de la factura. Recarga la ficha antes de marcar la garantía como cubierta.',
            ),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 10),
          ),
        );
        return;
      }

      if (!protectPaymentCommercialSnapshot &&
          (requestedDiscountAmount < 0 ||
              requestedDiscountAmount > _subtotal)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El descuento no puede superar el subtotal.'),
          ),
        );
        return;
      }

      // Cada adjunto va en job-images/<taller>/<trabajo>/<archivo al azar>,
      // con su extensión, y se anota en la bandeja antes de subirlo
      // (`uploadJobAttachment`): si el trabajo no se guarda, o la app se
      // cierra a mitad, la próxima sesión borra el que nadie reclama. Uno que
      // no sube detiene el guardado: antes el error se tragaba y el trabajo
      // se guardaba sin él.
      final uploadedUrls = List<String>.from(_imageUrls);
      final attachmentJobId = savedJobId ?? _newJobId;
      for (final imageData in List.of(_newImages)) {
        final String url;
        try {
          _imageScope ??= await bikeshopService.workshopCommandScope();
          _uploadedAttachments = true;
          url = await bikeshopService.uploadJobAttachment(
            jobId: attachmentJobId,
            bytes: imageData.bytes,
            fileName: imageData.name,
            ownerForm: _formInstanceId,
          );
        } on JobAttachmentNotAcceptedException catch (error) {
          throw _JobSaveStopped(error.toString());
        } catch (error) {
          debugPrint('Error uploading job attachment: $error');
          throw _JobSaveStopped(
            'No se pudo guardar el adjunto ${imageData.name}. El trabajo aún '
            'no fue enviado; vuelve a guardar.',
          );
        }
        uploadedUrls.add(url);
        // Ya subido: un reintento del guardado no lo vuelve a subir.
        if (mounted) {
          setState(() {
            _imageUrls.add(url);
            _newImages.remove(imageData);
          });
        }
      }

      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      // Use first bike as the "primary" bike for legacy compatibility
      final primaryBike = _bikeTabs.isNotEmpty ? _bikeTabs.first.bike : null;
      if (requiresBike && primaryBike?.id == null) {
        throw Exception('La primera bicicleta no tiene ID');
      }

      final mirror = _headerMirror(protect: protectPaymentCommercialSnapshot);

      // Create MechanicJob object (job-level data)
      final job = MechanicJob(
        id: savedJobId ?? _newJobId,
        tenantId: tenantId,
        jobNumber:
            _existingJob?.jobNumber ?? '', // Will be auto-generated if empty
        customerId: _selectedCustomer!.id!,
        bikeId: primaryBike?.id, // Nullable for non-bike jobs
        // Service budgets are presented as Servicio in the form, while the
        // deployed rolling-compatible database facade remains `quotation`
        // until the audited conversion command creates the invoice.
        jobType: mechanicJobPersistedJobType(
          jobType: _jobType,
          serviceCommercialPath: _serviceCommercialPath,
        ),
        // The physical object and commercial stage are independent. A normal
        // Servicio can therefore retain its bicycle/ficha/diagnosis while its
        // workflow remains a non-posting proposal until approval.
        workflowKind: _existingJob?.workflowKind ??
            mechanicJobCreationWorkflowKind(
              jobType: _jobType,
              serviceCommercialPath: _serviceCommercialPath,
            ),
        intakeKind: _existingJob?.intakeKind ??
            mechanicJobCreationIntakeKind(
              jobType: _jobType,
              bikeId: primaryBike?.id,
              subjectId: _selectedSubject?.id,
              subjectNotes: _subjectNotesController.text,
            ),
        modeNeedsReview: _existingJob?.modeNeedsReview,
        modeReviewReason: _existingJob?.modeReviewReason,
        subjectId:
            _jobType == JobType.itemService || _jobType == JobType.warranty
                ? _selectedSubject?.id ?? _selectedWarrantySource?.subjectId
                : null,
        subjectNotes: _subjectNotesController.text.isNotEmpty
            ? _subjectNotesController.text
            : null,
        warrantyOutcome: _jobType == JobType.warranty
            ? (_warrantySaveCheckpoint.confirmedOutcome ??
                _existingJob?.warrantyOutcome ??
                WarrantyOutcome.pending)
            : _warrantyOutcome,
        quotationStatus: _isProposalWorkflow ? _quotationStatus : null,
        quotationValidUntil: _isProposalWorkflow ? _quotationValidUntil : null,
        priority: _selectedPriority,
        // Covered-warranty lifecycle triggers post/reverse the internal
        // invoice from status/status_id. A diagnosis-only save must therefore
        // preserve both fields while financial evidence is protected.
        status: protectPaymentCommercialSnapshot
            ? (_existingJob?.status ?? _selectedStatus)
            : _selectedStatus,
        statusId: protectPaymentCommercialSnapshot
            ? _existingJob?.statusId
            : _selectedCustomStatus?.id,
        arrivalDate: _selectedArrivalDate,
        diagnosticDeadline: _existingJob?.diagnosticDeadline, // ✅ Preserve
        servicePackageId: _existingJob?.servicePackageId, // ✅ Preserve
        warrantyNotes: _existingJob?.warrantyNotes, // ✅ Preserve
        convertedAt: _existingJob?.convertedAt, // ✅ Preserve
        convertedFromId: _existingJob?.convertedFromId, // ✅ Preserve
        assignedTo: _existingJob?.assignedTo, // ✅ Preserve
        assignedTechnicianName:
            _existingJob?.assignedTechnicianName, // ✅ Preserve
        diagnosticSentAt: _existingJob?.diagnosticSentAt, // ✅ Preserve
        startedAt: _existingJob?.startedAt, // ✅ Preserve
        completedAt: _existingJob?.completedAt, // ✅ Preserve
        deliveredAt: _existingJob?.deliveredAt, // ✅ Preserve
        createdAt: _existingJob?.createdAt ?? DateTime.now(),
        // Store first bike's data in legacy fields for backward compat
        clientRequest: mirror['client_request'] as String?,
        diagnosis: mirror['diagnosis'] as String?,
        workPerformed: mirror['work_performed'] as String?,
        notes: mirror['notes'] as String?,
        deliveryDeadline: _jobType == JobType.sale
            ? _existingJob?.deliveryDeadline
            : _selectedDeadline,
        requiresApproval: mirror['requires_approval'] as bool,
        isWarrantyJob: mirror['is_warranty_job'] as bool,
        // A paid/part-paid linked invoice is immutable commercial evidence.
        // Keep its exact monetary mirrors while allowing diagnosis/header-safe
        // fields to save. Unpaid jobs apply discount after all line requests.
        discountAmount: protectPaymentCommercialSnapshot
            ? (_existingJob?.discountAmount ?? 0)
            : 0,
        estimatedDurationHours: double.tryParse(
          _estimatedDurationController.text.trim().replaceAll(',', '.'),
        ),
        actualLaborHours: double.tryParse(
          _actualLaborHoursController.text.trim().replaceAll(',', '.'),
        ),
        estimatedCost: protectPaymentCommercialSnapshot
            ? (_existingJob?.estimatedCost ?? 0)
            : 0,
        finalCost: protectPaymentCommercialSnapshot
            ? (_existingJob?.finalCost ?? 0)
            : 0,
        partsCost: protectPaymentCommercialSnapshot
            ? (_existingJob?.partsCost ?? 0)
            : 0,
        laborCost: protectPaymentCommercialSnapshot
            ? (_existingJob?.laborCost ?? 0)
            : 0,
        taxAmount: protectPaymentCommercialSnapshot
            ? (_existingJob?.taxAmount ?? 0)
            : 0,
        totalCost: protectPaymentCommercialSnapshot
            ? (_existingJob?.totalCost ?? 0)
            : 0,
        taxTreatment: protectPaymentCommercialSnapshot
            ? (_existingJob?.taxTreatment ?? _taxTreatment)
            : _taxTreatment,
        invoiceId: _existingJob?.invoiceId,
        isInvoiced: _existingJob?.isInvoiced ?? false,
        isPaid: _existingJob?.isPaid ?? false,
        imageUrls: uploadedUrls,
      );

      final String jobId;
      MechanicJob savedHeader;
      // El alta de un trabajo nuevo: no se envía aquí. Se respalda con sus
      // líneas (y lo que las sigue) en la bandeja antes del primer envío, y
      // sale primero (cierre del Master Schema, 2026-09-29). Antes se creaba
      // aquí, antes de respaldar nada: un cierre entre el alta y las líneas
      // dejaba un trabajo sin líneas ni factura.
      PendingWorkshopCommand? creation;

      if (savedJobId != null) {
        // La cabecera de un trabajo guardado ya no se reescribe entera aquí:
        // lo que cambió viaja con las líneas y la ficha en un solo comando.
        jobId = savedJobId;
        savedHeader = _existingJob ?? job;
        persistedJobId = jobId;
      } else {
        jobId = _newJobId;
        savedHeader = job;
        creation = bikeshopService.jobCreationCommand(
          job,
          label: _newJobCommandLabel(),
        );
        // Lo visto por sus líneas es lo que el alta deja: el descuento parte
        // del cero del alta.
        final created = creation.params['p_job'] as Map<String, dynamic>;
        _headerBaseline = {
          for (final column in mechanicJobFormHeaderColumns)
            column: created[column],
        };
      }

      // Sin la cabecera vista, un campo cambiado no tendría con qué
      // compararse y se perdería en silencio: mejor no guardar. (Un trabajo
      // nuevo la toma de su alta.)
      final missingHeader = savedJobId == null
          ? const <String>{}
          : mechanicJobFormHeaderColumns
              .difference(_headerBaseline.keys.toSet());
      if (missingHeader.isNotEmpty) {
        throw _JobSaveStopped(
          'No se leyó completa la cabecera del trabajo '
          '(${missingHeader.join(', ')}). Recárgalo antes de guardar.',
        );
      }

      // Lo que el formulario deja en la cabecera. Con pago, sólo lo que no es
      // comercial; sin pago, el descuento pedido (se aplica al final del
      // comando, con el subtotal ya nuevo).
      final editedHeader = protectPaymentCommercialSnapshot
          ? mechanicJobPaymentProtectedUpdatePayload(
              job.toJson(forUpdate: true),
            )
          : {
              ...job.toJson(forUpdate: true),
              'discount_amount': requestedDiscountAmount,
            };

      // La garantía se registra contra la cabecera guardada (cliente, bici,
      // componente): en un trabajo ya guardado, lo que cambió de ella va
      // antes, en su propio comando con recibo.
      if (_jobType == JobType.warranty &&
          savedJobId != null &&
          _warrantySaveCheckpoint
              .needsRegistration(_selectedWarrantySource?.jobId)) {
        final earlyHeader = jobHeaderPatch(
          seen: _headerBaseline,
          shown: _headerShown,
          edited: {...editedHeader}..remove('discount_amount'),
        );
        if (earlyHeader.isNotEmpty) {
          await _saveLinesWithBikeFacts(
            bikeshopService: bikeshopService,
            jobId: jobId,
            lines: null,
            header: earlyHeader,
            includeBikeFacts: false,
            label: _jobCommandLabel(savedHeader),
          );
        }
      }

      // Validate and register the warranty source before any line deletion or
      // inventory/invoice-affecting persistence. A server-side rejection can
      // now leave at most the recoverable job header, never a destructively
      // half-updated set of products/services.
      // En una garantía nueva el registro va detrás de sus líneas, en la
      // misma cadena que el alta: el trabajo original elegido sólo vive en
      // este formulario hasta registrarse, y el registro acepta la bici que
      // las líneas dejaron (la marca como trabajo de garantía).
      PendingWorkshopCommand? chainedRegistration;
      final registrationSourceJobId = _selectedWarrantySource?.jobId;
      if (_jobType == JobType.warranty &&
          _warrantySaveCheckpoint.needsRegistration(registrationSourceJobId)) {
        _pendingWarrantyRegistrationOperationKey ??= const Uuid().v4();
        if (savedJobId != null) {
          await bikeshopService.registerWarrantyClaim(
            warrantyJobId: jobId,
            sourceJobId: registrationSourceJobId!,
            operationKey: _pendingWarrantyRegistrationOperationKey!,
          );
          _warrantySaveCheckpoint.confirmRegistration(registrationSourceJobId);
        } else {
          chainedRegistration = bikeshopService.warrantyRegistrationCommand(
            warrantyJobId: jobId,
            sourceJobId: registrationSourceJobId!,
            operationKey: _pendingWarrantyRegistrationOperationKey!,
            label: _newJobCommandLabel(),
          );
        }
      }

      // ============================================================
      // MULTI-BIKE: Save each bike tab as MechanicJobBike + its items
      // ============================================================

      // Always re-read the aggregate after header/claim persistence. Claim
      // registration can create the canonical mechanic_job_bikes row even for
      // a brand-new warranty; assuming a new form still has an empty aggregate
      // would attempt to insert that same (job, bike) relationship twice.
      // Un trabajo nuevo todavía no tiene nada guardado: no hay qué releer.
      final existingItemsForSave = savedJobId == null
          ? const <MechanicJobItem>[]
          : await bikeshopService.getJobItems(jobId);
      final existingJobBikesForSave = savedJobId == null
          ? const <MechanicJobBike>[]
          : await bikeshopService.getJobBikes(jobId, forceRefresh: true);
      final existingItemById = <String, MechanicJobItem>{
        for (final item in existingItemsForSave)
          if (item.id != null && item.id!.isNotEmpty) item.id!: item,
      };

      final existingJobBikeById = <String, MechanicJobBike>{
        for (final jobBike in existingJobBikesForSave)
          if (jobBike.id != null && jobBike.id!.isNotEmpty)
            jobBike.id!: jobBike,
      };
      final existingJobBikeByBikeId = <String, MechanicJobBike>{
        for (final jobBike in existingJobBikesForSave)
          if (jobBike.bikeId.isNotEmpty) jobBike.bikeId: jobBike,
      };

      MechanicJobBike? existingJobBikeForTab(_BikeTabData tab) {
        final tabJobBikeId = tab.jobBikeId;
        if (tabJobBikeId != null && tabJobBikeId.isNotEmpty) {
          final byId = existingJobBikeById[tabJobBikeId];
          if (byId != null) return byId;
        }

        final tabBikeId = tab.bike?.id;
        if (tabBikeId != null && tabBikeId.isNotEmpty) {
          return existingJobBikeByBikeId[tabBikeId];
        }

        return null;
      }

      // Las líneas se juntan aquí y se guardan todas, con lo que «Configurar»
      // confirmó de la bici, en un solo comando al final (ítem 4): antes cada
      // línea era su propia escritura y un corte dejaba la mitad guardada.
      final linesToSave = <JobLineToSave>[];
      final jobBikesToSave = <JobBikeToSave>[];
      final keptJobBikeIds = <String>{};

      void stagePartItem(
        JobPartItem item,
        String? jobBikeId, {
        String? jobBikeKey,
      }) {
        // Guardada es la que el formulario cargó (o recibió del último
        // guardado), con su versión: si otra persona la borró, el servidor lo
        // dice en vez de insertarla de nuevo.
        final persisted = _seenLineVersions.containsKey(item.id);
        linesToSave.add(JobLineToSave(
          clientKey: item.id,
          persisted: persisted,
          jobBikeKey: jobBikeKey,
          item: jobLineFromPart(
            item,
            persisted: persisted,
            jobId: jobId,
            jobBikeId: jobBikeId,
            tenantId: tenantId,
            existing: existingItemById[item.id],
            configuration: jobLineConfiguration(
              answers: _effectiveWizardAnswersForItem(item),
              partChange: _partChangeMarkerForSave(item),
            ),
          ),
        ));
      }

      // Save each bike tab
      for (int i = 0; i < _bikeTabs.length; i++) {
        final tab = _bikeTabs[i];

        if (tab.isGeneralTab) {
          // Save General tab parts with jobBikeId = null
          if (!protectPaymentCommercialSnapshot) {
            for (final item in tab.partItems) {
              if (item.name.isEmpty) continue; // Skip empty rows
              stagePartItem(item, null);
            }
          }
          continue; // Skip MechanicJobBike creation
        }

        if (tab.bike?.id == null) {
          debugPrint('⚠️ Skipping bike tab $i - no bike ID');
          continue;
        }

        // Create MechanicJobBike record for this bike
        final normalizedTabDiagnosisSheet =
            _normalizeDiagnosisSheetStatuses(tab.diagnosisSheet);
        final existingJobBike = existingJobBikeForTab(tab);
        if (protectPaymentCommercialSnapshot && existingJobBike == null) {
          debugPrint(
            '🔒 Ignoring unpersisted bike ${tab.bike?.id} while the linked invoice is payment-protected.',
          );
          continue;
        }
        final shouldPreserveExistingDiagnosisSheet =
            !normalizedTabDiagnosisSheet.hasMeaningfulData &&
                existingJobBike?.diagnosisSheet.hasMeaningfulData == true;
        final normalizedDiagnosisSheet = shouldPreserveExistingDiagnosisSheet
            ? existingJobBike!.diagnosisSheet
            : normalizedTabDiagnosisSheet;
        final diagnosisSheetUpdatedAt =
            normalizedDiagnosisSheet.hasMeaningfulData
                ? (shouldPreserveExistingDiagnosisSheet
                    ? existingJobBike?.diagnosisSheetUpdatedAt
                    : (tab.diagnosisSheetUpdatedAt ?? DateTime.now()).toUtc())
                : null;

        if (shouldPreserveExistingDiagnosisSheet) {
          debugPrint(
            '[DiagnosisSave] Preserved structured diagnosis for '
            '${tab.bike?.displayName ?? tab.bike?.id ?? 'bike'} while saving narrative/details.',
          );
        }

        final jobBike = MechanicJobBike(
          id: existingJobBike?.id,
          tenantId: tenantId,
          jobId: jobId,
          bikeId: tab.bike!.id!,
          orderIndex: protectPaymentCommercialSnapshot
              ? (existingJobBike?.orderIndex ?? i)
              : i,
          statusId: existingJobBike?.statusId,
          diagnosis: tab.diagnosisController.text.trim().isEmpty
              ? null
              : tab.diagnosisController.text.trim(),
          workRequested: tab.clientRequestController.text.trim().isEmpty
              ? null
              : tab.clientRequestController.text.trim(),
          workPerformed: tab.workRequestedController.text.trim().isEmpty
              ? null
              : tab.workRequestedController.text.trim(),
          technicianNotes: tab.technicianNotesController.text.trim().isEmpty
              ? null
              : tab.technicianNotesController.text.trim(),
          diagnosisSheetKey: normalizedDiagnosisSheet.hasMeaningfulData
              ? (shouldPreserveExistingDiagnosisSheet
                  ? (existingJobBike?.diagnosisSheetKey ??
                      normalizedDiagnosisSheet.templateKey)
                  : (tab.diagnosisSheetKey ??
                      normalizedDiagnosisSheet.templateKey))
              : null,
          diagnosisSheet: normalizedDiagnosisSheet,
          diagnosisSheetUpdatedAt: diagnosisSheetUpdatedAt,
          isWarrantyWork: protectPaymentCommercialSnapshot
              ? (existingJobBike?.isWarrantyWork ?? tab.isWarrantyWork)
              : tab.isWarrantyWork,
          requiresApproval: protectPaymentCommercialSnapshot
              ? (existingJobBike?.requiresApproval ?? tab.requiresApproval)
              : tab.requiresApproval,
          approvedByCustomer: protectPaymentCommercialSnapshot
              ? (existingJobBike?.approvedByCustomer ?? tab.approvedByCustomer)
              : tab.approvedByCustomer,
          approvedAt: existingJobBike?.approvedAt,
          imageUrls: existingJobBike?.imageUrls ?? const <String>[],
        );

        // En el mismo comando que las líneas y la cabecera (revisión de Codex,
        // 2026-09-28): una bici nueva toma allí su id y sus líneas la nombran
        // por su llave, la bici, que está una sola vez en el trabajo. De una
        // que ya estaba viaja sólo lo que cambió, con lo que se vio.
        final jobBikeKey = tab.bike!.id!;
        final existingJobBikeId = existingJobBike?.id;
        if (existingJobBike == null || existingJobBikeId == null) {
          jobBikesToSave.add(JobBikeToSave.added(
            clientKey: jobBikeKey,
            jobBike: jobBike,
          ));
        } else {
          // Una bici que otra persona agregó al trabajo después de que se
          // cargó (el formulario no mostraba su fila): escribirla con la
          // fila releída al guardar pisaría lo suyo. Sólo se acepta la que
          // acaba de crear el registro de la garantía de este guardado.
          if (!_shownJobBikeIds.contains(existingJobBikeId) &&
              !(willRegisterWarrantyClaim && tab.bike?.id == warrantyBikeId)) {
            throw const _JobSaveStopped(
              'Otra persona agregó esta bici al trabajo mientras lo editabas. '
              'Recarga el trabajo antes de guardar.',
            );
          }
          keptJobBikeIds.add(existingJobBikeId);
          final changed = JobBikeToSave.changed(
            clientKey: jobBikeKey,
            jobBike: jobBike,
            seen: _jobBikeBaseline[existingJobBikeId] ??
                existingJobBike.persisted ??
                const {},
            // La hoja que se conserva sin mostrarla no se reescribe.
            keep: shouldPreserveExistingDiagnosisSheet
                ? const {
                    'diagnosis_sheet_key',
                    'diagnosis_sheet_data',
                    'diagnosis_sheet_updated_at',
                  }
                : const {},
          );
          if (changed != null) jobBikesToSave.add(changed);
        }

        // Save this bike's parts/products only while the commercial snapshot
        // remains editable. Diagnosis above is intentionally still writable.
        if (!protectPaymentCommercialSnapshot) {
          for (final item in tab.partItems) {
            if (item.name.isEmpty) continue; // Skip empty rows
            stagePartItem(
              item,
              existingJobBike?.id,
              jobBikeKey: existingJobBike == null ? jobBikeKey : null,
            );
          }
        }
      }

      // Las bicis que el formulario mostraba y ya no están en sus pestañas
      // salen, con sus líneas. Una que ya no está, la quitó otro.
      if (!protectPaymentCommercialSnapshot) {
        for (final shownId in _shownJobBikeIds) {
          final existing = existingJobBikeById[shownId];
          if (keptJobBikeIds.contains(shownId) || existing == null) continue;
          jobBikesToSave.add(JobBikeToSave.removed(
            clientKey: 'sale-$shownId',
            jobBikeId: shownId,
            bikeId: existing.bikeId,
            seen: _jobBikeBaseline[shownId] ?? existing.persisted ?? const {},
          ));
        }
      }

      // For non-service jobs (no bike tabs): save items from legacy _partItems
      if (!protectPaymentCommercialSnapshot &&
          _bikeTabs.isEmpty &&
          _partItems.isNotEmpty) {
        for (final item in _partItems) {
          if (item.name.isEmpty) continue;
          stagePartItem(item, null);
        }
      }

      // Add services (job-level, not per-bike for now). Una ya guardada en
      // esta sesión del formulario se actualiza por su id.
      final laborItems = protectPaymentCommercialSnapshot
          ? const <_JobServiceItem>[]
          : _serviceItems;
      for (final service in laborItems) {
        final hoursWorked = service.hours;
        final hourlyRate = service.hourlyRate;
        final serviceProduct = service.serviceProduct;
        final name = service.description.isNotEmpty
            ? service.description
            : serviceProduct?.name ?? 'Servicio';
        final persistedId = _laborLinePersistedIds[service.id];
        final persisted =
            persistedId != null && _seenLineVersions.containsKey(persistedId);
        final clientKey = persisted ? persistedId : 'labor-${service.id}';

        linesToSave.add(JobLineToSave(
          clientKey: clientKey,
          persisted: persisted,
          item: jobLineFromLabor(
            persistedId: persisted ? persistedId : null,
            jobId: jobId,
            tenantId: tenantId,
            serviceProduct: serviceProduct,
            name: name,
            hours: hoursWorked,
            hourlyRate: hourlyRate,
          ),
        ));
      }

      // La decisión de garantía de este guardado (y el cambio de estado que
      // la sigue) se respalda en la bandeja en la misma escritura que las
      // líneas, detrás de ellas: un cierre después de escribir las líneas ya
      // no deja el trabajo sin decisión ni documento (punto 2 del cierre,
      // 2026-09-29). Si las líneas no se escriben, salen con ellas.
      final warrantyDecisionInSave = _jobType == JobType.warranty &&
          _warrantySaveCheckpoint.needsDecision(desiredWarrantyOutcome);
      String? decisionReason;
      ({
        String operationKey,
        String statusId,
        JobStatusCustom? target
      })? chainedStatus;
      final followUps = <PendingWorkshopCommand>[
        // El registro de una garantía nueva va antes que su decisión.
        if (chainedRegistration != null) chainedRegistration,
      ];
      if (warrantyDecisionInSave) {
        decisionReason = _warrantyDecisionReasonController.text.trim().isEmpty
            ? null
            : _warrantyDecisionReasonController.text.trim();
        final decisionFingerprint =
            '${desiredWarrantyOutcome.dbValue}|${decisionReason ?? ''}';
        if (_pendingWarrantyDecisionFingerprint != decisionFingerprint) {
          _pendingWarrantyDecisionOperationKey = const Uuid().v4();
          _pendingWarrantyDecisionFingerprint = decisionFingerprint;
        }
        followUps.add(bikeshopService.warrantyDecisionCommand(
          warrantyJobId: jobId,
          outcome: desiredWarrantyOutcome,
          reason: decisionReason,
          operationKey: _pendingWarrantyDecisionOperationKey!,
          label: _jobCommandLabel(savedHeader),
        ));
        final plan = _plannedStatusTransition();
        if (plan != null) {
          final target = plan.statusId == null
              ? await bikeshopService.activeStatusForLegacyStatus(
                  _selectedStatus,
                )
              : _selectedCustomStatus;
          chainedStatus = (
            operationKey: plan.operationKey,
            statusId: plan.statusId ?? target!.id!,
            target: target,
          );
          followUps.add(bikeshopService.statusTransitionCommand(
            jobId: jobId,
            statusId: chainedStatus.statusId,
            operationKey: chainedStatus.operationKey,
            label: _jobCommandLabel(savedHeader),
          ));
        }
      }

      // Líneas y ficha juntas, con recibo y versión (ítem 4). Las líneas que
      // el formulario quitó las borra el mismo comando.
      final lineSave = await _saveLinesWithBikeFacts(
        bikeshopService: bikeshopService,
        jobId: jobId,
        lines: protectPaymentCommercialSnapshot ? null : linesToSave,
        // Un trabajo recién creado ya tiene su cabecera: la insertó el alta
        // con lo mismo que editó el formulario, y los disparadores la pudieron
        // normalizar (ejes de modo). Reescribirla chocaría con esas guardias;
        // sólo el descuento, que el alta deja en cero, viaja.
        header: jobHeaderPatch(
          seen: _headerBaseline,
          shown: _headerShown,
          edited: savedJobId != null
              ? editedHeader
              : {
                  if (editedHeader.containsKey('discount_amount'))
                    'discount_amount': editedHeader['discount_amount'],
                },
        ),
        // Con las líneas van todas las bicis que quedan: la que falta sale en
        // el mismo comando, con sus líneas. Sin líneas (con pago), sólo las
        // que ya estaban, y ninguna sale.
        jobBikes: jobBikesToSave,
        // La factura queda al día en el mismo comando, salvo que la decisión
        // de garantía de este guardado sea la dueña de su documento.
        invoice: !warrantyDecisionInSave,
        label: creation == null
            ? _jobCommandLabel(savedHeader)
            : _newJobCommandLabel(),
        followUps: followUps,
        creation: creation,
        // Con el recibo del alta en la mano el trabajo existe, aunque sus
        // líneas todavía no lleguen: sólo desde aquí se dice «creado».
        onCreated: (created) {
          _adoptCreatedJob(created);
          persistedJobId = created.id;
          savedHeader = created;
        },
      );
      final bikeFactProblems = lineSave.problems;
      String? registrationPendingNotice;
      if (chainedRegistration != null) {
        // El registro de la garantía nueva, detrás de sus líneas: la bandeja
        // lo envía ahora. Sin respuesta, no se dice vinculada.
        try {
          await bikeshopService.settleWarrantyRegistration(
            chainedRegistration.operationKey,
          );
          _warrantySaveCheckpoint.confirmRegistration(registrationSourceJobId!);
        } on MechanicJobWarrantyRegistrationPending catch (pending) {
          registrationPendingNotice = pending.toString();
        }
      }
      final invoiceOutcome = lineSave.result?.invoice;
      String? statusPendingNotice;
      String? warrantyDecisionPendingNotice;

      if (warrantyDecisionInSave) {
        // La misma llave que quedó respaldada con las líneas: la bandeja la
        // envía ahora, detrás de ellas. La decisión es la dueña del
        // documento también mientras sigue pendiente: la factura genérica no
        // se hace aquí.
        warrantyDecisionManagedDocument = true;
        try {
          await bikeshopService.decideWarrantyClaim(
            warrantyJobId: jobId,
            outcome: desiredWarrantyOutcome,
            reason: decisionReason,
            operationKey: _pendingWarrantyDecisionOperationKey!,
            label: _jobCommandLabel(savedHeader),
          );
          _warrantySaveCheckpoint.confirmDecision(desiredWarrantyOutcome);
          _pendingWarrantyDecision = null;
        } on MechanicJobWarrantyDecisionPending catch (pending) {
          // No está aplicada: la cobertura a la vista sigue siendo la del
          // servidor y el panel la dice pendiente.
          _pendingWarrantyDecisionOperationKey = pending.operationKey;
          _pendingWarrantyDecision = (
            outcome: desiredWarrantyOutcome,
            reason: decisionReason,
            operationKey: pending.operationKey,
          );
          warrantyDecisionPendingNotice = pending.toString();
        }
      }

      await _debugLogPegaInvoiceSnapshot(
        'before_invoice_phase',
        jobId: jobId,
      );

      if (invoiceOutcome != null) {
        // La factura ya quedó al día en el comando, en la misma transacción
        // que su recibo; si no se pudo, el guardado igual quedó y se dice.
        await _debugLogPegaInvoiceSnapshot(
          'after_invoice_in_command',
          jobId: jobId,
          invoiceId: invoiceOutcome.invoiceId,
        );
        if (invoiceOutcome.failed) {
          // Su continuación quedó en la bandeja del equipo: se vuelve a
          // intentar sola, también tras cerrar la app.
          throw Exception(
            'El trabajo quedó guardado, pero su factura no se pudo hacer: '
            '${invoiceOutcome.errorMessage ?? invoiceOutcome.errorCode}. '
            'Quedó pendiente en este equipo y se vuelve a intentar sola; '
            'resuelve eso y se hará.',
          );
        }
      } else if (protectPaymentCommercialSnapshot) {
        // Migration 070 makes this paid branch a strict commercial no-op. Keep
        // the compatibility call, but do not claim that invoice lines are
        // projected back into the job: both persisted records stay untouched.
        await bikeshopService.syncJobToInvoice(jobId);
        await _debugLogPegaInvoiceSnapshot(
          'after_protected_invoice_guard',
          jobId: jobId,
          invoiceId: _existingJob?.invoiceId,
        );
      } else if (!warrantyDecisionManagedDocument) {
        // Sync invoice AFTER all items are written. A warranty decision owns
        // its customer/internal document atomically, so running this generic
        // projection immediately afterwards would duplicate that ownership.
        final savedJob = await bikeshopService.getJobById(jobId);
        final linkedInvoiceId = savedJob?.invoiceId;

        final shouldCreateInvoice = savedJob != null &&
            (savedJob.isSaleWorkflow ||
                (savedJob.isBillableServiceWorkflow &&
                    (savedJob.jobType == JobType.service ||
                        savedJob.jobType == JobType.itemService)));

        if (linkedInvoiceId != null &&
            savedJob?.workflowKind != JobWorkflowKind.quotation) {
          // If there's an existing invoice, we still sync it just to keep it updated,
          // (unless we want to delete it if it's a quotation now, but we'll assume
          // quotes don't get invoices attached in the first place).
          debugPrint('🔄 Syncing job to invoice: $linkedInvoiceId');
          await bikeshopService.syncJobToInvoice(jobId);
          await _debugLogPegaInvoiceSnapshot(
            'after_invoice_sync',
            jobId: jobId,
            invoiceId: linkedInvoiceId,
          );
        } else if (shouldCreateInvoice) {
          debugPrint('🧾 No linked invoice yet, creating one after items save');
          String? createdInvoiceId;
          Object? lastInvoiceError;
          for (var attempt = 1; attempt <= 2; attempt++) {
            try {
              createdInvoiceId =
                  await bikeshopService.createInvoiceFromJob(jobId);
              lastInvoiceError = null;
              break;
            } catch (error) {
              lastInvoiceError = error;
              if (attempt < 2) {
                await Future<void>.delayed(const Duration(milliseconds: 300));
              }
            }
          }
          if (lastInvoiceError != null || createdInvoiceId == null) {
            throw Exception(
              'El trabajo quedó guardado, pero no se pudo confirmar su factura: $lastInvoiceError',
            );
          }
          await _debugLogPegaInvoiceSnapshot(
            'after_invoice_create',
            jobId: jobId,
            invoiceId: createdInvoiceId,
          );
        } else {
          debugPrint(
              'ℹ️ Skipping customer invoice generation for JobType: ${savedJob?.jobType}, outcome: ${savedJob?.warrantyOutcome}');
        }
      }

      // Persisted lifecycle changes are deliberately last: the canonical RPC
      // derives legacy status and timestamps from the database clock, and a
      // covered warranty may post/reverse its invoice only after all accepted
      // lines and invoice mirrors are final. Keep one operation key across a
      // retry after a lost acknowledgement.
      final statusPlan = _plannedStatusTransition();
      if (statusPlan != null) {
        final targetStatusId = statusPlan.statusId;
        final operationKey = statusPlan.operationKey;
        try {
          if (chainedStatus != null) {
            // El mismo cambio que quedó respaldado detrás de la decisión:
            // espera a que ésta se aplique, y si no se aplica sale con
            // ella sin enviarse.
            await bikeshopService.transitionJobStatus(
              jobId,
              chainedStatus.statusId,
              operationKey: chainedStatus.operationKey,
              targetStatus: chainedStatus.target,
              syncBikeMemoryOnCompletion: false,
            );
          } else if (targetStatusId != null) {
            // La memoria se sincroniza una vez, al final de este guardado.
            await bikeshopService.transitionJobStatus(
              jobId,
              targetStatusId,
              operationKey: operationKey,
              targetStatus: _selectedCustomStatus,
              syncBikeMemoryOnCompletion: false,
            );
          } else {
            await bikeshopService.transitionJobStatusByLegacyStatus(
              jobId,
              _selectedStatus,
              operationKey: operationKey,
              syncBikeMemoryOnCompletion: false,
            );
          }
        } on MechanicJobStatusTransitionPending catch (pending) {
          // El trabajo quedó guardado; el estado quedó en la bandeja con su
          // llave, detrás del guardado, y se aplica solo (también si se
          // cierra la app). Guardar otra vez reusa la misma llave.
          statusPendingNotice = pending.toString();
        }
      }

      // Refresh bicycle memory only after the guarded commercial phase. When a
      // payment exists, this reads the persisted job aggregate; it does not
      // rewrite job lines from the invoice. Un trabajo terminado escribe aquí
      // lo instalado, y lo que no llegó se dice igual que lo configurado.
      if (_jobType != JobType.sale) {
        bikeFactProblems
            .addAll(await bikeshopService.syncBikeMemoryFromJob(jobId));
      }

      if (mounted && context.mounted) {
        _pendingWarrantyRegistrationOperationKey = null;
        if (warrantyDecisionPendingNotice == null) {
          _pendingWarrantyDecisionOperationKey = null;
          _pendingWarrantyDecisionFingerprint = null;
        }
        if (statusPendingNotice == null) {
          _pendingStatusTransitionOperationKey = null;
          _pendingStatusTransitionFingerprint = null;
        }
        final savedLabel = widget.jobId != null
            ? 'Trabajo actualizado correctamente'
            : 'Trabajo creado correctamente';
        _captureInlineDraftBaseline();
        if (bikeFactProblems.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(savedLabel),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _showBikeFactOutcome(
            '$savedLabel, pero la ficha de la bici no se actualizó. '
            '${bikeFactProblems.join(' ')}',
          );
        }
        // Lo que quedó en la bandeja se dice como pendiente, nunca como
        // aplicado: la decisión de garantía y el estado detrás de ella.
        final pendingNotices = [
          if (registrationPendingNotice != null) registrationPendingNotice,
          if (warrantyDecisionPendingNotice != null)
            warrantyDecisionPendingNotice,
          if (statusPendingNotice != null) statusPendingNotice,
        ];
        if (pendingNotices.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(pendingNotices.join(' ')),
              duration: const Duration(seconds: 8),
            ),
          );
        }
        if (widget.isEmbedded) {
          if (widget.onSaved != null) widget.onSaved!();
        } else if (bikeFactProblems.isNotEmpty && widget.jobId == null) {
          // Trabajo nuevo: se abre el guardado, que lee la ficha vigente y
          // retoma lo que faltó.
          context.go('/taller/pegas/$jobId');
        } else {
          await _leaveRoutedForm(result: true);
        }
      }
    } on WorkshopImageUnavailableException catch (unavailable) {
      // Un adjunto subido que la bandeja ya borró (la ventana estuvo
      // inactiva y otra lo dio por abandonado) o que es de otro trabajo: no
      // se respaldó nada. Sale de la lista para volver a adjuntarlo, en vez
      // de guardar un enlace roto (carrera del barrido, 2026-09-29).
      if (mounted) {
        setState(() {
          _imageUrls.removeWhere((url) =>
              unavailable.removedUrls.contains(url) ||
              unavailable.foreignUrls.contains(url));
        });
      }
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(unavailable.toString()),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } on JobCreationPendingException catch (pending) {
      // Nada se creó todavía: el formulario sigue abierto con lo editado, y
      // el próximo Guardar (o la reanudación) manda primero lo respaldado.
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pending.toString()),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } on JobCompletionBlockedException catch (blocked) {
      if (!mounted) return;
      await showJobCompletionBlocked(context, blocked);
      if (mounted && persistedJobId != null && widget.jobId == null) {
        context.go('/taller/pegas/$persistedJobId?tab=products');
      } else if (mounted) {
        _selectWorkbenchTab(_JobWorkbenchTab.products);
      }
    } catch (e) {
      final recoveryJobId = persistedJobId ?? widget.jobId;
      final paymentRaceReconciled = !wasPaymentProtectedAtSaveStart &&
          recoveryJobId != null &&
          await _reconcileConfirmedPaymentRaceAfterSaveFailure(recoveryJobId);
      if (!mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              paymentRaceReconciled
                  ? 'Se confirmó un pago concurrente. La factura y el contenido comercial protegido se mantuvieron sin reescritura. Reabre la ficha para cargar el estado vigente antes de continuar. Detalle: $e'
                  : persistedJobId != null && widget.jobId == null
                      ? 'El trabajo quedó creado, pero una etapa posterior falló. Abriremos la ficha existente para evitar duplicarlo. Detalle: $e'
                      : 'Error al guardar trabajo: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
        if (persistedJobId != null && widget.jobId == null) {
          context.go('/taller/pegas/$persistedJobId');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _openJobStatusConversation() async {
    await _openJobMessagingConversation(readyForPickup: false);
  }

  Future<void> _openReadyForPickupConversation() async {
    await _openJobMessagingConversation(readyForPickup: true);
  }

  Future<void> _openJobMessagingConversation({
    required bool readyForPickup,
  }) async {
    final customer = _selectedCustomer;
    final bike = _selectedBike;
    final job = _existingJob;

    if (customer == null || bike == null || job == null || job.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay datos suficientes para enviar mensaje')),
      );
      return;
    }

    final phone = customer.phone?.trim();
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El cliente no tiene número de teléfono registrado')),
      );
      return;
    }

    try {
      final chatProvider = context.read<ChatProvider>();
      final conversationId =
          await MessagingService().openWhatsAppSupportConversation(
        phoneNumber: phone,
        contactName: customer.name,
        customerId: customer.id,
        contextType: 'job',
        contextId: job.id,
      );

      chatProvider.setConversationDraft(
        conversationId,
        _buildJobMessagingDraft(
          customer: customer,
          bike: bike,
          job: job,
          readyForPickup: readyForPickup,
        ),
        title: readyForPickup
            ? 'Aviso de retiro listo'
            : 'Actualización de servicio técnico',
        subtitle: '${_jobReference(job)} · ${bike.displayName}',
      );

      if (!mounted) return;
      context.go('/chat?conversation=$conversationId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la conversación: $e')),
        );
      }
    }
  }

  String _buildJobMessagingDraft({
    required Customer customer,
    required Bike bike,
    required MechanicJob job,
    required bool readyForPickup,
  }) {
    final firstName = customer.name.trim().split(RegExp(r'\s+')).first;
    final jobReference = _jobReference(job);
    final totalLine = job.totalCost > 0
        ? '\nTotal registrado: ${_formatJobCurrency(job.totalCost)}'
        : '';

    if (readyForPickup) {
      return '''Hola $firstName, te escribimos de Viñabike. Tu ${bike.displayName} ya está lista para retiro.

Trabajo: $jobReference
Estado: ${job.statusDisplayName}$totalLine

Puedes retirarla en Álvarez 32, Local 17. Si retirará otra persona, respóndenos con su nombre antes de venir. Gracias.''';
    }

    final requestLine = (job.clientRequest ?? '').trim().isNotEmpty
        ? '\nSolicitud registrada: ${job.clientRequest!.trim()}'
        : '';

    return '''Hola $firstName, te escribimos de Viñabike por el servicio de tu ${bike.displayName}.

Trabajo: $jobReference
Estado actual: ${job.statusDisplayName}$requestLine$totalLine

Si tienes alguna duda o necesitas coordinar algo, puedes responder por este mismo chat. Gracias.''';
  }

  String _jobReference(MechanicJob job) {
    final jobNumber = job.jobNumber?.trim();
    if (jobNumber != null && jobNumber.isNotEmpty) return jobNumber;
    final id = job.id;
    if (id == null || id.length < 8) return 'Trabajo técnico';
    return '#${id.substring(0, 8)}';
  }

  String _formatJobCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'es_CL',
      symbol: r'$',
      decimalDigits: 0,
    ).format(amount);
  }

  Future<void> _confirmDeleteBike(Bike bike) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Está seguro de eliminar la bicicleta "${bike.displayName}"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;

      try {
        final bikeshopService =
            Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(bike.id!);

        await _refreshCustomerBikes();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Bicicleta "${bike.displayName}" eliminada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar bicicleta: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showBikeManagementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gestionar Bicicletas'),
        content: SizedBox(
          width: 500,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _bikes.length,
            itemBuilder: (context, index) {
              final bike = _bikes[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.pedal_bike),
                  title: Text(bike.displayName),
                  subtitle: bike.serialNumber != null
                      ? Text('S/N: ${bike.serialNumber}')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          Navigator.pop(context); // Close management dialog

                          await _openBikeDialog(
                            bike: bike,
                            selectSavedBike: _selectedBike?.id == bike.id,
                          );
                        },
                        tooltip: 'Editar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(context); // Close dialog
                          _confirmDeleteBike(bike);
                        },
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Form(
      key: _formKey,
      child: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _existingJobLoadError != null
                    ? _buildExistingJobLoadFailure(theme)
                    : _buildForm(theme),
          ),
        ],
      ),
    );

    final surface = widget.isEmbedded
        ? ColoredBox(
            color: theme.colorScheme.surface,
            child: content,
          )
        : MainLayout(child: content);

    return PopScope(
      canPop: _allowRoutePop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSaving) return;
        _handleCancel();
      },
      child: surface,
    );
  }

  Widget _buildExistingJobLoadFailure(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_problem_outlined,
                    size: 42,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No se abrió una ficha parcial',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _existingJobLoadError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => unawaited(_retryInitialData()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar carga completa'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryInitialData() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _existingJobLoadError = null;
    });
    await _loadInitialData();
  }

  Widget _buildHeader(ThemeData theme) {
    final isEditing = widget.jobId != null;
    final title = isEditing ? 'Editar Trabajo' : 'Nuevo Trabajo';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
          ResponsiveViewport.widthOf(context),
        );

        if (isCompact) {
          return _buildInlineWorkspaceHeader(
            theme,
            isEditing: isEditing,
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor,
                width: 1,
              ),
            ),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (isEditing &&
                            _selectedCustomer != null &&
                            _selectedBike != null) ...[
                          if (_selectedStatus == JobStatus.finalizado ||
                              _selectedStatus == JobStatus.entregado)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openReadyForPickupConversation(),
                              icon: const Icon(Icons.check_circle,
                                  color: Colors.green),
                              label: const Text('Avisar Cliente'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => _openJobStatusConversation(),
                              icon: const Icon(Icons.message,
                                  color: Colors.green),
                              label: const Text('WhatsApp'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            ),
                        ],
                        OutlinedButton.icon(
                          onPressed: _isSaving ? null : _handleCancel,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                        ),
                        FilledButton.icon(
                          onPressed: _canSaveJob ? _saveJob : null,
                          icon: _isSaving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _isFinalQuotationReadOnly
                                      ? Icons.lock_outline
                                      : Icons.save,
                                ),
                          label: Text(
                            _isFinalQuotationReadOnly
                                ? 'Solo lectura'
                                : 'Guardar',
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (isEditing &&
                        _selectedCustomer != null &&
                        _selectedBike != null) ...[
                      if (_selectedStatus == JobStatus.finalizado ||
                          _selectedStatus == JobStatus.entregado)
                        OutlinedButton.icon(
                          onPressed: () => _openReadyForPickupConversation(),
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          label: const Text('Avisar Cliente'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => _openJobStatusConversation(),
                          icon: const Icon(Icons.message, color: Colors.green),
                          label: const Text('WhatsApp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _handleCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _canSaveJob ? _saveJob : null,
                      icon: _isSaving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isFinalQuotationReadOnly
                                  ? Icons.lock_outline
                                  : Icons.save,
                            ),
                      label: Text(
                        _isFinalQuotationReadOnly ? 'Solo lectura' : 'Guardar',
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildInlineWorkspaceHeader(
    ThemeData theme, {
    required bool isEditing,
  }) {
    final jobLabel = _existingJob?.jobNumber?.trim();
    final title = jobLabel != null && jobLabel.isNotEmpty
        ? jobLabel
        : isEditing
            ? 'Trabajo'
            : 'Nuevo trabajo';
    final subtitle = switch (widget.initialTab) {
      'products' => 'Productos y servicios',
      'diagnosis' => 'Diagnóstico',
      _ => 'Ficha del trabajo',
    };
    final canMessageCustomer =
        isEditing && _selectedCustomer != null && _selectedBike != null;
    final shouldNotifyReady = _selectedStatus == JobStatus.finalizado ||
        _selectedStatus == JobStatus.entregado;
    final messageLabel = shouldNotifyReady ? 'Avisar cliente' : 'WhatsApp';

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(4, 5, 8, 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('mechanic-job-inline-back'),
            onPressed: _isSaving ? null : _handleCancel,
            tooltip: 'Volver a trabajos',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('mechanic-job-inline-overflow'),
            enabled: canMessageCustomer && !_isSaving,
            tooltip: canMessageCustomer ? messageLabel : 'Más acciones',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value != 'message_customer') return;
              if (shouldNotifyReady) {
                unawaited(_openReadyForPickupConversation());
              } else {
                unawaited(_openJobStatusConversation());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'message_customer',
                child: Row(
                  children: [
                    Icon(
                      shouldNotifyReady
                          ? Icons.check_circle_outline_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Text(messageLabel),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 2),
          FilledButton(
            key: const ValueKey('mechanic-job-inline-save'),
            onPressed: _canSaveJob ? _saveJob : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 13),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isFinalQuotationReadOnly ? 'Solo lectura' : 'Guardar',
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachment() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      final result = await ImageService.pickFile();

      setState(() {
        _isUploadingImage = false;
      });

      if (result != null) {
        setState(() {
          _newImages.add((bytes: result.bytes, name: result.name));
        });
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al adjuntar archivo: $e')),
        );
      }
    }
  }

  bool _isImage(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext);
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

  Widget _buildAttachmentsSection() {
    if (_imageUrls.isEmpty && _newImages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _isUploadingImage ? null : _pickAttachment,
            icon: _isUploadingImage
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file),
            label: const Text('Adjuntar archivo'),
          ),
          const SizedBox(height: 8),
          Text(
            'Sin adjuntos',
            style:
                TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Calculate item width based on available width
            final crossAxisCount =
                (constraints.maxWidth / 120).floor().clamp(2, 6);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _imageUrls.length +
                  _newImages.length +
                  1, // +1 for add button
              itemBuilder: (context, index) {
                // Add button is always last
                if (index == _imageUrls.length + _newImages.length) {
                  return InkWell(
                    onTap: _isUploadingImage ? null : _pickAttachment,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[50], // Sutil background
                      ),
                      child: Center(
                        child: _isUploadingImage
                            ? const CircularProgressIndicator()
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.attach_file,
                                      color: Colors.grey[600]),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Agregar',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                }

                // Determine if it's an existing URL or a new local image
                final isNew = index >= _imageUrls.length;
                final relativeIndex = isNew ? index - _imageUrls.length : index;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isNew
                          ? (_isImage(_newImages[relativeIndex].name)
                              ? Image.memory(
                                  _newImages[relativeIndex].bytes,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.grey[100],
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.insert_drive_file,
                                          color: Colors.blueGrey, size: 32),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Text(
                                          _newImages[relativeIndex].name,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.black87,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                          : (_isImage(_imageUrls[relativeIndex])
                              ? WorkshopAssetContent(
                                  reference: _imageUrls[relativeIndex],
                                  builder: (context, url) => Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[200],
                                        child: const Center(
                                          child: Icon(Icons.broken_image,
                                              color: Colors.grey),
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[100],
                                  child: const Center(
                                    child: Icon(Icons.insert_drive_file,
                                        color: Colors.blueGrey, size: 32),
                                  ),
                                )),
                    ),
                    // Delete button overlay
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => _removeImage(relativeIndex, isNew),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // "New" badge for local images
                    if (isNew)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NUEVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1180;

        if (isWide) {
          // Two-column layout for wide screens (+ chat sidebar for existing jobs)
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT COLUMN - Work content with bike tabs embedded
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_isCommercialSnapshotLocked ||
                            _hasConvertedQuotationHistory) ...[
                          _buildCommercialLockBanner(theme),
                          const SizedBox(height: 16),
                        ],
                        // Job details with embedded bike tabs
                        KeyedSubtree(
                          key: _workbenchSectionKey,
                          child: _buildJobDetailsSectionCard(
                            theme,
                            icon: Icons.build_outlined,
                            title: 'Detalles del Trabajo',
                            child: _buildWorkbenchContent(theme),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.attach_file,
                          title: 'Adjuntos',
                          child: _lockFormContent(
                            _buildAttachmentsSection(),
                            locked: _isFinalQuotationReadOnly,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // RIGHT COLUMN - Customer and Summary (fixed width sidebar)
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        KeyedSubtree(
                          key: _customerSectionKey,
                          child: _buildSectionCard(
                            theme,
                            icon: Icons.person_outline,
                            title: 'Cliente',
                            child: _lockFormContent(
                              _buildCustomerBikeSection(),
                              locked: _isFinalQuotationReadOnly,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        KeyedSubtree(
                          key: _costSummarySectionKey,
                          child: _buildSectionCard(
                            theme,
                            icon: Icons.calculate_outlined,
                            title: 'Resumen de Costos',
                            child: _lockFormContent(
                              _buildCostSummary(),
                              locked: _isCommercialSnapshotLocked,
                            ),
                          ),
                        ),
                        if (_existingJob?.invoiceId != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            theme,
                            icon: Icons.receipt_outlined,
                            title: 'Factura Vinculada',
                            child: _buildInvoiceSection(),
                          ),
                        ],
                        // Service details panel (only when a service is selected)
                        if (_selectedServiceItem != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            theme,
                            icon: Icons.build_circle_outlined,
                            title: 'Detalle de Servicio',
                            child: _lockFormContent(
                              _buildServiceDetailsPanel(),
                              locked: _isCommercialSnapshotLocked,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // CHAT SIDEBAR - Only for existing jobs
                if (widget.jobId != null) ...[
                  const SizedBox(width: 8),
                  EntityChatSidebar(
                    entityType: 'job',
                    entityId: widget.jobId!,
                    entityTitle:
                        'Trabajo #${_existingJob?.jobNumber ?? widget.jobId!.substring(0, 6)}',
                    deferLoadingUntilExpanded: true,
                  ),
                ],
              ],
            ),
          );
        } else {
          // Single-column layout for narrow screens
          final customerSection = KeyedSubtree(
            key: _customerSectionKey,
            child: _buildSectionCard(
              theme,
              icon: Icons.person_outline,
              title: 'Cliente',
              child: _lockFormContent(
                _buildCustomerBikeSection(),
                locked: _isFinalQuotationReadOnly,
              ),
            ),
          );
          final workbenchSection = KeyedSubtree(
            key: _workbenchSectionKey,
            child: _buildJobDetailsSectionCard(
              theme,
              icon: Icons.build_outlined,
              title: 'Detalles del Trabajo',
              child: _buildWorkbenchContent(theme),
            ),
          );
          final prioritizesRequestedWorkbench =
              widget.isInlineWorkspace && widget.jobId != null;

          return SingleChildScrollView(
            padding: widget.isInlineWorkspace
                ? const EdgeInsets.fromLTRB(8, 12, 8, 16)
                : const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_isCommercialSnapshotLocked ||
                    _hasConvertedQuotationHistory) ...[
                  _buildCommercialLockBanner(theme),
                  const SizedBox(height: 16),
                ],
                if (prioritizesRequestedWorkbench) ...[
                  workbenchSection,
                  const SizedBox(height: 16),
                  customerSection,
                ] else ...[
                  customerSection,
                  const SizedBox(height: 16),
                  workbenchSection,
                ],
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.attach_file,
                  title: 'Adjuntos',
                  child: _lockFormContent(
                    _buildAttachmentsSection(),
                    locked: _isFinalQuotationReadOnly,
                  ),
                ),
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: _costSummarySectionKey,
                  child: _buildSectionCard(
                    theme,
                    icon: Icons.calculate_outlined,
                    title: 'Resumen de Costos',
                    child: _lockFormContent(
                      _buildCostSummary(),
                      locked: _isCommercialSnapshotLocked,
                    ),
                  ),
                ),
                if (_existingJob?.invoiceId != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.receipt_outlined,
                    title: 'Factura Vinculada',
                    child: _buildInvoiceSection(),
                  ),
                ],
                // Service details panel (mobile)
                if (_selectedServiceItem != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.build_circle_outlined,
                    title: 'Detalle de Servicio',
                    child: _lockFormContent(
                      _buildServiceDetailsPanel(),
                      locked: _isCommercialSnapshotLocked,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
      },
    );
  }

  Widget _lockFormContent(Widget child, {required bool locked}) {
    if (!locked) return child;
    return IgnorePointer(
      ignoring: true,
      child: Opacity(opacity: 0.68, child: child),
    );
  }

  Widget _buildCommercialLockBanner(ThemeData theme) {
    final isFinalQuotation = _isFinalQuotationReadOnly;
    final isFinanciallyProtected = _isPaymentProtectedCommercialSnapshotLocked;
    final statusLabel = _effectiveQuotationStatus.displayName.toLowerCase();
    final proposalLabel =
        _existingJob?.proposalDocumentLabel ?? _proposalDocumentLabel;
    final postedInvoice = isFinanciallyProtected &&
        !_linkedInvoiceHasActivePayments &&
        !_linkedInvoicePaymentStateUnknown &&
        _linkedInvoiceIsPosted;
    final invoiceName = _linkedInvoiceNumber ?? 'vinculada';
    final title = postedInvoice
        ? 'Factura $invoiceName confirmada'
        : isFinanciallyProtected
            ? 'Historial financiero protegido'
            : isFinalQuotation
                ? '$proposalLabel $statusLabel · solo lectura'
                : 'Propuesta original conservada';
    final message = postedInvoice
        ? _jobType == JobType.sale
            ? 'Ya descontó stock y tiene su asiento. Productos, precios y descuento se corrigen desde la factura, que rehace ambos y lo trae aquí; puedes actualizar la nota del acuerdo.'
            : 'Ya descontó stock y tiene su asiento. Productos, precios y descuento se corrigen desde la factura, que rehace ambos y lo trae aquí; puedes seguir con diagnóstico, notas y estado.'
        : isFinanciallyProtected
            ? _jobType == JobType.sale
                ? _linkedInvoiceHasActivePayments
                    ? 'La factura de esta venta tiene abonos vigentes. Puedes actualizar la nota del acuerdo; productos, precios, descuento, totales y factura quedan protegidos.'
                    : 'No se pudo confirmar el estado de pago de la factura. Por seguridad solo puedes actualizar la nota del acuerdo hasta recargarla correctamente.'
                : _linkedInvoiceHasActivePayments
                    ? 'La factura de este trabajo tiene pagos vigentes. Puedes actualizar diagnóstico, notas y el estado operativo de un servicio normal; productos, precios, descuento, totales y factura quedan protegidos. Una garantía cubierta requiere resolver primero el pago desde la factura.'
                    : 'No se pudo confirmar el estado de pago de la factura. Por seguridad puedes actualizar diagnóstico, notas y el estado operativo de un servicio normal; la información comercial queda protegida hasta recargarla correctamente.'
            : isFinalQuotation
                ? 'Este documento ya salió de edición. Para aprobar, rechazar, reabrir o convertir usa las acciones auditadas de la tabla; así no se altera lo enviado al cliente.'
                : 'Este trabajo ya es un servicio cobrable y puede seguir actualizándose normalmente. Los valores que el cliente aprobó permanecen inmutables en el historial de la propuesta.';

    if (widget.isInlineWorkspace &&
        !isFinanciallyProtected &&
        !isFinalQuotation) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.24),
          ),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('commercial-history-inline-disclosure'),
            minTileHeight: 52,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(48, 0, 14, 14),
            leading: Icon(
              Icons.lock_clock_outlined,
              size: 20,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            title: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              isFinanciallyProtected
                  ? Icons.account_balance_outlined
                  : Icons.lock_clock_outlined,
              color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isInlineWorkspace) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _handleCancel,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Ir a la tabla'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final isCompactInline = widget.isInlineWorkspace;
    return Card(
      elevation: 0,
      margin: isCompactInline ? EdgeInsets.zero : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isCompactInline ? 16 : 20),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompactInline ? 12 : 20,
          isCompactInline ? 16 : 20,
          isCompactInline ? 12 : 20,
          isCompactInline ? 18 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  /// Special section card with bike tabs embedded in header
  Widget _buildJobDetailsSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final hasBikeTabs = _selectedCustomer != null && _bikeTabs.isNotEmpty;
    final isCompactInline = widget.isInlineWorkspace;
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasBikeTabs) ...[
            _buildInlineBikeTabs(theme),
            const SizedBox(height: 10),
          ],
          child,
        ],
      );
    }

    return Card(
      elevation: 0,
      margin: isCompactInline ? EdgeInsets.zero : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isCompactInline ? 16 : 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon, title, and bike tabs
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompactInline ? 12 : 20,
              isCompactInline ? 16 : 20,
              isCompactInline ? 12 : 20,
              0,
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(icon,
                            color: theme.colorScheme.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (hasBikeTabs) ...[
                    const SizedBox(height: 12),
                    _buildInlineBikeTabs(theme),
                  ],
                ],
              );
            }),
          ),
          SizedBox(height: isCompactInline ? 16 : 20),
          // Content
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompactInline ? 12 : 20,
              0,
              isCompactInline ? 12 : 20,
              isCompactInline ? 18 : 24,
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Full-width bike tab bar — sits below the card title, above content.
  Widget _buildInlineBikeTabs(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurfaceVariant;
    final dividerColor =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thin divider above tab bar
        Divider(height: 1, thickness: 1, color: dividerColor),
        // Tab bar row
        Container(
          color: theme.colorScheme.surfaceContainerLowest,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._bikeTabs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tab = entry.value;
                    final isSelected = index == _selectedBikeTabIndex;

                    // Hide the General tab when it has no items
                    if (tab.isGeneralTab && tab.partItems.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final label = tab.isGeneralTab
                        ? 'General'
                        : (tab.bike?.displayName ?? 'Bici ${index + 1}');
                    final icon = tab.isGeneralTab
                        ? Icons.shopping_bag_outlined
                        : Icons.pedal_bike_outlined;
                    final canClose = !_isCommercialSnapshotLocked &&
                        _jobType != JobType.warranty &&
                        !tab.isGeneralTab &&
                        _bikeTabs.where((t) => !t.isGeneralTab).length > 1;

                    return _BikeTabButton(
                      label: label,
                      icon: icon,
                      isSelected: isSelected,
                      canClose: canClose,
                      onTap: () {
                        setState(() {
                          _selectedBikeTabIndex = index;
                          _selectedBike = _bikeTabs[index].bike;
                        });
                        unawaited(_loadSelectedBikeProfile(_selectedBike));
                      },
                      onClose: () => _confirmRemoveBike(index, label),
                      primaryColor: primary,
                      inactiveColor: onSurface,
                    );
                  }),
                  if (!_isCommercialSnapshotLocked &&
                      _jobType == JobType.service)
                    // Add bike button — vertically centered, subtle
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message: 'Agregar bicicleta',
                        child: InkWell(
                          onTap: _showAddBikeSelector,
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: primary.withValues(alpha: 0.08),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            child: Icon(Icons.add, size: 18, color: primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Bottom divider
        Divider(height: 1, thickness: 1, color: dividerColor),
      ],
    );
  }

  // ============================================================
  // CONFIRMATION DIALOGS
  // ============================================================
  void _confirmRemoveBike(int index, String bikeName) {
    if (_isSaving || _isCommercialSnapshotLocked) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover bicicleta'),
        content: Text(
            '¿Estás seguro de que deseas quitar la bicicleta "$bikeName" de este trabajo?\n\nSe perderán los datos ingresados en esta pestaña.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _removeBikeTab(index);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkbenchContent(ThemeData theme) {
    final effectiveTab = _jobType == JobType.sale &&
            _selectedWorkbenchTab == _JobWorkbenchTab.diagnosis
        ? _JobWorkbenchTab.general
        : _selectedWorkbenchTab;
    final content = switch (effectiveTab) {
      _JobWorkbenchTab.general => _buildGeneralSection(theme),
      _JobWorkbenchTab.diagnosis => _buildDiagnosisSection(theme),
      _JobWorkbenchTab.products => _buildPartsSection(),
    };
    // Productos y Servicios protege línea por línea (paso G6): se lee
    // entera, con los precios fijos y sin acciones que cambien la venta,
    // en vez de quedar atenuada e intocable.
    final contentLocked = effectiveTab == _JobWorkbenchTab.products
        ? false
        : _isFinalQuotationReadOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWorkbenchTabs(theme),
        const SizedBox(height: 20),
        _lockFormContent(content, locked: contentLocked),
      ],
    );
  }

  Widget _buildWorkbenchTabs(ThemeData theme) {
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    if (isCompact) {
      return MechanicJobCompactWorkbenchNavigation(
        selectedIndex: _selectedWorkbenchTab.index,
        showDiagnosis: _jobType != JobType.sale,
        productsLabel: _jobType == JobType.sale ? 'Cobro' : 'Ítems',
        onSelected: (index) => _selectWorkbenchTab(
          _JobWorkbenchTab.values[index],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildWorkbenchTabButton(
              theme: theme,
              tab: _JobWorkbenchTab.general,
              icon: Icons.tune_outlined,
              label: 'General',
            ),
          ),
          const SizedBox(width: 6),
          if (_jobType != JobType.sale) ...[
            Expanded(
              child: _buildWorkbenchTabButton(
                theme: theme,
                tab: _JobWorkbenchTab.diagnosis,
                icon: Icons.medical_information_outlined,
                label: 'Diagnóstico',
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: _buildWorkbenchTabButton(
              theme: theme,
              tab: _JobWorkbenchTab.products,
              icon: Icons.shopping_basket_outlined,
              label: _jobType == JobType.sale
                  ? 'Productos y cobro'
                  : 'Productos y Servicios',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkbenchTabButton({
    required ThemeData theme,
    required _JobWorkbenchTab tab,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedWorkbenchTab == tab;

    return Material(
      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _selectWorkbenchTab(tab),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectWorkbenchTab(_JobWorkbenchTab tab) {
    if (_selectedWorkbenchTab == tab) return;
    setState(() {
      _selectedWorkbenchTab = tab;
    });

    if (!MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    )) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final workbenchContext = _workbenchSectionKey.currentContext;
      if (workbenchContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          workbenchContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.02,
        ),
      );
    });
  }

  void _updateCurrentDiagnosisSheet(
    MechanicJobDiagnosisSheet Function(MechanicJobDiagnosisSheet current)
        transform, {
    bool refresh = true,
  }) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) return;

    void apply() {
      currentTab.diagnosisSheet = transform(currentTab.diagnosisSheet);
      currentTab.diagnosisSheetKey = currentTab.diagnosisSheet.templateKey;
      currentTab.diagnosisSheetUpdatedAt = DateTime.now().toUtc();
    }

    if (refresh) {
      setState(apply);
    } else {
      apply();
    }
  }

  double? _parseNullableDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String? _normalizeNullableText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  BikeMemoryLocation _resolveWizardLocation(
    BikeMemoryLocation currentLocation,
    Map<String, dynamic> answers,
  ) {
    if (currentLocation != BikeMemoryLocation.none) {
      return currentLocation;
    }

    switch (canonicalBrakeWheelValueFromAnswers(answers)) {
      case 'front':
        return BikeMemoryLocation.front;
      case 'rear':
        return BikeMemoryLocation.rear;
      default:
        return currentLocation;
    }
  }

  bool _isBrakeServiceFamily(String? family) {
    return family == 'brake' || family == 'brakes';
  }

  bool _isWheelServiceFamily(String? family) {
    return family == 'wheels' || family == 'wheel';
  }

  /// Lo que las respuestas de un servicio de rueda o de freno le devuelven a
  /// la ficha de la bici de la pestaña actual (pasos C y D).
  WheelServiceFacts? _positionedServiceFactsFor(
    ServiceWizardProfile? serviceProfile,
    BikeMemoryLocation location,
    Map<String, dynamic> answers,
  ) {
    final family = serviceProfile?.serviceFamily;
    final isWheel = _isWheelServiceFamily(family);
    if (!isWheel && !_isBrakeServiceFamily(family)) return null;
    final bikeProfile = _bikeProfileForCurrentTab();
    final positions = serviceWheelPositions(location, answers);
    final values = bikeProfile?.technicalValues ?? const <String, dynamic>{};
    final confirmed =
        bikeProfile?.technicalConfirmed ?? const <String, dynamic>{};
    return isWheel
        ? wheelServiceFacts(
            positions: positions,
            answers: answers,
            values: values,
            confirmed: confirmed,
          )
        : brakeServiceFacts(
            positions: positions,
            answers: answers,
            values: values,
            confirmed: confirmed,
          );
  }

  bool _isBottomBracketServiceFamily(String? family) {
    return family == 'bottom_bracket';
  }

  bool _serviceProfileHasNoneOnlyTarget(ServiceWizardProfile? serviceProfile) {
    return serviceProfile?.targetPositionMode == 'none';
  }

  BikeMemoryLocation _normalizedLocationForServiceProfile(
    ServiceWizardProfile? serviceProfile,
    BikeMemoryLocation location,
  ) {
    if (_serviceProfileHasNoneOnlyTarget(serviceProfile)) {
      return BikeMemoryLocation.none;
    }
    return location;
  }

  BikeProfile? _pendingBikeProfileForBike(Bike? bike) {
    final bikeId = bike?.id;
    if (bikeId == null || bikeId.isEmpty) {
      return null;
    }

    return _pendingBikeProfileOverrides[bikeId];
  }

  BikeProfile? _bikeProfileForCurrentTab() {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) {
      return null;
    }

    final pendingProfile = _pendingBikeProfileForBike(currentTab.bike);
    if (pendingProfile != null) {
      return pendingProfile;
    }

    return _selectedBike?.id == currentTab.bike?.id
        ? _selectedBikeProfile
        : null;
  }

  _BikeTabData? _bikeTabForBike(Bike? bike) {
    final bikeId = bike?.id;
    if (bikeId == null || bikeId.isEmpty) {
      return null;
    }

    for (final tab in _bikeTabs) {
      if (!tab.isGeneralTab && tab.bike?.id == bikeId) {
        return tab;
      }
    }

    return null;
  }

  bool _bikeHasRearOnlyDrivetrain(BikeProfile? bikeProfile) {
    final drivetrainConfig =
        bikeProfile?.technicalValues['drivetrainConfig']?.toString();
    final normalizedConfig = drivetrainConfig?.trim().toLowerCase();
    if (normalizedConfig == null ||
        normalizedConfig.isEmpty ||
        normalizedConfig == 'singlespeed') {
      return false;
    }

    return drivetrainFrontChainringCountFromConfig(normalizedConfig) == '1';
  }

  Future<ServiceWizardProfile?> _loadServiceWizardProfileForProduct(
    Product? product, {
    required bool isServiceItem,
  }) async {
    if (!isServiceItem || product?.id == null) {
      return null;
    }

    final profile = await _serviceWizardService
        .getProfileForProduct(product!.id)
        .catchError((_) => null);
    return ServiceWizardService.normalizeProfile(profile);
  }

  BikeMemoryLocation _defaultServiceLocationForProfile(
    ServiceWizardProfile? serviceProfile, {
    required BikeProfile? bikeProfile,
    BikeMemoryLocation currentLocation = BikeMemoryLocation.none,
  }) {
    final normalizedLocation = _normalizedLocationForServiceProfile(
      serviceProfile,
      currentLocation,
    );
    if (normalizedLocation != BikeMemoryLocation.none) {
      return normalizedLocation;
    }

    if (currentLocation != BikeMemoryLocation.none) {
      return normalizedLocation;
    }

    if (serviceProfile?.serviceFamily != 'drivetrain') {
      return normalizedLocation;
    }

    return _bikeHasRearOnlyDrivetrain(bikeProfile)
        ? BikeMemoryLocation.rear
        : normalizedLocation;
  }

  /// Lo que la carga de la ficha completa en cada línea: su perfil de
  /// servicio y la rueda por defecto. Devuelve cambios por línea, no una
  /// lista nueva: la espera del perfil es larga y reemplazar la lista
  /// entera borraba lo configurado o movido mientras tanto (revisión de
  /// Codex, 2026-09-27).
  Future<List<_ServiceLocationHydration>?>
      _hydrateDefaultServiceLocationsForTab(
    _BikeTabData tab,
    BikeProfile? bikeProfile,
  ) async {
    if (!_bikeHasRearOnlyDrivetrain(bikeProfile)) {
      return null;
    }

    final hydrations = <_ServiceLocationHydration>[];

    for (final item in List<JobPartItem>.of(tab.partItems)) {
      ServiceWizardProfile? wizardProfile =
          ServiceWizardService.normalizeProfile(item.wizardProfile);

      if (wizardProfile == null && item.product != null) {
        wizardProfile = await _loadServiceWizardProfileForProduct(
          item.product,
          isServiceItem: item.isServiceItem,
        );
      }

      final defaultLocation = _defaultServiceLocationForProfile(
        wizardProfile,
        bikeProfile: bikeProfile,
        currentLocation: item.location,
      );

      if (wizardProfile != item.wizardProfile ||
          defaultLocation != item.location) {
        hydrations.add(_ServiceLocationHydration(
          itemId: item.id,
          profile: wizardProfile,
          fromLocation: item.location,
          toLocation: defaultLocation,
        ));
      }
    }

    return hydrations.isEmpty ? null : hydrations;
  }

  /// Aplica la hidratación sobre la lista de ahora: sólo a la línea que
  /// sigue ahí, la rueda sólo si nadie la cambió y el perfil sólo si falta.
  void _applyServiceLocationHydrations(
    _BikeTabData tab,
    List<_ServiceLocationHydration> hydrations,
  ) {
    for (final hydration in hydrations) {
      final index =
          tab.partItems.indexWhere((item) => item.id == hydration.itemId);
      if (index < 0) continue;
      final current = tab.partItems[index];
      tab.partItems[index] = current.copyWith(
        wizardProfile: current.wizardProfile ?? hydration.profile,
        location: current.location == hydration.fromLocation
            ? hydration.toLocation
            : current.location,
      );
    }
  }

  Set<BikeMemoryLocation> _availableServiceLocationsForItem(JobPartItem item) {
    final wizardProfile =
        ServiceWizardService.normalizeProfile(item.wizardProfile);
    if (_serviceProfileHasNoneOnlyTarget(wizardProfile)) {
      return const {BikeMemoryLocation.none};
    }

    if (wizardProfile?.serviceFamily == 'drivetrain' &&
        _bikeHasRearOnlyDrivetrain(_bikeProfileForCurrentTab())) {
      return const {BikeMemoryLocation.rear};
    }

    return const {
      BikeMemoryLocation.none,
      BikeMemoryLocation.front,
      BikeMemoryLocation.rear,
    };
  }

  String? _selectedBottomBracketFamilyFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    BikeProfile? bikeProfile,
    Map<String, dynamic> answers,
  ) {
    if (!_isBottomBracketServiceFamily(serviceProfile?.serviceFamily) ||
        bikeProfile == null) {
      return null;
    }

    final technicalValues = bikeProfile.technicalValues;
    final technicalConfirmed = bikeProfile.technicalConfirmed;
    final currentFamily = technicalValues['bottomBracketFamily']?.toString();
    if (isKnownBottomBracketFamily(currentFamily) &&
        technicalConfirmed['bottomBracketFamily'] == true) {
      return null;
    }

    final candidate = answers['bottom_bracket_family']?.toString();
    if (candidate == null ||
        !kBottomBracketFamilyOptions.containsKey(candidate) ||
        candidate == 'unknown') {
      return null;
    }

    return candidate;
  }

  String? _resolvedBottomBracketFamilyForWizardAnswers(
    BikeProfile bikeProfile,
    Map<String, dynamic> answers,
  ) {
    return canonicalBottomBracketFamilyValue(
      answers['bottom_bracket_family']?.toString() ??
          bikeProfile.technicalValues['bottomBracketFamily']?.toString(),
    );
  }

  double? _bottomBracketMeasurementValue(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    if (rawValue is num) {
      return rawValue.toDouble();
    }

    return _parseNullableDouble(rawValue.toString());
  }

  double? _selectedBottomBracketShellWidthFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    BikeProfile? bikeProfile,
    Map<String, dynamic> answers,
  ) {
    if (!_isBottomBracketServiceFamily(serviceProfile?.serviceFamily) ||
        bikeProfile == null) {
      return null;
    }

    final resolvedFamily =
        _resolvedBottomBracketFamilyForWizardAnswers(bikeProfile, answers);
    if (!isKnownBottomBracketFamily(resolvedFamily)) {
      return null;
    }

    final candidate =
        _bottomBracketMeasurementValue(answers['bb_shell_width_mm']);
    if (candidate == null) {
      return null;
    }

    final currentValue = _bottomBracketMeasurementValue(
      bikeProfile.technicalValues['bbShellWidthMm'] ??
          bikeProfile.technicalValues['bb_shell_width_mm'],
    );
    final confirmed = bikeProfile.technicalConfirmed['bbShellWidthMm'] == true;
    if (currentValue != null &&
        (currentValue - candidate).abs() < 0.001 &&
        confirmed) {
      return null;
    }

    return candidate;
  }

  double? _selectedBottomBracketShellDiameterFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    BikeProfile? bikeProfile,
    Map<String, dynamic> answers,
  ) {
    if (!_isBottomBracketServiceFamily(serviceProfile?.serviceFamily) ||
        bikeProfile == null) {
      return null;
    }

    final resolvedFamily =
        _resolvedBottomBracketFamilyForWizardAnswers(bikeProfile, answers);
    if (!bottomBracketFamilyUsesShellDiameter(resolvedFamily)) {
      return null;
    }

    final candidate =
        _bottomBracketMeasurementValue(answers['bb_shell_diameter_mm']);
    if (candidate == null) {
      return null;
    }

    final currentValue = _bottomBracketMeasurementValue(
      bikeProfile.technicalValues['bbShellDiameterMm'] ??
          bikeProfile.technicalValues['bb_shell_diameter_mm'],
    );
    final confirmed =
        bikeProfile.technicalConfirmed['bbShellDiameterMm'] == true;
    if (currentValue != null &&
        (currentValue - candidate).abs() < 0.001 &&
        confirmed) {
      return null;
    }

    return candidate;
  }

  String? _selectedBottomBracketSpindleInterfaceFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    BikeProfile? bikeProfile,
    Map<String, dynamic> answers,
  ) {
    if (!_isBottomBracketServiceFamily(serviceProfile?.serviceFamily) ||
        bikeProfile == null) {
      return null;
    }

    final resolvedFamily =
        _resolvedBottomBracketFamilyForWizardAnswers(bikeProfile, answers);
    if (!isKnownBottomBracketFamily(resolvedFamily)) {
      return null;
    }

    final candidate = canonicalBottomBracketSpindleInterfaceValue(
      answers['spindle_interface']?.toString(),
    );
    if (candidate == null || candidate == 'unknown') {
      return null;
    }

    final currentValue = canonicalBottomBracketSpindleInterfaceValue(
      bikeProfile.technicalValues['spindleInterface']?.toString(),
    );
    final confirmed =
        bikeProfile.technicalConfirmed['spindleInterface'] == true;
    if (currentValue == candidate && confirmed) {
      return null;
    }

    return candidate;
  }

  String? _selectedDrivetrainConfigFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    BikeProfile? bikeProfile,
    Map<String, dynamic> answers,
  ) {
    if (serviceProfile?.serviceFamily != 'drivetrain' || bikeProfile == null) {
      return null;
    }

    final derivedConfig = drivetrainConfigFromCounts(
      answers['front_chainring_count'],
      answers['rear_cog_count'],
    );
    if (derivedConfig == null) {
      return null;
    }

    final currentConfig =
        bikeProfile.technicalValues['drivetrainConfig']?.toString();
    final confirmed =
        bikeProfile.technicalConfirmed['drivetrainConfig'] == true &&
            bikeProfile.technicalConfirmed['drivetrainSpeeds'] == true;
    // Un total que no es platos × piñones también se repara: el parche ya no
    // acepta dejarlos incoherentes (20260928120000, revisión de Codex).
    final currentSpeeds = num.tryParse(
      '${bikeProfile.technicalValues['drivetrainSpeeds'] ?? ''}',
    );
    final derivedSpeeds = drivetrainSpeedsFromCounts(
      answers['front_chainring_count'],
      answers['rear_cog_count'],
    );
    if (currentConfig == derivedConfig &&
        confirmed &&
        currentSpeeds == derivedSpeeds) {
      return null;
    }

    return derivedConfig;
  }

  int? _selectedDrivetrainSpeedsFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    Map<String, dynamic> answers,
  ) {
    if (serviceProfile?.serviceFamily != 'drivetrain') {
      return null;
    }

    return drivetrainSpeedsFromCounts(
      answers['front_chainring_count'],
      answers['rear_cog_count'],
    );
  }

  String? _selectedDrivetrainFreehubTypeFromWizardAnswers(
    ServiceWizardProfile? serviceProfile,
    BikeProfile? bikeProfile,
    Map<String, dynamic> answers,
  ) {
    if (serviceProfile?.serviceFamily != 'drivetrain' || bikeProfile == null) {
      return null;
    }

    final candidate = canonicalDrivetrainFreehubTypeValue(
      answers['freehub_type']?.toString(),
    );
    if (candidate == null) {
      return null;
    }

    final currentValue = canonicalDrivetrainFreehubTypeValue(
      bikeProfile.technicalValues['freehubType']?.toString(),
    );
    final confirmed = bikeProfile.technicalConfirmed['freehubType'] == true;
    if (currentValue == candidate && confirmed) {
      return null;
    }

    return candidate;
  }

  BikeProfile? _buildPromotedBikeProfileFromServiceWizard({
    required ServiceWizardProfile? serviceProfile,
    required Map<String, dynamic> answers,
    BikeMemoryLocation location = BikeMemoryLocation.none,
  }) {
    if (_isLoadingSelectedBikeProfile || _selectedBikeProfileLoadFailed) {
      return null;
    }

    final currentTab = _currentBikeTab;
    final bike = currentTab?.bike;
    final currentProfile = _bikeProfileForCurrentTab();
    if (currentTab == null ||
        currentTab.isGeneralTab ||
        bike == null ||
        bike.id == null) {
      return null;
    }

    final effectiveProfile = currentProfile ??
        BikeProfile(
          tenantId: bike.tenantId,
          bikeId: bike.id!,
          technicalProfile: const {
            'values': <String, dynamic>{},
            'sources': <String, dynamic>{},
            'confirmed': <String, dynamic>{},
          },
        );

    final bottomBracketFamily = _selectedBottomBracketFamilyFromWizardAnswers(
      serviceProfile,
      effectiveProfile,
      answers,
    );
    final bottomBracketShellWidth =
        _selectedBottomBracketShellWidthFromWizardAnswers(
      serviceProfile,
      effectiveProfile,
      answers,
    );
    final bottomBracketShellDiameter =
        _selectedBottomBracketShellDiameterFromWizardAnswers(
      serviceProfile,
      effectiveProfile,
      answers,
    );
    final bottomBracketSpindleInterface =
        _selectedBottomBracketSpindleInterfaceFromWizardAnswers(
      serviceProfile,
      effectiveProfile,
      answers,
    );
    final drivetrainConfig = _selectedDrivetrainConfigFromWizardAnswers(
      serviceProfile,
      effectiveProfile,
      answers,
    );
    final drivetrainSpeeds = _selectedDrivetrainSpeedsFromWizardAnswers(
      serviceProfile,
      answers,
    );
    final drivetrainFreehubType =
        _selectedDrivetrainFreehubTypeFromWizardAnswers(
      serviceProfile,
      effectiveProfile,
      answers,
    );
    final wheelFacts =
        _positionedServiceFactsFor(serviceProfile, location, answers);
    if ((wheelFacts == null || wheelFacts.isEmpty) &&
        bottomBracketFamily == null &&
        bottomBracketShellWidth == null &&
        bottomBracketShellDiameter == null &&
        bottomBracketSpindleInterface == null &&
        drivetrainConfig == null &&
        drivetrainFreehubType == null) {
      return null;
    }

    final technicalValues =
        Map<String, dynamic>.from(effectiveProfile.technicalValues);
    final technicalSources =
        Map<String, dynamic>.from(effectiveProfile.technicalSources);
    final technicalConfirmed =
        Map<String, dynamic>.from(effectiveProfile.technicalConfirmed);

    var didChange = false;
    // Una sugerencia sola, vista en una rueda, no renueva «Última
    // confirmación» de la ficha.
    var didConfirm = false;

    if (bottomBracketFamily != null) {
      if (technicalValues['bottomBracketFamily']?.toString() !=
              bottomBracketFamily ||
          technicalConfirmed['bottomBracketFamily'] != true) {
        technicalValues['bottomBracketFamily'] = bottomBracketFamily;
        technicalSources['bottomBracketFamily'] = 'mechanic';
        technicalConfirmed['bottomBracketFamily'] = true;
        didChange = true;
        didConfirm = true;
      }

      if (!bottomBracketFamilyUsesShellDiameter(bottomBracketFamily) &&
          technicalValues.containsKey('bbShellDiameterMm')) {
        technicalValues.remove('bbShellDiameterMm');
        technicalSources.remove('bbShellDiameterMm');
        technicalConfirmed.remove('bbShellDiameterMm');
        didChange = true;
        didConfirm = true;
      }
    }

    if (bottomBracketShellWidth != null) {
      final currentValue = _bottomBracketMeasurementValue(
        technicalValues['bbShellWidthMm'] ??
            technicalValues['bb_shell_width_mm'],
      );
      if (currentValue == null ||
          (currentValue - bottomBracketShellWidth).abs() >= 0.001 ||
          technicalConfirmed['bbShellWidthMm'] != true) {
        technicalValues['bbShellWidthMm'] = bottomBracketShellWidth;
        technicalSources['bbShellWidthMm'] = 'mechanic';
        technicalConfirmed['bbShellWidthMm'] = true;
        didChange = true;
        didConfirm = true;
      }
    }

    if (bottomBracketShellDiameter != null) {
      final currentValue = _bottomBracketMeasurementValue(
        technicalValues['bbShellDiameterMm'] ??
            technicalValues['bb_shell_diameter_mm'],
      );
      if (currentValue == null ||
          (currentValue - bottomBracketShellDiameter).abs() >= 0.001 ||
          technicalConfirmed['bbShellDiameterMm'] != true) {
        technicalValues['bbShellDiameterMm'] = bottomBracketShellDiameter;
        technicalSources['bbShellDiameterMm'] = 'mechanic';
        technicalConfirmed['bbShellDiameterMm'] = true;
        didChange = true;
        didConfirm = true;
      }
    }

    if (bottomBracketSpindleInterface != null) {
      if (technicalValues['spindleInterface']?.toString() !=
              bottomBracketSpindleInterface ||
          technicalConfirmed['spindleInterface'] != true) {
        technicalValues['spindleInterface'] = bottomBracketSpindleInterface;
        technicalSources['spindleInterface'] = 'mechanic';
        technicalConfirmed['spindleInterface'] = true;
        didChange = true;
        didConfirm = true;
      }
    }

    if (drivetrainConfig != null) {
      if (technicalValues['drivetrainConfig']?.toString() != drivetrainConfig ||
          technicalValues['drivetrainSpeeds'] != drivetrainSpeeds ||
          technicalConfirmed['drivetrainConfig'] != true ||
          technicalConfirmed['drivetrainSpeeds'] != true) {
        technicalValues['drivetrainConfig'] = drivetrainConfig;
        if (drivetrainSpeeds != null) {
          technicalValues['drivetrainSpeeds'] = drivetrainSpeeds;
        }
        technicalSources['drivetrainConfig'] = 'mechanic';
        technicalConfirmed['drivetrainConfig'] = true;
        technicalSources['drivetrainSpeeds'] = 'mechanic';
        technicalConfirmed['drivetrainSpeeds'] = true;
        didChange = true;
        didConfirm = true;
      }
    }

    // Rueda y freno: lo confirmado sube como dato del mecánico; lo visto en
    // una sola rueda de un dato de toda la bici, como sugerencia sin confirmar.
    if (wheelFacts != null) {
      wheelFacts.confirm.forEach((key, value) {
        technicalValues[key] = value;
        technicalSources[key] = 'mechanic';
        technicalConfirmed[key] = true;
        didChange = true;
        didConfirm = true;
      });
      wheelFacts.suggest.forEach((key, value) {
        technicalValues[key] = value;
        technicalSources[key] = kServiceSuggestionSource;
        technicalConfirmed.remove(key);
        didChange = true;
      });
    }

    if (drivetrainFreehubType != null) {
      if (technicalValues['freehubType']?.toString() != drivetrainFreehubType ||
          technicalConfirmed['freehubType'] != true) {
        technicalValues['freehubType'] = drivetrainFreehubType;
        technicalSources['freehubType'] = 'mechanic';
        technicalConfirmed['freehubType'] = true;
        didChange = true;
        didConfirm = true;
      }
    }

    if (!didChange) {
      return null;
    }

    final confirmedAt =
        didConfirm ? DateTime.now() : effectiveProfile.lastConfirmedAt;
    final summarySnapshot = <String, dynamic>{
      ...effectiveProfile.summarySnapshot,
      ...BikeProfileSummaryBuilder.buildSummarySnapshot(
        bike: bike,
        intakeProfile: effectiveProfile.intakeProfile,
        technicalValues: technicalValues,
        lastConfirmedAt: confirmedAt,
      ),
    };
    final technicalProfile = <String, dynamic>{
      ...effectiveProfile.technicalProfile,
      'values': technicalValues,
      'sources': technicalSources,
      'confirmed': technicalConfirmed,
    };

    return effectiveProfile.copyWith(
      technicalProfile: technicalProfile,
      summarySnapshot: summarySnapshot,
      lastConfirmedAt: confirmedAt,
      updatedAt: effectiveProfile.updatedAt,
    );
  }

  void _discardPendingBikeProfilePromotion(String bikeId) {
    _pendingBikeProfileOverrides.remove(bikeId);
    _pendingBikeProfileBaselines.remove(bikeId);
    _pendingBikeProfileOperationKeys.remove(bikeId);
  }

  /// Lo que «Configurar» dejó pendiente para cada bici, con su llave, para
  /// entregárselo al formulario del trabajo ya guardado.
  Map<String, PendingBikeFactPromotion> _pendingBikeFactPromotions() => {
        for (final entry in _pendingBikeProfileOverrides.entries)
          entry.key: PendingBikeFactPromotion(
            operationKey: _pendingBikeProfileOperationKeys.putIfAbsent(
              entry.key,
              () => const Uuid().v4(),
            ),
            baseline: _pendingBikeProfileBaselines[entry.key],
            target: entry.value,
          ),
      };

  /// Un aviso de ficha no escrita queda a la vista hasta que el mecánico lo
  /// cierra: pide una acción suya, y un aviso breve se pierde al salir.
  void _showBikeFactOutcome(String? problem, {String? success}) {
    if (problem == null && success == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(problem ?? success!),
        backgroundColor:
            problem == null ? Colors.green : Colors.orange.shade800,
        action: problem == null
            ? null
            : SnackBarAction(
                label: 'Entendido',
                textColor: Colors.white,
                onPressed: () {},
              ),
      ),
    );
  }

  /// Guarda las líneas del trabajo y lo que confirmó «Configurar» en un solo
  /// comando con recibo (`save_mechanic_job_lines_v1`, ítem 4): o quedan las
  /// dos cosas o ninguna. [lines] en null deja las líneas como están (un
  /// trabajo con pago) y sólo lleva la ficha. El comando se respalda en la
  /// bandeja del equipo antes de enviarse; cabecera, fotos y estado no van en
  /// él: se escriben antes (cabecera y fotos) y después (estado), cada uno por
  /// su lado.
  ///
  /// Devuelve un aviso por cada promoción que no se pudo armar. Lanza si nada
  /// se guardó: si otra persona cambió las líneas
  /// ([JobLinesChangedException]), o si la ficha de una bici no tomó el dato;
  /// en ese caso lo de «Configurar» para esa bici sale del formulario, para
  /// que el siguiente guardado pase, y la ficha se vuelve a leer. Sin
  /// respuesta del servidor ([JobLineSavePendingException]) el comando sigue
  /// en la bandeja y el formulario recuerda su llave.
  /// Lo que no tomó la ficha, y el recibo del comando (null si no hubo nada
  /// que mandar).
  Future<({List<String> problems, JobLineSaveResult? result})>
      _saveLinesWithBikeFacts({
    required BikeshopService bikeshopService,
    required String jobId,
    required List<JobLineToSave>? lines,
    required Map<String, Map<String, dynamic>> header,
    required String label,
    List<JobBikeToSave>? jobBikes,
    bool includeBikeFacts = true,
    bool invoice = false,
    List<PendingWorkshopCommand> followUps = const [],
    PendingWorkshopCommand? creation,
    void Function(MechanicJob job)? onCreated,
  }) async {
    final problems = <String>[];
    final promotions = includeBikeFacts
        ? _pendingBikeFactPromotions()
        : const <String, PendingBikeFactPromotion>{};
    final bikeFacts = <String, List<BikeTechnicalFact>>{};
    for (final entry in promotions.entries) {
      try {
        bikeFacts[entry.key] = bikeTechnicalFactsDiff(
          baseline: entry.value.baseline,
          target: entry.value.target,
        );
      } on StateError catch (error) {
        problems.add(
          '${_bikeLabelForPendingPromotion(entry.key)}: ${error.message}',
        );
        _discardPendingBikeProfilePromotion(entry.key);
      }
    }

    // Un trabajo nuevo siempre manda su alta con sus líneas.
    if (creation == null &&
        lines == null &&
        header.isEmpty &&
        (jobBikes == null || jobBikes.isEmpty) &&
        bikeFacts.values.every((facts) => facts.isEmpty)) {
      _forgetWrittenPromotions(promotions, bikeFacts.keys);
      // Sin líneas que mandar, lo que las seguía se respalda igual antes de
      // enviarse, en orden.
      if (followUps.isNotEmpty) {
        await bikeshopService.stageJobCommands(
          followUps.first,
          followUps: followUps.sublist(1),
        );
      }
      return (problems: problems, result: null);
    }

    final params = bikeshopService.buildJobLineSaveParams(
      jobId: jobId,
      seenLines: lines == null
          ? null
          : [
              for (final entry in _seenLineVersions.entries)
                JobLineVersion(id: entry.key, version: entry.value),
            ],
      lines: lines,
      bikeFacts: bikeFacts,
      header: header,
      jobBikes: jobBikes,
      invoice: invoice,
    );
    // Cada guardado lleva su llave. Un reintento del mismo no pasa por aquí:
    // lo reenvía la bandeja tal como se respaldó ([_settlePendingLineSave]).
    final pendingSave = _PendingLineSave.sent(
      operationKey: const Uuid().v4(),
      jobId: jobId,
      promotions: promotions,
      bikeIds: bikeFacts.keys.toSet(),
      creation: creation,
      headerShown: _headerMirror(
        protect: _isPaymentProtectedCommercialSnapshotLocked,
      ),
    );
    _pendingLineSave = pendingSave;

    final JobLineSaveResult result;
    try {
      if (creation != null) {
        // El alta, sus líneas y lo que las sigue se respaldan juntos antes
        // del primer envío, y salen en ese orden.
        result = (await bikeshopService.createJobWithLines(
          creation: creation,
          lineOperationKey: pendingSave.operationKeys.single,
          lineParams: params,
          label: label,
          followUps: followUps,
          onCreated: onCreated,
        ))
            .lines;
      } else {
        result = await bikeshopService.saveJobLines(
          operationKey: pendingSave.operationKeys.single,
          params: params,
          label: label,
          followUps: followUps,
        );
      }
    } on JobCreationPendingException {
      // Ni el alta llegó: todo sigue en la bandeja, con su llave, y el
      // próximo Guardar lo resuelve primero. No hay trabajo creado.
      rethrow;
    } on JobCreationRejectedException {
      // El alta no se aceptó y lo que la seguía salió con ella.
      _pendingLineSave = null;
      rethrow;
    } on JobLineSavePendingException catch (pending) {
      // Sigue en la bandeja con su llave; el formulario la recuerda. Lo que
      // lo seguía quedó detrás, respaldado.
      if (followUps.isEmpty) rethrow;
      // Si detrás va la decisión de garantía, el panel la dice pendiente
      // desde ya, leída de la bandeja, no al guardar otra vez.
      if (followUps.any((command) =>
          command.kind == WorkshopCommandKind.jobWarrantyDecision)) {
        try {
          final decision = await bikeshopService.pendingWarrantyDecision(jobId);
          if (mounted) setState(() => _pendingWarrantyDecision = decision);
        } catch (error) {
          debugPrint('Could not read the pending warranty decision: $error');
        }
      }
      throw _JobLinesPendingWithFollowUps(pending, followUps);
    } on JobLineSaveBikeFactException catch (error) {
      _pendingLineSave = null;
      throw await _stopForBikeFactRejection(error);
    } on WorkshopOutboxPersistenceException {
      // El respaldo pudo quedar a medias (cada llave es una escritura): el
      // formulario conserva estas llaves y el próximo Guardar resuelve primero
      // lo que haya quedado de ellas. Olvidarlas dejaba reusar la llave del
      // alta con otro contenido mientras la anterior seguía en la bandeja
      // (revisión de Codex del alta, 2026-09-29).
      rethrow;
    } catch (_) {
      _pendingLineSave = null;
      rethrow;
    }
    _pendingLineSave = null;
    _adoptLineSave(result, pendingSave);
    return (problems: problems, result: result);
  }

  /// El cambio de estado que pide este guardado, con su llave (la misma al
  /// reintentar el mismo cambio), o null si no pide ninguno. [statusId] nulo
  /// es un estado de los de antes, que se resuelve por su código.
  ({String operationKey, String? statusId})? _plannedStatusTransition() {
    if (_savedJobId == null || _isStatusTransitionLocked) return null;
    final existingStatusId = _existingJob?.statusId;
    final targetStatusId = _selectedCustomStatus?.id;
    final needsCustomTransition = targetStatusId != null &&
        targetStatusId.isNotEmpty &&
        targetStatusId != existingStatusId;
    final needsLegacyTransition =
        targetStatusId == null && _existingJob?.status != _selectedStatus;
    if (!needsCustomTransition && !needsLegacyTransition) return null;
    final fingerprint = targetStatusId ?? _selectedStatus.dbValue;
    if (_pendingStatusTransitionFingerprint != fingerprint) {
      _pendingStatusTransitionFingerprint = fingerprint;
      _pendingStatusTransitionOperationKey = const Uuid().v4();
    }
    return (
      operationKey: _pendingStatusTransitionOperationKey!,
      statusId: needsCustomTransition ? targetStatusId : null,
    );
  }

  /// La decisión de garantía de este trabajo que sigue en la bandeja se
  /// envía antes de escribir otra cosa. Si se aplica, es la cobertura del
  /// trabajo (también la que se tomó desde la tabla) y el formulario la da
  /// por confirmada: el guardado no la repite y lleva su factura al día. Si
  /// sigue sin respuesta, no se escribe encima. Si el servidor no la acepta,
  /// se dice y se detiene: lo que venía detrás ya salió con ella.
  Future<void> _settlePendingWarrantyDecision(
    BikeshopService bikeshopService,
  ) async {
    final jobId = _savedJobId;
    if (jobId == null) return;
    final pending = await bikeshopService.pendingWarrantyDecision(jobId);
    if (pending == null) {
      if (_pendingWarrantyDecision != null && mounted) {
        setState(() => _pendingWarrantyDecision = null);
      }
      return;
    }
    try {
      await bikeshopService.decideWarrantyClaim(
        warrantyJobId: jobId,
        outcome: pending.outcome,
        reason: pending.reason,
        operationKey: pending.operationKey,
      );
    } on MechanicJobWarrantyDecisionPending {
      if (mounted) setState(() => _pendingWarrantyDecision = pending);
      throw const _JobSaveStopped(
        'La decisión de garantía anterior de este trabajo sigue sin '
        'respuesta del servidor. Está respaldada en este equipo con su llave '
        'y se aplica sola; para no escribir encima, este guardado no hizo '
        'nada. Vuelve a guardar cuando haya conexión.',
      );
    } catch (error) {
      if (mounted) setState(() => _pendingWarrantyDecision = null);
      throw _JobSaveStopped(
        'La decisión de garantía anterior de este trabajo no se aplicó '
        '($error). Revisa la garantía y vuelve a guardar.',
      );
    }
    if (!mounted) return;
    setState(() {
      _warrantyOutcome = pending.outcome;
      _warrantySaveCheckpoint.confirmDecision(pending.outcome);
      _pendingWarrantyDecision = null;
      _pendingWarrantyDecisionOperationKey = null;
      _pendingWarrantyDecisionFingerprint = null;
    });
  }

  /// La ficha no tomó lo de «Configurar» y, con ella, las líneas tampoco se
  /// guardaron. Lo que se armó sobre la ficha vieja ya no vale: sale, la
  /// ficha se vuelve a leer y «Configurar» arma lo nuevo sobre la vigente.
  /// Hasta entonces el trabajo no se guarda.
  Future<_JobSaveStopped> _stopForBikeFactRejection(
    JobLineSaveBikeFactException error,
  ) async {
    final label = _bikeLabelForPendingPromotion(error.bikeId);
    _discardPendingBikeProfilePromotion(error.bikeId);
    if (mounted) await _loadSelectedBikeProfile(_selectedBike);
    final cause = error.cause;
    final reason = cause is BikeTechnicalFactConflict
        ? '$label: la ficha cambió mientras el trabajo estaba abierto'
            '${cause.keys.isEmpty ? '' : ' (${cause.keys.join(', ')})'}'
        : '$label: el servidor rechazó el dato de la ficha ($cause)';
    _bikeFactsAwaitingReconfirmation[error.bikeId] =
        '$reason. Vuelve a Configurar el servicio de esa bici (o quítalo) '
        'antes de guardar el trabajo.';
    return _JobSaveStopped(
      '$reason, así que las líneas no se guardaron. Vuelve a Configurar el '
      'servicio de esa bici con la ficha vigente (o quítalo) y guarda de '
      'nuevo.',
    );
  }

  /// El alta de este formulario llegó (con su recibo): el formulario pasa a
  /// ser el del trabajo creado. La cabecera como quedó es lo visto para el
  /// guardado siguiente.
  void _adoptCreatedJob(MechanicJob job) {
    _createdJob = job;
    _existingJob = job;
    _headerBaseline = Map<String, dynamic>.of(job.persistedHeader ?? {});
  }

  /// Lo que dejó escrito un guardado de líneas de este formulario pasa al
  /// formulario: cada línea nueva adopta su id, todas su versión y lo de
  /// «Configurar» ya escrito sale. Las tareas de las líneas nuevas no se
  /// crean aquí: nacieron con ellas en el comando, también cuando lo
  /// confirma la reanudación o la consulta del recibo.
  void _adoptLineSave(JobLineSaveResult result, _PendingLineSave save) {
    // La cabecera como quedó es lo visto para el guardado siguiente.
    final header = result.header;
    if (header != null) {
      _headerBaseline = {..._headerBaseline, ...header};
    }
    // Una bici nueva adopta el id que tomó en el comando, y cada una lo que
    // quedó como lo visto para el guardado siguiente.
    final savedJobBikes = result.jobBikes;
    if (savedJobBikes != null) {
      _jobBikeBaseline
        ..clear()
        ..addAll({for (final saved in savedJobBikes) saved.id: saved.row});
      for (final saved in savedJobBikes) {
        for (final tab in _bikeTabs) {
          if (!tab.isGeneralTab && tab.bike?.id == saved.bikeId) {
            tab.jobBikeId = saved.id;
          }
        }
      }
      _shownJobBikeIds
        ..clear()
        ..addAll({
          for (final tab in _bikeTabs)
            if (!tab.isGeneralTab &&
                tab.jobBikeId != null &&
                _jobBikeBaseline.containsKey(tab.jobBikeId))
              tab.jobBikeId!,
        });
    }
    // Desde aquí, lo editado se mide contra lo que se mandó: lo que queda a
    // la vista si se adopta al tiro, y no lo editado después si el recibo
    // llega en un guardado posterior (cierre del Master Schema, 2026-09-29).
    _headerShown = save.headerShown ??
        _headerMirror(
          protect: _isPaymentProtectedCommercialSnapshotLocked,
        );
    final savedLines = result.lines;
    if (savedLines != null) {
      // Una línea nueva adopta su id de la base, y todas su versión: el
      // próximo guardado las actualiza en vez de insertarlas otra vez.
      for (final line in savedLines) {
        final clientKey = line.clientKey;
        if (clientKey == null || clientKey == line.id) continue;
        if (clientKey.startsWith('labor-')) {
          _laborLinePersistedIds[clientKey.substring('labor-'.length)] =
              line.id;
        } else {
          _adoptPersistedLineId(clientKey, line.id);
        }
      }
      _seenLineVersions
        ..clear()
        ..addAll({for (final line in savedLines) line.id: line.version});
      // Un trabajo terminado pudo cambiar la ficha al guardar: se vuelve a
      // leer qué escribió cada línea.
      unawaited(_loadPartChangeWriters());
    }

    _forgetWrittenPromotions(save.promotions, save.bikeIds);
    final selectedBikeId = _selectedBike?.id;
    final refreshedProfile = selectedBikeId == null
        ? null
        : result.bikeFacts[selectedBikeId]?.profile;
    if (refreshedProfile != null) {
      if (mounted) {
        setState(() => _selectedBikeProfile = refreshedProfile);
      } else {
        _selectedBikeProfile = refreshedProfile;
      }
    }
  }

  /// Resuelve el guardado de líneas que quedó sin respuesta antes de escribir
  /// otra cosa. Si llegó, el formulario adopta su recibo (o, si era de un
  /// formulario anterior, recarga el trabajo y se detiene: las líneas a la
  /// vista no lo tenían). Si sigue sin respuesta, se detiene sin escribir. Si
  /// el servidor no lo aplicó, lo dice como lo habría dicho entonces.
  Future<void> _settlePendingLineSave(BikeshopService bikeshopService) async {
    final pending = _pendingLineSave;
    if (pending == null) return;
    // Un trabajo nuevo: su alta va antes que sus líneas. Si sigue sin
    // respuesta, nada más se envía; si no se creó, este guardado la manda de
    // nuevo; si llegó, el formulario pasa a ser el del trabajo creado y lo
    // editado después viaja como cambio.
    final creation = pending.creation;
    if (creation != null) {
      final MechanicJob? created;
      try {
        created = await bikeshopService.settleJobCreation(creation);
      } on JobCreationPendingException {
        throw const _JobSaveStopped(
          'El trabajo nuevo sigue sin respuesta del servidor: todavía no está '
          'creado. Está respaldado en este equipo, con sus líneas, y se envía '
          'solo; para no mandarlo dos veces, este guardado no hizo nada. '
          'Vuelve a guardar cuando haya conexión.',
        );
      } on WorkshopOutboxPersistenceException {
        // Un fallo local al resolverlo tampoco lo olvida: sigue en la
        // bandeja y el próximo Guardar lo intenta de nuevo (segunda revisión
        // de Codex del alta, 2026-09-29).
        rethrow;
      } catch (_) {
        _pendingLineSave = null;
        rethrow;
      }
      if (created == null) {
        _pendingLineSave = null;
        return;
      }
      _adoptCreatedJob(created);
    }
    var wrote = false;
    for (final operationKey in pending.operationKeys) {
      final JobLineSaveResult? result;
      try {
        result = await bikeshopService.settleJobLineSave(operationKey);
      } on JobLineSavePendingException {
        throw const _JobSaveStopped(
          'El guardado anterior de las líneas de este trabajo sigue sin '
          'respuesta del servidor. Está respaldado en este equipo con su '
          'llave y se envía solo; para no escribir encima, este guardado no '
          'hizo nada. Vuelve a guardar cuando haya conexión.',
        );
      } on JobLineSaveBikeFactException catch (error) {
        _pendingLineSave = null;
        if (!pending.fromThisForm) continue;
        throw await _stopForBikeFactRejection(error);
      } on WorkshopOutboxPersistenceException {
        rethrow;
      } catch (_) {
        _pendingLineSave = null;
        if (!pending.fromThisForm) continue;
        rethrow;
      }
      if (result == null) continue;
      wrote = true;
      if (pending.fromThisForm) _adoptLineSave(result, pending);
    }
    _pendingLineSave = null;
    if (wrote && !pending.fromThisForm) {
      await _loadExistingJob();
      throw const _JobSaveStopped(
        'Llegó el guardado de las líneas que había quedado pendiente en este '
        'equipo y el trabajo se recargó con él. Revisa y vuelve a guardar lo '
        'que hayas cambiado después.',
      );
    }
  }

  /// Reenvía lo que la bandeja del equipo guarda de [jobId] y devuelve las
  /// llaves de los guardados de líneas que siguen sin respuesta. Una bandeja
  /// que no se deja leer no impide abrir el trabajo: su guardado tampoco
  /// podría respaldar nada y se detiene ahí.
  Future<List<String>> _resumePendingLineSaves(
    BikeshopService bikeshopService,
    String jobId,
  ) async {
    try {
      final runs = await bikeshopService.resumePendingBikeCommands(
        jobId: jobId,
      );
      if (mounted) {
        for (final run in runs) {
          final continuation =
              run.command.kind == WorkshopCommandKind.jobInvoiceContinuation;
          if (run.command.kind != WorkshopCommandKind.jobLineSave &&
              run.command.kind != WorkshopCommandKind.jobWarrantyDecision &&
              !continuation) {
            continue;
          }
          // Al abrir el trabajo se dice también que su factura sigue
          // pendiente; la reanudación periódica no lo repite.
          final notice =
              workshopCommandNotice(run, includeOffline: continuation);
          if (notice != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(notice)),
            );
          }
        }
      }
      return await bikeshopService.pendingJobLineSaves(jobId);
    } catch (error) {
      debugPrint('⚠️ No se pudo revisar la bandeja del trabajo: $error');
      return const [];
    }
  }

  /// Cómo se nombra en los avisos un trabajo nuevo antes de tener número.
  String _newJobCommandLabel() {
    final customer = _selectedCustomer?.name.trim();
    return customer == null || customer.isEmpty
        ? 'Trabajo nuevo'
        : 'Trabajo nuevo de $customer';
  }

  String _jobCommandLabel(MechanicJob job) {
    final reference = _jobReference(job);
    return reference.startsWith('Trabajo') ? reference : 'Trabajo $reference';
  }

  /// Las líneas cuyo campo de cantidad no dice una cantidad, en cualquier
  /// pestaña (una pestaña que no se ve no valida su campo).
  List<String> _linesWithIncompleteQuantity() => [
        for (final item in [
          for (final tab in _bikeTabs) ...tab.partItems,
          if (_bikeTabs.isEmpty) ..._partItems,
        ])
          if (item.name.isNotEmpty && item.quantityDraft != null)
            '«${item.displayName}»',
      ];

  /// Los avisos de las bicis que esperan reconfirmar lo de «Configurar». Una
  /// bici que salió del trabajo, o que ya no tiene servicios configurados, no
  /// espera nada: no queda línea que diga otra cosa que la ficha.
  List<String> _bikesAwaitingReconfirmation() {
    _bikeFactsAwaitingReconfirmation.removeWhere((bikeId, _) {
      final tab = _bikeTabs
          .where((tab) => !tab.isGeneralTab && tab.bike?.id == bikeId)
          .firstOrNull;
      return tab == null ||
          !tab.partItems
              .any((item) => _effectiveWizardAnswersForItem(item) != null);
    });
    return _bikeFactsAwaitingReconfirmation.values.toList();
  }

  /// Lo de «Configurar» que ya quedó en la ficha sale del formulario, salvo
  /// que se haya vuelto a promover esa bici mientras se guardaba (llave nueva).
  void _forgetWrittenPromotions(
    Map<String, PendingBikeFactPromotion> promotions,
    Iterable<String> bikeIds,
  ) {
    for (final bikeId in bikeIds.toList()) {
      if (_pendingBikeProfileOperationKeys[bikeId] ==
          promotions[bikeId]?.operationKey) {
        _discardPendingBikeProfilePromotion(bikeId);
      }
    }
  }

  String _bikeLabelForPendingPromotion(String bikeId) {
    final bike = _bikeTabs
        .map((tab) => tab.bike)
        .where((bike) => bike?.id == bikeId)
        .firstOrNull;
    final label = [bike?.brand, bike?.model]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    return label.isEmpty ? 'Bicicleta' : label;
  }

  String? _firstMatchingWizardOption(
    ServiceProfileQuestion? question,
    List<String> candidates,
  ) {
    if (question == null) {
      return null;
    }

    final options = question.options.map((option) => option.value).toSet();
    for (final candidate in candidates) {
      if (options.contains(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String? _wizardLocationAnswer(
    ServiceProfileQuestion? question,
    BikeMemoryLocation location,
  ) {
    switch (location) {
      case BikeMemoryLocation.front:
        return _firstMatchingWizardOption(
            question, const ['front', 'delantero']);
      case BikeMemoryLocation.rear:
        return _firstMatchingWizardOption(question, const ['rear', 'trasero']);
      case BikeMemoryLocation.left:
        return _firstMatchingWizardOption(
            question, const ['left', 'izquierdo']);
      case BikeMemoryLocation.right:
        return _firstMatchingWizardOption(question, const ['right', 'derecho']);
      case BikeMemoryLocation.center:
        return _firstMatchingWizardOption(question, const ['center', 'centro']);
      case BikeMemoryLocation.none:
        return null;
    }
  }

  String? _mappedBrakeTypeWizardAnswer(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawBrakeType == null || rawBrakeType.isEmpty) {
      return null;
    }

    switch (rawBrakeType) {
      case 'hydraulic_disc':
        return _firstMatchingWizardOption(
          question,
          const ['hydraulic_disc', 'hidraulico'],
        );
      case 'mechanical_disc':
        return _firstMatchingWizardOption(
          question,
          const ['mechanical_disc', 'disco_mec', 'mecanico'],
        );
      case 'rim':
        final exactFamily = _mappedRimBrakeFamilyWizardAnswer(
          rawRimBrakeFamily,
          question,
        );
        if (exactFamily != null) {
          return exactFamily;
        }
        if (rawRimBrakeFamily == null ||
            rawRimBrakeFamily.isEmpty ||
            rawRimBrakeFamily == 'unknown') {
          final genericRim = _firstMatchingWizardOption(
            question,
            const ['rim', 'llanta'],
          );
          if (genericRim != null) {
            return genericRim;
          }
          return _firstMatchingWizardOption(
            question,
            const ['mechanical_disc', 'disco_mec', 'mecanico'],
          );
        }
        return null;
      case 'roller_brake':
        return _firstMatchingWizardOption(
          question,
          const ['roller_brake', 'roller'],
        );
      case 'drum_brake':
        return _firstMatchingWizardOption(
          question,
          const ['drum_brake', 'tambor', 'drum'],
        );
      case 'coaster_brake':
        return _firstMatchingWizardOption(
          question,
          const ['coaster_brake', 'contrapedal', 'coaster'],
        );
      case 'band_brake':
        return _firstMatchingWizardOption(
          question,
          const ['band_brake', 'banda', 'band'],
        );
      default:
        return null;
    }
  }

  String? _mappedMechanicalBrakeTypeWizardAnswer(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawBrakeType == null || rawBrakeType.isEmpty) {
      return null;
    }

    switch (rawBrakeType) {
      case 'mechanical_disc':
        return _firstMatchingWizardOption(
          question,
          const ['mechanical_disc', 'disco_mec', 'mecanico'],
        );
      case 'rim':
        return _mappedRimBrakeFamilyWizardAnswer(
          rawRimBrakeFamily,
          question,
        );
      default:
        return null;
    }
  }

  String? _mappedRimBrakeFamilyWizardAnswer(
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null ||
        rawRimBrakeFamily == null ||
        rawRimBrakeFamily.isEmpty) {
      return null;
    }

    final hints = switch (rawRimBrakeFamily) {
      'v_brake' => const ['v_brake', 'v-brake', 'v brake', 'vbrake'],
      'cantilever' => const ['cantilever', 'canti'],
      'road_caliper_short_reach' => const [
          'road_caliper_short_reach',
          'short reach',
          'caliper corto',
          'caliper',
          'ruta'
        ],
      'road_caliper_long_reach' => const [
          'road_caliper_long_reach',
          'long reach',
          'caliper largo',
          'caliper',
          'ruta'
        ],
      'u_brake' => const ['u_brake', 'u-brake', 'u brake', 'ubrake'],
      'rod_brake' => const ['rod_brake', 'varilla', 'rod brake'],
      _ => const <String>[],
    };

    if (hints.isEmpty) {
      return null;
    }

    return _firstMatchingWizardOption(question, hints);
  }

  String? _mappedBottomBracketFamilyWizardAnswer(
    String? rawBottomBracketFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null ||
        rawBottomBracketFamily == null ||
        rawBottomBracketFamily.isEmpty) {
      return null;
    }

    return _firstMatchingWizardOption(question, [rawBottomBracketFamily]);
  }

  String? _normalizedWizardMeasurementValue(dynamic rawValue) {
    final parsedValue = _bottomBracketMeasurementValue(rawValue);
    if (parsedValue == null) {
      return null;
    }

    if (parsedValue == parsedValue.roundToDouble()) {
      return parsedValue.toInt().toString();
    }

    return parsedValue.toStringAsFixed(1);
  }

  String? _mappedBottomBracketMeasurementWizardAnswer(
    dynamic rawMeasurement,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawMeasurement == null) {
      return null;
    }

    final normalizedValue = _normalizedWizardMeasurementValue(rawMeasurement);
    if (normalizedValue == null) {
      return null;
    }

    final rawString = rawMeasurement.toString().trim();
    return _firstMatchingWizardOption(
      question,
      [normalizedValue, if (rawString.isNotEmpty) rawString],
    );
  }

  String? _mappedBottomBracketSpindleInterfaceWizardAnswer(
    String? rawSpindleInterface,
    ServiceProfileQuestion? question,
  ) {
    if (question == null ||
        rawSpindleInterface == null ||
        rawSpindleInterface.isEmpty) {
      return null;
    }

    final canonicalValue =
        canonicalBottomBracketSpindleInterfaceValue(rawSpindleInterface);
    if (canonicalValue == null) {
      return null;
    }

    return _firstMatchingWizardOption(question, [canonicalValue]);
  }

  bool _needsRimBrakeFamilyConfirmation(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
  ) {
    return rawBrakeType == 'rim' &&
        (rawRimBrakeFamily == null ||
            rawRimBrakeFamily.isEmpty ||
            rawRimBrakeFamily == 'unknown');
  }

  String? _mappedRotorSizeWizardAnswer(
    ServiceProfileQuestion? question,
    Map<String, dynamic> technicalValues,
    BikeMemoryLocation location,
  ) {
    if (question == null) {
      return null;
    }

    final rawValue = switch (location) {
      BikeMemoryLocation.front => technicalValues['frontRotorSizeMm'],
      BikeMemoryLocation.rear => technicalValues['rearRotorSizeMm'],
      _ => null,
    };
    if (rawValue == null) {
      return null;
    }

    final normalized = rawValue.toString().trim();
    return _firstMatchingWizardOption(question, [normalized]);
  }

  List<String>? _mappedDerailleursWizardAnswer(
    String? drivetrainConfig,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || question.questionType != 'multi_select') {
      return null;
    }

    final normalized = drivetrainConfig?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final options = question.options.map((option) => option.value).toSet();
    if (normalized.startsWith('1x') && options.contains('rear')) {
      return const ['rear'];
    }

    if (normalized.startsWith('2x') || normalized.startsWith('3x')) {
      if (!(options.contains('front') && options.contains('rear'))) {
        return null;
      }
      return const ['front', 'rear'];
    }

    return null;
  }

  String? _mappedDrivetrainFrontChainringCountWizardAnswer(
    String? drivetrainConfig,
    ServiceProfileQuestion? question,
  ) {
    final frontCount =
        drivetrainFrontChainringCountFromConfig(drivetrainConfig);
    if (frontCount == null) {
      return null;
    }
    return _firstMatchingWizardOption(question, [frontCount]);
  }

  String? _mappedDrivetrainRearCogCountWizardAnswer(
    String? drivetrainConfig,
    ServiceProfileQuestion? question,
  ) {
    final rearCount = drivetrainRearCogCountFromConfig(drivetrainConfig);
    if (rearCount == null) {
      return null;
    }
    return _firstMatchingWizardOption(question, [rearCount]);
  }

  String? _mappedDrivetrainFreehubTypeWizardAnswer(
    String? rawFreehubType,
    ServiceProfileQuestion? question,
  ) {
    final freehubType = canonicalDrivetrainFreehubTypeValue(rawFreehubType);
    if (freehubType == null) {
      return null;
    }
    return _firstMatchingWizardOption(question, [freehubType]);
  }

  String? _mappedChainWearWizardAnswerFromDiagnosis(
    ServiceProfileQuestion? question,
    DrivetrainDiagnosisSheet sheet,
  ) {
    final wearPercent = sheet.chainWearPercent;
    if (question == null || wearPercent == null) {
      return null;
    }

    final bucket = _drivetrainChainWearBucketFromMeasurement(wearPercent);
    return bucket == null
        ? null
        : _firstMatchingWizardOption(question, [bucket]);
  }

  String? _mappedCableConditionWizardAnswerFromDiagnosis(
    ServiceProfileQuestion? question,
    DrivetrainDiagnosisSheet sheet,
  ) {
    final rawValue = _normalizeNullableText(sheet.cableCondition ?? '');
    if (question == null || rawValue == null) {
      return null;
    }

    final canonicalValue = canonicalDrivetrainCableConditionValue(rawValue);
    if (canonicalValue == null) {
      return null;
    }

    return _firstMatchingWizardOption(question, [canonicalValue]);
  }

  String? _drivetrainChainWearBucketFromMeasurement(double? rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue >= 75) {
      return 'replace';
    }
    if (rawValue >= 50) {
      return 'worn';
    }
    return 'ok';
  }

  double? _chainWearPercentFromWizardAnswer(
    dynamic rawValue, {
    double? currentValue,
  }) {
    final normalizedValue = rawValue?.toString();
    if (currentValue != null &&
        _drivetrainChainWearBucketFromMeasurement(currentValue) ==
            normalizedValue) {
      return currentValue;
    }

    switch (normalizedValue) {
      case 'ok':
        return 10;
      case 'worn':
        return 60;
      case 'replace':
        return 85;
      default:
        return null;
    }
  }

  String? _normalizedDrivetrainCableCondition(dynamic rawValue) {
    return canonicalDrivetrainCableConditionValue(rawValue?.toString());
  }

  BikeSystemOverallStatus _drivetrainCableConditionStatus(String? rawValue) {
    switch (rawValue) {
      case 'ok':
        return BikeSystemOverallStatus.ok;
      case 'high_friction':
      case 'frayed':
      case 'corroded':
      case 'housing_damaged':
        return BikeSystemOverallStatus.attention;
      case 'replace':
        return BikeSystemOverallStatus.critical;
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  String? _buildDrivetrainProfileHint(Map<String, dynamic> technicalValues) {
    final config = _normalizeNullableText(
        technicalValues['drivetrainConfig']?.toString() ?? '');
    final speeds = _normalizeNullableText(
        technicalValues['drivetrainSpeeds']?.toString() ?? '');
    final freehubLabel = drivetrainFreehubTypeLabel(
      technicalValues['freehubType']?.toString(),
    );

    final parts = <String>[];
    if (config != null) {
      parts.add(config);
    }
    if (speeds != null) {
      parts.add('${speeds}v');
    }
    if (freehubLabel != null) {
      parts.add(freehubLabel);
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' · ');
  }

  List<BrakeDiagnosisSheet> _brakeDiagnosisSheetsForTargets(
    Set<BikeMemoryLocation> targets,
  ) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab || targets.isEmpty) {
      return const [];
    }

    final diagnosisSheet = currentTab.diagnosisSheet;
    final sheets = <BrakeDiagnosisSheet>[];
    for (final target in targets) {
      switch (target) {
        case BikeMemoryLocation.front:
          sheets.add(diagnosisSheet.frontBrake);
          break;
        case BikeMemoryLocation.rear:
          sheets.add(diagnosisSheet.rearBrake);
          break;
        case BikeMemoryLocation.none:
        case BikeMemoryLocation.left:
        case BikeMemoryLocation.right:
        case BikeMemoryLocation.center:
          break;
      }
    }
    return sheets;
  }

  String? _sharedBrakeStringAnswer(
    List<BrakeDiagnosisSheet> sheets,
    String? Function(BrakeDiagnosisSheet sheet) mapAnswer,
  ) {
    if (sheets.isEmpty) {
      return null;
    }

    String? sharedAnswer;
    for (final sheet in sheets) {
      final answer = mapAnswer(sheet);
      if (answer == null || answer.isEmpty) {
        return null;
      }
      if (sharedAnswer == null) {
        sharedAnswer = answer;
        continue;
      }
      if (sharedAnswer != answer) {
        return null;
      }
    }

    return sharedAnswer;
  }

  bool? _sharedBrakeBoolAnswer(
    List<BrakeDiagnosisSheet> sheets,
    bool? Function(BrakeDiagnosisSheet sheet) mapAnswer,
  ) {
    if (sheets.isEmpty) {
      return null;
    }

    bool? sharedAnswer;
    for (final sheet in sheets) {
      final answer = mapAnswer(sheet);
      if (answer == null) {
        return null;
      }
      if (sharedAnswer == null) {
        sharedAnswer = answer;
        continue;
      }
      if (sharedAnswer != answer) {
        return null;
      }
    }

    return sharedAnswer;
  }

  List<String>? _sharedBrakeListAnswer(
    List<BrakeDiagnosisSheet> sheets,
    List<String>? Function(BrakeDiagnosisSheet sheet) mapAnswer,
  ) {
    if (sheets.isEmpty) {
      return null;
    }

    List<String>? sharedAnswer;
    for (final sheet in sheets) {
      final answer = mapAnswer(sheet);
      if (answer == null || answer.isEmpty) {
        return null;
      }
      if (sharedAnswer == null) {
        sharedAnswer = answer;
        continue;
      }
      if (!listEquals(sharedAnswer, answer)) {
        return null;
      }
    }

    return sharedAnswer;
  }

  int _brakeContaminationRank(String? status) {
    switch (status) {
      case 'ok':
        return 0;
      case 'dirty':
        return 1;
      case 'contaminated':
        return 2;
      case 'replace':
        return 3;
      default:
        return -1;
    }
  }

  String? _mappedPadConditionWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    if (optionValues.contains('critical')) {
      if (sheet.padContaminationStatus == 'replace') {
        return 'critical';
      }
      final wear = sheet.padWearPercent;
      if (wear == null) {
        return null;
      }
      if (wear >= 75) {
        return 'critical';
      }
      if (wear >= 50) {
        return 'worn';
      }
      return 'ok';
    }

    if (optionValues.contains('contaminadas')) {
      final contamination = sheet.padContaminationStatus;
      if (contamination == 'dirty' ||
          contamination == 'contaminated' ||
          contamination == 'replace') {
        return 'contaminadas';
      }
      final wear = sheet.padWearPercent;
      if (wear == null) {
        return null;
      }
      if (wear >= 50) {
        return 'desgastadas';
      }
      return 'bien';
    }

    return null;
  }

  bool? _mappedPadContaminatedWizardAnswerFromDiagnosis(
    BrakeDiagnosisSheet sheet,
  ) {
    final contamination = sheet.padContaminationStatus;
    if (contamination == null || contamination.isEmpty) {
      return null;
    }

    return contamination != 'ok';
  }

  String? _mappedRotorConditionWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    final thickness = sheet.rotorThicknessMm;
    final trueness = sheet.rotorTruenessStatus;
    final contamination = sheet.rotorContaminationStatus;

    if (optionValues.contains('warped')) {
      if (thickness != null && thickness <= 1.5) {
        return 'replace';
      }
      if (trueness == 'replace' || contamination == 'replace') {
        return 'replace';
      }
      if (trueness == 'misaligned' || trueness == 'attention') {
        return 'warped';
      }
      if (contamination == 'dirty' || contamination == 'contaminated') {
        return 'glazed';
      }
      if (trueness == 'ok' || contamination == 'ok' || thickness != null) {
        return 'ok';
      }
      return null;
    }

    if (optionValues.contains('torcido')) {
      if (thickness != null && thickness <= 1.7) {
        return 'desgastado';
      }
      if (trueness == 'replace') {
        return 'desgastado';
      }
      if (trueness == 'misaligned' || trueness == 'attention') {
        return 'torcido';
      }
      if (contamination == 'replace' ||
          contamination == 'dirty' ||
          contamination == 'contaminated') {
        return 'contaminado';
      }
      if (trueness == 'ok' || contamination == 'ok' || thickness != null) {
        return 'bien';
      }
    }

    return null;
  }

  String? _mappedRotorSeverityWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    final thickness = sheet.rotorThicknessMm;
    final trueness = sheet.rotorTruenessStatus;

    String? normalizedSeverity;
    if (thickness != null && thickness <= 1.5 || trueness == 'replace') {
      normalizedSeverity = 'severe';
    } else if (trueness == 'misaligned' ||
        (thickness != null && thickness <= 1.7)) {
      normalizedSeverity = 'moderate';
    } else if (trueness == 'attention') {
      normalizedSeverity = 'minor';
    }

    if (normalizedSeverity == null) {
      return null;
    }

    switch (normalizedSeverity) {
      case 'minor':
        return optionValues.contains('minor')
            ? 'minor'
            : (optionValues.contains('leve') ? 'leve' : null);
      case 'moderate':
        return optionValues.contains('moderate')
            ? 'moderate'
            : (optionValues.contains('moderado') ? 'moderado' : null);
      case 'severe':
        return optionValues.contains('severe')
            ? 'severe'
            : (optionValues.contains('severo') ? 'severo' : null);
    }

    return null;
  }

  String? _mappedBrakeContaminationLevelWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    final contaminationStatuses = <String>[
      if (sheet.padContaminationStatus != null) sheet.padContaminationStatus!,
      if (sheet.rotorContaminationStatus != null)
        sheet.rotorContaminationStatus!,
    ];
    if (contaminationStatuses.isEmpty) {
      return null;
    }

    contaminationStatuses.sort(
      (left, right) => _brakeContaminationRank(right)
          .compareTo(_brakeContaminationRank(left)),
    );

    final normalized = switch (contaminationStatuses.first) {
      'ok' => 'none',
      'dirty' => 'light',
      'contaminated' => 'moderate',
      'replace' => 'severe',
      _ => null,
    };
    if (normalized == null || !optionValues.contains(normalized)) {
      return null;
    }

    return normalized;
  }

  List<String>? _mappedBrakeSymptomsWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final orderedValues = canonicalizeBrakeSymptomKeys(sheet.symptomKeys);
    return orderedValues.isEmpty ? null : orderedValues;
  }

  List<String>? _normalizeBrakeSymptomWizardAnswers(dynamic rawValue) {
    final values = (rawValue as List?)
        ?.map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (values == null || values.isEmpty) {
      return null;
    }

    final ordered = canonicalizeBrakeSymptomKeys(values);
    return ordered.isEmpty ? null : ordered;
  }

  dynamic _mappedBrakeDiagnosisWizardAnswer(
    ServiceProfileQuestion question,
    List<BrakeDiagnosisSheet> sheets,
  ) {
    switch (question.key) {
      case 'pad_condition':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedPadConditionWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'pad_contaminated':
        return _sharedBrakeBoolAnswer(
          sheets,
          _mappedPadContaminatedWizardAnswerFromDiagnosis,
        );
      case 'rotor_condition':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedRotorConditionWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'damage_level':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedRotorSeverityWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'contamination_level':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedBrakeContaminationLevelWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'symptom':
        return _sharedBrakeListAnswer(
          sheets,
          (sheet) =>
              _mappedBrakeSymptomsWizardAnswerFromDiagnosis(question, sheet),
        );
      default:
        return null;
    }
  }

  bool _areBrakeDiagnosisSheetsEquivalent(
    BrakeDiagnosisSheet left,
    BrakeDiagnosisSheet right,
  ) {
    return left.overallStatus == right.overallStatus &&
        left.padWearPercent == right.padWearPercent &&
        left.padContaminationStatus == right.padContaminationStatus &&
        left.rotorThicknessMm == right.rotorThicknessMm &&
        left.rotorTruenessStatus == right.rotorTruenessStatus &&
        left.rotorContaminationStatus == right.rotorContaminationStatus &&
        listEquals(left.symptomKeys, right.symptomKeys) &&
        left.notes == right.notes;
  }

  BikeSystemOverallStatus _derivedBrakeDiagnosisStatus(
    BrakeDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _brakeComponentStatus(sheet, 'brake_pad'),
      _brakeComponentStatus(sheet, 'rotor'),
      if (sheet.symptomKeys.isNotEmpty) BikeSystemOverallStatus.attention,
    ]);
  }

  BrakeDiagnosisSheet _applyBrakeWizardAnswersToSheet({
    required BrakeDiagnosisSheet sheet,
    required Map<String, dynamic> allAnswers,
    required Map<String, ServiceProfileQuestion> questionsByKey,
  }) {
    // Lo que este freno ya dice no se reescribe con su propia precarga.
    final answers = answersChangedFromPrefill(allAnswers, {
      for (final entry in questionsByKey.entries)
        entry.key: _mappedBrakeDiagnosisWizardAnswer(entry.value, [sheet]),
    });
    var nextSheet = sheet;

    final padCondition = answers['pad_condition']?.toString();
    if (padCondition != null && padCondition.isNotEmpty) {
      final optionValues = questionsByKey['pad_condition']
              ?.options
              .map((option) => option.value)
              .toSet() ??
          const <String>{};
      if (optionValues.contains('critical')) {
        switch (padCondition) {
          case 'ok':
            nextSheet = nextSheet.copyWith(padWearPercent: 25);
            break;
          case 'worn':
            nextSheet = nextSheet.copyWith(padWearPercent: 60);
            break;
          case 'critical':
            nextSheet = nextSheet.copyWith(padWearPercent: 90);
            break;
        }
      } else if (optionValues.contains('contaminadas')) {
        switch (padCondition) {
          case 'bien':
            nextSheet = nextSheet.copyWith(
              padContaminationStatus: 'ok',
              clearPadContaminationStatus: false,
            );
            break;
          case 'desgastadas':
            nextSheet = nextSheet.copyWith(padWearPercent: 60);
            break;
          case 'contaminadas':
            nextSheet = nextSheet.copyWith(
              padContaminationStatus: 'contaminated',
            );
            break;
        }
      }
    }

    // Inverso de la precarga, que lee lo peor de pastillas y rotor: «ninguna»
    // limpia los dos; un nivel no dice cuál de los dos, y va a las pastillas
    // (paso D).
    final padContamination = switch (answers['contamination_level']) {
      'none' => 'ok',
      'light' => 'dirty',
      'moderate' => 'contaminated',
      'severe' => 'replace',
      _ => null,
    };
    if (padContamination != null) {
      nextSheet = nextSheet.copyWith(
        padContaminationStatus: padContamination,
        rotorContaminationStatus: padContamination == 'ok' &&
                nextSheet.rotorContaminationStatus != null
            ? 'ok'
            : null,
      );
    }

    final rawPadContaminated = answers['pad_contaminated'];
    if (rawPadContaminated is bool) {
      nextSheet = nextSheet.copyWith(
        padContaminationStatus: rawPadContaminated ? 'contaminated' : 'ok',
      );
    }

    final rotorCondition = answers['rotor_condition']?.toString();
    if (rotorCondition != null && rotorCondition.isNotEmpty) {
      final optionValues = questionsByKey['rotor_condition']
              ?.options
              .map((option) => option.value)
              .toSet() ??
          const <String>{};
      if (optionValues.contains('warped')) {
        switch (rotorCondition) {
          case 'ok':
            nextSheet = nextSheet.copyWith(
              rotorTruenessStatus: 'ok',
              rotorContaminationStatus: 'ok',
            );
            break;
          case 'glazed':
            nextSheet = nextSheet.copyWith(
              rotorContaminationStatus: 'dirty',
            );
            break;
          case 'warped':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
            break;
          case 'replace':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'replace');
            break;
        }
      } else if (optionValues.contains('torcido')) {
        switch (rotorCondition) {
          case 'bien':
            nextSheet = nextSheet.copyWith(
              rotorTruenessStatus: 'ok',
              rotorContaminationStatus: 'ok',
            );
            break;
          case 'torcido':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
            break;
          case 'contaminado':
            nextSheet = nextSheet.copyWith(
              rotorContaminationStatus: 'contaminated',
            );
            break;
          case 'desgastado':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'replace');
            break;
        }
      }
    }

    final damageLevel = answers['damage_level']?.toString();
    switch (damageLevel) {
      case 'minor':
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'attention');
        break;
      case 'moderate':
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
        break;
      case 'severe':
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'replace');
        break;
    }

    final rawSymptoms = (answers['symptom'] as List?)
        ?.map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (rawSymptoms != null) {
      if (rawSymptoms.contains('desalineado')) {
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
      }

      final orderedSymptoms = canonicalizeBrakeSymptomKeys(rawSymptoms);
      nextSheet = nextSheet.copyWith(
        symptomKeys: orderedSymptoms,
        clearSymptomKeys: orderedSymptoms.isEmpty,
      );
    }

    return nextSheet;
  }

  _ServiceWizardDialogConfig _buildServiceWizardDialogConfig(
    ServiceWizardProfile? profile,
    JobPartItem item,
  ) {
    final currentTab = _currentBikeTab;
    final technicalValues = _bikeProfileForCurrentTab()?.technicalValues ??
        const <String, dynamic>{};
    final technicalConfirmed =
        _bikeProfileForCurrentTab()?.technicalConfirmed ??
            const <String, dynamic>{};
    final questionsByKey = {
      for (final question in profile?.questions ?? <ServiceProfileQuestion>[])
        question.key: question,
    };
    final initialAnswers = ServiceWizardService.normalizeAnswersForProfile(
      profile,
      Map<String, dynamic>.from(
          item.wizardAnswers ?? const <String, dynamic>{}),
    );
    final hiddenQuestionKeys = <String>{};
    final questionOverrides = <String, ServiceWizardQuestionOverride>{};
    final diagnosisLinkedQuestionKeys = <String>{};
    ServiceWizardContextSummary? contextSummary;
    final compatibleDiagnosisQuestionKeys = {
      for (final question in profile?.questions ?? <ServiceProfileQuestion>[])
        if (isDiagnosisSemanticQuestionCompatible(
          key: question.key,
          questionType: question.questionType,
          optionValues: question.options.map((option) => option.value),
        ))
          question.key,
    };

    final wheelAnswer =
        _wizardLocationAnswer(questionsByKey['which_wheel'], item.location);
    if (wheelAnswer != null) {
      initialAnswers['which_wheel'] = wheelAnswer;
    }

    String? helperText;
    if (_isBrakeServiceFamily(profile?.serviceFamily)) {
      diagnosisLinkedQuestionKeys.addAll(compatibleDiagnosisQuestionKeys);
      if (item.location != BikeMemoryLocation.none) {
        hiddenQuestionKeys.add('which_wheel');
      }

      final rawBrakeType = technicalValues['brakeType']?.toString();
      final rawRimBrakeFamily = technicalValues['rimBrakeFamily']?.toString();
      // El fluido es de cada freno (paso F.2): se precarga el de los frenos
      // que toca la línea, si dicen lo mismo. Lo confirmado manda y no se
      // pregunta; lo sugerido sólo llena lo que aún no se contestó.
      final fluidKeys = [
        for (final position
            in serviceWheelPositions(item.location, initialAnswers))
          position == BikeMemoryLocation.front
              ? 'frontBrakeFluidType'
              : 'rearBrakeFluidType',
      ];
      final fluidValues = {
        for (final key in fluidKeys)
          canonicalBrakeFluidTypeValue(technicalValues[key]?.toString()),
      };
      final knownBrakeFluid = fluidValues.length == 1 &&
              kBrakeFluidTypeOptions.containsKey(fluidValues.single)
          ? fluidValues.single
          : null;
      if (knownBrakeFluid != null &&
          (questionsByKey['fluid_type']?.options ?? const [])
              .any((option) => option.value == knownBrakeFluid)) {
        if (fluidKeys.every((key) => technicalConfirmed[key] == true)) {
          initialAnswers['fluid_type'] = knownBrakeFluid;
          hiddenQuestionKeys.add('fluid_type');
        } else {
          initialAnswers.putIfAbsent('fluid_type', () => knownBrakeFluid);
        }
      }
      final normalizedSymptomAnswers =
          _normalizeBrakeSymptomWizardAnswers(initialAnswers['symptom']);
      if (normalizedSymptomAnswers == null) {
        initialAnswers.remove('symptom');
      } else {
        initialAnswers['symptom'] = normalizedSymptomAnswers;
      }

      questionOverrides['symptom'] = ServiceWizardQuestionOverride(
        label: 'Síntomas observados',
        helperText:
            'Usa la misma lista del diagnóstico del freno para que ambos lados hablen el mismo idioma.',
        options: _kBrakeSymptomOptions,
      );

      final bikeLabel = currentTab?.displayName ?? 'Bicicleta';
      final bikeTypeLabel = currentTab?.bike?.bikeType?.displayName;
      final targetLabel = switch (item.location) {
        BikeMemoryLocation.front => 'Freno delantero',
        BikeMemoryLocation.rear => 'Freno trasero',
        _ => 'Servicio de freno',
      };
      final needsRimBrakeFamilyConfirmation =
          _needsRimBrakeFamilyConfirmation(rawBrakeType, rawRimBrakeFamily);
      contextSummary = ServiceWizardContextSummary(
        title: bikeLabel,
        subtitle: targetLabel,
        chips: [
          if (bikeTypeLabel != null && bikeTypeLabel.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.directions_bike_outlined,
              label: 'Tipo de bici: $bikeTypeLabel',
            ),
          if (rawBrakeType != null && rawBrakeType.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.tune_outlined,
              label: needsRimBrakeFamilyConfirmation
                  ? 'Freno confirmado: llanta · falta familia'
                  : 'Freno confirmado: ${_formatBrakeSystemDetail(rawBrakeType, rawRimBrakeFamily)}',
            ),
          if (knownBrakeFluid != null)
            ServiceWizardContextChip(
              icon: Icons.water_drop_outlined,
              label: 'Fluido: ${brakeFluidLabel(knownBrakeFluid)}',
            ),
        ],
      );

      if (needsRimBrakeFamilyConfirmation) {
        final rimFamilyOptions = (questionsByKey['brake_type']?.options ??
                const <ServiceQuestionOption>[])
            .where(
                (option) => kRimBrakeFamilyOptionValues.contains(option.value))
            .toList(growable: false);
        questionOverrides['brake_type'] = ServiceWizardQuestionOverride(
          label: 'Familia de freno de llanta',
          helperText:
              'La ficha de la bici ya dice freno de llanta: falta la familia exacta, y queda en la ficha al guardar el trabajo.',
          lockedSelection: const ServiceWizardLockedSelection(
            label: 'Tipo de freno (desde la bicicleta)',
            valueLabel: 'Llanta (rim)',
          ),
          options: rimFamilyOptions,
        );
      }

      final mappedBrakeType = _mappedBrakeTypeWizardAnswer(
        rawBrakeType,
        rawRimBrakeFamily,
        questionsByKey['brake_type'],
      );
      if (mappedBrakeType != null) {
        initialAnswers['brake_type'] = mappedBrakeType;
        // Se oculta sólo lo confirmado; lo sugerido queda a la vista.
        if (!needsRimBrakeFamilyConfirmation &&
            technicalConfirmed['brakeType'] == true &&
            (rawBrakeType != 'rim' ||
                technicalConfirmed['rimBrakeFamily'] == true)) {
          hiddenQuestionKeys.add('brake_type');
        }
      }

      final mappedMechanicalBrakeType = _mappedMechanicalBrakeTypeWizardAnswer(
        rawBrakeType,
        rawRimBrakeFamily,
        questionsByKey['brake_type_mech'],
      );
      if (mappedMechanicalBrakeType != null) {
        initialAnswers['brake_type_mech'] = mappedMechanicalBrakeType;
        hiddenQuestionKeys.add('brake_type_mech');
      }

      // El rotor deja de preguntarse sólo si la ficha confirma un freno que no
      // es de disco; si no lo sabe, decide la respuesta del tipo de freno en
      // el asistente. Un tamaño se oculta sólo confirmado para esa rueda: lo
      // sugerido queda a la vista (revisión C–F, 2026-09-27).
      final confirmedNotDisc = rawBrakeType != null &&
          rawBrakeType.isNotEmpty &&
          rawBrakeType != 'unknown' &&
          technicalConfirmed['brakeType'] == true &&
          !_isDiscBrakeType(rawBrakeType);
      if (confirmedNotDisc) {
        initialAnswers.remove('rotor_size');
        hiddenQuestionKeys.add('rotor_size');
      } else {
        final rotorSize = _mappedRotorSizeWizardAnswer(
          questionsByKey['rotor_size'],
          technicalValues,
          item.location,
        );
        if (rotorSize != null) {
          initialAnswers['rotor_size'] = rotorSize;
          final rotorKey = item.location == BikeMemoryLocation.front
              ? 'frontRotorSizeMm'
              : 'rearRotorSizeMm';
          if (technicalConfirmed[rotorKey] == true) {
            hiddenQuestionKeys.add('rotor_size');
          }
        }
      }

      final diagnosisTargets = _resolveBrakeDiagnosisTargets(
        item.location,
        initialAnswers,
      );
      final diagnosisSheets = _brakeDiagnosisSheetsForTargets(diagnosisTargets);
      if (diagnosisSheets.isNotEmpty) {
        for (final question
            in profile?.questions ?? <ServiceProfileQuestion>[]) {
          final diagnosisAnswer = _mappedBrakeDiagnosisWizardAnswer(
            question,
            diagnosisSheets,
          );
          if (diagnosisAnswer != null) {
            initialAnswers[question.key] = diagnosisAnswer;
          }
        }
      }

      // Es la bajada de la capa «Ficha»: la del diagnóstico ya dice que es
      // el mismo de su pestaña (G3), y aquí no se nombra al asistente.
      if (item.location == BikeMemoryLocation.front) {
        helperText = 'Lo que confirmes queda en la ficha del freno delantero.';
      } else if (item.location == BikeMemoryLocation.rear) {
        helperText = 'Lo que confirmes queda en la ficha del freno trasero.';
      } else {
        helperText = 'El tipo de freno es de la bici completa y el rotor, '
            'de cada rueda: elige arriba a qué rueda aplica.';
      }

      if (rawBrakeType != null && !_isDiscBrakeType(rawBrakeType)) {
        if (needsRimBrakeFamilyConfirmation) {
          helperText = '$helperText La ficha ya dice freno de llanta: falta '
              'la familia exacta, y el rotor no se pregunta.';
        } else {
          final brakeDetail = _formatBrakeSystemDetail(
            rawBrakeType,
            rawRimBrakeFamily,
          );
          helperText = '$helperText La ficha ya confirma freno $brakeDetail: '
              'no se repite el tipo ni se pregunta el rotor.';
        }
      } else if (rawBrakeType != null && rawBrakeType.isNotEmpty) {
        helperText =
            '$helperText La ficha ya dice freno ${_formatBrakeType(rawBrakeType)}.';
      }
      if (questionsByKey.containsKey('fluid_type') &&
          !hiddenQuestionKeys.contains('fluid_type')) {
        helperText = '$helperText El fluido queda en la ficha de cada freno '
            'que sangres.';
      }
    } else if (_isWheelServiceFamily(profile?.serviceFamily)) {
      if (item.location != BikeMemoryLocation.none) {
        hiddenQuestionKeys.add('which_wheel');
      }
      final positions = serviceWheelPositions(item.location, initialAnswers);
      final prefill = wheelServicePrefill(
        positions: positions,
        bikeWheelSize: currentTab?.bike?.wheelSize,
        values: technicalValues,
        confirmed: technicalConfirmed,
        optionsByKey: {
          for (final question
              in profile?.questions ?? <ServiceProfileQuestion>[])
            question.key:
                question.options.map((option) => option.value).toSet(),
        },
      );
      // Lo confirmado en la ficha manda; lo sugerido sólo llena lo que el
      // mecánico todavía no contestó.
      prefill.answers.forEach((key, value) {
        if (prefill.hiddenKeys.contains(key)) {
          initialAnswers[key] = value;
        } else {
          initialAnswers.putIfAbsent(key, () => value);
        }
      });
      hiddenQuestionKeys.addAll(prefill.hiddenKeys);
      diagnosisLinkedQuestionKeys.addAll(
        const {'tire_condition', 'rim_damage', 'symptom'}
            .where(questionsByKey.containsKey),
      );
      // Lo que el diagnóstico de esa rueda ya dice se precarga, a la vista.
      if (positions.length == 1 && currentTab != null) {
        final sheet = positions.single == BikeMemoryLocation.front
            ? currentTab.diagnosisSheet.frontWheel
            : currentTab.diagnosisSheet.rearWheel;
        final fromDiagnosis = <String, Object?>{
          for (final entry in wheelAnswersFromDiagnosis(
            tireCondition: sheet.tireCondition,
            rimCondition: sheet.rimCondition,
            hubBearingCondition: sheet.hubBearingCondition,
          ).entries)
            if ((questionsByKey[entry.key]?.options ?? const [])
                .any((option) => option.value == entry.value))
              entry.key: entry.value,
        };
        initialAnswers.addAll(
          answersWithDiagnosisPrefill(initialAnswers, fromDiagnosis),
        );
      }
      contextSummary = ServiceWizardContextSummary(
        title: currentTab?.displayName ?? 'Bicicleta',
        subtitle: positions.length == 2
            ? 'Ambas ruedas'
            : switch (positions.firstOrNull) {
                BikeMemoryLocation.front => 'Rueda delantera',
                BikeMemoryLocation.rear => 'Rueda trasera',
                _ => 'Servicio de rueda',
              },
        chips: [
          for (final fact in prefill.knownFacts)
            ServiceWizardContextChip(
              icon: Icons.tune_outlined,
              label: 'Ficha: $fact',
            ),
        ],
      );
      // La ayuda dice sólo lo que este servicio hace con la ficha.
      helperText = [
        'Lo confirmado en la ficha no se pregunta; lo que confirmes aquí sube '
            'a la ficha al guardar.',
        if (questionsByKey.containsKey('hole_count'))
          'Las perforaciones son de la rueda que armas: la ficha las toma al '
              'terminar el trabajo.',
        if (questionsByKey.containsKey('valve_type') ||
            questionsByKey.containsKey('brake_type'))
          'Válvula o freno vistos en una sola rueda quedan sugeridos, sin '
              'confirmar.',
      ].join(' ');
    } else if (profile?.serviceFamily == 'drivetrain') {
      diagnosisLinkedQuestionKeys.addAll(compatibleDiagnosisQuestionKeys);

      final drivetrainConfig = technicalValues['drivetrainConfig']?.toString();
      final drivetrainConfirmed =
          technicalConfirmed['drivetrainConfig'] == true &&
              technicalConfirmed['drivetrainSpeeds'] == true;
      final confirmedDrivetrainConfig =
          drivetrainConfirmed ? drivetrainConfig : null;
      final frontChainringAnswer =
          _mappedDrivetrainFrontChainringCountWizardAnswer(
        confirmedDrivetrainConfig,
        questionsByKey['front_chainring_count'],
      );
      if (frontChainringAnswer != null) {
        initialAnswers['front_chainring_count'] = frontChainringAnswer;
        hiddenQuestionKeys.add('front_chainring_count');
      }

      final rearCogAnswer = _mappedDrivetrainRearCogCountWizardAnswer(
        confirmedDrivetrainConfig,
        questionsByKey['rear_cog_count'],
      );
      if (rearCogAnswer != null) {
        initialAnswers['rear_cog_count'] = rearCogAnswer;
        hiddenQuestionKeys.add('rear_cog_count');
      }

      final freehubAnswer = _mappedDrivetrainFreehubTypeWizardAnswer(
        technicalConfirmed['freehubType'] == true
            ? technicalValues['freehubType']?.toString()
            : null,
        questionsByKey['freehub_type'],
      );
      if (freehubAnswer != null) {
        initialAnswers['freehub_type'] = freehubAnswer;
        if (isKnownDrivetrainFreehubType(
          technicalValues['freehubType']?.toString(),
        )) {
          hiddenQuestionKeys.add('freehub_type');
        }
      }

      final derailleurs = _mappedDerailleursWizardAnswer(
        confirmedDrivetrainConfig,
        questionsByKey['derailleurs'],
      );
      if (derailleurs != null) {
        initialAnswers['derailleurs'] = derailleurs;
      }

      final drivetrainSheet = currentTab?.diagnosisSheet.drivetrain;
      if (drivetrainSheet != null) {
        final chainWearAnswer = _mappedChainWearWizardAnswerFromDiagnosis(
          questionsByKey['chain_wear'],
          drivetrainSheet,
        );
        if (chainWearAnswer != null) {
          initialAnswers['chain_wear'] = chainWearAnswer;
        }

        final cableConditionAnswer =
            _mappedCableConditionWizardAnswerFromDiagnosis(
          questionsByKey['cable_condition'],
          drivetrainSheet,
        );
        if (cableConditionAnswer != null) {
          initialAnswers['cable_condition'] = cableConditionAnswer;
        }
      }

      final drivetrainHint = _buildDrivetrainProfileHint(technicalValues);
      helperText = drivetrainHint == null
          ? 'Lo que confirmes aquí queda en la ficha de transmisión de la bici.'
          : 'Lo que confirmes aquí queda en la ficha de transmisión de la '
              'bici, que ya dice $drivetrainHint.';
    } else if (_isBottomBracketServiceFamily(profile?.serviceFamily)) {
      final rawBottomBracketFamily =
          technicalValues['bottomBracketFamily']?.toString();
      final mappedBottomBracketFamily = _mappedBottomBracketFamilyWizardAnswer(
        rawBottomBracketFamily,
        questionsByKey['bottom_bracket_family'],
      );
      final hasKnownFamily = isKnownBottomBracketFamily(rawBottomBracketFamily);
      final familyConfirmed =
          hasKnownFamily && technicalConfirmed['bottomBracketFamily'] == true;
      final shellWidthValue = technicalValues['bbShellWidthMm'] ??
          technicalValues['bb_shell_width_mm'];
      final shellDiameterValue = technicalValues['bbShellDiameterMm'] ??
          technicalValues['bb_shell_diameter_mm'];
      final spindleInterfaceValue =
          technicalValues['spindleInterface']?.toString();
      final bikeLabel = currentTab?.displayName ?? 'Bicicleta';
      final bikeTypeLabel = currentTab?.bike?.bikeType?.displayName;
      final familyLabel = bottomBracketFamilyLabel(rawBottomBracketFamily);
      final shellWidthLabel = bottomBracketMeasurementLabel(shellWidthValue);
      final shellDiameterLabel =
          bottomBracketMeasurementLabel(shellDiameterValue);
      final spindleInterfaceLabel =
          bottomBracketSpindleInterfaceLabel(spindleInterfaceValue);

      contextSummary = ServiceWizardContextSummary(
        title: bikeLabel,
        subtitle: 'Pedalier / BB',
        chips: [
          if (bikeTypeLabel != null && bikeTypeLabel.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.directions_bike_outlined,
              label: 'Tipo de bici: $bikeTypeLabel',
            ),
          ServiceWizardContextChip(
            icon: Icons.settings_input_component_outlined,
            label: hasKnownFamily && familyLabel != null
                ? 'Pedalier confirmado: $familyLabel'
                : 'Pedalier / BB sin confirmar',
          ),
          if (shellWidthLabel != null &&
              technicalConfirmed['bbShellWidthMm'] == true)
            ServiceWizardContextChip(
              icon: Icons.straighten_outlined,
              label: 'Ancho caja: $shellWidthLabel',
            ),
          if (shellDiameterLabel != null &&
              technicalConfirmed['bbShellDiameterMm'] == true)
            ServiceWizardContextChip(
              icon: Icons.donut_large_outlined,
              label: 'Diámetro shell: $shellDiameterLabel',
            ),
          if (spindleInterfaceLabel != null &&
              technicalConfirmed['spindleInterface'] == true)
            ServiceWizardContextChip(
              icon: Icons.settings_ethernet_outlined,
              label: 'Interfaz eje: $spindleInterfaceLabel',
            ),
        ],
      );

      if (mappedBottomBracketFamily != null) {
        initialAnswers['bottom_bracket_family'] = mappedBottomBracketFamily;
        if (familyConfirmed) {
          hiddenQuestionKeys.add('bottom_bracket_family');
        }
      }

      final mappedShellWidth = _mappedBottomBracketMeasurementWizardAnswer(
        shellWidthValue,
        questionsByKey['bb_shell_width_mm'],
      );
      if (mappedShellWidth != null) {
        initialAnswers['bb_shell_width_mm'] = mappedShellWidth;
        if (technicalConfirmed['bbShellWidthMm'] == true) {
          hiddenQuestionKeys.add('bb_shell_width_mm');
        }
      }

      final mappedShellDiameter = _mappedBottomBracketMeasurementWizardAnswer(
        shellDiameterValue,
        questionsByKey['bb_shell_diameter_mm'],
      );
      if (mappedShellDiameter != null) {
        initialAnswers['bb_shell_diameter_mm'] = mappedShellDiameter;
        if (technicalConfirmed['bbShellDiameterMm'] == true) {
          hiddenQuestionKeys.add('bb_shell_diameter_mm');
        }
      }

      final mappedSpindleInterface =
          _mappedBottomBracketSpindleInterfaceWizardAnswer(
        spindleInterfaceValue,
        questionsByKey['spindle_interface'],
      );
      if (mappedSpindleInterface != null) {
        initialAnswers['spindle_interface'] = mappedSpindleInterface;
        if (technicalConfirmed['spindleInterface'] == true) {
          hiddenQuestionKeys.add('spindle_interface');
        }
      }

      helperText = hasKnownFamily && familyLabel != null
          ? 'La ficha ya confirma el pedalier $familyLabel: sólo se preguntan '
              'las medidas de la caja o el eje que falten.'
          : 'Lo que confirmes aquí (tipo de pedalier, ancho y diámetro de la '
              'caja, eje) sube a la ficha al guardar el trabajo.';
      _prefillBearingSymptom(
        questionsByKey['symptom'],
        initialAnswers,
        bearingCondition:
            currentTab?.diagnosisSheet.bottomBracket.bearingCondition,
        noiseStatus: currentTab?.diagnosisSheet.bottomBracket.noiseStatus,
      );
      if (questionsByKey.containsKey('symptom')) {
        diagnosisLinkedQuestionKeys.add('symptom');
      }
    } else if (profile?.serviceFamily == 'cockpit') {
      _prefillBearingSymptom(
        questionsByKey['symptom'],
        initialAnswers,
        bearingCondition:
            currentTab?.diagnosisSheet.cockpit.headsetBearingCondition,
        noiseStatus: currentTab?.diagnosisSheet.cockpit.headsetNoiseStatus,
      );
      if (questionsByKey.containsKey('symptom')) {
        diagnosisLinkedQuestionKeys.add('symptom');
      }
    }

    return _ServiceWizardDialogConfig(
      initialAnswers: initialAnswers,
      hiddenQuestionKeys: hiddenQuestionKeys,
      helperText: helperText,
      contextSummary: contextSummary,
      questionOverrides: questionOverrides,
      diagnosisLinkedQuestionKeys: diagnosisLinkedQuestionKeys,
    );
  }

  String? _serviceWizardSyncFeedback(
    ServiceWizardProfile? profile,
    JobPartItem item,
    Map<String, dynamic> answers,
  ) {
    if (_isBrakeServiceFamily(profile?.serviceFamily)) {
      final targets = _resolveBrakeDiagnosisTargets(item.location, answers);
      if (targets.isEmpty) {
        return 'Servicio guardado. Para ligarlo a la ficha técnica, define el lado como delantero o trasero.';
      }
      if (targets.length == 2) {
        return 'Servicio vinculado a la ficha técnica de freno delantero y trasero.';
      }
      if (targets.contains(BikeMemoryLocation.front)) {
        return 'Servicio vinculado a la ficha técnica del freno delantero.';
      }
      if (targets.contains(BikeMemoryLocation.rear)) {
        return 'Servicio vinculado a la ficha técnica del freno trasero.';
      }
    }

    if (profile?.serviceFamily == 'drivetrain') {
      return 'Servicio vinculado a la ficha técnica de transmisión.';
    }

    return null;
  }

  String? _bikeProfilePromotionFeedback(ServiceWizardProfile? profile) {
    if (_isBottomBracketServiceFamily(profile?.serviceFamily)) {
      return 'El tipo de pedalier, las medidas de la caja y el eje quedan en la ficha al guardar el trabajo.';
    }

    return null;
  }

  String? _buildPersistedWizardSummary(
    ServiceWizardProfile? profile,
    Map<String, dynamic> answers,
    String fallbackSummary, {
    Set<String> hiddenQuestionKeys = const <String>{},
  }) {
    final normalizedAnswers =
        ServiceWizardService.normalizeAnswersForProfile(profile, answers);
    if (normalizedAnswers.isEmpty) {
      return null;
    }

    if (profile == null) {
      return _normalizeNullableText(fallbackSummary);
    }

    final filteredAnswers = Map<String, dynamic>.from(normalizedAnswers)
      ..remove('which_wheel')
      ..removeWhere((key, _) => hiddenQuestionKeys.contains(key));
    final filteredQuestions = profile.questions
        .where(
          (question) =>
              question.key != 'which_wheel' &&
              !hiddenQuestionKeys.contains(question.key),
        )
        .toList();

    String summary = ServiceWizardService.buildSummary(
      filteredAnswers,
      filteredQuestions,
    );

    final extraNotes =
        _normalizeNullableText(answers['_notes']?.toString() ?? '');
    if (extraNotes != null) {
      summary = summary.isEmpty ? extraNotes : '$summary\n$extraNotes';
    }

    return _normalizeNullableText(summary);
  }

  BikeSystemOverallStatus _mergeDerivedDiagnosisStatus(
    BikeSystemOverallStatus current,
    BikeSystemOverallStatus derived,
  ) {
    if (derived == BikeSystemOverallStatus.unknown) {
      return current;
    }
    if (current == BikeSystemOverallStatus.unknown) {
      return derived;
    }
    return _diagnosisStatusRank(derived) > _diagnosisStatusRank(current)
        ? derived
        : current;
  }

  int _diagnosisStatusRank(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.unknown:
        return 0;
      case BikeSystemOverallStatus.ok:
        return 1;
      case BikeSystemOverallStatus.attention:
        return 2;
      case BikeSystemOverallStatus.critical:
        return 3;
    }
  }

  String? _upsertGuidedDiagnosisNote(
    String? existingNotes, {
    required String marker,
    required String? content,
  }) {
    final retainedLines = <String>[];
    for (final rawLine in (existingNotes ?? '').split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.startsWith(marker)) continue;
      retainedLines.add(line);
    }

    final normalizedContent = _normalizeNullableText(content ?? '');
    if (normalizedContent != null) {
      retainedLines.add('$marker $normalizedContent');
    }

    if (retainedLines.isEmpty) {
      return null;
    }

    return retainedLines.join('\n');
  }

  bool _hasGuidedDiagnosisNote(String? notes, String marker) {
    return (notes ?? '').split('\n').any((line) => line.startsWith(marker));
  }

  void _applyWizardAnswersToDiagnosis({
    required JobPartItem item,
    required ServiceWizardProfile? profile,
    required Map<String, dynamic> answers,
  }) {
    if (profile == null) {
      return;
    }

    switch (profile.serviceFamily) {
      case 'brake':
      case 'brakes':
        _applyBrakeWizardAnswersToDiagnosis(
          item: item,
          profile: profile,
          answers: answers,
        );
        return;
      case 'drivetrain':
        _applyDrivetrainWizardAnswersToDiagnosis(
          profile: profile,
          answers: answers,
        );
        return;
      case 'wheels':
      case 'wheel':
        _applyWheelWizardAnswersToDiagnosis(
          item: item,
          profile: profile,
          answers: answers,
        );
        return;
      case 'bottom_bracket':
      case 'cockpit':
        _applyBearingSymptomToDiagnosis(
          answers: answers,
          bottomBracket: profile.serviceFamily == 'bottom_bracket',
        );
        return;
      default:
        return;
    }
  }

  /// Lo que el diagnóstico de pedalier o dirección ya dice se precarga como
  /// síntoma, a la vista.
  void _prefillBearingSymptom(
    ServiceProfileQuestion? question,
    Map<String, dynamic> initialAnswers, {
    String? bearingCondition,
    String? noiseStatus,
  }) {
    final symptom = bearingSymptomFromDiagnosis(
      bearingCondition: bearingCondition,
      noiseStatus: noiseStatus,
    );
    if (symptom != null &&
        (question?.options.any((option) => option.value == symptom) ?? false)) {
      initialAnswers.addAll(
        answersWithDiagnosisPrefill(initialAnswers, {'symptom': symptom}),
      );
    }
  }

  /// El síntoma de pedalier o dirección va a su diagnóstico: rodamiento o
  /// ruido, y el estado que justifica (paso E). «Preventivo» no escribe nada.
  void _applyBearingSymptomToDiagnosis({
    required Map<String, dynamic> answers,
    required bool bottomBracket,
  }) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) return;
    final sheet = currentTab.diagnosisSheet;
    // Un crujido ya anotado se precarga como «ruido»: devolverlo igual no es
    // un hallazgo nuevo y no rebaja el diagnóstico a «requiere revisión».
    final prefill = bottomBracket
        ? bearingSymptomFromDiagnosis(
            bearingCondition: sheet.bottomBracket.bearingCondition,
            noiseStatus: sheet.bottomBracket.noiseStatus,
          )
        : bearingSymptomFromDiagnosis(
            bearingCondition: sheet.cockpit.headsetBearingCondition,
            noiseStatus: sheet.cockpit.headsetNoiseStatus,
          );
    final findings = bearingSymptomFindings(
      answersChangedFromPrefill(answers, {'symptom': prefill})['symptom'],
    );
    if (findings.isEmpty) return;
    final derived = BikeSystemOverallStatus.fromDbValue(findings.status);

    _updateCurrentDiagnosisSheet((current) {
      if (bottomBracket) {
        final next = current.bottomBracket.copyWith(
          bearingCondition: findings.bearingCondition,
          noiseStatus: findings.noiseStatus,
        );
        return current.copyWith(
          bottomBracket: next.copyWith(
            overallStatus: _mergeDerivedDiagnosisStatus(
              next.overallStatus,
              _maxSystemStatus(
                  [derived, _derivedBottomBracketDiagnosisStatus(next)]),
            ),
          ),
        );
      }
      final next = current.cockpit.copyWith(
        headsetBearingCondition: findings.bearingCondition,
        headsetNoiseStatus: findings.noiseStatus,
      );
      return current.copyWith(
        cockpit: next.copyWith(
          overallStatus: _mergeDerivedDiagnosisStatus(
            next.overallStatus,
            _maxSystemStatus([derived, _derivedCockpitDiagnosisStatus(next)]),
          ),
        ),
      );
    });
  }

  /// Lo que un servicio de rueda observó va al diagnóstico de esa rueda, o de
  /// las dos si la línea es de ambas. Sólo hallazgos (neumático, aro, maza y
  /// su estado): la configuración del servicio queda en la línea, no se copia
  /// al diagnóstico.
  void _applyWheelWizardAnswersToDiagnosis({
    required JobPartItem item,
    required ServiceWizardProfile profile,
    required Map<String, dynamic> answers,
  }) {
    final normalizedAnswers =
        ServiceWizardService.normalizeAnswersForProfile(profile, answers);
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) return;
    final targets = serviceWheelPositions(item.location, normalizedAnswers);
    if (targets.isEmpty) return;

    final findings = wheelDiagnosisFindings(normalizedAnswers);
    final marker = '[Servicio guiado: ${profile.name}]';
    // Un ruido de maza es un hallazgo sin campo propio: va a la nota.
    final noteContent =
        normalizedAnswers['symptom'] == 'noise' ? 'Maza con ruido' : null;
    final hasGuidedNote = targets.any((target) => _hasGuidedDiagnosisNote(
          (target == BikeMemoryLocation.front
                  ? currentTab.diagnosisSheet.frontWheel
                  : currentTab.diagnosisSheet.rearWheel)
              .notes,
          marker,
        ));
    if (findings.isEmpty && noteContent == null && !hasGuidedNote) return;

    WheelDiagnosisSheet apply(WheelDiagnosisSheet sheet) {
      // Lo que esta rueda ya dice no se reescribe con su propia precarga.
      final findings = wheelDiagnosisFindings(answersChangedFromPrefill(
        normalizedAnswers,
        wheelAnswersFromDiagnosis(
          tireCondition: sheet.tireCondition,
          rimCondition: sheet.rimCondition,
          hubBearingCondition: sheet.hubBearingCondition,
        ),
      ));
      final notes = _upsertGuidedDiagnosisNote(
        sheet.notes,
        marker: marker,
        content: noteContent,
      );
      final next = sheet.copyWith(
        tireCondition: findings.tireCondition,
        rimCondition: findings.rimCondition,
        hubBearingCondition: findings.hubBearingCondition,
        notes: notes,
        clearNotes: notes == null,
      );
      return next.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          next.overallStatus,
          _maxSystemStatus([
            BikeSystemOverallStatus.fromDbValue(findings.status),
            _derivedWheelDiagnosisStatus(next),
          ]),
        ),
      );
    }

    _updateCurrentDiagnosisSheet(
      (current) => current.copyWith(
        frontWheel: targets.contains(BikeMemoryLocation.front)
            ? apply(current.frontWheel)
            : null,
        rearWheel: targets.contains(BikeMemoryLocation.rear)
            ? apply(current.rearWheel)
            : null,
      ),
    );
  }

  void _applyBrakeWizardAnswersToDiagnosis({
    required JobPartItem item,
    required ServiceWizardProfile profile,
    required Map<String, dynamic> answers,
  }) {
    final normalizedAnswers =
        ServiceWizardService.normalizeAnswersForProfile(profile, answers);
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) {
      return;
    }

    final targets =
        _resolveBrakeDiagnosisTargets(item.location, normalizedAnswers);
    if (targets.isEmpty) {
      return;
    }

    final questionsByKey = {
      for (final question in profile.questions) question.key: question,
    };
    final noteParts = <String>[];
    var derivedStatus = BikeSystemOverallStatus.unknown;

    const diagnosisSyncedKeys = <String>{
      'pad_condition',
      'pad_contaminated',
      'rotor_condition',
      'damage_level',
      'symptom',
      'contamination_level',
    };

    void addSelectAnswer(
      String key,
      Map<String, BikeSystemOverallStatus> statusMap,
    ) {
      final rawValue = normalizedAnswers[key]?.toString();
      if (rawValue == null || rawValue.isEmpty) {
        return;
      }

      final question = questionsByKey[key];
      final resolvedLabel = question != null
          ? ServiceWizardService.resolveLabel(question, rawValue)
          : rawValue;
      noteParts.add('${question?.label ?? key}: $resolvedLabel');

      final candidateStatus =
          statusMap[rawValue] ?? BikeSystemOverallStatus.unknown;
      if (_diagnosisStatusRank(candidateStatus) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = candidateStatus;
      }
    }

    void addMultiSelectAnswer(
      String key,
      BikeSystemOverallStatus derivedFromAnySelection,
    ) {
      final rawValues = (normalizedAnswers[key] as List?)
          ?.map((value) => value.toString())
          .toList();
      if (rawValues == null || rawValues.isEmpty) {
        return;
      }

      final question = questionsByKey[key];
      final resolvedLabels = rawValues.map((rawValue) {
        return question != null
            ? ServiceWizardService.resolveLabel(question, rawValue)
            : rawValue;
      }).join(', ');
      noteParts.add('${question?.label ?? key}: $resolvedLabels');

      if (_diagnosisStatusRank(derivedFromAnySelection) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = derivedFromAnySelection;
      }
    }

    void addExecutionOnlyNotePart(ServiceProfileQuestion question) {
      if (diagnosisSyncedKeys.contains(question.key)) {
        return;
      }

      final rawValue = normalizedAnswers[question.key];
      if (rawValue == null) {
        return;
      }

      if (rawValue is bool) {
        noteParts.add('${question.label}: ${rawValue ? 'Sí' : 'No'}');
        return;
      }

      if (rawValue is List) {
        final values = rawValue
            .map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList(growable: false);
        if (values.isEmpty) {
          return;
        }
        final resolvedLabels = values
            .map((raw) => ServiceWizardService.resolveLabel(question, raw))
            .join(', ');
        noteParts.add('${question.label}: $resolvedLabels');
        return;
      }

      final normalized = _normalizeNullableText(rawValue.toString());
      if (normalized == null) {
        return;
      }

      noteParts.add(
        '${question.label}: ${ServiceWizardService.resolveLabel(question, normalized)}',
      );
    }

    addSelectAnswer('pad_condition', {
      'ok': BikeSystemOverallStatus.ok,
      'bien': BikeSystemOverallStatus.ok,
      'worn': BikeSystemOverallStatus.attention,
      'desgastadas': BikeSystemOverallStatus.attention,
      'contaminadas': BikeSystemOverallStatus.attention,
      'critical': BikeSystemOverallStatus.critical,
      'replace': BikeSystemOverallStatus.critical,
    });
    addSelectAnswer('rotor_condition', {
      'ok': BikeSystemOverallStatus.ok,
      'bien': BikeSystemOverallStatus.ok,
      'glazed': BikeSystemOverallStatus.attention,
      'contaminado': BikeSystemOverallStatus.attention,
      'desgastado': BikeSystemOverallStatus.critical,
      'torcido': BikeSystemOverallStatus.critical,
      'warped': BikeSystemOverallStatus.critical,
      'replace': BikeSystemOverallStatus.critical,
    });
    addSelectAnswer('contamination_level', {
      'none': BikeSystemOverallStatus.ok,
      'light': BikeSystemOverallStatus.attention,
      'moderate': BikeSystemOverallStatus.attention,
      'severe': BikeSystemOverallStatus.critical,
    });
    final padContaminated = answers['pad_contaminated'];
    if (padContaminated is bool) {
      final candidateStatus = padContaminated
          ? BikeSystemOverallStatus.attention
          : BikeSystemOverallStatus.ok;
      if (_diagnosisStatusRank(candidateStatus) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = candidateStatus;
      }
    }
    addSelectAnswer('damage_level', {
      'minor': BikeSystemOverallStatus.attention,
      'moderate': BikeSystemOverallStatus.attention,
      'severe': BikeSystemOverallStatus.critical,
    });
    addMultiSelectAnswer('symptom', BikeSystemOverallStatus.attention);

    for (final question in profile.questions) {
      addExecutionOnlyNotePart(question);
    }

    final freeNotes =
        _normalizeNullableText(normalizedAnswers['_notes']?.toString() ?? '');
    if (freeNotes != null) {
      noteParts.add('Observación: $freeNotes');
    }

    final marker = '[Servicio guiado: ${profile.name}]';
    final noteContent = noteParts.isEmpty ? null : noteParts.join(' · ');
    final updatedSheetsByTarget = <BikeMemoryLocation, BrakeDiagnosisSheet>{
      for (final target in targets)
        target: _applyBrakeWizardAnswersToSheet(
          sheet: target == BikeMemoryLocation.front
              ? currentTab.diagnosisSheet.frontBrake
              : currentTab.diagnosisSheet.rearBrake,
          allAnswers: normalizedAnswers,
          questionsByKey: questionsByKey,
        ),
    };
    final hasSemanticChanges = updatedSheetsByTarget.entries.any((entry) {
      final currentSheet = entry.key == BikeMemoryLocation.front
          ? currentTab.diagnosisSheet.frontBrake
          : currentTab.diagnosisSheet.rearBrake;
      return !_areBrakeDiagnosisSheetsEquivalent(currentSheet, entry.value);
    });

    if (derivedStatus == BikeSystemOverallStatus.unknown &&
        noteContent == null &&
        !hasSemanticChanges) {
      final hasExistingGuidedNote = targets.any((target) {
        final notes = target == BikeMemoryLocation.front
            ? currentTab.diagnosisSheet.frontBrake.notes
            : currentTab.diagnosisSheet.rearBrake.notes;
        return _hasGuidedDiagnosisNote(notes, marker);
      });
      if (!hasExistingGuidedNote) {
        return;
      }
    }

    BrakeDiagnosisSheet applyToSheet(
        BikeMemoryLocation target, BrakeDiagnosisSheet sheet) {
      final nextSheet = updatedSheetsByTarget[target] ?? sheet;
      final mergedNotes = _upsertGuidedDiagnosisNote(
        nextSheet.notes,
        marker: marker,
        content: noteContent,
      );
      return nextSheet.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          nextSheet.overallStatus,
          _maxSystemStatus([
            derivedStatus,
            _derivedBrakeDiagnosisStatus(nextSheet),
          ]),
        ),
        notes: mergedNotes,
        clearNotes: mergedNotes == null,
      );
    }

    _updateCurrentDiagnosisSheet(
      (current) => current.copyWith(
        frontBrake: targets.contains(BikeMemoryLocation.front)
            ? applyToSheet(BikeMemoryLocation.front, current.frontBrake)
            : current.frontBrake,
        rearBrake: targets.contains(BikeMemoryLocation.rear)
            ? applyToSheet(BikeMemoryLocation.rear, current.rearBrake)
            : current.rearBrake,
      ),
    );
  }

  Set<BikeMemoryLocation> _resolveBrakeDiagnosisTargets(
    BikeMemoryLocation location,
    Map<String, dynamic> answers,
  ) =>
      serviceWheelPositions(location, answers);

  void _applyDrivetrainWizardAnswersToDiagnosis({
    required ServiceWizardProfile profile,
    required Map<String, dynamic> answers,
  }) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) {
      return;
    }

    final normalizedAnswers =
        ServiceWizardService.normalizeAnswersForProfile(profile, answers);
    final currentDrivetrainSheet = currentTab.diagnosisSheet.drivetrain;
    final questionsByKey = {
      for (final question in profile.questions) question.key: question,
    };
    final noteParts = <String>[];
    var derivedStatus = BikeSystemOverallStatus.unknown;

    void addSelectAnswer(
      String key,
      Map<String, BikeSystemOverallStatus> statusMap,
    ) {
      final rawValue = normalizedAnswers[key]?.toString();
      if (rawValue == null || rawValue.isEmpty) {
        return;
      }

      final question = questionsByKey[key];
      final resolvedLabel = question != null
          ? ServiceWizardService.resolveLabel(question, rawValue)
          : rawValue;
      noteParts.add('${question?.label ?? key}: $resolvedLabel');

      final candidateStatus =
          statusMap[rawValue] ?? BikeSystemOverallStatus.unknown;
      if (_diagnosisStatusRank(candidateStatus) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = candidateStatus;
      }
    }

    final chainWearPercent = _chainWearPercentFromWizardAnswer(
      normalizedAnswers['chain_wear'],
      currentValue: currentDrivetrainSheet.chainWearPercent,
    );
    final cableCondition = _normalizedDrivetrainCableCondition(
        normalizedAnswers['cable_condition']);

    addSelectAnswer('chain_wear', {
      'ok': BikeSystemOverallStatus.ok,
      'worn': BikeSystemOverallStatus.attention,
      'replace': BikeSystemOverallStatus.critical,
    });
    addSelectAnswer('cable_condition', {
      'ok': BikeSystemOverallStatus.ok,
      'high_friction': BikeSystemOverallStatus.attention,
      'frayed': BikeSystemOverallStatus.attention,
      'corroded': BikeSystemOverallStatus.attention,
      'housing_damaged': BikeSystemOverallStatus.attention,
      'replace': BikeSystemOverallStatus.critical,
    });

    final freeNotes =
        _normalizeNullableText(normalizedAnswers['_notes']?.toString() ?? '');
    if (freeNotes != null) {
      noteParts.add('Observación: $freeNotes');
    }

    final marker = '[Servicio guiado: ${profile.name}]';
    final noteContent = noteParts.isEmpty ? null : noteParts.join(' · ');
    if (derivedStatus == BikeSystemOverallStatus.unknown &&
        chainWearPercent == null &&
        cableCondition == null &&
        noteContent == null &&
        !_hasGuidedDiagnosisNote(
            currentTab.diagnosisSheet.drivetrain.notes, marker)) {
      return;
    }

    _updateCurrentDiagnosisSheet(
      (current) {
        final mergedNotes = _upsertGuidedDiagnosisNote(
          current.drivetrain.notes,
          marker: marker,
          content: noteContent,
        );
        return current.copyWith(
          drivetrain: current.drivetrain.copyWith(
            overallStatus: _mergeDerivedDiagnosisStatus(
              current.drivetrain.overallStatus,
              derivedStatus,
            ),
            chainWearPercent: chainWearPercent,
            cableCondition: cableCondition,
            notes: mergedNotes,
            clearNotes: mergedNotes == null,
          ),
        );
      },
    );
  }

  void _insertDiagnosisSnippet(
      TextEditingController controller, String snippet) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid && selection.start >= 0
        ? selection.start
        : text.length;
    final end =
        selection.isValid && selection.end >= 0 ? selection.end : text.length;
    final selectedText = text.substring(start, end);
    final replacement =
        selectedText.isEmpty ? snippet : '$selectedText$snippet';
    final nextText = text.replaceRange(start, end, replacement);
    final cursor = start + replacement.length;

    controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );

    if (mounted) {
      setState(() {});
    }
  }

  bool _isGeneratingNarrativeDraftFor(_BikeTabData currentTab) =>
      _generatingNarrativeDraftTabId == currentTab.tabId;

  Future<void> _handleGenerateNarrativeDraft(_BikeTabData currentTab) async {
    final source = _buildDiagnosisNarrativeSource(currentTab);
    if (!source.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero completa hallazgos en el modelo estructurado para redactar un borrador.',
          ),
        ),
      );
      return;
    }

    final insertMode = await _resolveNarrativeDraftInsertMode(
      currentTab.diagnosisController.text,
    );
    if (insertMode == null || !mounted) {
      return;
    }

    setState(() {
      _generatingNarrativeDraftTabId = currentTab.tabId;
    });

    var usedFallback = false;

    try {
      final prompt = _buildDiagnosisNarrativePrompt(currentTab, source);
      String draft;

      try {
        _aiAssistantService.initialize();
        draft = _sanitizeGeneratedNarrativeDraft(
          await _aiAssistantService.generateOneShotText(prompt),
        );
        if (draft.trim().isEmpty) {
          throw StateError('Empty narrative draft');
        }
      } catch (_) {
        usedFallback = true;
        draft = _buildDiagnosisNarrativeFallback(currentTab, source);
      }

      if (!mounted) {
        return;
      }

      final controller = currentTab.diagnosisController;
      final nextText = _mergeNarrativeDraft(
        controller.text,
        draft,
        insertMode,
      );

      setState(() {
        controller.text = nextText;
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        _generatingNarrativeDraftTabId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usedFallback
                ? 'Se generó un borrador local desde el modelo estructurado.'
                : 'Borrador generado desde el modelo estructurado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _generatingNarrativeDraftTabId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el borrador: $e')),
      );
    }
  }

  Future<_NarrativeDraftInsertMode?> _resolveNarrativeDraftInsertMode(
    String existingText,
  ) async {
    if (existingText.trim().isEmpty) {
      return _NarrativeDraftInsertMode.replace;
    }

    return showDialog<_NarrativeDraftInsertMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('La ficha narrativa ya tiene texto'),
          content: const Text(
            '¿Quieres reemplazar el texto actual o agregar el nuevo borrador al final?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _NarrativeDraftInsertMode.append,
              ),
              child: const Text('Agregar abajo'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _NarrativeDraftInsertMode.replace,
              ),
              child: const Text('Reemplazar'),
            ),
          ],
        );
      },
    );
  }

  _DiagnosisNarrativeSource _buildDiagnosisNarrativeSource(
    _BikeTabData currentTab,
  ) {
    final sections = <_DiagnosisNarrativeSection>[];
    final recommendations = <String>{};
    var hasCriticalRisk = false;
    final sheet = currentTab.diagnosisSheet;

    final drivetrainNarrative =
        _buildDrivetrainNarrativeFromSheet(sheet.drivetrain);
    if (drivetrainNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Transmisión',
          body: drivetrainNarrative,
        ),
      );
      recommendations.addAll(
        _buildDrivetrainRecommendationHints(sheet.drivetrain),
      );
      hasCriticalRisk =
          hasCriticalRisk || _drivetrainHasCriticalRisk(sheet.drivetrain);
    }

    final frontBrakeNarrative =
        _buildBrakeNarrativeFromSheet('freno delantero', sheet.frontBrake);
    if (frontBrakeNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Freno delantero',
          body: frontBrakeNarrative,
        ),
      );
      recommendations.addAll(
        _buildBrakeRecommendationHints('freno delantero', sheet.frontBrake),
      );
      hasCriticalRisk =
          hasCriticalRisk || _brakeHasCriticalRisk(sheet.frontBrake);
    }

    final rearBrakeNarrative =
        _buildBrakeNarrativeFromSheet('freno trasero', sheet.rearBrake);
    if (rearBrakeNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Freno trasero',
          body: rearBrakeNarrative,
        ),
      );
      recommendations.addAll(
        _buildBrakeRecommendationHints('freno trasero', sheet.rearBrake),
      );
      hasCriticalRisk =
          hasCriticalRisk || _brakeHasCriticalRisk(sheet.rearBrake);
    }

    final frontWheelNarrative =
        _buildWheelNarrativeFromSheet('rueda delantera', sheet.frontWheel);
    if (frontWheelNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Rueda delantera',
          body: frontWheelNarrative,
        ),
      );
      recommendations.addAll(
        _buildWheelRecommendationHints('rueda delantera', sheet.frontWheel),
      );
      hasCriticalRisk =
          hasCriticalRisk || _wheelHasCriticalRisk(sheet.frontWheel);
    }

    final rearWheelNarrative =
        _buildWheelNarrativeFromSheet('rueda trasera', sheet.rearWheel);
    if (rearWheelNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Rueda trasera',
          body: rearWheelNarrative,
        ),
      );
      recommendations.addAll(
        _buildWheelRecommendationHints('rueda trasera', sheet.rearWheel),
      );
      hasCriticalRisk =
          hasCriticalRisk || _wheelHasCriticalRisk(sheet.rearWheel);
    }

    final bottomBracketNarrative =
        _buildBottomBracketNarrativeFromSheet(sheet.bottomBracket);
    if (bottomBracketNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Pedalier / BB',
          body: bottomBracketNarrative,
        ),
      );
      recommendations.addAll(
        _buildBottomBracketRecommendationHints(sheet.bottomBracket),
      );
      hasCriticalRisk =
          hasCriticalRisk || _bottomBracketHasCriticalRisk(sheet.bottomBracket);
    }

    final cockpitNarrative = _buildCockpitNarrativeFromSheet(sheet.cockpit);
    if (cockpitNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Cockpit / direccion',
          body: cockpitNarrative,
        ),
      );
      recommendations.addAll(
        _buildCockpitRecommendationHints(sheet.cockpit),
      );
      hasCriticalRisk =
          hasCriticalRisk || _cockpitHasCriticalRisk(sheet.cockpit);
    }

    final suspensionNarrative =
        _buildSuspensionNarrativeFromSheet(sheet.suspension);
    if (suspensionNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Suspension',
          body: suspensionNarrative,
        ),
      );
      recommendations.addAll(
        _buildSuspensionRecommendationHints(sheet.suspension),
      );
      hasCriticalRisk =
          hasCriticalRisk || _suspensionHasCriticalRisk(sheet.suspension);
    }

    return _DiagnosisNarrativeSource(
      sections: sections,
      recommendationHints: recommendations.toList(growable: false),
      hasCriticalRisk: hasCriticalRisk,
    );
  }

  String _buildDiagnosisNarrativePrompt(
    _BikeTabData currentTab,
    _DiagnosisNarrativeSource source,
  ) {
    final bikeName = currentTab.bike?.displayName ?? 'Bicicleta del cliente';
    final bikeType = currentTab.bike?.bikeType?.displayName;
    final clientRequest = _normalizeNullableText(
      currentTab.clientRequestController.text,
    );

    final buffer = StringBuffer()
      ..writeln(
        'Redacta un informe de diagnóstico de bicicleta en español claro, humano y profesional para compartir con el cliente.',
      )
      ..writeln('Reglas obligatorias:')
      ..writeln('- Usa solo la información entregada.')
      ..writeln(
          '- No inventes causas, piezas, medidas ni recomendaciones no respaldadas.')
      ..writeln(
        '- No menciones campos faltantes ni expresiones como "sin definir", "desconocido" o "no aplica".',
      )
      ..writeln('- No uses claves técnicas internas ni labels de formulario.')
      ..writeln(
          '- Organiza la respuesta con secciones breves usando markdown simple en formato "### Título".')
      ..writeln(
          '- Usa una sección por componente relevante, por ejemplo "### Freno delantero" o "### Transmisión".')
      ..writeln(
          '- No uses viñetas ni listas; debajo de cada título debe ir un párrafo corto.')
      ..writeln(
          '- Si corresponde, cierra con una sección como "### Recomendación" o "### Siguiente paso".')
      ..writeln('- Entrega como máximo 5 secciones cortas.')
      ..writeln(
          '- Usa un tono sobrio, cercano y profesional, como un taller serio hablando con su cliente.')
      ..writeln('- No seas melodramático, alarmista ni grandilocuente.')
      ..writeln('- No suenes robótico ni enumeres campos uno por uno.')
      ..writeln(
          '- Convierte porcentajes o mediciones técnicas en lenguaje natural cuando sea posible.')
      ..writeln(
          '- Ejemplo: en vez de "desgaste de pastillas de 55%", prefiere "las pastillas muestran desgaste avanzado".')
      ..writeln(
          '- Si hay criticidad o urgencia, exprésala de forma natural y proporcionada.')
      ..writeln()
      ..writeln('Contexto de la visita:')
      ..writeln('- Bicicleta: $bikeName');

    if (bikeType != null && bikeType.trim().isNotEmpty) {
      buffer.writeln('- Tipo: $bikeType');
    }
    if (clientRequest != null) {
      buffer.writeln('- Solicitud del cliente: $clientRequest');
    }
    if (source.hasCriticalRisk) {
      buffer.writeln('- Prioridad percibida: alta');
    }

    buffer
      ..writeln()
      ..writeln('Hallazgos estructurados ya depurados por sección:');

    for (final section in source.sections) {
      buffer.writeln('- ${section.title}: ${section.body}');
    }

    if (source.recommendationHints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
            'Recomendaciones sugeridas si corresponden con los hallazgos:');
      for (final recommendation in source.recommendationHints) {
        buffer.writeln('- $recommendation');
      }
    }

    return buffer.toString();
  }

  String _buildDiagnosisNarrativeFallback(
    _BikeTabData currentTab,
    _DiagnosisNarrativeSource source,
  ) {
    final clientRequest = _normalizeNullableText(
      currentTab.clientRequestController.text,
    );
    final sections = <String>[];

    if (clientRequest != null) {
      sections.add(
        _formatNarrativeMarkdownSection(
          'Motivo del ingreso',
          'La revisión se realizó teniendo en cuenta lo que comentó el cliente sobre $clientRequest.',
        ),
      );
    }

    for (final section in source.sections) {
      sections
          .add(_formatNarrativeMarkdownSection(section.title, section.body));
    }

    if (source.recommendationHints.isNotEmpty) {
      sections.add(
        _formatNarrativeMarkdownSection(
          source.hasCriticalRisk
              ? 'Siguiente paso prioritario'
              : 'Recomendación',
          'Con este diagnóstico, lo más razonable es ${_joinNaturalList(source.recommendationHints)}.',
        ),
      );
    }

    return sections.join('\n\n').trim();
  }

  String _formatNarrativeMarkdownSection(String title, String body) {
    return '### $title\n$body';
  }

  String _mergeNarrativeDraft(
    String existingText,
    String draft,
    _NarrativeDraftInsertMode mode,
  ) {
    final cleanedDraft = draft.trim();
    if (existingText.trim().isEmpty ||
        mode == _NarrativeDraftInsertMode.replace) {
      return cleanedDraft;
    }
    return '${existingText.trimRight()}\n\n$cleanedDraft';
  }

  String _sanitizeGeneratedNarrativeDraft(String rawText) {
    var cleaned = rawText.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'\s*```$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  String? _buildDrivetrainNarrativeFromSheet(DrivetrainDiagnosisSheet sheet) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add('La transmisión se encuentra en buen estado general.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('La transmisión presenta detalles que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
            'La transmisión muestra un desgaste o una condición que ya merece atención prioritaria.');
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    if (sheet.chainWearPercent != null) {
      final chainWear = _describeChainWearSentence(sheet.chainWearPercent);
      if (chainWear != null) {
        sentences.add(chainWear);
      }
    }

    final chainLube = _describeChainLubricationSentence(
      sheet.chainLubricationStatus,
    );
    if (chainLube != null) {
      sentences.add(chainLube);
    }

    final cableCondition =
        _describeDrivetrainCableConditionSentence(sheet.cableCondition);
    if (cableCondition != null) {
      sentences.add(cableCondition);
    }

    final cassette = _describeDrivetrainComponentSentence(
      'El cassette',
      sheet.cassetteCondition,
    );
    if (cassette != null) {
      sentences.add(cassette);
    }

    final chainring = _describeDrivetrainComponentSentence(
      'El plato',
      sheet.chainringCondition,
    );
    if (chainring != null) {
      sentences.add(chainring);
    }

    final rearDerailleur = _describeDrivetrainComponentSentence(
      'El cambio trasero',
      sheet.rearDerailleurCondition,
    );
    if (rearDerailleur != null) {
      sentences.add(rearDerailleur);
    }

    final frontDerailleur = _describeDrivetrainComponentSentence(
      'El cambio delantero',
      sheet.frontDerailleurCondition,
    );
    if (frontDerailleur != null) {
      sentences.add(frontDerailleur);
    }

    final shifter = _describeDrivetrainComponentSentence(
      'El shifter',
      sheet.shifterCondition,
    );
    if (shifter != null) {
      sentences.add(shifter);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  String? _buildBrakeNarrativeFromSheet(
    String brakeLabel,
    BrakeDiagnosisSheet sheet,
  ) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add('El $brakeLabel se encuentra en buen estado general.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('El $brakeLabel presenta detalles que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
            'El $brakeLabel muestra hallazgos importantes que requieren atención pronta.');
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    if (sheet.symptomKeys.isNotEmpty) {
      final symptomLabels = canonicalizeBrakeSymptomKeys(sheet.symptomKeys)
          .map((value) => kBrakeSymptomLabels[value] ?? value)
          .toList(growable: false);
      sentences.add(
        'Durante la prueba se observaron síntomas como ${_joinNaturalList(symptomLabels)}.',
      );
    }

    if (sheet.padWearPercent != null) {
      final padWear = _describeBrakePadWearSentence(
        brakeLabel,
        sheet.padWearPercent,
      );
      if (padWear != null) {
        sentences.add(padWear);
      }
    }

    final padContamination = _describeBrakePadContaminationSentence(
        brakeLabel, sheet.padContaminationStatus);
    if (padContamination != null) {
      sentences.add(padContamination);
    }

    if (sheet.rotorThicknessMm != null) {
      final rotorWear = _describeRotorThicknessSentence(
        brakeLabel,
        sheet.rotorThicknessMm,
      );
      if (rotorWear != null) {
        sentences.add(rotorWear);
      }
    }

    final rotorTrueness =
        _describeRotorTruenessSentence(brakeLabel, sheet.rotorTruenessStatus);
    if (rotorTrueness != null) {
      sentences.add(rotorTrueness);
    }

    final rotorContamination = _describeRotorContaminationSentence(
      brakeLabel,
      sheet.rotorContaminationStatus,
    );
    if (rotorContamination != null) {
      sentences.add(rotorContamination);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  String? _buildWheelNarrativeFromSheet(
    String wheelLabel,
    WheelDiagnosisSheet sheet,
  ) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add('La $wheelLabel se encuentra en buen estado general.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('La $wheelLabel presenta detalles que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
          'La $wheelLabel muestra hallazgos importantes que requieren atención pronta.',
        );
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    final tire = _describeWheelComponentSentence(
      'El neumático',
      sheet.tireCondition,
    );
    if (tire != null) {
      sentences.add(tire);
    }

    final rim = _describeWheelComponentSentence('El aro', sheet.rimCondition);
    if (rim != null) {
      sentences.add(rim);
    }

    final spokes =
        _describeWheelComponentSentence('Los rayos', sheet.spokeCondition);
    if (spokes != null) {
      sentences.add(spokes);
    }

    final hub = _describeWheelComponentSentence(
      'La maza',
      sheet.hubBearingCondition,
    );
    if (hub != null) {
      sentences.add(hub);
    }

    final tubeless = _describeTubelessStatusSentence(sheet.tubelessStatus);
    if (tubeless != null) {
      sentences.add(tubeless);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  String? _buildBottomBracketNarrativeFromSheet(
    BottomBracketDiagnosisSheet sheet,
  ) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add(
            'El pedalier se encuentra estable y sin hallazgos relevantes.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('El pedalier presenta señales que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
            'El pedalier muestra hallazgos que requieren atención pronta.');
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    final bearing = _describeMechanicalBearingSentence(
      'El pedalier',
      sheet.bearingCondition,
    );
    if (bearing != null) {
      sentences.add(bearing);
    }

    final noise = _describeMechanicalNoiseSentence(
      'El pedalier',
      sheet.noiseStatus,
    );
    if (noise != null) {
      sentences.add(noise);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  String? _buildCockpitNarrativeFromSheet(CockpitDiagnosisSheet sheet) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences
            .add('La dirección se encuentra estable y sin juego apreciable.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('La dirección presenta señales que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
            'La dirección muestra hallazgos que requieren atención pronta.');
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    final bearing = _describeMechanicalBearingSentence(
      'El headset',
      sheet.headsetBearingCondition,
    );
    if (bearing != null) {
      sentences.add(bearing);
    }

    final noise = _describeMechanicalNoiseSentence(
      'La dirección',
      sheet.headsetNoiseStatus,
    );
    if (noise != null) {
      sentences.add(noise);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  String? _buildSuspensionNarrativeFromSheet(SuspensionDiagnosisSheet sheet) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add('La suspensión se encuentra en buen estado general.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('La suspensión presenta detalles que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
          'La suspensión muestra hallazgos importantes que requieren atención pronta.',
        );
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    final fork = _describeSuspensionComponentSentence(
      'La horquilla',
      sheet.forkCondition,
    );
    if (fork != null) {
      sentences.add(fork);
    }

    final forkNoise = _describeMechanicalNoiseSentence(
      'La horquilla',
      sheet.forkNoiseStatus,
    );
    if (forkNoise != null) {
      sentences.add(forkNoise);
    }

    final rearShock = _describeSuspensionComponentSentence(
      'El amortiguador',
      sheet.rearShockCondition,
    );
    if (rearShock != null) {
      sentences.add(rearShock);
    }

    final rearShockNoise = _describeMechanicalNoiseSentence(
      'El amortiguador',
      sheet.rearShockNoiseStatus,
    );
    if (rearShockNoise != null) {
      sentences.add(rearShockNoise);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  List<String> _buildDrivetrainRecommendationHints(
    DrivetrainDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.chainWearPercent != null) {
      if (sheet.chainWearPercent! >= 75) {
        recommendations.add(
          'reemplazar la cadena y revisar el desgaste asociado en cassette y plato',
        );
      } else if (sheet.chainWearPercent! >= 50) {
        recommendations.add(
          'revisar el desgaste de la cadena y su compatibilidad con cassette y plato',
        );
      }
    }

    if (sheet.chainLubricationStatus == 'dry' ||
        sheet.chainLubricationStatus == 'dirty' ||
        sheet.chainLubricationStatus == 'contaminated') {
      recommendations
          .add('realizar limpieza y lubricación completa de la transmisión');
    }

    if (sheet.cassetteCondition == 'worn' ||
        sheet.cassetteCondition == 'replace') {
      recommendations.add('evaluar cambio de cassette');
    }
    if (sheet.chainringCondition == 'worn' ||
        sheet.chainringCondition == 'replace') {
      recommendations.add('evaluar cambio de plato');
    }
    if (sheet.rearDerailleurCondition == 'attention' ||
        sheet.rearDerailleurCondition == 'bent' ||
        sheet.rearDerailleurCondition == 'replace') {
      recommendations.add('ajustar o reemplazar el cambio trasero');
    }
    if (sheet.frontDerailleurCondition == 'attention' ||
        sheet.frontDerailleurCondition == 'bent' ||
        sheet.frontDerailleurCondition == 'replace') {
      recommendations.add('ajustar o reemplazar el cambio delantero');
    }
    if (sheet.shifterCondition == 'sticky' ||
        sheet.shifterCondition == 'attention' ||
        sheet.shifterCondition == 'replace') {
      recommendations.add('revisar o reemplazar el shifter');
    }
    if (sheet.cableCondition == 'high_friction' ||
        sheet.cableCondition == 'frayed' ||
        sheet.cableCondition == 'corroded' ||
        sheet.cableCondition == 'housing_damaged' ||
        sheet.cableCondition == 'replace') {
      recommendations.add(
          'reemplazar cables de cambios y revisar el estado de las fundas');
    }

    return recommendations.toList(growable: false);
  }

  List<String> _buildBrakeRecommendationHints(
    String brakeLabel,
    BrakeDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.padWearPercent != null) {
      if (sheet.padWearPercent! >= 75) {
        recommendations.add('reemplazar las pastillas del $brakeLabel');
      } else if (sheet.padWearPercent! >= 50) {
        recommendations.add('evaluar el cambio de pastillas del $brakeLabel');
      }
    }

    if (sheet.padContaminationStatus == 'contaminated') {
      recommendations
          .add('descontaminar o reemplazar las pastillas del $brakeLabel');
    }
    if (sheet.padContaminationStatus == 'replace') {
      recommendations.add('reemplazar las pastillas del $brakeLabel');
    }

    if (sheet.rotorThicknessMm != null) {
      if (sheet.rotorThicknessMm! <= 1.5) {
        recommendations.add('reemplazar el rotor del $brakeLabel');
      } else if (sheet.rotorThicknessMm! <= 1.7) {
        recommendations.add('revisar la vida útil del rotor del $brakeLabel');
      }
    }

    if (sheet.rotorTruenessStatus == 'misaligned') {
      recommendations.add('centrar el rotor del $brakeLabel');
    }
    if (sheet.rotorTruenessStatus == 'replace') {
      recommendations.add('reemplazar el rotor del $brakeLabel');
    }
    if (sheet.rotorContaminationStatus == 'contaminated') {
      recommendations.add('limpiar o descontaminar el rotor del $brakeLabel');
    }
    if (sheet.rotorContaminationStatus == 'replace') {
      recommendations.add('reemplazar el rotor del $brakeLabel');
    }

    if (sheet.symptomKeys.contains('spongy_lever')) {
      recommendations.add(
          'revisar el sistema del $brakeLabel para recuperar firmeza en la manilla');
    }
    if (sheet.symptomKeys.contains('low_power')) {
      recommendations.add(
          'recuperar la potencia de frenado del $brakeLabel mediante ajuste y revisión del conjunto');
    }

    return recommendations.toList(growable: false);
  }

  List<String> _buildWheelRecommendationHints(
    String wheelLabel,
    WheelDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.tireCondition == 'worn') {
      recommendations.add('evaluar cambio de neumático en la $wheelLabel');
    }
    if (sheet.tireCondition == 'damaged' || sheet.tireCondition == 'replace') {
      recommendations.add('reemplazar el neumático de la $wheelLabel');
    }

    if (sheet.rimCondition == 'attention' || sheet.rimCondition == 'bent') {
      recommendations.add('centrar y revisar el aro de la $wheelLabel');
    }
    if (sheet.rimCondition == 'cracked' || sheet.rimCondition == 'replace') {
      recommendations.add('reemplazar el aro de la $wheelLabel');
    }

    if (sheet.spokeCondition == 'loose' || sheet.spokeCondition == 'uneven') {
      recommendations.add('tensionar y centrar rayos de la $wheelLabel');
    }
    if (sheet.spokeCondition == 'broken') {
      recommendations.add('reemplazar rayos cortados de la $wheelLabel');
    }

    if (sheet.hubBearingCondition == 'rough' ||
        sheet.hubBearingCondition == 'play' ||
        sheet.hubBearingCondition == 'service') {
      recommendations.add('realizar servicio de maza en la $wheelLabel');
    }
    if (sheet.hubBearingCondition == 'replace') {
      recommendations.add('reemplazar rodamientos o maza de la $wheelLabel');
    }

    if (sheet.tubelessStatus == 'leaking' ||
        sheet.tubelessStatus == 'dry_sealant') {
      recommendations.add('revisar sellado tubeless de la $wheelLabel');
    }

    return recommendations.toList(growable: false);
  }

  List<String> _buildBottomBracketRecommendationHints(
    BottomBracketDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.bearingCondition == 'rough' ||
        sheet.bearingCondition == 'play' ||
        sheet.bearingCondition == 'service') {
      recommendations.add('realizar servicio de pedalier');
    }
    if (sheet.bearingCondition == 'replace') {
      recommendations.add('reemplazar rodamientos o conjunto de pedalier');
    }
    if (sheet.noiseStatus == 'creaking' ||
        sheet.noiseStatus == 'clicking' ||
        sheet.noiseStatus == 'knocking' ||
        sheet.noiseStatus == 'service') {
      recommendations.add('revisar torque, holguras y ajuste del pedalier');
    }

    return recommendations.toList(growable: false);
  }

  List<String> _buildCockpitRecommendationHints(CockpitDiagnosisSheet sheet) {
    final recommendations = <String>{};

    if (sheet.headsetBearingCondition == 'rough' ||
        sheet.headsetBearingCondition == 'play' ||
        sheet.headsetBearingCondition == 'service') {
      recommendations.add('realizar servicio de dirección / headset');
    }
    if (sheet.headsetBearingCondition == 'replace') {
      recommendations.add('reemplazar rodamientos o juego de dirección');
    }
    if (sheet.headsetNoiseStatus == 'creaking' ||
        sheet.headsetNoiseStatus == 'clicking' ||
        sheet.headsetNoiseStatus == 'knocking' ||
        sheet.headsetNoiseStatus == 'service') {
      recommendations.add('revisar juego, torque y ajuste de la dirección');
    }

    return recommendations.toList(growable: false);
  }

  List<String> _buildSuspensionRecommendationHints(
    SuspensionDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.forkCondition == 'rough' ||
        sheet.forkCondition == 'sticky' ||
        sheet.forkCondition == 'leaking' ||
        sheet.forkCondition == 'play' ||
        sheet.forkCondition == 'service') {
      recommendations.add('realizar servicio de horquilla');
    }
    if (sheet.forkCondition == 'replace') {
      recommendations.add('evaluar reemplazo de horquilla');
    }
    if (sheet.forkNoiseStatus == 'creaking' ||
        sheet.forkNoiseStatus == 'clicking' ||
        sheet.forkNoiseStatus == 'knocking' ||
        sheet.forkNoiseStatus == 'service') {
      recommendations.add('revisar juego y funcionamiento de la horquilla');
    }

    if (sheet.rearShockCondition == 'rough' ||
        sheet.rearShockCondition == 'sticky' ||
        sheet.rearShockCondition == 'leaking' ||
        sheet.rearShockCondition == 'play' ||
        sheet.rearShockCondition == 'service') {
      recommendations.add('realizar servicio de amortiguador');
    }
    if (sheet.rearShockCondition == 'replace') {
      recommendations.add('evaluar reemplazo de amortiguador');
    }
    if (sheet.rearShockNoiseStatus == 'creaking' ||
        sheet.rearShockNoiseStatus == 'clicking' ||
        sheet.rearShockNoiseStatus == 'knocking' ||
        sheet.rearShockNoiseStatus == 'service') {
      recommendations.add('revisar juego y funcionamiento del amortiguador');
    }

    return recommendations.toList(growable: false);
  }

  bool _drivetrainHasCriticalRisk(DrivetrainDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        (sheet.chainWearPercent != null && sheet.chainWearPercent! >= 75) ||
        sheet.cableCondition == 'replace' ||
        sheet.cassetteCondition == 'replace' ||
        sheet.chainringCondition == 'replace' ||
        sheet.rearDerailleurCondition == 'replace' ||
        sheet.frontDerailleurCondition == 'replace' ||
        sheet.shifterCondition == 'replace';
  }

  bool _brakeHasCriticalRisk(BrakeDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        (sheet.padWearPercent != null && sheet.padWearPercent! >= 75) ||
        (sheet.rotorThicknessMm != null && sheet.rotorThicknessMm! <= 1.5) ||
        sheet.rotorTruenessStatus == 'replace' ||
        sheet.padContaminationStatus == 'replace' ||
        sheet.rotorContaminationStatus == 'replace';
  }

  bool _wheelHasCriticalRisk(WheelDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        sheet.tireCondition == 'replace' ||
        sheet.tireCondition == 'damaged' ||
        sheet.rimCondition == 'cracked' ||
        sheet.rimCondition == 'replace' ||
        sheet.spokeCondition == 'broken' ||
        sheet.hubBearingCondition == 'replace';
  }

  bool _bottomBracketHasCriticalRisk(BottomBracketDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        sheet.bearingCondition == 'replace';
  }

  bool _cockpitHasCriticalRisk(CockpitDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        sheet.headsetBearingCondition == 'replace';
  }

  bool _suspensionHasCriticalRisk(SuspensionDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        sheet.forkCondition == 'replace' ||
        sheet.rearShockCondition == 'replace';
  }

  String? _describeChainLubricationSentence(String? status) {
    switch (status) {
      case 'ok':
        return 'La cadena se encuentra correctamente lubricada.';
      case 'dry':
        return 'La cadena se encuentra seca y requiere lubricación.';
      case 'dirty':
        return 'La cadena presenta suciedad excesiva.';
      case 'contaminated':
        return 'La cadena se encuentra contaminada.';
      default:
        return null;
    }
  }

  String? _describeChainWearSentence(double? wearPercent) {
    if (wearPercent == null) {
      return null;
    }
    if (wearPercent >= 75) {
      return 'La cadena muestra un desgaste muy avanzado y ya está en rango de recambio.';
    }
    if (wearPercent >= 50) {
      return 'La cadena muestra un desgaste avanzado.';
    }
    if (wearPercent >= 25) {
      return 'La cadena ya presenta desgaste visible.';
    }
    return null;
  }

  String? _describeDrivetrainCableConditionSentence(String? status) {
    switch (status) {
      case 'ok':
        return 'Los cables y fundas de cambios funcionan con un recorrido suave y sin resistencia anormal.';
      case 'high_friction':
        return 'Los cables de cambios presentan friccion alta o recorrido duro.';
      case 'frayed':
        return 'Los cables de cambios se encuentran deshilachados y conviene reemplazarlos.';
      case 'corroded':
        return 'Los cables de cambios presentan corrosion visible.';
      case 'housing_damaged':
        return 'Las fundas de cambios presentan danio o colapso.';
      case 'replace':
        return 'El sistema de cables y fundas presenta un danio severo y requiere recambio.';
      default:
        return null;
    }
  }

  String? _describeBrakePadWearSentence(
    String brakeLabel,
    double? wearPercent,
  ) {
    if (wearPercent == null) {
      return null;
    }
    if (wearPercent >= 75) {
      return 'Las pastillas del $brakeLabel están muy gastadas y cerca del fin de vida útil.';
    }
    if (wearPercent >= 50) {
      return 'Las pastillas del $brakeLabel muestran un desgaste avanzado.';
    }
    if (wearPercent >= 25) {
      return 'Las pastillas del $brakeLabel ya muestran desgaste y conviene seguirlas de cerca.';
    }
    return null;
  }

  String? _describeRotorThicknessSentence(
    String brakeLabel,
    double? thicknessMm,
  ) {
    if (thicknessMm == null) {
      return null;
    }
    if (thicknessMm <= 1.5) {
      return 'El rotor del $brakeLabel ya está por debajo del mínimo recomendado.';
    }
    if (thicknessMm <= 1.7) {
      return 'El rotor del $brakeLabel se encuentra cerca del límite de desgaste.';
    }
    return null;
  }

  String? _describeDrivetrainComponentSentence(String subject, String? status) {
    switch (status) {
      case 'ok':
        return '$subject se encuentra en buen estado.';
      case 'attention':
        return '$subject requiere atención.';
      case 'worn':
        return '$subject presenta desgaste.';
      case 'bent':
        return '$subject se encuentra desalineado o doblado.';
      case 'sticky':
        return '$subject presenta accionamiento duro o pegado.';
      case 'replace':
        return '$subject requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeBrakePadContaminationSentence(
    String brakeLabel,
    String? status,
  ) {
    switch (status) {
      case 'ok':
        return null;
      case 'dirty':
        return 'Las pastillas del $brakeLabel presentan suciedad.';
      case 'contaminated':
        return 'Las pastillas del $brakeLabel están contaminadas.';
      case 'replace':
        return 'Las pastillas del $brakeLabel requieren reemplazo.';
      default:
        return null;
    }
  }

  String? _describeRotorTruenessSentence(String brakeLabel, String? status) {
    switch (status) {
      case 'ok':
        return null;
      case 'attention':
        return 'El rotor del $brakeLabel presenta una leve desalineación.';
      case 'misaligned':
        return 'El rotor del $brakeLabel se encuentra desviado y presenta roce.';
      case 'replace':
        return 'El rotor del $brakeLabel requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeRotorContaminationSentence(
    String brakeLabel,
    String? status,
  ) {
    switch (status) {
      case 'ok':
        return null;
      case 'dirty':
        return 'El rotor del $brakeLabel presenta suciedad.';
      case 'contaminated':
        return 'El rotor del $brakeLabel está contaminado.';
      case 'replace':
        return 'El rotor del $brakeLabel requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeWheelComponentSentence(String subject, String? status) {
    switch (status) {
      case 'ok':
        return null;
      case 'attention':
        return '$subject requiere revision.';
      case 'worn':
        return '$subject presenta desgaste.';
      case 'damaged':
        return '$subject presenta daño visible.';
      case 'bent':
        return '$subject se encuentra golpeado o desviado.';
      case 'cracked':
        return '$subject presenta fisura.';
      case 'loose':
        return '$subject presentan soltura.';
      case 'uneven':
        return '$subject presentan tension dispareja.';
      case 'broken':
        return '$subject presentan cortes o roturas.';
      case 'rough':
        return '$subject gira aspera.';
      case 'play':
        return '$subject presenta juego.';
      case 'service':
        return '$subject requiere servicio.';
      case 'replace':
        return '$subject requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeTubelessStatusSentence(String? status) {
    switch (status) {
      case 'ok':
      case 'not_applicable':
        return null;
      case 'leaking':
        return 'El sistema tubeless pierde aire o no está sellando correctamente.';
      case 'dry_sealant':
        return 'El liquido tubeless se encuentra seco o insuficiente.';
      default:
        return null;
    }
  }

  String? _describeMechanicalBearingSentence(String subject, String? status) {
    switch (status) {
      case 'ok':
        return '$subject gira suave y sin asperezas.';
      case 'rough':
        return '$subject presenta roce o aspereza al girar.';
      case 'play':
        return '$subject presenta juego perceptible.';
      case 'service':
        return '$subject requiere servicio.';
      case 'replace':
        return '$subject requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeMechanicalNoiseSentence(String subject, String? status) {
    switch (status) {
      case 'ok':
        return null;
      case 'creaking':
        return '$subject presenta crujidos bajo carga.';
      case 'clicking':
        return '$subject presenta chasquidos o clics repetidos.';
      case 'knocking':
        return '$subject presenta golpeteos o juego marcado.';
      case 'service':
        return '$subject requiere revision por ruidos o funcionamiento irregular.';
      default:
        return null;
    }
  }

  String? _describeSuspensionComponentSentence(String subject, String? status) {
    switch (status) {
      case 'ok':
        return '$subject funciona correctamente.';
      case 'attention':
        return '$subject requiere revision.';
      case 'rough':
        return '$subject presenta funcionamiento aspero.';
      case 'sticky':
        return '$subject presenta recorrido pegado o poco fluido.';
      case 'leaking':
        return '$subject presenta fuga visible.';
      case 'play':
        return '$subject presenta juego.';
      case 'service':
        return '$subject requiere servicio.';
      case 'replace':
        return '$subject requiere reemplazo.';
      default:
        return null;
    }
  }

  String _joinNaturalList(Iterable<String> values) {
    final items = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (items.isEmpty) {
      return '';
    }
    if (items.length == 1) {
      return items.first;
    }
    if (items.length == 2) {
      return '${items.first} y ${items.last}';
    }
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }

  Color _diagnosisStatusColor(ThemeData theme, BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.ok:
        return Colors.green.shade700;
      case BikeSystemOverallStatus.attention:
        return Colors.orange.shade700;
      case BikeSystemOverallStatus.critical:
        return theme.colorScheme.error;
      case BikeSystemOverallStatus.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _formatDiagnosisSheetTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Sin sincronizar';
    return DateFormat('dd/MM HH:mm').format(timestamp.toLocal());
  }

  Widget _buildDiagnosisWorkspace(
    ThemeData theme,
    _BikeTabData currentTab,
    TextEditingController diagnosisCtrl,
  ) {
    final diagnosisSheet = _currentDiagnosisSheet;
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    final statuses = _kStructuredDiagnosisEditableSystems
        .map(
          (spec) => _structuredDiagnosisStatus(diagnosisSheet, spec.systemKey),
        )
        .toList(growable: false);
    final trackedSystems = _kStructuredDiagnosisEditableSystems
        .where(
          (spec) => _structuredDiagnosisHasMeaningfulData(
            diagnosisSheet,
            spec.systemKey,
          ),
        )
        .length;
    final criticalSystems = statuses
        .where((status) => status == BikeSystemOverallStatus.critical)
        .length;
    final reviewedSummary = trackedSystems == 0
        ? 'Aún no hay sistemas revisados.'
        : '$trackedSystems de ${_kStructuredDiagnosisEditableSystems.length} sistemas revisados.';
    final exceptionSummary = criticalSystems == 0
        ? 'Sin alertas críticas.'
        : '$criticalSystems ${criticalSystems == 1 ? 'alerta crítica' : 'alertas críticas'}.';

    final workspace = Column(
      key: const ValueKey('mechanic-job-diagnosis-workspace'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label:
              'Diagnóstico ${currentTab.bike?.displayName ?? ''}. $reviewedSummary $exceptionSummary',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diagnóstico ${currentTab.bike?.displayName ?? ''}'.trim(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$reviewedSummary $exceptionSummary',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: criticalSystems > 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        criticalSystems > 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (!isCompact) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Actualizado ${_formatDiagnosisSheetTimestamp(currentTab.diagnosisSheetUpdatedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: isCompact ? 12 : 16),
        _buildDiagnosisSubtabs(theme),
        SizedBox(height: isCompact ? 12 : 18),
        _selectedDiagnosisWorkbenchTab == _DiagnosisWorkbenchTab.narrative
            ? _buildNarrativeDiagnosisPanel(theme, currentTab, diagnosisCtrl)
            : _buildStructuredDiagnosisPanel(theme, currentTab),
      ],
    );

    if (isCompact) {
      return workspace;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: workspace,
    );
  }

  Widget _buildDiagnosisSection(ThemeData theme) {
    final currentTab = _currentBikeTab;
    final diagnosisCtrl =
        currentTab?.diagnosisController ?? _diagnosisController;

    // Warranty diagnosis is always gated by the original job before looking
    // at any tab. This prevents a stale Service tab from becoming the claim's
    // technical record while the source is missing or still loading.
    if (_jobType == JobType.warranty) {
      final source = _selectedWarrantySource;
      if (source == null) {
        return _buildWarrantyDiagnosisPrerequisite(theme);
      }
      if (_isLoadingWarrantySourceObject) {
        return _buildWarrantyDiagnosisPrerequisite(
          theme,
          title: 'Cargando objeto del trabajo original',
          message:
              'Espera a que se confirme la bicicleta o el componente antes de registrar el diagnóstico.',
          icon: Icons.sync,
        );
      }
      if (_warrantySourceObjectError != null ||
          !source.physicalObject.isValid) {
        return _buildWarrantyDiagnosisPrerequisite(
          theme,
          title: 'No se pudo confirmar el objeto recibido',
          message: _warrantySourceObjectError ??
              'Clasifica primero el trabajo original como bicicleta o componente.',
          icon: Icons.error_outline,
          isError: true,
        );
      }
      if (!_warrantySourceObjectMatchesForm(source)) {
        return _buildWarrantyDiagnosisPrerequisite(
          theme,
          title: 'Objeto del trabajo original no disponible',
          message:
              'Vuelve a General y reintenta la selección. No se habilitará un diagnóstico sobre otro objeto.',
          icon: Icons.error_outline,
          isError: true,
        );
      }
      if (source.physicalObject.isComponent) {
        return _buildNonBikeDiagnosisPanel(theme);
      }
    }

    if (currentTab == null) {
      if (_jobType == JobType.itemService || _jobType == JobType.quotation) {
        return _buildNonBikeDiagnosisPanel(theme);
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.pedal_bike_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Agrega una bicicleta para habilitar la pestaña de diagnóstico.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (currentTab.isGeneralTab) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'La pestaña General / Venta no tiene diagnóstico propio. El diagnóstico se registra por bicicleta.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildDiagnosisWorkspace(theme, currentTab, diagnosisCtrl);
  }

  Widget _buildWarrantyDiagnosisPrerequisite(
    ThemeData theme, {
    String title = 'Selecciona el trabajo original',
    String message =
        'La garantía puede corresponder a una bicicleta completa o a un componente suelto. Elige primero el trabajo original para cargar el diagnóstico correcto.',
    IconData icon = Icons.verified_user_outlined,
    bool isError = false,
  }) {
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNonBikeDiagnosisPanel(ThemeData theme) {
    final isQuotation = _jobType == JobType.quotation;
    final subjectNotes = _subjectNotesController.text.trim();
    final subjectLabel = _selectedSubject?.name ??
        (subjectNotes.isNotEmpty
            ? subjectNotes
            : (isQuotation ? 'cotización' : 'componente recibido'));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isQuotation
                    ? Icons.description_outlined
                    : Icons.build_circle_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isQuotation
                      ? 'Evaluación previa de la cotización'
                      : 'Diagnóstico de $subjectLabel',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isQuotation
                ? 'Registra antecedentes útiles para cotizar. Esto no afirma que una bicicleta o componente haya quedado recibido.'
                : 'Este diagnóstico pertenece al componente, por lo que no crea ni exige una bicicleta ficticia.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _diagnosisController,
            minLines: 5,
            maxLines: 10,
            decoration: InputDecoration(
              labelText: isQuotation
                  ? 'Evaluación / observaciones técnicas'
                  : 'Diagnóstico del componente',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              hintText: isQuotation
                  ? 'Compatibilidad, alternativas, mediciones o condiciones consideradas...'
                  : 'Hallazgos, mediciones, riesgos y condición de ingreso...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisSubtabs(ThemeData theme) {
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildDiagnosisSubtabButton(
              theme: theme,
              tab: _DiagnosisWorkbenchTab.structured,
              icon: Icons.auto_awesome_mosaic_rounded,
              label: isCompact ? 'Por sistema' : 'Modelo estructurado',
            ),
          ),
          Expanded(
            child: _buildDiagnosisSubtabButton(
              theme: theme,
              tab: _DiagnosisWorkbenchTab.narrative,
              icon: Icons.description_rounded,
              label: isCompact ? 'Notas' : 'Ficha narrativa',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisSubtabButton({
    required ThemeData theme,
    required _DiagnosisWorkbenchTab tab,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedDiagnosisWorkbenchTab == tab;
    final semanticsLabel = tab == _DiagnosisWorkbenchTab.structured
        ? 'Diagnóstico por sistema'
        : 'Notas de diagnóstico';

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Material(
          color: isSelected ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          elevation: isSelected ? 1 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          child: InkWell(
            onTap: () {
              if (_selectedDiagnosisWorkbenchTab == tab) return;
              setState(() {
                _selectedDiagnosisWorkbenchTab = tab;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNarrativeDiagnosisPanel(
    ThemeData theme,
    _BikeTabData currentTab,
    TextEditingController diagnosisCtrl,
  ) {
    final isGenerating = _isGeneratingNarrativeDraftFor(currentTab);
    final canGenerate = currentTab.diagnosisSheet.hasMeaningfulData;
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notas de diagnóstico',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Registra hallazgos, acciones y repuestos en una nota legible.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final generateAction = FilledButton.icon(
      onPressed: isGenerating || !canGenerate
          ? null
          : () => _handleGenerateNarrativeDraft(currentTab),
      icon: isGenerating
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : const Icon(Icons.auto_awesome_outlined, size: 16),
      label: Text(
        isGenerating ? 'Redactando...' : 'Redactar desde revisión',
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
      ),
    );

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompact) ...[
            heading,
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: generateAction),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                generateAction,
              ],
            ),
          const SizedBox(height: 10),
          Text(
            canGenerate
                ? 'Genera un borrador legible para el cliente usando solo los datos definidos del modelo estructurado. El borrador se organiza por componentes y se previsualiza con títulos en negrita.'
                : 'Completa primero el modelo estructurado para generar un borrador narrativo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.format_list_bulleted,
                  label: 'Bullet',
                  onTap: () => _insertDiagnosisSnippet(diagnosisCtrl, '• '),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.title_outlined,
                  label: 'Título',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\n### Título\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.search_outlined,
                  label: 'Hallazgo',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\nHallazgo:\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.construction_outlined,
                  label: 'Acción',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\nAcción recomendada:\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.inventory_2_outlined,
                  label: 'Repuesto',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\nRepuesto sugerido:\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.priority_high_outlined,
                  label: 'Urgente',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\n[URGENTE] ',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: ValueKey(
              'diagnosis_workspace_${_currentBikeTab?.tabId ?? "legacy"}',
            ),
            controller: diagnosisCtrl,
            decoration: const InputDecoration(
              labelText: 'Ficha de diagnóstico',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              hintText:
                  'Describe hallazgos, pruebas realizadas, riesgos y acciones recomendadas. Puedes usar títulos markdown como ### Freno delantero.',
            ),
            maxLines: 12,
            minLines: isCompact ? 6 : 10,
            onChanged: (_) => setState(() {}),
          ),
          if (diagnosisCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildNarrativePreviewCard(theme, diagnosisCtrl.text),
          ],
          const SizedBox(height: 10),
          Text(
            '${diagnosisCtrl.text.trim().isEmpty ? 0 : diagnosisCtrl.text.trim().split(RegExp(r'\s+')).length} palabras · Se guarda con esta bicicleta',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrativePreviewCard(ThemeData theme, String markdown) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa formateada',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          MarkdownBody(
            data: markdown,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              h3: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
              p: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisToolbarButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildStructuredDiagnosisPanel(
    ThemeData theme,
    _BikeTabData currentTab,
  ) {
    final diagnosisSheet = currentTab.diagnosisSheet;

    final activeSystemKey = _resolveStructuredDiagnosisSystemKey(currentTab);
    final activeSpec = bikeSystemControllerSpecFor(activeSystemKey) ??
        _kStructuredDiagnosisEditableSystems.first;
    final profile =
        _selectedBike?.id == currentTab.bike?.id ? _selectedBikeProfile : null;
    final bikeVariant = resolveBikeDiagramVariant(
      bike: currentTab.bike,
    );
    final brakeType = profile?.technicalValues['brakeType']?.toString();
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 980;
        final diagramPanel = _buildStructuredDiagnosisDiagramPanel(
          theme,
          currentTab: currentTab,
          activeSystemKey: activeSystemKey,
          bikeVariant: bikeVariant,
          brakeType: brakeType,
        );
        final inspectorPanel = _buildStructuredDiagnosisInspectorPanel(
          theme,
          currentTab: currentTab,
          diagnosisSheet: diagnosisSheet,
          activeSpec: activeSpec,
          profile: profile,
          brakeType: brakeType,
        );

        if (isCompact) {
          final choices = _kStructuredDiagnosisEditableSystems.map(
            (spec) {
              final status = _structuredDiagnosisStatus(
                diagnosisSheet,
                spec.systemKey,
              );
              return MechanicJobCompactChoice(
                id: spec.systemKey,
                label: spec.label,
                icon: spec.icon,
                statusLabel: status.displayName,
                statusColor: _diagnosisStatusColor(theme, status),
              );
            },
          ).toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MechanicJobCompactChoiceMenu(
                controlLabel: 'Sistema',
                selectedId: activeSystemKey,
                choices: choices,
                onSelected: (systemKey) {
                  setState(() {
                    _selectedStructuredDiagnosisSystemKey = systemKey;
                  });
                },
              ),
              const SizedBox(height: 12),
              inspectorPanel,
              const SizedBox(height: 12),
              _buildDiagnosisMapDisclosure(
                theme,
                diagramPanel: diagramPanel,
                compact: true,
              ),
            ],
          );
        }

        if (wideLayout) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: diagramPanel),
              const SizedBox(width: 32),
              Expanded(flex: 5, child: inspectorPanel),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            inspectorPanel,
            const SizedBox(height: 16),
            _buildDiagnosisMapDisclosure(
              theme,
              diagramPanel: diagramPanel,
              compact: false,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDiagnosisMapDisclosure(
    ThemeData theme, {
    required Widget diagramPanel,
    required bool compact,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('mechanic-job-diagnosis-map-disclosure'),
          minTileHeight: 52,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            0,
            compact ? 8 : 12,
            compact ? 8 : 12,
          ),
          leading: const Icon(Icons.pedal_bike_outlined, size: 20),
          title: const Text('Mapa de la bicicleta'),
          subtitle: const Text('Vista opcional para elegir un sistema'),
          children: [diagramPanel],
        ),
      ),
    );
  }

  String _resolveStructuredDiagnosisSystemKey(_BikeTabData currentTab) {
    final preferred = _selectedStructuredDiagnosisSystemKey;
    if (preferred != null && bikeSystemControllerSpecFor(preferred) != null) {
      return preferred;
    }

    String fallbackKey = _kStructuredDiagnosisEditableSystems.first.systemKey;
    var fallbackRank = -1;

    for (final spec in _kStructuredDiagnosisEditableSystems) {
      final status = _structuredDiagnosisStatus(
        currentTab.diagnosisSheet,
        spec.systemKey,
      );
      final hasData = _structuredDiagnosisHasMeaningfulData(
        currentTab.diagnosisSheet,
        spec.systemKey,
      );
      final rank = _structuredDiagnosisStatusRank(status) + (hasData ? 1 : 0);
      if (rank > fallbackRank) {
        fallbackKey = spec.systemKey;
        fallbackRank = rank;
      }
    }

    return fallbackKey;
  }

  int _structuredDiagnosisStatusRank(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.critical:
        return 3;
      case BikeSystemOverallStatus.attention:
        return 2;
      case BikeSystemOverallStatus.ok:
        return 1;
      case BikeSystemOverallStatus.unknown:
        return 0;
    }
  }

  BikeSystemOverallStatus _structuredDiagnosisStatus(
    MechanicJobDiagnosisSheet sheet,
    String systemKey,
  ) {
    switch (systemKey) {
      case 'cockpit':
        return sheet.cockpit.overallStatus;
      case 'suspension':
        return sheet.suspension.overallStatus;
      case 'front_wheel':
        return sheet.frontWheel.overallStatus;
      case 'bottom_bracket':
        return sheet.bottomBracket.overallStatus;
      case 'rear_wheel':
        return sheet.rearWheel.overallStatus;
      case 'wheels':
        return BikeSystemOverallStatus.unknown;
      case 'front_brake':
        return sheet.frontBrake.overallStatus;
      case 'rear_brake':
        return sheet.rearBrake.overallStatus;
      case 'drivetrain':
      default:
        return sheet.drivetrain.overallStatus;
    }
  }

  bool _structuredDiagnosisHasMeaningfulData(
    MechanicJobDiagnosisSheet sheet,
    String systemKey,
  ) {
    switch (systemKey) {
      case 'cockpit':
        return sheet.cockpit.hasMeaningfulData;
      case 'suspension':
        return sheet.suspension.hasMeaningfulData;
      case 'front_wheel':
        return sheet.frontWheel.hasMeaningfulData;
      case 'bottom_bracket':
        return sheet.bottomBracket.hasMeaningfulData;
      case 'rear_wheel':
        return sheet.rearWheel.hasMeaningfulData;
      case 'wheels':
        return false;
      case 'front_brake':
        return sheet.frontBrake.hasMeaningfulData;
      case 'rear_brake':
        return sheet.rearBrake.hasMeaningfulData;
      case 'drivetrain':
      default:
        return sheet.drivetrain.hasMeaningfulData;
    }
  }

  List<_StructuredDiagnosisComponentSpec> _structuredDiagnosisComponentSpecs(
    String systemKey,
    BikeProfile? profile,
  ) {
    var specs = _kStructuredDiagnosisComponentSpecs
        .where((spec) => spec.systemKey == systemKey)
        .toList();

    if (systemKey == 'front_brake' || systemKey == 'rear_brake') {
      final brakeType = profile?.technicalValues['brakeType']
          ?.toString()
          .trim()
          .toLowerCase();
      if (!_isDiscBrakeType(brakeType)) {
        specs = specs.where((spec) => spec.componentKey != 'rotor').toList();
      }
      return specs;
    }

    if (systemKey == 'suspension') {
      final layout = profile?.technicalValues['suspensionLayout']
          ?.toString()
          .trim()
          .toLowerCase();
      final hasFork = layout == null ||
          layout.isEmpty ||
          layout == 'front_suspension' ||
          layout == 'full_suspension';
      final hasRearShock = layout == 'full_suspension';

      specs = specs.where((spec) {
        switch (spec.componentKey) {
          case 'fork':
            return hasFork;
          case 'rear_shock':
            return hasRearShock;
          default:
            return true;
        }
      }).toList();

      return specs;
    }

    if (systemKey != 'drivetrain') {
      return specs;
    }

    final config = profile?.technicalValues['drivetrainConfig']
        ?.toString()
        .trim()
        .toLowerCase();
    final isSingleSpeed = config == 'singlespeed' ||
        config == 'single_speed' ||
        (config?.contains('fixie') ?? false) ||
        (config?.contains('single') ?? false);
    final usesFrontDerailleur = !isSingleSpeed &&
        !((config?.startsWith('1x') ?? false) || config == '1x');

    specs = specs.where((spec) {
      switch (spec.componentKey) {
        case 'front_derailleur':
          return usesFrontDerailleur;
        case 'rear_derailleur':
        case 'shifter':
          return !isSingleSpeed;
        default:
          return true;
      }
    }).toList();

    return specs;
  }

  String _diagnosisComponentSelectionScopeKey(String tabId, String systemKey) {
    return '$tabId::$systemKey';
  }

  String? _resolveStructuredDiagnosisComponentKey(
    String systemKey,
    BikeProfile? profile, {
    required String selectionScopeKey,
  }) {
    final specs = _structuredDiagnosisComponentSpecs(systemKey, profile);
    if (specs.isEmpty) {
      return null;
    }

    final preferred =
        _selectedStructuredDiagnosisComponentKeys[selectionScopeKey];
    if (preferred != null &&
        specs.any((spec) => spec.componentKey == preferred)) {
      return preferred;
    }

    return specs.first.componentKey;
  }

  BikeSystemOverallStatus _statusFromConditionValue(String? rawValue) {
    switch (rawValue) {
      case 'replace':
      case 'critical':
      case 'bent':
      case 'damaged':
      case 'contaminated':
      case 'broken':
      case 'cracked':
        return BikeSystemOverallStatus.critical;
      case 'attention':
      case 'worn':
      case 'dry':
      case 'dirty':
      case 'sticky':
      case 'high_friction':
      case 'corroded':
      case 'housing_damaged':
      case 'loose':
      case 'uneven':
      case 'rough':
      case 'play':
      case 'service':
      case 'leaking':
      case 'dry_sealant':
      case 'creaking':
      case 'clicking':
      case 'knocking':
        return BikeSystemOverallStatus.attention;
      case 'ok':
        return BikeSystemOverallStatus.ok;
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _drivetrainComponentStatus(
    DrivetrainDiagnosisSheet sheet,
    String componentKey,
  ) {
    switch (componentKey) {
      case 'chain':
        final wear = sheet.chainWearPercent;
        if (wear != null) {
          if (wear >= 75) return BikeSystemOverallStatus.critical;
          if (wear >= 50) return BikeSystemOverallStatus.attention;
          return BikeSystemOverallStatus.ok;
        }
        return _statusFromConditionValue(sheet.chainLubricationStatus);
      case 'cassette':
        return _statusFromConditionValue(sheet.cassetteCondition);
      case 'chainring':
        return _statusFromConditionValue(sheet.chainringCondition);
      case 'rear_derailleur':
        return _statusFromConditionValue(sheet.rearDerailleurCondition);
      case 'front_derailleur':
        return _statusFromConditionValue(sheet.frontDerailleurCondition);
      case 'shifter':
        return _maxSystemStatus([
          _statusFromConditionValue(sheet.shifterCondition),
          _drivetrainCableConditionStatus(sheet.cableCondition),
        ]);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _wheelComponentStatus(
    WheelDiagnosisSheet sheet,
    String componentKey,
  ) {
    switch (componentKey) {
      case 'tire':
        return _maxSystemStatus([
          _statusFromConditionValue(sheet.tireCondition),
          _statusFromConditionValue(sheet.tubelessStatus),
        ]);
      case 'rim':
        return _statusFromConditionValue(sheet.rimCondition);
      case 'spokes':
        return _statusFromConditionValue(sheet.spokeCondition);
      case 'hub':
        return _statusFromConditionValue(sheet.hubBearingCondition);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _suspensionComponentStatus(
    SuspensionDiagnosisSheet sheet,
    String componentKey,
  ) {
    switch (componentKey) {
      case 'fork':
        return _maxSystemStatus([
          _statusFromConditionValue(sheet.forkCondition),
          _statusFromConditionValue(sheet.forkNoiseStatus),
        ]);
      case 'rear_shock':
        return _maxSystemStatus([
          _statusFromConditionValue(sheet.rearShockCondition),
          _statusFromConditionValue(sheet.rearShockNoiseStatus),
        ]);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _maxSystemStatus(
    Iterable<BikeSystemOverallStatus> values,
  ) {
    if (values.any((value) => value == BikeSystemOverallStatus.critical)) {
      return BikeSystemOverallStatus.critical;
    }
    if (values.any((value) => value == BikeSystemOverallStatus.attention)) {
      return BikeSystemOverallStatus.attention;
    }
    if (values.any((value) => value == BikeSystemOverallStatus.ok)) {
      return BikeSystemOverallStatus.ok;
    }
    return BikeSystemOverallStatus.unknown;
  }

  BikeSystemOverallStatus _derivedDrivetrainDiagnosisStatus(
    DrivetrainDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _drivetrainComponentStatus(sheet, 'chain'),
      _drivetrainComponentStatus(sheet, 'cassette'),
      _drivetrainComponentStatus(sheet, 'chainring'),
      _drivetrainComponentStatus(sheet, 'rear_derailleur'),
      _drivetrainComponentStatus(sheet, 'front_derailleur'),
      _drivetrainComponentStatus(sheet, 'shifter'),
    ]);
  }

  BikeSystemOverallStatus _derivedWheelDiagnosisStatus(
    WheelDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _wheelComponentStatus(sheet, 'tire'),
      _wheelComponentStatus(sheet, 'rim'),
      _wheelComponentStatus(sheet, 'spokes'),
      _wheelComponentStatus(sheet, 'hub'),
    ]);
  }

  BikeSystemOverallStatus _derivedBottomBracketDiagnosisStatus(
    BottomBracketDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _statusFromConditionValue(sheet.bearingCondition),
      _statusFromConditionValue(sheet.noiseStatus),
    ]);
  }

  BikeSystemOverallStatus _derivedCockpitDiagnosisStatus(
    CockpitDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _statusFromConditionValue(sheet.headsetBearingCondition),
      _statusFromConditionValue(sheet.headsetNoiseStatus),
    ]);
  }

  BikeSystemOverallStatus _derivedSuspensionDiagnosisStatus(
    SuspensionDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _suspensionComponentStatus(sheet, 'fork'),
      _suspensionComponentStatus(sheet, 'rear_shock'),
    ]);
  }

  MechanicJobDiagnosisSheet _normalizeDiagnosisSheetStatuses(
    MechanicJobDiagnosisSheet sheet,
  ) {
    return sheet.copyWith(
      suspension: sheet.suspension.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.suspension.overallStatus,
          _derivedSuspensionDiagnosisStatus(sheet.suspension),
        ),
      ),
      drivetrain: sheet.drivetrain.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.drivetrain.overallStatus,
          _derivedDrivetrainDiagnosisStatus(sheet.drivetrain),
        ),
      ),
      frontBrake: sheet.frontBrake.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.frontBrake.overallStatus,
          _derivedBrakeDiagnosisStatus(sheet.frontBrake),
        ),
      ),
      rearBrake: sheet.rearBrake.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.rearBrake.overallStatus,
          _derivedBrakeDiagnosisStatus(sheet.rearBrake),
        ),
      ),
      frontWheel: sheet.frontWheel.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.frontWheel.overallStatus,
          _derivedWheelDiagnosisStatus(sheet.frontWheel),
        ),
      ),
      rearWheel: sheet.rearWheel.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.rearWheel.overallStatus,
          _derivedWheelDiagnosisStatus(sheet.rearWheel),
        ),
      ),
      bottomBracket: sheet.bottomBracket.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.bottomBracket.overallStatus,
          _derivedBottomBracketDiagnosisStatus(sheet.bottomBracket),
        ),
      ),
      cockpit: sheet.cockpit.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          sheet.cockpit.overallStatus,
          _derivedCockpitDiagnosisStatus(sheet.cockpit),
        ),
      ),
    );
  }

  double _chainWearGaugeValue(double? rawValue) {
    if (rawValue == null) {
      return 0.0;
    }

    final normalized = rawValue > 1 ? rawValue / 100 : rawValue;
    return normalized.clamp(0.0, 1.0);
  }

  double _chainWearPercentFromGauge(double gaugeValue) {
    return (gaugeValue * 100).clamp(0.0, 100.0);
  }

  String _formatChainWearGauge(double? rawValue) {
    if (rawValue == null) {
      return 'Sin medición';
    }
    return _chainWearGaugeValue(rawValue).toStringAsFixed(2);
  }

  Widget _buildStructuredDiagnosisDiagramPanel(
    ThemeData theme, {
    required _BikeTabData currentTab,
    required String activeSystemKey,
    required BikeDiagramVariant bikeVariant,
    required String? brakeType,
  }) {
    final rimBrakeFamily = _selectedBike?.id == currentTab.bike?.id
        ? _selectedBikeProfile?.technicalValues['rimBrakeFamily']?.toString()
        : null;
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista técnica de la bicicleta',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Selecciona un sistema sobre la bicicleta para abrir su revisión.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1,
            child: BikeSystemController(
              bike: currentTab.bike,
              profile: _selectedBike?.id == currentTab.bike?.id
                  ? _selectedBikeProfile
                  : null,
              variant: bikeVariant,
              entries: kBikeSystemControllerSpecs
                  .map(
                    (spec) => BikeSystemControllerEntry(
                      spec: spec,
                      status: _structuredDiagnosisStatus(
                        currentTab.diagnosisSheet,
                        spec.systemKey,
                      ),
                    ),
                  )
                  .toList(growable: false),
              selectedSystemKey: activeSystemKey,
              onSystemSelected: (systemKey) {
                setState(() {
                  _selectedStructuredDiagnosisSystemKey = systemKey;
                });
              },
              onClearSelection: () {
                setState(() {
                  _selectedStructuredDiagnosisSystemKey = null;
                });
              },
              idleHintText: 'Selecciona un sistema para cambiar la vista.',
              selectedHintText:
                  'Selecciona otro componente para cambiar la vista.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStructuredDiagnosisMetaChip(
                theme,
                icon: Icons.category_outlined,
                label: bikeVariant.displayName,
              ),
              if (brakeType != null && brakeType.isNotEmpty)
                _buildStructuredDiagnosisMetaChip(
                  theme,
                  icon: Icons.disc_full,
                  label:
                      'Freno ${_formatBrakeSystemDetail(brakeType, rimBrakeFamily)}',
                ),
              if (currentTab.bike?.wheelSize?.isNotEmpty == true)
                _buildStructuredDiagnosisMetaChip(
                  theme,
                  icon: Icons.circle_outlined,
                  label: 'Aro ${currentTab.bike!.wheelSize!}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredDiagnosisMetaChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBrakeType(String rawValue) {
    switch (rawValue) {
      case 'rim':
        return 'llanta';
      case 'mechanical_disc':
        return 'disco mecánico';
      case 'hydraulic_disc':
        return 'disco hidráulico';
      case 'roller_brake':
        return 'roller brake';
      case 'drum_brake':
        return 'tambor';
      case 'coaster_brake':
        return 'contrapedal';
      case 'band_brake':
        return 'banda';
      default:
        return rawValue;
    }
  }

  bool _isDiscBrakeType(String? rawValue) {
    return rawValue == 'mechanical_disc' || rawValue == 'hydraulic_disc';
  }

  String? _formatRimBrakeFamily(String? rawValue) {
    switch (rawValue) {
      case 'v_brake':
        return 'V-Brake';
      case 'cantilever':
        return 'Cantilever';
      case 'road_caliper_short_reach':
        return 'caliper ruta corto';
      case 'road_caliper_long_reach':
        return 'caliper ruta largo';
      case 'u_brake':
        return 'U-Brake';
      case 'rod_brake':
        return 'freno de varilla';
      case 'other':
        return 'otro sistema de llanta';
      case 'unknown':
        return 'familia de llanta no confirmada';
      default:
        return rawValue;
    }
  }

  String _formatBrakeSystemDetail(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
  ) {
    if (rawBrakeType == null || rawBrakeType.isEmpty) {
      return 'desconocido';
    }

    if (rawBrakeType == 'rim') {
      final rimBrakeFamily = _formatRimBrakeFamily(rawRimBrakeFamily);
      if (rimBrakeFamily != null && rimBrakeFamily.isNotEmpty) {
        return 'de llanta ($rimBrakeFamily)';
      }
    }

    return _formatBrakeType(rawBrakeType);
  }

  Widget _buildStructuredDiagnosisInspectorPanel(
    ThemeData theme, {
    required _BikeTabData currentTab,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required BikeSystemControllerSpec activeSpec,
    required BikeProfile? profile,
    required String? brakeType,
  }) {
    final rimBrakeFamily =
        profile?.technicalValues['rimBrakeFamily']?.toString();
    switch (activeSpec.systemKey) {
      case 'wheels':
        return _buildUnavailableStructuredDiagnosisSystemCard(
          theme,
          activeSpec: activeSpec,
          profile: profile,
          bike: currentTab.bike,
          templateKey: diagnosisSheet.templateKey,
        );
      case 'suspension':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.suspension.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.suspension.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              suspension: current.suspension.copyWith(overallStatus: status),
            ),
          ),
          child: _buildSuspensionDiagnosisFields(
            currentTab,
            suspensionSheet: diagnosisSheet.suspension,
            profile: profile,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(suspension: transform(current.suspension)),
              refresh: refresh,
            ),
          ),
        );
      case 'cockpit':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.cockpit.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.cockpit.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              cockpit: current.cockpit.copyWith(overallStatus: status),
            ),
          ),
          child: _buildCockpitDiagnosisFields(
            currentTab,
            cockpitSheet: diagnosisSheet.cockpit,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(cockpit: transform(current.cockpit)),
              refresh: refresh,
            ),
          ),
        );
      case 'front_wheel':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.frontWheel.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.frontWheel.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              frontWheel: current.frontWheel.copyWith(overallStatus: status),
            ),
          ),
          child: _buildWheelDiagnosisFields(
            currentTab,
            systemKey: 'front_wheel',
            wheelSheet: diagnosisSheet.frontWheel,
            profile: profile,
            bike: currentTab.bike,
            title: 'delantera',
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(frontWheel: transform(current.frontWheel)),
              refresh: refresh,
            ),
          ),
        );
      case 'bottom_bracket':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.bottomBracket.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.bottomBracket.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              bottomBracket:
                  current.bottomBracket.copyWith(overallStatus: status),
            ),
          ),
          child: _buildBottomBracketDiagnosisFields(
            currentTab,
            bottomBracketSheet: diagnosisSheet.bottomBracket,
            profile: profile,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                bottomBracket: transform(current.bottomBracket),
              ),
              refresh: refresh,
            ),
          ),
        );
      case 'rear_wheel':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.rearWheel.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.rearWheel.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              rearWheel: current.rearWheel.copyWith(overallStatus: status),
            ),
          ),
          child: _buildWheelDiagnosisFields(
            currentTab,
            systemKey: 'rear_wheel',
            wheelSheet: diagnosisSheet.rearWheel,
            profile: profile,
            bike: currentTab.bike,
            title: 'trasera',
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(rearWheel: transform(current.rearWheel)),
              refresh: refresh,
            ),
          ),
        );
      case 'front_brake':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.frontBrake.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.frontBrake.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              frontBrake: current.frontBrake.copyWith(overallStatus: status),
            ),
          ),
          child: _buildBrakeDiagnosisFields(
            currentTab,
            systemKey: 'front_brake',
            profile: profile,
            brakeSheet: diagnosisSheet.frontBrake,
            prefix: 'front',
            title: 'delantero',
            helperText: brakeType != null && !_isDiscBrakeType(brakeType)
                ? 'La ficha dice freno ${_formatBrakeSystemDetail(brakeType, rimBrakeFamily)}: no hay rotor que medir.'
                : null,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(frontBrake: transform(current.frontBrake)),
              refresh: refresh,
            ),
          ),
        );
      case 'rear_brake':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.rearBrake.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.rearBrake.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              rearBrake: current.rearBrake.copyWith(overallStatus: status),
            ),
          ),
          child: _buildBrakeDiagnosisFields(
            currentTab,
            systemKey: 'rear_brake',
            profile: profile,
            brakeSheet: diagnosisSheet.rearBrake,
            prefix: 'rear',
            title: 'trasero',
            helperText: brakeType != null && !_isDiscBrakeType(brakeType)
                ? 'La ficha dice freno ${_formatBrakeSystemDetail(brakeType, rimBrakeFamily)}: no hay rotor que medir.'
                : null,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(rearBrake: transform(current.rearBrake)),
              refresh: refresh,
            ),
          ),
        );
      case 'drivetrain':
      default:
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.drivetrain.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.drivetrain.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              drivetrain: current.drivetrain.copyWith(overallStatus: status),
            ),
          ),
          child: _buildDrivetrainDiagnosisFields(
            currentTab,
            drivetrainSheet: diagnosisSheet.drivetrain,
            profile: profile,
          ),
        );
    }
  }

  Widget _buildDrivetrainDiagnosisFields(
    _BikeTabData currentTab, {
    required DrivetrainDiagnosisSheet drivetrainSheet,
    required BikeProfile? profile,
  }) {
    final selectionScopeKey = _diagnosisComponentSelectionScopeKey(
      currentTab.tabId,
      'drivetrain',
    );
    final componentSpecs =
        _structuredDiagnosisComponentSpecs('drivetrain', profile);
    final selectedComponentKey = _resolveStructuredDiagnosisComponentKey(
      'drivetrain',
      profile,
      selectionScopeKey: selectionScopeKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (componentSpecs.isNotEmpty) ...[
          Text(
            'Componentes del sistema',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          _buildDiagnosisComponentSelector(
            Theme.of(context),
            specs: componentSpecs,
            selectedComponentKey: selectedComponentKey,
            statusForComponent: (componentKey) =>
                _drivetrainComponentStatus(drivetrainSheet, componentKey),
            onSelected: (componentKey) {
              setState(() {
                _selectedStructuredDiagnosisComponentKeys[selectionScopeKey] =
                    componentKey;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (selectedComponentKey != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey('editor_$selectedComponentKey'),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildDrivetrainComponentEditor(
                currentTab,
                drivetrainSheet: drivetrainSheet,
                componentKey: selectedComponentKey,
              ),
            ),
          ),
        const SizedBox(height: 20),
        TextFormField(
          key: ValueKey(
            'diag_drive_notes_${currentTab.tabId}_${drivetrainSheet.notes ?? 'empty'}',
          ),
          initialValue: drivetrainSheet.notes,
          decoration: const InputDecoration(
            labelText: 'Notas transmisión',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  notes: normalized,
                  clearNotes: normalized == null,
                ),
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDiagnosisComponentSelector(
    ThemeData theme, {
    required List<_StructuredDiagnosisComponentSpec> specs,
    required String? selectedComponentKey,
    required BikeSystemOverallStatus Function(String componentKey)
        statusForComponent,
    required ValueChanged<String> onSelected,
  }) {
    if (specs.isEmpty) return const SizedBox.shrink();
    if (MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    )) {
      final choices = specs.map(
        (spec) {
          final status = statusForComponent(spec.componentKey);
          return MechanicJobCompactChoice(
            id: spec.componentKey,
            label: spec.label,
            icon: spec.icon,
            statusLabel: status.displayName,
            statusColor: _diagnosisStatusColor(theme, status),
          );
        },
      ).toList(growable: false);
      return MechanicJobCompactChoiceMenu(
        controlLabel: 'Componente',
        selectedId: selectedComponentKey ?? specs.first.componentKey,
        choices: choices,
        onSelected: onSelected,
      );
    }

    return _DiagnosisComponentSelectorStrip(
      key: ValueKey(
          specs.isEmpty ? 'diag_components_empty' : specs.first.systemKey),
      specs: specs,
      selectedComponentKey: selectedComponentKey,
      statusForComponent: statusForComponent,
      onSelected: onSelected,
      colorForStatus: (status) => _diagnosisStatusColor(theme, status),
    );
  }

  Widget _buildDrivetrainComponentEditor(
    _BikeTabData currentTab, {
    required DrivetrainDiagnosisSheet drivetrainSheet,
    required String componentKey,
  }) {
    switch (componentKey) {
      case 'chain':
        return Column(
          children: [
            _buildChainWearField(currentTab, drivetrainSheet),
            const SizedBox(height: 12),
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_chain_lube_${currentTab.tabId}_${drivetrainSheet.chainLubricationStatus ?? 'empty'}',
              label: 'Lubricación cadena',
              icon: Icons.opacity_outlined,
              value: drivetrainSheet.chainLubricationStatus,
              options: _kChainLubricationOptions,
              onChanged: (value) {
                _updateCurrentDiagnosisSheet(
                  (current) => current.copyWith(
                    drivetrain: current.drivetrain.copyWith(
                      chainLubricationStatus: value,
                      clearChainLubricationStatus: value == null,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      case 'cassette':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_cassette_${currentTab.tabId}_${drivetrainSheet.cassetteCondition ?? 'empty'}',
          label: 'Estado cassette',
          icon: Icons.settings_input_component_outlined,
          value: drivetrainSheet.cassetteCondition,
          options: _kDrivetrainWearConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  cassetteCondition: value,
                  clearCassetteCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'chainring':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_chainring_${currentTab.tabId}_${drivetrainSheet.chainringCondition ?? 'empty'}',
          label: 'Estado plato',
          icon: Icons.adjust,
          value: drivetrainSheet.chainringCondition,
          options: _kDrivetrainWearConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  chainringCondition: value,
                  clearChainringCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'rear_derailleur':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_rear_derailleur_${currentTab.tabId}_${drivetrainSheet.rearDerailleurCondition ?? 'empty'}',
          label: 'Estado cambio trasero',
          icon: Icons.alt_route_outlined,
          value: drivetrainSheet.rearDerailleurCondition,
          options: _kDerailleurConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  rearDerailleurCondition: value,
                  clearRearDerailleurCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'front_derailleur':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_front_derailleur_${currentTab.tabId}_${drivetrainSheet.frontDerailleurCondition ?? 'empty'}',
          label: 'Estado cambio delantero',
          icon: Icons.call_split_outlined,
          value: drivetrainSheet.frontDerailleurCondition,
          options: _kDerailleurConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  frontDerailleurCondition: value,
                  clearFrontDerailleurCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'shifter':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_cable_condition_${currentTab.tabId}_${drivetrainSheet.cableCondition ?? 'empty'}',
              label: 'Estado cables y fundas',
              icon: Icons.swap_horiz,
              value: drivetrainSheet.cableCondition,
              options: kDrivetrainCableConditionOptions,
              onChanged: (value) {
                _updateCurrentDiagnosisSheet(
                  (current) => current.copyWith(
                    drivetrain: current.drivetrain.copyWith(
                      cableCondition: value,
                      clearCableCondition: value == null,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_shifter_${currentTab.tabId}_${drivetrainSheet.shifterCondition ?? 'empty'}',
              label: 'Estado shifter',
              icon: Icons.touch_app_outlined,
              value: drivetrainSheet.shifterCondition,
              options: _kShifterConditionOptions,
              onChanged: (value) {
                _updateCurrentDiagnosisSheet(
                  (current) => current.copyWith(
                    drivetrain: current.drivetrain.copyWith(
                      shifterCondition: value,
                      clearShifterCondition: value == null,
                    ),
                  ),
                );
              },
            ),
          ],
        );
    }
  }

  Widget _buildWheelDiagnosisFields(
    _BikeTabData currentTab, {
    required String systemKey,
    required WheelDiagnosisSheet wheelSheet,
    required BikeProfile? profile,
    required Bike? bike,
    required String title,
    required _WheelDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);
    final selectionScopeKey = _diagnosisComponentSelectionScopeKey(
      currentTab.tabId,
      systemKey,
    );
    final componentSpecs = _structuredDiagnosisComponentSpecs(
      systemKey,
      profile,
    );
    final selectedComponentKey = _resolveStructuredDiagnosisComponentKey(
      systemKey,
      profile,
      selectionScopeKey: selectionScopeKey,
    );
    final technicalValues =
        profile?.technicalValues ?? const <String, dynamic>{};
    final contextChips = <Widget>[];

    void addContextChip(IconData icon, String? label) {
      final normalized = _normalizeNullableText(label ?? '');
      if (normalized == null) return;
      contextChips.add(
        _buildStructuredDiagnosisMetaChip(theme, icon: icon, label: normalized),
      );
    }

    final wheelSize = _normalizeNullableText(bike?.wheelSize ?? '');
    addContextChip(
      Icons.circle_outlined,
      wheelSize == null ? null : 'Aro $wheelSize',
    );
    final hubSpacing = systemKey == 'front_wheel'
        ? bike?.frontHubSpacingMm
        : bike?.rearHubSpacingMm;
    if (hubSpacing != null) {
      addContextChip(
        Icons.settings_input_component_outlined,
        'Maza ${_formatHubSpacingMm(hubSpacing)} mm',
      );
    }
    final spokeKey =
        systemKey == 'front_wheel' ? 'frontSpokeHoles' : 'rearSpokeHoles';
    final spokeHoles =
        _normalizeNullableText(technicalValues[spokeKey]?.toString() ?? '');
    addContextChip(
      Icons.blur_circular_outlined,
      spokeHoles == null ? null : '$spokeHoles rayos',
    );
    final valveType =
        _normalizeNullableText(technicalValues['valveType']?.toString() ?? '');
    addContextChip(
      Icons.opacity_outlined,
      valveType == null ? null : 'Valvula $valveType',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contextChips.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: contextChips),
          const SizedBox(height: 16),
        ],
        if (componentSpecs.isNotEmpty) ...[
          Text(
            'Componentes del sistema',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildDiagnosisComponentSelector(
            theme,
            specs: componentSpecs,
            selectedComponentKey: selectedComponentKey,
            statusForComponent: (componentKey) =>
                _wheelComponentStatus(wheelSheet, componentKey),
            onSelected: (componentKey) {
              setState(() {
                _selectedStructuredDiagnosisComponentKeys[selectionScopeKey] =
                    componentKey;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (selectedComponentKey != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey('editor_${systemKey}_$selectedComponentKey'),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildWheelComponentEditor(
                currentTab,
                systemKey: systemKey,
                wheelSheet: wheelSheet,
                componentKey: selectedComponentKey,
                update: update,
              ),
            ),
          ),
        const SizedBox(height: 20),
        TextFormField(
          key: ValueKey(
            'diag_${systemKey}_notes_${currentTab.tabId}_${wheelSheet.notes ?? 'empty'}',
          ),
          initialValue: wheelSheet.notes,
          decoration: InputDecoration(
            labelText: 'Notas rueda $title',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            update(
              (current) => current.copyWith(
                notes: normalized,
                clearNotes: normalized == null,
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildWheelComponentEditor(
    _BikeTabData currentTab, {
    required String systemKey,
    required WheelDiagnosisSheet wheelSheet,
    required String componentKey,
    required _WheelDiagnosisSheetUpdater update,
  }) {
    switch (componentKey) {
      case 'tire':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_${systemKey}_tire_${currentTab.tabId}_${wheelSheet.tireCondition ?? 'empty'}',
              label: 'Estado del neumático',
              icon: Icons.trip_origin,
              value: wheelSheet.tireCondition,
              options: _kWheelTireConditionOptions,
              onChanged: (value) {
                update(
                  (current) => current.copyWith(
                    tireCondition: value,
                    clearTireCondition: value == null,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_${systemKey}_tubeless_${currentTab.tabId}_${wheelSheet.tubelessStatus ?? 'empty'}',
              label: 'Estado tubeless',
              icon: Icons.opacity_outlined,
              value: wheelSheet.tubelessStatus,
              options: _kWheelTubelessStatusOptions,
              onChanged: (value) {
                update(
                  (current) => current.copyWith(
                    tubelessStatus: value,
                    clearTubelessStatus: value == null,
                  ),
                );
              },
            ),
          ],
        );
      case 'rim':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_${systemKey}_rim_${currentTab.tabId}_${wheelSheet.rimCondition ?? 'empty'}',
          label: 'Estado aro',
          icon: Icons.circle_outlined,
          value: wheelSheet.rimCondition,
          options: _kWheelRimConditionOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                rimCondition: value,
                clearRimCondition: value == null,
              ),
            );
          },
        );
      case 'spokes':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_${systemKey}_spokes_${currentTab.tabId}_${wheelSheet.spokeCondition ?? 'empty'}',
          label: 'Estado rayos',
          icon: Icons.blur_circular_outlined,
          value: wheelSheet.spokeCondition,
          options: _kWheelSpokeConditionOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                spokeCondition: value,
                clearSpokeCondition: value == null,
              ),
            );
          },
        );
      case 'hub':
      default:
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_${systemKey}_hub_${currentTab.tabId}_${wheelSheet.hubBearingCondition ?? 'empty'}',
          label: 'Estado rodamientos maza',
          icon: Icons.settings_input_component_outlined,
          value: wheelSheet.hubBearingCondition,
          options: _kWheelHubBearingConditionOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                hubBearingCondition: value,
                clearHubBearingCondition: value == null,
              ),
            );
          },
        );
    }
  }

  Widget _buildBottomBracketDiagnosisFields(
    _BikeTabData currentTab, {
    required BottomBracketDiagnosisSheet bottomBracketSheet,
    required BikeProfile? profile,
    required _BottomBracketDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);
    final familyLabel = bottomBracketFamilyLabel(
      profile?.technicalValues['bottomBracketFamily']?.toString(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (familyLabel != null && familyLabel.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStructuredDiagnosisMetaChip(
                theme,
                icon: Icons.hub_outlined,
                label: 'Familia BB: $familyLabel',
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _buildDiagnosisSelectField(
          keySuffix:
              'diag_bb_bearing_${currentTab.tabId}_${bottomBracketSheet.bearingCondition ?? 'empty'}',
          label: 'Estado rodamientos pedalier',
          icon: Icons.hub_outlined,
          value: bottomBracketSheet.bearingCondition,
          options: _kBearingConditionOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                bearingCondition: value,
                clearBearingCondition: value == null,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildDiagnosisSelectField(
          keySuffix:
              'diag_bb_noise_${currentTab.tabId}_${bottomBracketSheet.noiseStatus ?? 'empty'}',
          label: 'Ruidos / juego pedalier',
          icon: Icons.graphic_eq,
          value: bottomBracketSheet.noiseStatus,
          options: _kMechanicalNoiseStatusOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                noiseStatus: value,
                clearNoiseStatus: value == null,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(
            'diag_bb_notes_${currentTab.tabId}_${bottomBracketSheet.notes ?? 'empty'}',
          ),
          initialValue: bottomBracketSheet.notes,
          decoration: const InputDecoration(
            labelText: 'Notas pedalier / BB',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            update(
              (current) => current.copyWith(
                notes: normalized,
                clearNotes: normalized == null,
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCockpitDiagnosisFields(
    _BikeTabData currentTab, {
    required CockpitDiagnosisSheet cockpitSheet,
    required _CockpitDiagnosisSheetUpdater update,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiagnosisSelectField(
          keySuffix:
              'diag_cockpit_bearing_${currentTab.tabId}_${cockpitSheet.headsetBearingCondition ?? 'empty'}',
          label: 'Estado rodamientos headset',
          icon: Icons.settings_input_component_outlined,
          value: cockpitSheet.headsetBearingCondition,
          options: _kBearingConditionOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                headsetBearingCondition: value,
                clearHeadsetBearingCondition: value == null,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildDiagnosisSelectField(
          keySuffix:
              'diag_cockpit_noise_${currentTab.tabId}_${cockpitSheet.headsetNoiseStatus ?? 'empty'}',
          label: 'Ruidos / juego direccion',
          icon: Icons.graphic_eq,
          value: cockpitSheet.headsetNoiseStatus,
          options: _kMechanicalNoiseStatusOptions,
          onChanged: (value) {
            update(
              (current) => current.copyWith(
                headsetNoiseStatus: value,
                clearHeadsetNoiseStatus: value == null,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(
            'diag_cockpit_notes_${currentTab.tabId}_${cockpitSheet.notes ?? 'empty'}',
          ),
          initialValue: cockpitSheet.notes,
          decoration: const InputDecoration(
            labelText: 'Notas cockpit / direccion',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            update(
              (current) => current.copyWith(
                notes: normalized,
                clearNotes: normalized == null,
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSuspensionDiagnosisFields(
    _BikeTabData currentTab, {
    required SuspensionDiagnosisSheet suspensionSheet,
    required BikeProfile? profile,
    required _SuspensionDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);
    final selectionScopeKey =
        _diagnosisComponentSelectionScopeKey(currentTab.tabId, 'suspension');
    final componentSpecs =
        _structuredDiagnosisComponentSpecs('suspension', profile);
    final selectedComponentKey = _resolveStructuredDiagnosisComponentKey(
      'suspension',
      profile,
      selectionScopeKey: selectionScopeKey,
    );
    final suspensionLayout = _normalizeNullableText(
      profile?.technicalValues['suspensionLayout']?.toString() ?? '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (suspensionLayout != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStructuredDiagnosisMetaChip(
                theme,
                icon: Icons.waves_outlined,
                label: 'Layout: $suspensionLayout',
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (componentSpecs.isNotEmpty) ...[
          Text(
            'Componentes del sistema',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildDiagnosisComponentSelector(
            theme,
            specs: componentSpecs,
            selectedComponentKey: selectedComponentKey,
            statusForComponent: (componentKey) =>
                _suspensionComponentStatus(suspensionSheet, componentKey),
            onSelected: (componentKey) {
              setState(() {
                _selectedStructuredDiagnosisComponentKeys[selectionScopeKey] =
                    componentKey;
              });
            },
          ),
          const SizedBox(height: 16),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              'La bici no expone un componente de suspension visitable desde el perfil tecnico actual. Puedes dejar notas si observaste algo relevante, pero no se fuerza una ficha imposible para una configuracion rigida.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (selectedComponentKey != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey('editor_suspension_$selectedComponentKey'),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildSuspensionComponentEditor(
                currentTab,
                suspensionSheet: suspensionSheet,
                componentKey: selectedComponentKey,
                update: update,
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(
            'diag_suspension_notes_${currentTab.tabId}_${suspensionSheet.notes ?? 'empty'}',
          ),
          initialValue: suspensionSheet.notes,
          decoration: const InputDecoration(
            labelText: 'Notas suspension',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            update(
              (current) => current.copyWith(
                notes: normalized,
                clearNotes: normalized == null,
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSuspensionComponentEditor(
    _BikeTabData currentTab, {
    required SuspensionDiagnosisSheet suspensionSheet,
    required String componentKey,
    required _SuspensionDiagnosisSheetUpdater update,
  }) {
    switch (componentKey) {
      case 'rear_shock':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_rear_shock_condition_${currentTab.tabId}_${suspensionSheet.rearShockCondition ?? 'empty'}',
              label: 'Estado amortiguador',
              icon: Icons.linear_scale,
              value: suspensionSheet.rearShockCondition,
              options: _kSuspensionConditionOptions,
              onChanged: (value) {
                update(
                  (current) => current.copyWith(
                    rearShockCondition: value,
                    clearRearShockCondition: value == null,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_rear_shock_noise_${currentTab.tabId}_${suspensionSheet.rearShockNoiseStatus ?? 'empty'}',
              label: 'Ruidos amortiguador',
              icon: Icons.graphic_eq,
              value: suspensionSheet.rearShockNoiseStatus,
              options: _kMechanicalNoiseStatusOptions,
              onChanged: (value) {
                update(
                  (current) => current.copyWith(
                    rearShockNoiseStatus: value,
                    clearRearShockNoiseStatus: value == null,
                  ),
                );
              },
            ),
          ],
        );
      case 'fork':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_fork_condition_${currentTab.tabId}_${suspensionSheet.forkCondition ?? 'empty'}',
              label: 'Estado horquilla',
              icon: Icons.waves_outlined,
              value: suspensionSheet.forkCondition,
              options: _kSuspensionConditionOptions,
              onChanged: (value) {
                update(
                  (current) => current.copyWith(
                    forkCondition: value,
                    clearForkCondition: value == null,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_fork_noise_${currentTab.tabId}_${suspensionSheet.forkNoiseStatus ?? 'empty'}',
              label: 'Ruidos horquilla',
              icon: Icons.graphic_eq,
              value: suspensionSheet.forkNoiseStatus,
              options: _kMechanicalNoiseStatusOptions,
              onChanged: (value) {
                update(
                  (current) => current.copyWith(
                    forkNoiseStatus: value,
                    clearForkNoiseStatus: value == null,
                  ),
                );
              },
            ),
          ],
        );
    }
  }

  String _formatHubSpacingMm(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  Widget _buildChainWearField(
    _BikeTabData currentTab,
    DrivetrainDiagnosisSheet drivetrainSheet,
  ) {
    final gaugeValue = _chainWearGaugeValue(drivetrainSheet.chainWearPercent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Medición desgaste cadena',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _formatChainWearGauge(drivetrainSheet.chainWearPercent),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (drivetrainSheet.chainWearPercent != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _updateCurrentDiagnosisSheet(
                    (current) => current.copyWith(
                      drivetrain: current.drivetrain.copyWith(
                        clearChainWearPercent: true,
                      ),
                    ),
                  );
                },
                child: const Text('Limpiar'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Usa la medición tipo checker 0.0 a 1.0. El sistema la conserva internamente como porcentaje para compatibilidad con el modelo actual.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Slider(
          key: ValueKey(
            'diag_chain_slider_${currentTab.tabId}_${drivetrainSheet.chainWearPercent?.toString() ?? 'empty'}',
          ),
          value: gaugeValue,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: gaugeValue.toStringAsFixed(2),
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  chainWearPercent: _chainWearPercentFromGauge(value),
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0.0', style: Theme.of(context).textTheme.bodySmall),
            Text('0.5', style: Theme.of(context).textTheme.bodySmall),
            Text('0.75', style: Theme.of(context).textTheme.bodySmall),
            Text('1.0', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _buildDiagnosisSelectField({
    required String keySuffix,
    required String label,
    required IconData icon,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return BikeshopSingleSelectDropdownField(
      key: ValueKey(keySuffix),
      options: serviceQuestionOptionsFromMap(options),
      value: value,
      labelText: label,
      icon: icon,
      includeEmptyOption: true,
      onChanged: onChanged,
    );
  }

  BikeSystemOverallStatus _brakeComponentStatus(
    BrakeDiagnosisSheet brakeSheet,
    String componentKey,
  ) {
    switch (componentKey) {
      case 'brake_pad':
        return _maxSystemStatus([
          _statusFromWearPercentValue(brakeSheet.padWearPercent),
          _statusFromConditionValue(brakeSheet.padContaminationStatus),
        ]);
      case 'rotor':
        return _maxSystemStatus([
          _statusFromRotorThicknessValue(brakeSheet.rotorThicknessMm),
          _statusFromConditionValue(brakeSheet.rotorTruenessStatus),
          _statusFromConditionValue(brakeSheet.rotorContaminationStatus),
        ]);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _statusFromWearPercentValue(double? value) {
    if (value == null) return BikeSystemOverallStatus.unknown;
    if (value >= 75) return BikeSystemOverallStatus.critical;
    if (value >= 50) return BikeSystemOverallStatus.attention;
    return BikeSystemOverallStatus.ok;
  }

  BikeSystemOverallStatus _statusFromRotorThicknessValue(double? value) {
    if (value == null) return BikeSystemOverallStatus.unknown;
    if (value <= 1.5) return BikeSystemOverallStatus.critical;
    if (value <= 1.7) return BikeSystemOverallStatus.attention;
    return BikeSystemOverallStatus.ok;
  }

  String _formatPercentMeasurement(double? value) {
    if (value == null) return 'Sin medicion';
    return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
  }

  String _formatRotorThickness(double? value) {
    if (value == null) return 'Sin medicion';
    return '${value.toStringAsFixed(2)} mm';
  }

  Widget _buildDiagnosisSystemCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required BikeSystemOverallStatus status,
    required Color statusTint,
    required ValueChanged<BikeSystemOverallStatus> onStatusChanged,
    required Widget child,
  }) {
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(isCompact ? 12 : 24),
      decoration: BoxDecoration(
        color: isCompact
            ? Colors.transparent
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(isCompact ? 0 : 20),
        border: isCompact
            ? null
            : Border.all(
                color: theme.dividerColor.withValues(alpha: 0.15),
              ),
        boxShadow: isCompact
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
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
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCompact)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusTint.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.displayName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusTint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<BikeSystemOverallStatus>(
            key: ValueKey('diag_status_${title}_${status.dbValue}'),
            initialValue: status,
            decoration: InputDecoration(
              labelText: 'Estado general',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              prefixIcon: const Icon(Icons.monitor_heart_outlined),
            ),
            items: BikeSystemOverallStatus.values.map((value) {
              return DropdownMenuItem(
                value: value,
                child: Text(value.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            },
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildUnavailableStructuredDiagnosisSystemCard(
    ThemeData theme, {
    required BikeSystemControllerSpec activeSpec,
    required BikeProfile? profile,
    required Bike? bike,
    required String templateKey,
  }) {
    final technicalValues =
        profile?.technicalValues ?? const <String, dynamic>{};
    final contextLines = <String>[];

    switch (activeSpec.systemKey) {
      case 'suspension':
        final suspensionLayout =
            technicalValues['suspensionLayout']?.toString();
        if (suspensionLayout != null && suspensionLayout.isNotEmpty) {
          contextLines.add('Suspensión confirmada: $suspensionLayout');
        }
        break;
      case 'front_wheel':
        if (bike?.wheelSize?.trim().isNotEmpty == true) {
          contextLines.add('Aro compartido: ${bike!.wheelSize!.trim()}');
        }
        if (bike?.frontHubSpacingMm != null) {
          final spacing = bike!.frontHubSpacingMm!;
          contextLines.add(
            'Maza delantera: ${spacing == spacing.roundToDouble() ? spacing.toStringAsFixed(0) : spacing.toStringAsFixed(1)} mm',
          );
        }
        final frontSpokeHoles = technicalValues['frontSpokeHoles']?.toString();
        if (frontSpokeHoles != null && frontSpokeHoles.isNotEmpty) {
          contextLines.add('Rayos rueda delantera: $frontSpokeHoles');
        }
        final frontValveType = technicalValues['valveType']?.toString();
        if (frontValveType != null && frontValveType.isNotEmpty) {
          contextLines.add('Válvula compartida: $frontValveType');
        }
        break;
      case 'bottom_bracket':
        final bottomBracketFamily =
            technicalValues['bottomBracketFamily']?.toString();
        if (bottomBracketFamily != null && bottomBracketFamily.isNotEmpty) {
          contextLines.add('Pedalier / BB confirmado: $bottomBracketFamily');
        }
        break;
      case 'rear_wheel':
        if (bike?.wheelSize?.trim().isNotEmpty == true) {
          contextLines.add('Aro compartido: ${bike!.wheelSize!.trim()}');
        }
        if (bike?.rearHubSpacingMm != null) {
          final spacing = bike!.rearHubSpacingMm!;
          contextLines.add(
            'Maza trasera: ${spacing == spacing.roundToDouble() ? spacing.toStringAsFixed(0) : spacing.toStringAsFixed(1)} mm',
          );
        }
        final rearSpokeHoles = technicalValues['rearSpokeHoles']?.toString();
        if (rearSpokeHoles != null && rearSpokeHoles.isNotEmpty) {
          contextLines.add('Rayos rueda trasera: $rearSpokeHoles');
        }
        final rearValveType = technicalValues['valveType']?.toString();
        if (rearValveType != null && rearValveType.isNotEmpty) {
          contextLines.add('Válvula compartida: $rearValveType');
        }
        break;
      case 'wheels':
        if (bike?.wheelSize?.trim().isNotEmpty == true) {
          contextLines.add('Aro: ${bike!.wheelSize!.trim()}');
        }
        final frontSpokeHoles = technicalValues['frontSpokeHoles']?.toString();
        if (frontSpokeHoles != null && frontSpokeHoles.isNotEmpty) {
          contextLines.add('Rayos rueda delantera: $frontSpokeHoles');
        }
        final rearSpokeHoles = technicalValues['rearSpokeHoles']?.toString();
        if (rearSpokeHoles != null && rearSpokeHoles.isNotEmpty) {
          contextLines.add('Rayos rueda trasera: $rearSpokeHoles');
        }
        final valveType = technicalValues['valveType']?.toString();
        if (valveType != null && valveType.isNotEmpty) {
          contextLines.add('Válvula: $valveType');
        }
        break;
      case 'cockpit':
        contextLines.add(
          'Headset y dirección siguen anclados aquí como sistema de steering, aunque esta visita todavía no tenga ficha estructurada editable.',
        );
      case 'front_brake':
      case 'rear_brake':
      case 'drivetrain':
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                      activeSpec.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeSpec.diagnosisSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Sin ficha estructurada',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este sistema ya usa el mismo controlador visual compartido del resto del backbone, pero la plantilla $templateKey todavía no modela una ficha estructurada editable para esta visita.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Hoy la verdad estructurada de la visita sigue limitada a transmisión, freno delantero y freno trasero. Cuando este sistema gane soporte, el mismo controlador se reutilizará aquí sin crear otra variante visual.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (contextLines.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Lo que ya dice la ficha',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...contextLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBrakeDiagnosisFields(
    _BikeTabData currentTab, {
    required String systemKey,
    required BikeProfile? profile,
    required BrakeDiagnosisSheet brakeSheet,
    required String prefix,
    required String title,
    String? helperText,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final selectionScopeKey = _diagnosisComponentSelectionScopeKey(
      currentTab.tabId,
      systemKey,
    );
    final componentSpecs =
        _structuredDiagnosisComponentSpecs(systemKey, profile);
    final selectedComponentKey = _resolveStructuredDiagnosisComponentKey(
      systemKey,
      profile,
      selectionScopeKey: selectionScopeKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (componentSpecs.isNotEmpty) ...[
          Text(
            'Componentes del sistema',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          _buildDiagnosisComponentSelector(
            Theme.of(context),
            specs: componentSpecs,
            selectedComponentKey: selectedComponentKey,
            statusForComponent: (componentKey) =>
                _brakeComponentStatus(brakeSheet, componentKey),
            onSelected: (componentKey) {
              setState(() {
                _selectedStructuredDiagnosisComponentKeys[selectionScopeKey] =
                    componentKey;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (selectedComponentKey != null)
          _buildBrakeComponentEditor(
            currentTab,
            brakeSheet: brakeSheet,
            componentKey: selectedComponentKey,
            prefix: prefix,
            title: title,
            update: update,
          ),
        if (helperText != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .secondary
                    .withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildBrakeSymptomsSection(
          brakeSheet,
          title: title,
          update: update,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(
            'diag_${prefix}_notes_${currentTab.tabId}_${brakeSheet.notes ?? 'empty'}',
          ),
          initialValue: brakeSheet.notes,
          decoration: InputDecoration(
            labelText: 'Notas freno $title',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            update(
              (current) => current.copyWith(
                notes: normalized,
                clearNotes: normalized == null,
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildBrakeComponentEditor(
    _BikeTabData currentTab, {
    required BrakeDiagnosisSheet brakeSheet,
    required String componentKey,
    required String prefix,
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    switch (componentKey) {
      case 'rotor':
        return _buildRotorThicknessField(
          currentTab,
          brakeSheet: brakeSheet,
          prefix: prefix,
          title: title,
          update: update,
        );
      case 'brake_pad':
      default:
        return _buildBrakePadWearField(
          currentTab,
          brakeSheet: brakeSheet,
          prefix: prefix,
          title: title,
          update: update,
        );
    }
  }

  Widget _buildDiagnosisLinkedBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link_outlined,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            'Servicio guiado',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrakePadWearField(
    _BikeTabData currentTab, {
    required BrakeDiagnosisSheet brakeSheet,
    required String prefix,
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final wearValue = brakeSheet.padWearPercent ?? 0;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
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
                      'Desgaste pastillas $title',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildDiagnosisLinkedBadge(theme),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatPercentMeasurement(brakeSheet.padWearPercent),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (brakeSheet.padWearPercent != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    update((current) =>
                        current.copyWith(clearPadWearPercent: true));
                  },
                  child: const Text('Limpiar'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Usa el slider para dejar un estado rápido de desgaste sin depender de ingreso manual.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            key: ValueKey(
              'diag_${prefix}_pad_slider_${currentTab.tabId}_${brakeSheet.padWearPercent?.toString() ?? 'empty'}',
            ),
            value: wearValue.clamp(0, 100),
            min: 0,
            max: 100,
            divisions: 20,
            label: wearValue.toStringAsFixed(0),
            onChanged: (value) {
              update((current) => current.copyWith(padWearPercent: value));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%', style: theme.textTheme.bodySmall),
              Text('50%', style: theme.textTheme.bodySmall),
              Text('75%', style: theme.textTheme.bodySmall),
              Text('100%', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          _buildDiagnosisSelectField(
            keySuffix:
                'diag_${prefix}_pad_contamination_${currentTab.tabId}_${brakeSheet.padContaminationStatus ?? 'empty'}',
            label: 'Contaminacion pastillas $title',
            icon: Icons.cleaning_services_outlined,
            value: brakeSheet.padContaminationStatus,
            options: kBrakePadContaminationOptions,
            onChanged: (value) {
              update(
                (current) => current.copyWith(
                  padContaminationStatus: value,
                  clearPadContaminationStatus: value == null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRotorThicknessField(
    _BikeTabData currentTab, {
    required BrakeDiagnosisSheet brakeSheet,
    required String prefix,
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
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
                      'Grosor rotor $title',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildDiagnosisLinkedBadge(theme),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatRotorThickness(brakeSheet.rotorThicknessMm),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(
              'diag_${prefix}_rotor_${currentTab.tabId}_${brakeSheet.rotorThicknessMm?.toString() ?? 'empty'}',
            ),
            initialValue: brakeSheet.rotorThicknessMm?.toString(),
            decoration: InputDecoration(
              labelText: 'Medicion rotor $title (mm)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.straighten_outlined),
              suffixIcon: brakeSheet.rotorThicknessMm != null
                  ? IconButton(
                      onPressed: () {
                        update(
                          (current) =>
                              current.copyWith(clearRotorThicknessMm: true),
                        );
                      },
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              final parsed = _parseNullableDouble(value);
              update(
                (current) => current.copyWith(
                  rotorThicknessMm: parsed,
                  clearRotorThicknessMm: parsed == null,
                ),
                refresh: false,
              );
            },
          ),
          const SizedBox(height: 12),
          _buildDiagnosisSelectField(
            keySuffix:
                'diag_${prefix}_rotor_trueness_${currentTab.tabId}_${brakeSheet.rotorTruenessStatus ?? 'empty'}',
            label: 'Trueness rotor $title',
            icon: Icons.sync_problem_outlined,
            value: brakeSheet.rotorTruenessStatus,
            options: kBrakeRotorTruenessOptions,
            onChanged: (value) {
              update(
                (current) => current.copyWith(
                  rotorTruenessStatus: value,
                  clearRotorTruenessStatus: value == null,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildDiagnosisSelectField(
            keySuffix:
                'diag_${prefix}_rotor_contamination_${currentTab.tabId}_${brakeSheet.rotorContaminationStatus ?? 'empty'}',
            label: 'Contaminacion rotor $title',
            icon: Icons.cleaning_services_outlined,
            value: brakeSheet.rotorContaminationStatus,
            options: kBrakeRotorContaminationOptions,
            onChanged: (value) {
              update(
                (current) => current.copyWith(
                  rotorContaminationStatus: value,
                  clearRotorContaminationStatus: value == null,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Referencia rapida: <= 1.7 mm requiere atencion y <= 1.5 mm se considera critico para esta capa de memoria.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrakeSymptomsSection(
    BrakeDiagnosisSheet brakeSheet, {
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sintomas freno $title',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _buildDiagnosisLinkedBadge(theme),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Marca solo lo observado en esta visita. Este bloque queda en la verdad de diagnóstico del freno y lo reutiliza el servicio guiado.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          BikeshopMultiSelectPickerField(
            options: _kBrakeSymptomOptions,
            selectedValues: brakeSheet.symptomKeys,
            dialogTitle: 'Sintomas freno $title',
            onChanged: (nextSymptoms) {
              final orderedSymptoms =
                  canonicalizeBrakeSymptomKeys(nextSymptoms);
              update(
                (current) => current.copyWith(
                  symptomKeys: orderedSymptoms,
                  clearSymptomKeys: orderedSymptoms.isEmpty,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BIKE TAB BAR (Multi-bike support) - Browser-style elegant tabs
  // ============================================================
  // ignore: unused_element
  Widget _buildBikeTabBar(ThemeData theme) {
    // Browser-style tabs that sit on top of the content area
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            // Existing bike tabs - browser style
            ..._bikeTabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isSelected = index == _selectedBikeTabIndex;
              // Hide General tab chip when empty
              if (tab.isGeneralTab && tab.partItems.isEmpty) {
                return const SizedBox.shrink();
              }

              return _BrowserStyleBikeTab(
                label: tab.displayName,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedBikeTabIndex = index;
                    _selectedBike = _bikeTabs[index].bike;
                  });
                  unawaited(_loadSelectedBikeProfile(_selectedBike));
                },
                onClose: !_isCommercialSnapshotLocked &&
                        _jobType == JobType.service &&
                        _bikeTabs.length > 1
                    ? () => _confirmRemoveBike(index, tab.displayName)
                    : null,
              );
            }),
            // Add new tab button
            if (_jobType == JobType.service)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: IconButton(
                  onPressed:
                      _isCommercialSnapshotLocked ? null : _showAddBikeSelector,
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'Agregar bicicleta',
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(32, 32),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CUSTOMER + BIKE SECTION (original design)
  // ============================================================
  Widget _buildCustomerBikeSection() {
    final warrantyObject = _selectedWarrantySource?.physicalObject;
    final warrantyHasBike = _jobType == JobType.warranty &&
        ((warrantyObject?.isBike ?? false) ||
            (_selectedWarrantySource == null && _existingJob?.bikeId != null));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Customer selector with quick add
        Semantics(
          button: widget.jobId == null,
          label: _selectedCustomer == null
              ? 'Seleccionar cliente'
              : 'Cliente ${_selectedCustomer!.name}',
          child: InkWell(
            key: const ValueKey('mechanic-job-customer-selector'),
            onTap: widget.jobId != null
                ? null // Disable editing customer in edit mode
                : _showCustomerSelector,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Cliente *',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person),
                suffixIcon: widget.jobId == null
                    ? const Icon(Icons.arrow_drop_down)
                    : null,
                errorText: _hasAttemptedSave && _selectedCustomer == null
                    ? 'Seleccione un cliente'
                    : null,
              ),
              child: Text(
                _selectedCustomer?.name ?? 'Seleccione un cliente',
                style: _selectedCustomer != null
                    ? null
                    : TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_jobType == JobType.service || warrantyHasBike) ...[
          // Custom bike dropdown with action buttons
          if (_selectedCustomer != null)
            PopupMenuButton<String>(
              enabled: widget.jobId == null &&
                  _jobType == JobType.service, // Warranty object is inherited.
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _jobType == JobType.warranty
                      ? 'Bicicleta del trabajo original'
                      : 'Bicicleta *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.pedal_bike),
                  suffixIcon: _jobType == JobType.service
                      ? const Icon(Icons.arrow_drop_down)
                      : const Icon(Icons.lock_outline),
                  helperText: _jobType == JobType.warranty
                      ? 'Se hereda del trabajo original y no puede reemplazarse manualmente.'
                      : null,
                ),
                child: Text(
                  _jobType == JobType.warranty && _isLoadingWarrantySourceObject
                      ? 'Cargando bicicleta del trabajo original...'
                      : _jobType == JobType.warranty &&
                              _warrantySourceObjectError != null
                          ? _warrantySourceObjectError!
                          : _selectedBike != null
                              ? '${_selectedBike!.displayName}${_selectedBike!.serialNumber != null ? ' (S/N: ${_selectedBike!.serialNumber})' : ''}'
                              : 'Seleccione una bicicleta',
                  style: _selectedBike != null
                      ? null
                      : TextStyle(color: Colors.grey[600]),
                ),
              ),
              itemBuilder: (context) => [
                // Bike list - add to tabs (not just select)
                ..._bikes.map((bike) {
                  final alreadyInTabs =
                      _bikeTabs.any((tab) => tab.bike?.id == bike.id);
                  return PopupMenuItem<String>(
                    value: 'bike_${bike.id}',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${bike.displayName}${bike.serialNumber != null ? ' (S/N: ${bike.serialNumber})' : ''}',
                          ),
                        ),
                        if (alreadyInTabs)
                          Icon(Icons.check, size: 16, color: Colors.green[600]),
                      ],
                    ),
                    onTap: () {
                      // Use _addBikeTab to properly add to multi-bike system
                      _addBikeTab(bike);
                    },
                  );
                }),
                // Divider
                if (_bikes.isNotEmpty) const PopupMenuDivider(),
                // Nueva Bici button
                PopupMenuItem<String>(
                  value: 'new_bike',
                  child: const Row(
                    children: [
                      Icon(Icons.add, size: 18),
                      SizedBox(width: 8),
                      Text('Nueva bicicleta'),
                    ],
                  ),
                  onTap: () async {
                    // Delay to let menu close
                    final messenger = ScaffoldMessenger.of(context);
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (!mounted) return;

                    final newBike =
                        await _openBikeDialog(selectSavedBike: true);

                    if (!mounted) return;

                    // Add to multi-bike tabs
                    if (newBike != null && mounted) {
                      _addBikeTab(newBike);

                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                              'Bicicleta "${newBike.displayName}" creada y agregada'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
                // Gestionar Bicis button
                if (_bikes.isNotEmpty)
                  PopupMenuItem<String>(
                    value: 'manage_bikes',
                    child: const Row(
                      children: [
                        Icon(Icons.settings, size: 18),
                        SizedBox(width: 8),
                        Text('Gestionar bicicletas'),
                      ],
                    ),
                    onTap: () async {
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (mounted) {
                        _showBikeManagementDialog();
                      }
                    },
                  ),
              ],
            )
          else
            // Show disabled field when no customer selected
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Bicicleta *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pedal_bike),
                enabled: false,
              ),
              child: Text(
                'Primero seleccione un cliente',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          if (_selectedBike != null && _selectedBike!.isUnderWarranty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.green[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta bicicleta está bajo garantía hasta ${DateFormat('dd/MM/yyyy').format(_selectedBike!.warrantyUntil!)}',
                      style: TextStyle(color: Colors.green[900]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedBike != null) _buildBikeProfileSummaryCard(),
        ] else if (_jobType == JobType.warranty) ...[
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Objeto asociado',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.build_outlined),
            ),
            child: Text(
              _isLoadingWarrantySourceObject
                  ? 'Cargando objeto del trabajo original...'
                  : _warrantySourceObjectError != null
                      ? _warrantySourceObjectError!
                      : warrantyObject?.isComponent == true
                          ? (_selectedSubject?.name ??
                              warrantyObject?.subjectNotes ??
                              'Componente del trabajo original')
                          : 'Selecciona el trabajo original en la sección de garantía',
            ),
          ),
        ] else if (_jobType == JobType.itemService) ...[
          _lockFormContent(
            Column(
              children: [
                _buildSubjectPicker(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subjectNotesController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción manual del componente',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                    hintText:
                        'Obligatoria solo si no seleccionaste catálogo. Ej.: Rueda trasera 26", número de serie...',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            locked: _isPaymentProtectedCommercialSnapshotLocked,
          ),
        ] else if (_jobType == JobType.quotation) ...[
          TextFormField(
            controller: _subjectNotesController,
            decoration: const InputDecoration(
              labelText: 'Producto / servicio a cotizar *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.request_quote_outlined),
              suffixIcon: Tooltip(
                message:
                    'Úsalo para consultas sin bicicleta recibida, aunque el producto todavía no exista en inventario.',
                child: Icon(Icons.info_outline),
              ),
              hintText:
                  'Ej: Shimano Deore 12v, bicicleta gravel talla M, servicio de mantención...',
            ),
            maxLines: 2,
          ),
        ] else if (_jobType == JobType.sale) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Venta / cobro · Sin bicicleta ni componente recibido',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGeneralSection(ThemeData theme) {
    if (_jobType == JobType.sale) {
      return _buildSaleGeneralSection(theme);
    }

    final selectedTab = _currentBikeTab;
    final warrantySource = _selectedWarrantySource;
    final currentTab = _jobType == JobType.warranty &&
            (warrantySource == null ||
                !_warrantySourceObjectMatchesForm(warrantySource))
        ? null
        : selectedTab;
    final requestController = currentTab != null && !currentTab.isGeneralTab
        ? currentTab.clientRequestController
        : _clientRequestController;
    final requestKey = currentTab != null && !currentTab.isGeneralTab
        ? 'clientRequest_${currentTab.tabId}'
        : 'clientRequest_job';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.jobId == null) ...[
          _buildJobTypeSelector(),
          const SizedBox(height: 20),
        ] else ...[
          _buildJobTypeBadge(),
          const SizedBox(height: 20),
        ],
        if (_existingJob?.convertedAt != null &&
            _existingJob?.warrantyOutcome == WarrantyOutcome.notCovered &&
            _jobType == JobType.service) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Este trabajo de servicio técnico fue generada a partir de una Garantía No Cubierta.',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_jobType != JobType.quotation) ...[
          _buildReceptionPlanningSection(theme),
          const SizedBox(height: 18),
        ],
        TextFormField(
          key: ValueKey(requestKey),
          controller: requestController,
          decoration: const InputDecoration(
            labelText: 'Solicitud del cliente',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.chat_bubble_outline),
            hintText:
                'Qué pidió el cliente al dejar el objeto o solicitar la cotización...',
            alignLabelWithHint: true,
          ),
          minLines: 2,
          maxLines: 4,
        ),
        if (currentTab == null &&
            (_jobType == JobType.service || _jobType == JobType.warranty)) ...[
          const SizedBox(height: 12),
          _buildEmptyObjectGeneralNotice(theme),
        ],
        if (_jobType == JobType.warranty) ...[
          const SizedBox(height: 18),
          _buildWarrantySection(),
        ],
        if (_isProposalWorkflow) ...[
          const SizedBox(height: 18),
          _buildQuotationSection(),
        ],
      ],
    );
  }

  Widget _buildReceptionPlanningSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Recepción y compromiso',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'El estado operativo y las decisiones de presupuesto o garantía se cambian desde el chip Estado de la tabla.',
              child: Icon(
                Icons.info_outline,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final columns = constraints.maxWidth >= 840
                ? 3
                : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<JobPriority>(
                    initialValue: _selectedPriority,
                    decoration: const InputDecoration(
                      labelText: 'Prioridad',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: JobPriority.values
                        .map(
                          (priority) => DropdownMenuItem(
                            value: priority,
                            child: Text(priority.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (priority) {
                      if (priority != null) {
                        setState(() => _selectedPriority = priority);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedArrivalDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) {
                        setState(() => _selectedArrivalDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Ingreso',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.login),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(_selectedArrivalDate),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDeadline ??
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => _selectedDeadline = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Entrega comprometida',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event_available_outlined),
                      ),
                      child: Text(
                        _selectedDeadline == null
                            ? 'Sin fecha'
                            : DateFormat('dd/MM/yyyy')
                                .format(_selectedDeadline!),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    controller: _estimatedDurationController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,4}([\.,]\d{0,2})?$'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Horas estimadas',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timer_outlined),
                      suffixText: 'h',
                    ),
                  ),
                ),
                if (_existingJob != null)
                  SizedBox(
                    width: width,
                    child: TextFormField(
                      controller: _actualLaborHoursController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d{0,4}([\.,]\d{0,2})?$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Horas reales',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.handyman_outlined),
                        suffixText: 'h',
                        helperText: 'Tiempo efectivo del mecánico',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSaleGeneralSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.jobId == null) ...[
          _buildJobTypeSelector(),
          const SizedBox(height: 16),
        ] else ...[
          _buildJobTypeBadge(),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Icon(Icons.payments_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Seguimiento del cobro',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'Agrega los productos en Productos y Servicios. La factura vinculada controla abonos, saldo, inventario, impuestos y contabilidad.',
              child: Icon(
                Icons.info_outline,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _technicianNotesController,
          decoration: const InputDecoration(
            labelText: 'Acuerdo de pago / nota interna (opcional)',
            hintText: 'Ej.: abonará \$10.000 cada semana',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildEmptyObjectGeneralNotice(ThemeData theme) {
    var icon = Icons.pedal_bike_outlined;
    var message =
        'Agrega una bicicleta para habilitar la ficha técnica y el diagnóstico estructurado.';

    if (_jobType == JobType.quotation) {
      icon = Icons.description_outlined;
      message =
          'Puedes cotizar sin recibir una bicicleta. Registra la evaluación previa en Diagnóstico; no se crea ficha técnica, factura, stock ni contabilidad hasta convertir la cotización.';
    } else if (_jobType == JobType.itemService) {
      icon = Icons.build_circle_outlined;
      message =
          'Este trabajo recibe solo el componente. Registra sus hallazgos en Diagnóstico; no se crea ni se exige una bicicleta ficticia.';
    } else if (_jobType == JobType.warranty) {
      final source = _selectedWarrantySource;
      if (source == null) {
        icon = Icons.verified_user_outlined;
        message =
            'Selecciona el trabajo original para identificar si el cliente dejó una bicicleta completa o un componente y cargar el diagnóstico correcto.';
      } else if (_isLoadingWarrantySourceObject) {
        icon = Icons.sync;
        message =
            'Confirmando el objeto exacto del trabajo original. Espera antes de continuar.';
      } else if (_warrantySourceObjectError != null ||
          !source.physicalObject.isValid) {
        icon = Icons.error_outline;
        message = _warrantySourceObjectError ??
            'Clasifica primero el trabajo original como bicicleta o componente.';
      } else if (source.physicalObject.isComponent) {
        icon = Icons.build_circle_outlined;
        message =
            'La garantía corresponde a un componente suelto. Registra sus hallazgos en Diagnóstico sin crear una bicicleta ficticia.';
      } else {
        message =
            'La garantía corresponde a una bicicleta. Revisa el trabajo original si su ficha no se cargó antes de continuar.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // JOB TYPE UI HELPERS
  // ============================================================

  Future<bool> _confirmModeSwitchRemovesBikeContext(JobType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cambiar el tipo de trabajo?'),
        content: Text(
          'Al cambiar a ${type.displayName} se quitará la bicicleta seleccionada y su ficha/diagnóstico específico de esta creación. Los productos y servicios se conservarán en General para que no tengas que ingresarlos otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Mantener tipo actual'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Cambiar a ${type.displayName}'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _selectJobType(JobType type) async {
    final previousType = _jobType;
    if (previousType == type) return;

    final removesBikeContext = mechanicJobModeSwitchRemovesBikeContext(
      from: previousType,
      to: type,
      hasPhysicalBikeTabs: _hasPhysicalBikeTabs,
    );
    if (removesBikeContext &&
        !await _confirmModeSwitchRemovesBikeContext(type)) {
      return;
    }
    if (!mounted) return;

    setState(() {
      if (removesBikeContext) {
        _moveBikeTabLinesToStandalone();
      }
      _warrantySourceSelectionEpoch++;
      _isLoadingWarrantySourceObject = false;
      _warrantySourceObjectError = null;
      _pendingWarrantyRegistrationOperationKey = null;
      _pendingWarrantyDecisionOperationKey = null;
      _pendingWarrantyDecisionFingerprint = null;
      _warrantySaveCheckpoint.reset();

      // A warranty never inherits the free-form bicycle/component selection
      // of the previous mode. Its physical object is loaded exclusively from
      // the original delivered job selected below.
      if (type == JobType.warranty && previousType != JobType.warranty) {
        _clearSelectedBikeObject(discardPendingProfileEdits: true);
        _selectedWarrantySource = null;
        _selectedSubject = null;
      }

      _jobType = type;
      if (type == JobType.service) {
        // Most bicycle receptions begin with diagnosis + customer approval.
        // Workers can still choose Facturar ahora explicitly below.
        _serviceCommercialPath = ServiceCommercialPath.budgetFirst;
      }
      if (type == JobType.sale) {
        _selectedWorkbenchTab = _JobWorkbenchTab.general;
      }
      _warrantyOutcome = null;
      final isProposal = type == JobType.quotation ||
          (type == JobType.service &&
              _serviceCommercialPath == ServiceCommercialPath.budgetFirst);
      _quotationStatus = isProposal ? QuotationStatus.pending : null;
      _quotationValidUntil =
          isProposal ? DateTime.now().add(const Duration(days: 30)) : null;

      if (type != JobType.service && type != JobType.warranty) {
        _clearSelectedBikeObject(discardPendingProfileEdits: true);
      }

      if (type != JobType.itemService) {
        _selectedSubject = null;
      }

      if (type != JobType.itemService && type != JobType.quotation) {
        _subjectNotesController.clear();
      }

      if (type != JobType.warranty) {
        _selectedWarrantySource = null;
        _warrantyClaim = null;
        _warrantyDecisionReasonController.clear();
      }

      if (type == JobType.warranty) {
        // Switching an already-loaded non-warranty job creates a new claim;
        // there is no historical claim projection to hydrate for this mode.
        _warrantyClaimLoadCompleted = true;
      }

      final isWarrantyType = type == JobType.warranty;
      for (final tab in _bikeTabs) {
        tab.isWarrantyWork = isWarrantyType;
      }
    });

    if (type == JobType.warranty && _selectedCustomer != null) {
      unawaited(_loadWarrantySourcesForSelectedCustomer());
    }
  }

  void _selectServiceCommercialPath(ServiceCommercialPath path) {
    if (widget.jobId != null || _serviceCommercialPath == path) return;
    setState(() {
      _serviceCommercialPath = path;
      if (path == ServiceCommercialPath.budgetFirst) {
        _quotationStatus = QuotationStatus.pending;
        _quotationValidUntil ??= DateTime.now().add(const Duration(days: 30));
      } else {
        _quotationStatus = null;
        _quotationValidUntil = null;
      }
    });
  }

  Widget _buildServiceCommercialPathSelector(ThemeData theme) {
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Documento inicial',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: _serviceCommercialPath.description,
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Modalidad comercial del servicio',
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ServiceCommercialPath>(
              segments: const [
                ButtonSegment(
                  value: ServiceCommercialPath.budgetFirst,
                  icon: Icon(Icons.request_quote_outlined, size: 17),
                  label: Text('Presupuestar primero'),
                ),
                ButtonSegment(
                  value: ServiceCommercialPath.invoiceNow,
                  icon: Icon(Icons.receipt_long_outlined, size: 17),
                  label: Text('Facturar ahora'),
                ),
              ],
              selected: {_serviceCommercialPath},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _selectServiceCommercialPath(selection.first),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJobTypeSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Tipo de trabajo',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: _jobTypeDescription(_jobType),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: JobType.values.map((type) {
            final isSelected = _jobType == type;
            final textColor = isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant;
            final bgColor =
                isSelected ? colorScheme.primary : colorScheme.surface;
            final borderColor =
                isSelected ? colorScheme.primary : colorScheme.outlineVariant;

            return Tooltip(
              message: _jobTypeDescription(type),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => unawaited(_selectJobType(type)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: borderColor,
                        width: 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2))
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _jobTypeIcon(type),
                          size: 16,
                          color: textColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type.displayName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: textColor,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_jobType == JobType.service) ...[
          const SizedBox(height: 12),
          _buildServiceCommercialPathSelector(theme),
        ],
      ],
    );
  }

  String _jobTypeDescription(JobType type) {
    switch (type) {
      case JobType.service:
        return 'El cliente deja una bicicleta. Elige si primero enviarás un presupuesto o si la factura debe crearse al guardar.';
      case JobType.itemService:
        return 'El cliente deja solo un componente. No aumenta el contador de bicicletas.';
      case JobType.quotation:
        return 'Cotización sin bicicleta ni componente recibido: genera PDF, pero no factura, stock ni contabilidad hasta aprobarla.';
      case JobType.warranty:
        return 'Reclamo vinculado a un trabajo entregado. La cobertura se decide y registra por separado.';
      case JobType.sale:
        return 'Venta de productos con factura y seguimiento de abonos. No recibe bicicleta ni componente.';
    }
  }

  Widget _buildJobTypeBadge() {
    final theme = Theme.of(context);
    final label =
        _isServiceBudget ? 'Servicio · Presupuesto' : _jobType.displayName;
    final explanation = _isServiceBudget
        ? 'La bicicleta, ficha y diagnóstico ya pertenecen a este trabajo. Aprueba y factura el presupuesto mediante la acción auditada de la tabla.'
        : _jobType == JobType.quotation
            ? 'El modo no se cambia en esta ficha. Aprueba, rechaza, reabre o convierte la cotización mediante las acciones auditadas de la tabla.'
            : 'El modo y la recepción quedan fijos al crear el registro. Las conversiones válidas se realizan mediante acciones auditadas de la tabla.';

    return Tooltip(
      message: explanation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Icon(_jobTypeIcon(_jobType),
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  IconData _jobTypeIcon(JobType type) {
    switch (type) {
      case JobType.service:
        return Icons.pedal_bike_outlined;
      case JobType.warranty:
        return Icons.verified_user_outlined;
      case JobType.quotation:
        return Icons.request_quote_outlined;
      case JobType.itemService:
        return Icons.build_circle_outlined;
      case JobType.sale:
        return Icons.shopping_bag_outlined;
    }
  }

  IconData _getIconDataFromString(String iconName) {
    switch (iconName) {
      case 'build':
        return Icons.build;
      case 'tire_repair':
        return Icons.tire_repair;
      case 'circle':
        return Icons.circle;
      case 'radio_button_unchecked':
        return Icons.radio_button_unchecked;
      case 'settings':
        return Icons.settings;
      case 'link':
        return Icons.link;
      case 'swap_horiz':
        return Icons.swap_horiz;
      case 'stop_circle':
        return Icons.stop_circle;
      case 'pan_tool':
        return Icons.pan_tool;
      case 'cable':
        return Icons.cable;
      case 'arrow_upward':
        return Icons.arrow_upward;
      case 'compress':
        return Icons.compress;
      case 'accessible':
        return Icons.accessible;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'horizontal_rule':
        return Icons.horizontal_rule;
      case 'extension':
        return Icons.extension;
      case 'airline_seat_recline_normal':
        return Icons.airline_seat_recline_normal;
      case 'sports':
        return Icons.sports;
      case 'rectangle':
        return Icons.rectangle;
      default:
        return Icons.build_circle_outlined;
    }
  }

  Widget _buildSubjectPicker() {
    return InkWell(
      onTap: widget.jobId == null ? _showSubjectSearchPicker : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Ítem / Componente (opcional)',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(_jobTypeIcon(_jobType)),
          suffixIcon: widget.jobId == null
              ? const Tooltip(
                  message:
                      'Busca en el catálogo o usa la descripción manual de abajo.',
                  child: Icon(Icons.search),
                )
              : null,
        ),
        child: Text(
          _selectedSubject?.name ?? 'Buscar componente...',
          style: _selectedSubject != null
              ? null
              : TextStyle(color: Colors.grey[600]),
        ),
      ),
    );
  }

  Future<void> _showSubjectSearchPicker() async {
    final result = await showDialog<JobSubject>(
      context: context,
      builder: (context) {
        String search = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableSubjects.where((subject) {
              final term = search.toLowerCase();
              return term.isEmpty ||
                  subject.name.toLowerCase().contains(term) ||
                  subject.category.toLowerCase().contains(term) ||
                  (subject.description?.toLowerCase().contains(term) ?? false);
            }).toList()
              ..sort((a, b) {
                final categoryCompare = a.category.compareTo(b.category);
                if (categoryCompare != 0) return categoryCompare;
                return a.sortOrder.compareTo(b.sortOrder);
              });

            String? lastCategory;

            return Dialog(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 560, maxHeight: 620),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seleccionar componente',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        onChanged: (value) =>
                            setModalState(() => search = value),
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre o categoría...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No se encontraron componentes',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final subject = filtered[index];
                                  final showHeader =
                                      lastCategory != subject.category;
                                  lastCategory = subject.category;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (showHeader) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 10, bottom: 6),
                                          child: Text(
                                            subject.category.toUpperCase(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  letterSpacing: 0.6,
                                                ),
                                          ),
                                        ),
                                      ],
                                      ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        leading: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          foregroundColor: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          child: Icon(
                                            _getIconDataFromString(
                                                subject.icon),
                                            size: 16,
                                          ),
                                        ),
                                        title: Text(subject.name),
                                        subtitle:
                                            subject.description?.isNotEmpty ==
                                                    true
                                                ? Text(subject.description!)
                                                : null,
                                        onTap: () =>
                                            Navigator.of(context).pop(subject),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() => _selectedSubject = result);
    }
  }

  Widget _buildWarrantySection() {
    final theme = Theme.of(context);
    final selectedSource = _selectedWarrantySource;
    final sourceLocked = _isPaymentProtectedCommercialSnapshotLocked ||
        _warrantyClaim?.sourceJobId != null ||
        _warrantySaveCheckpoint.registeredSourceJobId != null;
    final outcome = _warrantyOutcome ?? WarrantyOutcome.pending;
    final outcomeColor = switch (outcome) {
      WarrantyOutcome.covered => const Color(0xFF059669),
      WarrantyOutcome.notCovered => const Color(0xFFDC2626),
      WarrantyOutcome.pending => const Color(0xFFD97706),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Origen de la garantía',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'La decisión de cobertura se cambia desde el chip Estado de la tabla. Si se cubre, los repuestos descuentan inventario y registran costo de garantía sin venta ni IVA.',
              child: Icon(
                Icons.info_outline,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingWarrantySources) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
        if (_warrantySourcesLoadError != null) ...[
          _buildWarrantyLoadError(
            _warrantySourcesLoadError!,
            onRetry: _loadWarrantySourcesForSelectedCustomer,
          ),
          const SizedBox(height: 8),
        ],
        if (_warrantyClaimLoadError != null) ...[
          _buildWarrantyLoadError(
            _warrantyClaimLoadError!,
            onRetry: _retryExistingJobLoad,
          ),
          const SizedBox(height: 8),
        ],
        if (_exactWarrantySourceLoadError != null) ...[
          _buildWarrantyLoadError(
            _exactWarrantySourceLoadError!,
            onRetry: _retryExistingJobLoad,
          ),
          const SizedBox(height: 8),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey('warranty-source-${selectedSource?.jobId ?? 'none'}'),
          initialValue: selectedSource?.jobId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Trabajo original *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.history),
            suffixIcon: sourceLocked
                ? const Tooltip(
                    message:
                        'El vínculo está bloqueado para preservar la trazabilidad.',
                    child: Icon(Icons.lock_outline),
                  )
                : const Tooltip(
                    message:
                        'Selecciona el trabajo cuya reparación está siendo reclamada.',
                    child: Icon(Icons.info_outline),
                  ),
          ),
          items: _warrantySources
              .map((source) => DropdownMenuItem<String>(
                    value: source.jobId,
                    child: Text(
                      _warrantySourceLabel(source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: sourceLocked || _hasBlockingWarrantyLoadFailure
              ? null
              : (jobId) => unawaited(_selectWarrantySource(jobId)),
        ),
        if (_isLoadingWarrantySourceObject) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (_warrantySourceObjectError != null) ...[
          const SizedBox(height: 8),
          Text(
            _warrantySourceObjectError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (selectedSource != null) ...[
          const SizedBox(height: 10),
          _buildWarrantyEligibilityNotice(selectedSource),
        ] else if (_warrantyClaim != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registro histórico sin trabajo original identificado. '
                    'La decisión existente se conserva sin inventar fechas.',
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_warrantyCoverageNeedsFinancialReview &&
            outcome != WarrantyOutcome.covered) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _linkedInvoiceHasActivePayments
                  ? 'La factura tiene pagos vigentes. “Cubierto” queda bloqueado hasta revisar, reversar o reembolsar el pago desde la factura.'
                  : 'No se pudo confirmar el estado de pago. Recarga la ficha antes de elegir “Cubierto”.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message:
                  'Cambiar desde la columna Estado de la tabla de trabajos.',
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: outcomeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: outcomeColor.withValues(alpha: 0.38),
                  ),
                ),
                child: Text(
                  'Cobertura: ${outcome.displayName}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: outcomeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Text(
              'Se cambia desde Estado en la tabla',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (_pendingWarrantyDecision case final pending?) ...[
          const SizedBox(height: 8),
          // Lo que sigue en la bandeja no se muestra como aplicado: la
          // cobertura de arriba es la del servidor.
          WarrantyDecisionPendingNotice(outcome: pending.outcome),
        ],
      ],
    );
  }

  Widget _buildWarrantyLoadError(
    String message, {
    required Future<void> Function() onRetry,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$message Guardar está bloqueado hasta confirmar esta información.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryExistingJobLoad() async {
    if (widget.jobId == null || _isLoading) return;
    setState(() => _isLoading = true);
    await _loadExistingJob();
    if (mounted) setState(() => _isLoading = false);
  }

  String _warrantySourceLabel(MechanicJobServiceWarranty source) {
    final deliveredAt = source.lastDeliveredAt?.toLocal();
    final dateLabel = deliveredAt == null
        ? 'sin fecha'
        : DateFormat('dd/MM/yyyy').format(deliveredAt);
    final warrantyLabel = switch (source.state) {
      ServiceWarrantyState.active => 'vigente ${source.daysRemaining ?? 0}d',
      ServiceWarrantyState.expired => 'vencida',
      ServiceWarrantyState.notStarted => 'sin ventana',
    };
    final classificationLabel =
        source.modeNeedsReview || !source.physicalObject.isValid
            ? ' · clasificar recepción'
            : source.physicalObject.isComponent
                ? ' · componente'
                : ' · bicicleta';
    return '${source.jobNumber ?? 'Trabajo'} · $dateLabel · $warrantyLabel$classificationLabel';
  }

  bool get _hasWarrantySourceScopedDraft {
    if (_bikeTabs.any((tab) => tab.partItems.isNotEmpty)) return true;
    for (final tab in _bikeTabs.where((candidate) => !candidate.isGeneralTab)) {
      if (tab.clientRequestController.text.trim().isNotEmpty ||
          tab.diagnosisController.text.trim().isNotEmpty ||
          tab.workRequestedController.text.trim().isNotEmpty ||
          tab.technicianNotesController.text.trim().isNotEmpty ||
          tab.diagnosisSheet.hasMeaningfulData) {
        return true;
      }
      final bikeId = tab.bike?.id;
      if (bikeId != null && _pendingBikeProfileOverrides.containsKey(bikeId)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _confirmWarrantySourceContextReplacement() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cambiar el trabajo original?'),
        content: const Text(
          'La bicicleta y el diagnóstico ingresado para el trabajo original actual pertenecen a ese objeto y se quitarán. Los productos y servicios se conservarán en General.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Mantener trabajo actual'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cambiar trabajo original'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _selectWarrantySource(String? jobId) async {
    final source = _warrantySources
        .where((candidate) => candidate.jobId == jobId)
        .firstOrNull;
    if (_selectedWarrantySource?.jobId == source?.jobId) return;
    final requiresConfirmation =
        mechanicJobWarrantySourceChangeNeedsConfirmation(
      currentSourceJobId: _selectedWarrantySource?.jobId,
      nextSourceJobId: source?.jobId,
      hasSourceScopedDraft: _hasWarrantySourceScopedDraft,
    );
    if (requiresConfirmation &&
        !await _confirmWarrantySourceContextReplacement()) {
      return;
    }
    if (!mounted) return;

    final selectionEpoch = ++_warrantySourceSelectionEpoch;

    setState(() {
      // Commercial lines survive a source replacement, but diagnosis remains
      // attached to the physical object the user explicitly agreed to remove.
      _moveBikeTabLinesToStandalone();
      _clearSelectedBikeObject(discardPendingProfileEdits: true);
      _selectedSubject = null;
      _subjectNotesController.clear();
      _selectedWarrantySource = source;
      _warrantySourceObjectError = null;
      _isLoadingWarrantySourceObject = source != null;
      _pendingWarrantyRegistrationOperationKey = null;
      _pendingWarrantyDecisionOperationKey = null;
      _pendingWarrantyDecisionFingerprint = null;
    });

    if (source == null) return;

    final object = source.physicalObject;
    if (!object.isValid) {
      setState(() {
        _isLoadingWarrantySourceObject = false;
        _warrantySourceObjectError =
            'El trabajo original no tiene una recepción física única. Clasifícalo primero como bicicleta o componente.';
      });
      return;
    }

    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      Bike? sourceBike;
      JobSubject? sourceSubject;

      if (object.isBike) {
        sourceBike = _findBikeById(object.bikeId);
        sourceBike ??= await bikeshopService.getBikeById(object.bikeId!);
      } else if (object.subjectId != null) {
        sourceSubject = _availableSubjects
            .where((candidate) => candidate.id == object.subjectId)
            .firstOrNull;
        sourceSubject ??=
            await bikeshopService.getJobSubjectById(object.subjectId!);
      }

      if (!mounted ||
          selectionEpoch != _warrantySourceSelectionEpoch ||
          _selectedWarrantySource?.jobId != source.jobId) {
        return;
      }

      if (object.isBike) {
        if (sourceBike == null || sourceBike.customerId != source.customerId) {
          setState(() {
            _isLoadingWarrantySourceObject = false;
            _warrantySourceObjectError =
                'No se pudo cargar la bicicleta exacta del trabajo original.';
          });
          return;
        }

        final warrantyTab = _BikeTabData(bike: sourceBike)
          ..isWarrantyWork = true;
        _hydrateFirstBikeNarrativeFromStandalone(warrantyTab);
        setState(() {
          _bikeTabs
            ..add(warrantyTab)
            ..add(_BikeTabData(
              isGeneralTab: true,
              tabId: 'general_tab',
            ));
          _moveStandaloneLinesToGeneralTab();
          _selectedBike = sourceBike;
          _selectedBikeTabIndex = 0;
          _isLoadingWarrantySourceObject = false;
        });
        unawaited(_loadSelectedBikeProfile(sourceBike));
        return;
      }

      if (object.subjectId != null &&
          (sourceSubject == null || sourceSubject.id != object.subjectId)) {
        setState(() {
          _isLoadingWarrantySourceObject = false;
          _warrantySourceObjectError =
              'No se pudo cargar el componente exacto del trabajo original.';
        });
        return;
      }

      final resolvedSubject = sourceSubject;
      setState(() {
        _selectedSubject = resolvedSubject;
        _subjectNotesController.text = object.subjectNotes ?? '';
        if (resolvedSubject != null &&
            !_availableSubjects
                .any((subject) => subject.id == resolvedSubject.id)) {
          _availableSubjects = [resolvedSubject, ..._availableSubjects];
        }
        _isLoadingWarrantySourceObject = false;
      });
    } catch (error) {
      if (!mounted ||
          selectionEpoch != _warrantySourceSelectionEpoch ||
          _selectedWarrantySource?.jobId != source.jobId) {
        return;
      }
      setState(() {
        _isLoadingWarrantySourceObject = false;
        _warrantySourceObjectError =
            'No se pudo confirmar el objeto del trabajo original. Reintenta antes de guardar.';
      });
      debugPrint('Error loading warranty source object: $error');
    }
  }

  Widget _buildWarrantyEligibilityNotice(
    MechanicJobServiceWarranty source,
  ) {
    final theme = Theme.of(context);
    final isActive = source.state == ServiceWarrantyState.active;
    final color = isActive ? const Color(0xFF059669) : const Color(0xFFB45309);
    final expiry = source.warrantyExpiresAt?.toLocal();
    final text = isActive
        ? 'Dentro del plazo de 14 días${expiry == null ? '' : ' · vence ${DateFormat('dd/MM/yyyy HH:mm').format(expiry)}'}.'
        : source.state == ServiceWarrantyState.expired
            ? 'Fuera del plazo${expiry == null ? '' : ' · venció ${DateFormat('dd/MM/yyyy HH:mm').format(expiry)}'}. Se puede aceptar con justificación.'
            : 'No existe una fecha de entrega confiable. Se puede aceptar con justificación.';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.08),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.verified_outlined : Icons.info_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotationSection() {
    final theme = Theme.of(context);
    final status = _effectiveQuotationStatus;
    final statusColor = switch (status) {
      QuotationStatus.pending => const Color(0xFFD97706),
      QuotationStatus.approved => const Color(0xFF059669),
      QuotationStatus.rejected => const Color(0xFFDC2626),
      QuotationStatus.expired => const Color(0xFF64748B),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.request_quote_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              _proposalDocumentLabel,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'Mientras esté pendiente no crea factura, pago, salida de stock ni asiento contable. El estado se cambia desde el chip Estado de la tabla.',
              child: Icon(
                Icons.info_outline,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message:
                  'Cambiar desde la columna Estado de la tabla de trabajos.',
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.38),
                  ),
                ),
                child: Text(
                  'Estado: ${status.displayName}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isFinalQuotationReadOnly
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _quotationValidUntil ??
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => _quotationValidUntil = date);
                      }
                    },
              icon: const Icon(Icons.event_outlined, size: 17),
              label: Text(
                _quotationValidUntil == null
                    ? 'Sin vencimiento'
                    : 'Vigente hasta ${DateFormat('dd/MM/yyyy').format(_quotationValidUntil!)}',
              ),
            ),
            Tooltip(
              message:
                  'Después de esta fecha, un $_proposalDocumentLabelLower pendiente aparece vencido. Puedes extenderla antes de registrar la decisión del cliente.',
              child: Icon(
                Icons.help_outline,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Quién tiene cada servicio en el taller y su nota vigente (paso G4,
  /// 2026-09-27). Sale de las tareas que el TaskService ya tiene en memoria;
  /// sin tarea no hay franja: «Sin encargar» en cada línea sería ruido en un
  /// taller donde casi ningún trabajo usa tareas (2 de 578 el 2026-09-27).
  Map<String, _LineWork> _lineWorkByItem() {
    final jobId = widget.jobId;
    if (jobId == null) return const {};
    TaskService? taskService;
    try {
      taskService = Provider.of<TaskService>(context);
    } on ProviderNotFoundException {
      return const {};
    }
    final work = <String, _LineWork>{};
    final taskIds = <String>{};
    // Una nota escrita o corregida en el rail sube la versión de su tarea;
    // así se vuelven a leer las notas aunque las tareas sean las mismas.
    final taskVersions = <String>{};
    for (final task in taskService.tasks) {
      final taskId = task.id;
      if (taskId == null ||
          task.linkedJobId != jobId ||
          task.status == TaskStatus.cancelled) {
        continue;
      }
      for (final link in taskService.jobItemsOf(taskId)) {
        if (link.invalidatedAt != null) continue;
        taskIds.add(taskId);
        taskVersions.add('$taskId@${task.version}');
        // Si dos tareas cubren un servicio, manda la que no está terminada.
        final current = work[link.jobItemId];
        if (current != null && current.task.status != TaskStatus.completed) {
          continue;
        }
        final key = task.assigneeKey;
        work[link.jobItemId] = _LineWork(
          taskId: taskId,
          task: task,
          assignee: task.assigneeName ??
              (key == null ? null : _taskAssigneeNames[key]),
          done: link.doneAt != null,
          note: _serviceNotesByItem['$taskId/${link.jobItemId}'],
        );
      }
    }
    if (!setEquals(taskVersions, _serviceNoteTaskVersions)) {
      _serviceNoteTaskVersions = taskVersions;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _refreshServiceNotes(taskService!, taskIds, taskVersions),
      );
    }
    return work;
  }

  Map<String, ServiceNote> _serviceNotesByItem = const {};
  Map<String, _LineWork> _currentLineWork = const {};

  /// Nombre de cada responsable por cuenta o por trabajador, como el panel
  /// de tareas (`get_smart_task_assignment_directory_v1`).
  Map<String, String> _taskAssigneeNames = const {};
  Set<String> _serviceNoteTaskVersions = const {};

  Future<void> _refreshServiceNotes(
    TaskService taskService,
    Set<String> taskIds,
    Set<String> taskVersions,
  ) async {
    final notes = <String, ServiceNote>{};
    var names = _taskAssigneeNames;
    if (taskIds.isNotEmpty && names.isEmpty) {
      try {
        names = {
          for (final principal
              in await taskService.fetchAssignmentDirectory()) ...{
            if (principal.userId != null)
              principal.userId!: principal.displayName,
            if (principal.employeeId != null)
              principal.employeeId!: principal.displayName,
          },
        };
      } catch (error) {
        debugPrint('⚠️ Task assignment directory: $error');
      }
    }
    for (final taskId in taskIds) {
      try {
        final byItem = await taskService.fetchServiceNotes(taskId);
        byItem.forEach((itemId, note) => notes['$taskId/$itemId'] = note);
      } catch (error) {
        debugPrint('⚠️ Service notes of task $taskId: $error');
      }
    }
    // Sólo la lectura de las versiones vigentes pinta: una más vieja que
    // termina después no pisa la nota recién corregida.
    if (!mounted || !setEquals(taskVersions, _serviceNoteTaskVersions)) return;
    setState(() {
      _serviceNotesByItem = notes;
      _taskAssigneeNames = names;
    });
  }

  void _openLineTask(String taskId) {
    try {
      context.read<RightToolbarService>().openConversation(
            tool: ToolbarTool.tasks,
            conversationId: taskId,
          );
    } on ProviderNotFoundException {
      // Sin el rail (una prueba o un host embebido) no hay dónde abrirla.
    }
  }

  Widget _buildPartsSection() {
    final theme = Theme.of(context);
    _currentLineWork = _lineWorkByItem();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (MechanicJobResponsivePolicy.usesCompactComposition(
          ResponsiveViewport.widthOf(context),
        )) {
          return _buildMobilePartsSection(theme);
        }

        // Escritorio: una lista de líneas con columnas alineadas por número
        // (cantidad, precio, total) y sin bordes de celda; cae a desplazamiento
        // horizontal sólo si el panel es más angosto que la fila mínima.
        // 718 px es lo que queda en una ventana de 1248 con menú y panel
        // derecho: la fila completa, con su menú, tiene que caber ahí.
        const minTableWidth = JobLineRow.fixedWidth + 200;
        final tableWidth = constraints.maxWidth > minTableWidth
            ? constraints.maxWidth
            : minTableWidth;
        final scheme = theme.colorScheme;
        final headerStyle = theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: scheme.onSurfaceVariant,
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                    child: Row(
                      children: [
                        const SizedBox(width: JobLineRow.thumbSize + 14),
                        Expanded(
                          child:
                              Text('PRODUCTO / SERVICIO', style: headerStyle),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: JobLineRow.quantityWidth,
                          child: Text('CANT.',
                              style: headerStyle, textAlign: TextAlign.right),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: JobLineRow.priceWidth,
                          child: Text('PRECIO',
                              style: headerStyle, textAlign: TextAlign.right),
                        ),
                        SizedBox(
                          width: JobLineRow.totalWidth,
                          child: Text('TOTAL',
                              style: headerStyle, textAlign: TextAlign.right),
                        ),
                        const SizedBox(width: JobLineRow.menuWidth),
                      ],
                    ),
                  ),
                  ..._buildGroupedPartRows(theme),
                  if (_serviceItems.isNotEmpty)
                    ..._serviceItems
                        .asMap()
                        .entries
                        .map((entry) => _lockFormContent(
                              _buildServiceRow(
                                  theme,
                                  _currentPartItems.length + entry.key + 1,
                                  entry.value,
                                  entry.key),
                              locked: _isCommercialSnapshotLocked,
                            )),
                  if (!_isCommercialSnapshotLocked)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: JobLineRow.thumbSize,
                              height: 48,
                              child: Icon(
                                Icons.add_circle_outline,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: _buildPartAutocompleteField()),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobilePartsSection(ThemeData theme) {
    final itemCount = _currentPartItems.length + _serviceItems.length;

    return Semantics(
      container: true,
      label: 'Editor móvil de productos y servicios',
      child: Column(
        key: const ValueKey('mobile_products_services_editor'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (itemCount == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Aún no hay productos o servicios.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ..._buildGroupedPartRows(theme, mobileLayout: true),
          ..._serviceItems.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _lockFormContent(
                    _buildMobileServiceRow(
                      theme,
                      _currentPartItems.length + entry.key + 1,
                      entry.value,
                      entry.key,
                    ),
                    locked: _isCommercialSnapshotLocked,
                  ),
                ),
              ),
          if (!_isCommercialSnapshotLocked)
            Semantics(
              container: true,
              label: 'Agregar producto o servicio',
              child: Card(
                key: const ValueKey('mobile_products_services_add_card'),
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.24),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildPartAutocompleteField(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPartAutocompleteField() {
    return ProductAutocompleteField(
      key: ValueKey(_partAutocompleteKey),
      focusNode: _partAutocompleteFocus,
      compatibilityContextKey: _partCompatibilityContextKey,
      compatibilityResolver: _partCompatibilityContextKey == null
          ? null
          : _resolveCurrentBikePartCompatibility,
      onProductSelected: (selection) {
        if (selection.isCatalogProduct && selection.product != null) {
          _addCatalogPart(selection.product!);
        } else if (!selection.isCatalogProduct) {
          _addCustomPart(selection.displayText);
        }
      },
      allowCustomItems: true,
      preloadCatalog: false,
      labelText: 'Agregar repuesto o parte',
      hintText: 'Buscar en catálogo o escribir personalizado...',
    );
  }

  Widget _buildPartRow(
    ThemeData theme,
    int index,
    JobPartItem item,
    int itemIndex, {
    bool mobileLayout = false,
    ({int? previous, int? next}) neighbors = (previous: null, next: null),
  }) {
    final previousIndex = neighbors.previous;
    final nextIndex = neighbors.next;
    void swapWith(int? other) {
      if (other == null) return;
      setState(() {
        final temp = _currentPartItems[itemIndex];
        _currentPartItems[itemIndex] = _currentPartItems[other];
        _currentPartItems[other] = temp;
        // La línea elegida para el panel lateral sigue a su línea.
        if (_selectedServiceIndex == itemIndex) {
          _selectedServiceIndex = other;
        } else if (_selectedServiceIndex == other) {
          _selectedServiceIndex = itemIndex;
        }
      });
    }

    return _PartItemRow(
      key: ValueKey('part_${item.id}'),
      item: item,
      availableServiceLocations: _availableServiceLocationsForItem(item),
      partChanges: _partChangesFor(item),
      index: index,
      itemIndex: itemIndex,
      compatibilityContextKey: _partCompatibilityContextKey,
      compatibilityResolver: _partCompatibilityContextKey == null
          ? null
          : _resolveCurrentBikePartCompatibility,
      isFirst: previousIndex == null,
      isLast: nextIndex == null,
      indexWidth: _colIndexWidth,
      quantityWidth: _colQuantityWidth,
      priceWidth: _colPriceWidth,
      totalWidth: _colTotalWidth,
      actionsWidth: _colActionsWidth,
      mobileLayout: mobileLayout,
      configStatus: _lineConfigStatus(item),
      highlighted:
          _selectedServiceIndex == itemIndex || _configuringItemId == item.id,
      configurationPanel:
          mobileLayout ? null : _serviceConfigurationPanelFor(item),
      locked: _isCommercialSnapshotLocked,
      work: _currentLineWork[item.id],
      onOpenTask: _openLineTask,
      assignTargets: _assignTargetsFor(item),
      onChoosePartWheel: (location) => _choosePartWheel(itemIndex, location),
      onChanged: (newItem) {
        // Otro repuesto no hereda el cambio que se confirmó para el anterior.
        final productChanged = newItem.product?.id != item.product?.id;
        if (productChanged) newItem = newItem.copyWith(clearPartChange: true);
        setState(() {
          _currentPartItems[itemIndex] = newItem;
          _syncPendingWizardAnswerCache(newItem);
        });
        if (productChanged && newItem.product != null) {
          unawaited(_loadPartChangeContext(products: [newItem.product]));
        }
      },
      onRemove: () => setState(() {
        final removedId = _currentPartItems[itemIndex].id;
        if (_configuringItemId == removedId) _closeServiceConfiguration();
        _pendingServiceWizardAnswers.remove(removedId);
        _currentPartItems.removeAt(itemIndex);
      }),
      onMoveUp: () => swapWith(previousIndex),
      onMoveDown: () => swapWith(nextIndex),
      onEditWizard: item.isServiceItem &&
              item.product != null &&
              !_isCommercialSnapshotLocked
          ? () => _editServiceWizard(itemIndex)
          : null,
      onTap: () {
        if (item.hasWizardAnswers) {
          setState(() => _selectedServiceIndex = itemIndex);
        }
      },
    );
  }

  /// Qué le falta a un servicio o cómo quedó, con las mismas reglas del
  /// asistente: lo que la ficha ya confirma o la línea ya dice no falta.
  _LineConfigStatus? _lineConfigStatus(JobPartItem item) {
    if (!item.isServiceItem || item.product == null) return null;
    final profile = ServiceWizardService.normalizeProfile(item.wizardProfile);
    if (profile == null || profile.questions.isEmpty) return null;
    final config = _buildServiceWizardDialogConfig(profile, item);
    bool blank(Object? value) =>
        value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is Iterable && value.isEmpty);
    final missing = [
      for (final question in profile.questions)
        // La rueda la muestra su propio chip en la línea.
        if (question.isRequired &&
            question.key != 'which_wheel' &&
            !config.hiddenQuestionKeys.contains(question.key) &&
            blank(config.initialAnswers[question.key]))
          question.label.replaceAll('¿', '').replaceAll('?', '').trim(),
    ];
    if (missing.isNotEmpty) {
      return _LineConfigStatus(
        JobLineChipTone.warning,
        'Falta: ${missing.join(', ')}',
      );
    }
    if (item.hasWizardAnswers) {
      final summary = (item.notes ?? '').trim();
      return _LineConfigStatus(
        JobLineChipTone.success,
        summary.isEmpty ? 'Configurado' : summary,
      );
    }
    return const _LineConfigStatus(
      JobLineChipTone.neutral,
      'Revisar configuración',
    );
  }

  /// «Configurar» de una línea de servicio (paso G3, 2026-09-27): en
  /// escritorio se abre bajo la línea, con las preguntas agrupadas por
  /// destino; en teléfono, en una hoja inferior con el mismo editor. Volver a
  /// pedirlo sobre la línea abierta la cierra.
  Future<void> _editServiceWizard(int itemIndex) async {
    final item = _currentPartItems[itemIndex];
    if (item.product == null) return;
    final compact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    // Cambios sin aplicar: se pregunta antes de perderlos, también al volver
    // a tocar «Configurar» de la misma línea, que cierra el panel.
    if (_configuringItemId != null && _configuringDraft != null) {
      final sameLine = _configuringItemId == item.id;
      final keepEditing = await _confirmUnappliedConfiguration(
        continueLabel:
            sameLine ? 'Descartar y cerrar' : 'Descartar y abrir esta',
      );
      if (!mounted || keepEditing) return;
      // Descartado y cerrado: en escritorio el toque era para cerrar.
      if (sameLine && !compact) return;
    }
    // Un panel abierto en escritorio no sobrevive a la hoja del teléfono:
    // si la ventana se angostó con él abierto, quedaba invisible y este
    // toque lo cerraba en vez de abrir la hoja.
    if (_configuringItemId != null &&
        (compact || _configuringItemId == item.id)) {
      final wasThisLine = _configuringItemId == item.id;
      setState(_closeServiceConfiguration);
      if (!compact && wasThisLine) return;
    }

    // Use cached profile, or re-fetch if missing
    final tabIndex = _selectedBikeTabIndex;
    ServiceWizardProfile? profile = item.wizardProfile;
    profile ??= await _serviceWizardService
        .getProfileForProduct(item.product!.id)
        .catchError((_) => null);
    profile = ServiceWizardService.normalizeProfile(profile);

    // La configuración se arma con la ficha de la bici visible: si mientras
    // se esperaba el perfil se cambió de bici, armarla ahora usaría la ficha
    // de otra y podría subirle sus datos (revisión de Codex, 2026-09-27).
    if (!mounted ||
        _selectedBikeTabIndex != tabIndex ||
        !_currentPartItems.any((line) => line.id == item.id)) {
      return;
    }

    final config = _buildServiceWizardDialogConfig(profile, item);

    if (compact) {
      final result = await showServiceConfigurationSheet(
        context,
        productName: item.product!.name,
        profile: profile,
        initialAnswers: config.initialAnswers,
        contextSummary: config.contextSummary,
        helperText: config.helperText,
        hiddenQuestionKeys: config.hiddenQuestionKeys,
        questionOverrides: config.questionOverrides,
        diagnosisLinkedQuestionKeys: config.diagnosisLinkedQuestionKeys,
        layerOf: _serviceConfigurationLayerOf(profile, config),
        layerCopy: _serviceConfigurationLayerCopy(item),
      );
      if (result == null || !mounted) return;
      final index = _currentPartItems.indexWhere((line) => line.id == item.id);
      if (index >= 0) {
        _applyServiceConfiguration(index, profile, config, result);
      }
      return;
    }

    setState(() {
      _configuringItemId = item.id;
      _configuringProfile = profile;
      _configuringConfig = config;
    });
  }

  void _adoptPersistedLineId(String temporaryId, String persistedId) {
    for (final tab in _bikeTabs) {
      final index = tab.partItems.indexWhere((item) => item.id == temporaryId);
      if (index < 0) continue;
      tab.partItems[index] = tab.partItems[index].withPersistedId(persistedId);
    }
    final standaloneIndex =
        _partItems.indexWhere((item) => item.id == temporaryId);
    if (standaloneIndex >= 0) {
      _partItems[standaloneIndex] =
          _partItems[standaloneIndex].withPersistedId(persistedId);
    }
    final pendingAnswers = _pendingServiceWizardAnswers.remove(temporaryId);
    if (pendingAnswers != null) {
      _pendingServiceWizardAnswers[persistedId] = pendingAnswers;
    }
    if (_configuringItemId == temporaryId) _configuringItemId = persistedId;
  }

  String? _configuringItemId;
  ServiceWizardProfile? _configuringProfile;
  _ServiceWizardDialogConfig? _configuringConfig;

  /// Lo que el operador cambió en el panel y todavía no aplicó.
  Map<String, dynamic>? _configuringDraft;

  void _closeServiceConfiguration() {
    _configuringItemId = null;
    _configuringProfile = null;
    _configuringConfig = null;
    _configuringDraft = null;
  }

  /// true: seguir en la configuración abierta. El panel está en la línea, no
  /// en un diálogo, así que «Guardar», otra línea o cambiar de pestaña ya no
  /// la cierran solos (revisión de Codex, 2026-09-27).
  Future<bool> _confirmUnappliedConfiguration({
    required String continueLabel,
  }) async {
    final line = _bikeTabs
        .expand((tab) => tab.partItems)
        .where((item) => item.id == _configuringItemId)
        .firstOrNull;
    final name = line?.displayName ?? 'este servicio';
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Configuración sin aplicar'),
        content: Text(
          'Cambiaste la configuración de «$name» y no la aplicaste. '
          'Si sigues, esos cambios se pierden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(continueLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Volver a la configuración'),
          ),
        ],
      ),
    );
    if (!mounted) return true;
    if (discard == true) {
      setState(_closeServiceConfiguration);
      return false;
    }
    // Volver es volver a la línea: su bici y su pestaña.
    final tabIndex = _bikeTabs.indexWhere(
      (tab) => tab.partItems.any((item) => item.id == _configuringItemId),
    );
    if (tabIndex >= 0 && tabIndex != _selectedBikeTabIndex) {
      setState(() {
        _selectedBikeTabIndex = tabIndex;
        _selectedBike = _bikeTabs[tabIndex].bike;
      });
      unawaited(_loadSelectedBikeProfile(_selectedBike));
    }
    _selectWorkbenchTab(_JobWorkbenchTab.products);
    return true;
  }

  /// El panel de «Configurar» bajo la línea que lo pidió, o null.
  Widget? _serviceConfigurationPanelFor(JobPartItem item) {
    final config = _configuringConfig;
    if (_configuringItemId != item.id || config == null) return null;
    final profile = _configuringProfile;
    return ServiceConfigurationEditor(
      key: ValueKey('service_configuration_${item.id}'),
      productName: item.product?.name ?? item.displayName,
      profile: profile,
      initialAnswers: _configuringDraft ?? config.initialAnswers,
      onDraftChanged: (draft) => _configuringDraft = draft,
      contextSummary: config.contextSummary,
      helperText: config.helperText,
      hiddenQuestionKeys: config.hiddenQuestionKeys,
      questionOverrides: config.questionOverrides,
      diagnosisLinkedQuestionKeys: config.diagnosisLinkedQuestionKeys,
      layerOf: _serviceConfigurationLayerOf(profile, config),
      layerCopy: _serviceConfigurationLayerCopy(item),
      presentation: ServiceConfigurationPresentation.inline,
      onCancel: () => setState(_closeServiceConfiguration),
      onConfirm: (result) {
        final index =
            _currentPartItems.indexWhere((line) => line.id == item.id);
        setState(_closeServiceConfiguration);
        if (index >= 0) {
          _applyServiceConfiguration(index, profile, config, result);
        }
      },
    );
  }

  /// La capa de cada pregunta sale de su contrato
  /// (`ServiceQuestionContract.destination`); lo que el formulario ya enlaza
  /// al diagnóstico va con el diagnóstico aunque el contrato no lo nombre.
  ServiceConfigurationLayer Function(String) _serviceConfigurationLayerOf(
    ServiceWizardProfile? profile,
    _ServiceWizardDialogConfig config,
  ) {
    return (key) {
      if (config.diagnosisLinkedQuestionKeys.contains(key)) {
        return ServiceConfigurationLayer.diagnosis;
      }
      return switch (serviceQuestionContractFor(
        family: profile?.serviceFamily,
        key: key,
      )?.destination) {
        ServiceQuestionDestination.lineTarget =>
          ServiceConfigurationLayer.target,
        ServiceQuestionDestination.bikeProfile =>
          ServiceConfigurationLayer.bike,
        ServiceQuestionDestination.diagnosis =>
          ServiceConfigurationLayer.diagnosis,
        _ => ServiceConfigurationLayer.service,
      };
    };
  }

  Map<ServiceConfigurationLayer, ServiceConfigurationLayerCopy>
      _serviceConfigurationLayerCopy(JobPartItem item) {
    final bike = _selectedBike?.displayName.trim();
    final where = switch (item.location) {
      BikeMemoryLocation.front => ' · rueda delantera',
      BikeMemoryLocation.rear => ' · rueda trasera',
      _ => '',
    };
    return {
      ServiceConfigurationLayer.bike: ServiceConfigurationLayerCopy(
        bike == null || bike.isEmpty
            ? 'Ficha de la bici$where'
            : 'Ficha de la $bike$where',
        'Lo confirmado no se vuelve a preguntar. Lo que respondas llega a la '
        'ficha al guardar el trabajo; lo que el servicio instala, al '
        'terminarlo.',
      ),
      ServiceConfigurationLayer.diagnosis: ServiceConfigurationLayerCopy(
        'Diagnóstico$where',
        'Es el mismo de la pestaña Diagnóstico, no una copia.',
      ),
      ServiceConfigurationLayer.service: const ServiceConfigurationLayerCopy(
        'De este servicio',
        'Sólo para hacer el trabajo; queda en esta línea.',
      ),
    };
  }

  /// Lo que devuelve «Configurar», venga del panel o de la hoja: la línea,
  /// su diagnóstico y lo que sube a la ficha.
  void _applyServiceConfiguration(
    int itemIndex,
    ServiceWizardProfile? profile,
    _ServiceWizardDialogConfig config,
    ServiceWizardResult result,
  ) {
    final item = _currentPartItems[itemIndex];
    final normalizedAnswers = ServiceWizardService.normalizeAnswersForProfile(
        profile, result.answers);
    final normalizedLocation =
        _resolveWizardLocation(item.location, normalizedAnswers);
    final persistedSummary = _buildPersistedWizardSummary(
      profile,
      normalizedAnswers,
      result.summary,
      hiddenQuestionKeys: config.hiddenQuestionKeys,
    );
    final updatedItem = item.copyWith(
      notes: persistedSummary,
      wizardAnswers: normalizedAnswers.isNotEmpty ? normalizedAnswers : null,
      wizardProfile: profile,
      location: normalizedLocation,
    );
    final promotedBikeProfile = _buildPromotedBikeProfileFromServiceWizard(
      serviceProfile: profile,
      answers: normalizedAnswers,
      location: normalizedLocation,
    );
    final wheelFacts = _positionedServiceFactsFor(
        profile, normalizedLocation, normalizedAnswers);
    final syncFeedback = _serviceWizardSyncFeedback(
      profile,
      updatedItem,
      normalizedAnswers,
    );
    final promotionFeedback = wheelFacts != null
        ? wheelServiceFactsSummary(wheelFacts)
        : promotedBikeProfile == null
            ? null
            : _bikeProfilePromotionFeedback(profile);

    setState(() {
      // Configurar con la ficha vigente cargada es la reconfirmación, cambie
      // o no la ficha: otro pudo haber confirmado ya lo mismo, y entonces no
      // hay nada que promover (revisión de Codex, 2026-09-28).
      final reconfirmedBikeId = _currentBikeTab?.bike?.id;
      if (reconfirmedBikeId != null &&
          !_isLoadingSelectedBikeProfile &&
          !_selectedBikeProfileLoadFailed) {
        _bikeFactsAwaitingReconfirmation.remove(reconfirmedBikeId);
      }
      _currentPartItems[itemIndex] = updatedItem;
      _syncPendingWizardAnswerCache(updatedItem);
      _applyWizardAnswersToDiagnosis(
        item: updatedItem,
        profile: profile,
        answers: normalizedAnswers,
      );
      if (promotedBikeProfile != null) {
        final bikeId = promotedBikeProfile.bikeId;
        if (!_pendingBikeProfileOverrides.containsKey(bikeId)) {
          _pendingBikeProfileBaselines[bikeId] =
              _selectedBike?.id == bikeId ? _selectedBikeProfile : null;
        }
        _pendingBikeProfileOverrides[bikeId] = promotedBikeProfile;
        _pendingBikeProfileOperationKeys[bikeId] = const Uuid().v4();
        if (_selectedBike?.id == bikeId) {
          _selectedBikeProfile = promotedBikeProfile;
        }
      }
      _selectedServiceIndex = itemIndex;
    });

    final feedbackParts = <String>[
      if (syncFeedback != null) syncFeedback,
      if (promotionFeedback != null) promotionFeedback,
    ];

    if (feedbackParts.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(feedbackParts.join(' '))),
      );
    }
  }

  // ignore: unused_element
  Widget _buildLaborSection() {
    final theme = Theme.of(context);

    // If on mobile, show mobile layout (cards)
    // We can detect mobile by screen width context
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mano de Obra',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_serviceItems.isNotEmpty)
            ..._serviceItems.asMap().entries.map((entry) =>
                _buildMobileServiceRow(
                    theme, entry.key + 1, entry.value, entry.key)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addServiceItem,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Mano de Obra'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mano de Obra',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Responsive grid table (same as parts)
            LayoutBuilder(
              builder: (context, constraints) {
                const minTableWidth = 900.0;
                final tableWidth = constraints.maxWidth > minTableWidth
                    ? constraints.maxWidth
                    : minTableWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Table header
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8)),
                            ),
                            child: Row(
                              children: [
                                // # column
                                Container(
                                  width: _colIndexWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('#',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Descripción column (flex)
                                Expanded(
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 250),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2)),
                                      ),
                                    ),
                                    child: Text(
                                      'DESCRIPCIÓN',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),

                                // Fecha column
                                Container(
                                  width: _colDateWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('FECHA',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Horas column
                                Container(
                                  width: _colHoursWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('HORAS',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Tarifa column
                                Container(
                                  width: _colRateWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('TARIFA/H',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Total column
                                Container(
                                  width: _colTotalWidth,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Text('TOTAL',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.right),
                                ),

                                // Actions column
                                const SizedBox(width: _colActionsWidth),
                              ],
                            ),
                          ),

                          // Header/Content divider
                          Divider(
                              height: 1,
                              thickness: 1,
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.2)),

                          // Labor items
                          Column(
                            children: [
                              // Existing labor items
                              if (_serviceItems.isNotEmpty)
                                ..._serviceItems.asMap().entries.map((entry) =>
                                    _buildServiceRow(theme, entry.key + 1,
                                        entry.value, entry.key)),

                              // Add labor button row (always show)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: _serviceItems.isNotEmpty
                                        ? BorderSide(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2))
                                        : BorderSide.none,
                                  ),
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Empty # column
                                      Container(
                                        width: _colIndexWidth,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                                color: theme.colorScheme.outline
                                                    .withValues(alpha: 0.2)),
                                          ),
                                        ),
                                      ),

                                      // Add labor button spanning remaining columns
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          child: FilledButton.icon(
                                            onPressed: _addServiceItem,
                                            icon:
                                                const Icon(Icons.add, size: 18),
                                            label: const Text(
                                                'Agregar Mano de Obra'),
                                            style: FilledButton.styleFrom(
                                              alignment: Alignment.centerLeft,
                                            ),
                                          ),
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a service/labor row using the universal LineRowWrapper.
  /// Provides hover-based reorder arrows and consistent styling.
  Widget _buildMobileServiceRow(
      ThemeData theme, int index, _JobServiceItem item, int itemIndex) {
    final canMoveUp = itemIndex > 0;
    final canMoveDown = itemIndex < _serviceItems.length - 1;
    final lineLabel = item.displayName.trim().isEmpty
        ? 'Servicio sin nombre'
        : item.displayName;

    return Semantics(
      key: ValueKey('mobile_service_semantics_${item.id}'),
      container: true,
      label: 'Línea $index, $lineLabel',
      child: Card(
        key: ValueKey('mobile_service_card_${item.id}'),
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$index',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mano de obra',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('mobile_service_move_up_${item.id}'),
                    onPressed: canMoveUp
                        ? () => _moveServiceItem(itemIndex, itemIndex - 1)
                        : null,
                    tooltip: 'Mover hacia arriba',
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    key: ValueKey('mobile_service_move_down_${item.id}'),
                    onPressed: canMoveDown
                        ? () => _moveServiceItem(itemIndex, itemIndex + 1)
                        : null,
                    tooltip: 'Mover hacia abajo',
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  IconButton(
                    key: ValueKey('mobile_service_delete_${item.id}'),
                    onPressed: () => _removeServiceItem(itemIndex),
                    tooltip: 'Eliminar servicio',
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('mobile_service_description_${item.id}'),
                initialValue: item.description,
                decoration: InputDecoration(
                  labelText: item.serviceProduct == null
                      ? 'Nombre del servicio'
                      : 'Detalle del servicio',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) {
                  _updateServiceItem(
                    itemIndex,
                    item.copyWith(description: value),
                  );
                },
              ),
              if (item.serviceProduct != null) ...[
                const SizedBox(height: 6),
                Text(
                  item.serviceProduct!.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('mobile_service_quantity_${item.id}'),
                      initialValue: item.hours % 1 == 0
                          ? item.hours.toStringAsFixed(0)
                          : item.hours.toStringAsFixed(2),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Horas',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (value) {
                        _updateServiceItem(
                          itemIndex,
                          item.copyWith(
                            hours: double.tryParse(value) ?? 0,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('mobile_service_price_${item.id}'),
                      initialValue: item.hourlyRate.toStringAsFixed(0),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio unit.',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (value) {
                        _updateServiceItem(
                          itemIndex,
                          item.copyWith(
                            hourlyRate: double.tryParse(value) ?? 0,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    Text(
                      'Total',
                      style: theme.textTheme.labelLarge,
                    ),
                    const Spacer(),
                    Semantics(
                      key: ValueKey('mobile_service_total_${item.id}'),
                      label: 'Total del servicio',
                      value: NumberFormat.currency(
                        symbol: '\$',
                        decimalDigits: 0,
                      ).format(item.total),
                      child: Text(
                        NumberFormat.currency(
                          symbol: '\$',
                          decimalDigits: 0,
                        ).format(item.total),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _moveServiceItem(int fromIndex, int toIndex) {
    if (fromIndex < 0 ||
        fromIndex >= _serviceItems.length ||
        toIndex < 0 ||
        toIndex >= _serviceItems.length) {
      return;
    }
    setState(() {
      final item = _serviceItems.removeAt(fromIndex);
      _serviceItems.insert(toIndex, item);
    });
  }

  void _removeServiceItem(int itemIndex) {
    if (itemIndex < 0 || itemIndex >= _serviceItems.length) return;
    setState(() => _serviceItems.removeAt(itemIndex));
  }

  void _updateServiceItem(int itemIndex, _JobServiceItem item) {
    if (itemIndex < 0 || itemIndex >= _serviceItems.length) return;
    setState(() => _serviceItems[itemIndex] = item);
  }

  Widget _buildServiceRow(
      ThemeData theme, int index, _JobServiceItem item, int itemIndex) {
    return LineRowWrapper(
      key: ValueKey('service_${item.id}'),
      index: index,
      canMoveUp: itemIndex > 0,
      canMoveDown: itemIndex < _serviceItems.length - 1,
      onMoveUp: () {
        if (itemIndex > 0) {
          _moveServiceItem(itemIndex, itemIndex - 1);
        }
      },
      onMoveDown: () {
        if (itemIndex < _serviceItems.length - 1) {
          _moveServiceItem(itemIndex, itemIndex + 1);
        }
      },
      onRemove: () => _removeServiceItem(itemIndex),
      canEdit: true,
      indexColumnWidth: _colIndexWidth,
      actionsColumnWidth: _colActionsWidth,
      columns: [
        // Description column
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service icon/image
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: item.serviceProduct?.imageUrl != null
                      ? Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.network(
                            item.serviceProduct!.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.work_outline,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.work_outline,
                          color: Colors.blue,
                          size: 24,
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // Service name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Custom description only
                    if (item.hasCustomDescription)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          item.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Quantity column (represents hours for services)
        LineColumn(
          width: _colQuantityWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Center(
            child: Text(
              item.hours % 1 == 0
                  ? item.hours.toStringAsFixed(0)
                  : item.hours.toStringAsFixed(2),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),

        // Unit Price column - EDITABLE
        LineColumn(
          width: _colPriceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextFormField(
            initialValue: item.hourlyRate.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3)),
              ),
              prefixText: '\$ ',
              prefixStyle: theme.textTheme.bodyMedium,
            ),
            onChanged: (value) {
              final newPrice = double.tryParse(value) ?? 0;
              _updateServiceItem(
                itemIndex,
                item.copyWith(hourlyRate: newPrice),
              );
            },
          ),
        ),

        // Total column (no right border - last content column)
        LineColumn(
          width: _colTotalWidth,
          showRightBorder: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                .format(item.total),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCostSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCostRow('Subtotal:', _subtotal, true),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Descuento:', style: TextStyle(fontSize: 16)),
            SizedBox(
              width: 150,
              child: TextFormField(
                controller: _discountController,
                focusNode: _discountFocusNode,
                enabled: !_isCommercialSnapshotLocked,
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  final discount = double.tryParse(value ?? '') ?? 0;
                  if (discount < 0 || discount > _subtotal) {
                    return 'Máximo: ${NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(_subtotal)}';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(thickness: 2),
        _buildCostRow('TOTAL:', _total, true, fontSize: 20),
      ],
    );
  }

  Widget _buildCostRow(String label, double amount, bool bold,
      {double fontSize = 16}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(amount),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: bold ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    );
  }

  /// The currently selected service item (for sidebar detail)
  JobPartItem? get _selectedServiceItem {
    if (_selectedServiceIndex == null) return null;
    if (_selectedServiceIndex! < 0 ||
        _selectedServiceIndex! >= _currentPartItems.length) {
      return null;
    }
    final item = _currentPartItems[_selectedServiceIndex!];
    return item.hasWizardAnswers ? item : null;
  }

  Widget _buildServiceDetailsPanel() {
    final theme = Theme.of(context);
    final item = _selectedServiceItem;
    if (item == null) return const SizedBox.shrink();
    return _buildServiceDetailCard(theme, item);
  }

  Widget _buildServiceDetailCard(ThemeData theme, JobPartItem item) {
    final profile = ServiceWizardService.normalizeProfile(item.wizardProfile);
    final answers = ServiceWizardService.normalizeAnswersForProfile(
      profile,
      Map<String, dynamic>.from(
          item.wizardAnswers ?? const <String, dynamic>{}),
    );
    final questions = profile?.questions ?? [];
    final itemIndex = _currentPartItems.indexOf(item);

    // Build answer key→value pairs
    final answerPairs = <MapEntry<String, String>>[];
    for (final q in questions) {
      final val = answers[q.key];
      if (val == null || val.toString().isEmpty) continue;
      if (q.key == '_notes') continue;

      String displayValue;
      if (val is bool) {
        displayValue = val ? 'Sí' : 'No';
      } else if (val is List) {
        if (val.isEmpty) continue;
        displayValue = val.map((v) {
          return ServiceWizardService.resolveLabel(q, v.toString());
        }).join(', ');
      } else {
        displayValue = ServiceWizardService.resolveLabel(q, val.toString());
      }
      answerPairs.add(MapEntry(q.label, displayValue));
    }

    final notes = answers['_notes'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: service name + edit button
        Row(
          children: [
            Icon(
              Icons.build_circle,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (itemIndex >= 0)
              Tooltip(
                message: 'Editar configuración',
                child: InkWell(
                  onTap: () => _editServiceWizard(itemIndex),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Answer details
        if (answerPairs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: answerPairs.map((pair) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          pair.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          pair.value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        // Notes
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 13,
                color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInvoiceSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt, color: Colors.green[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Factura: ${_linkedInvoiceNumber ?? _existingJob?.invoiceId ?? "N/A"}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Estado: Factura creada automáticamente con los repuestos y servicios de este trabajo',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  if (_existingJob?.invoiceId != null) {
                    context.push(
                        '/sales/invoices/${_existingJob!.invoiceId}/edit?referrer=job&jobId=${_existingJob!.id}');
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ver Factura'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
              ),
              if (_existingJob?.isPaid != true)
                OutlinedButton.icon(
                  onPressed: () {
                    final invoiceId = _existingJob?.invoiceId;
                    if (invoiceId != null) {
                      context.push('/sales/invoices/$invoiceId/payment');
                    }
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Registrar pago'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Helper classes for form items

class _PartItemRow extends StatefulWidget {
  final JobPartItem item;
  final Set<BikeMemoryLocation> availableServiceLocations;

  /// Los cambios de ficha que propone un repuesto con ficha técnica (un rotor
  /// de 180 atrás; una maza trasera, su driver y su anclaje): la línea pide
  /// la rueda y los dice, uno por chip.
  final List<PartBikeFactChange> partChanges;

  /// Elegir la rueda de ese repuesto, o volver a elegirla, confirma el
  /// cambio.
  final ValueChanged<BikeMemoryLocation>? onChoosePartWheel;
  final int index;
  final int itemIndex;
  final Future<Map<String, ProductCompatibilityAssessment>> Function(
      List<Product> products)? compatibilityResolver;
  final Object? compatibilityContextKey;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<JobPartItem> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onEditWizard;
  final VoidCallback? onTap;
  final double indexWidth;
  final double quantityWidth;
  final double priceWidth;
  final double totalWidth;
  final double actionsWidth;
  final bool mobileLayout;

  /// Cómo quedó la configuración del servicio, o qué le falta.
  final _LineConfigStatus? configStatus;

  /// La línea está abierta en el detalle del servicio.
  final bool highlighted;

  /// «Configurar» abierto bajo la línea (escritorio).
  final Widget? configurationPanel;

  /// La factura ya tiene pagos (o la propuesta es final): la línea se lee
  /// entera, pero no cambia la venta.
  final bool locked;

  /// La tarea que cubre este servicio en el taller, si hay una.
  final _LineWork? work;
  final ValueChanged<String>? onOpenTask;

  /// «Asignar a <bici>»: en General de un trabajo con varias bicis, una por
  /// bici. Sin acción ([onSelected] nula) mientras la línea está en
  /// «Configurar».
  final List<({String label, VoidCallback? onSelected})> assignTargets;

  const _PartItemRow({
    super.key,
    required this.item,
    this.availableServiceLocations = const {
      BikeMemoryLocation.none,
      BikeMemoryLocation.front,
      BikeMemoryLocation.rear,
    },
    this.partChanges = const [],
    this.onChoosePartWheel,
    required this.index,
    required this.itemIndex,
    this.compatibilityResolver,
    this.compatibilityContextKey,
    required this.isFirst,
    required this.isLast,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    this.onEditWizard,
    this.onTap,
    required this.indexWidth,
    required this.quantityWidth,
    required this.priceWidth,
    required this.totalWidth,
    required this.actionsWidth,
    this.mobileLayout = false,
    this.configStatus,
    this.highlighted = false,
    this.configurationPanel,
    this.locked = false,
    this.work,
    this.onOpenTask,
    this.assignTargets = const [],
  });

  @override
  State<_PartItemRow> createState() => _PartItemRowState();
}

class _PartItemRowState extends State<_PartItemRow> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.displayName);
  }

  @override
  void didUpdateWidget(_PartItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.product != oldWidget.item.product ||
        (widget.item.product == null &&
            widget.item.name != oldWidget.item.name &&
            widget.item.name != _nameController.text)) {
      _nameController.text = widget.item.displayName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    if (widget.mobileLayout) {
      return _buildMobileCard(theme, item);
    }

    return _buildDesktopRow(theme, item);
  }

  Widget _buildDesktopRow(ThemeData theme, JobPartItem item) {
    return JobLineRow(
      thumb: _buildLineThumb(theme, item),
      body: _buildProductEditor(item, mobileLayout: false),
      quantity: _buildQuantityField(theme, item, mobileLayout: false),
      price: _buildPriceField(theme, item, mobileLayout: false),
      total: _buildTotalText(theme, item),
      actions: _lineActions(item, mobileLayout: false),
      semanticLabel: 'Línea ${widget.index}, ${_lineLabel(item)}',
      highlighted: widget.highlighted,
      onTap: widget.onTap,
      expandedChild: widget.configurationPanel,
    );
  }

  Widget _buildMobileCard(ThemeData theme, JobPartItem item) {
    return JobLineRow(
      key: ValueKey('mobile_part_semantics_${item.id}'),
      cardKey: ValueKey('mobile_part_card_${item.id}'),
      mobileLayout: true,
      thumb: _buildLineThumb(theme, item),
      body: _buildProductEditor(item, mobileLayout: true),
      quantity: _buildQuantityField(theme, item, mobileLayout: true),
      price: _buildPriceField(theme, item, mobileLayout: true),
      total: Semantics(
        key: ValueKey('mobile_part_total_${item.id}'),
        label: 'Total de la línea',
        value: _formattedTotal(item),
        excludeSemantics: true,
        child: _buildTotalText(theme, item, mobileLayout: true),
      ),
      actions: _lineActions(item, mobileLayout: true),
      semanticLabel: 'Línea ${widget.index}, ${_lineLabel(item)}',
      highlighted: widget.highlighted,
      onTap: widget.onTap,
    );
  }

  bool _editingDescription = false;

  String _lineLabel(JobPartItem item) => item.displayName.trim().isEmpty
      ? (item.isServiceItem ? 'Servicio sin nombre' : 'Producto sin nombre')
      : item.displayName;

  bool _hasLineIdentity(JobPartItem item) =>
      item.product != null || item.name.trim().isNotEmpty;

  /// La descripción del operador. En un servicio configurado `notes` guarda
  /// el resumen del asistente, que se ve como chip y no se edita a mano.
  bool _ownsDescription(JobPartItem item) => !item.hasWizardAnswers;

  Widget _buildLineThumb(ThemeData theme, JobPartItem item) {
    final scheme = theme.colorScheme;
    final imageUrl = item.product?.imageUrl;
    if (!item.isServiceItem && imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(4),
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: item.isServiceItem
            ? scheme.primaryContainer.withValues(alpha: 0.6)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        item.isServiceItem
            ? Icons.handyman_outlined
            : Icons.inventory_2_outlined,
        size: 20,
        color: item.isServiceItem ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }

  String _locationLabel(BikeMemoryLocation location) => switch (location) {
        BikeMemoryLocation.front => 'Delantero',
        BikeMemoryLocation.rear => 'Trasero',
        _ => 'Sin fijar lado',
      };

  String _lineMeta(JobPartItem item) {
    final sku = item.sku;
    final parts = <String>[
      if (item.isServiceItem)
        'Servicio'
      else if (item.product != null)
        'Repuesto'
      else
        'Artículo sin catálogo',
      if (sku != null && sku.isNotEmpty) sku,
      if (item.product?.isSet == true) 'Juego completo',
      if (item.product?.isSetComponent == true) 'Pieza de juego',
    ];
    return parts.join(' · ');
  }

  List<JobLineAction> _lineActions(
    JobPartItem item, {
    required bool mobileLayout,
  }) {
    final prefix = mobileLayout ? 'mobile_part' : 'desktop_part';
    if (widget.locked) return const [];
    return [
      if (item.isServiceItem && widget.onEditWizard != null)
        JobLineAction(
          key: ValueKey('${prefix}_action_configure_${item.id}'),
          icon: Icons.tune,
          label: 'Configurar servicio',
          onSelected: widget.onEditWizard,
        ),
      if (_hasLineIdentity(item) && _ownsDescription(item))
        JobLineAction(
          key: ValueKey('${prefix}_action_description_${item.id}'),
          icon: Icons.notes_outlined,
          label: (item.notes ?? '').trim().isEmpty
              ? 'Agregar descripción'
              : 'Editar descripción',
          onSelected: () => setState(() => _editingDescription = true),
        ),
      if (_hasLineIdentity(item))
        JobLineAction(
          key: ValueKey('${prefix}_action_replace_${item.id}'),
          icon: Icons.swap_horiz,
          label: item.isServiceItem
              ? 'Cambiar por otro servicio'
              : 'Cambiar por otro artículo',
          onSelected: () => _handleProductChanged(item, null),
        ),
      for (final (index, target) in widget.assignTargets.indexed)
        JobLineAction(
          key: ValueKey('${prefix}_assign_bike_${item.id}_$index'),
          icon: Icons.pedal_bike_outlined,
          label: target.label,
          onSelected: target.onSelected,
          startsGroup: index == 0,
        ),
      JobLineAction(
        key: ValueKey('${prefix}_move_up_${item.id}'),
        icon: Icons.arrow_upward,
        label: 'Subir',
        onSelected: widget.isFirst ? null : widget.onMoveUp,
        startsGroup: true,
      ),
      JobLineAction(
        key: ValueKey('${prefix}_move_down_${item.id}'),
        icon: Icons.arrow_downward,
        label: 'Bajar',
        onSelected: widget.isLast ? null : widget.onMoveDown,
      ),
      JobLineAction(
        key: ValueKey('${prefix}_delete_${item.id}'),
        icon: Icons.delete_outline,
        label: 'Quitar del trabajo',
        onSelected: widget.onRemove,
        danger: true,
        startsGroup: true,
      ),
    ];
  }

  Widget _buildProductEditor(
    JobPartItem item, {
    required bool mobileLayout,
  }) {
    // Sin producto ni nombre, la línea es el buscador del catálogo.
    if (!_hasLineIdentity(item)) {
      return SmartProductField(
        key: ValueKey(
          '${mobileLayout ? 'mobile' : 'desktop'}_part_product_${item.id}',
        ),
        productNameController: _nameController,
        initialData: ProductFieldData(
          product: item.product,
          productName: item.displayName,
          productSku: item.product?.sku,
          isCatalogProduct: item.isCatalogProduct,
          description: item.hasWizardAnswers ? null : item.notes,
        ),
        compatibilityContextKey: widget.compatibilityContextKey,
        compatibilityResolver: widget.compatibilityResolver,
        hintText: 'Buscar por nombre...',
        allowCustomItems: true,
        showCost: false,
        onProductChanged: (selection) {
          _handleProductChanged(item, selection);
        },
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = (item.notes ?? '').trim();
    final configStatus = widget.configStatus;
    final orderedLocations = const [
      BikeMemoryLocation.none,
      BikeMemoryLocation.front,
      BikeMemoryLocation.rear,
    ].where(widget.availableServiceLocations.contains).toList();
    final chipMinHeight = mobileLayout ? 48.0 : 0.0;
    final chipVisibleHeight = mobileLayout ? 40.0 : 26.0;

    Widget touchable(Widget child) => mobileLayout
        ? ConstrainedBox(
            constraints: BoxConstraints(minHeight: chipMinHeight),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: child,
            ),
          )
        : child;

    // Un repuesto que cambia la ficha pide su rueda como un servicio.
    final partChanges = widget.partChanges;
    final choosesWheel = item.isServiceItem || partChanges.isNotEmpty;
    // Dos datos que no calzan por lo mismo (una maza que no se raya en la
    // rueda) se dicen una vez.
    final shownLabels = <String>{};
    final chips = <Widget>[
      if (choosesWheel &&
          widget.locked &&
          item.location != BikeMemoryLocation.none)
        JobLineChip(
          icon: Icons.place_outlined,
          label: _locationLabel(item.location),
          tone: JobLineChipTone.info,
        ),
      if (choosesWheel && orderedLocations.length > 1 && !widget.locked)
        touchable(
          PopupMenuButton<BikeMemoryLocation>(
            key: ValueKey(
              '${mobileLayout ? 'mobile' : 'desktop'}_part_location_${item.id}',
            ),
            tooltip: 'Rueda o lado de la bici',
            onSelected: (location) {
              final choosePartWheel = widget.onChoosePartWheel;
              if (partChanges.isNotEmpty && choosePartWheel != null) {
                choosePartWheel(location);
              } else if (location != item.location) {
                widget.onChanged(item.copyWith(location: location));
              }
            },
            itemBuilder: (context) => [
              for (final location in orderedLocations)
                CheckedPopupMenuItem<BikeMemoryLocation>(
                  value: location,
                  checked: location == item.location,
                  child: Text(_locationLabel(location)),
                ),
            ],
            child: JobLineChip(
              icon: Icons.place_outlined,
              label: _locationLabel(item.location),
              trailingIcon: Icons.expand_more,
              minHeight: chipVisibleHeight,
              tone: item.location == BikeMemoryLocation.none
                  ? JobLineChipTone.warning
                  : JobLineChipTone.info,
            ),
          ),
        ),
      // Lo que el repuesto le hace a la ficha de la bici al terminar.
      for (final (changeIndex, partChange) in partChanges.indexed)
        if (!(widget.locked &&
                (partChange.status == PartBikeFactChangeStatus.chooseWheel ||
                    partChange.status == PartBikeFactChangeStatus.chooseBike ||
                    partChange.status ==
                        PartBikeFactChangeStatus.unconfirmed)) &&
            shownLabels.add(partChange.label))
          touchable(
            JobLineChip(
              key: ValueKey(
                '${mobileLayout ? 'mobile' : 'desktop'}_part_change_${item.id}'
                '${changeIndex == 0 ? '' : '_${partChange.link?.bikeFactKey ?? changeIndex}'}',
              ),
              icon: switch (partChange.status) {
                PartBikeFactChangeStatus.change => Icons.sync_alt,
                PartBikeFactChangeStatus.confirms ||
                PartBikeFactChangeStatus.fits =>
                  Icons.check_circle_outline,
                PartBikeFactChangeStatus.incompatible => Icons.error_outline,
                PartBikeFactChangeStatus.caution => Icons.report_outlined,
                PartBikeFactChangeStatus.pending => Icons.pending_outlined,
                PartBikeFactChangeStatus.chooseBike =>
                  Icons.pedal_bike_outlined,
                PartBikeFactChangeStatus.chooseWheel =>
                  partChange.onlyPosition == null
                      ? Icons.place_outlined
                      : Icons.touch_app_outlined,
                PartBikeFactChangeStatus.unconfirmed =>
                  Icons.touch_app_outlined,
              },
              label: partChange.label,
              tone: switch (partChange.status) {
                PartBikeFactChangeStatus.change => JobLineChipTone.info,
                PartBikeFactChangeStatus.confirms ||
                PartBikeFactChangeStatus.fits =>
                  JobLineChipTone.success,
                PartBikeFactChangeStatus.incompatible ||
                PartBikeFactChangeStatus.caution ||
                PartBikeFactChangeStatus.pending ||
                PartBikeFactChangeStatus.chooseBike ||
                PartBikeFactChangeStatus.chooseWheel =>
                  JobLineChipTone.warning,
                PartBikeFactChangeStatus.unconfirmed => JobLineChipTone.neutral,
              },
              maxLines: mobileLayout ? 3 : 2,
              minHeight: chipVisibleHeight,
              tooltip: partChange.tooltip,
              // Tocarlo confirma el cambio en la rueda que ya dice la línea, o
              // elige la única rueda en que va la pieza (un cassette, atrás).
              onTap: widget.locked || widget.onChoosePartWheel == null
                  ? null
                  : switch (partChange.status) {
                      PartBikeFactChangeStatus.unconfirmed => () =>
                          widget.onChoosePartWheel!(item.location),
                      PartBikeFactChangeStatus.chooseWheel
                          when partChange.onlyPosition != null =>
                        () =>
                            widget.onChoosePartWheel!(partChange.onlyPosition!),
                      _ => null,
                    },
            ),
          ),
      // Una línea protegida no se configura: lo que falta ya no es una tarea,
      // y sólo queda el resumen de lo que se configuró.
      if (configStatus != null &&
          (!widget.locked || configStatus.tone == JobLineChipTone.success))
        touchable(
          JobLineChip(
            key: ValueKey(
              '${mobileLayout ? 'mobile' : 'desktop'}_part_configure_${item.id}',
            ),
            icon: switch (configStatus.tone) {
              JobLineChipTone.warning => Icons.error_outline,
              JobLineChipTone.success => Icons.check_circle_outline,
              _ => Icons.tune,
            },
            label: configStatus.label,
            tone: configStatus.tone,
            maxLines: mobileLayout ? 3 : 2,
            minHeight: chipVisibleHeight,
            onTap: widget.onEditWizard,
            tooltip: widget.onEditWizard == null ? null : 'Configurar servicio',
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _lineLabel(item),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _lineMeta(item),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        // Una línea protegida se lee entera y no se edita, ni su descripción.
        if (_ownsDescription(item) && _editingDescription && !widget.locked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextFormField(
              key: ValueKey(
                '${mobileLayout ? 'mobile' : 'desktop'}_part_description_${item.id}',
              ),
              initialValue: item.notes ?? '',
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              style: theme.textTheme.bodyMedium,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Descripción de la línea',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  widget.onChanged(item.copyWith(notes: value)),
              onTapOutside: (_) => setState(() => _editingDescription = false),
              onFieldSubmitted: (_) =>
                  setState(() => _editingDescription = false),
            ),
          )
        else if (_ownsDescription(item) && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: widget.locked
                  ? null
                  : () => setState(() => _editingDescription = true),
              child: Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        // Con «Configurar» abierto, el panel ya dice la rueda y lo que falta.
        if (chips.isNotEmpty && widget.configurationPanel == null) ...[
          const SizedBox(height: 8),
          // En teléfono cada chip ya trae su margen de toque de 48.
          Wrap(spacing: 6, runSpacing: mobileLayout ? 0 : 6, children: chips),
        ],
        // Primero cómo quedó configurado; después quién lo hace en el taller.
        if (widget.work != null) ...[
          const SizedBox(height: 8),
          _buildWorkLine(theme, widget.work!),
        ],
      ],
    );
  }

  /// La franja del taller: quién lo tiene y cómo va, y la nota vigente del
  /// servicio con cuántas lleva el hilo. Tocarla abre la tarea en el rail.
  Widget _buildWorkLine(ThemeData theme, _LineWork work) {
    final scheme = theme.colorScheme;
    final ok =
        VinabikeThemeRoles.maybeOf(context)?.success.accent ?? scheme.primary;
    final muted = scheme.onSurfaceVariant;
    // Las palabras del panel de tareas; «Hecho» es de este servicio.
    final state = work.done
        ? 'Hecho'
        : work.task.awaitsAcknowledgement
            ? 'Por aceptar'
            : switch (work.task.status) {
                TaskStatus.inProgress => 'En curso',
                TaskStatus.blocked => 'Bloqueada',
                TaskStatus.completed => 'Completada',
                _ => 'Pendiente',
              };
    final who = work.assignee?.trim();
    final note = work.note;
    final count = note == null
        ? null
        : (note.count == 1 ? '1 nota' : '${note.count} notas');
    final label = [
      'Tarea: $state${who == null || who.isEmpty ? '' : ', $who'}',
      if (note != null) 'Nota: ${note.body}, $count',
    ].join('. ');
    return Semantics(
      button: widget.onOpenTask != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('part_work_${widget.item.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onOpenTask == null
            ? null
            : () => widget.onOpenTask!(work.taskId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    work.done ? Icons.check_circle_outline : Icons.schedule,
                    size: 15,
                    color: work.done ? ok : muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: work.done ? ok : scheme.onSurface,
                    ),
                  ),
                  if (who != null && who.isNotEmpty)
                    Flexible(
                      child: Text(
                        ' · $who',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.sticky_note_2_outlined, size: 15, color: muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        note.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      ' · $count',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleProductChanged(
    JobPartItem item,
    ProductFieldSelection? selection,
  ) {
    if (selection == null) {
      widget.onChanged(item.copyWith(
        clearProduct: true,
        clearWizard: true,
        name: '',
        isCatalogProduct: true,
        isServiceItem: false,
        location: BikeMemoryLocation.none,
        notes: '',
      ));
      return;
    }

    if (selection.isCatalogProduct && selection.product != null) {
      final isSameProduct = item.product?.id == selection.product!.id;
      final isServiceItem = selection.product!.isService;

      widget.onChanged(item.copyWith(
        product: selection.product,
        name: selection.productName ?? '',
        isCatalogProduct: true,
        isServiceItem: isServiceItem,
        unitPrice: selection.price > 0 ? selection.price : item.unitPrice,
        notes: selection.description ?? '',
        clearWizard: !isSameProduct,
        location: isServiceItem && isSameProduct
            ? item.location
            : BikeMemoryLocation.none,
      ));
      return;
    }

    widget.onChanged(item.copyWith(
      clearProduct: true,
      clearWizard: true,
      name: selection.productName ?? '',
      isCatalogProduct: false,
      isServiceItem: false,
      unitPrice: item.unitPrice,
      location: BikeMemoryLocation.none,
      notes: selection.description ?? '',
    ));
  }

  /// Un número que ya no se edita: se lee igual que el editable, con el
  /// candado en el precio.
  Widget _lockedNumber(
    ThemeData theme,
    String text, {
    required bool mobileLayout,
    required String label,
    bool showLock = false,
  }) {
    final scheme = theme.colorScheme;
    final value = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLock) ...[
          Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    if (!mobileLayout) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(alignment: Alignment.centerRight, child: value),
      );
    }
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: const OutlineInputBorder(),
      ),
      child: value,
    );
  }

  Widget _buildQuantityField(
    ThemeData theme,
    JobPartItem item, {
    required bool mobileLayout,
  }) {
    if (widget.locked) {
      return _lockedNumber(
        theme,
        formatJobLineQuantity(item.quantity),
        mobileLayout: mobileLayout,
        label: 'Cantidad',
      );
    }
    // Horas de mano de obra, litros o metros llevan decimales (1,5).
    return TextFormField(
      key: mobileLayout ? ValueKey('mobile_part_quantity_${item.id}') : null,
      initialValue: formatJobLineQuantity(item.quantity),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: mobileLayout ? TextAlign.start : TextAlign.right,
      style: theme.textTheme.bodyMedium,
      decoration: mobileLayout
          ? const InputDecoration(
              labelText: 'Cantidad',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(),
            )
          : _kLineNumberDecoration,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
      ],
      onChanged: (value) => widget.onChanged(item.withQuantityText(value)),
    );
  }

  Widget _buildPriceField(
    ThemeData theme,
    JobPartItem item, {
    required bool mobileLayout,
  }) {
    if (widget.locked) {
      return _lockedNumber(
        theme,
        mobileLayout
            ? '\$ ${item.unitPrice.toStringAsFixed(0)}'
            : item.unitPrice.toStringAsFixed(0),
        mobileLayout: mobileLayout,
        label: 'Precio unit.',
        showLock: true,
      );
    }
    // «Cambiar por otro artículo» trae el precio del nuevo, pero un campo con
    // `initialValue` conserva el texto que ya tenía: mostraba el precio del
    // artículo anterior mientras el total usaba el nuevo (C1/C4 nativo,
    // 2026-09-30). Otro artículo es otro campo.
    return KeyedSubtree(
      key: ValueKey('part_price_product_${item.product?.id ?? item.name}'),
      child: _buildEditablePriceField(theme, item, mobileLayout: mobileLayout),
    );
  }

  Widget _buildEditablePriceField(
    ThemeData theme,
    JobPartItem item, {
    required bool mobileLayout,
  }) {
    return TextFormField(
      key: mobileLayout ? ValueKey('mobile_part_price_${item.id}') : null,
      initialValue: item.unitPrice.toStringAsFixed(0),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: mobileLayout ? TextAlign.start : TextAlign.right,
      style: theme.textTheme.bodyMedium,
      decoration: mobileLayout
          ? const InputDecoration(
              labelText: 'Precio unit.',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            )
          : _kLineNumberDecoration,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(r'^\d+\.?\d{0,2}'),
        ),
      ],
      onChanged: (value) {
        final newPrice = double.tryParse(value) ?? 0;
        widget.onChanged(item.copyWith(unitPrice: newPrice));
      },
    );
  }

  String _formattedTotal(JobPartItem item) {
    return NumberFormat.currency(symbol: '\$', decimalDigits: 0)
        .format(item.quantity * item.unitPrice);
  }

  Widget _buildTotalText(
    ThemeData theme,
    JobPartItem item, {
    bool mobileLayout = false,
  }) {
    return Text(
      _formattedTotal(item),
      style: (mobileLayout
              ? theme.textTheme.titleMedium
              : theme.textTheme.bodyMedium)
          ?.copyWith(fontWeight: FontWeight.w700),
      textAlign: TextAlign.right,
    );
  }
}

/// En escritorio cantidad y precio se leen como números: sin borde, relleno
/// ni signo (el recuadro lo dibuja la fila al pasar el mouse, y el total ya
/// lleva el signo). Se anulan todos los bordes porque el tema pone el suyo.
const InputDecoration _kLineNumberDecoration = InputDecoration(
  isDense: true,
  filled: false,
  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
);

/// Cómo quedó la configuración de un servicio, para su chip en la línea.
class _LineConfigStatus {
  const _LineConfigStatus(this.tone, this.label);

  final JobLineChipTone tone;
  final String label;
}

class _JobServiceItem {
  final String id;
  final Product? serviceProduct;
  final String description;
  final double hours;
  final double hourlyRate;
  final DateTime date;

  _JobServiceItem({
    String? id,
    this.serviceProduct,
    required this.description,
    required this.hours,
    required this.hourlyRate,
    required this.date,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  String get displayName => serviceProduct?.name ?? description;

  bool get hasCustomDescription =>
      serviceProduct != null &&
      description.isNotEmpty &&
      description != serviceProduct!.name;

  double get total => hours * hourlyRate;

  _JobServiceItem copyWith({
    Product? serviceProduct,
    String? description,
    double? hours,
    double? hourlyRate,
    DateTime? date,
  }) {
    return _JobServiceItem(
      id: id,
      serviceProduct: serviceProduct ?? this.serviceProduct,
      description: description ?? this.description,
      hours: hours ?? this.hours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      date: date ?? this.date,
    );
  }
}

// Modern part item dialog with ProductAutocompleteField
class _PartItemDialog extends StatefulWidget {
  final Function(
          ProductSelection selection, int quantity, double price, String? notes)
      onItemAdded;

  const _PartItemDialog({
    required this.onItemAdded,
  });

  @override
  State<_PartItemDialog> createState() => _PartItemDialogState();
}

class _PartItemDialogState extends State<_PartItemDialog> {
  ProductSelection? _selection;
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  final _productTextController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    _productTextController.dispose();
    super.dispose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      title: const Text('Agregar Repuesto o Parte'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product autocomplete field
            ProductAutocompleteField(
              controller: _productTextController,
              onProductSelected: (selection) {
                setState(() {
                  _selection = selection;
                  if (selection.isCatalogProduct && selection.product != null) {
                    _priceController.text = selection.product!.price.toString();
                  } else if (!selection.isCatalogProduct) {
                    // For ad-hoc items, set a default price if empty
                    if (_priceController.text.isEmpty) {
                      _priceController.text = '0';
                    }
                  }
                });
              },
              allowCustomItems: true,
              labelText: 'Repuesto o Parte',
              hintText: 'Buscar en catálogo o escribir personalizado...',
            ),
            const SizedBox(height: 16),

            // Notes field
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: Cliente pidió color específico...',
                border: OutlineInputBorder(),
                helperText: 'Información adicional sobre esta parte',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Quantity and price
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Precio Unitario',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),

            // Stock warning for catalog products
            if (_selection?.isCatalogProduct == true &&
                _selection?.product != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _selection!.product!.availableStockQuantity > 0
                        ? Colors.blue.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selection!.product!.availableStockQuantity > 0
                            ? Icons.inventory
                            : Icons.warning_amber,
                        size: 20,
                        color: _selection!.product!.availableStockQuantity > 0
                            ? Colors.blue
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stock disponible: ${_selection!.product!.availableStockQuantity} unidades',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                _selection!.product!.availableStockQuantity > 0
                                    ? Colors.blue.shade900
                                    : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            // If user typed something but didn't select, create ad-hoc selection
            if (_selection == null &&
                _productTextController.text.trim().isNotEmpty) {
              _selection = ProductSelection(
                isCatalogProduct: false,
                displayText: _productTextController.text.trim(),
                customDescription: _productTextController.text.trim(),
              );
              // Set default price if not set
              if (_priceController.text.isEmpty) {
                _priceController.text = '0';
              }
            }

            // Validate all required fields
            String? errorMessage;

            if (_selection == null ||
                _productTextController.text.trim().isEmpty) {
              errorMessage = 'Por favor seleccione o ingrese un producto';
            } else if (_quantityController.text.isEmpty ||
                int.tryParse(_quantityController.text) == null) {
              errorMessage = 'Por favor ingrese una cantidad válida';
            } else if (_priceController.text.isEmpty ||
                double.tryParse(_priceController.text) == null) {
              errorMessage = 'Por favor ingrese un precio válido';
            } else if (int.parse(_quantityController.text) <= 0) {
              errorMessage = 'La cantidad debe ser mayor a 0';
            } else if (double.parse(_priceController.text) < 0) {
              errorMessage = 'El precio no puede ser negativo';
            }

            if (errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errorMessage)),
              );
            } else {
              widget.onItemAdded(
                _selection!,
                int.parse(_quantityController.text),
                double.parse(_priceController.text),
                _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              );
              Navigator.of(context).pop();
            }
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// Product selector dialog
class _ProductSelectorDialog extends StatefulWidget {
  final List<Product> products;
  final Function(Product product, int quantity, double price) onProductSelected;

  const _ProductSelectorDialog({
    required this.products,
    required this.onProductSelected,
  });

  @override
  State<_ProductSelectorDialog> createState() => _ProductSelectorDialogState();
}

class _ProductSelectorDialogState extends State<_ProductSelectorDialog> {
  Product? _selectedProduct;
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _searchController = TextEditingController();
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = widget.products.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.sku.toLowerCase().contains(query) ||
            (p.brand?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar Producto'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar producto',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Product>(
              initialValue: _selectedProduct,
              decoration: const InputDecoration(
                labelText: 'Producto',
                border: OutlineInputBorder(),
              ),
              items: _filteredProducts.map((product) {
                return DropdownMenuItem(
                  value: product,
                  child: Text(
                      '${product.name} (${product.sku}) - Stock: ${product.availableStockQuantity}'),
                );
              }).toList(),
              onChanged: (product) {
                setState(() {
                  _selectedProduct = product;
                  _priceController.text = product?.price.toString() ?? '';
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Precio Unitario',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedProduct != null &&
                _quantityController.text.isNotEmpty &&
                _priceController.text.isNotEmpty) {
              widget.onProductSelected(
                _selectedProduct!,
                int.parse(_quantityController.text),
                double.parse(_priceController.text),
              );
              Navigator.of(context).pop();
            }
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// Service entry dialog
class _ServiceEntryDialog extends StatefulWidget {
  final List<Product> serviceProducts;
  final void Function(
    Product? serviceProduct,
    String description,
    double hours,
    double rate,
    DateTime date,
  ) onServiceAdded;

  const _ServiceEntryDialog({
    required this.serviceProducts,
    required this.onServiceAdded,
  });

  @override
  State<_ServiceEntryDialog> createState() => _ServiceEntryDialogState();
}

class _ServiceEntryDialogState extends State<_ServiceEntryDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _hoursController;
  late final TextEditingController _rateController;
  final TextEditingController _searchController = TextEditingController();

  late DateTime _selectedDate;
  late List<Product> _filteredServices;
  Product? _selectedService;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _selectedService = null;

    _descriptionController = TextEditingController();
    _hoursController = TextEditingController(text: '1');
    _rateController = TextEditingController(text: '15000');
    _selectedDate = DateTime.now();

    _filteredServices = List<Product>.from(widget.serviceProducts);
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _hoursController.dispose();
    _rateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredServices = List<Product>.from(widget.serviceProducts);
      } else {
        _filteredServices = widget.serviceProducts.where((service) {
          final nameMatch = service.name.toLowerCase().contains(query);
          final skuMatch = service.sku.toLowerCase().contains(query);
          return nameMatch || skuMatch;
        }).toList();
      }
    });
  }

  void _selectService(Product service) {
    setState(() {
      _selectedService = service;
      final currentDescription = _descriptionController.text.trim();
      if (currentDescription.isEmpty || currentDescription == service.name) {
        _descriptionController.text = service.name;
      }
      _rateController.text = service.price.toStringAsFixed(0);
      _validationMessage = null;
    });
  }

  void _setValidationMessage(String? message) {
    setState(() {
      _validationMessage = message;
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      title: const Text('Agregar Mano de Obra'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.serviceProducts.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Seleccionar servicio',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar servicio',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: _filteredServices.isEmpty
                    ? Center(
                        child: Text(
                          'No se encontraron servicios',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filteredServices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final service = _filteredServices[index];
                          final isSelected = _selectedService?.id == service.id;
                          return ListTile(
                            leading: const Icon(Icons.design_services_outlined),
                            title: Text(service.name),
                            subtitle: Text(service.sku),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: theme.colorScheme.primary)
                                : null,
                            selected: isSelected,
                            onTap: () => _selectService(service),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción del trabajo',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hoursController,
                    decoration: const InputDecoration(
                      labelText: 'Horas',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _rateController,
                    decoration: const InputDecoration(
                      labelText: 'Tarifa/Hora',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _validationMessage!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            _setValidationMessage(null);
            final parsedHours =
                double.tryParse(_hoursController.text.replaceAll(',', '.'));
            final parsedRate =
                double.tryParse(_rateController.text.replaceAll(',', '.'));
            final trimmedDescription = _descriptionController.text.trim();

            if (parsedHours == null || parsedHours <= 0) {
              _setValidationMessage('Ingrese un número de horas válido.');
              return;
            }
            if (parsedRate == null || parsedRate < 0) {
              _setValidationMessage('Ingrese una tarifa válida.');
              return;
            }
            if (trimmedDescription.isEmpty && _selectedService == null) {
              _setValidationMessage(
                  'Seleccione un servicio o ingrese una descripción.');
              return;
            }

            final description = trimmedDescription.isNotEmpty
                ? trimmedDescription
                : _selectedService?.name ?? '';

            widget.onServiceAdded(
              _selectedService,
              description,
              parsedHours,
              parsedRate,
              _selectedDate,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// Customer Selector Widget
class _CustomerSelector extends StatefulWidget {
  final List<Customer> initialCustomers;
  final Future<Customer?> Function(String name) onCreateCustomer;

  const _CustomerSelector({
    required this.initialCustomers,
    required this.onCreateCustomer,
  });

  @override
  State<_CustomerSelector> createState() => _CustomerSelectorState();
}

class _CustomerSelectorState extends State<_CustomerSelector> {
  late final List<Customer> _allCustomers =
      List<Customer>.from(widget.initialCustomers);
  late List<Customer> _customers = List<Customer>.from(widget.initialCustomers);
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;
  bool _showCreateForm = false;
  Customer? _editingCustomer;

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rutController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String term) {
    _debounce?.cancel();
    if (_isSearching) {
      setState(() => _isSearching = false);
    }
    setState(() {
      _customers = _filterCustomers(term);
    });
  }

  List<Customer> _filterCustomers(String term) {
    final query = _normalizeSearchTerm(term);
    if (query.isEmpty) {
      return List<Customer>.from(_allCustomers);
    }

    return _allCustomers.where((customer) {
      final searchableParts = [
        customer.name,
        customer.rut,
        customer.email ?? '',
        customer.phone ?? '',
      ];

      return searchableParts.any(
        (value) => _normalizeSearchTerm(value).contains(query),
      );
    }).toList(growable: false);
  }

  String _normalizeSearchTerm(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ü', 'u');
  }

  void _populateFormFromCustomer(Customer customer) {
    _nameController.text = customer.name;
    _rutController.text = customer.rut;
    _emailController.text = customer.email ?? '';
    _phoneController.text = customer.phone ?? '';
    _addressController.text = customer.address ?? '';
  }

  void _clearForm() {
    _nameController.clear();
    _rutController.clear();
    _emailController.clear();
    _phoneController.clear();
    _addressController.clear();
  }

  void _startCreateCustomer() {
    setState(() {
      _showCreateForm = true;
      _editingCustomer = null;
      _clearForm();
    });
  }

  void _startEditCustomer(Customer customer) {
    setState(() {
      _showCreateForm = true;
      _editingCustomer = customer;
      _populateFormFromCustomer(customer);
    });
  }

  void _closeForm() {
    setState(() {
      _showCreateForm = false;
      _editingCustomer = null;
      _clearForm();
    });
  }

  Future<void> _handleCreateCustomer() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El nombre es obligatorio'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final customer = await _saveCustomerWithData({
      'name': _nameController.text.trim(),
      'rut': _rutController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
    });

    if (customer != null && mounted) {
      Navigator.of(context).pop(customer);
    }
  }

  Future<Customer?> _saveCustomerWithData(Map<String, String> data) async {
    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final isEditing = _editingCustomer != null;

      final normalizedRut = (data['rut'] ?? '').trim();
      final normalizedEmail = (data['email'] ?? '').trim();
      final normalizedPhone = (data['phone'] ?? '').trim();
      final normalizedAddress = (data['address'] ?? '').trim();

      final saved = isEditing
          ? await customerService.updateCustomer(
              _editingCustomer!.copyWith(
                name: data['name']!,
                rut: normalizedRut,
                email: normalizedEmail.isEmpty ? null : normalizedEmail,
                phone: normalizedPhone.isEmpty ? null : normalizedPhone,
                address: normalizedAddress.isEmpty ? null : normalizedAddress,
                updatedAt: DateTime.now(),
              ),
            )
          : await customerService.createCustomer(
              Customer(
                tenantId: tenantId,
                name: data['name']!,
                rut: normalizedRut,
                email: normalizedEmail.isEmpty ? null : normalizedEmail,
                phone: normalizedPhone.isEmpty ? null : normalizedPhone,
                address: normalizedAddress.isEmpty ? null : normalizedAddress,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

      if (!mounted) return saved;
      setState(() {
        final existingIndex =
            _allCustomers.indexWhere((item) => item.id == saved.id);
        if (existingIndex >= 0) {
          _allCustomers[existingIndex] = saved;
        } else {
          _allCustomers.add(saved);
        }
        _allCustomers.sort(
          (left, right) => left.name.toLowerCase().compareTo(
                right.name.toLowerCase(),
              ),
        );
        _customers = _filterCustomers(_searchController.text);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Cliente "${saved.name}" actualizado exitosamente'
                  : 'Cliente "${saved.name}" creado exitosamente',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      return saved;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear cliente: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.all(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 650,
        // When showing the form vertically, constraint height smoothly
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          minHeight: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clean Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _showCreateForm ? Icons.person_add : Icons.people_alt,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _showCreateForm
                          ? (_editingCustomer != null
                              ? 'Editar Cliente'
                              : 'Nuevo Cliente')
                          : 'Seleccionar Cliente',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content Area (Switches between List and Form)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _showCreateForm
                    ? _buildFormView(theme)
                    : _buildListView(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(ThemeData theme) {
    return Column(
      key: const ValueKey('list_view'),
      children: [
        // Action Bar (Search + Add Button)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, RUT, email...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _startCreateCustomer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ),

        // Progress Indicator
        if (_isSearching)
          const LinearProgressIndicator(minHeight: 2)
        else
          const Divider(height: 1),

        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Nombre',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Contacto',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 48), // Space for edit button
            ],
          ),
        ),
        const Divider(height: 1),

        // Table Body
        Expanded(
          child: _customers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off,
                          size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No se encontraron clientes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final customer = _customers[index];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(customer),
                      hoverColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        child: Row(
                          children: [
                            // Name & Document
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                  if (customer.rut.isNotEmpty)
                                    Text(
                                      customer.rut,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Contact Info
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (customer.phone?.isNotEmpty == true)
                                    Text(
                                      customer.phone!,
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (customer.email?.isNotEmpty == true)
                                    Text(
                                      customer.email!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (customer.phone?.isEmpty != false &&
                                      customer.email?.isEmpty != false)
                                    Text(
                                      'Sin contacto',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Actions
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: theme.colorScheme.outline,
                              tooltip: 'Editar cliente',
                              onPressed: () => _startEditCustomer(customer),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFormView(ThemeData theme) {
    return Column(
      key: const ValueKey('form_view'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _nameController,
                        label: 'Nombre Completo *',
                        icon: Icons.person_outline,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _rutController,
                        label: 'RUT o Documento',
                        icon: Icons.badge_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _phoneController,
                        label: 'Teléfono',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _emailController,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _addressController,
                  label: 'Dirección (Opcional)',
                  icon: Icons.location_on_outlined,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _closeForm,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _handleCreateCustomer,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Guardar y Seleccionar'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// ============================================================
// BROWSER-STYLE BIKE TAB (Chrome/Edge inspired tab design)
// ============================================================
class _BrowserStyleBikeTab extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _BrowserStyleBikeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onClose,
  });

  @override
  State<_BrowserStyleBikeTab> createState() => _BrowserStyleBikeTabState();
}

class _BrowserStyleBikeTabState extends State<_BrowserStyleBikeTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: widget.isSelected
                ? Border(
                    top: BorderSide(color: theme.colorScheme.primary, width: 3),
                    left: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5)),
                    right: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5)),
                  )
                : Border(
                    bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                        width: 1),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pedal_bike,
                size: 16,
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: widget.isSelected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (widget.onClose != null &&
                  (_isHovered || widget.isSelected)) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? theme.colorScheme.error.withValues(alpha: 0.1)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: _isHovered
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ] else if (widget.onClose != null) ...[
                const SizedBox(width: 22), // Placeholder for close button width
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BikeTabButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final Color primaryColor;
  final Color inactiveColor;

  const _BikeTabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.canClose,
    required this.onTap,
    required this.primaryColor,
    required this.inactiveColor,
    this.onClose,
  });

  @override
  State<_BikeTabButton> createState() => _BikeTabButtonState();
}

class _BikeTabButtonState extends State<_BikeTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MechanicJobResponsivePolicy.usesCompactComposition(
      ResponsiveViewport.widthOf(context),
    );
    final showClose = widget.canClose &&
        widget.onClose != null &&
        (isCompact || _isHovered || widget.isSelected);

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: 'Bicicleta ${widget.label}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? widget.primaryColor.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: widget.isSelected
                        ? widget.primaryColor
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 16,
                    color: widget.isSelected
                        ? widget.primaryColor
                        : widget.inactiveColor,
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: widget.isSelected
                            ? theme.colorScheme.onSurface
                            : widget.inactiveColor,
                      ),
                    ),
                  ),
                  if (widget.canClose)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: showClose ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !showClose,
                        child: Semantics(
                          button: true,
                          label: 'Quitar ${widget.label} del trabajo',
                          child: Tooltip(
                            message: 'Quitar ${widget.label}',
                            child: InkWell(
                              onTap: widget.onClose,
                              borderRadius: BorderRadius.circular(999),
                              hoverColor: theme.colorScheme.error
                                  .withValues(alpha: 0.12),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(
                                  Icons.close,
                                  size: 17,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una tarea del taller que cubre un servicio de la línea (paso G4).
class _LineWork {
  const _LineWork({
    required this.taskId,
    required this.task,
    required this.done,
    this.assignee,
    this.note,
  });

  final String taskId;
  final TaskModel task;
  final String? assignee;

  /// Quien lo trabaja lo marcó hecho (`smart_task_job_items.done_at`).
  final bool done;
  final ServiceNote? note;
}

/// Lo que la ficha completa en una línea al cargarse (perfil y rueda por
/// defecto), para aplicarlo sobre la lista vigente.
class _ServiceLocationHydration {
  const _ServiceLocationHydration({
    required this.itemId,
    required this.profile,
    required this.fromLocation,
    required this.toLocation,
  });

  final String itemId;
  final ServiceWizardProfile? profile;
  final BikeMemoryLocation fromLocation;
  final BikeMemoryLocation toLocation;
}

/// El guardado se detuvo antes de escribir las líneas; el mensaje dice por
/// qué y qué hacer.
/// Un guardado de líneas enviado sin respuesta. [fromThisForm]: lo armó este
/// formulario y trae lo necesario para adoptar su recibo (lo de «Configurar»
/// que llevaba). Si no, se encontró en la bandeja al abrir el trabajo: las
/// líneas a la vista no lo tienen. Las tareas de sus líneas nuevas viajan en
/// el comando, no aquí: nacen con él en el servidor.
class _PendingLineSave {
  const _PendingLineSave._({
    required this.operationKeys,
    required this.fromThisForm,
    this.jobId,
    this.promotions = const {},
    this.bikeIds = const {},
    this.creation,
    this.headerShown,
  });

  factory _PendingLineSave.sent({
    required String operationKey,
    required String jobId,
    required Map<String, PendingBikeFactPromotion> promotions,
    required Set<String> bikeIds,
    PendingWorkshopCommand? creation,
    Map<String, dynamic>? headerShown,
  }) =>
      _PendingLineSave._(
        operationKeys: [operationKey],
        fromThisForm: true,
        jobId: jobId,
        promotions: promotions,
        bikeIds: bikeIds,
        creation: creation,
        headerShown: headerShown,
      );

  factory _PendingLineSave.restored(List<String> operationKeys) =>
      _PendingLineSave._(operationKeys: operationKeys, fromThisForm: false);

  /// Del más viejo al más nuevo.
  final List<String> operationKeys;
  final bool fromThisForm;

  /// El trabajo del guardado de este formulario, para adoptar su recibo.
  final String? jobId;
  final Map<String, PendingBikeFactPromotion> promotions;
  final Set<String> bikeIds;

  /// El alta que va antes de estas líneas (un trabajo nuevo), tal como se
  /// respaldó: se resuelve primero, y si ya salió de la bandeja su recibo se
  /// consulta con su contenido.
  final PendingWorkshopCommand? creation;

  /// Lo que el formulario mostraba de la cabecera al enviarlas: si su recibo
  /// se adopta en un guardado posterior, lo editado desde entonces sigue
  /// contando como editado.
  final Map<String, dynamic>? headerShown;
}

class _JobSaveStopped implements Exception {
  const _JobSaveStopped(this.message);

  final String message;

  @override
  String toString() => message;
}

/// El guardado de las líneas quedó sin respuesta y, detrás, respaldado con
/// él, lo que lo seguía: la decisión de garantía y quizá el cambio de estado.
/// Salen solos cuando las líneas lleguen; nada de eso está aplicado todavía.
class _JobLinesPendingWithFollowUps implements Exception {
  const _JobLinesPendingWithFollowUps(this.lines, this.followUps);

  final JobLineSavePendingException lines;
  final List<PendingWorkshopCommand> followUps;

  @override
  String toString() {
    final why = lines.busy
        ? 'Otra pestaña abierta está enviando el guardado de las líneas'
        : lines.queued
            ? 'El guardado de las líneas espera detrás de uno anterior de '
                'este trabajo que sigue sin respuesta'
            : 'El servidor no respondió al guardar las líneas';
    final names = [
      for (final follower in followUps)
        switch (follower.kind) {
          WorkshopCommandKind.jobWarrantyDecision => 'la decisión de garantía',
          WorkshopCommandKind.jobStatusTransition => 'el cambio de estado',
          _ => 'otro cambio',
        },
    ].join(' y ');
    return '$why. Quedaron respaldadas en este equipo y, detrás de ellas, '
        '$names: se envían solos, en ese orden, cuando las líneas lleguen '
        '(también al abrir este trabajo). Hasta entonces la cobertura y el '
        'documento siguen como estaban.';
  }
}
