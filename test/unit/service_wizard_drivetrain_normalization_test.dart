import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/service_wizard_service.dart';

void main() {
  group('ServiceWizardService drivetrain normalization', () {
    test('normalizes weak cable_condition options to diagnosis vocabulary', () {
      const profile = ServiceWizardProfile(
        id: 'profile-1',
        name: 'Derailleur adjustment',
        serviceFamily: 'drivetrain',
        questions: [
          ServiceProfileQuestion(
            id: 'question-1',
            key: 'cable_condition',
            label: 'Estado de cables',
            questionType: 'single_select',
            isRequired: false,
            isAdvanced: false,
            options: [
              ServiceQuestionOption(value: 'ok', label: 'OK'),
              ServiceQuestionOption(
                value: 'frayed',
                label: 'Deshilachados - reemplazar',
              ),
              ServiceQuestionOption(
                value: 'replace',
                label: 'Ya reemplazados',
              ),
            ],
            sortOrder: 0,
          ),
        ],
      );

      final normalized = ServiceWizardService.normalizeProfile(profile)!;
      final question = normalized.questions.single;

      expect(question.label, 'Estado cables y fundas');
      expect(
        question.options.map((option) => option.value).toList(growable: false),
        const [
          'ok',
          'high_friction',
          'frayed',
          'corroded',
          'housing_damaged',
          'replace',
        ],
      );
      expect(
        question.options.map((option) => option.label).toList(growable: false),
        const [
          'Funcionamiento suave / sin resistencia anormal',
          'Alta friccion / recorrido duro',
          'Deshilachado',
          'Corrosion visible',
          'Funda danada / colapsada',
          'Danio severo / recambio necesario',
        ],
      );
    });

    test('normalizes drivetrain cable condition aliases to canonical values',
        () {
      const profile = ServiceWizardProfile(
        id: 'profile-2',
        name: 'Derailleur adjustment',
        serviceFamily: 'drivetrain',
        questions: [
          ServiceProfileQuestion(
            id: 'question-2',
            key: 'cable_condition',
            label: 'Estado cables y fundas',
            questionType: 'single_select',
            isRequired: false,
            isAdvanced: false,
            options: [
              ServiceQuestionOption(
                value: 'high_friction',
                label: 'Alta friccion / recorrido duro',
              ),
            ],
            sortOrder: 0,
          ),
        ],
      );

      final normalizedAnswers = ServiceWizardService.normalizeAnswersForProfile(
        profile,
        const {'cable_condition': 'hard'},
      );

      expect(normalizedAnswers['cable_condition'], 'high_friction');
    });
  });
}
