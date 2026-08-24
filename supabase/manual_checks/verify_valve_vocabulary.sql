-- El asistente reconoce las palabras del taller, y «va» sigue sin ser vocabulario.
select frase,
  (public.assistant_infer_technical_predicates_internal_v1(
     '5443b130-cc28-45af-a420-cd500b288890', frase)
   -> 'predicates')::text predicados
from (values
  ('camaras 26 con valvula americana de 48mm'),
  ('camaras 26 valvula de auto'),
  ('camaras 29 valvula francesa'),
  -- Control: una frase con «va» de verbo no puede filtrar válvulas.
  ('el pedido va manana')
) f(frase);
