import 'package:timezone/timezone.dart' as tz;
import 'package:vinabike_public_core/shared/utils/shop_zone.dart';

/// «hoy a las 09:30», «mañana a las 09:30», «el lunes 23 a las 09:30» o
/// «el 3 de diciembre a las 09:30», en la hora de la tienda: lo mismo que
/// dice el aviso de la base (`supplier_order_when_text_internal`).
String supplierOrderWhenLabel(DateTime at, {DateTime? now}) {
  final local = tz.TZDateTime.from(at.toUtc(), shopLocation());
  final today =
      tz.TZDateTime.from((now ?? DateTime.now()).toUtc(), shopLocation());
  final day = DateTime(local.year, local.month, local.day);
  final base = DateTime(today.year, today.month, today.day);
  final days = day.difference(base).inDays;
  final hour =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (days == 0) return 'hoy a las $hour';
  if (days == 1) return 'mañana a las $hour';
  if (days > 1 && days < 7) {
    return 'el ${_weekdays[local.weekday - 1]} ${local.day} a las $hour';
  }
  return 'el ${local.day} de ${_months[local.month - 1]} a las $hour';
}

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
