-- El 70% de la entrada de cada pregunta es prefijo idéntico —catálogo de
-- herramientas más reglas del servidor— reenviado en cada llamada. Gemini
-- informa en su metadata cuántos de esos tokens sirvió desde su caché
-- (`cachedContentTokenCount`) y nuestro parser lo ignoraba: el ledger cobra
-- como nuevo lo que el proveedor quizá ya descuenta.
--
-- Antes de optimizar hay que medir. Esto sólo registra el dato.

alter table public.assistant_provider_attempts
  add column if not exists cached_input_tokens integer not null default 0;

CREATE OR REPLACE FUNCTION assistant_runtime.assistant_record_provider_attempt_v2(p_envelope text, p_body text, p_mac_hex text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'assistant_runtime', 'pg_temp'
AS $function$
declare
  v_attestation jsonb;
  v_body jsonb := p_body::jsonb;
  v_response jsonb;
begin
  -- Se aceptan las DOS formas del cuerpo a propósito: la que trae
  -- `p_cached_input_tokens` y la que no. Este ledger es obligatorio —si el
  -- registro falla, la corrida muere—, así que la base tiene que tolerar
  -- cualquier orden de despliegue entre ella y la función de borde.
  if not (
    assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
      'p_actor_user_id', 'p_attempt_no', 'p_authority_fingerprint',
      'p_completed_at', 'p_error_code', 'p_estimated_cost_microusd',
      'p_fence_token', 'p_finish_reason', 'p_input_tokens', 'p_lease_token',
      'p_model', 'p_model_role', 'p_output_tokens', 'p_provider',
      'p_provider_request_hash', 'p_response_hash', 'p_run_id', 'p_started_at',
      'p_status', 'p_tenant_id'
    ])
    or assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
      'p_actor_user_id', 'p_attempt_no', 'p_authority_fingerprint',
      'p_cached_input_tokens', 'p_completed_at', 'p_error_code',
      'p_estimated_cost_microusd', 'p_fence_token', 'p_finish_reason',
      'p_input_tokens', 'p_lease_token', 'p_model', 'p_model_role',
      'p_output_tokens', 'p_provider', 'p_provider_request_hash',
      'p_response_hash', 'p_run_id', 'p_started_at', 'p_status', 'p_tenant_id'
    ])
  ) then
    raise exception 'Invalid provider attestation body' using errcode = '22023';
  end if;
  v_attestation := assistant_runtime.assistant_verify_attestation_internal_v1(
    'assistant_record_provider_attempt_v2', p_envelope, p_body, p_mac_hex
  );
  if (v_attestation ->> 'replayed')::boolean then return v_attestation -> 'response'; end if;
  v_response := assistant_runtime.assistant_record_provider_attempt_v1(
    (v_body ->> 'p_tenant_id')::uuid,
    (v_body ->> 'p_actor_user_id')::uuid,
    v_body ->> 'p_authority_fingerprint',
    (v_body ->> 'p_run_id')::uuid,
    (v_body ->> 'p_lease_token')::uuid,
    (v_body ->> 'p_fence_token')::bigint,
    (v_body ->> 'p_attempt_no')::integer,
    v_body ->> 'p_provider',
    v_body ->> 'p_model',
    v_body ->> 'p_model_role',
    v_body ->> 'p_status',
    v_body ->> 'p_finish_reason',
    (v_body ->> 'p_input_tokens')::bigint,
    (v_body ->> 'p_output_tokens')::bigint,
    (v_body ->> 'p_estimated_cost_microusd')::bigint,
    v_body ->> 'p_provider_request_hash',
    v_body ->> 'p_response_hash',
    v_body ->> 'p_error_code',
    (v_body ->> 'p_started_at')::timestamptz,
    (v_body ->> 'p_completed_at')::timestamptz
  );
  -- Cuántos de los tokens de entrada vinieron del caché del proveedor. Se
  -- guarda aparte del costo: primero medir si el caché actúa, después decidir
  -- si conviene tarifarlo distinto.
  update public.assistant_provider_attempts attempt
  set cached_input_tokens = coalesce(
    (v_body ->> 'p_cached_input_tokens')::integer, 0
  )
  where attempt.run_id = (v_body ->> 'p_run_id')::uuid
    and attempt.attempt_no = (v_body ->> 'p_attempt_no')::integer;
  return assistant_runtime.assistant_store_attestation_response_internal_v1(
    v_attestation, v_response
  );
end;
$function$
;
