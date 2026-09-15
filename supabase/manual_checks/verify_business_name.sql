select
  1 / (case when (select prosrc from pg_proc where proname='assistant_prepare_customer_contact_v1') like '%businessName%' then 1 else 0 end) as negocio_presente,
  1 / (case when (select nullif(btrim(shop_name),'') from tenants where id='5443b130-cc28-45af-a420-cd500b288890') is not null then 1 else 0 end) as tiene_nombre;
