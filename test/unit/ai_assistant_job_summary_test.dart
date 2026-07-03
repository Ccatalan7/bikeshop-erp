import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  group('AIAssistantService job summaries', () {
    test('summarizes jobs from today when the user asks for the day', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final service = AIAssistantService();

      final response = await service.sendMessage(
        'puedes hacerme un resumen de los trabajos del día?',
        jobs: [
          MechanicJob(
            id: 'job-today',
            tenantId: 'tenant',
            jobNumber: 'PG-TODAY',
            customerId: 'customer-today',
            arrivalDate: today.add(const Duration(hours: 9)),
            status: JobStatus.diagnostico,
            clientRequest: 'Revisar rueda trasera',
            totalCost: 38000,
          ),
          MechanicJob(
            id: 'job-old-active',
            tenantId: 'tenant',
            jobNumber: 'PG-OLD',
            customerId: 'customer-old',
            arrivalDate: today.subtract(const Duration(days: 6)),
            status: JobStatus.pendiente,
            clientRequest: 'Ajuste antiguo',
            totalCost: 4000,
          ),
        ],
      );

      expect(response.text, contains('Tienes 1 trabajo ingresado hoy.'));
      expect(response.text, contains('PG-TODAY'));
      expect(response.text, isNot(contains('PG-OLD')));
    });

    test('matches the Trabajos active filter for explicit active summaries',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final service = AIAssistantService();

      final response = await service.sendMessage(
        'dame un resumen de los trabajos activos',
        jobs: [
          MechanicJob(
            id: 'job-active',
            tenantId: 'tenant',
            jobNumber: 'PG-ACTIVE',
            customerId: 'customer-active',
            arrivalDate: today.subtract(const Duration(days: 1)),
            status: JobStatus.enCurso,
          ),
          MechanicJob(
            id: 'job-finished',
            tenantId: 'tenant',
            jobNumber: 'PG-FINISHED',
            customerId: 'customer-finished',
            arrivalDate: today,
            status: JobStatus.finalizado,
          ),
          MechanicJob(
            id: 'job-delivered-paid',
            tenantId: 'tenant',
            jobNumber: 'PG-DELIVERED',
            customerId: 'customer-delivered',
            arrivalDate: today,
            status: JobStatus.entregado,
            isInvoiced: true,
            isPaid: true,
          ),
          MechanicJob(
            id: 'job-cancelled',
            tenantId: 'tenant',
            jobNumber: 'PG-CANCELLED',
            customerId: 'customer-cancelled',
            arrivalDate: today,
            status: JobStatus.cancelado,
          ),
        ],
      );

      expect(response.text, contains('Tienes 2 trabajos activos.'));
      expect(response.text, contains('PG-ACTIVE'));
      expect(response.text, contains('PG-FINISHED'));
      expect(response.text, isNot(contains('PG-DELIVERED')));
      expect(response.text, isNot(contains('PG-CANCELLED')));
    });

    test('does not fall back to cached jobs for an empty current view',
        () async {
      final service = AIAssistantService();

      final response = await service.sendMessage(
        'dame un resumen de los trabajos activos',
        jobs: const [],
        jobsAreCurrentView: true,
        jobSummaryScopeLabel: 'trabajos activos',
      );

      expect(
        response.text,
        'No encontré trabajos en la vista actual para resumir ahora. Reabre la vista de Trabajos o actualiza la tabla para sincronizar el asistente.',
      );
    });

    test('does not use cache fallback when the toolbar has no job context',
        () async {
      final service = AIAssistantService();

      final response = await service.sendMessage(
        'dame un resumen de los trabajos activos',
        jobs: const [],
        allowJobCacheFallback: false,
      );

      expect(
        response.text,
        'No encontré trabajos en la vista actual para resumir ahora. Reabre la vista de Trabajos o actualiza la tabla para sincronizar el asistente.',
      );
    });

    test('excludes test jobs from global active summaries by default',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final service = AIAssistantService();

      final response = await service.sendMessage(
        'hazme un resumen de los trabajos activos',
        jobs: [
          MechanicJob(
            id: 'job-real',
            tenantId: 'tenant',
            jobNumber: 'PG-REAL',
            customerId: 'customer-real',
            arrivalDate: today,
            status: JobStatus.diagnostico,
          ),
          MechanicJob(
            id: 'job-test',
            tenantId: 'tenant',
            jobNumber: 'PG-TEST',
            customerId: 'customer-test',
            arrivalDate: today,
            status: JobStatus.pendiente,
            notes: 'dummy sandbox job',
          ),
        ],
      );

      expect(response.text, contains('Tienes 1 trabajo activo.'));
      expect(response.text, contains('PG-REAL'));
      expect(response.text, isNot(contains('PG-TEST')));
      expect(response.text, isNot(contains('Pendiente: 1')));
    });

    test('uses custom visible status labels instead of legacy defaults',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final service = AIAssistantService();

      final response = await service.sendMessage(
        'dame un resumen de los trabajos activos',
        jobs: [
          MechanicJob(
            id: 'job-custom-status',
            tenantId: 'tenant',
            jobNumber: 'PG-CUSTOM',
            customerId: 'customer-custom',
            arrivalDate: today,
            status: JobStatus.pendiente,
            customStatus: JobStatusCustom(
              tenantId: 'tenant',
              name: 'COMENZAR',
              code: 'comenzar',
            ),
          ),
        ],
        jobsAreCurrentView: true,
        jobSummaryScopeLabel: 'trabajos activos',
      );

      expect(response.text, contains('COMENZAR: 1'));
      expect(response.text, isNot(contains('Pendiente: 1')));
    });
  });
}
