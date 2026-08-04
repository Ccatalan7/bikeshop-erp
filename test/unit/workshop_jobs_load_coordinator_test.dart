import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_jobs_load_coordinator.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

/// Gestión de Trabajos: la carga más reciente es la única que habla.
///
/// El coworker recibía el banner rojo «Error: ERP authority scope changed
/// during load». Ese texto es el resultado TIPADO de una lectura que quedó
/// obsoleta — el guardarraíl que impide publicar datos de otra autoridad — y
/// la tabla lo convertía en error de usuario porque su `catch (e)` es anterior
/// al cache authority-scoped y porque ninguna carga era dueña de las otras.
void main() {
  group('latest ticket wins', () {
    test('una carga anterior deja de poder publicar cuando otra empieza', () {
      final coordinator = WorkshopJobsLoadCoordinator();

      final a = coordinator.start();
      expect(a.isCurrent, isTrue);

      final b = coordinator.start();

      expect(a.isCurrent, isFalse, reason: 'A ya no manda');
      expect(a.isSuperseded, isTrue);
      expect(
        b.isCurrent,
        isTrue,
        reason: 'la respuesta nueva sí pinta la tabla',
      );
    });

    test('el orden de llegada no cambia quién manda', () {
      final coordinator = WorkshopJobsLoadCoordinator();
      final first = coordinator.start();
      final second = coordinator.start();
      final third = coordinator.start();

      // Llegan desordenadas: tercera, primera, segunda.
      expect(third.isCurrent, isTrue);
      expect(first.isCurrent, isFalse);
      expect(second.isCurrent, isFalse);
    });

    test('dispose invalida cualquier ticket vivo', () {
      final coordinator = WorkshopJobsLoadCoordinator();
      final live = coordinator.start();
      expect(live.isCurrent, isTrue);

      coordinator.dispose();

      expect(
        live.isCurrent,
        isFalse,
        reason: 'una respuesta que llega con la página cerrada no posee nada',
      );
      expect(coordinator.hasCurrentLoad, isFalse);
      // Y un ticket pedido después tampoco resucita al coordinador.
      expect(coordinator.start().isCurrent, isFalse);
    });
  });

  group('qué es un fallo y qué es una cancelación', () {
    test('el resultado tipado de autoridad NO es un error del operador', () {
      expect(
        WorkshopJobsLoadCoordinator.isSupersededError(
          const AuthorityScopeChangedException(),
        ),
        isTrue,
      );
    });

    test('cualquier otro error sí lo es', () {
      for (final error in <Object>[
        StateError('no se pudo leer la factura'),
        Exception('timeout'),
        ArgumentError('id vacío'),
      ]) {
        expect(
          WorkshopJobsLoadCoordinator.isSupersededError(error),
          isFalse,
          reason: '$error tiene que seguir llegando al operador',
        );
      }
    });
  });

  group('el cableado de _loadData respeta el contrato', () {
    // El wiring vive en un `State` privado de una página que no se puede
    // montar sin Supabase, providers y rutas; lo que se afirma aquí es el
    // contrato exacto que la corrección introduce, sobre el código real.
    final source = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();

    test('cada carga toma un ticket antes de tocar la pantalla', () {
      expect(source, contains('final ticket = _jobsLoadCoordinator.start();'));
      expect(
        source,
        contains('_jobsLoadCoordinator.dispose();'),
        reason: 'dispose invalida el ticket vivo',
      );
    });

    test('una respuesta vieja no publica', () {
      final loadData = source.substring(
        source.indexOf('Future<void> _loadData({'),
        source.indexOf('Future<List<Invoice>> _loadInvoices('),
      );
      final publishGuard = loadData.indexOf('if (ticket.isSuperseded) return;');
      final publishState = loadData.indexOf('_jobs = jobs;');
      expect(publishGuard, greaterThan(-1));
      expect(
        publishGuard,
        lessThan(publishState),
        reason: 'la guarda va ANTES de escribir la tabla',
      );
    });

    test('el resultado tipado se separa antes del catch genérico', () {
      final loadData = source.substring(
        source.indexOf('Future<void> _loadData({'),
        source.indexOf('Future<List<Invoice>> _loadInvoices('),
      );
      final catchStart = loadData.indexOf('} catch (e) {');
      final staleGuard =
          loadData.indexOf('if (ticket.isSuperseded) return;', catchStart);
      final classified = loadData.indexOf(
        'WorkshopJobsLoadCoordinator.isSupersededError(e)',
      );
      final surfaced = loadData.indexOf('showSnackBar');
      final rethrown = loadData.indexOf('if (rethrowErrors) rethrow;');

      expect(catchStart, greaterThan(-1));
      expect(staleGuard, greaterThan(catchStart),
          reason: 'una carga vieja se descarta antes de clasificar nada');
      expect(classified, greaterThan(staleGuard));
      expect(
        classified,
        lessThan(surfaced),
        reason: 'se clasifica antes de decidir si se muestra',
      );
      // 1 · la cancelación tipada del ticket ACTUAL termina el cargando y
      //     vuelve: ni banner, ni rethrow — ni siquiera con rethrowErrors.
      final typedBranch = loadData.substring(classified, surfaced);
      expect(typedBranch, contains('setState(() => _isLoading = false)'));
      expect(typedBranch, contains('return;'));
      expect(
        typedBranch,
        isNot(contains('rethrow')),
        reason: 'relanzarla sólo movía la misma frase interna a otro catch',
      );
      expect(
        typedBranch,
        isNot(contains('_jobs =')),
        reason: 'la tabla visible no se vacía al cancelar',
      );
      // 3 · el único rethrow que queda vive después del banner, es decir en la
      //     rama del fallo REAL del ticket actual.
      expect(rethrown, greaterThan(surfaced));
      expect(
        'rethrow;'.allMatches(loadData).length,
        1,
        reason: 'un solo camino puede propagar, y es el del error real',
      );
    });

    test('_onBikeshopServiceChanged sigue siendo la ruta quirúrgica', () {
      final handler = source.substring(
        source.indexOf('void _onBikeshopServiceChanged() {'),
        source.indexOf('void _refreshFromCache() {'),
      );
      // Realtime repinta desde el cache; sólo cae a la carga completa cuando
      // no hay cache que repintar.
      expect(handler, contains('if (_bikeshopService.hasJobsCache) {'));
      expect(handler, contains('_refreshFromCache();'));
      expect(
        '_loadData()'.allMatches(handler).length,
        1,
        reason: 'la única carga completa es el fallback de cache vacío',
      );

      final refresh = source.substring(
        source.indexOf('void _refreshFromCache() {'),
        source.indexOf('void _startLocalOperation() {'),
      );
      for (final fetch in const <String>[
        'getJobs(',
        'getBikes(',
        'getCustomers(',
        'getAllJobBikes(',
        'Supabase.instance',
        'await ',
      ]) {
        expect(
          refresh.contains(fetch),
          isFalse,
          reason: '_refreshFromCache no puede volver a la base por "$fetch"',
        );
      }
      expect(refresh, contains('_bikeshopService.cachedJobs'));
      // Y la corrección no le puso un ticket: la ruta quirúrgica no pasa por
      // el coordinador y queda intacta.
      expect(refresh, isNot(contains('_jobsLoadCoordinator')));
      expect(handler, isNot(contains('_jobsLoadCoordinator')));
    });

    test('un refresco no vacía la tabla que ya se ve', () {
      final loadData = source.substring(
        source.indexOf('Future<void> _loadData({'),
        source.indexOf('Future<List<Invoice>> _loadInvoices('),
      );
      expect(
        loadData,
        contains('} else if (_jobs.isEmpty) {\n      setState(() '
            '=> _isLoading = true);'),
        reason: 'sólo se muestra el cargando cuando no hay nada que conservar',
      );
    });

    test('la corrección no reintenta ni relaja la autoridad', () {
      // Sólo el código: un comentario que EXPLICA por qué no hay reintento no
      // puede hacer fallar la guarda que prohíbe el reintento.
      final coordinator = File(
        'lib/modules/bikeshop/services/workshop_jobs_load_coordinator.dart',
      ).readAsStringSync().split('\n').map((line) {
        final comment = line.indexOf('//');
        return comment == -1 ? line : line.substring(0, comment);
      }).join('\n');
      for (final forbidden in const <String>[
        'retry',
        'Timer',
        'Future.delayed',
        'tenantId',
        'userId',
      ]) {
        expect(
          coordinator.contains(forbidden),
          isFalse,
          reason: 'el coordinador no puede saber de "$forbidden": sólo dice '
              'quién manda, y la autoridad la sigue guardando el cache',
        );
      }
    });
  });
}
