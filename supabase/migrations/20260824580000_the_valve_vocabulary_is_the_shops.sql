-- El vocabulario de la válvula es el del taller, no el del manual.
--
-- El asistente sólo reconocía «schrader» y «presta» —las palabras que nadie usa
-- acá—. Con «cámaras 26 con válvula VA de 48mm» resolvía el aro y **nada de la
-- válvula**, así que devolvía cámaras Presta mezcladas con las pedidas.
--
-- La inferencia arma su vocabulario con las palabras de los ROTULOS de
-- `spec_definition_values`, tomando tokens alfabéticos de tres letras o más.
-- Entonces el arreglo no es código: es poner en el rótulo las palabras que el
-- catálogo y el operador realmente usan.
--
-- **«VA» y «VF» quedan fuera a propósito.** Dos letras, y «va» es un verbo
-- común en español: aceptarlo convertiría cualquier frase con «va» en un filtro
-- de válvula. Es el mismo accidente que ya ocurrió con «con uña / claw», que
-- hacía que toda frase con «con una» filtrara patillas. «americana», «auto» y
-- «francesa» sí son inequívocas en una tienda de bicicletas.
--
-- El rótulo además se ve en el formulario, y ahí también gana: dice la palabra
-- con la que el mecánico la pide.

begin;

update public.spec_definition_values v
set label = nuevo.label, updated_at = now()
from (values
  ('schrader', 'Schrader (americana / auto)'),
  ('presta', 'Presta (francesa)'),
  ('dunlop', 'Dunlop (inglesa)')
) as nuevo(code, label)
where v.code = nuevo.code
  and v.spec_definition_id = (
    select d.id from public.spec_definitions d
    where d.tenant_id is null and d.key = 'valve_type'
  );

-- `allowed_values` lleva las mismas etiquetas: si divergen, el formulario
-- muestra una lista y guarda contra otra.
update public.spec_definitions
set allowed_values = '["Presta (francesa)", "Schrader (americana / auto)", "Dunlop (inglesa)", "Otra", "Desconocido"]'::jsonb,
    updated_at = now()
where tenant_id is null and key = 'valve_type';

commit;
