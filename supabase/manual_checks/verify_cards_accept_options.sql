-- Read-back: la validación acepta la tarjeta con opciones y sigue rechazando
-- lo que no corresponde.
select
  1 / (case when public.assistant_cards_valid_v1('[{
    "kind": "customer_contact",
    "title": "Marcelo Silva",
    "destination": "conversations",
    "chips": [],
    "entityRef": {"kind": "customer", "id": "11111111-1111-4111-8111-111111111111"},
    "optionKind": "whatsapp_template",
    "options": [
      {"id": "bicicleta_lista_retiro", "label": "Lista para retiro",
       "description": "Hola Marcelo, tu bicicleta esta lista."}
    ]
  }]'::jsonb) then 1 else 0 end) as acepta_la_tarjeta,
  -- Una familia de opciones sin opciones no ofrece nada.
  1 / (case when not public.assistant_cards_valid_v1('[{
    "kind": "customer_contact", "title": "X", "destination": "conversations",
    "chips": [], "optionKind": "whatsapp_template"
  }]'::jsonb) then 1 else 0 end) as rechaza_familia_vacia,
  -- Una clave desconocida sigue rechazándose.
  1 / (case when not public.assistant_cards_valid_v1('[{
    "kind": "customer_contact", "title": "X", "destination": "conversations",
    "chips": [], "algoRaro": 1
  }]'::jsonb) then 1 else 0 end) as rechaza_clave_ajena,
  -- Y una tarjeta de inventario de siempre sigue siendo válida.
  1 / (case when public.assistant_cards_valid_v1('[{
    "kind": "customer", "title": "Cliente", "destination": "customers",
    "chips": [],
    "entityRef": {"kind": "customer", "id": "11111111-1111-4111-8111-111111111111"}
  }]'::jsonb) then 1 else 0 end) as no_rompe_lo_anterior;
