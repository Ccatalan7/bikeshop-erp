-- Auto-link employee to user when invitation is accepted
-- This trigger ensures bidirectional linking between employees and users

create or replace function public.handle_user_invitation_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only process if invitation was just accepted (status changed to 'accepted')
  if NEW.status = 'accepted' and (OLD.status is null or OLD.status != 'accepted') then
    -- If invitation has employee_id, link the new user to the employee
    if NEW.employee_id is not null then
      -- Update employee record with user_id from metadata (set during signup)
      update employees
      set user_id = (NEW.metadata->>'user_id')::uuid,
          updated_at = now()
      where id = NEW.employee_id
        and user_id is null; -- Only if not already linked
      
      raise notice 'Auto-linked employee % to user %', NEW.employee_id, (NEW.metadata->>'user_id');
    end if;
  end if;
  
  return NEW;
end;
$$;

-- Create trigger on user_invitations
drop trigger if exists trg_user_invitation_accepted on user_invitations;
create trigger trg_user_invitation_accepted
  after update on user_invitations
  for each row
  execute function public.handle_user_invitation_accepted();
