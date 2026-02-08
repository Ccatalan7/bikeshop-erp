-- Update 'En Curso' to trigger Start
UPDATE job_statuses 
SET triggers_start = true 
WHERE name = 'En Curso' AND triggers_start = false;

-- Update 'Finalizado' to trigger Completion
UPDATE job_statuses 
SET triggers_completion = true 
WHERE name = 'Finalizado' AND triggers_completion = false;

-- Update 'Entregado' to trigger Delivery
UPDATE job_statuses 
SET triggers_delivery = true 
WHERE name = 'Entregado' AND triggers_delivery = false;
