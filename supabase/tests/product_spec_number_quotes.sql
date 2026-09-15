-- A numeric quote is exact evidence, not integer-zero trimming or arithmetic.
begin;
set local client_min_messages=error;
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0210000-0000-4000-8000-000000000001','Numeric quote boundary');
insert into public.spec_definitions(id,tenant_id,key,label,data_type,is_filterable,validation_rules)
 values('c0210000-0000-4000-8000-000000000011','c0210000-0000-4000-8000-000000000001','quoted_number','Número','number',true,'{}');
create function pg_temp.reading(p_value jsonb,p_quote text) returns text language sql stable as $$
 select public.spec_reading_rejection_internal_v1('c0210000-0000-4000-8000-000000000011',p_value,p_quote)
$$;
select is(pg_temp.reading(value,quote),null,label) from (values
 ('10'::jsonb,'10','integer 10 retains its zero'),
 ('100'::jsonb,'100 mm','integer 100 retains every zero'),
 ('0'::jsonb,'0 mm','zero does not become an empty expression'),
 ('10.00'::jsonb,'10 mm','only fractional zeroes may disappear'),
 ('10'::jsonb,'10.000 mm','equivalent fractional quote zeroes are accepted'),
 ('"1.2300"'::jsonb,'1.230 mm','exact decimal strings retain their value'),
 ('-10'::jsonb,'-10°','negative integer retains its sign and zero'),
 ('-10'::jsonb,'−10°','the Unicode minus remains negative'),
 ('10'::jsonb,'+10°','an explicit positive sign is accepted'),
 ('0.5'::jsonb,'0.50 mm','fractional zero does not change a measurement'),
 ('"9007199254740993"'::jsonb,'9007199254740993','large integers never pass through a float'),
 ('"0.100000000000000001"'::jsonb,'0.100000000000000001','fractional precision is exact'),
 ('48'::jsonb,'48 MM','the original ordinary-number behavior is retained'),
 ('10'::jsonb,'12 x 10 mm','a whole number can occur among other dimensions')
) cases(value,quote,label);
select is(pg_temp.reading(value,quote),'la cita no trae ese número',label) from (values
 ('10'::jsonb,'1','ten is not one'),
 ('100'::jsonb,'10','one hundred is not ten'),
 ('0'::jsonb,'ninguna cifra','empty numeric patterns cannot accept prose'),
 ('0'::jsonb,'1','zero is not supported by any other digit'),
 ('10'::jsonb,'-10','a negative does not prove a positive'),
 ('10'::jsonb,'−10','Unicode minus cannot prove a positive'),
 ('-10'::jsonb,'10','a positive does not prove a negative'),
 ('1'::jsonb,'10','a prefix is not the whole integer'),
 ('0.1'::jsonb,'0.12','a prefix is not the whole decimal'),
 ('10'::jsonb,'10,5','a comma decimal is not its integer prefix'),
 ('5'::jsonb,'10,5','a comma decimal is not its fractional suffix'),
 ('2'::jsonb,'1e2','an exponent is not an independent number'),
 ('1'::jsonb,'1e2','scientific notation is not its mantissa alone'),
 ('100'::jsonb,'1e2','this literal evidence path does not interpret scientific notation'),
 ('80'::jsonb,'48 MM','an unrelated number is not evidence'),
 ('"0.100000000000000001"'::jsonb,'0.100000000000000002','nearby exact fractions stay different')
) cases(value,quote,label);
select is(pg_temp.reading(value,'10'),'el valor no es un número',label) from (values
 ('null'::jsonb,'JSON null is not a number'),
 (null::jsonb,'SQL null is not a number'),
 ('true'::jsonb,'boolean is not a number'),
 ('[]'::jsonb,'array is not a number'),
 ('{}'::jsonb,'object is not a number'),
 ('"NaN"'::jsonb,'NaN is not a physical measurement'),
 ('"Infinity"'::jsonb,'positive infinity is not a physical measurement'),
 ('"-Infinity"'::jsonb,'negative infinity is not a physical measurement'),
 ('"abc"'::jsonb,'non-numeric text is rejected')
) cases(value,label);
select ok(not has_function_privilege(role,'public.spec_reading_rejection_internal_v1(uuid,jsonb,text)','execute'),role||' cannot bypass the authenticated reading writer')
 from unnest(array['anon','authenticated']) role;
select * from finish();
rollback;
