import '../models/intelligent_purchasing_models.dart';

/// Si con lo que hay leído se puede **comprometer una compra**.
///
/// **No saber no es un permiso.** El 2026-08-31, con la sesión autenticada,
/// `supply_need_stock_bundle_internal_v1` respondió `500 / 57014` —statement
/// timeout— mientras el resto de las consultas respondía 200. La pantalla se
/// vaciaba entera, y ése era el defecto visible; pero el defecto peligroso es
/// el contrario: dejar la evidencia del proveedor a la vista y permitir que
/// alguien mande el pedido **sin haber podido mirar la bodega**. El paso de
/// stock existe justamente para impedir comprar lo que ya está en la tienda.
///
/// Por eso la frontera tiene dos mitades y son distintas:
///
/// - **Mirar y refiltrar sí**: los proveedores y el recibo del portal no le
///   preguntan nada a la bodega, ya costaron minutos de navegación real, y
///   volver a juzgarlos es local.
/// - **Comprometer no**: sumar una línea al plan, guardar el pedido o mandarlo.
///
/// `resolution == null` es «no se pudo leer», no «no hay stock»: una lectura
/// que respondió con cobertura cero **sí** autoriza, porque ahí sí se sabe.
bool supplyPurchaseAuthorized({
  required bool hasSelectedNeed,
  required SupplyStockResolution? resolution,
}) =>
    !hasSelectedNeed || resolution != null;

/// Lo que se le dice al operador cuando pide comprar sin bodega leída.
///
/// Nombra la causa y la salida. «No se pudo completar el análisis» no decía ni
/// qué falló ni qué seguía sirviendo.
const String kSupplyStockUnreadBlockMessage =
    'No se pudo leer la bodega, así que no se sabe qué hay en stock. '
    'Reintenta esa lectura antes de comprometer una compra.';
