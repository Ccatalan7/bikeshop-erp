-- El asistente ya resuelve el largo de válvula desde la frase.
select frase,
  (public.assistant_infer_technical_predicates_internal_v1(
     '5443b130-cc28-45af-a420-cd500b288890', frase) -> 'predicates')::text
   predicados
from (values
  ('camaras 26 valvula de auto 48mm'),
  ('camaras 26 valvula de auto de 48 mm'),
  ('camaras 29 francesa 60mm')
) f(frase);
