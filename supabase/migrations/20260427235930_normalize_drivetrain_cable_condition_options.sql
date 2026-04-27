update public.service_profile_questions spq
   set options_json = '[{"value":"ok","label":"Funcionamiento suave / sin resistencia anormal"},{"value":"high_friction","label":"Alta friccion / recorrido duro"},{"value":"frayed","label":"Deshilachado"},{"value":"corroded","label":"Corrosion visible"},{"value":"housing_damaged","label":"Funda danada / colapsada"},{"value":"replace","label":"Danio severo / recambio necesario"}]'::jsonb,
       updated_at = now()
  from public.service_profiles sp
 where sp.id = spq.service_profile_id
   and sp.key = 'derailleur_adjustment'
   and spq.key = 'cable_condition'
   and (
     spq.options_json is null
     or spq.options_json::text like '%Ya reemplazados%'
     or spq.options_json::text like '%Deshilachados - reemplazar%'
   );
