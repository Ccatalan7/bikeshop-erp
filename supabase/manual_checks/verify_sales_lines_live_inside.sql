-- Read-back: la función ya no nombra una tabla inexistente y lee las líneas
-- donde de verdad viven, dentro del documento.
--
-- No se la invoca acá: exige contexto de tenant y el read-back corre sin
-- sesión de negocio. La ejecución real se comprobó aparte, fijando el JWT.
select
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_availability_targets_v1'
  ) not like '%sales_invoice_lines%' then 1 else 0 end) as sin_tabla_inexistente,
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_availability_targets_v1'
  ) like '%jsonb_array_elements(invoice.items)%' then 1 else 0 end)
    as lee_las_lineas_del_documento,
  -- Sólo se pregunta por lo que falta: un chequeo es lento.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_availability_targets_v1'
  ) like '%available <= greatest(minimum, 0)%' then 1 else 0 end)
    as pregunta_por_lo_que_falta;
