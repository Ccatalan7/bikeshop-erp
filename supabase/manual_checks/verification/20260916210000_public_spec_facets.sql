-- Verifier: fails (division by zero) until both v2 RPCs exist, the facet snapshot returns spec rows with coverage for the whole catalogue, and no reader still says «Largo nominal de esta variante de rayo».
select 1/(case when to_regprocedure('public.get_public_products_faceted_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,text,integer,integer)') is not null
  and to_regprocedure('public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb)') is not null
  and (select count(*) from public.get_public_product_facets_v2('5443b130-cc28-45af-a420-cd500b288890'::uuid) f where f.facet_key like 'spec:%' and f.range_min > 0 and f.range_max >= f.range_min) > 0
  and not exists (select 1 from public.spec_definitions where label = 'Largo nominal de esta variante de rayo')
  and not exists (select 1 from public.spec_templates where form_contract::text like '%Largo nominal de esta variante de rayo%')
  then 1 else 0 end) as ok;
