create or replace function public.is_broad_drivetrain_ecosystem_claim(
  p_value text
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_normalized text;
  v_has_brand_family boolean;
  v_has_exact_semantics boolean;
begin
  if p_value is null or btrim(p_value) = '' then
    return false;
  end if;

  v_normalized := lower(btrim(p_value));
  v_normalized := replace(v_normalized, 'á', 'a');
  v_normalized := replace(v_normalized, 'é', 'e');
  v_normalized := replace(v_normalized, 'í', 'i');
  v_normalized := replace(v_normalized, 'ó', 'o');
  v_normalized := replace(v_normalized, 'ú', 'u');
  v_normalized := regexp_replace(v_normalized, '[^a-z0-9]+', '', 'g');

  if v_normalized like '%ecosistema%' then
    return true;
  end if;

  if v_normalized like '%compatible%'
     and v_normalized not like '%genericocompatible%' then
    return true;
  end if;

  v_has_brand_family := v_normalized like '%shimano%'
    or v_normalized like '%sram%'
    or v_normalized like '%campagnolo%'
    or v_normalized like '%microshift%';

  if not v_has_brand_family then
    return false;
  end if;

  v_has_exact_semantics := v_normalized like '%hg%'
    or v_normalized like '%sis%'
    or v_normalized like '%dynasys%'
    or v_normalized like '%linkglide%'
    or v_normalized like '%cues%'
    or v_normalized like '%exactactuation%'
    or v_normalized like '%xactuation%'
    or v_normalized like '%eagle%'
    or v_normalized like '%axs%'
    or v_normalized like '%flattop%'
    or v_normalized like '%ttype%'
    or v_normalized like '%transmission%'
    or v_normalized like '%advent%'
    or v_normalized like '%acolyte%'
    or v_normalized like '%friccion%'
    or v_normalized like '%universal%'
    or v_normalized like '%single%'
    or v_normalized like '%bmx%'
    or v_normalized like '%ruta%';

  return not v_has_exact_semantics;
end;
$$;

create or replace function public.validate_product_spec_value_exact_drivetrain_fields()
returns trigger
language plpgsql
as $$
declare
  v_spec_key text;
  v_raw_value text;
begin
  select sd.key
    into v_spec_key
    from public.spec_definitions sd
   where sd.id = new.spec_definition_id;

  if v_spec_key not in ('drivetrain_platform', 'shift_actuation_family') then
    return new;
  end if;

  v_raw_value := btrim(coalesce(
    new.value_option,
    new.value_text,
    case
      when new.value_json is not null and jsonb_typeof(new.value_json) = 'string'
        then new.value_json #>> '{}'
      else null
    end,
    new.display_value,
    ''
  ));

  if v_raw_value = '' then
    return new;
  end if;

  if v_spec_key = 'drivetrain_platform' then
    if not (v_raw_value = any (array[
      'Shimano HG / SIS',
      'Shimano Hyperglide+',
      'Shimano Linkglide / CUES',
      'SRAM Eagle',
      'SRAM FlatTop / AXS road',
      'SRAM T-Type Transmission',
      'Campagnolo',
      'Microshift Advent / Acolyte',
      'Friccion / universal',
      'Single speed / BMX',
      'Generico compatible',
      'Desconocido / sin confirmar'
    ]))
       and public.is_broad_drivetrain_ecosystem_claim(v_raw_value) then
      raise exception
        'drivetrain_platform must store an exact platform label, not a broad ecosystem claim (%).',
        v_raw_value
        using errcode = '23514';
    end if;
  end if;

  if v_spec_key = 'shift_actuation_family' then
    if not (v_raw_value = any (array[
      'Shimano SIS 6-9v',
      'Shimano Dynasys 10v',
      'Shimano Dynasys 11/12v',
      'Shimano CUES / Linkglide',
      'Shimano ruta',
      'SRAM Exact Actuation',
      'SRAM X-Actuation / Eagle',
      'SRAM AXS road / FlatTop',
      'SRAM T-Type Transmission',
      'Campagnolo',
      'Microshift Advent / Acolyte',
      'Friccion / universal',
      'Otro',
      'Desconocido / sin confirmar'
    ]))
       and public.is_broad_drivetrain_ecosystem_claim(v_raw_value) then
      raise exception
        'shift_actuation_family must store an exact actuation/indexing label, not a broad ecosystem claim (%).',
        v_raw_value
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_product_spec_value_exact_drivetrain_fields on public.product_spec_values;
create trigger trg_validate_product_spec_value_exact_drivetrain_fields
  before insert or update of spec_definition_id, value_text, value_option, value_json, display_value
  on public.product_spec_values
  for each row
  execute function public.validate_product_spec_value_exact_drivetrain_fields();