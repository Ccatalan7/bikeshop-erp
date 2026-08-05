import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

/// Every turn now carries the authority its rows must belong to. These jobs are
/// built for tenant `tenant`, so the summaries below are asked for under that
/// same authority; a mismatch is what the isolation suites cover.
final _authority = AIAssistantTurnAuthority(
  ErpAuthorityScopeKey.from(userId: 'user-test', tenantId: 'tenant')!,
  permissions: const <String>{AIToolPermission.operationalRead},
);

void main() {
  group('AIAssistantService job summaries', () {
    test('today follows Chile when Los Angeles is still on the prior date',
        () async {
      // 2026-08-03 23:30 in Los Angeles is already 2026-08-04 02:30 in
      // Santiago. Device-local date matching would select the wrong jobs.
      final now = DateTime.utc(2026, 8, 4, 6, 30);
      final service = AIAssistantService(now: () => now);

      final response = await service.sendMessage(
        authority: _authority,
        'puedes hacerme un resumen de los trabajos del día?',
        jobs: [
          MechanicJob(
            id: 'job-today',
            tenantId: 'tenant',
            jobNumber: 'PG-TODAY',
            customerId: 'customer-today',
            arrivalDate: DateTime.utc(2026, 8, 4, 6),
            status: JobStatus.diagnostico,
            clientRequest: 'Revisar rueda trasera',
            totalCost: 38000,
          ),
          MechanicJob(
            id: 'job-old-active',
            tenantId: 'tenant',
            jobNumber: 'PG-OLD',
            customerId: 'customer-old',
            arrivalDate: DateTime.utc(2026, 8, 4, 3, 30),
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
        authority: _authority,
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
        authority: _authority,
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

    test('missing toolbar context is unavailable, not a verified zero',
        () async {
      final service = AIAssistantService();

      final response = await service.sendMessage(
        authority: _authority,
        'dame un resumen de los trabajos activos',
        jobs: const [],
        allowJobCacheFallback: false,
      );

      expect(response.text, contains('no se pudo confirmar'));
      expect(response.text.toLowerCase(), isNot(contains('no encontré')));
    });

    test('excludes test jobs from global active summaries by default',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final service = AIAssistantService();

      final response = await service.sendMessage(
        authority: _authority,
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
        authority: _authority,
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
