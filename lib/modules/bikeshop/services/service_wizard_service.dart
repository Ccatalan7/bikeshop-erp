import 'package:supabase_flutter/supabase_flutter.dart';

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

      return ServiceWizardProfile(
        id: profileId,
        name: profileData['name'] as String,
        serviceFamily: (profileData['service_family'] as String?) ?? '',
        customerSummaryTemplate:
            profileData['customer_summary_template'] as String?,
        questions: questions,
      );
    } catch (_) {
      return null;
    }
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
    return rawValue;
  }
}
