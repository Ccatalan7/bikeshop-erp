import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../config/bottom_bracket_canonical_data.dart';
import '../config/drivetrain_canonical_data.dart';
import '../services/service_wizard_service.dart';
import 'bikeshop_multi_select_picker_field.dart';

class ServiceWizardContextChip {
  final IconData icon;
  final String label;

  const ServiceWizardContextChip({
    required this.icon,
    required this.label,
  });
}

class ServiceWizardContextSummary {
  final String title;
  final String? subtitle;
  final List<ServiceWizardContextChip> chips;

  const ServiceWizardContextSummary({
    required this.title,
    this.subtitle,
    this.chips = const <ServiceWizardContextChip>[],
  });
}

class ServiceWizardLockedSelection {
  final String label;
  final String valueLabel;

  const ServiceWizardLockedSelection({
    required this.label,
    required this.valueLabel,
  });
}

class ServiceWizardQuestionOverride {
  final String? label;
  final String? helperText;
  final List<ServiceQuestionOption>? options;
  final ServiceWizardLockedSelection? lockedSelection;
  final bool preferDropdownInput;

  const ServiceWizardQuestionOverride({
    this.label,
    this.helperText,
    this.options,
    this.lockedSelection,
    this.preferDropdownInput = false,
  });
}

/// Dónde queda lo que responde una pregunta (paso G3 del backbone,
/// 2026-09-27): a qué rueda aplica la línea, la ficha de la bici, el
/// diagnóstico de la visita o sólo este servicio. Es el destino de
/// `ServiceQuestionContract`, dicho para quien configura.
enum ServiceConfigurationLayer { target, bike, diagnosis, service }

class ServiceConfigurationLayerCopy {
  const ServiceConfigurationLayerCopy(this.title, [this.subtitle]);

  final String title;
  final String? subtitle;
}

/// Diálogo (formulario de producto), panel bajo la línea (trabajo en
/// escritorio) u hoja inferior (trabajo en teléfono). Las preguntas, sus
/// reglas y el resultado son los mismos en los tres.
enum ServiceConfigurationPresentation { dialog, inline, sheet }

/// Shows the service wizard dialog for a service product.
/// Returns [ServiceWizardResult] with answers + summary, or null if skipped.
/// Pass [initialAnswers] to pre-fill when re-editing a configured service.
Future<ServiceWizardResult?> showServiceWizardDialog(
  BuildContext context, {
  required String productName,
  required bool productIsService,
  ServiceWizardProfile? profile,
  Map<String, dynamic>? initialAnswers,
  ServiceWizardContextSummary? contextSummary,
  String? helperText,
  Set<String> hiddenQuestionKeys = const <String>{},
  Map<String, ServiceWizardQuestionOverride> questionOverrides =
      const <String, ServiceWizardQuestionOverride>{},
  Set<String> diagnosisLinkedQuestionKeys = const <String>{},
}) {
  return showDialog<ServiceWizardResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ServiceConfigurationEditor(
      productName: productName,
      profile: profile,
      initialAnswers: initialAnswers,
      contextSummary: contextSummary,
      helperText: helperText,
      hiddenQuestionKeys: hiddenQuestionKeys,
      questionOverrides: questionOverrides,
      diagnosisLinkedQuestionKeys: diagnosisLinkedQuestionKeys,
    ),
  );
}

/// Muestra «Configurar» en una hoja inferior (trabajo en teléfono). Devuelve
/// el resultado, o null si se cancela.
Future<ServiceWizardResult?> showServiceConfigurationSheet(
  BuildContext context, {
  required String productName,
  required ServiceWizardProfile? profile,
  Map<String, dynamic>? initialAnswers,
  ServiceWizardContextSummary? contextSummary,
  String? helperText,
  Set<String> hiddenQuestionKeys = const <String>{},
  Map<String, ServiceWizardQuestionOverride> questionOverrides =
      const <String, ServiceWizardQuestionOverride>{},
  Set<String> diagnosisLinkedQuestionKeys = const <String>{},
  ServiceConfigurationLayer Function(String questionKey)? layerOf,
  Map<ServiceConfigurationLayer, ServiceConfigurationLayerCopy> layerCopy =
      const {},
}) {
  return showModalBottomSheet<ServiceWizardResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => ServiceConfigurationEditor(
      productName: productName,
      profile: profile,
      initialAnswers: initialAnswers,
      contextSummary: contextSummary,
      helperText: helperText,
      hiddenQuestionKeys: hiddenQuestionKeys,
      questionOverrides: questionOverrides,
      diagnosisLinkedQuestionKeys: diagnosisLinkedQuestionKeys,
      layerOf: layerOf,
      layerCopy: layerCopy,
      presentation: ServiceConfigurationPresentation.sheet,
    ),
  );
}

class ServiceConfigurationEditor extends StatefulWidget {
  final String productName;
  final ServiceWizardProfile? profile;
  final Map<String, dynamic>? initialAnswers;
  final ServiceWizardContextSummary? contextSummary;
  final String? helperText;
  final Set<String> hiddenQuestionKeys;
  final Map<String, ServiceWizardQuestionOverride> questionOverrides;
  final Set<String> diagnosisLinkedQuestionKeys;
  final ServiceConfigurationPresentation presentation;

  /// Agrupa las preguntas por destino; sin él, van en una sola lista.
  final ServiceConfigurationLayer Function(String questionKey)? layerOf;
  final Map<ServiceConfigurationLayer, ServiceConfigurationLayerCopy> layerCopy;

  /// Sin estos, el editor cierra su ruta con el resultado (diálogo y hoja).
  final ValueChanged<ServiceWizardResult>? onConfirm;
  final VoidCallback? onCancel;

  /// Cada cambio del operador, antes de aplicar. El panel bajo la línea se
  /// desmonta al cambiar de pestaña: el formulario guarda este borrador para
  /// reabrirlo igual y para no guardar el trabajo sin decir que quedó uno.
  final ValueChanged<Map<String, dynamic>>? onDraftChanged;

  const ServiceConfigurationEditor({
    super.key,
    required this.productName,
    required this.profile,
    this.initialAnswers,
    this.contextSummary,
    this.helperText,
    this.hiddenQuestionKeys = const <String>{},
    this.questionOverrides = const <String, ServiceWizardQuestionOverride>{},
    this.diagnosisLinkedQuestionKeys = const <String>{},
    this.presentation = ServiceConfigurationPresentation.dialog,
    this.layerOf,
    this.layerCopy = const {},
    this.onConfirm,
    this.onCancel,
    this.onDraftChanged,
  });

  bool get isEditing => initialAnswers != null && initialAnswers!.isNotEmpty;

  @override
  State<ServiceConfigurationEditor> createState() =>
      _ServiceWizardDialogState();
}

class _ServiceWizardDialogState extends State<ServiceConfigurationEditor>
    with SingleTickerProviderStateMixin {
  final Map<String, dynamic> _answers = {};
  final Set<String> _requiredQuestionErrors = <String>{};
  final _notesController = TextEditingController();
  bool _hasAutoDerivedRearDerailleur = false;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // Pre-fill answers when re-editing
    if (widget.initialAnswers != null) {
      for (final entry in widget.initialAnswers!.entries) {
        if (entry.key == '_notes') {
          _notesController.text = entry.value?.toString() ?? '';
        } else {
          _answers[entry.key] = entry.value;
        }
      }
    }

    _syncDerivedAnswers();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<ServiceProfileQuestion> get _visibleQuestions {
    final questions = widget.profile?.questions ?? [];
    final hiddenQuestionKeys = _effectiveHiddenQuestionKeys;
    return questions
        .where(
          (q) => !q.isAdvanced && !hiddenQuestionKeys.contains(q.key),
        )
        .toList();
  }

  Set<String> get _effectiveHiddenQuestionKeys {
    final hiddenQuestionKeys = <String>{...widget.hiddenQuestionKeys};
    if (_shouldAutoHideRearOnlyDerailleur) {
      hiddenQuestionKeys.add('derailleurs');
    }
    if (_isBottomBracketWizard) {
      final family = _selectedBottomBracketFamily;
      if (!isKnownBottomBracketFamily(family)) {
        hiddenQuestionKeys.addAll(const {
          'bb_shell_width_mm',
          'bb_shell_diameter_mm',
          'spindle_interface',
        });
      } else if (!bottomBracketFamilyUsesShellDiameter(family)) {
        hiddenQuestionKeys.add('bb_shell_diameter_mm');
      }
    }
    if (_brakeAnswerExcludesRotor) {
      hiddenQuestionKeys.add('rotor_size');
    }
    return hiddenQuestionKeys;
  }

  /// El rotor sólo existe en un freno de disco: con el tipo de freno
  /// respondido como freno de llanta no se pregunta ni se guarda. Sin
  /// respuesta, la pregunta queda a la vista (la ficha puede no saberlo).
  bool get _brakeAnswerExcludesRotor {
    final brake = _answers['brake_type']?.toString();
    return brake != null &&
        brake.isNotEmpty &&
        brake != 'unknown' &&
        !brake.endsWith('_disc');
  }

  ServiceWizardQuestionOverride? _overrideFor(ServiceProfileQuestion q) {
    return widget.questionOverrides[q.key];
  }

  String _questionLabel(ServiceProfileQuestion q) {
    return _overrideFor(q)?.label ?? q.label;
  }

  List<ServiceQuestionOption> _questionOptions(ServiceProfileQuestion q) {
    return _overrideFor(q)?.options ??
        _bottomBracketQuestionOptions(q) ??
        q.options;
  }

  ServiceProfileQuestion? _questionByKey(String key) {
    final questions =
        widget.profile?.questions ?? const <ServiceProfileQuestion>[];
    for (final question in questions) {
      if (question.key == key) {
        return question;
      }
    }
    return null;
  }

  bool _isDiagnosisLinked(ServiceProfileQuestion q) {
    return widget.diagnosisLinkedQuestionKeys.contains(q.key);
  }

  bool get _isBottomBracketWizard {
    return widget.profile?.serviceFamily == 'bottom_bracket';
  }

  String? get _selectedBottomBracketFamily {
    return canonicalBottomBracketFamilyValue(
      _answers['bottom_bracket_family']?.toString(),
    );
  }

  List<ServiceQuestionOption>? _bottomBracketQuestionOptions(
    ServiceProfileQuestion q,
  ) {
    if (!_isBottomBracketWizard) {
      return null;
    }

    final family = _selectedBottomBracketFamily;
    if (!isKnownBottomBracketFamily(family)) {
      return null;
    }

    final options = switch (q.key) {
      'bb_shell_width_mm' => bottomBracketShellWidthOptionsForFamily(family),
      'bb_shell_diameter_mm' =>
        bottomBracketShellDiameterOptionsForFamily(family),
      'spindle_interface' =>
        bottomBracketSpindleInterfaceOptionsForFamily(family),
      _ => const <String, String>{},
    };

    if (options.isEmpty) {
      return null;
    }

    return options.entries
        .map(
          (entry) => ServiceQuestionOption(
            value: entry.key,
            label: entry.value,
          ),
        )
        .toList(growable: false);
  }

  String _resolveQuestionValueLabel(ServiceProfileQuestion q, String rawValue) {
    for (final option in _questionOptions(q)) {
      if (option.value == rawValue) {
        return option.label;
      }
    }
    return ServiceWizardService.resolveLabel(q, rawValue);
  }

  String _buildSummary(List<ServiceProfileQuestion> questions) {
    final parts = <String>[];
    for (final q in questions) {
      final value = _answers[q.key];
      if (value == null || value.toString().isEmpty) {
        continue;
      }

      final label = _questionLabel(q);
      if (value is bool) {
        parts.add('$label: ${value ? 'Sí' : 'No'}');
        continue;
      }

      if (value is List) {
        if (value.isEmpty) {
          continue;
        }
        final resolvedLabels = value
            .map((raw) => _resolveQuestionValueLabel(q, raw.toString()))
            .join(', ');
        parts.add('$label: $resolvedLabels');
        continue;
      }

      parts.add('$label: ${_resolveQuestionValueLabel(q, value.toString())}');
    }
    return parts.join(' · ');
  }

  bool _questionHasAnswer(ServiceProfileQuestion q) {
    final value = _answers[q.key];
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return true;
    }
    if (value is List) {
      return value.isNotEmpty;
    }
    return value.toString().trim().isNotEmpty;
  }

  bool get _shouldAutoHideRearOnlyDerailleur {
    if (widget.profile?.serviceFamily != 'drivetrain') {
      return false;
    }

    final frontChainringCount = canonicalDrivetrainFrontChainringCountValue(
      _answers['front_chainring_count']?.toString(),
    );
    if (frontChainringCount != '1') {
      return false;
    }

    final derailleursQuestion = _questionByKey('derailleurs');
    if (derailleursQuestion == null ||
        derailleursQuestion.questionType != 'multi_select') {
      return false;
    }

    final optionValues = _questionOptions(
      derailleursQuestion,
    ).map((option) => option.value).toSet();
    return optionValues.contains('rear');
  }

  void _syncDerivedDrivetrainAnswers() {
    if (_shouldAutoHideRearOnlyDerailleur) {
      _answers['derailleurs'] = const ['rear'];
      _requiredQuestionErrors.remove('derailleurs');
      _hasAutoDerivedRearDerailleur = true;
      return;
    }

    if (!_hasAutoDerivedRearDerailleur) {
      return;
    }

    final currentValue = _answers['derailleurs'];
    if (currentValue is List &&
        currentValue.length == 1 &&
        currentValue.first.toString() == 'rear') {
      _answers.remove('derailleurs');
    }
    _hasAutoDerivedRearDerailleur = false;
  }

  void _syncDerivedBottomBracketAnswers() {
    if (!_isBottomBracketWizard) {
      return;
    }

    final family = _selectedBottomBracketFamily;
    if (!isKnownBottomBracketFamily(family)) {
      _answers.remove('bb_shell_width_mm');
      _answers.remove('bb_shell_diameter_mm');
      _answers.remove('spindle_interface');
      return;
    }

    void removeIfInvalid(String key) {
      final currentValue = _answers[key]?.toString();
      if (currentValue == null || currentValue.isEmpty) {
        return;
      }
      final allowedValues = _questionOptions(
        _questionByKey(key) ??
            ServiceProfileQuestion(
              id: '',
              key: key,
              label: '',
              questionType: 'single_select',
              isRequired: false,
              isAdvanced: false,
              options: const <ServiceQuestionOption>[],
              sortOrder: 0,
            ),
      ).map((option) => option.value).toSet();
      if (allowedValues.isNotEmpty && !allowedValues.contains(currentValue)) {
        _answers.remove(key);
      }
    }

    removeIfInvalid('bb_shell_width_mm');
    removeIfInvalid('spindle_interface');

    if (!bottomBracketFamilyUsesShellDiameter(family)) {
      _answers.remove('bb_shell_diameter_mm');
      return;
    }

    removeIfInvalid('bb_shell_diameter_mm');
  }

  void _syncDerivedAnswers() {
    _syncDerivedDrivetrainAnswers();
    _syncDerivedBottomBracketAnswers();
    if (_brakeAnswerExcludesRotor) {
      _answers.remove('rotor_size');
    }
  }

  void _emitDraft() {
    final notes = _notesController.text.trim();
    widget.onDraftChanged?.call({
      ..._answers,
      if (notes.isNotEmpty) '_notes': notes,
    });
  }

  void _updateAnswer(String key, dynamic value) {
    _updateAnswerState(key, value);
    _emitDraft();
  }

  void _updateAnswerState(String key, dynamic value) {
    setState(() {
      _answers[key] = value;
      _syncDerivedAnswers();
      if (_requiredQuestionErrors.contains(key)) {
        final normalized = value is String ? value.trim() : value;
        final hasValue = normalized is bool
            ? true
            : normalized is List
                ? normalized.isNotEmpty
                : normalized != null && normalized.toString().isNotEmpty;
        if (hasValue) {
          _requiredQuestionErrors.remove(key);
        }
      }
    });
  }

  bool _validateRequiredQuestions() {
    final missingKeys = _visibleQuestions
        .where((q) => q.isRequired && !_questionHasAnswer(q))
        .map((q) => q.key)
        .toSet();

    if (missingKeys.isEmpty) {
      if (_requiredQuestionErrors.isNotEmpty) {
        setState(() => _requiredQuestionErrors.clear());
      }
      return true;
    }

    setState(() {
      _requiredQuestionErrors
        ..clear()
        ..addAll(missingKeys);
    });
    return false;
  }

  void _confirm() {
    if (!_validateRequiredQuestions()) {
      return;
    }

    final answers = Map<String, dynamic>.from(_answers);
    if (_notesController.text.trim().isNotEmpty) {
      answers['_notes'] = _notesController.text.trim();
    }

    final questions = _visibleQuestions;
    String summary = _buildSummary(questions);
    if (answers['_notes'] != null) {
      final notes = answers['_notes'] as String;
      summary = summary.isEmpty ? notes : '$summary\n$notes';
    }

    final result = ServiceWizardResult(answers: answers, summary: summary);
    if (widget.onConfirm != null) {
      widget.onConfirm!(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  void _cancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProfile = widget.profile != null && _visibleQuestions.isNotEmpty;

    if (widget.presentation != ServiceConfigurationPresentation.dialog) {
      return _buildEmbedded(theme, hasProfile);
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.contextSummary != null) ...[
                        _buildContextSummary(theme, widget.contextSummary!),
                        const SizedBox(height: 16),
                      ],
                      if (widget.helperText != null) ...[
                        _buildContextHint(theme, widget.helperText!),
                        const SizedBox(height: 16),
                      ],
                      if (hasProfile) ...[
                        ..._visibleQuestions
                            .map((q) => _buildQuestion(theme, q)),
                        const SizedBox(height: 8),
                      ] else ...[
                        _buildNoProfileHint(theme),
                        const SizedBox(height: 16),
                      ],
                      _buildNotesField(theme),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              _buildActions(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// Panel bajo la línea o hoja inferior: sin la cabecera del diálogo (la
  /// línea ya nombra el servicio), con las capas y «Cancelar» / «Aplicar».
  /// Escape cancela, como la X del diálogo.
  Widget _buildEmbedded(ThemeData theme, bool hasProfile) {
    final sheet = widget.presentation == ServiceConfigurationPresentation.sheet;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sheet) ...[
          Text(
            widget.productName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
        ],
        ..._buildLayeredBody(theme, hasProfile),
      ],
    );
    final actions = Row(
      children: [
        const Spacer(),
        TextButton(
          key: const ValueKey('service_configuration_cancel'),
          onPressed: _cancel,
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('service_configuration_apply'),
          onPressed: _confirm,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Aplicar'),
        ),
      ],
    );
    final Widget content = sheet
        ? Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: body,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: actions,
                  ),
                ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [body, const SizedBox(height: 12), actions],
          );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: FocusScope(child: content),
    );
  }

  /// Las preguntas por destino (paso G3): «Aplica a», la ficha de la bici
  /// con lo que ya sabe a la vista, el diagnóstico de la visita y lo que es
  /// sólo de este servicio, con las notas del técnico. Sin [layerOf], la
  /// lista única del diálogo.
  List<Widget> _buildLayeredBody(ThemeData theme, bool hasProfile) {
    final layerOf = widget.layerOf;
    if (layerOf == null) {
      return [
        if (widget.contextSummary != null) ...[
          _buildContextSummary(theme, widget.contextSummary!),
          const SizedBox(height: 16),
        ],
        if (widget.helperText != null) ...[
          _buildContextHint(theme, widget.helperText!),
          const SizedBox(height: 16),
        ],
        if (hasProfile)
          ..._visibleQuestions.map((q) => _buildQuestion(theme, q))
        else ...[
          _buildNoProfileHint(theme),
          const SizedBox(height: 16),
        ],
        _buildNotesField(theme),
      ];
    }

    final groups = <ServiceConfigurationLayer, List<ServiceProfileQuestion>>{};
    for (final question in _visibleQuestions) {
      groups.putIfAbsent(layerOf(question.key), () => []).add(question);
    }
    // Lo que la ficha ya confirma: la pregunta está oculta y su respuesta es
    // la de la ficha. Lo sugerido o registrado ya se ve en su pregunta.
    final hidden = _effectiveHiddenQuestionKeys;
    final facts = <({String label, String value})>[
      for (final question
          in widget.profile?.questions ?? const <ServiceProfileQuestion>[])
        if (hidden.contains(question.key) &&
            layerOf(question.key) == ServiceConfigurationLayer.bike &&
            _questionHasAnswer(question))
          (label: _questionLabel(question), value: _answerLabel(question)),
    ];
    final sections = <Widget>[
      if (!hasProfile) _buildNoProfileHint(theme),
    ];
    for (final layer in ServiceConfigurationLayer.values) {
      final questions = groups[layer] ?? const <ServiceProfileQuestion>[];
      final layerFacts = layer == ServiceConfigurationLayer.bike
          ? facts
          : const <({String label, String value})>[];
      final isService = layer == ServiceConfigurationLayer.service;
      if (questions.isEmpty && layerFacts.isEmpty && !isService) continue;
      final copy = widget.layerCopy[layer];
      final children = <Widget>[
        for (final fact in layerFacts) _buildFactRow(theme, fact),
        for (final question in questions)
          layer == ServiceConfigurationLayer.target
              ? _buildTargetQuestion(theme, question)
              : _buildLayerQuestion(theme, question),
        if (isService) _buildNotesField(theme),
      ];
      if (layer == ServiceConfigurationLayer.target) {
        // Sin caja, pero alineado con los controles de las capas.
        sections.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ));
        continue;
      }
      sections.add(_buildLayer(
        theme,
        title: copy?.title ?? _defaultLayerTitle(layer),
        subtitle: layer == ServiceConfigurationLayer.bike
            ? (widget.helperText ?? copy?.subtitle)
            : copy?.subtitle,
        children: children,
      ));
    }
    return [
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        sections[i],
      ],
    ];
  }

  String _defaultLayerTitle(ServiceConfigurationLayer layer) => switch (layer) {
        ServiceConfigurationLayer.target => 'Aplica a',
        ServiceConfigurationLayer.bike => 'Ficha de la bici',
        ServiceConfigurationLayer.diagnosis => 'Diagnóstico',
        ServiceConfigurationLayer.service => 'De este servicio',
      };

  Widget _buildLayer(
    ThemeData theme, {
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  String _answerLabel(ServiceProfileQuestion q) {
    final value = _answers[q.key];
    String labelOf(Object? raw) {
      for (final option in _questionOptions(q)) {
        if (option.value == raw?.toString()) return option.label;
      }
      return raw?.toString() ?? '';
    }

    if (value is bool) return value ? 'Sí' : 'No';
    if (value is List) return value.map(labelOf).join(', ');
    return labelOf(value);
  }

  static const double _layerLabelWidth = 180;

  /// Etiqueta y control en una fila cuando cabe, como una ficha; apilados en
  /// un panel angosto.
  Widget _layerRow(
    ThemeData theme, {
    required Widget label,
    required Widget control,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [label, const SizedBox(height: 8), control],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _layerLabelWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 12),
                  child: label,
                ),
              ),
              Expanded(child: control),
            ],
          );
        },
      ),
    );
  }

  Widget _layerLabel(ThemeData theme, ServiceProfileQuestion q) {
    return Text.rich(
      TextSpan(
        text: _questionLabel(q),
        children: [
          if (q.isRequired)
            TextSpan(
              text: ' *',
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildLayerQuestion(ThemeData theme, ServiceProfileQuestion q) {
    final override = _overrideFor(q);
    return _layerRow(
      theme,
      label: _layerLabel(theme, q),
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (override?.lockedSelection != null) ...[
            _buildLockedSelectionField(theme, override!.lockedSelection!),
            const SizedBox(height: 8),
          ],
          _buildQuestionInput(theme, q),
          if (override?.helperText != null) ...[
            const SizedBox(height: 6),
            Text(
              override!.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (_requiredQuestionErrors.contains(q.key)) ...[
            const SizedBox(height: 6),
            Text(
              'Este campo es obligatorio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// «Aplica a»: pocas opciones que se eligen de una vez, no una lista.
  Widget _buildTargetQuestion(ThemeData theme, ServiceProfileQuestion q) {
    final options = _questionOptions(q);
    if (q.questionType != 'single_select' || options.length > 4) {
      return _buildLayerQuestion(theme, q);
    }
    final selected = _answers[q.key]?.toString();
    return _layerRow(
      theme,
      label: Text.rich(
        TextSpan(
          text: 'Aplica a',
          children: [
            if (q.isRequired)
              TextSpan(
                text: ' *',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.label),
                  selected: selected == option.value,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => _updateAnswer(q.key, option.value),
                ),
            ],
          ),
          if (_requiredQuestionErrors.contains(q.key)) ...[
            const SizedBox(height: 6),
            Text(
              'Elige a qué rueda aplica.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lo que la ficha ya confirma: se ve, no se vuelve a preguntar.
  Widget _buildFactRow(
    ThemeData theme,
    ({String label, String value}) fact,
  ) {
    final ok = VinabikeThemeRoles.maybeOf(context)?.success.accent ??
        theme.colorScheme.primary;
    return _layerRow(
      theme,
      label: Text(
        fact.label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      control: Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              fact.value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 15, color: ok),
                const SizedBox(width: 4),
                Text(
                  'confirmado en la ficha',
                  style: theme.textTheme.bodySmall?.copyWith(color: ok),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.75),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.build_circle_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.profile?.name != null &&
                          widget.profile!.name != widget.productName
                      ? widget.profile!.name
                      : 'Configurar servicio',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProfileHint(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este servicio no tiene preguntas configuradas. '
              'Puedes agregar notas manualmente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextHint(ThemeData theme, String helperText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.link_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              helperText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSummary(
    ThemeData theme,
    ServiceWizardContextSummary summary,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_bike_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (summary.subtitle != null &&
                        summary.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summary.chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Column(
              children: summary.chips.map((chip) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          chip.icon,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          chip.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestion(
    ThemeData theme,
    ServiceProfileQuestion q, {
    double bottom = 20,
  }) {
    final override = _overrideFor(q);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _questionLabel(q),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              // En capas, la del diagnóstico ya lo dice.
              if (_isDiagnosisLinked(q) && widget.layerOf == null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.link_outlined,
                        size: 12,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Diagnóstico',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (q.isRequired)
                Text(' *',
                    style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          if (override?.lockedSelection != null) ...[
            const SizedBox(height: 10),
            _buildLockedSelectionField(theme, override!.lockedSelection!),
          ],
          if (override?.helperText != null) ...[
            const SizedBox(height: 8),
            Text(
              override!.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildQuestionInput(theme, q),
          if (_requiredQuestionErrors.contains(q.key)) ...[
            const SizedBox(height: 8),
            Text(
              'Este campo es obligatorio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLockedSelectionField(
    ThemeData theme,
    ServiceWizardLockedSelection lockedSelection,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lockedSelection.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lockedSelection.valueLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_drop_down_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionInput(ThemeData theme, ServiceProfileQuestion q) {
    switch (q.questionType) {
      case 'boolean':
        return _buildBooleanInput(theme, q);
      case 'single_select':
        return _buildSingleSelectDropdownInput(theme, q);
      case 'multi_select':
        return _buildMultiSelectDropdownInput(theme, q);
      case 'number':
        return _buildNumberInput(theme, q);
      default:
        return _buildTextInput(theme, q);
    }
  }

  /// Sí / No como chips que se eligen con teclado y anuncian cuál está
  /// elegido (revisión de Codex, 2026-09-27: eran GestureDetector sin foco).
  Widget _buildBooleanInput(ThemeData theme, ServiceProfileQuestion q) {
    final val = _answers[q.key] as bool?; // null = nothing selected yet
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in [
          (label: 'Sí', value: true),
          (label: 'No', value: false),
        ])
          ChoiceChip(
            label: Text(option.label),
            selected: val == option.value,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => _updateAnswer(q.key, option.value),
          ),
      ],
    );
  }

  Widget _buildSingleSelectDropdownInput(
    ThemeData theme,
    ServiceProfileQuestion q,
  ) {
    final options = _questionOptions(q);
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    // Una respuesta vieja que ya no es opción (el fluido `dot` de antes del
    // paso F.2) se pregunta de nuevo en vez de tumbar el desplegable.
    final answer = _answers[q.key]?.toString();
    final selected =
        options.any((option) => option.value == answer) ? answer : null;

    return BikeshopSingleSelectDropdownField(
      options: options,
      value: selected,
      hintText: 'Selecciona una opción',
      onChanged: (value) {
        _updateAnswer(q.key, value);
      },
    );
  }

  Widget _buildMultiSelectDropdownInput(
    ThemeData theme,
    ServiceProfileQuestion q,
  ) {
    final selected = (_answers[q.key] as List?)?.cast<String>() ?? <String>[];

    return BikeshopMultiSelectPickerField(
      options: _questionOptions(q),
      selectedValues: selected,
      dialogTitle: _questionLabel(q),
      onChanged: (updatedValues) {
        _updateAnswer(q.key, updatedValues);
      },
    );
  }

  Widget _buildNumberInput(ThemeData theme, ServiceProfileQuestion q) {
    return TextFormField(
      initialValue: _answers[q.key]?.toString() ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        hintText: 'Ingrese un valor...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onChanged: (v) {
        _updateAnswer(q.key, double.tryParse(v) ?? v);
      },
    );
  }

  Widget _buildTextInput(ThemeData theme, ServiceProfileQuestion q) {
    return TextFormField(
      initialValue: _answers[q.key]?.toString() ?? '',
      decoration: InputDecoration(
        hintText: 'Ingrese información...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onChanged: (v) => _updateAnswer(q.key, v),
    );
  }

  Widget _buildNotesField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notas del técnico',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesController,
          onChanged: (_) => _emitDraft(),
          maxLines: 3,
          decoration: InputDecoration(
            hintText:
                'Describe el trabajo a realizar, condiciones del equipo...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          TextButton(
            onPressed: _cancel,
            child: const Text('Omitir'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check, size: 18),
            label: Text(
                widget.isEditing ? 'Actualizar servicio' : 'Agregar servicio'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
