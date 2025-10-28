-- =====================================================
-- Seed Chart of Accounts for Existing Tenants
-- =====================================================
-- Purpose: Add missing accounts to existing tenants
-- Run this ONCE after deploying the new account structure
-- =====================================================

do $$
declare
  v_tenant record;
  v_inserted_count integer := 0;
  v_deleted_count integer := 0;
begin
  -- Loop through all active tenants
  for v_tenant in 
    select id, shop_name 
    from public.tenants 
    where is_active = true
  loop
    raise notice 'Processing tenant: % (%)', v_tenant.shop_name, v_tenant.id;
    
    -- STEP 1: Migrate journal_lines from duplicate accounts to unified accounts
    -- Map old account codes to new unified codes
    update public.journal_lines
    set 
      account_id = (select id from public.accounts where tenant_id = v_tenant.id and code = '1130'),
      account_code = '1130',
      account_name = 'Cuentas por Cobrar Comerciales'
    where account_id in (
      select id from public.accounts 
      where tenant_id = v_tenant.id and code = '110200'
    );
    
    update public.journal_lines
    set 
      account_id = (select id from public.accounts where tenant_id = v_tenant.id and code = '1105'),
      account_code = '1105',
      account_name = 'Inventarios'
    where account_id in (
      select id from public.accounts 
      where tenant_id = v_tenant.id and code in ('140000', '1150')
    );
    
    update public.journal_lines
    set 
      account_id = (select id from public.accounts where tenant_id = v_tenant.id and code = '4100'),
      account_code = '4100',
      account_name = 'Ingresos Operacionales'
    where account_id in (
      select id from public.accounts 
      where tenant_id = v_tenant.id and code = '410000'
    );
    
    update public.journal_lines
    set 
      account_id = (select id from public.accounts where tenant_id = v_tenant.id and code = '5100'),
      account_code = '5100',
      account_name = 'Costo de Ventas'
    where account_id in (
      select id from public.accounts 
      where tenant_id = v_tenant.id and code = '510000'
    );
    
    raise notice '✅ Migrated journal lines to unified accounts';
    
    -- STEP 2: Delete duplicate/obsolete accounts (now safe since journal_lines migrated)
    delete from public.accounts 
    where tenant_id = v_tenant.id 
    and code in (
      '110200',  -- Old: Accounts Receivable (duplicate of 1130)
      '140000',  -- Old: Inventory (duplicate of 1105)
      '1150',    -- Old: Inventarios de Mercaderías (duplicate of 1105)
      '410000',  -- Old: Service Revenue (duplicate of 4100)
      '510000'   -- Old: Costo de Ventas (duplicate of 5100)
    );
    
    get diagnostics v_deleted_count = row_count;
    if v_deleted_count > 0 then
      raise notice '🗑️  Deleted % duplicate accounts', v_deleted_count;
    end if;
    
    -- STEP 3: Insert unified accounts (ON CONFLICT will update existing ones)
    insert into public.accounts (tenant_id, code, name, type, category, description, is_active)
    values
      -- ============================================================================
      -- ASSETS (1xxx) - Activos
      -- ============================================================================
      (v_tenant.id, '1101', 'Caja General', 'asset', 'currentAsset', 'Efectivo disponible en caja y fondos inmediatos', true),
      (v_tenant.id, '1110', 'Bancos - Cuenta Corriente', 'asset', 'currentAsset', 'Saldos disponibles en cuentas corrientes bancarias', true),
      (v_tenant.id, '1130', 'Cuentas por Cobrar Comerciales', 'asset', 'currentAsset', 'Saldos pendientes de cobro a clientes por ventas a crédito', true),
      (v_tenant.id, '1105', 'Inventarios', 'asset', 'currentAsset', 'Valor del inventario de productos y repuestos', true),
      (v_tenant.id, '1107', 'IVA Crédito Fiscal', 'asset', 'currentAsset', 'IVA pagado en compras, recuperable', true),
      (v_tenant.id, '1190', 'Otros Activos Corrientes', 'asset', 'currentAsset', 'Activos circulantes no clasificados en otra cuenta específica', true),

      -- ============================================================================
      -- LIABILITIES (2xxx) - Pasivos
      -- ============================================================================
      (v_tenant.id, '2101', 'Cuentas por Pagar Proveedores', 'liability', 'currentLiability', 'Obligaciones con proveedores', true),
      (v_tenant.id, '2150', 'IVA Débito Fiscal', 'liability', 'currentLiability', 'IVA generado en ventas', true),
      (v_tenant.id, '210200', 'IVA por Pagar', 'liability', 'currentLiability', 'IVA a pagar al SII', true),

      -- ============================================================================
      -- EQUITY (3xxx) - Patrimonio
      -- ============================================================================
      (v_tenant.id, '3101', 'Capital', 'equity', 'capital', 'Capital aportado por los socios', true),
      (v_tenant.id, '3201', 'Utilidades Retenidas', 'equity', 'retainedEarnings', 'Utilidades acumuladas de ejercicios anteriores', true),

      -- ============================================================================
      -- REVENUE (4xxx) - Ingresos
      -- ============================================================================
      (v_tenant.id, '4100', 'Ingresos Operacionales', 'income', 'operatingIncome', 'Ingresos operacionales por ventas y servicios', true),

      -- ============================================================================
      -- EXPENSES (5xxx) - Gastos
      -- ============================================================================
      (v_tenant.id, '5100', 'Costo de Ventas', 'expense', 'costOfGoodsSold', 'Costo de ventas de productos y servicios', true),
      (v_tenant.id, '610100', 'Sueldos y Salarios', 'expense', 'operatingExpense', 'Remuneraciones del personal y pagos de nómina', true),
      (v_tenant.id, '610200', 'Cotizaciones Previsionales y Salud', 'expense', 'operatingExpense', 'Aportes previsionales, salud y seguros obligatorios del personal', true),
      (v_tenant.id, '610300', 'Honorarios Profesionales', 'expense', 'operatingExpense', 'Servicios profesionales externos y consultorías', true),
      (v_tenant.id, '620100', 'Arriendo de Locales', 'expense', 'operatingExpense', 'Pagos de arriendo de oficinas, locales y bodegas', true),
      (v_tenant.id, '620200', 'Servicios Básicos', 'expense', 'operatingExpense', 'Consumo de electricidad, agua, gas y otros servicios básicos', true),
      (v_tenant.id, '620300', 'Telefonía e Internet', 'expense', 'operatingExpense', 'Planes de telefonía fija, móvil y servicios de internet', true),
      (v_tenant.id, '620400', 'Mantención y Reparaciones', 'expense', 'operatingExpense', 'Gastos de mantenimiento preventivo y correctivo de infraestructura y equipos', true),
      (v_tenant.id, '620500', 'Suministros de Oficina', 'expense', 'operatingExpense', 'Materiales de oficina, papelería e insumos administrativos', true),
      (v_tenant.id, '630100', 'Marketing y Publicidad', 'expense', 'operatingExpense', 'Campañas de marketing, publicidad y promoción de la marca', true),
      (v_tenant.id, '630200', 'Comisiones y Servicios de Venta', 'expense', 'operatingExpense', 'Comisiones pagadas a vendedores y servicios relacionados con ventas', true),
      (v_tenant.id, '640100', 'Gastos de Viaje y Viáticos', 'expense', 'operatingExpense', 'Traslados, alojamiento y viáticos del personal', true),
      (v_tenant.id, '640200', 'Capacitación y Desarrollo', 'expense', 'operatingExpense', 'Programas de formación, cursos y certificaciones del personal', true),
      (v_tenant.id, '650100', 'Seguros Generales', 'expense', 'operatingExpense', 'Primas de seguros patrimoniales, de responsabilidad y otros', true),
      (v_tenant.id, '650200', 'Impuestos y Contribuciones Municipales', 'expense', 'taxExpense', 'Patentes, contribuciones y otros impuestos municipales', true),
      (v_tenant.id, '660100', 'Intereses y Gastos Financieros', 'expense', 'financialExpense', 'Intereses de créditos, comisiones bancarias y costos financieros', true),
      (v_tenant.id, '670100', 'Depreciación y Amortización', 'expense', 'operatingExpense', 'Gastos por depreciación de activos fijos y amortización de intangibles', true),
      (v_tenant.id, '680100', 'Gastos Varios', 'expense', 'operatingExpense', 'Gastos generales menores no clasificados en otras cuentas específicas', true)
    on conflict (tenant_id, code) do update
    set
      name = excluded.name,
      type = excluded.type,
      category = excluded.category,
      description = coalesce(excluded.description, accounts.description),
      is_active = true,
      updated_at = now();
    
    get diagnostics v_inserted_count = row_count;
    raise notice '✅ Processed % accounts for tenant %', v_inserted_count, v_tenant.shop_name;
  end loop;

  raise notice '🎉 All tenants have been seeded with the complete chart of accounts';
end $$;
