-- Verifier: fails (division by zero) while the tube fit rows stay hidden from the storefront or keep the old label.
select 1/(case when (select count(*) from public.spec_definitions where tenant_id is null and key='tube_fit_rows' and is_customer_visible and label='Aro y ancho de neumático' and not is_filterable)=1 then 1 else 0 end) as ok;
