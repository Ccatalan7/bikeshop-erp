import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/service_wizard_service.dart';

void main() {
  group('ServiceWizardService brake normalization', () {
    test('normalizes live brake_type_mech option values to canonical values',
        () {
      final profile = ServiceWizardProfile(
        id: 'profile-1',
        name: 'Cable brake service',
        serviceFamily: 'brake',
        questions: const [
          ServiceProfileQuestion(
            id: 'question-1',
            key: 'brake_type_mech',
            label: 'Tipo de freno mecánico',
            questionType: 'single_select',
            isRequired: true,
            isAdvanced: false,
            options: [
              ServiceQuestionOption(value: 'v-brake', label: 'V-Brake'),
              ServiceQuestionOption(
                value: 'disco_mec',
                label: 'Disco Mecánico',
              ),
              ServiceQuestionOption(
                value: 'cantilever',
                label: 'Cantilever',
              ),
            ],
            sortOrder: 0,
          ),
        ],
      );

      final normalized = ServiceWizardService.normalizeProfile(profile)!;
      final options = normalized.questions.single.options;

      expect(
        options.map((option) => option.value).toList(growable: false),
        const ['v_brake', 'mechanical_disc', 'cantilever'],
      );
      expect(
        options.map((option) => option.label).toList(growable: false),
        const ['V-Brake', 'Disco mecánico', 'Cantilever'],
      );
    });

    test('normalizes live mechanical brake answers to canonical values', () {
      final profile = ServiceWizardProfile(
        id: 'profile-2',
        name: 'Cable brake service',
        serviceFamily: 'brake',
        questions: const [
          ServiceProfileQuestion(
            id: 'question-2',
            key: 'brake_type_mech',
            label: 'Tipo de freno mecánico',
            questionType: 'single_select',
            isRequired: false,
            isAdvanced: false,
            options: [
              ServiceQuestionOption(
                value: 'disco_mec',
                label: 'Disco Mecánico',
              ),
            ],
            sortOrder: 0,
          ),
        ],
      );

      final normalizedAnswers = ServiceWizardService.normalizeAnswersForProfile(
        profile,
        const {'brake_type_mech': 'disco_mec'},
      );

      expect(normalizedAnswers['brake_type_mech'], 'mechanical_disc');
    });
  });
}
