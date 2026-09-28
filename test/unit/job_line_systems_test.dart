import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_line_systems.dart';

void main() {
  const none = BikeMemoryLocation.none;

  test('un servicio con perfil va a su familia, con la rueda de la línea', () {
    expect(
      jobLineSystem(serviceFamily: 'brakes', location: BikeMemoryLocation.rear),
      JobLineSystem.rearBrake,
    );
    expect(jobLineSystem(serviceFamily: 'wheels', location: none),
        JobLineSystem.wheels);
    expect(jobLineSystem(serviceFamily: 'bottom_bracket', location: none),
        JobLineSystem.drivetrain,
        reason: 'el pedalier va con la transmisión, como en la tienda');
  });

  test('un repuesto va al segundo nivel de su categoría', () {
    expect(
      jobLineSystem(
        categoryPath: 'Componentes / Ruedas / Mazas / Maza',
        location: BikeMemoryLocation.front,
      ),
      JobLineSystem.frontWheel,
    );
    expect(
      jobLineSystem(
          categoryPath: 'Componentes / Cambios / Shifters', location: none),
      JobLineSystem.drivetrain,
    );
    expect(
      jobLineSystem(categoryPath: 'Accesorios / Puños', location: none),
      JobLineSystem.cockpit,
    );
    expect(
      jobLineSystem(categoryPath: 'Accesorios / Pedales', location: none),
      JobLineSystem.drivetrain,
    );
    expect(
      jobLineSystem(
          categoryPath: 'Mantenimiento / Líquido Frenos', location: none),
      JobLineSystem.brakes,
    );
    expect(
      jobLineSystem(categoryPath: 'Accesorios / Luces', location: none),
      JobLineSystem.accessories,
    );
  });

  test('lo que no nombra un sistema es de la bici entera', () {
    expect(jobLineSystem(location: none), JobLineSystem.general,
        reason: '«Mecánica Básica» no tiene perfil ni categoría');
    expect(
      jobLineSystem(
          categoryPath: 'Componentes / Fundas y piolas', location: none),
      JobLineSystem.general,
      reason: 'una piola puede ser de freno o de cambio',
    );
    expect(
      jobLineSystem(serviceFamily: 'otra', location: none),
      JobLineSystem.general,
    );
  });

  test('los grupos siguen el orden de la bici y el de cada trabajo', () {
    final groups = groupJobLinesBySystem<String>(
      ['maza', 'mecánica', 'cadena', 'rayos'],
      (line) => switch (line) {
        'maza' || 'rayos' => JobLineSystem.rearWheel,
        'cadena' => JobLineSystem.drivetrain,
        _ => JobLineSystem.general,
      },
    );
    expect(
      [for (final group in groups) group.system],
      [
        JobLineSystem.general,
        JobLineSystem.drivetrain,
        JobLineSystem.rearWheel,
      ],
    );
    expect(groups.last.lines, ['maza', 'rayos']);
  });

  test('subir y bajar mueven dentro del grupo que se ve', () {
    // Lista del trabajo: 0 biela, 1 frenos, 2 maza, 3 enrayado.
    final groups = groupJobLinesBySystem<int>(
      [0, 1, 2, 3],
      (index) => switch (index) {
        0 => JobLineSystem.drivetrain,
        1 => JobLineSystem.brakes,
        _ => JobLineSystem.wheels,
      },
    );
    expect(jobLineGroupNeighbors(groups, 2), (previous: null, next: 3),
        reason: 'la maza encabeza Ruedas aunque en la lista la preceda frenos');
    expect(jobLineGroupNeighbors(groups, 3), (previous: 2, next: null));
    expect(jobLineGroupNeighbors(groups, 1), (previous: null, next: null));
  });
}
