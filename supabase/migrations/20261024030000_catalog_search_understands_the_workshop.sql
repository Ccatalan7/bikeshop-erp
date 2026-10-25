-- 20261024030000: the catalog's search understands the workshop's words and
-- each product's spec sheet.
--
-- 2026-10-24, owner, trying the header's new search box: «the search should
-- be WAY SMARTER in terms of tech specs intuition». «camara francesa» found
-- three tubes and «camara fv» none; «29x2.25» found nothing though the tyres
-- say «29 x 2.25»; «cadena 11v» depended on a name saying «11v» while the
-- catalog writes «11 velocidades»; «cámara para bicicleta aro 29» asked every
-- word of the name. Until today a word had to be written in the product's own
-- text, and four hand-written aliases (piñón, cadena, cámara, neumático) were
-- the only vocabulary.
--
-- What changes, in the one search every public read shares
-- (get_public_products_without_inventory_reservations: the catalog, its
-- facets, the header's box and the Flutter store's listing):
--   1. catalog_search_terms holds the workshop's vocabulary as data: each
--      concept's equivalent words («presta», «francesa», «fv») and the
--      broader ones it belongs to («válvula»). A product whose name, category
--      or spec sheet says one of the words answers to all of them.
--   2. The spec sheet the store's filters show is searchable as the name is
--      (spec_public_facet_values_compute_internal_v1): a tube whose sheet
--      says «Francesa (Presta)» is found by «presta».
--   3. catalog_search_normalize_v1 reads what a visitor types the way the
--      catalog writes it: «29x2.25» is «29 2.25», «11 velocidades», «11s» and
--      «1x11» are «11v», «29er» is «29», «700c» is «700».
--   4. «de», «para» and the like ask nothing; «bicicleta», «aro» and «rin»
--      count when found but are not required.
--   5. One or two letters start a word: «av» is no longer found inside
--      «llave».

create table if not exists public.catalog_search_terms (
  id uuid primary key default gen_random_uuid(),
  -- Null: the vocabulary every store shares. A store may add its own words.
  tenant_id uuid references public.tenants(id) on delete cascade,
  concept text not null,
  -- 'part': what a product is, said only by its name and category (a chain
  -- whose spec sheet says «derailleur» is not a derailleur); 'attribute': a
  -- property the spec sheet may say too («Francesa (Presta)»).
  kind text not null default 'part',
  -- Equivalent words: any of them in a product brings all of them.
  terms text[] not null,
  -- Broader words the concept belongs to; they do not bring it back.
  broader text[] not null default '{}',
  -- Several words that name it together («pata de cambio»): in a product
  -- they bring the concept, and their words come with it.
  phrases text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_search_terms_kind check (kind in ('part', 'attribute')),
  constraint catalog_search_terms_terms_present check (cardinality(terms) > 0),
  -- Words as the search compares them: lower case, no accents, one word.
  constraint catalog_search_terms_normalized check (
    array_to_string(terms || broader, ' ') ~ '^[a-z0-9]+( [a-z0-9]+)*$'
    and array_to_string(phrases, ',') ~ '^([a-z0-9]+( [a-z0-9]+)+(,[a-z0-9]+( [a-z0-9]+)+)*)?$'
  )
);

create unique index if not exists catalog_search_terms_concept_uidx
  on public.catalog_search_terms (
    coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
    concept
  );

comment on table public.catalog_search_terms is
  'The workshop''s vocabulary for the public catalog search (20261024030000): a product whose name, category or spec sheet says one of a concept''s terms answers to all of them and to its broader words. Read only by get_public_products_without_inventory_reservations (security definer).';

alter table public.catalog_search_terms enable row level security;
revoke all on table public.catalog_search_terms from public, anon, authenticated;

-- The vocabulary of a Chilean workshop, Chilean words first. Counted on
-- 2026-10-24 in Viñabike's own texts (what customers asked for in
-- mechanic_jobs.client_request, the diagnoses and the work done, and the
-- catalog's names): «motor» 21 requests against 1 for «pedalier», «cambio»
-- 183 against 14 for «desviador», «pata de cambio» 13 against 6 for
-- «postiza», «patines» 5 and «zapatas» 0, «piola» 14 and «cable» 0, «maza»
-- 42 and «buje» 0, «piñón» 13 and «cassette» 4, «asiento» 10 and «sillín» 2.
-- The other Spanish and English names follow, so a visitor from anywhere
-- finds the part too (docs/wiki/compatibilidad/paginas/palabras-del-taller.md).
insert into public.catalog_search_terms (tenant_id, concept, kind, terms, broader, phrases)
values
  (null, 'valvula_presta', 'attribute', array['presta','francesa','francesas','fv','sclaverand'], array['valvula','valvulas'], '{}'::text[]),
  (null, 'valvula_schrader', 'attribute', array['auto','americana','americanas','schrader','av'], array['valvula','valvulas'], '{}'::text[]),
  (null, 'valvula_dunlop', 'attribute', array['dunlop','holandesa','dv','woods'], array['valvula','valvulas'], '{}'::text[]),
  (null, 'tubeless', 'attribute', array['tubeless','tlr'], '{}'::text[], array['sin camara']),
  (null, 'sellante', 'attribute', array['sellante','sellantes','antipinchazo','antipinchazos','autosellante','sealant','latex'], '{}'::text[], array['liquido tubeless','liquido antipinchazos']),
  (null, 'hidraulico', 'attribute', array['hidraulico','hidraulicos','hidraulica','hidraulicas','hydraulic'], '{}'::text[], '{}'::text[]),
  (null, 'mecanico', 'attribute', array['mecanico','mecanicos','mecanica','mecanicas','mechanical'], '{}'::text[], '{}'::text[]),
  (null, 'mtb', 'attribute', array['mtb','montana','mountain'], '{}'::text[], '{}'::text[]),
  (null, 'ruta', 'attribute', array['ruta','carretera','road'], '{}'::text[], '{}'::text[]),
  (null, 'urbana', 'attribute', array['urbana','urbano','urbanas','urbanos','paseo','city'], '{}'::text[], '{}'::text[]),
  (null, 'infantil', 'attribute', array['infantil','infantiles','nino','ninos','nina','ninas','kids','junior'], '{}'::text[], '{}'::text[]),
  (null, 'electrica', 'attribute', array['electrica','electricas','electrico','electricos','ebike','ebikes'], '{}'::text[], '{}'::text[]),
  (null, 'scooter', 'attribute', array['scooter','scooters','monopatin','monopatines'], '{}'::text[], '{}'::text[]),
  (null, 'recargable', 'attribute', array['recargable','recargables','usb'], '{}'::text[], '{}'::text[]),
  (null, 'plegable', 'attribute', array['plegable','plegables','kevlar','folding'], '{}'::text[], '{}'::text[]),
  (null, 'pasante', 'attribute', array['pasante','thru','thruaxle'], array['eje','ejes'], array['eje pasante']),
  (null, 'fixie', 'attribute', array['fixie','fixed','fijo'], '{}'::text[], array['pinon fijo']),
  (null, 'camara', 'part', array['camara','camaras','tube','tubes'], '{}'::text[], array['camara de aire']),
  (null, 'neumatico', 'part', array['neumatico','neumaticos','cubierta','cubiertas','goma','gomas','tire','tires','tyre','tyres'], '{}'::text[], '{}'::text[]),
  (null, 'llanta', 'part', array['llanta','llantas','rim','rims'], array['aro','aros'], '{}'::text[]),
  (null, 'rueda', 'part', array['rueda','ruedas','wheel','wheels','wheelset'], '{}'::text[], '{}'::text[]),
  (null, 'maza', 'part', array['maza','mazas','masa','masas','buje','bujes','hub','hubs'], '{}'::text[], '{}'::text[]),
  (null, 'rayo', 'part', array['rayo','rayos','radio','radios','spoke','spokes'], '{}'::text[], '{}'::text[]),
  (null, 'niple', 'part', array['niple','niples','nipple','nipples'], '{}'::text[], '{}'::text[]),
  (null, 'cono', 'part', array['cono','conos','cone','cones'], '{}'::text[], '{}'::text[]),
  (null, 'cassette', 'part', array['pinon','pinones','cassette','cassettes','casete','cassete','casette','freewheel','sprocket','sprockets','cog'], array['transmision'], array['rueda libre','pinon libre']),
  (null, 'cadena', 'part', array['cadena','cadenas','chain','chains'], array['transmision'], '{}'::text[]),
  (null, 'eslabon', 'part', array['eslabon','eslabones','powerlink'], array['cadena','cadenas'], array['eslabon rapido','missing link','quick link']),
  (null, 'cubrecadena', 'part', array['cubrecadena','cubrecadenas'], array['cadena','cadenas'], array['cubre cadena','protector de cadena']),
  (null, 'plato', 'part', array['plato','platos','corona','coronas','catalina','catalinas','chainring','chainrings'], array['transmision'], '{}'::text[]),
  (null, 'volante', 'part', array['volante','volantes','biela','bielas','multiplicacion','crank','cranks','crankset'], array['transmision'], '{}'::text[]),
  (null, 'motor', 'part', array['motor','motores','pedalier','pedaliers','bb','bracket','pedalera'], array['transmision'], array['eje de centro','eje central','caja pedalera','bottom bracket']),
  (null, 'cambio', 'part', array['desviador','desviadores','descarrilador','descarriladores','derailleur','derailleurs'], array['cambios','transmision'], array['cambio trasero','cambio delantero']),
  (null, 'shifter', 'part', array['shifter','shifters','mando','mandos','trigger','gripshift'], array['cambio','cambios','transmision'], array['manilla de cambio','manillas de cambio','palanca de cambio','palancas de cambio','mando de cambio']),
  (null, 'pata_de_cambio', 'part', array['postiza','postizas','hanger','hangers','patilla'], '{}'::text[], array['pata de cambio','pata del cambio','colgador de cambio']),
  (null, 'pata', 'part', array['parador','atril','kickstand'], '{}'::text[], array['pata de bicicleta','pata lateral','pata central','pata trasera']),
  (null, 'piola', 'part', array['piola','piolas','cable','cables','chicote','chicotes','guaya','guayas'], '{}'::text[], '{}'::text[]),
  (null, 'funda', 'part', array['funda','fundas','forro','forros','housing'], '{}'::text[], '{}'::text[]),
  (null, 'freno', 'part', array['freno','frenos','caliper','calipers','brake','brakes'], '{}'::text[], '{}'::text[]),
  (null, 'pastilla', 'part', array['pastilla','pastillas','balata','balatas','pad','pads'], array['freno','frenos'], '{}'::text[]),
  (null, 'patin', 'part', array['patin','patines','zapata','zapatas'], array['freno','frenos','pastilla','pastillas'], array['gomas de freno','goma de freno']),
  (null, 'disco', 'part', array['rotor','rotores'], array['disco','discos','freno','frenos'], array['disco de freno','discos de freno']),
  (null, 'vbrake', 'part', array['vbrake','vbrakes'], array['freno','frenos'], array['v brake','v brakes']),
  (null, 'manilla', 'part', array['manilla','manillas','lever','levers'], '{}'::text[], array['manilla de freno','manillas de freno']),
  (null, 'direccion', 'part', array['direccion','cazoleta','cazoletas','headset','headsets'], '{}'::text[], array['juego de direccion','caja de direccion']),
  (null, 'tee', 'part', array['tee','tees','potencia','potencias','avance','stem','stems'], '{}'::text[], '{}'::text[]),
  (null, 'manubrio', 'part', array['manubrio','manubrios','manillar','manillares','handlebar','handlebars'], '{}'::text[], '{}'::text[]),
  (null, 'cacho', 'part', array['cacho','cachos','barend','barends'], '{}'::text[], array['bar end','bar ends']),
  (null, 'puno', 'part', array['puno','punos','mango','mangos','grip','grips'], '{}'::text[], '{}'::text[]),
  (null, 'cinta_manubrio', 'part', array['bartape'], '{}'::text[], array['cinta de manubrio','cinta manubrio','bar tape']),
  (null, 'cinta_llanta', 'part', array['rimtape'], '{}'::text[], array['cinta de llanta','fondo de llanta','cinta tubeless']),
  (null, 'tija', 'part', array['tija','tijas','poste','seatpost','seatposts'], '{}'::text[], array['tubo de asiento','tubo del asiento','poste de asiento','tubo de sillin']),
  (null, 'telescopica', 'part', array['telescopica','telescopicas','telescopico','dropper'], array['tija','tijas'], '{}'::text[]),
  (null, 'asiento', 'part', array['asiento','asientos','sillin','sillines','montura','saddle','saddles'], '{}'::text[], '{}'::text[]),
  (null, 'silla_nino', 'part', array['sillita','sillitas','portabebe','portabebes'], '{}'::text[], array['silla para nino','asiento para nino','silla de nino']),
  (null, 'abrazadera', 'part', array['abrazadera','abrazaderas','collarin','collarines','clamp'], '{}'::text[], '{}'::text[]),
  (null, 'horquilla', 'part', array['horquilla','horquillas','fork','forks'], array['suspension'], '{}'::text[]),
  (null, 'amortiguador', 'part', array['amortiguador','amortiguadores','shock'], array['suspension'], '{}'::text[]),
  (null, 'cuadro', 'part', array['cuadro','cuadros','marco','frame','frames'], '{}'::text[], '{}'::text[]),
  (null, 'pedal', 'part', array['pedal','pedales','pedals'], '{}'::text[], '{}'::text[]),
  (null, 'cala', 'part', array['cala','calas','automatico','automaticos','spd','clipless','cleat','cleats'], array['pedal','pedales'], '{}'::text[]),
  (null, 'luz', 'part', array['luz','luces','foco','focos','linterna','linternas','farol','faroles','lampara','light','lights'], '{}'::text[], '{}'::text[]),
  (null, 'reflectante', 'part', array['reflectante','reflectantes','reflector','reflectores'], '{}'::text[], array['ojo de gato','ojos de gato']),
  (null, 'casco', 'part', array['casco','cascos','helmet','helmets'], '{}'::text[], '{}'::text[]),
  (null, 'lentes', 'part', array['lentes','anteojos','gafas'], '{}'::text[], '{}'::text[]),
  (null, 'guante', 'part', array['guante','guantes','glove','gloves'], '{}'::text[], '{}'::text[]),
  (null, 'calza', 'part', array['calza','calzas','culotte','culottes','badana'], '{}'::text[], '{}'::text[]),
  (null, 'polera', 'part', array['polera','poleras','jersey','tricota'], '{}'::text[], '{}'::text[]),
  (null, 'candado', 'part', array['candado','candados','lock','locks'], '{}'::text[], '{}'::text[]),
  (null, 'inflador', 'part', array['bombin','bombines','inflador','infladores','bomba','bombas','minibomba','pump','pumps'], '{}'::text[], array['bomba de aire','bomba de pie']),
  (null, 'caramayola', 'part', array['caramayola','caramayolas','caramagiola','caramagiolas','caramanola','anfora','bidon','bidones','botella','botellas','bottle'], '{}'::text[], '{}'::text[]),
  (null, 'portacaramayola', 'part', array['portacaramayola','portacaramagiola','portacaramagiolas','portabidon','portabidones','portabotella','portabotellas'], '{}'::text[], array['porta caramayola','porta caramagiola','porta bidon','porta botella']),
  (null, 'mochila', 'part', array['mochila','mochilas','camelbak'], '{}'::text[], array['mochila de hidratacion','bolsa de hidratacion']),
  (null, 'bolso', 'part', array['bolso','bolsos','bolsa','bolsas','banano','alforja','alforjas','bag','bags'], '{}'::text[], '{}'::text[]),
  (null, 'parche', 'part', array['parche','parches','parchar','patch','patches'], '{}'::text[], array['kit de parches']),
  (null, 'desmontador', 'part', array['desmontador','desmontadores','espatula','espatulas'], '{}'::text[], array['palanca de neumatico','palancas de neumatico','tire lever','tire levers']),
  (null, 'lubricante', 'part', array['lubricante','lubricantes','aceite','aceites','cera','lube'], '{}'::text[], '{}'::text[]),
  (null, 'grasa', 'part', array['grasa','grasas','grease'], '{}'::text[], '{}'::text[]),
  (null, 'desengrasante', 'part', array['desengrasante','desengrasantes','limpiador','limpiadores','shampoo','degreaser'], '{}'::text[], '{}'::text[]),
  (null, 'liquido_freno', 'part', array['dot'], array['freno','frenos'], array['liquido de freno','liquido de frenos','aceite mineral']),
  (null, 'herramienta', 'part', array['herramienta','herramientas','multiherramienta','multitool','tool','tools'], '{}'::text[], '{}'::text[]),
  (null, 'llave', 'part', array['llave','llaves','wrench'], array['herramienta','herramientas'], '{}'::text[]),
  (null, 'tapabarro', 'part', array['tapabarro','tapabarros','guardabarro','guardabarros','salpicadera','fender','fenders','mudguard'], '{}'::text[], '{}'::text[]),
  (null, 'parrilla', 'part', array['parrilla','parrillas','portaequipaje','portaequipajes','rack','carrier'], '{}'::text[], '{}'::text[]),
  (null, 'canasto', 'part', array['canasto','canastos','canasta','canastas','cesta','basket'], '{}'::text[], '{}'::text[]),
  (null, 'timbre', 'part', array['timbre','timbres','campanilla','campanillas','bocina','bocinas','corneta','bell'], '{}'::text[], '{}'::text[]),
  (null, 'espejo', 'part', array['espejo','espejos','retrovisor','mirror'], '{}'::text[], '{}'::text[]),
  (null, 'cuentakilometros', 'part', array['cuentakilometros','velocimetro','ciclocomputador','odometro','gps'], '{}'::text[], array['cuenta kilometros']),
  (null, 'rodillo', 'part', array['rodillo','rodillos','trainer'], '{}'::text[], '{}'::text[]),
  (null, 'rueditas', 'part', array['rueditas'], '{}'::text[], array['ruedas de apoyo','rueditas de apoyo','ruedas de entrenamiento']),
  (null, 'rodamiento', 'part', array['rodamiento','rodamientos','bolillas','bolitas','balero','baleros','bearing','bearings'], '{}'::text[], '{}'::text[]),
  (null, 'eje', 'part', array['eje','ejes','axle','spindle'], '{}'::text[], '{}'::text[]),
  (null, 'espaciador', 'part', array['espaciador','espaciadores','separador','separadores','laina','lainas','spacer','spacers'], '{}'::text[], '{}'::text[]),
  (null, 'adaptador', 'part', array['adaptador','adaptadores','adapter','adapters'], '{}'::text[], '{}'::text[])
on conflict ((coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)), concept)
do update set kind = excluded.kind, terms = excluded.terms, broader = excluded.broader,
  phrases = excluded.phrases, updated_at = now();

-- What a visitor types, as the catalog writes it, in the words the search
-- compares (lower case, no accents, letters and digits).
create or replace function public.catalog_search_normalize_v1(p_text text)
returns text
language sql
stable
parallel safe
set search_path to 'public'
as $function$
  select trim(regexp_replace(
    -- «700c» is the 700 the names say («700 x 25C»).
    regexp_replace(
      -- «29er» is a 29.
      regexp_replace(
        -- «29x2.25», «700 x 25c»: the measures, without the «x».
        regexp_replace(
          -- «11 velocidades», «11 vel», «11s», «11-speed»: «11v».
          regexp_replace(
            -- «1x11», «2x10»: the speeds of the cassette, «11v».
            regexp_replace(
              unaccent(lower(btrim(coalesce(p_text, '')))),
              '(^|\s)[1-3]x([0-9]{1,2})(?=\s|$|v)',
              '\1\2v',
              'g'
            ),
            '(^|[^0-9.,])([0-9]{1,2})[\s-]?(v|vel|vels|velocidad|velocidades|s|sp|spd|speed|speeds)(?![a-z])',
            '\1\2v',
            'g'
          ),
          '([0-9])\s*[x×*]\s*([0-9])',
          '\1 \2',
          'g'
        ),
        '(^|[^0-9])([0-9]{2})er(?![a-z])',
        '\1\2',
        'g'
      ),
      '(^|[^0-9])([0-9]{3})c(?![a-z0-9])',
      '\1\2',
      'g'
    ),
    '[^a-z0-9]+',
    ' ',
    'g'
  ))
$function$;

comment on function public.catalog_search_normalize_v1(text) is
  'A visitor''s search as the catalog writes it (20261024030000): «29x2.25» → «29 2 25», «11 velocidades»/«11s»/«1x11» → «11v», «29er» → «29», «700c» → «700».';

revoke all on function public.catalog_search_normalize_v1(text) from public, anon, authenticated;

-- The one search every public read shares, with the vocabulary, the spec
-- sheet and the visitor's words read as above.
CREATE OR REPLACE FUNCTION public.get_public_products_without_inventory_reservations(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_sku text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      coalesce(t.required_tokens, array[]::text[]) as required_tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type,
      -- The outer reservation-aware wrapper is the sole stock-policy owner.
      'all'::text as stock_policy,
      -- La regla única de venta online (catalog_product_web_block_v1) lee
      -- los ajustes del sitio una vez por consulta.
      public.catalog_web_policy_v1(p_tenant_id) as policy
    from (
      select public.catalog_search_normalize_v1(p_search_term) as term
    ) s
    cross join lateral (
      -- A word that only joins others («de», «para») asks nothing; one that
      -- names the bicycle or the wheel («bicicleta», «aro») counts when the
      -- product has it but is not required: «cámara para bicicleta aro 29»
      -- is a 29 tube, whose name says neither (2026-10-24).
      select
        coalesce(
          array_agg(w.token order by w.n) filter (where not w.stop),
          array_agg(w.token order by w.n)
        ) as tokens,
        coalesce(
          array_agg(w.token order by w.n) filter (where not w.stop and not w.soft),
          array_agg(w.token order by w.n) filter (where not w.stop),
          array_agg(w.token order by w.n)
        ) as required_tokens
      from (
        select
          token_parts.token,
          token_parts.n,
          token_parts.token = any (array[
            'de', 'del', 'la', 'las', 'el', 'los', 'lo', 'para', 'con', 'y',
            'e', 'o', 'u', 'en', 'un', 'una', 'unos', 'unas', 'por', 'al', 'a',
            'mi', 'su', 'que'
          ]) as stop,
          token_parts.token = any (array[
            'bici', 'bicis', 'bicicleta', 'bicicletas', 'bike', 'bikes', 'aro',
            'aros', 'rin', 'rines', 'rodado', 'medida', 'tipo'
          ]) as soft
        from regexp_split_to_table(s.term, '\s+') with ordinality as token_parts(token, n)
        where token_parts.token <> ''
      ) w
    ) t
  ),
  normalized as (
    -- The normalized texts only matter to a search: without a term every
    -- product passes and the order reads the raw name, price and date, so
    -- they are not computed (nor scored, below).
    select
      p.*,
      a.term,
      a.tokens,
      a.required_tokens,
      a.page_limit,
      a.page_offset,
      a.sort_by,
      (
        a.term ~ '(^| )(servicio|servicios|mantencion|mantenciones|reparacion|reparaciones|ajuste|ajustes|instalacion|instalaciones|limpieza|lavado|engrase|sangrado|purga|centrado|enrayado|diagnostico|revision)( |$)'
      ) as service_intent,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_name, p.name))), '[^a-z0-9]+', ' ', 'g')) end as name_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.sku, ''))), '[^a-z0-9]+', ' ', 'g')) end as sku_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.barcode, ''))), '[^a-z0-9]+', ' ', 'g')) end as barcode_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.gtin, ''))), '[^a-z0-9]+', ' ', 'g')) end as gtin_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.category_name, p.category, ''))), '[^a-z0-9]+', ' ', 'g')) end as category_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.brand, ''))), '[^a-z0-9]+', ' ', 'g')) end as brand_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.model, ''))), '[^a-z0-9]+', ' ', 'g')) end as model_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer, ''))), '[^a-z0-9]+', ' ', 'g')) end as manufacturer_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer_sku, ''))), '[^a-z0-9]+', ' ', 'g')) end as manufacturer_sku_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_description, p.description))), '[^a-z0-9]+', ' ', 'g')) end as description_n
    from public.products p
    cross join args a
    where p.tenant_id = p_tenant_id
      and p.is_active = true
      and coalesce(p.is_published, false) = true
      and coalesce(p.show_on_website, false) = true
      and (
        p_product_ids is null
        or cardinality(p_product_ids) = 0
        or p.id = any(p_product_ids)
      )
      and (
        p_category_ids is null
        or cardinality(p_category_ids) = 0
        or p.category_id = any(p_category_ids)
      )
      and (
        a.wanted_sku is null
        or lower(p.sku) = lower(a.wanted_sku)
      )
      and (
        a.wanted_product_type is null
        or p.product_type = a.wanted_product_type
      )
      -- Consumible, precio, costo, foto, nombre, categoría: lo decide la
      -- regla única, la misma que usan la ficha, el checkout y el ERP.
      and public.catalog_product_web_block_v1(p, a.policy) is null
      and (
        a.stock_policy = 'all'
        or coalesce(p.is_service, false)
        or p.product_type = 'service'
        or (
          a.stock_policy = 'available_only'
          and (
            coalesce(p.track_stock, true) = false
            or coalesce(p.stock_quantity, p.inventory_qty, 0) > 0
          )
        )
        or (
          a.stock_policy = 'out_of_stock_only'
          and coalesce(p.track_stock, true) = true
          and coalesce(p.stock_quantity, p.inventory_qty, 0) <= 0
        )
      )
  ),
  spec_text as (
    -- The spec sheet as the store's filters show it («Francesa (Presta)»,
    -- «622», «MTB»; a yes/no field by its name when it is «Sí», as
    -- «Tubeless Ready»), searchable as the name is. A cassette's count of
    -- sprockets is also its speeds («11v»). Read only for a search.
    select
      v.product_id,
      trim(regexp_replace(
        unaccent(lower(string_agg(
          case
            when v.data_type = 'boolean' and v.value_text = 'Sí' then v.spec_label
            when v.data_type = 'boolean' then null
            when v.spec_key = 'sprocket_count' then v.value_text || ' ' || v.value_text || 'v'
            else v.value_text
          end,
          ' '
        ))),
        '[^a-z0-9]+',
        ' ',
        'g'
      )) as spec_n
    from public.spec_public_facet_values_compute_internal_v1(p_tenant_id, null) v
    where (select a.term from args a) <> ''
    group by v.product_id
  ),
  vocabulary as materialized (
    -- The workshop's words (catalog_search_terms): the shared ones and the
    -- store's own, by concept. A concept brings its terms, its broader
    -- words and the words of its phrases.
    select v.concept, v.kind, v.terms, v.broader, v.phrases
    from public.catalog_search_terms v
    where (v.tenant_id is null or v.tenant_id = p_tenant_id)
      and (select a.term from args a) <> ''
  ),
  vocabulary_terms as materialized (
    select distinct v.concept, v.kind, term_parts.term
    from vocabulary v
    cross join lateral unnest(v.terms) as term_parts(term)
  ),
  vocabulary_phrases as materialized (
    select distinct v.concept, v.kind, phrase_parts.phrase
    from vocabulary v
    cross join lateral unnest(v.phrases) as phrase_parts(phrase)
  ),
  vocabulary_words as materialized (
    select distinct v.concept, word_parts.word
    from vocabulary v
    cross join lateral unnest(
      v.terms || v.broader || string_to_array(nullif(array_to_string(v.phrases, ' '), ''), ' ')
    ) as word_parts(word)
  ),
  product_words as materialized (
    -- Each product's words once, by where they are: the first word of its
    -- name (what it is), the rest of the name, its category and its spec
    -- sheet.
    select n.id as product_id, word_parts.word, case when word_parts.pos = 1 then 'head' else 'name' end as source
    from normalized n
    cross join lateral unnest(string_to_array(nullif(n.name_n, ''), ' ')) with ordinality as word_parts(word, pos)
    where n.term <> ''
    union all
    select n.id, word_parts.word, 'category'
    from normalized n
    cross join lateral unnest(string_to_array(nullif(n.category_n, ''), ' ')) as word_parts(word)
    where n.term <> ''
    union all
    select st.product_id, word_parts.word, 'spec'
    from spec_text st
    cross join lateral unnest(string_to_array(nullif(st.spec_n, ''), ' ')) as word_parts(word)
  ),
  concept_hits as materialized (
    -- The concepts each product says, ranked by where: 3 its name starts
    -- with the part («Motor sellado», «Disco de freno…»), 2 its category
    -- names it, 1 its name says it elsewhere or, for an attribute, its spec
    -- sheet does. A part is what the name and category say, never the spec
    -- sheet: a chain whose sheet says «derailleur» is not a derailleur.
    select h.product_id, h.concept, max(h.rank) as rank
    from (
      select pw.product_id, vt.concept,
        case
          when vt.kind = 'part' and pw.source = 'head' then 3
          when vt.kind = 'part' and pw.source = 'category' then 2
          else 1
        end as rank
      from product_words pw
      join vocabulary_terms vt on vt.term = pw.word
      where vt.kind = 'attribute' or pw.source <> 'spec'
      union all
      select n.id, vp.concept,
        case
          when vp.kind = 'part' and n.name_n like vp.phrase || '%' then 3
          when vp.kind = 'part' and (' ' || n.category_n || ' ') like '% ' || vp.phrase || ' %' then 2
          else 1
        end
      from normalized n
      left join spec_text st on st.product_id = n.id
      join vocabulary_phrases vp
        on (' ' || concat_ws(' ', n.name_n, n.category_n,
              case when vp.kind = 'attribute' then st.spec_n end) || ' ')
           like '% ' || vp.phrase || ' %'
      where n.term <> ''
    ) h
    group by h.product_id, h.concept
  ),
  vocabulary_names as materialized (
    -- What names a concept on its own: each term and each phrase.
    select vt.concept, vt.term as name from vocabulary_terms vt
    union
    select vp.concept, vp.phrase from vocabulary_phrases vp
  ),
  product_names as materialized (
    -- The names of what each product is, so a search that is exactly one
    -- of them («pata de cambio», «motor») puts those products first.
    select ch.product_id,
      '|' || string_agg(distinct vn.name, '|') filter (where ch.rank = 3) || '|' as head_names,
      '|' || string_agg(distinct vn.name, '|') filter (where ch.rank = 2) || '|' as type_names
    from concept_hits ch
    join vocabulary_names vn on vn.concept = ch.concept
    where ch.rank >= 2
    group by ch.product_id
  ),
  product_aliases as materialized (
    select ch.product_id,
      string_agg(distinct vw.word, ' ') filter (where ch.rank = 3) as head_n,
      string_agg(distinct vw.word, ' ') filter (where ch.rank = 2) as type_n,
      string_agg(distinct vw.word, ' ') as words_n
    from concept_hits ch
    join vocabulary_words vw on vw.concept = ch.concept
    group by ch.product_id
  ),
  enriched as (
    select
      n.*,
      coalesce(st.spec_n, '') as spec_n,
      -- What the product is: the part its name starts with, and next the
      -- part its category names. «pedalier» puts the bottom brackets before
      -- the wrench «Llave para motor sellado», which sits in «Motores».
      coalesce(pa.head_n, '') as alias_head_n,
      coalesce(pa.type_n, '') as alias_type_n,
      coalesce(pn.head_names, '') as head_names,
      coalesce(pn.type_names, '') as type_names,
      case when n.term = '' then '' else trim(concat_ws(
        ' ',
        -- Every concept the product says: «francesa» brings «presta» and
        -- «fv»; «Postiza» brings «pata de cambio».
        pa.words_n,
        -- Speeds as a visitor writes them: «11 velocidades», «11s», «1x11»
        -- (not a chain's width, «1/2x11/128»).
        (
          select string_agg(distinct coalesce(m[1], m[2]) || 'v', ' ')
          from regexp_matches(
            n.name_n,
            '(?:^| )(?:([0-9]{1,2}) ?(?:v|vel|vels|velocidad|velocidades|s|sp|spd|speed|speeds)|(?<![0-9] )[1-3]x([0-9]{1,2})(?! 128))(?= |$)',
            'g'
          ) as m
        ),
        -- 27.5 is 650b; the 700 is the 28 some write.
        case
          when concat_ws(' ', n.name_n, st.spec_n) ~ '(^| )(27 5|650 ?b|275|584)( |$)'
            then '650b 275 27 5'
        end,
        case when n.name_n ~ '(^| )700( |$)' then '28 700c' end
      )) end as alias_n
    from normalized n
    left join spec_text st on st.product_id = n.id
    left join product_aliases pa on pa.product_id = n.id
    left join product_names pn on pn.product_id = n.id
  ),
  matched as (
    select
      e.*,
      (
        case when e.term <> '' and e.sku_n = e.term then 1000 else 0 end +
        case when e.term <> '' and e.barcode_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.gtin_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.name_n = e.term then 850 else 0 end +
        case when e.term <> '' and e.name_n like e.term || '%' then 760 else 0 end +
        case when e.term <> '' and e.name_n like '%' || e.term || '%' then 650 else 0 end +
        case when e.term <> '' and e.head_names like '%|' || e.term || '|%' then 700 else 0 end +
        case when e.term <> '' and e.type_names like '%|' || e.term || '|%' then 600 else 0 end +
        case when e.term <> '' and e.category_n = e.term then 620 else 0 end +
        case when e.term <> '' and e.category_n like '%' || e.term || '%' then 560 else 0 end +
        case when e.term <> '' and e.alias_n like '%' || e.term || '%' then 500 else 0 end +
        case when e.term <> '' and e.sku_n like '%' || e.term || '%' then 460 else 0 end +
        case when e.term <> '' and e.manufacturer_sku_n like '%' || e.term || '%' then 420 else 0 end +
        case when e.term <> '' and e.brand_n like '%' || e.term || '%' then 360 else 0 end +
        case when e.term <> '' and e.model_n like '%' || e.term || '%' then 320 else 0 end +
        case when e.term <> '' and e.manufacturer_n like '%' || e.term || '%' then 300 else 0 end +
        case when e.term <> '' and e.spec_n like '%' || e.term || '%' then 280 else 0 end
      ) as phrase_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when tp.is_number and e.sku_n = tp.token then 120
            when tp.is_number and e.barcode_n = tp.token then 120
            when tp.is_number and e.gtin_n = tp.token then 120
            when tp.is_number and e.name_n ~ tp.number then 70
            when tp.is_number and e.category_n ~ tp.number then 58
            when tp.is_number and e.alias_n ~ tp.number then 52
            when tp.is_number and e.spec_n ~ tp.number then 40
            when tp.is_number then 0
            when e.name_n like tp.token || '%' then 95
            when (' ' || e.alias_head_n) like tp.pat then 92
            when (' ' || e.alias_type_n) like tp.pat then 80
            when (' ' || e.name_n) like tp.pat then 76
            when (' ' || e.category_n) like tp.pat then 66
            when (' ' || e.alias_n) like tp.pat then 56
            when (' ' || e.sku_n) like tp.pat then 54
            when (' ' || e.manufacturer_sku_n) like tp.pat then 48
            when (' ' || e.spec_n) like tp.pat then 44
            when (' ' || e.brand_n) like tp.pat then 42
            when (' ' || e.model_n) like tp.pat then 38
            when (' ' || e.manufacturer_n) like tp.pat then 34
            when length(tp.token) >= 4 and greatest(
              word_similarity(tp.token, e.name_n),
              word_similarity(tp.token, e.category_n),
              word_similarity(tp.token, e.brand_n),
              word_similarity(tp.token, e.model_n),
              word_similarity(tp.token, e.manufacturer_n),
              word_similarity(tp.token, e.alias_n)
            ) >= case when length(tp.token) >= 5 then 0.56 else 0.72 end then 28
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        cross join lateral (
          select
            token_parts.token,
            token_parts.token ~ '^[0-9]+$' as is_number,
            '(^|[^0-9])' || token_parts.token || '([^0-9]|$)' as number,
            -- One or two letters start a word («fv», «av», «ca» while
            -- typing); a longer word may sit inside one («caramagiola» in
            -- «portacaramagiola»).
            case when length(token_parts.token) <= 2
              then '% ' || token_parts.token || '%'
              else '%' || token_parts.token || '%'
            end as pat
        ) tp
        where token_parts.token <> ''
      ), 0) end as token_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when tp.is_number and e.description_n ~ tp.number then 8
            when not tp.is_number and (' ' || e.description_n) like tp.pat then 8
            when not tp.is_number and length(tp.token) >= 5 and word_similarity(tp.token, e.description_n) >= 0.86 then 5
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        cross join lateral (
          select
            token_parts.token,
            token_parts.token ~ '^[0-9]+$' as is_number,
            '(^|[^0-9])' || token_parts.token || '([^0-9]|$)' as number,
            case when length(token_parts.token) <= 2
              then '% ' || token_parts.token || '%'
              else '%' || token_parts.token || '%'
            end as pat
        ) tp
        where token_parts.token <> ''
      ), 0) end as weak_description_score
    from enriched e
    where e.term = ''
      or not exists (
        select 1
        from unnest(e.required_tokens) as token_parts(token)
        cross join lateral (
          select
            token_parts.token,
            token_parts.token ~ '^[0-9]+$' as is_number,
            '(^|[^0-9])' || token_parts.token || '([^0-9]|$)' as number,
            case when length(token_parts.token) <= 2
              then '% ' || token_parts.token || '%'
              else '%' || token_parts.token || '%'
            end as pat
        ) tp
        where token_parts.token <> ''
          and not (
            (
              tp.is_number
              and (
                e.sku_n = tp.token
                or e.barcode_n = tp.token
                or e.gtin_n = tp.token
                or e.name_n ~ tp.number
                or e.category_n ~ tp.number
                or e.alias_n ~ tp.number
                or e.spec_n ~ tp.number
                or e.description_n ~ tp.number
              )
            )
            or (
              not tp.is_number
              and (
                (' ' || e.name_n) like tp.pat
                or (' ' || e.category_n) like tp.pat
                or (' ' || e.alias_n) like tp.pat
                or (' ' || e.sku_n) like tp.pat
                or (' ' || e.barcode_n) like tp.pat
                or (' ' || e.gtin_n) like tp.pat
                or (' ' || e.brand_n) like tp.pat
                or (' ' || e.model_n) like tp.pat
                or (' ' || e.manufacturer_n) like tp.pat
                or (' ' || e.manufacturer_sku_n) like tp.pat
                or (' ' || e.spec_n) like tp.pat
                or (' ' || e.description_n) like tp.pat
                or (
                  length(tp.token) >= 4
                  and greatest(
                    word_similarity(tp.token, e.name_n),
                    word_similarity(tp.token, e.category_n),
                    word_similarity(tp.token, e.brand_n),
                    word_similarity(tp.token, e.model_n),
                    word_similarity(tp.token, e.manufacturer_n),
                    word_similarity(tp.token, e.alias_n)
                  ) >= case when length(tp.token) >= 5 then 0.56 else 0.72 end
                )
                or (
                  length(tp.token) >= 5
                  and word_similarity(tp.token, e.description_n) >= 0.86
                )
              )
            )
          )
      )
  ),
  scored as (
    select
      m.*,
      (m.phrase_strong_score + m.token_strong_score) as strong_score,
      (
        m.phrase_strong_score +
        m.token_strong_score +
        m.weak_description_score +
        case when m.product_type = 'service' and not m.service_intent
          then -260 else 0 end
      ) as search_score
    from matched m
  ),
  ranked as (
    select s.*
    from scored s
    where s.term = ''
      or s.product_type <> 'service'
      or s.service_intent
      or s.strong_score > 0
      or not exists (
        select 1
        from scored product_match
        where product_match.product_type <> 'service'
          and product_match.strong_score > 0
      )
  ),
  counted as (
    select p.*, count(*) over() as row_total
    from ranked p
  )
  select
    p.id,
    p.tenant_id,
    coalesce(nullif(btrim(p.website_name), ''), p.name) as name,
    p.sku,
    p.barcode,
    coalesce(p.website_price, p.price) as price,
    0::numeric as cost,
    p.inventory_qty,
    p.stock_quantity,
    coalesce(nullif(btrim(p.website_image_url), ''), p.image_url) as image_url,
    coalesce(nullif(btrim(p.website_image_url_optimized), ''), p.image_url_optimized) as image_url_optimized,
    case
      when cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        then p.website_image_urls
      else p.image_urls
    end as image_urls,
    p.description,
    p.website_description,
    p.category,
    p.category_id,
    p.category_name,
    p.brand_id,
    p.brand,
    p.model,
    p.manufacturer,
    p.manufacturer_sku,
    p.gtin,
    p.product_type,
    p.track_stock,
    p.is_active,
    p.is_published,
    p.show_on_website,
    p.created_at,
    p.updated_at,
    p.row_total as total_count
  from counted p
  order by
    case when p.term <> '' then p.search_score end desc nulls last,
    case when p.term = '' and p.sort_by = 'price_asc'
      then coalesce(p.website_price, p.price) end asc nulls last,
    case when p.term = '' and p.sort_by = 'price_desc'
      then coalesce(p.website_price, p.price) end desc nulls last,
    case when p.term = '' and p.sort_by = 'newest'
      then p.created_at end desc nulls last,
    coalesce(nullif(btrim(p.website_name), ''), p.name) asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$function$;
