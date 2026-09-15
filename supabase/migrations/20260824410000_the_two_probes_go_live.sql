-- Se encienden las dos sondas reconocidas.
--
-- Nacieron apagadas porque configurar un portal no es autorizar consultarlo.
-- El dueño autorizó continuar, así que quedan habilitadas — sólo RBX y MKR, que
-- son los dos que se reconocieron en vivo y cuya lectura está probada.
--
-- Ningún otro proveedor queda encendido por arrastre: una sonda sin reconocer
-- consultaría a ciegas y escribiría conclusiones que nadie verificó.

begin;

update public.supplier_portal_probes probe
set is_enabled = true, updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.name in ('RBX', 'MKR Imports');

commit;
