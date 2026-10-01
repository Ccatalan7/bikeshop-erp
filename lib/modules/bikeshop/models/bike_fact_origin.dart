/// De dónde vino un dato de la ficha, en palabras del taller.
///
/// `technical_profile.sources` guarda un código por dato (`catalog`,
/// `mechanic`, `job_completion`…). La ficha lo mostraba crudo —«Fuente:
/// catalog»—, y un dato trazable tiene que decir de qué modelo o de qué
/// revisión vino (criterio 1 del Master, C1/C4 2026-09-30).
///
/// `catalogModel` nombra el modelo del catálogo que sembró la ficha («Trek
/// Marlin 7 2024»), y sólo desde la entrada enlazada por `catalogBikeId`: la
/// marca, el modelo y el año de la bici son editables y no prueban de qué
/// modelo vinieron los datos. Sin esa entrada, el origen es genérico. Un código
/// que no se reconoce devuelve `null`: la ficha no muestra jerga interna, y la
/// confirmación se dice aparte.
String? bikeFactOriginLabel(String? source, {String? catalogModel}) {
  final model = catalogModel?.trim();
  switch (source?.trim()) {
    case 'catalog':
      return model == null || model.isEmpty
          ? 'Del modelo en el catálogo'
          : 'Del modelo $model';
    case 'bike_type':
      return 'Sugerido por el tipo de bici';
    // Lo que el mecánico anota en el formulario o en un servicio. Anotar no
    // prueba confirmación: esa se dice aparte, desde `confirmed`.
    case 'mechanic':
      return 'Anotado en el taller';
    case 'job_completion':
      return 'Instalado en un trabajo terminado';
    case 'intake':
      return 'Anotado al recibir la bici';
    case 'manual':
      return 'Anotado a mano';
    default:
      return null;
  }
}

/// El origen con su estado. Lo sembrado o anotado que nadie confirmó lo dice
/// («Del modelo Trek Marlin 7 2024 · sin confirmar»); sin origen conocido no
/// hay leyenda.
String? bikeFactOriginCaption(
  String? source, {
  required bool confirmed,
  String? catalogModel,
}) {
  final origin = bikeFactOriginLabel(source, catalogModel: catalogModel);
  if (origin == null) return null;
  return confirmed ? origin : '$origin · sin confirmar';
}

/// El modelo del catálogo tal como lo dice el taller: marca, modelo y año,
/// sin partes vacías.
String? bikeCatalogModelLabel({
  String? brand,
  String? model,
  int? year,
}) {
  final parts = [
    brand?.trim(),
    model?.trim(),
    if (year != null && year > 0) '$year',
  ].whereType<String>().where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? null : parts.join(' ');
}
