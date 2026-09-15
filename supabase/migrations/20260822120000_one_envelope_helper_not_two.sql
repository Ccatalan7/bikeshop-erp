-- Un `create or replace function` que AGREGA un parámetro no reemplaza nada:
-- crea una sobrecarga. La firma de 3 argumentos siguió existiendo junto a la
-- nueva de 4 con default, y desde ese momento toda llamada de 3 argumentos
-- —las 38 herramientas del asistente menos la de inventario— murió con
-- «function ... is not unique». En la app se veía como «La fuente autorizada
-- respondió como no disponible», que es honesto y no dice nada de la causa.
--
-- Se elimina la vieja. La de 4 argumentos con default atiende igual a quien
-- llame con 3, así que ningún llamador necesita cambiar.
--
-- Regla que queda: agregar un parámetro con default a una función existente
-- NO es un cambio compatible en Postgres. O se borra la firma anterior en la
-- misma migración, o se deja el mismo número de argumentos.

drop function if exists public.assistant_tool_envelope_internal_v1(
  uuid, jsonb, boolean
);
