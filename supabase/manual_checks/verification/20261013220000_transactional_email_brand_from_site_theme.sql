-- Read-back de 20261013220000: el correo encolado toma el color y las fuentes
-- del tema del editor del sitio.

select 1 / case
  when position(
     $$'brandColor'$$
     in pg_get_functiondef('public.enqueue_transactional_email_from_order_event_id(uuid)'::regprocedure)
   ) > 0
   and position(
     $$theme_heading_font$$
     in pg_get_functiondef('public.enqueue_transactional_email_from_order_event_id(uuid)'::regprocedure)
   ) > 0
  then 1 else 0 end as transactional_email_brand_from_site_theme;
