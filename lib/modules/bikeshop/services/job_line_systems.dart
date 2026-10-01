/// El sistema de la bici al que pertenece una línea del trabajo (paso G1,
/// 2026-09-27): «Rueda trasera · 2 · $45.000».
///
/// No se adivina por el nombre de la línea. Sale de dos datos explícitos:
///
/// - un servicio con perfil trae su familia (`service_profiles.service_family`);
/// - un repuesto trae su categoría, y el segundo nivel del árbol de la tienda
///   ya es un sistema: «Componentes / Ruedas / Mazas / Maza».
///
/// Con datos de producción (120 días al 2026-09-27) el segundo nivel da sistema
/// a 221 de 253 repuestos y la familia a 168 de 260 servicios. Lo demás
/// —«Mecánica Básica», «Limpieza General», fundas y piolas (de freno o de
/// cambio), lubricantes— es trabajo sobre la bici entera y queda en «General».
/// La categoría heredada «Neumáticos», aun sin árbol vinculado, también
/// identifica una rueda. La posición (delantera o trasera) es la de la línea.
library;

import '../models/bikeshop_models.dart';

enum JobLineSystem {
  general('General'),
  drivetrain('Transmisión'),
  frontBrake('Freno delantero'),
  rearBrake('Freno trasero'),
  brakes('Frenos'),
  frontWheel('Rueda delantera'),
  rearWheel('Rueda trasera'),
  wheels('Ruedas'),
  cockpit('Dirección'),
  suspension('Suspensión'),
  accessories('Accesorios');

  const JobLineSystem(this.label);

  /// Cómo lo dice el taller.
  final String label;
}

/// El orden de los grupos es el de la declaración: primero lo que toca la bici
/// entera, después cada sistema de adelante hacia atrás.
JobLineSystem jobLineSystem({
  String? serviceFamily,
  String? categoryPath,
  required BikeMemoryLocation location,
}) {
  final family = _normalize(serviceFamily);
  if (family.isNotEmpty) {
    final fromFamily = switch (family) {
      'brake' || 'brakes' => _positioned(location, _Kind.brake),
      'wheels' || 'wheel' => _positioned(location, _Kind.wheel),
      // El pedalier va con la transmisión, como en el árbol de la tienda.
      'drivetrain' || 'bottom_bracket' => JobLineSystem.drivetrain,
      'cockpit' || 'headset' => JobLineSystem.cockpit,
      'suspension' => JobLineSystem.suspension,
      _ => null,
    };
    if (fromFamily != null) return fromFamily;
  }

  final segments = (categoryPath ?? '')
      .split('/')
      .map(_normalize)
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return JobLineSystem.general;
  final second = segments.length > 1 ? segments[1] : '';
  final fromCategory = switch ((segments.first, second)) {
    (_, 'transmision' || 'cambios' || 'groupset' || 'pedales') =>
      JobLineSystem.drivetrain,
    (_, 'frenos' || 'liquido frenos') => _positioned(location, _Kind.brake),
    ('neumaticos', _) ||
    (_, 'ruedas' || 'rueda estabilizadora' || 'neumaticos') =>
      _positioned(location, _Kind.wheel),
    (_, 'direccion' || 'punos') => JobLineSystem.cockpit,
    (_, 'shock' || 'suspension') => JobLineSystem.suspension,
    ('accesorios' || 'bmx', _) => JobLineSystem.accessories,
    _ => null,
  };
  return fromCategory ?? JobLineSystem.general;
}

enum _Kind { brake, wheel }

JobLineSystem _positioned(BikeMemoryLocation location, _Kind kind) =>
    switch ((kind, location)) {
      (_Kind.brake, BikeMemoryLocation.front) => JobLineSystem.frontBrake,
      (_Kind.brake, BikeMemoryLocation.rear) => JobLineSystem.rearBrake,
      (_Kind.brake, _) => JobLineSystem.brakes,
      (_Kind.wheel, BikeMemoryLocation.front) => JobLineSystem.frontWheel,
      (_Kind.wheel, BikeMemoryLocation.rear) => JobLineSystem.rearWheel,
      (_Kind.wheel, _) => JobLineSystem.wheels,
    };

String _normalize(String? raw) => (raw ?? '')
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');

/// Las líneas de un trabajo agrupadas por sistema, en el orden de
/// [JobLineSystem], conservando dentro de cada grupo el orden del trabajo.
List<({JobLineSystem system, List<T> lines})> groupJobLinesBySystem<T>(
  List<T> lines,
  JobLineSystem Function(T line) systemOf,
) {
  final bySystem = <JobLineSystem, List<T>>{};
  for (final line in lines) {
    bySystem.putIfAbsent(systemOf(line), () => []).add(line);
  }
  return [
    for (final system in JobLineSystem.values)
      if (bySystem[system] case final group?) (system: system, lines: group),
  ];
}

/// La línea anterior y la siguiente de [line] dentro de su grupo: «Subir» y
/// «Bajar» mueven ahí, porque la vecina en la lista del trabajo puede ser de
/// otro sistema y el cambio no se vería.
({T? previous, T? next}) jobLineGroupNeighbors<T>(
  List<({JobLineSystem system, List<T> lines})> groups,
  T line,
) {
  for (final group in groups) {
    final position = group.lines.indexOf(line);
    if (position < 0) continue;
    return (
      previous: position > 0 ? group.lines[position - 1] : null,
      next:
          position < group.lines.length - 1 ? group.lines[position + 1] : null,
    );
  }
  return (previous: null, next: null);
}
