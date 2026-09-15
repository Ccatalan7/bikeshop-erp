-- Fase 3 de la unificación: una sola tabla de hechos técnicos.
--
-- Hoy el mismo hecho —«esta caja es inglesa»— se guarda de cuatro formas según
-- quién sea el sujeto: fila con etiqueta en `product_spec_values`, blob JSONB
-- con código en `bike_profiles.technical_profile`, blob JSONB con claves
-- propias en `diagnosis_sheet_data`, y par `{label,value}` en el wizard. Un
-- producto y una bici no se pueden cruzar sin un traductor en Dart.
--
-- Acá el sujeto es una columna. Un producto, una bici y la ficha de un trabajo
-- guardan sus hechos en la misma tabla, con el mismo campo y apuntando al mismo
-- vocabulario. Cruzar bici con producto pasa a ser un join.
--
-- `source` y `confirmed` dejan de ser privilegio de las bicis. Hoy un producto
-- no puede decir «esto lo confirmó el mecánico» y una ficha de diagnóstico
-- tampoco; con esto los tres pueden, y la matriz de compatibilidad puede
-- distinguir «no lo sé» de «lo sé y es raro» en cualquier sujeto.
--
-- Los valores de lista van en una tabla hija, una fila por valor elegido. Eso
-- resuelve single_select y multi_select con la misma forma, y mantiene la
-- llave foránea real: un hecho no puede apuntar a un valor que no existe.
-- Un arreglo de uuid no daría esa garantía.
--
-- Esta fase no mueve ni un dato: crea las tablas. El backfill va aparte.

begin;

create table if not exists public.spec_facts (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  subject_type        text not null,
  subject_id          uuid not null,
  spec_definition_id  uuid not null references public.spec_definitions(id) on delete cascade,
  value_number        numeric,
  value_boolean       boolean,
  value_text          text,
  source              text not null default 'mechanic',
  confirmed           boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint spec_facts_subject_type_known
    check (subject_type in ('product', 'bike', 'job_bike')),
  constraint spec_facts_source_known
    check (source in ('mechanic', 'catalog', 'supplier_text', 'inferred', 'import')),
  constraint spec_facts_one_scalar
    check (num_nonnulls(value_number, value_boolean, value_text) <= 1)
);

comment on table public.spec_facts is
  'Un hecho técnico sobre un sujeto: producto, bici o bici dentro de un '
  'trabajo. Misma forma para los tres, mismo vocabulario, mismas marcas de '
  'procedencia y confirmación. Los valores de lista viven en spec_fact_values.';
comment on column public.spec_facts.source is
  'De dónde salió: el mecánico lo confirmó, vino del catálogo global, se leyó '
  'del texto del proveedor en una migración revisada, se dedujo, o entró en '
  'una importación. Nunca se infiere en runtime.';
comment on column public.spec_facts.confirmed is
  'Si alguien con la pieza en la mano lo confirmó. Distinto de tener valor: '
  'un dato heredado del catálogo tiene valor y no está confirmado.';

create unique index if not exists spec_facts_subject_definition
  on public.spec_facts (tenant_id, subject_type, subject_id, spec_definition_id);
create index if not exists spec_facts_subject
  on public.spec_facts (tenant_id, subject_type, subject_id);
create index if not exists spec_facts_definition
  on public.spec_facts (spec_definition_id);

create table if not exists public.spec_fact_values (
  fact_id   uuid not null references public.spec_facts(id) on delete cascade,
  value_id  uuid not null references public.spec_definition_values(id) on delete restrict,
  position  integer not null default 0,
  primary key (fact_id, value_id)
);

comment on table public.spec_fact_values is
  'Los valores de lista de un hecho. Una fila para single_select, varias para '
  'multi_select — la misma forma para los dos. La llave foránea garantiza que '
  'un hecho nunca apunte a un valor que ya no existe, que es justamente lo que '
  'un texto libre no puede garantizar.';

create index if not exists spec_fact_values_value
  on public.spec_fact_values (value_id);

alter table public.spec_facts enable row level security;
drop policy if exists "spec_facts_select" on public.spec_facts;
create policy "spec_facts_select" on public.spec_facts
  for select to authenticated using (tenant_id = public.user_tenant_id());
drop policy if exists "spec_facts_write" on public.spec_facts;
create policy "spec_facts_write" on public.spec_facts
  for all to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

alter table public.spec_fact_values enable row level security;
drop policy if exists "spec_fact_values_select" on public.spec_fact_values;
create policy "spec_fact_values_select" on public.spec_fact_values
  for select to authenticated
  using (exists (
    select 1 from public.spec_facts f
    where f.id = fact_id and f.tenant_id = public.user_tenant_id()
  ));
drop policy if exists "spec_fact_values_write" on public.spec_fact_values;
create policy "spec_fact_values_write" on public.spec_fact_values
  for all to authenticated
  using (exists (
    select 1 from public.spec_facts f
    where f.id = fact_id and f.tenant_id = public.user_tenant_id()
  ))
  with check (exists (
    select 1 from public.spec_facts f
    where f.id = fact_id and f.tenant_id = public.user_tenant_id()
  ));

-- Un hecho de lista no puede tener también un escalar, y uno escalar no puede
-- tener valores de lista. Se comprueba al escribir el valor, que es el único
-- momento en que ambos lados existen.
create or replace function public.spec_fact_value_shape_internal_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $shape$
declare
  v_tipo text;
  v_escalares integer;
begin
  select d.data_type, num_nonnulls(f.value_number, f.value_boolean, f.value_text)
    into v_tipo, v_escalares
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  where f.id = new.fact_id;

  if v_tipo not in ('single_select', 'multi_select') then
    raise exception 'spec_fact_values sólo aplica a campos de lista (% es %)',
      new.fact_id, v_tipo using errcode = '22023';
  end if;
  if v_escalares > 0 then
    raise exception 'un hecho de lista no puede llevar además un valor escalar'
      using errcode = '22023';
  end if;
  if v_tipo = 'single_select'
     and (select count(*) from public.spec_fact_values where fact_id = new.fact_id) > 0 then
    raise exception 'un campo de selección única admite un solo valor'
      using errcode = '22023';
  end if;
  return new;
end;
$shape$;

drop trigger if exists spec_fact_values_shape on public.spec_fact_values;
create trigger spec_fact_values_shape
  before insert on public.spec_fact_values
  for each row execute function public.spec_fact_value_shape_internal_v1();

commit;
