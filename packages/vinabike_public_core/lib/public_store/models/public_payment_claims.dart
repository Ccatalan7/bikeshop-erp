import 'public_checkout_capabilities.dart';

/// The only payment claims this storefront can make.
///
/// Deliberately limited to what `PublicCheckoutCapabilities` can actually
/// confirm. Card networks are absent by design: the server contract exposes
/// `mercadopago` and `transfer` only, so a Visa/Mastercard/Redcompra badge
/// could never be backed by evidence — it would be inferred from the mere
/// presence of a card processor, which is exactly the invented claim this
/// surface exists to prevent.
const Map<PublicCheckoutPaymentCode, ({String label, String? imageUrl})>
    kPublicStorePaymentClaims = {
  PublicCheckoutPaymentCode.mercadopago: (
    label: 'MercadoPago',
    imageUrl:
        'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/mercadopago.svg',
  ),
  // Bank transfer has no third-party mark to display, so it is stated with
  // this application's own generic icon and wording.
  PublicCheckoutPaymentCode.transfer: (
    label: 'Transferencia bancaria',
    imageUrl: null,
  ),
};

/// Projects the server-confirmed methods into footer claims.
///
/// A `null` capability set means loading or failed — both are *unknown*, and
/// unknown must show nothing rather than a stale or optimistic list.
List<PublicCheckoutPaymentCode> resolvePublicPaymentClaims(
  PublicCheckoutCapabilities? capabilities,
) {
  if (capabilities == null) return const <PublicCheckoutPaymentCode>[];
  return capabilities.availableMethods
      .where(kPublicStorePaymentClaims.containsKey)
      .toList(growable: false);
}
