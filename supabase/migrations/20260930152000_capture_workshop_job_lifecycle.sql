-- C5: make the effective production job lifecycle reproducible.
-- This captures its reviewed body without changing production behavior.
-- The legacy local bootstrap consumed stock/booked journals during close;
-- this effective body does neither. Local fixture/UI evidence is documented
-- in PLANS.md; the production gate compares the exact normalized definition.
begin;

CREATE OR REPLACE FUNCTION public.handle_mechanic_job_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_old_status text; v_new_status text; v_should_consume_inventory boolean := false; v_should_restore_inventory boolean := false; v_should_create_journal boolean := false; v_should_delete_journal boolean := false;
begin
  if pg_trigger_depth() > 1 then if TG_OP = 'DELETE' then return OLD; else return NEW; end if; end if;
  if TG_OP = 'INSERT' then
    if TG_WHEN = 'BEFORE' then if NEW.job_number is null or NEW.job_number = '' then NEW.job_number := public.generate_mechanic_job_number(); end if; if NEW.status = 'EN_CURSO' and NEW.started_at is null then NEW.started_at := now(); end if; if NEW.status = 'FINALIZADO' and NEW.completed_at is null then NEW.completed_at := now(); end if; if NEW.status = 'ENTREGADO' and NEW.delivered_at is null then NEW.delivered_at := now(); end if; return NEW; end if;
    if TG_WHEN = 'AFTER' then perform public.log_mechanic_job_timeline(NEW.id,'created',null,NEW.status,'Job created: ' || coalesce(NEW.client_request, 'Service request')); if NEW.status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then v_should_consume_inventory := true; end if; if NEW.status in ('FINALIZADO', 'ENTREGADO') and not NEW.is_invoiced then v_should_create_journal := true; end if; end if; return NEW;
  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status; v_new_status := NEW.status;
    if v_old_status <> v_new_status then
      perform public.log_mechanic_job_timeline(NEW.id,'status_changed',v_old_status,v_new_status,'Status changed from ' || v_old_status || ' to ' || v_new_status);
      if v_new_status = 'EN_CURSO' and NEW.started_at is null then NEW.started_at := now(); end if; if v_new_status = 'FINALIZADO' and NEW.completed_at is null then NEW.completed_at := now(); end if; if v_new_status = 'ENTREGADO' and NEW.delivered_at is null then NEW.delivered_at := now(); end if;
      if NEW.invoice_id is not null then if v_new_status = 'ENTREGADO' then update public.sales_invoices set status = 'enviado', updated_at = now() where id = NEW.invoice_id and status = 'draft'; elsif v_new_status = 'CANCELADO' then update public.sales_invoices set status = 'cancelado', updated_at = now() where id = NEW.invoice_id and status != 'paid'; end if; end if;
      if v_old_status not in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') and v_new_status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then v_should_consume_inventory := true; elsif v_old_status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') and v_new_status = 'CANCELADO' then v_should_restore_inventory := true; end if;
      if v_new_status in ('FINALIZADO', 'ENTREGADO') and v_old_status not in ('FINALIZADO', 'ENTREGADO') and not NEW.is_invoiced then v_should_create_journal := true; elsif v_new_status = 'CANCELADO' and v_old_status in ('FINALIZADO', 'ENTREGADO') then v_should_delete_journal := true; end if;
    end if;

    -- 🌟 Link Bridge Fix: If invoice_id is newly linked, force a Forward Sync!
    if NEW.invoice_id is not null and OLD.invoice_id is null then
      perform public.sync_invoice_items_to_job(NEW.invoice_id);
      perform public.sync_invoice_status_to_job(NEW.invoice_id);
    end if;

    if OLD.diagnosis is distinct from NEW.diagnosis and NEW.diagnosis is not null then perform public.log_mechanic_job_timeline(NEW.id,'diagnosis_added',null,null,'Diagnosis updated'); end if;
    if OLD.assigned_to is distinct from NEW.assigned_to then perform public.log_mechanic_job_timeline(NEW.id,'assigned',OLD.assigned_technician_name,NEW.assigned_technician_name,'Technician assigned'); end if;
    if OLD.approved_by_customer <> NEW.approved_by_customer and NEW.approved_by_customer then perform public.log_mechanic_job_timeline(NEW.id,'approved',null,null,'Customer approved the work'); end if;
    if OLD.is_invoiced <> NEW.is_invoiced and NEW.is_invoiced then perform public.log_mechanic_job_timeline(NEW.id,'invoiced',null,NEW.invoice_id::text,'Job invoiced'); v_should_delete_journal := true; end if;
    return NEW;
  elsif TG_OP = 'DELETE' then
    if OLD.status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then perform public.restore_mechanic_job_inventory(OLD.id); end if;
    perform public.delete_mechanic_job_journal_entry(OLD.id); return OLD;
  end if;
end;
$function$;

-- Preserve the effective production ACL when rebuilding from the older base.
revoke all on function public.handle_mechanic_job_change()
  from public, anon, authenticated, service_role;
grant execute on function public.handle_mechanic_job_change() to service_role;

commit;
