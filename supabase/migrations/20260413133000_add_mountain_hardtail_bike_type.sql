alter table public.bikes drop constraint if exists bikes_bike_type_check;

alter table public.bikes add constraint bikes_bike_type_check check (
  bike_type in (
    'road',
    'mountain',
    'mountain_hardtail',
    'hybrid',
    'electric',
    'bmx',
    'folding',
    'cruiser',
    'gravel',
    'other'
  )
);

update public.bikes as b
set bike_type = case bp.technical_profile -> 'values' ->> 'bikeStyle'
  when 'mountain_full_suspension' then 'mountain'
  when 'mountain_hardtail' then 'mountain_hardtail'
  when 'road' then 'road'
  when 'gravel' then 'gravel'
  when 'commuter' then 'hybrid'
  when 'electric' then 'electric'
  when 'bmx' then 'bmx'
  when 'fixie' then 'other'
  else b.bike_type
end
from public.bike_profiles as bp
where bp.bike_id = b.id
  and coalesce(bp.technical_profile -> 'values' ->> 'bikeStyle', '') <> '';
