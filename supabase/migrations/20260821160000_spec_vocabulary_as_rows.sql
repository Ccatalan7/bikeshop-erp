-- Fase 1 de la unificación: el valor de una ficha deja de ser un string.
--
-- Hoy el CAMPO tiene identidad (`spec_definitions.id`) pero el VALOR no: es
-- texto, y está escrito de cuatro formas distintas según quién lo guarde —
-- etiqueta literal en `product_spec_values.value_option`, código corto en
-- `bike_profiles.technical_profile`, claves propias en
-- `diagnosis_sheet_data`, y pares `{label, value}` dentro de
-- `service_profile_questions.options_json`. Siete archivos de Dart existen sólo
-- para traducir entre esas formas.
--
-- El costo real, medido: renombrar «Cartucho sellado» a «Rodamiento sellado» el
-- 2026-08-21 obligó a reescribir el vocabulario, las condiciones de las reglas,
-- las opciones ofrecidas y los 48 productos en una sola transacción. Se escapó
-- uno de los cuatro y lo cazó una afirmación del read-back.
--
-- Con esta tabla, ese renombre pasa a ser un `update` de una fila.
--
-- Los códigos NO se inventan cuando ya existen. El wizard de servicios lleva
-- años guardando pares `{label, value}` con el código correcto: 192 de las 505
-- etiquetas del catálogo ya tienen uno ahí, y esos mandan. El vocabulario del
-- pedalier va curado a mano porque nació hoy. El resto se genera desde la
-- etiqueta, y a partir de aquí ya no vuelve a moverse aunque la etiqueta sí.
--
-- Esta fase no mueve ni un dato de negocio: crea la tabla y la llena. Nada la
-- lee todavía.

begin;

create table if not exists public.spec_definition_values (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid references public.tenants(id) on delete cascade,
  spec_definition_id  uuid not null references public.spec_definitions(id) on delete cascade,
  code                text not null,
  label               text not null,
  sort_order          integer not null default 0,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint spec_definition_values_code_shape
    check (code ~ '^[a-z][a-z0-9_]{0,63}$')
);

comment on table public.spec_definition_values is
  'El vocabulario de un campo de ficha, una fila por valor. `code` es la '
  'identidad estable y nunca cambia; `label` es lo que se muestra y cambia '
  'libre. Todo lo que guarde un hecho referencia el código, nunca la etiqueta.';

create unique index if not exists spec_definition_values_definition_code
  on public.spec_definition_values (spec_definition_id, code);
create index if not exists spec_definition_values_definition
  on public.spec_definition_values (spec_definition_id) where is_active;
create index if not exists spec_definition_values_tenant
  on public.spec_definition_values (tenant_id);

alter table public.spec_definition_values enable row level security;
drop policy if exists "spec_definition_values_select" on public.spec_definition_values;
create policy "spec_definition_values_select" on public.spec_definition_values
  for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
drop policy if exists "spec_definition_values_write" on public.spec_definition_values;
create policy "spec_definition_values_write" on public.spec_definition_values
  for all to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

-- Genera un código legible desde una etiqueta, para el vocabulario que nunca
-- tuvo uno. Sólo se usa al crear la fila: después el código es inmutable.
create or replace function public.spec_value_code_from_label_internal_v1(p_label text)
returns text
language sql
immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $slug$
  -- Una etiqueta puede ser puro número («10» velocidades, «29» pulgadas) y un
  -- código tiene que empezar por letra para no confundirse con un id. En ese
  -- caso lleva prefijo `v_`, que es feo pero estable — y estable es el punto.
  with limpio as (
    select nullif(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            lower(public.unaccent(coalesce(p_label, ''))),
            '[^a-z0-9]+', '_', 'g'
          ), '_+', '_', 'g'
        ), '^_|_$', '', 'g'
      ), ''
    ) as texto
  )
  select case
    when texto is null then null
    when texto ~ '^[a-z]' then left(texto, 64)
    else left('v_' || texto, 64)
  end from limpio;
$slug$;

commit;
