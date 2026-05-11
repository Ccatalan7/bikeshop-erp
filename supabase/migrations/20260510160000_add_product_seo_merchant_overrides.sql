-- Website SEO and Google Merchant override fields for products.
-- All fields are optional; public surfaces fall back to the normal product data.

alter table public.products
  add column if not exists website_seo_title text,
  add column if not exists website_seo_description text,
  add column if not exists website_search_terms text[] not null default array[]::text[],
  add column if not exists website_merchant_title text,
  add column if not exists website_merchant_description text,
  add column if not exists website_merchant_brand text,
  add column if not exists website_merchant_gtin text,
  add column if not exists website_merchant_mpn text,
  add column if not exists website_google_product_category text;
