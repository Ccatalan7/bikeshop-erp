-- Create some synthetic jobs and bike events to populate the Historial tab
DO $$
DECLARE
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_customer_id uuid := '33da9a32-e9b7-42e4-b442-ecc722541a6e';
  v_bike_id uuid := 'be0f8049-9f6d-489f-b497-db4d50be2944'; -- 'Test 1'
  v_job1_id uuid;
  v_job2_id uuid;
  v_user_id uuid;
BEGIN
  -- Get an active admin user for created_by
  SELECT id INTO v_user_id FROM auth.users LIMIT 1;

  -- Delete existing test events for this bike just in case to avoid clutter
  DELETE FROM public.bike_events WHERE bike_id = v_bike_id;
  
  -- Create Job 1 (completed in the past)
  INSERT INTO public.mechanic_jobs (
    tenant_id, customer_id, bike_id, job_number, status, client_request, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_customer_id, v_bike_id, 'PEGA-10001', 'COMPLETADA', 'Ajuste general frenos y transmisión', now() - interval '6 months', now() - interval '6 months'
  ) RETURNING id INTO v_job1_id;

  -- Create Job 2 (in progress now)
  INSERT INTO public.mechanic_jobs (
    tenant_id, customer_id, bike_id, job_number, status, client_request, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_customer_id, v_bike_id, 'PEGA-10150', 'EN PROCESO', 'Cambio neumático trasero', now() - interval '2 days', now() - interval '2 days'
  ) RETURNING id INTO v_job2_id;

  -- 1. Bike Registered (Oldest)
  INSERT INTO public.bike_events (
    tenant_id, bike_id, event_category, event_type, event_date, title, summary, source, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, 'state', 'bike_registered', now() - interval '1 year', 'Bicicleta registrada', 'Primera vez que ingresa al taller', 'system', now() - interval '1 year', now() - interval '1 year'
  );

  -- 2. Profile created
  INSERT INTO public.bike_events (
    tenant_id, bike_id, event_category, event_type, event_date, title, summary, source, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, 'state', 'profile_created', now() - interval '11 months', 'Perfil base creado', 'Se registraron los frenos y tipo de transmisión', 'system', now() - interval '11 months', now() - interval '11 months'
  );

  -- 3. Job 1 Created
  INSERT INTO public.bike_events (
    tenant_id, bike_id, job_id, event_category, event_type, event_date, title, summary, source, reference_number, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, v_job1_id, 'visit', 'job_created', now() - interval '6 months', 'Trabajo ingresado', 'Ingreso por mantenimiento general', 'system', 'PEGA-10001', now() - interval '6 months', now() - interval '6 months'
  );

  -- 4. Component Replaced (during Job 1)
  INSERT INTO public.bike_events (
    tenant_id, bike_id, job_id, event_category, event_type, event_date, title, summary, source, reference_number, severity, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, v_job1_id, 'component', 'component_replaced', now() - interval '6 months' + interval '2 days', 'Reemplazo Cadena', 'Cadena muy estirada. Se instaló Shimano HG-53', 'manual', 'PEGA-10001', 'info', now() - interval '6 months' + interval '2 days', now() - interval '6 months' + interval '2 days'
  );

  -- 5. Job 1 Completed
  INSERT INTO public.bike_events (
    tenant_id, bike_id, job_id, event_category, event_type, event_date, title, summary, source, reference_number, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, v_job1_id, 'visit', 'job_completed', now() - interval '6 months' + interval '3 days', 'Trabajo finalizado y entregado', 'Cliente retiró la bicicleta', 'system', 'PEGA-10001', now() - interval '6 months' + interval '3 days', now() - interval '6 months' + interval '3 days'
  );

  -- 6. Incident / Diagnosis
  INSERT INTO public.bike_events (
    tenant_id, bike_id, event_category, event_type, event_date, title, summary, source, severity, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, 'incident', 'incident_reported', now() - interval '2 months', 'Reporte de ruido en motor', 'Cliente escribe por Whatsapp indicando crujido al pedalear fuerte.', 'manual', 'warning', now() - interval '2 months', now() - interval '2 months'
  );

  -- 7. Job 2 Created (Recent)
  INSERT INTO public.bike_events (
    tenant_id, bike_id, job_id, event_category, event_type, event_date, title, summary, source, reference_number, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, v_job2_id, 'visit', 'job_created', now() - interval '2 days', 'Nuevo ingreso a taller', 'Revisión por ruido en motor y pinchazo', 'system', 'PEGA-10150', now() - interval '2 days', now() - interval '2 days'
  );

  -- 8. Profile Updated (Recent)
  INSERT INTO public.bike_events (
    tenant_id, bike_id, event_category, event_type, event_date, title, summary, source, created_at, updated_at
  ) VALUES (
    v_tenant_id, v_bike_id, 'evidence', 'profile_updated', now() - interval '1 day', 'Actualización de especificaciones', 'Mecánico confirmó medida de motor BSA 68mm', 'system', now() - interval '1 day', now() - interval '1 day'
  );

END $$;
