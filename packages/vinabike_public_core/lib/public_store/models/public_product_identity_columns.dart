/// The public columns a catalog listing row is completed with before it
/// becomes a card: set identity and the product's own website and Merchant
/// fields (`website_merchant_title` wins over `website_name` in
/// `PublicCommerceProductProjection`).
///
/// `get_public_products_faceted_v2` does not return them. The Flutter store
/// (`PublicInventoryService._attachSetIdentity`) and the HTML storefront read
/// them with this one list since 2026-10-05; before that the HTML cards showed
/// the website name where Flutter showed the commercial title.
const publicProductIdentityColumns =
    'id,is_set,set_type,parent_set_id,component_label,component_position,'
    'website_name,website_price,website_description,'
    'website_seo_title,website_seo_description,'
    'website_merchant_title,website_merchant_description,'
    'website_merchant_brand,website_merchant_gtin,website_merchant_mpn,'
    'website_google_product_category,price_currency';
