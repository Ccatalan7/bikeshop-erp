import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/service_wizard_service.dart';

/// Shows the service wizard dialog for a service product.
/// Returns [ServiceWizardResult] with answers + summary, or null if skipped.
/// Pass [initialAnswers] to pre-fill when re-editing a configured service.
Future<ServiceWizardResult?> showServiceWizardDialog(
  BuildContext context, {
  required String productName,
  required bool productIsService,
  ServiceWizardProfile? profile,
  Map<String, dynamic>? initialAnswers,
}) {
  return showDialog<ServiceWizardResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ServiceWizardDialog(
      productName: productName,
      profile: profile,
      initialAnswers: initialAnswers,
    ),
  );
}

class _ServiceWizardDialog extends StatefulWidget {
  final String productName;
  final ServiceWizardProfile? profile;
  final Map<String, dynamic>? initialAnswers;

  const _ServiceWizardDialog({
    required this.productName,
    required this.profile,
    this.initialAnswers,
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
    return questions.where((q) => !q.isAdvanced).toList();
  }

  void _confirm() {
    final answers = Map<String, dynamic>.from(_answers);
    if (_notesController.text.trim().isNotEmpty) {
      answers['_notes'] = _notesController.text.trim();
    }

    final questions = _visibleQuestions;
    String summary = ServiceWizardService.buildSummary(answers, questions);
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

  Widget _buildQuestion(ThemeData theme, ServiceProfileQuestion q) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  q.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (q.isRequired)
                Text(' *',
                    style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          _buildQuestionInput(theme, q),
        ],
      ),
    );
  }

  Widget _buildQuestionInput(ThemeData theme, ServiceProfileQuestion q) {
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
                    Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          val == option.value ? FontWeight.w600 : FontWeight.w400,
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: q.options.map((opt) {
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
                  Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary),
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


  Widget _buildMultiSelectInput(ThemeData theme, ServiceProfileQuestion q) {
    final selected = (_answers[q.key] as List?)?.cast<String>() ?? <String>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: q.options.map((opt) {
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
            label: Text(widget.isEditing ? 'Actualizar servicio' : 'Agregar servicio'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
