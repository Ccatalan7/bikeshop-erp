-- Read-back: el presupuesto admite exactamente dos valores, y ninguno más.
select
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_begin_run_v1'
  ) like '%not in (8, 18)%' then 1 else 0 end) as admite_ocho_y_dieciocho,
  -- No es un número libre del cliente: el presupuesto es lo que impide que una
  -- corrida se vuelva ilimitada.
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_begin_run_v1'
  ) not like '%p_tool_call_budget between%' then 1 else 0 end) as sigue_cerrada,
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_begin_run_v1'
  ) like '%p_turn_budget <> 5%' then 1 else 0 end) as turnos_intactos;
