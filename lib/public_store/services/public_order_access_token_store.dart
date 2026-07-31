import '../../modules/website/models/public_order_access.dart';
import 'checkout_session_store.dart';

/// Compatibility façade over the single durable checkout authority.
///
/// New code can call [CheckoutSessionStore.saveOrderAccess] directly. Keeping
/// this small instance wrapper avoids reintroducing the former static
/// memory/sessionStorage split, which lost valid native credentials after the
/// checkout receipt was retired.
class PublicOrderAccessTokenStore {
  const PublicOrderAccessTokenStore(this._sessions);

  final CheckoutSessionStore _sessions;

  Future<void> save({
    required String tenantId,
    required PublicOrderCheckoutAccess access,
  }) =>
      _sessions.saveOrderAccess(
        tenantId: tenantId,
        access: access,
      );

  Future<PublicOrderCheckoutAccess?> read({
    required String tenantId,
    required String orderId,
  }) =>
      _sessions.readOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      );

  Future<void> forget({
    required String tenantId,
    required String orderId,
  }) =>
      _sessions.forgetOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      );
}
