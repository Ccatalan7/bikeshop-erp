import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/brake_canonical_data.dart';

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
  final String? customerSummaryTemplate;
  final List<ServiceProfileQuestion> questions;

  const ServiceWizardProfile({
    required this.id,
    required this.name,
    required this.serviceFamily,
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
              'service_profile_id, service_profiles(id, name, service_family, customer_summary_template)')
          .eq('product_id', productId)
          .eq('status', 'active')
          .maybeSingle();

      if (mapping == null) return null;

      final profileData = mapping['service_profiles'] as Map<String, dynamic>?;
      if (profileData == null) return null;

      final profileId = profileData['id'] as String;

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

    if (profile.serviceFamily != 'brake' && profile.serviceFamily != 'brakes') {
      return profile;
    }

    return ServiceWizardProfile(
      id: profile.id,
      name: profile.name,
      serviceFamily: 'brake',
      customerSummaryTemplate: profile.customerSummaryTemplate,
      questions: _normalizeBrakeQuestions(profile.questions),
    );
  }

  static Map<String, dynamic> normalizeAnswersForProfile(
    ServiceWizardProfile? profile,
    Map<String, dynamic> answers,
  ) {
    if (profile == null ||
        (profile.serviceFamily != 'brake' &&
            profile.serviceFamily != 'brakes')) {
      return Map<String, dynamic>.from(answers);
    }

    return canonicalizeBrakeWizardAnswers(answers);
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
        return kBrakeTypeDisplayLabels[rawValue] ?? rawValue;
      case 'symptom':
        return resolveBrakeSymptomLabel(rawValue) ?? rawValue;
      default:
        return rawValue;
    }
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
