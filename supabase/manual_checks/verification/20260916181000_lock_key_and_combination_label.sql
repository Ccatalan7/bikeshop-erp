-- Verifier: fails (division by zero) until the lock option reads «Llave y combinación».
select 1/(case when
  (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id
    where d.tenant_id is null and d.key='locking_mechanism' and v.label='Llave y combinación')=1
  and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id
    where d.tenant_id is null and d.key='locking_mechanism' and v.label='Llave y clave')=0
  then 1 else 0 end) as lock_label_ok;
