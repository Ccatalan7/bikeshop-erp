import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/brake_canonical_data.dart';
import '../config/diagnosis_field_definitions.dart';
import '../config/drivetrain_canonical_data.dart';

/// A single question in the service wizard
class ServiceProfileQuestion {
  final String id;
  final String key;
  final String label;
  final String
      questionType; // single_select, multi_select, text, number, boolean
  final bool isRequired;
  final bool isAdvanced;
  final List<ServiceQuestionOption> options;
  final int sortOrder;

  const ServiceProfileQuestion({
    required this.id,
    required this.key,
    required this.label,
    required this.questionType,
    required this.isRequired,
    required this.isAdvanced,
    required this.options,
    required this.sortOrder,
  });

  ServiceProfileQuestion copyWith({
    String? id,
    String? key,
    String? label,
    String? questionType,
    bool? isRequired,
    bool? isAdvanced,
    List<ServiceQuestionOption>? options,
    int? sortOrder,
  }) {
    return ServiceProfileQuestion(
      id: id ?? this.id,
      key: key ?? this.key,
      label: label ?? this.label,
      questionType: questionType ?? this.questionType,
      isRequired: isRequired ?? this.isRequired,
      isAdvanced: isAdvanced ?? this.isAdvanced,
      options: options ?? this.options,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory ServiceProfileQuestion.fromJson(Map<String, dynamic> json) {
    final rawOpts = json['options_json'] as List? ?? [];
    final opts = rawOpts.map((e) {
      if (e is Map<String, dynamic>) {
        return ServiceQuestionOption(
          value: (e['value'] ?? e['id'] ?? '').toString(),
          label: (e['label'] ?? e['value'] ?? '').toString(),
        );
      }
      return ServiceQuestionOption(value: e.toString(), label: e.toString());
    }).toList();

    return ServiceProfileQuestion(
      id: json['id'] as String,
      key: json['key'] as String,
      label: json['label'] as String,
      questionType: json['question_type'] as String? ?? 'text',
      isRequired: json['is_required'] as bool? ?? false,
      isAdvanced: json['is_advanced'] as bool? ?? false,
      options: opts,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class ServiceQuestionOption {
  final String value;
  final String label;
  const ServiceQuestionOption({required this.value, required this.label});
}

/// Full service profile including questions
class ServiceWizardProfile {
  final String id;
  final String name;
  final String serviceFamily;
  final String? targetFamily;
  final String? targetPositionMode;
  final String? customerSummaryTemplate;
  final List<ServiceProfileQuestion> questions;

  const ServiceWizardProfile({
    required this.id,
    required this.name,
    required this.serviceFamily,
    this.targetFamily,
    this.targetPositionMode,
    this.customerSummaryTemplate,
    required this.questions,
  });
}

/// Result returned from the wizard dialog
class ServiceWizardResult {
  final Map<String, dynamic> answers;
  final String summary;

  const ServiceWizardResult({required this.answers, required this.summary});
}

/// Service that fetches wizard profiles from Supabase
class ServiceWizardService {
  final _client = Supabase.instance.client;

  Future<ServiceWizardProfile?> getProfileForProduct(String productId) async {
    try {
      final mapping = await _client
          .from('service_product_profile_mappings')
          .select(
              'tenant_id, service_profile_id, service_profiles(id, name, service_family, customer_summary_template)')
          .eq('product_id', productId)
          .eq('status', 'active')
          .maybeSingle();

      if (mapping == null) return null;

      final profileData = mapping['service_profiles'] as Map<String, dynamic>?;
      if (profileData == null) return null;

      final profileId = profileData['id'] as String;
      final tenantId = mapping['tenant_id']?.toString();

      final rawTargets = await _client
          .from('service_profile_targets')
          .select('tenant_id, target_family, target_position_mode')
          .eq('service_profile_id', profileId)
          .or(
            tenantId != null && tenantId.isNotEmpty
                ? 'tenant_id.is.null,tenant_id.eq.$tenantId'
                : 'tenant_id.is.null',
          );

      Map<String, dynamic>? selectedTarget;
      for (final rawTarget in rawTargets as List) {
        final target = Map<String, dynamic>.from(rawTarget as Map);
        if (target['tenant_id']?.toString() == tenantId) {
          selectedTarget = target;
          break;
        }
        selectedTarget ??= target;
      }

      final rawQuestions = await _client
          .from('service_profile_questions')
          .select()
          .eq('service_profile_id', profileId)
          .order('sort_order');

      final questions = (rawQuestions as List)
          .map(
              (q) => ServiceProfileQuestion.fromJson(q as Map<String, dynamic>))
          .toList();

      return normalizeProfile(
        ServiceWizardProfile(
          id: profileId,
          name: profileData['name'] as String,
          serviceFamily: (profileData['service_family'] as String?) ?? '',
          targetFamily: selectedTarget?['target_family']?.toString(),
          targetPositionMode:
              selectedTarget?['target_position_mode']?.toString(),
          customerSummaryTemplate:
              profileData['customer_summary_template'] as String?,
          questions: questions,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static ServiceWizardProfile? normalizeProfile(ServiceWizardProfile? profile) {
    if (profile == null) {
      return null;
    }

    if (profile.serviceFamily == 'brake' || profile.serviceFamily == 'brakes') {
      return ServiceWizardProfile(
        id: profile.id,
        name: profile.name,
        serviceFamily: 'brake',
        targetFamily: profile.targetFamily,
        targetPositionMode: profile.targetPositionMode,
        customerSummaryTemplate: profile.customerSummaryTemplate,
        questions: _normalizeBrakeQuestions(profile.questions),
      );
    }

    if (profile.serviceFamily == 'drivetrain') {
      return ServiceWizardProfile(
        id: profile.id,
        name: profile.name,
        serviceFamily: profile.serviceFamily,
        targetFamily: profile.targetFamily,
        targetPositionMode: profile.targetPositionMode,
        customerSummaryTemplate: profile.customerSummaryTemplate,
        questions: _normalizeDrivetrainQuestions(profile.questions),
      );
    }

    return profile;
  }

  static Map<String, dynamic> normalizeAnswersForProfile(
    ServiceWizardProfile? profile,
    Map<String, dynamic> answers,
  ) {
    if (profile == null) {
      return Map<String, dynamic>.from(answers);
    }

    if (profile.serviceFamily == 'brake' || profile.serviceFamily == 'brakes') {
      return canonicalizeBrakeWizardAnswers(answers);
    }

    if (profile.serviceFamily == 'drivetrain') {
      return canonicalizeDrivetrainWizardAnswers(answers);
    }

    return Map<String, dynamic>.from(answers);
  }

  /// Generate a human-readable summary from wizard answers + questions.
  /// Resolves raw option values to their human-readable labels.
  static String buildSummary(
    Map<String, dynamic> answers,
    List<ServiceProfileQuestion> questions,
  ) {
    final parts = <String>[];
    for (final q in questions) {
      final val = answers[q.key];
      if (val == null || val.toString().isEmpty) continue;

      if (val is bool) {
        parts.add('${q.label}: ${val ? "Sí" : "No"}');
      } else if (val is List) {
        if (val.isNotEmpty) {
          final labels = val.map((v) {
            return resolveLabel(q, v.toString());
          }).join(', ');
          parts.add('${q.label}: $labels');
        }
      } else {
        final label = resolveLabel(q, val.toString());
        parts.add('${q.label}: $label');
      }
    }
    return parts.join(' · ');
  }

  /// Look up the human-readable label for a raw option value.
  /// Falls back to the raw value if no matching option is found.
  static String resolveLabel(ServiceProfileQuestion q, String rawValue) {
    for (final opt in q.options) {
      if (opt.value == rawValue) return opt.label;
    }

    switch (q.key) {
      case 'which_wheel':
        final canonicalValue = canonicalBrakeWheelValue(rawValue);
        return canonicalValue == null
            ? rawValue
            : (kBrakeWheelOptions[canonicalValue] ?? rawValue);
      case 'fluid_type':
        final canonicalValue = canonicalBrakeFluidTypeValue(rawValue);
        return canonicalValue == null
            ? rawValue
            : (kBrakeFluidTypeOptions[canonicalValue] ?? rawValue);
      case 'rotor_size':
        final canonicalValue = canonicalBrakeRotorSizeValue(rawValue);
        return canonicalValue == null
            ? rawValue
            : (kBrakeRotorSizeOptions[canonicalValue] ?? rawValue);
      case 'piston_count':
        final canonicalValue = canonicalBrakePistonCountValue(rawValue);
        return canonicalValue == null
            ? rawValue
            : (kBrakePistonCountOptions[canonicalValue] ?? rawValue);
      case 'damage_level':
        final canonicalValue = canonicalBrakeDamageLevelValue(rawValue);
        return canonicalValue == null
            ? rawValue
            : (kBrakeDamageLevelOptions[canonicalValue] ?? rawValue);
      case 'brake_type':
      case 'brake_type_mech':
        final canonicalValue = canonicalBrakeTypeValue(rawValue);
        return canonicalValue == null
            ? rawValue
            : (kBrakeTypeDisplayLabels[canonicalValue] ?? rawValue);
      case 'symptom':
        return resolveBrakeSymptomLabel(rawValue) ?? rawValue;
      case 'chain_wear':
      case 'cable_condition':
        return resolveDrivetrainAnswerLabel(q.key, rawValue) ?? rawValue;
      default:
        final definition = diagnosisFieldDefinitionForKey(q.key);
        if (definition != null) {
          return definition.options[rawValue] ?? rawValue;
        }
        return rawValue;
    }
  }

  static List<ServiceProfileQuestion> _normalizeDrivetrainQuestions(
    List<ServiceProfileQuestion> questions,
  ) {
    final result = <ServiceProfileQuestion>[];

    for (final question in questions) {
      if (isDiagnosisLinkedDrivetrainQuestionKey(question.key)) {
        final definition = diagnosisFieldDefinitionForKey(question.key);
        if (definition != null) {
          result.add(
            question.copyWith(
              label: definition.label,
              options: _optionsFromMap(definition.options),
            ),
          );
          continue;
        }
      }

      if (question.key == 'derailleurs') {
        result.add(
          question.copyWith(
            label: '¿Que desviadores?',
            options: const [
              ServiceQuestionOption(value: 'rear', label: 'Trasero'),
              ServiceQuestionOption(value: 'front', label: 'Delantero'),
            ],
          ),
        );
        continue;
      }

      if (question.key == 'front_chainring_count' ||
          question.key == 'rear_cog_count' ||
          question.key == 'freehub_type') {
        result.add(
          question.copyWith(
            label:
                resolveDrivetrainQuestionLabel(question.key) ?? question.label,
            options: switch (question.key) {
              'front_chainring_count' => _optionsFromMap(
                  kDrivetrainFrontChainringCountOptions,
                ),
              'rear_cog_count' => _optionsFromMap(
                  kDrivetrainRearCogCountOptions,
                ),
              'freehub_type' => _optionsFromMap(
                  kDrivetrainFreehubTypeOptions,
                ),
              _ => question.options,
            },
          ),
        );
        continue;
      }

      result.add(question);
    }

    result.sort((left, right) {
      final orderComparison = left.sortOrder.compareTo(right.sortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return left.key.compareTo(right.key);
    });
    return result;
  }

  static List<ServiceProfileQuestion> _normalizeBrakeQuestions(
    List<ServiceProfileQuestion> questions,
  ) {
    final normalizedQuestions = <String, ServiceProfileQuestion>{};
    final canonicalSources = <String, bool>{};

    for (final question in questions) {
      if (isObsoleteBrakeWizardQuestionKey(question.key)) {
        continue;
      }

      final normalizedKey = canonicalBrakeQuestionKey(question.key);
      final normalizedQuestion = question.copyWith(
        key: normalizedKey,
        label: question.key == normalizedKey
            ? question.label
            : (_canonicalBrakeQuestionLabel(normalizedKey) ?? question.label),
        options:
            _canonicalBrakeQuestionOptions(normalizedKey, question.options),
      );
      final isCanonicalSource = question.key == normalizedKey;
      final existingIsCanonical = canonicalSources[normalizedKey] ?? false;

      if (!normalizedQuestions.containsKey(normalizedKey) ||
          (isCanonicalSource && !existingIsCanonical)) {
        normalizedQuestions[normalizedKey] = normalizedQuestion;
        canonicalSources[normalizedKey] = isCanonicalSource;
      }
    }

    final result = normalizedQuestions.values.toList(growable: false);
    result.sort((left, right) {
      final orderComparison = left.sortOrder.compareTo(right.sortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return left.key.compareTo(right.key);
    });
    return result;
  }

  static List<ServiceQuestionOption> _canonicalBrakeQuestionOptions(
    String key,
    List<ServiceQuestionOption> options,
  ) {
    switch (key) {
      case 'which_wheel':
        return _optionsFromMap(kBrakeWheelOptions);
      case 'fluid_type':
        return _optionsFromMap(kBrakeFluidTypeOptions);
      case 'rotor_size':
        return _optionsFromMap(kBrakeRotorSizeOptions);
      case 'piston_count':
        return _optionsFromMap(kBrakePistonCountOptions);
      case 'damage_level':
        return _optionsFromMap(kBrakeDamageLevelOptions);
      case 'brake_type':
      case 'brake_type_mech':
        return _canonicalBrakeTypeQuestionOptions(options);
      case 'symptom':
        final normalizedValues = canonicalizeBrakeSymptomKeys(
          options.map((option) => option.value),
        );
        if (normalizedValues.isEmpty) {
          return options;
        }
        return normalizedValues
            .map(
              (value) => ServiceQuestionOption(
                value: value,
                label: kBrakeSymptomLabels[value] ?? value,
              ),
            )
            .toList(growable: false);
      default:
        return options;
    }
  }

  static List<ServiceQuestionOption> _optionsFromMap(Map<String, String> map) {
    return map.entries
        .map(
          (entry) => ServiceQuestionOption(
            value: entry.key,
            label: entry.value,
          ),
        )
        .toList(growable: false);
  }

  static List<ServiceQuestionOption> _canonicalBrakeTypeQuestionOptions(
    List<ServiceQuestionOption> options,
  ) {
    final normalized = <ServiceQuestionOption>[];
    final seenValues = <String>{};

    for (final option in options) {
      final canonicalValue = canonicalBrakeTypeValue(option.value);
      if (canonicalValue == null || seenValues.contains(canonicalValue)) {
        continue;
      }

      seenValues.add(canonicalValue);
      normalized.add(
        ServiceQuestionOption(
          value: canonicalValue,
          label: kBrakeTypeDisplayLabels[canonicalValue] ?? option.label,
        ),
      );
    }

    return normalized.isEmpty ? options : normalized;
  }

  static String? _canonicalBrakeQuestionLabel(String key) {
    switch (key) {
      case 'which_wheel':
        return '¿Qué rueda(s)?';
      case 'fluid_type':
        return 'Tipo de fluido';
      case 'rotor_size':
        return 'Tamaño del rotor';
      case 'piston_count':
        return 'Número de pistones';
      case 'damage_level':
        return 'Nivel de daño del rotor';
      default:
        return null;
    }
  }
}
