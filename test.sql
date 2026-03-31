SELECT external_wa_id, outbound_type, delivery_status, error_details 
FROM whatsapp_messages 
ORDER BY created_at DESC 
LIMIT 5;
