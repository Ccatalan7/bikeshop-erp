update public.service_profile_questions spq
	 set options_json = '[{"value":"v_brake","label":"V-Brake"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"cantilever","label":"Cantilever"}]'::jsonb,
			 updated_at = now()
	from public.service_profiles sp
 where sp.id = spq.service_profile_id
	 and sp.key = 'brake_cable_replace_adjust'
	 and spq.key = 'brake_type_mech'
	 and (
		 spq.options_json is null
		 or spq.options_json::text like '%disco_mec%'
		 or spq.options_json::text like '%v-brake%'
	 );
