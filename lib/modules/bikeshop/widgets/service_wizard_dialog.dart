import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/brake_canonical_data.dart';
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
    builder: (_) => _ServiceWizardDialog(
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

class _ServiceWizardDialog extends StatefulWidget {
  final String productName;
  final ServiceWizardProfile? profile;
  final Map<String, dynamic>? initialAnswers;
  final ServiceWizardContextSummary? contextSummary;
  final String? helperText;
  final Set<String> hiddenQuestionKeys;
  final Map<String, ServiceWizardQuestionOverride> questionOverrides;
  final Set<String> diagnosisLinkedQuestionKeys;

  const _ServiceWizardDialog({
    required this.productName,
    required this.profile,
    this.initialAnswers,
    this.contextSummary,
    this.helperText,
    this.hiddenQuestionKeys = const <String>{},
    this.questionOverrides = const <String, ServiceWizardQuestionOverride>{},
    this.diagnosisLinkedQuestionKeys = const <String>{},
  });

  bool get isEditing => initialAnswers != null && initialAnswers!.isNotEmpty;

  @override
  State<_ServiceWizardDialog> createState() => _ServiceWizardDialogState();
}

class _ServiceWizardDialogState extends State<_ServiceWizardDialog>
    with SingleTickerProviderStateMixin {
  final Map<String, dynamic> _answers = {};
  final _notesController = TextEditingController();
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
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<ServiceProfileQuestion> get _visibleQuestions {
    final questions = widget.profile?.questions ?? [];
    return questions
        .where(
          (q) => !q.isAdvanced && !widget.hiddenQuestionKeys.contains(q.key),
        )
        .toList();
  }

  ServiceWizardQuestionOverride? _overrideFor(ServiceProfileQuestion q) {
    return widget.questionOverrides[q.key];
  }

  String _questionLabel(ServiceProfileQuestion q) {
    return _overrideFor(q)?.label ?? q.label;
  }

  List<ServiceQuestionOption> _questionOptions(ServiceProfileQuestion q) {
    return _overrideFor(q)?.options ?? q.options;
  }

  bool _isDiagnosisLinked(ServiceProfileQuestion q) {
    return widget.diagnosisLinkedQuestionKeys.contains(q.key);
  }

  bool _prefersDropdownInput(ServiceProfileQuestion q) {
    return _overrideFor(q)?.preferDropdownInput == true ||
        (_isDiagnosisLinked(q) &&
            isDiagnosisLinkedBrakeQuestionKey(q.key) &&
            (q.questionType == 'single_select' ||
                q.questionType == 'multi_select'));
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

  void _confirm() {
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

    Navigator.of(context).pop(
      ServiceWizardResult(answers: answers, summary: summary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProfile = widget.profile != null && _visibleQuestions.isNotEmpty;

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
            onPressed: () => Navigator.of(context).pop(null),
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

  Widget _buildQuestion(ThemeData theme, ServiceProfileQuestion q) {
    final override = _overrideFor(q);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
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
              if (_isDiagnosisLinked(q))
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
    if (_prefersDropdownInput(q)) {
      switch (q.questionType) {
        case 'single_select':
          return _buildSingleSelectDropdownInput(theme, q);
        case 'multi_select':
          return _buildMultiSelectDropdownInput(theme, q);
      }
    }

    switch (q.questionType) {
      case 'boolean':
        return _buildBooleanInput(theme, q);
      case 'single_select':
        return _buildSingleSelectInput(theme, q);
      case 'multi_select':
        return _buildMultiSelectInput(theme, q);
      case 'number':
        return _buildNumberInput(theme, q);
      default:
        return _buildTextInput(theme, q);
    }
  }

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
          GestureDetector(
            onTap: () => setState(() => _answers[q.key] = option.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: val == option.value
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: val == option.value
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: val == option.value ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (val == option.value) ...[
                    Icon(Icons.check,
                        size: 14, color: theme.colorScheme.onPrimary),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: val == option.value
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: val == option.value
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSingleSelectInput(ThemeData theme, ServiceProfileQuestion q) {
    final selected = _answers[q.key] as String?;
    final options = _questionOptions(q);
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt.value;
        return GestureDetector(
          onTap: () => setState(() => _answers[q.key] = opt.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color:
                    isSelected ? theme.colorScheme.primary : theme.dividerColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check,
                      size: 14, color: theme.colorScheme.onPrimary),
                  const SizedBox(width: 4),
                ],
                Text(
                  opt.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSingleSelectDropdownInput(
    ThemeData theme,
    ServiceProfileQuestion q,
  ) {
    final selected = _answers[q.key] as String?;
    final options = _questionOptions(q);
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return BikeshopSingleSelectDropdownField(
      options: options,
      value: selected,
      hintText: 'Selecciona una opción',
      onChanged: (value) {
        setState(() => _answers[q.key] = value);
      },
    );
  }

  Widget _buildMultiSelectInput(ThemeData theme, ServiceProfileQuestion q) {
    final selected = (_answers[q.key] as List?)?.cast<String>() ?? <String>[];
    final options = _questionOptions(q);
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected.contains(opt.value);
        return FilterChip(
          label: Text(opt.label),
          selected: isSelected,
          onSelected: (val) {
            setState(() {
              final current =
                  List<String>.from((_answers[q.key] as List?) ?? []);
              if (val) {
                current.add(opt.value);
              } else {
                current.remove(opt.value);
              }
              _answers[q.key] = current;
            });
          },
          selectedColor: theme.colorScheme.primaryContainer,
          checkmarkColor: theme.colorScheme.primary,
          side: BorderSide(
            color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
          ),
        );
      }).toList(),
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
        setState(() => _answers[q.key] = updatedValues);
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
        setState(() => _answers[q.key] = double.tryParse(v) ?? v);
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
      onChanged: (v) => setState(() => _answers[q.key] = v),
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
            onPressed: () => Navigator.of(context).pop(null),
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
