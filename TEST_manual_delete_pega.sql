-- Test if the trigger function can be called manually
DO $$
DECLARE
  test_record record;
BEGIN
  -- Create a fake OLD record to test the function
  test_record := ROW(
    'abce6bc5-052b-4d8a-8026-c63289b1cb10'::uuid,  -- id (invoice that was deleted)
    '5443b130-cc28-45af-a420-cd500b288890'::uuid   -- tenant_id
  );
  
  RAISE NOTICE 'Testing cascade_delete_pega_invoice function...';
  
  -- The function should find and delete pega '50baf3aa-3089-46ec-ad29-a76ec0b6d9ae'
  -- But since invoice is already deleted, it won't find anything
  
END $$;

-- Alternative: Check if we can manually call the function
-- (This won't work as-is because trigger functions need TG_* variables)
-- But let's try to delete the pega directly with the same logic:

DO $$
DECLARE
  v_pega_id uuid;
  v_count int;
BEGIN
  -- Find pega with NULL invoice_id (from our previous test)
  SELECT id INTO v_pega_id
  FROM mechanic_jobs
  WHERE id = '50baf3aa-3089-46ec-ad29-a76ec0b6d9ae';
  
  IF v_pega_id IS NOT NULL THEN
    RAISE NOTICE 'Found pega: %', v_pega_id;
    
    -- Try to delete it directly
    DELETE FROM mechanic_jobs WHERE id = v_pega_id;
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % rows', v_count;
  ELSE
    RAISE NOTICE 'Pega not found';
  END IF;
END $$;

-- Then verify it's deleted:
SELECT * FROM mechanic_jobs WHERE id = '50baf3aa-3089-46ec-ad29-a76ec0b6d9ae';
