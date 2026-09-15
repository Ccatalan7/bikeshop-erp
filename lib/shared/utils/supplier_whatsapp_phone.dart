/// A qué número se le escribe por WhatsApp a un proveedor.
///
/// Un proveedor guarda dos teléfonos: el **vendedor** (`sales_rep_phone`, la
/// persona a la que se le escribe) y el **Teléfono** general de la ficha
/// (`phone`). El vendedor manda; el Teléfono es el respaldo cuando no hay
/// vendedor con número. Es la misma regla que el catálogo de compras aplica en
/// SQL (`coalesce(sales_rep_phone, phone)`), así que todas las superficies
/// —panel rápido de proveedores, chat, asistente de compras— apuntan al mismo
/// número.
///
/// **El defecto que esto no arregla solo (2026-09-02).** La ficha nueva de
/// proveedores dejó de mostrar y de guardar al vendedor, así que el número
/// quedó congelado y el dueño no tenía dónde cambiarlo: editaba el Teléfono y
/// el WhatsApp seguía apuntando al vendedor antiguo. La regla no cambia; lo
/// que se repuso es el campo Vendedor en la ficha.
///
/// Un número «usable» tiene al menos 8 dígitos; no se valida más porque hay
/// proveedores extranjeros.
String? supplierWhatsAppPhone({String? phone, String? salesRepPhone}) {
  for (final candidate in <String?>[salesRepPhone, phone]) {
    if (supplierPhoneIsUsable(candidate)) return candidate!.trim();
  }
  return null;
}

/// Al menos 8 dígitos.
bool supplierPhoneIsUsable(String? raw) => supplierPhoneDigits(raw).length >= 8;

/// Sólo los dígitos, sin `+`, espacios ni guiones.
String supplierPhoneDigits(String? raw) =>
    raw?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';

/// Si un hilo de WhatsApp corre por otro número que el registrado del
/// proveedor. Pasa cuando cambió el vendedor y el hilo viejo sigue en la
/// bandeja: el ERP le escribiría al registrado, pero ese chat va al anterior.
/// Se comparan sólo los dígitos; sin dos números usables no hay diferencia
/// que declarar.
bool supplierThreadPhoneDiffers({
  required String? threadPhone,
  required String? registeredPhone,
}) {
  if (!supplierPhoneIsUsable(threadPhone) ||
      !supplierPhoneIsUsable(registeredPhone)) {
    return false;
  }
  return supplierPhoneDigits(threadPhone) !=
      supplierPhoneDigits(registeredPhone);
}

/// Quién es la persona detrás de un hilo de proveedor, para ponerla junto al
/// nombre de la empresa en la bandeja («Comercial Ciclo · Fabiola»).
///
/// Dos hilos del mismo proveedor se veían idénticos: el viejo con la vendedora
/// anterior y el nuevo con el vendedor vigente (2026-09-02). El vínculo de
/// WhatsApp guarda el nombre de perfil de quien escribió; si el hilo se abrió
/// desde el ERP guarda el nombre de la empresa, que no es una persona. Cuando
/// el número del hilo es el del vendedor registrado, la persona es él aunque
/// todavía no haya contestado.
String? supplierContactPersonName({
  required String? supplierName,
  required String? bindingContactName,
  required String? threadPhone,
  required String? salesRepName,
  required String? salesRepPhone,
}) {
  final rep = salesRepName?.trim();
  if (rep != null &&
      rep.isNotEmpty &&
      supplierPhoneIsUsable(threadPhone) &&
      supplierPhoneIsUsable(salesRepPhone) &&
      supplierPhoneDigits(threadPhone) == supplierPhoneDigits(salesRepPhone)) {
    return rep;
  }
  final contact = bindingContactName?.trim();
  if (contact == null || contact.isEmpty) return null;
  final company = supplierName?.trim().toLowerCase();
  if (company != null && contact.toLowerCase() == company) return null;
  // Un número guardado como nombre tampoco es una persona.
  if (contact.replaceAll(RegExp(r'[\s+\-().]'), '') ==
      supplierPhoneDigits(contact)) {
    return null;
  }
  return contact;
}
