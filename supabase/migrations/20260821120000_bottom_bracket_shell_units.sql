-- La caja de motor con la medida en milímetros y la pulgada entre paréntesis.
--
-- La inglesa se cataloga como 1.37" x 24 y esa es la sigla impresa en la pieza,
-- pero la medida con la que se trabaja acá es 34,8 mm. Van las dos, con el
-- milímetro adelante: `BSA / Caja inglesa 34,8 mm (1.37") x 24`.
--
-- De paso el resto tenía la unidad a medias — «BB86 / BB92 41mm» sin espacio,
-- «Mid BMX 41.2mm» con punto decimal. Quedan parejas y con coma, que es como
-- se escribe un decimal en Chile.
--
-- Sólo se toca `bb_shell_standard`. Las pulgadas de rueda, cubierta, bolita y
-- tubo de dirección son nomenclatura propia de esas familias.
--
-- Los reemplazos usan la comilla del JSON como límite (`"viejo"` → `"nuevo"`),
-- así que son exactos y se pueden repetir sin acumular.

begin;

update public.spec_definitions set
  allowed_values =
    '["BSA / Caja inglesa 34,8 mm (1.37\") x 24","Italiano 36 mm x 24",'
    '"T47 47 mm","Francés 35 mm x 1","Suizo 35 mm x 1",'
    '"Euro BMX roscado 68 mm","BB86 / BB92 41 mm","PF30 46 mm","BB30 42 mm",'
    '"BB386EVO 46 mm","BB90 / BB95","BBRight / OSBB","Mid BMX 41,2 mm",'
    '"Spanish BMX 37 mm","Americano 51,5 mm"]'::jsonb,
  updated_at = now()
where key = 'bb_shell_standard' and tenant_id is null;

update public.spec_template_fields tf set
  visibility_rules = replace(replace(replace(replace(replace(replace(replace(
    replace(replace(replace(replace(replace(replace(tf.visibility_rules::text,
    '"BSA / Caja inglesa 1.37x24"', '"BSA / Caja inglesa 34,8 mm (1.37\") x 24"'),
    '"Italiano 36x24"', '"Italiano 36 mm x 24"'),
    '"T47"', '"T47 47 mm"'),
    '"Francés 35x1"', '"Francés 35 mm x 1"'),
    '"Suizo 35x1"', '"Suizo 35 mm x 1"'),
    '"Euro BMX roscado 68"', '"Euro BMX roscado 68 mm"'),
    '"BB86 / BB92 41mm"', '"BB86 / BB92 41 mm"'),
    '"PF30 46mm"', '"PF30 46 mm"'),
    '"BB30 42mm"', '"BB30 42 mm"'),
    '"BB386EVO 46mm"', '"BB386EVO 46 mm"'),
    '"Mid BMX 41.2mm"', '"Mid BMX 41,2 mm"'),
    '"Spanish BMX 37mm"', '"Spanish BMX 37 mm"'),
    '"Americano 51.5mm"', '"Americano 51,5 mm"')::jsonb,
  option_rules = replace(replace(replace(replace(replace(replace(replace(
    replace(replace(replace(replace(replace(replace(tf.option_rules::text,
    '"BSA / Caja inglesa 1.37x24"', '"BSA / Caja inglesa 34,8 mm (1.37\") x 24"'),
    '"Italiano 36x24"', '"Italiano 36 mm x 24"'),
    '"T47"', '"T47 47 mm"'),
    '"Francés 35x1"', '"Francés 35 mm x 1"'),
    '"Suizo 35x1"', '"Suizo 35 mm x 1"'),
    '"Euro BMX roscado 68"', '"Euro BMX roscado 68 mm"'),
    '"BB86 / BB92 41mm"', '"BB86 / BB92 41 mm"'),
    '"PF30 46mm"', '"PF30 46 mm"'),
    '"BB30 42mm"', '"BB30 42 mm"'),
    '"BB386EVO 46mm"', '"BB386EVO 46 mm"'),
    '"Mid BMX 41.2mm"', '"Mid BMX 41,2 mm"'),
    '"Spanish BMX 37mm"', '"Spanish BMX 37 mm"'),
    '"Americano 51.5mm"', '"Americano 51,5 mm"')::jsonb,
  updated_at = now()
from public.spec_templates t
where tf.template_id = t.id and t.key like 'bottom_bracket%';

update public.product_spec_values v set
  value_option = case v.value_option
    when 'BSA / Caja inglesa 1.37x24' then 'BSA / Caja inglesa 34,8 mm (1.37") x 24'
    when 'Italiano 36x24' then 'Italiano 36 mm x 24'
    when 'T47' then 'T47 47 mm'
    when 'Francés 35x1' then 'Francés 35 mm x 1'
    when 'Suizo 35x1' then 'Suizo 35 mm x 1'
    when 'Euro BMX roscado 68' then 'Euro BMX roscado 68 mm'
    when 'BB86 / BB92 41mm' then 'BB86 / BB92 41 mm'
    when 'PF30 46mm' then 'PF30 46 mm'
    when 'BB30 42mm' then 'BB30 42 mm'
    when 'BB386EVO 46mm' then 'BB386EVO 46 mm'
    when 'Mid BMX 41.2mm' then 'Mid BMX 41,2 mm'
    when 'Spanish BMX 37mm' then 'Spanish BMX 37 mm'
    when 'Americano 51.5mm' then 'Americano 51,5 mm'
    else v.value_option end,
  display_value = case v.value_option
    when 'BSA / Caja inglesa 1.37x24' then 'BSA / Caja inglesa 34,8 mm (1.37") x 24'
    when 'Italiano 36x24' then 'Italiano 36 mm x 24'
    when 'T47' then 'T47 47 mm'
    when 'Francés 35x1' then 'Francés 35 mm x 1'
    when 'Suizo 35x1' then 'Suizo 35 mm x 1'
    when 'Euro BMX roscado 68' then 'Euro BMX roscado 68 mm'
    when 'BB86 / BB92 41mm' then 'BB86 / BB92 41 mm'
    when 'PF30 46mm' then 'PF30 46 mm'
    when 'BB30 42mm' then 'BB30 42 mm'
    when 'BB386EVO 46mm' then 'BB386EVO 46 mm'
    when 'Mid BMX 41.2mm' then 'Mid BMX 41,2 mm'
    when 'Spanish BMX 37mm' then 'Spanish BMX 37 mm'
    when 'Americano 51.5mm' then 'Americano 51,5 mm'
    else v.display_value end,
  updated_at = now()
from public.spec_definitions d
where v.spec_definition_id = d.id and d.key = 'bb_shell_standard';

commit;
