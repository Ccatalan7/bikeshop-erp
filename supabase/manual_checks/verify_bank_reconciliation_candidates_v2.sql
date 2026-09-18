-- Falla si el catálogo v2 de conciliación bancaria no quedó desplegado, si
-- quedó abierto a anon, o si vuelve a mandar el asiento de un pago como un
-- segundo candidato idéntico (la causa de que sólo 2 de 229 filas reales se
-- preseleccionaran).
select
  to_regprocedure('public.get_bank_reconciliation_candidates_v2(uuid,date,date)') is not null as v2_presente,
  has_function_privilege('authenticated', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE') as contador_la_llama,
  has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE') as anon_la_llama,
  has_function_privilege('authenticated', 'public.bank_reconciliation_candidate_identity(uuid,text,uuid)', 'EXECUTE') as ayudante_expuesto,
  public.bank_reconciliation_name_list(array['MKR Imports', ' MKR ', 'Mauricio Kishinevsky Rosental S.A.', 'MKR', '', null]) as nombres;

select 1 / (case when
  to_regprocedure('public.get_bank_reconciliation_candidates_v2(uuid,date,date)') is not null
  and has_function_privilege('authenticated', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.bank_reconciliation_candidate_identity(uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.bank_reconciliation_employee_names(uuid,uuid,text[])', 'EXECUTE')
then 1 else 0 end) as afirma_catalogo_v2_y_privilegios;

-- Los nombres se ordenan por bytes: igual en cualquier collation del servidor.
select 1 / (case when
  public.bank_reconciliation_name_list(array['MKR Imports', ' MKR ', 'Mauricio Kishinevsky Rosental S.A.', 'MKR', '', null])
    = '["MKR", "MKR Imports", "Mauricio Kishinevsky Rosental S.A."]'::jsonb
then 1 else 0 end) as afirma_lista_de_nombres;

-- El asiento de un pago de venta ya no se filtra como candidato: la definición
-- excluye los módulos que el libro escribe de verdad.
select 1 / (case when
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''sales_payments'', ''purchase_payments'', ''expense_payments''%'
then 1 else 0 end) as afirma_sin_asientos_duplicados;
