select
  assistant_runtime.assistant_canonical_json_internal_v1(
    '{"wheel":29,"width":2.25,"minimum":0.001}'::jsonb
  ) = '{"minimum":0.001,"wheel":29,"width":2.25}'
  and pg_get_function_result(
    'assistant_runtime.assistant_canonical_json_internal_v1(jsonb)'::regprocedure
  ) = 'text' as attested_fixed_point_measurements_verified;
