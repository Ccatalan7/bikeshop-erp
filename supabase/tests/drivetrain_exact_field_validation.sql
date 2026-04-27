begin;

select plan(3);

create temp table tmp_drivetrain_validation_results (
  test_name text primary key,
  passed boolean not null
);

insert into public.tenants (id, shop_name)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Drivetrain Validation Tenant');

insert into public.products (
  id,
  tenant_id,
  name,
  sku,
  price,
  cost,
  is_service,
  product_type,
  track_stock,
  stock_quantity,
  inventory_qty,
  min_stock_level,
  max_stock_level
)
values
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Producto exacto plataforma', 'DRV-VAL-1', 1000, 500, false, 'product', true, 0, 0, 0, 0),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Producto broad plataforma', 'DRV-VAL-2', 1000, 500, false, 'product', true, 0, 0, 0, 0),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Producto broad actuation', 'DRV-VAL-3', 1000, 500, false, 'product', true, 0, 0, 0, 0);

do $$
begin
  begin
    insert into public.product_spec_values (
      tenant_id,
      product_id,
      spec_definition_id,
      value_option,
      display_value
    )
    values (
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
      (select id from public.spec_definitions where tenant_id is null and key = 'drivetrain_platform'),
      'Shimano Hyperglide+',
      'Shimano Hyperglide+'
    );

    insert into tmp_drivetrain_validation_results values ('exact_platform_accepts_exact_value', true);
  exception
    when others then
      insert into tmp_drivetrain_validation_results values ('exact_platform_accepts_exact_value', false);
  end;

  begin
    insert into public.product_spec_values (
      tenant_id,
      product_id,
      spec_definition_id,
      value_option,
      display_value
    )
    values (
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
      (select id from public.spec_definitions where tenant_id is null and key = 'drivetrain_platform'),
      'Shimano',
      'Shimano'
    );

    insert into tmp_drivetrain_validation_results values ('exact_platform_rejects_broad_value', false);
  exception
    when check_violation then
      insert into tmp_drivetrain_validation_results values ('exact_platform_rejects_broad_value', true);
    when others then
      insert into tmp_drivetrain_validation_results values ('exact_platform_rejects_broad_value', false);
  end;

  begin
    insert into public.product_spec_values (
      tenant_id,
      product_id,
      spec_definition_id,
      value_option,
      display_value
    )
    values (
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3',
      (select id from public.spec_definitions where tenant_id is null and key = 'shift_actuation_family'),
      'Ecosistema SRAM',
      'Ecosistema SRAM'
    );

    insert into tmp_drivetrain_validation_results values ('exact_actuation_rejects_broad_value', false);
  exception
    when check_violation then
      insert into tmp_drivetrain_validation_results values ('exact_actuation_rejects_broad_value', true);
    when others then
      insert into tmp_drivetrain_validation_results values ('exact_actuation_rejects_broad_value', false);
  end;
end $$;

select ok(
  (select passed from tmp_drivetrain_validation_results where test_name = 'exact_platform_accepts_exact_value'),
  'exact drivetrain platform values are accepted'
);

select ok(
  (select passed from tmp_drivetrain_validation_results where test_name = 'exact_platform_rejects_broad_value'),
  'broad drivetrain platform claims are rejected'
);

select ok(
  (select passed from tmp_drivetrain_validation_results where test_name = 'exact_actuation_rejects_broad_value'),
  'broad shift actuation claims are rejected'
);

select * from finish();

rollback;