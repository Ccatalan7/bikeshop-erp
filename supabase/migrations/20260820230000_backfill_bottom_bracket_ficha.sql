-- Backfill the pedalier ficha from what the product names already declare.
--
-- This is the reviewed migration path the architecture requires: packaging and
-- name text may fill ficha truth here, under review, and never as live
-- Dart-side inference while a mechanic types.
--
-- Only explicit declarations are persisted. A name saying `SQUARE TYPE` or
-- `P/CUADRADA` proves the spindle is square; it does NOT prove JIS or ISO, so
-- `spindle_interface` is left absent rather than guessed. Absence is how this
-- schema says "not known", which is the whole point of removing «Otro» from
-- the vocabulary.
--
-- Name text is dirty in every direction: `68 X 122.5mm`, `122.5mm - 68mm`,
-- `122,5x68mm`, `68MMM - 103MM`, `(73) VP 127.5MM`. Ordering is unreliable, so
-- the numbers are classified by range instead of position — a shell width is
-- one of 68/70/73/83, a square-taper spindle length lives between 100 and 150.
-- No live name carries a number that is ambiguous under that rule.

begin;

create temporary table bb_backfill on commit drop as
with target as (
  select p.id, p.tenant_id, upper(unaccent(p.name)) as name
  from public.products p
  join public.product_categories c on c.id = p.category_id
  join public.category_tech_mappings m
    on m.category_id = c.id and m.status = 'active'
  join public.spec_templates t
    on t.id = m.template_id and t.key = 'bottom_bracket'
  where p.is_active is true
),
numbers as (
  select target.id, target.tenant_id, target.name,
    (
      select min(n) from (
        select replace(token[1], ',', '.')::numeric n
        from regexp_matches(target.name, '([0-9]+(?:[.,][0-9]+)?)', 'g') token
      ) parsed
      where n in (68, 70, 73, 83)
    ) as shell_width,
    (
      select min(n) from (
        select replace(token[1], ',', '.')::numeric n
        from regexp_matches(target.name, '([0-9]+(?:[.,][0-9]+)?)', 'g') token
      ) parsed
      where n >= 100 and n <= 150
    ) as spindle_length
  from target
)
select
  n.id as product_id,
  n.tenant_id,
  n.name,
  -- Shell: only when the name says so. A 68 mm width is overwhelmingly BSA in
  -- this catalog, but "overwhelmingly" is not a declaration.
  case
    when n.name like '%MID%' then 'Mid BMX 41.2mm'
    when n.name like '%BSA%' or n.name like '%1.37%' then 'BSA 1.37x24'
    else null
  end as shell_standard,
  -- Construction: `INTEGRADO` / `HOLLOWTECH` is an external-cup unit; the rest
  -- of this catalog says `SELLADO`, which is a sealed cartridge.
  case
    when n.name like '%INTEGRADO%' or n.name like '%HOLLOWTECH%'
      then 'Copas externas'
    when n.name like '%STACKED%' then 'Rodamientos prensados'
    -- A declared spindle length settles it: the unit carries its own spindle,
    -- so it is a cartridge whatever the shop called it in the name. The
    -- Shimano BB-UN300 is listed as `CUBETA DE MOTOR …, SPINDLE:127.5MM` and is
    -- a complete sealed cartridge; reading `CUBETA` as "cups only" there would
    -- state the opposite of what the same name declares.
    when n.spindle_length is not null then 'Cartucho sellado'
    when n.name like '%SELLAD%' then 'Cartucho sellado'
    else null
  end as construction,
  -- An external-cup unit takes the spindle that comes with the crank; a sealed
  -- cartridge brings its own.
  case
    when n.name like '%INTEGRADO%' or n.name like '%HOLLOWTECH%' then false
    when n.spindle_length is not null then true
    when n.name like '%STACKED%' then false
    when n.name like '%SELLAD%' then true
    when n.name like '%CUBETA%' then false
    else null
  end as includes_spindle,
  -- Declared on the packaging of the external-cup units: `24/24` is Hollowtech
  -- on both sides, `22/24` is SRAM GXP.
  case
    when n.name like '%22/24%' and n.name like '%24/24%'
      then '["Hollowtech / 24mm","SRAM GXP 24/22"]'::jsonb
    when n.name like '%22/24%'
      then '["Hollowtech / 24mm","SRAM GXP 24/22"]'::jsonb
    when n.name like '%24/24%' or n.name like '%HOLLOWTECH%'
      then '["Hollowtech / 24mm"]'::jsonb
    when n.name like '%MID%' and n.name like '%22MM%'
      then '["BMX 22mm"]'::jsonb
    else null
  end as accepted_interfaces,
  n.shell_width,
  n.spindle_length
from numbers n;

-- One row per (product, definition), only where the name actually declared it.
insert into public.product_spec_values (
  tenant_id, product_id, spec_definition_id,
  value_text, value_number, value_boolean, value_option, value_json
)
select b.tenant_id, b.product_id, d.id,
       null, f.number_value, f.boolean_value, f.option_value, f.json_value
from bb_backfill b
cross join lateral (values
  ('bb_shell_standard', null::numeric, null::boolean, b.shell_standard, null::jsonb),
  ('bb_construction', null, null, b.construction, null),
  ('includes_spindle', null, b.includes_spindle, null, null),
  ('spindle_interface_accepted', null, null, null, b.accepted_interfaces),
  ('bb_shell_width_mm', b.shell_width, null, null, null),
  ('spindle_length_mm', b.spindle_length, null, null, null)
) as f(def_key, number_value, boolean_value, option_value, json_value)
join public.spec_definitions d
  on d.key = f.def_key and d.tenant_id is null
where coalesce(
  f.number_value::text, f.boolean_value::text, f.option_value, f.json_value::text
) is not null
on conflict (tenant_id, product_id, spec_definition_id) do update set
  value_number = excluded.value_number,
  value_boolean = excluded.value_boolean,
  value_option = excluded.value_option,
  value_json = excluded.value_json,
  updated_at = now();

commit;
