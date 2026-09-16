-- Follow-up to 20260916180000: the option «Llave y clave» of locking_mechanism
-- tied with «Clave (combinación)» in the name-reading label score (both share
-- the word «clave» at 1/2), so a lock named «… Clave …» could not be read.
-- «Llave y combinación» keeps the meaning and leaves «clave» to one option.
-- Rerunnable: conditional on the current wording.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
update public.spec_definition_values v set label='Llave y combinación', updated_at=now()
 from public.spec_definitions d
 where d.id=v.spec_definition_id and d.tenant_id is null and d.key='locking_mechanism'
   and v.label='Llave y clave';
commit;
