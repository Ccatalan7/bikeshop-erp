-- Una medida pegada a su unidad se lee igual que separada.
select frase,
  (public.assistant_infer_technical_predicates_internal_v1(
     '5443b130-cc28-45af-a420-cd500b288890', frase) -> 'predicates')::text
   predicados
from (values
  ('camaras 26 valvula de auto 48mm'),
  ('camaras 29 francesa 60mm'),
  -- Control: un calce de neumático NO se parte en un valor suelto.
  ('neumatico 26x1.95')
) f(frase);
