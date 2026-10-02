import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_directory_entries.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_visit_history.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_line_systems.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_silhouette.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';

const _tenant = 'tenant-1';

JobStatusCustom _status(String code, String name, StatusPhase phase,
        {bool delivery = false, String color = '#6B7280'}) =>
    JobStatusCustom(
      id: 'status-$code',
      tenantId: _tenant,
      name: name,
      code: code,
      color: color,
      phase: phase,
      triggersDelivery: delivery,
    );

final _pending = _status('PENDIENTE', 'Pendiente', StatusPhase.todo);
final _parts =
    _status('ESPERANDO_REPUESTOS', 'REPUESTOS', StatusPhase.inProgress);
final _finished = _status('FINALIZADO', 'Terminado', StatusPhase.complete);
final _delivered =
    _status('ENTREGADO', 'Entregado', StatusPhase.complete, delivery: true);
final _cancelled = _status('CANCELADO', 'Cancelado', StatusPhase.complete);

Bike _bike(String id, {String? color, BikeType? type}) => Bike(
      id: id,
      tenantId: _tenant,
      customerId: 'customer-$id',
      brand: 'Trek',
      model: 'Marlin $id',
      color: color,
      bikeType: type ?? BikeType.mountainHardtail,
    );

MechanicJob _job(
  String id, {
  String? bikeId,
  required JobStatusCustom status,
  required DateTime arrival,
  DateTime? completed,
  DateTime? delivered,
  double total = 0,
  String? request,
}) =>
    MechanicJob(
      id: id,
      tenantId: _tenant,
      jobNumber: 'PG-$id',
      customerId: 'customer-x',
      bikeId: bikeId,
      intakeKind: JobIntakeKind.bike,
      status: JobStatus.fromDbValue(status.code),
      statusId: status.id,
      customStatus: status,
      arrivalDate: arrival,
      completedAt: completed,
      deliveredAt: delivered,
      totalCost: total,
      clientRequest: request,
    );

MechanicJobBike _jobBike(String id, String jobId, String bikeId,
        {String? request}) =>
    MechanicJobBike(
      id: id,
      tenantId: _tenant,
      jobId: jobId,
      bikeId: bikeId,
      workRequested: request,
    );

MechanicJobItem _item(
  String jobId,
  String name,
  double price, {
  String? jobBikeId,
  String? systemKey,
  String type = 'product',
}) =>
    MechanicJobItem(
      tenantId: _tenant,
      jobId: jobId,
      jobBikeId: jobBikeId,
      productName: name,
      unitPrice: price,
      totalPrice: price,
      systemKey: systemKey,
      itemType: type,
    );

Customer _customer(String id, String name) =>
    Customer(id: id, tenantId: _tenant, name: name, rut: '');

void main() {
  group('bikePaintFromText reads the colour as the workshop wrote it', () {
    test('one colour, any gender or case', () {
      expect(bikePaintFromText('negra')?.primary,
          bikePaintFromText('Negro')?.primary);
      expect(bikePaintFromText('negra')?.secondary, isNull);
    });

    test('two colours paint the rear triangle with the second', () {
      final paint = bikePaintFromText('negra/verde');
      expect(paint?.secondary, isNotNull);
      expect(paint?.primary, bikePaintFromText('negro')?.primary);
      expect(paint?.secondary, bikePaintFromText('verde')?.primary);
      expect(bikePaintFromText('negra con rosado')?.secondary,
          bikePaintFromText('rosa')?.primary);
    });

    test('a one-letter typo still reads', () {
      final plomo = bikePaintFromText('plmomo con naranjo');
      expect(plomo?.primary, bikePaintFromText('plomo')?.primary);
      expect(plomo?.secondary, bikePaintFromText('naranja')?.primary);
      expect(bikePaintFromText('negro azukl')?.secondary,
          bikePaintFromText('azul')?.primary);
    });

    test('two-word colours win over their first word', () {
      expect(bikePaintFromText('Azul marino')?.primary,
          isNot(bikePaintFromText('azul')?.primary));
      expect(bikePaintFromText('rojo vino')?.primary,
          bikePaintFromText('burdeo')?.primary);
    });

    test('an exact word never turns into its neighbour', () {
      expect(bikePaintFromText('roja')?.primary,
          bikePaintFromText('rojo')?.primary);
      expect(bikePaintFromText('roja')?.primary,
          isNot(bikePaintFromText('rosa')?.primary));
    });

    test('no colour means no paint: the frame stays hollow', () {
      expect(bikePaintFromText(null), isNull);
      expect(bikePaintFromText(''), isNull);
      expect(bikePaintFromText('con calcomanías'), isNull);
    });
  });

  group('buildBikeDirectoryEntries', () {
    final today = DateTime(2026, 10, 2);
    final a = _bike('a', color: 'Negra');
    final b = _bike('b');
    final c = _bike('c');
    final test1 = Bike(
      id: 't',
      tenantId: _tenant,
      customerId: 'customer-test',
      brand: 'Test',
      model: '1',
    );
    final customers = {
      'customer-a': _customer('customer-a', 'Roldan Molina'),
      'customer-b': _customer('customer-b', 'Andrés Kroll'),
      'customer-c': _customer('customer-c', 'José Labra'),
      'customer-test': _customer('customer-test', 'Test'),
    };

    final jobs = [
      // Legacy single-bike job: only the header knows the bike.
      _job('1',
          bikeId: 'a',
          status: _delivered,
          arrival: DateTime(2026, 3, 6),
          delivered: DateTime(2026, 3, 27)),
      // Two bikes, the header names only one of them.
      _job('2',
          bikeId: 'b',
          status: _parts,
          arrival: DateTime(2026, 9, 25),
          total: 79000),
      _job('3',
          status: _finished,
          arrival: DateTime(2026, 9, 4),
          completed: DateTime(2026, 9, 16)),
      _job('4', bikeId: 'a', status: _cancelled, arrival: DateTime(2026, 9, 1)),
      _job('5', bikeId: 't', status: _pending, arrival: DateTime(2026, 10, 1)),
    ];
    final jobBikes = {
      '2': [_jobBike('jb2b', '2', 'b'), _jobBike('jb2c', '2', 'c')],
      '3': [_jobBike('jb3c', '3', 'c')],
    };

    final rows = {
      for (final row in buildBikeDirectoryEntries(
        bikes: [a, b, c, test1],
        customersById: customers,
        jobs: jobs,
        jobBikesByJobId: jobBikes,
      ))
        row.bike.id: row,
    };

    test('a job reaches every bike in its rows, and legacy jobs their header',
        () {
      expect(rows['a']!.visits, 1, reason: 'the cancelled job is no visit');
      expect(rows['a']!.latestJob?.id, '4');
      expect(rows['c']!.workshopJob?.id, '2',
          reason: 'job 2 holds bike c through mechanic_job_bikes');
      expect(rows['c']!.visits, 2);
    });

    test('test fixtures never count', () {
      expect(rows['t']!.latestJob, isNull);
      expect(rows['t']!.inWorkshop, isFalse);
    });

    test('the stage comes from the status phase, not its name', () {
      expect(rows['a']!.inWorkshop, isFalse);
      expect(rows['b']!.stage, BikeWorkshopStage.inProgress);
      expect(rows['b']!.waitingDays(today), 7);
    });

    test('ready for pickup waits from completion', () {
      final row = buildBikeDirectoryEntries(
        bikes: [c],
        customersById: customers,
        jobs: [jobs[2]],
        jobBikesByJobId: jobBikes,
      ).single;
      expect(row.stage, BikeWorkshopStage.readyForPickup);
      expect(row.waitingDays(today), 16);
    });

    test('Todas sorts by the latest visit; En el taller groups by stage', () {
      final sorted = sortByRecentVisit(rows.values);
      expect(sorted.first.bike.id, anyOf('b', 'c'));
      expect(sorted.last.bike.id, 't');
      final groups = groupInWorkshop(rows.values);
      expect(
          groups.map((group) => group.stage), [BikeWorkshopStage.inProgress]);
      expect(groups.single.rows.map((row) => row.bike.id).toSet(), {'b', 'c'});
    });

    test('shop status names in capitals read as a phrase', () {
      expect(jobStatusLabel(jobs[1]), 'Repuestos');
      expect(jobStatusLabel(jobs[2]), 'Terminado');
    });

    test('the search finds a bike by its owner and a word of the model', () {
      expect(
          bikeDirectorySearchScore(rows['b']!, 'kroll marlin'), greaterThan(0));
      expect(bikeDirectorySearchScore(rows['b']!, 'molina'), 0);
    });

    test('wheel sizes read as the workshop says them', () {
      expect(wheelSizeLabel('29"'), 'Aro 29');
      expect(wheelSizeLabel("27.5''"), 'Aro 27.5');
      expect(wheelSizeLabel('700'), '700c');
      expect(wheelSizeLabel(' '), isNull);
    });
  });

  group('buildBikeVisits', () {
    JobLineSystem systemOf(MechanicJobItem item) =>
        jobLineSystemFromKey(item.systemKey) ?? JobLineSystem.general;

    test('a bike gets its own lines; unassigned ones are a separate purchase',
        () {
      final job = _job('2',
          bikeId: 'b',
          status: _parts,
          arrival: DateTime(2026, 9, 25),
          total: 90000,
          request: 'Revisar todo');
      final visits = buildBikeVisits(
        bikeId: 'b',
        jobs: [job],
        jobBikesByJobId: {
          '2': [
            _jobBike('jb2b', '2', 'b', request: 'Cambiar pastillas'),
            _jobBike('jb2c', '2', 'c'),
          ],
        },
        itemsByJobId: {
          '2': [
            _item('2', 'Pastillas ZTTO', 9000,
                jobBikeId: 'jb2b', systemKey: 'brakes'),
            _item('2', 'Disco Shimano RT56', 25000,
                jobBikeId: 'jb2b', systemKey: 'brakes'),
            _item('2', 'Neumático CST', 20000,
                jobBikeId: 'jb2c', systemKey: 'wheels'),
            _item('2', 'Luz trasera', 6000),
          ],
        },
        systemOf: systemOf,
      );
      final visit = visits.single;
      expect(visit.amount, 34000,
          reason: 'with two bikes the amount is the sum of this bike lines');
      expect(visit.separatePurchaseAmount, 6000);
      expect(visit.request, 'Cambiar pastillas');
      expect(visit.groups.single.system, JobLineSystem.brakes);
      expect(visit.groups.single.lines.map((line) => line.name),
          ['Pastillas ZTTO', 'Disco Shimano RT56']);
      expect(visit.inWorkshop, isTrue);
    });

    test('a legacy job without bike rows belongs whole to its header bike', () {
      final job = _job('1',
          bikeId: 'a',
          status: _delivered,
          arrival: DateTime(2026, 3, 6),
          delivered: DateTime(2026, 3, 27),
          total: 230000,
          request: 'Cambio MT200 trasero');
      final visit = buildBikeVisits(
        bikeId: 'a',
        jobs: [job],
        jobBikesByJobId: const {},
        itemsByJobId: {
          '1': [
            _item('1', 'SunRace piñón M680', 25000, systemKey: 'drivetrain'),
            _item('1', 'Enrayado + centrado', 20000,
                systemKey: 'wheels', type: 'service'),
          ],
        },
        systemOf: systemOf,
      ).single;
      expect(visit.amount, 230000,
          reason: 'one bike and nothing apart: the job total is authoritative');
      expect(visit.groups.map((group) => group.system),
          [JobLineSystem.drivetrain, JobLineSystem.wheels]);
      expect(visit.groups.last.lines.single.isService, isTrue);
      expect(visit.inWorkshop, isFalse);
      expect(visit.daysInWorkshop(DateTime(2026, 10, 2)), 21);
    });

    test('other bikes and deleted jobs stay out; newest first', () {
      final visits = buildBikeVisits(
        bikeId: 'a',
        jobs: [
          _job('1',
              bikeId: 'a', status: _delivered, arrival: DateTime(2026, 3, 6)),
          _job('9',
              bikeId: 'z', status: _delivered, arrival: DateTime(2026, 4, 6)),
          _job('7',
              bikeId: 'a', status: _pending, arrival: DateTime(2026, 9, 6)),
        ],
        jobBikesByJobId: const {},
        itemsByJobId: const {},
        systemOf: systemOf,
      );
      expect(visits.map((visit) => visit.job.id), ['7', '1']);
    });

    test('a bike never takes the request of another bike of the same job', () {
      // The header keeps the first bike's request; bike c asked for nothing.
      final job = _job('2',
          bikeId: 'b',
          status: _parts,
          arrival: DateTime(2026, 9, 25),
          request: 'Cambiar pastillas');
      final rows = {
        '2': [
          _jobBike('jb2b', '2', 'b', request: 'Cambiar pastillas'),
          _jobBike('jb2c', '2', 'c'),
        ],
      };
      final forC = buildBikeVisits(
        bikeId: 'c',
        jobs: [job],
        jobBikesByJobId: rows,
        itemsByJobId: const {},
        systemOf: systemOf,
      ).single;
      expect(forC.request, isNull);

      // With only its own row, the header request is that bike's.
      final single = buildBikeVisits(
        bikeId: 'b',
        jobs: [job],
        jobBikesByJobId: {
          '2': [_jobBike('jb2b', '2', 'b')],
        },
        itemsByJobId: const {},
        systemOf: systemOf,
      ).single;
      expect(single.request, 'Cambiar pastillas');

      // One row, but the header names another bike: the request is not hers.
      final staleHeader = buildBikeVisits(
        bikeId: 'c',
        jobs: [job],
        jobBikesByJobId: {
          '2': [_jobBike('jb2c', '2', 'c')],
        },
        itemsByJobId: const {},
        systemOf: systemOf,
      ).single;
      expect(staleHeader.request, isNull);
    });

    test('a finished bike still in the shop counts its days until today', () {
      final visit = buildBikeVisits(
        bikeId: 'c',
        jobs: [
          _job('3',
              status: _finished,
              arrival: DateTime(2026, 9, 4),
              completed: DateTime(2026, 9, 16)),
        ],
        jobBikesByJobId: {
          '3': [_jobBike('jb3c', '3', 'c')],
        },
        itemsByJobId: const {},
        systemOf: systemOf,
      ).single;
      expect(visit.inWorkshop, isTrue);
      expect(visit.daysInWorkshop(DateTime(2026, 10, 2)), 28);
    });

    test('test jobs stay out with the same identity the directory uses', () {
      final jobs = [
        _job('5',
            bikeId: 't', status: _pending, arrival: DateTime(2026, 10, 1)),
        _job('6',
            bikeId: 't',
            status: _pending,
            arrival: DateTime(2026, 9, 1),
            request: '[test] revisar'),
      ];
      final ofTestOwner = buildBikeVisits(
        bikeId: 't',
        jobs: jobs,
        jobBikesByJobId: const {},
        itemsByJobId: const {},
        systemOf: systemOf,
        bike: _bike('t'),
        ownerName: 'Test',
      );
      expect(ofTestOwner, isEmpty);

      final ofRealOwner = buildBikeVisits(
        bikeId: 't',
        jobs: jobs,
        jobBikesByJobId: const {},
        itemsByJobId: const {},
        systemOf: systemOf,
        bike: _bike('t'),
        ownerName: 'Andrés Kroll',
      );
      expect(ofRealOwner.map((visit) => visit.job.id), ['5'],
          reason: 'a marked job is a test whoever owns the bike');
    });
  });
}
