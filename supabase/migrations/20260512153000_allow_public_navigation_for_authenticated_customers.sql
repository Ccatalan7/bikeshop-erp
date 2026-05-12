-- Allow both anonymous visitors and authenticated storefront customers to read
-- visible website navigation. Logged-in website customers do not have ERP
-- user_profiles rows, so the tenant-scoped authenticated policy alone is not
-- enough for public-store header/menu rendering.

drop policy if exists "website_navigation_select_public" on public.website_navigation;

create policy "website_navigation_select_public" on public.website_navigation
  for select
  to public
  using (is_visible = true);