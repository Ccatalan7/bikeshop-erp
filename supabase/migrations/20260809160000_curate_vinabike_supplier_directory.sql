-- Curated, evidence-backed enrichment for Vinabike's supplier directory.
-- High-confidence identity/contact facts come from official public sources;
-- operational classifications, engagements, and accounting posture also use
-- the tenant's own purchase/product/expense history. Ambiguous identities and
-- destructive duplicate merges are intentionally excluded.
begin;

create temporary table supplier_enrichment_manifest (
  rn integer primary key,
  supplier_id uuid not null,
  expected_name text not null,
  profile_patch jsonb not null,
  roles jsonb not null,
  capabilities jsonb not null,
  source_urls jsonb not null,
  classification_confidence text not null
) on commit drop;

insert into supplier_enrichment_manifest
select
  row.rn,
  row.supplier_id,
  row.expected_name,
  row.profile_patch,
  row.roles,
  row.capabilities,
  row.source_urls,
  row.classification_confidence
from jsonb_to_recordset($manifest$
[
  {
    "rn": 1,
    "supplier_id": "0df3cbca-2897-423b-a289-e26c96f9cb20",
    "expected_name": "Aliexpress",
    "profile_patch": {
      "display_name": "AliExpress",
      "party_kind": "organization",
      "trade_name": "AliExpress",
      "website": "https://www.aliexpress.com/",
      "aliases": [
        "Aliexpress"
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.aliexpress.com/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 3,
    "supplier_id": "975eb429-4666-465a-b1ee-1305e719e708",
    "expected_name": "Andes Industrial",
    "profile_patch": {
      "display_name": "Andes Industrial",
      "party_kind": "organization",
      "legal_name": "Sociedad Importadora y Comercializadora Andes Industrial Limitada",
      "trade_name": "Andes Industrial",
      "tax_identifier": "85.390.800-2",
      "country_code": "CL",
      "website": "https://www.andesindustrial.cl/",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://www.andesindustrial.cl/cuenta/solicitudRegistro",
      "https://transparencia.mma.gob.cl/2025/FIRMADO_23042025IF_N39-2025_Neumaticos_redacted.pdf"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 4,
    "supplier_id": "642776bc-a25e-4df7-ac0a-2336a9e139c0",
    "expected_name": "Andes Life",
    "profile_patch": {
      "display_name": "AndesLife",
      "party_kind": "organization",
      "legal_name": "Inversiones Life SpA",
      "trade_name": "AndesLife",
      "tax_identifier": "76.188.262-7",
      "country_code": "CL",
      "website": "https://andeslife.cl/",
      "city": "Rancagua",
      "region": "Región del Libertador General Bernardo O'Higgins",
      "aliases": [
        "Andes Life"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [
      "https://andeslife.cl/10/quienes-somos",
      "https://www.portalchile.org/empresa/inversiones-life-spa-76188262"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 5,
    "supplier_id": "b9c2cd91-89ff-4d03-835d-40bb4eea77ef",
    "expected_name": "Atletis",
    "profile_patch": {
      "display_name": "Atletis",
      "party_kind": "organization",
      "legal_name": "Atletis SpA",
      "trade_name": "Atletis",
      "country_code": "CL",
      "website": "https://www.atletis.cl/"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [
      "https://www.atletis.cl/terminos-y-condiciones"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 6,
    "supplier_id": "9300316d-0de9-4378-9f3c-1c3bb0cf703b",
    "expected_name": "Bakery Lynch",
    "profile_patch": {
      "display_name": "Bakery Lynch",
      "party_kind": "organization",
      "trade_name": "Bakery Lynch",
      "country_code": "CL",
      "website": "https://bakerylynch.shop/",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso"
    },
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://bakerylynch.shop/",
      "https://es.restaurantguru.com/Bakery-Lynch-Vina-del-Mar"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 7,
    "supplier_id": "4259a875-7268-460f-bdbd-0151a0693895",
    "expected_name": "Bancook",
    "profile_patch": {},
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://chilepymes.com/info/andres-eduardo-munoz-olivares-vincent-bancook-inversiones-eirl-40CF7C6FA1F6B5A5"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 8,
    "supplier_id": "bd6a063a-b36b-481f-a1c0-b122a0355c12",
    "expected_name": "Bashka",
    "profile_patch": {
      "display_name": "Bashka",
      "party_kind": "organization",
      "trade_name": "Bashka Restaurant",
      "country_code": "CL",
      "phone": "+56 9 4173 4477",
      "address": "Álvarez 102",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Bashka"
      ]
    },
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://visitavina.munivina.cl/wp-content/uploads/2024/07/Restaurantes-en-Vina-del-Mar-2024.pdf",
      "https://www.ubereats.com/cl/store/bashka-restaurant/qI3k5PcDSbin0ZoXF5F5gQ"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 9,
    "supplier_id": "a7cc635f-7a3b-4e70-acfb-fd89098365a4",
    "expected_name": "BeldaBike",
    "profile_patch": {
      "display_name": "Belda Cycles",
      "party_kind": "organization",
      "legal_name": "Bicicletas Belda Limitada",
      "trade_name": "Belda Cycles",
      "tax_identifier": "78.295.500-4",
      "country_code": "CL",
      "website": "https://beldacycles.cl/",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "BeldaBike",
        "Belda Bike"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://beldacycles.cl/content/19-belda-cycles-vina-del-mar",
      "https://www.portalchile.org/empresa/bicicletas-belda-limitada-78295500"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 10,
    "supplier_id": "b5c67141-ac89-4298-a01d-f13d3e36c19d",
    "expected_name": "BettaBikes",
    "profile_patch": {
      "display_name": "Betta Bikes",
      "party_kind": "organization",
      "legal_name": "Reparaciones y Ventas Betta Bikes EIRL",
      "trade_name": "Betta Bikes",
      "tax_identifier": "77.078.097-7",
      "country_code": "CL",
      "website": "https://bettabikes.cl/",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "BettaBikes"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [
      "https://bettabikes.cl/servicio-tecnico/",
      "https://www.mercantil.com/empresa/reparaciones-y-ventas-betta-bikes/vina-del-mar/300324199/esp"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 11,
    "supplier_id": "8a4aad60-9d16-4ec4-8cf7-5d48b7cc1d37",
    "expected_name": "Bikepointstore",
    "profile_patch": {
      "display_name": "Bike Point Store",
      "party_kind": "organization",
      "trade_name": "Bike Point Store",
      "country_code": "CL",
      "website": "https://www.bikepointstore.cl/",
      "aliases": [
        "Bikepointstore",
        "BikePoint Store"
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [
      "https://www.bikepointstore.cl/",
      "https://www.bikepointstore.cl/terminos-y-condiciones-6"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 12,
    "supplier_id": "2f28fdda-efea-4b89-b2a9-38e25561a3dc",
    "expected_name": "BlueExpress",
    "profile_patch": {
      "display_name": "Blue Express",
      "party_kind": "organization",
      "legal_name": "Blue Express S.A.",
      "trade_name": "Blue Express",
      "tax_identifier": "96.938.840-5",
      "country_code": "CL",
      "email": "holacourier@blue.cl",
      "website": "https://www.blue.cl/",
      "address": "Av. El Retiro, Parque Los Maitenes 9800",
      "comuna": "Pudahuel",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "aliases": [
        "BlueExpress"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "logistics_provider"
    ],
    "capabilities": [
      "freight_transport"
    ],
    "source_urls": [
      "https://www.blue.cl/nosotros",
      "https://cdn.blue.cl/curmg/Politica-de-Privacidad-Blue-Express.pdf"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 14,
    "supplier_id": "ba2a8b6c-384e-4ab5-bc3a-264c429bae9f",
    "expected_name": "Capri",
    "profile_patch": {
      "display_name": "Capri",
      "country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [],
    "source_urls": [
      "https://officepro.cl/quienes-somos"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 15,
    "supplier_id": "da967286-89fd-4a5b-9244-b6acc72a5657",
    "expected_name": "Cesar el Piño",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 16,
    "supplier_id": "af6e54db-7474-42bc-b8e8-02b5048adc6c",
    "expected_name": "CGE",
    "profile_patch": {
      "display_name": "CGE",
      "party_kind": "organization",
      "legal_name": "Compañía General de Electricidad S.A.",
      "trade_name": "CGE",
      "tax_identifier": "76.411.321-7",
      "country_code": "CL",
      "email": "atencionclientes@cge.cl",
      "phone": "800 800 767",
      "website": "https://www.cge.cl/",
      "address": "Av. Presidente Riesco 5561, piso 17",
      "comuna": "Las Condes",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "tax_country_code": "CL"
    },
    "roles": [
      "utility_provider"
    ],
    "capabilities": [
      "utilities",
      "credential_portal"
    ],
    "source_urls": [
      "https://www.interior.gob.cl/transparencia/doc/Adquisicion/300/186903.pdf",
      "https://sucursalvirtual.cge.cl/hu/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 17,
    "supplier_id": "d583e481-3073-455f-a86a-4f518c822a7f",
    "expected_name": "Chaskicleta",
    "profile_patch": {
      "display_name": "Chaskicleta",
      "party_kind": "organization",
      "trade_name": "Chaskicleta",
      "country_code": "CL",
      "email": "contacto@chaskicleta.cl",
      "phone": "+56 9 7421 4709",
      "website": "https://chaskicleta.cl/",
      "address": "San Diego 618",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [
      "https://chaskicleta.cl/pages/nosotros-chaskicleta",
      "https://chaskicleta.novussgo.cl/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 18,
    "supplier_id": "888e296e-a3ba-4892-8c26-1157f0d12ebc",
    "expected_name": "Chatarra Viña",
    "profile_patch": {
      "display_name": "Chatarra Viña",
      "party_kind": "organization",
      "legal_name": "Compra Venta de Metales, Chatarra, Papeles y Cartones Ivonne Romero Díaz EIRL",
      "trade_name": "Compra Venta de Chatarra y Metales Viña",
      "tax_identifier": "76.494.135-7",
      "country_code": "CL",
      "phone": "+56 9 5639 8632",
      "address": "Av. Carlos Ibáñez del Campo 3020",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Chatarra Viña"
      ],
      "tax_country_code": "CL"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [
      "https://www.waze.com/live-map/directions/cl/valparaiso/valparaiso/compra-venta-de-chatarra-y-metales-vina?to=place.ChIJl_yXte_diZYRmH51SDzEBik",
      "https://www.portalchile.org/empresa/compra-venta-de-metaleschatarrapapeles-y-cartones-ivonne-romero-diaz-eirl-76494135"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 20,
    "supplier_id": "4b734745-fa95-42a9-ac07-db4d78b79378",
    "expected_name": "Claudio Sr",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 21,
    "supplier_id": "f910b968-de7e-4c26-a0a2-866d13613ab4",
    "expected_name": "Comercial Ciclo",
    "profile_patch": {
      "display_name": "Comercial Ciclo",
      "party_kind": "organization",
      "legal_name": "Comercial Ciclo SpA",
      "trade_name": "Comercial Ciclo",
      "tax_identifier": "76.442.832-3",
      "country_code": "CL",
      "email": "contacto@comercialciclo.cl",
      "phone": "+56 2 2510 4633",
      "website": "https://www.comercialciclo.cl/",
      "address": "Aldunate 1043",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://www.comercialciclo.cl/error.php?idmessage=1",
      "https://www.portalchile.org/empresa/comercial-ciclo-spa-76442832"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 22,
    "supplier_id": "cbed73fe-c406-451d-ba7e-6fd8f14a960d",
    "expected_name": "Copec",
    "profile_patch": {
      "display_name": "Copec",
      "party_kind": "organization",
      "legal_name": "Copec S.A.",
      "trade_name": "Copec",
      "tax_identifier": "99.520.000-7",
      "country_code": "CL",
      "website": "https://www.copec.cl/",
      "address": "Av. Isidora Goyenechea 2915",
      "comuna": "Las Condes",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [],
    "source_urls": [
      "https://ww2.copec.cl/portal-de-proveedores/comunicados/cambio-de-razon-social"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 23,
    "supplier_id": "fb04aba0-f57e-42e9-9345-d1304070393b",
    "expected_name": "Correos de Chile",
    "profile_patch": {
      "display_name": "Correos de Chile",
      "party_kind": "organization",
      "legal_name": "Empresa de Correos de Chile",
      "trade_name": "CorreosChile",
      "tax_identifier": "60.503.000-9",
      "country_code": "CL",
      "email": "sac@correos.cl",
      "phone": "+56 2 2956 5000",
      "website": "https://www.correos.cl/",
      "address": "Av. Libertador Bernardo O'Higgins 1449, Torre 2, piso 3",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "aliases": [
        "Correos de Chile",
        "Correos Chile"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "logistics_provider"
    ],
    "capabilities": [
      "freight_transport",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.correos.cl/web/correos-transparente/estructura",
      "https://www.cmfchile.cl/institucional/mercados/entidad.php?control=svs&mercado=V&pestania=1&rut=60503000&tipoentidad=RVEMI&tpl=alt&vig=VI"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 24,
    "supplier_id": "a5d4d1da-f275-49fc-bb86-55f0a3b3a065",
    "expected_name": "Cristian",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 25,
    "supplier_id": "40c62a2e-56b5-4e7f-b45a-c5a17ab836e9",
    "expected_name": "CVPlot",
    "profile_patch": {
      "display_name": "CVPlot",
      "party_kind": "organization",
      "trade_name": "CVPlot",
      "country_code": "CL",
      "phone": "+56 9 8596 0325",
      "address": "Álvarez 32, piso 2, local 22",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso"
    },
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://valparaiso.guianegocios.cl/empresas/vina-del-mar-valparaiso-valparaiso/59/Cvplot.html"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 26,
    "supplier_id": "57337033-55f1-429f-b68e-959c83e1d129",
    "expected_name": "Darinka Lagomarsino",
    "profile_patch": {
      "display_name": "Darinka Lagomarsino",
      "party_kind": "person",
      "country_code": "CL"
    },
    "roles": [
      "landlord"
    ],
    "capabilities": [
      "rent_lease"
    ],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 27,
    "supplier_id": "e875cfcc-8304-4e7e-9bf6-44ed218b7050",
    "expected_name": "Defensor Forever",
    "profile_patch": {
      "display_name": "Defensor Forever",
      "party_kind": "organization",
      "legal_name": "Comercial Forever Limitada",
      "trade_name": "Defensor Forever",
      "tax_identifier": "76.701.347-7",
      "country_code": "CL",
      "phone": "+56 9 4909 7928",
      "website": "https://www.defensorforever.cl/",
      "address": "Sazie 2558",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods"
    ],
    "source_urls": [
      "https://www.defensorforever.cl/contact",
      "https://www.portalchile.org/detalle-marca/defensor-forever-1298028"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 28,
    "supplier_id": "d6214c93-8405-4039-b0ae-4e36d1949ce2",
    "expected_name": "Derman",
    "profile_patch": {
      "display_name": "Derman",
      "party_kind": "organization",
      "legal_name": "Comercializadora Bicicletas Universal Dos Limitada",
      "trade_name": "Derman",
      "tax_identifier": "78.305.850-2",
      "country_code": "CL",
      "email": "ventas@derman.cl",
      "phone": "+56 9 2749 7948",
      "website": "https://derman.cl/",
      "address": "San Diego 839",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://derman.cl/content/3-terminos-y-condiciones",
      "https://www.portalchile.org/diario-oficial/2021/02/18/comercializadora-bicicletas-universal-dos-limitada-78-305-850-2-1897554",
      "https://www.portalchile.org/empresa/comercializadora-bicicletas-universal-dos-limitada-78305850"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 29,
    "supplier_id": "4212c740-358a-4999-a30a-95af066b87b5",
    "expected_name": "Doña María Cristina",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "medium"
  },
  {
    "rn": 31,
    "supplier_id": "bb053eed-6676-4de1-8855-fc2ab7aea3ff",
    "expected_name": "Droppbike",
    "profile_patch": {
      "display_name": "Droppbike",
      "party_kind": "organization",
      "trade_name": "Droppbike",
      "country_code": "CL",
      "email": "contacto@droppbike.cl",
      "phone": "+56 9 5510 7441",
      "website": "https://droppbike.cl/",
      "address": "San Diego 974",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://droppbike.cl/",
      "https://droppbike.cl/shop/?post_type=product&stock_status=onsale"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 32,
    "supplier_id": "f40377ee-375d-488f-a493-963d72dca889",
    "expected_name": "DuqueBike",
    "profile_patch": {},
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [],
    "classification_confidence": "medium"
  },
  {
    "rn": 34,
    "supplier_id": "29881b1d-7bb9-421a-a042-432e251a35f9",
    "expected_name": "Esval",
    "profile_patch": {
      "display_name": "Esval",
      "party_kind": "organization",
      "legal_name": "ESVAL S.A.",
      "trade_name": "Esval",
      "tax_identifier": "76.000.739-0",
      "country_code": "CL",
      "email": "info@esval.cl",
      "phone": "+56 32 220 9000",
      "website": "https://www.esval.cl/personas/inicio",
      "address": "Cochrane 751",
      "comuna": "Valparaíso",
      "city": "Valparaíso",
      "region": "Región de Valparaíso",
      "tax_country_code": "CL"
    },
    "roles": [
      "utility_provider"
    ],
    "capabilities": [
      "utilities",
      "credential_portal"
    ],
    "source_urls": [
      "https://www.esval.cl/personas/inicio",
      "https://www.cmfchile.cl/institucional/mercados/entidad.php?control=svs&grupo=0&mercado=V&pestania=1&row=&rut=76000739&tipoentidad=RVEMI&tpl=alt&vig=VI"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 35,
    "supplier_id": "c7d8bc10-5612-4850-87c5-68de9eea74b8",
    "expected_name": "Fernando Tapia",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 36,
    "supplier_id": "6b20d354-1032-4a9f-816e-7f58352d2843",
    "expected_name": "Ferreteria 13 norte",
    "profile_patch": {},
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [],
    "classification_confidence": "medium"
  },
  {
    "rn": 37,
    "supplier_id": "fdeb3efa-0d43-437a-97d7-0bebacb71614",
    "expected_name": "Ferretería Diproi",
    "profile_patch": {},
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [],
    "classification_confidence": "medium"
  },
  {
    "rn": 39,
    "supplier_id": "8c82f929-a316-4eb4-bee0-41332832a5e1",
    "expected_name": "Garozzo",
    "profile_patch": {
      "display_name": "Bicicletas Garozzo",
      "party_kind": "organization",
      "trade_name": "Bicicletas Garozzo",
      "country_code": "CL",
      "phone": "+56 32 288 2127",
      "address": "San Antonio 1305, local 15",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Garozzo"
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://chilopina.com/tienda-de-bicicletas/vina-del-mar/bicicletas-garozzo/",
      "https://cl.todosnegocios.com/bicicletas-garozzo_1u"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 41,
    "supplier_id": "44dac360-fad6-4119-9343-5dd1d84ca4e1",
    "expected_name": "Gasfiteria Garrido",
    "profile_patch": {
      "display_name": "Gasfitería Garrido",
      "party_kind": "organization",
      "legal_name": "Gasfitería Garrido SpA",
      "trade_name": "Gasfitería Garrido",
      "tax_identifier": "77.537.991-K",
      "country_code": "CL",
      "email": "contacto@gasfiteriagarrido.cl",
      "phone": "+56 9 8947 1202",
      "website": "https://gasfiteriagarrido.cl/",
      "address": "Álvarez 58, local 6",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Gasfiteria Garrido"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://gasfiteriagarrido.cl/",
      "https://gasfiteriagarrido.cl/contacto/",
      "https://www.portalchile.org/empresa/gasfiteria-garrido-spa-77537991"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 42,
    "supplier_id": "908da3e9-b68a-43f8-b62e-7900435ecf31",
    "expected_name": "Gomas y Pernos",
    "profile_patch": {
      "display_name": "Comercial Gomas y Pernos",
      "party_kind": "organization",
      "legal_name": "Comercial Gomas y Pernos Limitada",
      "trade_name": "Gomas y Pernos",
      "tax_identifier": "78.518.070-4",
      "country_code": "CL",
      "email": "ventas@gomasypernos.cl",
      "phone": "+56 32 268 1030",
      "website": "https://gomasypernos.cl/",
      "address": "4 Oriente 1212",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Gomas y Pernos"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [
      "https://gomasypernos.cl/",
      "https://www.mercantil.com/empresa/comercial-gomas-y-pernos-ltda/vina-del-mar/300169697/esp/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 43,
    "supplier_id": "a34ad86e-7b04-4e81-a981-74ed5e9bb0e3",
    "expected_name": "Google",
    "profile_patch": {
      "display_name": "Google",
      "party_kind": "organization",
      "trade_name": "Google",
      "website": "https://about.google/intl/es-419/products/"
    },
    "roles": [
      "digital_platform"
    ],
    "capabilities": [
      "digital_services"
    ],
    "source_urls": [
      "https://about.google/intl/es-419/products/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 44,
    "supplier_id": "42a23b3d-d02d-4789-ad9a-7cb6dc87d12e",
    "expected_name": "Guillermo Nieto",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 45,
    "supplier_id": "cb71f8e6-9846-4989-961c-136dc4865f20",
    "expected_name": "I. Municipalidad de Viña del Mar",
    "profile_patch": {
      "display_name": "Municipalidad de Viña del Mar",
      "party_kind": "government_entity",
      "legal_name": "Ilustre Municipalidad de Viña del Mar",
      "tax_identifier": "69.061.000-0",
      "country_code": "CL",
      "website": "https://www.munivina.cl/",
      "address": "Arlegui 615",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "I. Municipalidad de Viña del Mar"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "government_authority"
    ],
    "capabilities": [
      "tax_payments"
    ],
    "source_urls": [
      "https://www.munivina.cl/",
      "https://www.mercadopublico.cl/PurchaseOrder/Modules/PO/DetailsPurchaseOrder.aspx?qs=BgB1aDcXwNbtpciSlKlwSQ%3D%3D"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 46,
    "supplier_id": "5330d4b8-10a1-44aa-a7ca-41ecfd3cd280",
    "expected_name": "Ignacio Fabres",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 47,
    "supplier_id": "522f1afa-5b1f-47c9-a372-180da963763a",
    "expected_name": "Imperio Bikers",
    "profile_patch": {
      "display_name": "Imperio Bikers",
      "party_kind": "organization",
      "legal_name": "Imperio Bikers SpA",
      "trade_name": "Imperio Bikers",
      "tax_identifier": "77.350.385-0",
      "country_code": "CL",
      "email": "contacto@imperiobikers.cl",
      "phone": "+56 9 7124 2563",
      "website": "https://www.imperiobikers.cl/",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables"
    ],
    "source_urls": [
      "https://www.imperiobikers.cl/sobre-nosotros/",
      "https://www.portalchile.org/empresa/imperio-bikers-spa-77350385"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 48,
    "supplier_id": "1fa94c8f-7a92-4ae7-965d-c72628cd1e3a",
    "expected_name": "Instagram",
    "profile_patch": {
      "display_name": "Instagram",
      "party_kind": "organization",
      "trade_name": "Instagram",
      "website": "https://www.instagram.com/"
    },
    "roles": [
      "operational_resource"
    ],
    "capabilities": [
      "credential_portal"
    ],
    "source_urls": [
      "https://about.meta.com/technologies/instagram/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 50,
    "supplier_id": "634d7887-a0e5-48a3-9fd8-acf464ea6884",
    "expected_name": "La Sierra",
    "profile_patch": {
      "display_name": "Ferretería La Sierra",
      "party_kind": "organization",
      "legal_name": "Ismael Rubin y Cía. Ltda.",
      "trade_name": "Ferretería La Sierra",
      "tax_identifier": "85.254.800-2",
      "country_code": "CL",
      "phone": "+56 32 271 1042",
      "address": "Etchevers 166",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "La Sierra"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [
      "https://www.mercadopublico.cl/PurchaseOrder/Modules/PO/DetailsPurchaseOrder.aspx?qs=BgB1aDcXwNbtpciSlKlwSQ%3D%3D",
      "https://www.mercantil.com/empresa/ferreteria-la-sierra/vina-del-mar/300100537/esp/",
      "https://www.fanaloza.cl/donde_comprar/ferreteria-la-sierra/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 52,
    "supplier_id": "c0555c5a-691c-4e89-bdb8-1312552c6641",
    "expected_name": "Libreria ProyeCad",
    "profile_patch": {
      "display_name": "Librería Projecad",
      "party_kind": "person",
      "legal_name": "Alison Paula del Carmen Ibarra González",
      "trade_name": "Librería Projecad",
      "tax_identifier": "13.226.482-1",
      "country_code": "CL",
      "email": "libreria@projecad.cl",
      "phone": "+56 32 266 5614",
      "website": "https://projecad.cl/libreria.html",
      "address": "Álvarez 32, local 24",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Libreria ProyeCad",
        "Projecad"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor",
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://projecad.cl/libreria.html",
      "https://www.mercantil.com/empresa/projecad/vina-del-mar/300341697/esp/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 53,
    "supplier_id": "2006c179-11cb-4ae3-b869-4581fc2ac3ba",
    "expected_name": "Liqui Moly",
    "profile_patch": {
      "display_name": "Liqui Moly Chile",
      "party_kind": "organization",
      "legal_name": "Liqui Moly Chile SpA",
      "trade_name": "Liqui Moly",
      "tax_identifier": "86.868.900-5",
      "country_code": "CL",
      "email": "ventas@liqui-moly.cl",
      "phone": "+56 2 2332 2100",
      "website": "https://www.liqui-moly.cl/",
      "address": "Av. Eliodoro Yáñez 1727",
      "comuna": "Providencia",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "aliases": [
        "Liqui Moly"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [
      "https://chile.ahk.de/es/socios/directorio-de-socios/liqui-moly-chile-s.a",
      "https://www.mercadopublico.cl/BID/Modules/PopUps/InformationProvider.aspx?enc=p953k1hcJyp5QFQvsgQWZOKeR4yvkwAOHX02FUuleCGL1YQUD554OPT1Wv4R54jfLteNzcHVhNHjvyrAVRcV4g%3D%3D"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 55,
    "supplier_id": "27d532fe-42e1-45ea-9ebd-17f4f924293d",
    "expected_name": "Maximiliano Toro",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 56,
    "supplier_id": "b6654661-eda8-49ee-9fd8-6df13097eaa2",
    "expected_name": "Mercadolibre",
    "profile_patch": {
      "display_name": "Mercado Libre",
      "party_kind": "organization",
      "legal_name": "MercadoLibre Chile Ltda.",
      "trade_name": "Mercado Libre",
      "tax_identifier": "77.398.220-1",
      "country_code": "CL",
      "website": "https://www.mercadolibre.cl/",
      "aliases": [
        "Mercadolibre"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "operational_resource"
    ],
    "capabilities": [
      "credential_portal"
    ],
    "source_urls": [
      "https://www.mercadolibre.cl/e/negocios/vendidos-por-mercado-libre?tracking_id=f055f4d11062f667bf8f64e67da37db4"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 57,
    "supplier_id": "1a43e266-6dc8-43a6-b647-ffa149680bda",
    "expected_name": "MF Pinturas",
    "profile_patch": {
      "display_name": "MF Pinturas",
      "party_kind": "organization",
      "legal_name": "Figueroa y Compañía Limitada",
      "trade_name": "MF Pinturas",
      "tax_identifier": "76.704.650-2",
      "country_code": "CL",
      "phone": "+56 32 268 0877",
      "website": "https://figueroaycialtda.cl/",
      "address": "San Antonio 999",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Región de Valparaíso",
      "aliases": [
        "Baco"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [
      "https://figueroaycialtda.cl/",
      "https://www.mercantil.com/empresa/baco/vina-del-mar/300262888/esp/",
      "https://www.visionferretera.cl/proveedores/figueroa-y-cia-ltda"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 59,
    "supplier_id": "3f6f71dc-99b8-4f0c-9f44-cd37276fc5ee",
    "expected_name": "MKR",
    "profile_patch": {
      "display_name": "MKR Imports",
      "party_kind": "organization",
      "legal_name": "Mauricio Kishinevsky Rosental S.A.",
      "trade_name": "MKR Imports",
      "tax_identifier": "96.623.280-3",
      "country_code": "CL",
      "email": "contact@mkr.cl",
      "website": "https://mkr.cl/",
      "address": "Av. Padre Hurtado Norte 1278",
      "comuna": "Vitacura",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "aliases": [
        "MKR"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://mkr.cl/",
      "https://mkr.cl/users/login"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 60,
    "supplier_id": "b678321a-4f13-4638-9aac-9883f76234ee",
    "expected_name": "Motorex",
    "profile_patch": {
      "display_name": "Motorex Chile",
      "party_kind": "organization",
      "legal_name": "Motorex Chile S.A.",
      "trade_name": "Motorex",
      "tax_identifier": "76.042.235-5",
      "country_code": "CL",
      "email": "info@motorexchile.cl",
      "phone": "+56 9 4409 2057",
      "website": "https://motorex.cl/",
      "address": "Av. La Dehesa 1201, oficina 506, Torre Norte",
      "comuna": "Lo Barnechea",
      "city": "Santiago",
      "region": "Región Metropolitana de Santiago",
      "aliases": [
        "Motorex"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [
      "https://motorex.cl/pages/terminos-y-condiciones",
      "https://motorex.cl/pages/dealers-2",
      "https://motorex.cl/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 61,
    "supplier_id": "35679cbf-a3ae-4f21-9851-d485d84b9f75",
    "expected_name": "NIC Chile",
    "profile_patch": {
      "display_name": "NIC Chile",
      "party_kind": "organization",
      "legal_name": "Universidad de Chile",
      "trade_name": "NIC Chile",
      "tax_identifier": "60.910.000-1",
      "country_code": "CL",
      "email": "info@nic.cl",
      "phone": "+56229407700",
      "website": "https://www.nic.cl/",
      "aliases": [
        "Universidad de Chile (NIC Chile)"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "digital_platform"
    ],
    "capabilities": [
      "digital_services",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://www.nic.cl/normativa/dte.html",
      "https://www.nic.cl/contacto/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 62,
    "supplier_id": "1443758b-9749-42ef-bbe8-59a970067991",
    "expected_name": "Outside Sports SPA",
    "profile_patch": {
      "display_name": "Outside Sports",
      "party_kind": "organization",
      "legal_name": "Outside Sports SpA",
      "trade_name": "Outside Sports",
      "country_code": "CL",
      "email": "contacto@outsidesports.cl",
      "website": "https://www.outsidesports.cl/",
      "address": "Bandera 84, oficina 309",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "aliases": [
        "Outside Sports SPA"
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://b2c.outsidesports.cl/shop/wishlist",
      "https://www.outsidesports.cl/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 63,
    "supplier_id": "0d636e10-cf7d-4034-a6bd-ce57eea6aeed",
    "expected_name": "Oxford Viña del Mar",
    "profile_patch": {
      "display_name": "Oxford Store Viña del Mar",
      "party_kind": "organization",
      "trade_name": "Oxford",
      "aliases": [
        "Oxford Viña del Mar",
        "Oxford Store"
      ],
      "country_code": "CL",
      "phone": "+56226319737",
      "website": "https://www.oxfordstore.cl/",
      "address": "10 Norte 655, local 2",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Valparaíso"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.oxfordstore.cl/sucursales"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 64,
    "supplier_id": "edf716cd-b1c6-421a-97af-2af401831e43",
    "expected_name": "Padro Bikes",
    "profile_patch": {
      "display_name": "Padro Bikes",
      "party_kind": "organization",
      "trade_name": "Padro Bikes",
      "country_code": "CL",
      "email": "contacto@padrobikes.cl",
      "phone": "+56990004101",
      "website": "https://padrobikes.cl/",
      "address": "14 Norte 1251",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Valparaíso"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://padrobikes.cl/policies/refund-policy"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 65,
    "supplier_id": "d4c85ebf-283d-4177-bbc8-b7de25d468d8",
    "expected_name": "Pedro Madrid",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "high"
  },
  {
    "rn": 66,
    "supplier_id": "3cf3c873-7b0d-421d-8f59-68713e6c91f5",
    "expected_name": "PerniFlex",
    "profile_patch": {
      "display_name": "Perniflex",
      "trade_name": "Perniflex",
      "aliases": [
        "PerniFlex"
      ],
      "country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "workshop_consumables"
    ],
    "source_urls": [
      "https://www.mercantil.com/empresa/perniflex/vina-del-mar/300243929/esp/",
      "https://valparaiso.guianegocios.cl/empresas/vina-del-mar-valparaiso-valparaiso/132060/Perniflex.html"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 70,
    "supplier_id": "8737a986-d708-4471-8a27-f27161778e0e",
    "expected_name": "Pullman Cargo",
    "profile_patch": {
      "display_name": "Pullman Cargo",
      "party_kind": "organization",
      "legal_name": "Pullman Cargo S.A.",
      "trade_name": "Pullman Cargo",
      "tax_identifier": "89.622.400-K",
      "country_code": "CL",
      "email": "hola@pullmancargo.cl",
      "website": "https://pullmancargo.cl/",
      "address": "Cerro Sombrero 1775",
      "comuna": "Maipú",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "tax_country_code": "CL"
    },
    "roles": [
      "logistics_provider"
    ],
    "capabilities": [
      "freight_transport",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://pullmancargo.cl/",
      "https://www.mercadopublico.cl/BID/Modules/PopUps/InformationProvider.aspx?enc=WZCzU63VjxRxXw6Beomt9hocbi1xfUqIusmOJBcmwk9Wi7kCijybcHI1JfiXc42uThOen6xmRv98O13V6d1Xhg%3D%3D"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 71,
    "supplier_id": "02ca8b13-8518-43b7-8f39-f6036488ab94",
    "expected_name": "RaceLub",
    "profile_patch": {
      "display_name": "RaceLub",
      "trade_name": "RaceLub",
      "country_code": "CL",
      "website": "https://racelub.cl/"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://racelub.cl/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 72,
    "supplier_id": "b33660dc-c38a-4a2d-833f-607bc2b0c2ae",
    "expected_name": "RBX",
    "profile_patch": {
      "display_name": "RBX",
      "party_kind": "organization",
      "legal_name": "Rafael Burgos S.A.",
      "trade_name": "RBX",
      "country_code": "CL",
      "email": "rburgos@rburgos.cl",
      "phone": "+56225200600",
      "website": "https://portal.rburgos.cl/",
      "address": "Arturo Prat 1032",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "aliases": [
        "Rafael Burgos"
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices",
      "credential_portal"
    ],
    "source_urls": [
      "https://portal.rburgos.cl/",
      "https://portal.rburgos.cl/contact/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 73,
    "supplier_id": "7d8c7564-dfac-477c-b1ff-19de8736035f",
    "expected_name": "Resolución Gráfica",
    "profile_patch": {
      "display_name": "Resolución Gráfica",
      "party_kind": "organization",
      "trade_name": "Resolución Gráfica",
      "country_code": "CL",
      "email": "contacto@resoluciongrafica.cl",
      "phone": "+56990805026",
      "website": "https://resoluciongrafica.cl/",
      "address": "1 Norte 3600",
      "comuna": "Viña del Mar",
      "city": "Viña del Mar",
      "region": "Valparaíso"
    },
    "roles": [
      "service_provider"
    ],
    "capabilities": [
      "purchase_invoices"
    ],
    "source_urls": [
      "https://resoluciongrafica.cl/nosotros/",
      "https://resoluciongrafica.cl/contacto/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 76,
    "supplier_id": "02988500-2227-4a4d-a583-91300f322a30",
    "expected_name": "SII",
    "profile_patch": {
      "display_name": "Servicio de Impuestos Internos",
      "party_kind": "government_entity",
      "legal_name": "Servicio de Impuestos Internos",
      "trade_name": "SII",
      "tax_identifier": "60.803.000-K",
      "country_code": "CL",
      "phone": "+56232525575",
      "website": "https://www.sii.cl/",
      "address": "Teatinos 120",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "aliases": [
        "Servicio de impuestos internos"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "government_authority"
    ],
    "capabilities": [
      "tax_payments",
      "credential_portal"
    ],
    "source_urls": [
      "https://www.sii.cl/ayudas/asistencia/3042-mesa_ayuda-3044.html",
      "https://www.sii.cl/transparencia/dificultad_tecnica_reporte_error.html"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 78,
    "supplier_id": "5a0a425b-4198-48ad-ad88-9dec38a686af",
    "expected_name": "Sodimac",
    "profile_patch": {
      "display_name": "Sodimac",
      "party_kind": "organization",
      "legal_name": "Sodimac S.A.",
      "trade_name": "Sodimac",
      "tax_identifier": "96.792.430-K",
      "country_code": "CL",
      "website": "https://www.sodimac.cl/",
      "address": "Rosario Norte 660, piso 14",
      "comuna": "Las Condes",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "purchase_invoices"
    ],
    "source_urls": [
      "https://empresas.sodimac.cl/sodimac-cl/myaccount/content/termsandconditions/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 79,
    "supplier_id": "b7ae6b58-0376-4e10-a296-a87f4bfaecd8",
    "expected_name": "SOLDEN SpA",
    "profile_patch": {
      "display_name": "SOLDEN",
      "party_kind": "organization",
      "legal_name": "Importadora y Comercializadora SOLDEN SpA",
      "trade_name": "SOLDEN",
      "tax_identifier": "77.197.665-4",
      "country_code": "CL",
      "aliases": [
        "SOLDEN SpA"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.portalchile.org/diario-oficial/2022/10/14/importadora-y-comercializadora-solden-spa-77-197-665-4-2201380"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 80,
    "supplier_id": "0c1d5ec7-cfee-4d4f-9ff7-a7a235906856",
    "expected_name": "Span y Café",
    "profile_patch": {},
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [
      "https://www.ubereats.com/cl/store/span-y-cafe-spa/t2EyRww7SsedOp0hUiz20Q"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 81,
    "supplier_id": "3bc9deaa-91f1-44d4-aaf8-581ba2309f50",
    "expected_name": "Starken",
    "profile_patch": {
      "display_name": "Starken",
      "party_kind": "organization",
      "legal_name": "Kaudat SpA",
      "trade_name": "Starken",
      "tax_identifier": "76.211.240-K",
      "country_code": "CL",
      "website": "https://starken.cl/",
      "address": "Avenida Libertador Bernardo O'Higgins 3750, oficina 404",
      "comuna": "Estación Central",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "aliases": [
        "Kaudat",
        "Kaudat SpA",
        "KAUDAT SPA",
        "Starken"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "logistics_provider"
    ],
    "capabilities": [
      "freight_transport",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://starken.cl/",
      "https://transparencia.uv.cl/documentos/representacion-ceremonial-protocolo/2024/rexe-60536-24_titulacion_nutricion_farmacia.pdf",
      "https://www.portalchile.org/empresa/kaudat-spa-76211240"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 82,
    "supplier_id": "e1d1028e-ad99-4d3b-8bc5-e9c9110206fa",
    "expected_name": "Tactical Zone",
    "profile_patch": {},
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.tacticalzone.cl/article/quienes-somos",
      "https://www.tacticalzone.cl/article/politica-de-privacidad"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 83,
    "supplier_id": "d5f1a34c-d42d-43ec-80a9-027da3dab18f",
    "expected_name": "TeknoBike",
    "profile_patch": {
      "display_name": "TeknoBike",
      "party_kind": "organization",
      "legal_name": "TeknoBike Ltda.",
      "trade_name": "TeknoBike",
      "country_code": "CL",
      "website": "https://www.teknobike.cl/",
      "aliases": [
        "TEKNOBIKE LTDA."
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.teknobike.cl/",
      "https://www.teknobike.cl/quienes-somos"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 84,
    "supplier_id": "5d6cce73-b639-4fde-9eea-f404f8a68371",
    "expected_name": "Transportes Gonzalez",
    "profile_patch": {},
    "roles": [
      "logistics_provider"
    ],
    "capabilities": [
      "freight_transport"
    ],
    "source_urls": [
      "https://www.portalchile.org/empresa/transportes-gonzalez-y-martinez-limitada-76519463",
      "https://dequienes.cl/diario-oficial/2015/11/30/transportes-gonzalez-flores-spa-972430"
    ],
    "classification_confidence": "medium"
  },
  {
    "rn": 85,
    "supplier_id": "2ec78a47-e099-47bc-9f3b-05d6941477e2",
    "expected_name": "Transportes Vayve",
    "profile_patch": {},
    "roles": [
      "logistics_provider"
    ],
    "capabilities": [
      "freight_transport",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.portalchile.org/empresa/transportes-vayve-limitada-78802720"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 87,
    "supplier_id": "c76ba2b0-3b1f-42c6-af7a-e92d1bed8753",
    "expected_name": "Trip",
    "profile_patch": {
      "display_name": "Trip",
      "party_kind": "organization",
      "trade_name": "Trip",
      "country_code": "CL",
      "email": "ventas@triphelmets.com",
      "phone": "+56931985530",
      "website": "https://www.triphelmets.com/",
      "address": "Erasmo Escala 2351",
      "comuna": "Santiago",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "aliases": [
        "Trip Helmets"
      ]
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.triphelmets.com/pages/distribuidores",
      "https://www.triphelmets.com/pages/contacto"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 88,
    "supplier_id": "edc955d4-f88c-4b0f-8b77-db05913daa1a",
    "expected_name": "Unimarc",
    "profile_patch": {
      "display_name": "Unimarc",
      "party_kind": "organization",
      "legal_name": "SMU S.A.",
      "trade_name": "Unimarc",
      "tax_identifier": "76.012.676-4",
      "country_code": "CL",
      "phone": "+56228188000",
      "website": "https://www.smu.cl/",
      "address": "Cerro El Plomo 5680, piso 10",
      "comuna": "Las Condes",
      "city": "Santiago",
      "region": "Región Metropolitana",
      "aliases": [
        "SMU"
      ],
      "tax_country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "purchase_invoices"
    ],
    "source_urls": [
      "https://www.cmfchile.cl/institucional/mercados/entidad.php?auth=&control=svs&grupo=&mercado=V&pestania=1&row=AAAwy2ACTAAABzMAAB&rut=76012676&send=&tipoentidad=RVEMI&vig=VI",
      "https://www.smu.cl/"
    ],
    "classification_confidence": "high"
  },
  {
    "rn": 90,
    "supplier_id": "45dab4b0-43f1-413c-93f0-215296be939e",
    "expected_name": "Vicente Díaz",
    "profile_patch": {
      "party_kind": "person"
    },
    "roles": [
      "service_provider"
    ],
    "capabilities": [],
    "source_urls": [],
    "classification_confidence": "medium"
  },
  {
    "rn": 91,
    "supplier_id": "f8c7d458-2a87-4822-8f31-63fc2a59cc61",
    "expected_name": "Vittal",
    "profile_patch": {
      "party_kind": "organization",
      "trade_name": "Vittal",
      "country_code": "CL"
    },
    "roles": [
      "goods_vendor"
    ],
    "capabilities": [
      "inventory_goods",
      "workshop_consumables",
      "purchase_invoices"
    ],
    "source_urls": [
      "https://chilepymes.com/info/vittal-spa-1FBDBFCED5C453A9",
      "https://dequienes.cl/diario-oficial/2021/12/22/vittal-spa-76995384-1-2060383"
    ],
    "classification_confidence": "high"
  }
]
$manifest$::jsonb) as row(
  rn integer,
  supplier_id uuid,
  expected_name text,
  profile_patch jsonb,
  roles jsonb,
  capabilities jsonb,
  source_urls jsonb,
  classification_confidence text
);

create temporary table supplier_enrichment_engagements (
  supplier text not null,
  supplier_id uuid not null,
  code text not null,
  kind text not null,
  name text not null,
  status text not null,
  starts_on date,
  effective_from date,
  billing_cycle text not null,
  currency_code text not null,
  expected_amount numeric,
  external_reference text,
  service_identifier text,
  portal_url text,
  terms jsonb not null,
  primary key (supplier_id, code)
) on commit drop;

insert into supplier_enrichment_engagements
select
  row.supplier,
  row.supplier_id,
  row.code,
  row.kind,
  row.name,
  row.status,
  row.starts_on,
  row.effective_from,
  row.billing_cycle,
  row.currency_code,
  row.expected_amount,
  row.external_reference,
  row.service_identifier,
  row.portal_url,
  row.terms
from jsonb_to_recordset($engagements$
[
  {
    "supplier": "CGE",
    "code": "electricity_service",
    "kind": "utility",
    "name": "Suministro eléctrico CGE",
    "starts_on": "2026-06-15",
    "effective_from": "2026-06-15",
    "billing_cycle": "monthly",
    "portal_url": "https://sucursalvirtual.cge.cl/",
    "terms": {
      "evidence_basis": "first_recorded_expense"
    },
    "supplier_id": "af6e54db-7474-42bc-b8e8-02b5048adc6c",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "Esval",
    "code": "water_service",
    "kind": "utility",
    "name": "Suministro de agua Esval",
    "starts_on": "2026-05-27",
    "effective_from": "2026-05-27",
    "billing_cycle": "monthly",
    "service_identifier": "322102",
    "portal_url": "https://www.esval.cl/personas/inicio",
    "terms": {
      "evidence_basis": "first_recorded_expense"
    },
    "supplier_id": "29881b1d-7bb9-421a-a042-432e251a35f9",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "Darinka Lagomarsino",
    "code": "store_lease",
    "kind": "lease",
    "name": "Arriendo del local",
    "starts_on": "2026-04-20",
    "effective_from": "2026-04-20",
    "billing_cycle": "monthly",
    "expected_amount": 499467,
    "terms": {
      "evidence_basis": "three_recorded_monthly_expenses",
      "ipc_adjustment": "1.4% semestral",
      "annual_adjustment": "5%"
    },
    "supplier_id": "57337033-55f1-429f-b68e-959c83e1d129",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "NIC Chile",
    "code": "domain_vinabike_cl",
    "kind": "subscription",
    "name": "Dominio vinabike.cl",
    "starts_on": "2026-07-17",
    "effective_from": "2026-07-17",
    "billing_cycle": "annual",
    "external_reference": "vinabike.cl",
    "portal_url": "https://www.nic.cl/",
    "terms": {
      "evidence_basis": "recorded_domain_expense"
    },
    "supplier_id": "35679cbf-a3ae-4f21-9851-d485d84b9f75",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "Correos de Chile",
    "code": "shipping_correos",
    "kind": "service_account",
    "name": "Despachos Correos de Chile",
    "starts_on": "2026-03-07",
    "effective_from": "2026-03-07",
    "billing_cycle": "irregular",
    "portal_url": "https://www.correos.cl/",
    "terms": {
      "evidence_basis": "six_recorded_shipping_expenses"
    },
    "supplier_id": "fb04aba0-f57e-42e9-9345-d1304070393b",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "Pullman Cargo",
    "code": "shipping_pullman",
    "kind": "service_account",
    "name": "Despachos Pullman Cargo",
    "starts_on": "2026-04-29",
    "effective_from": "2026-04-29",
    "billing_cycle": "irregular",
    "portal_url": "https://pullmancargo.cl/",
    "terms": {
      "evidence_basis": "two_recorded_shipping_expenses"
    },
    "supplier_id": "8737a986-d708-4471-8a27-f27161778e0e",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "Starken",
    "code": "shipping_starken",
    "kind": "service_account",
    "name": "Despachos Starken",
    "starts_on": "2026-03-05",
    "effective_from": "2026-03-05",
    "billing_cycle": "irregular",
    "portal_url": "https://starken.cl/",
    "terms": {
      "evidence_basis": "eight_recorded_shipping_expenses"
    },
    "supplier_id": "3bc9deaa-91f1-44d4-aaf8-581ba2309f50",
    "status": "active",
    "currency_code": "CLP"
  },
  {
    "supplier": "SII",
    "code": "tax_portal",
    "kind": "tax_obligation",
    "name": "Portal tributario SII",
    "starts_on": null,
    "effective_from": null,
    "billing_cycle": "none",
    "portal_url": "https://www.sii.cl/",
    "terms": {
      "evidence_basis": "protected_operational_credential"
    },
    "supplier_id": "02988500-2227-4a4d-a583-91300f322a30",
    "status": "active",
    "currency_code": "CLP"
  }
]
$engagements$::jsonb) as row(
  supplier text,
  code text,
  kind text,
  name text,
  starts_on date,
  effective_from date,
  billing_cycle text,
  portal_url text,
  terms jsonb,
  supplier_id uuid,
  status text,
  currency_code text,
  expected_amount numeric,
  external_reference text,
  service_identifier text
);

create temporary table supplier_enrichment_policies (
  supplier text not null,
  supplier_id uuid not null,
  code text not null,
  name text not null,
  engagement_code text not null,
  nature text not null,
  category_id uuid not null,
  debit_account_id uuid not null,
  tax_treatment text not null,
  expected_document_type text,
  line_nature text not null,
  evidence_count integer not null,
  primary key (supplier_id, code)
) on commit drop;

insert into supplier_enrichment_policies
select
  row.supplier,
  row.supplier_id,
  row.code,
  row.name,
  row.engagement_code,
  row.nature,
  row.category_id,
  row.debit_account_id,
  row.tax_treatment,
  row.expected_document_type,
  row.line_nature,
  row.evidence_count
from jsonb_to_recordset($policies$
[
  {
    "supplier": "CGE",
    "code": "utilities_electricity",
    "name": "Electricidad del local",
    "engagement_code": "electricity_service",
    "nature": "utilities",
    "category_id": "74d34095-b115-46c0-b493-24547779dd34",
    "debit_account_id": "c9568ea6-2e2d-4a77-bd2f-e5982390240a",
    "tax_treatment": "no_tax",
    "expected_document_type": "receipt",
    "line_nature": "operating_expense",
    "evidence_count": 1,
    "supplier_id": "af6e54db-7474-42bc-b8e8-02b5048adc6c"
  },
  {
    "supplier": "Esval",
    "code": "utilities_water",
    "name": "Agua del local",
    "engagement_code": "water_service",
    "nature": "utilities",
    "category_id": "74d34095-b115-46c0-b493-24547779dd34",
    "debit_account_id": "5c82e2af-5c5f-432c-9d9a-0100e5b6a5c4",
    "tax_treatment": "no_tax",
    "expected_document_type": "receipt",
    "line_nature": "operating_expense",
    "evidence_count": 1,
    "supplier_id": "29881b1d-7bb9-421a-a042-432e251a35f9"
  },
  {
    "supplier": "Darinka Lagomarsino",
    "code": "store_rent",
    "name": "Arriendo del local",
    "engagement_code": "store_lease",
    "nature": "rent_lease",
    "category_id": "39557960-e68b-4c43-9a94-61bee5bdb1e1",
    "debit_account_id": "d069e907-f25f-4856-ba34-1fa0593d1d98",
    "tax_treatment": "no_tax",
    "expected_document_type": "receipt",
    "line_nature": "operating_expense",
    "evidence_count": 3,
    "supplier_id": "57337033-55f1-429f-b68e-959c83e1d129"
  },
  {
    "supplier": "NIC Chile",
    "code": "domain_service",
    "name": "Dominio y hosting",
    "engagement_code": "domain_vinabike_cl",
    "nature": "digital_services",
    "category_id": "3fd6e490-c4aa-45fe-a527-e97958969897",
    "debit_account_id": "07a7b207-b4bf-4fa9-ac22-effe4f3007b6",
    "tax_treatment": "tax_included",
    "expected_document_type": "invoice",
    "line_nature": "service",
    "evidence_count": 1,
    "supplier_id": "35679cbf-a3ae-4f21-9851-d485d84b9f75"
  },
  {
    "supplier": "Correos de Chile",
    "code": "freight_correos",
    "name": "Fletes Correos de Chile",
    "engagement_code": "shipping_correos",
    "nature": "freight_logistics",
    "category_id": "a24229c2-6a43-4a92-aeda-2e8cd11357a3",
    "debit_account_id": "ddd31c33-1930-4012-b3a9-3787f1f63004",
    "tax_treatment": "tax_included",
    "expected_document_type": null,
    "line_nature": "freight",
    "evidence_count": 6,
    "supplier_id": "fb04aba0-f57e-42e9-9345-d1304070393b"
  },
  {
    "supplier": "Pullman Cargo",
    "code": "freight_pullman",
    "name": "Fletes Pullman Cargo",
    "engagement_code": "shipping_pullman",
    "nature": "freight_logistics",
    "category_id": "a24229c2-6a43-4a92-aeda-2e8cd11357a3",
    "debit_account_id": "ddd31c33-1930-4012-b3a9-3787f1f63004",
    "tax_treatment": "tax_included",
    "expected_document_type": "invoice",
    "line_nature": "freight",
    "evidence_count": 2,
    "supplier_id": "8737a986-d708-4471-8a27-f27161778e0e"
  },
  {
    "supplier": "Starken",
    "code": "freight_starken",
    "name": "Fletes Starken",
    "engagement_code": "shipping_starken",
    "nature": "freight_logistics",
    "category_id": "a24229c2-6a43-4a92-aeda-2e8cd11357a3",
    "debit_account_id": "ddd31c33-1930-4012-b3a9-3787f1f63004",
    "tax_treatment": "tax_included",
    "expected_document_type": null,
    "line_nature": "freight",
    "evidence_count": 8,
    "supplier_id": "3bc9deaa-91f1-44d4-aaf8-581ba2309f50"
  }
]
$policies$::jsonb) as row(
  supplier text,
  code text,
  name text,
  engagement_code text,
  nature text,
  category_id uuid,
  debit_account_id uuid,
  tax_treatment text,
  expected_document_type text,
  line_nature text,
  evidence_count integer,
  supplier_id uuid
);

do $migration$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_row record;
  v_supplier record;
  v_operation_id uuid;
  v_profile jsonb;
  v_roles jsonb;
  v_capabilities jsonb;
  v_tags jsonb;
  v_effective_from date;
  v_engagement_id uuid;
  v_candidate record;
  v_nature_code text;
  v_decision text;
begin
  if not exists (
    select 1 from public.tenants where id = v_tenant_id
  ) then
    raise notice 'Vinabike tenant absent; supplier enrichment is a no-op';
    return;
  end if;

  if exists (
    select 1
    from supplier_enrichment_manifest manifest
    left join public.suppliers supplier
      on supplier.tenant_id = v_tenant_id
     and supplier.id = manifest.supplier_id
     and (
       supplier.name = manifest.expected_name
       or (
         manifest.profile_patch ? 'display_name'
         and supplier.name = nullif(
           btrim(manifest.profile_patch->>'display_name'), ''
         )
       )
     )
    where manifest.classification_confidence = 'high'
      and supplier.id is null
  ) then
    raise exception 'Supplier enrichment manifest no longer matches production identity'
      using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from supplier_enrichment_manifest manifest
    cross join lateral jsonb_array_elements_text(manifest.roles) target(code)
    join public.supplier_relationship_roles assignment
      on assignment.tenant_id = v_tenant_id
     and assignment.supplier_id = manifest.supplier_id
     and assignment.role_code = target.code
     and assignment.assignment_source = 'observed'
     and assignment.valid_to is null
    where manifest.classification_confidence = 'high'
  ) or exists (
    select 1
    from supplier_enrichment_manifest manifest
    cross join lateral jsonb_array_elements_text(
      manifest.capabilities
    ) target(code)
    join public.supplier_relationship_capabilities assignment
      on assignment.tenant_id = v_tenant_id
     and assignment.supplier_id = manifest.supplier_id
     and assignment.capability_code = target.code
     and assignment.assignment_source = 'observed'
     and assignment.valid_to is null
    where manifest.classification_confidence = 'high'
  ) then
    raise exception 'Observed assignment must be reviewed before curated enrichment'
      using errcode = '23514';
  end if;

  perform set_config(
    'request.jwt.claims',
    '{"role":"service_role"}',
    true
  );

  for v_row in
    select
      manifest.rn,
      manifest.supplier_id,
      manifest.expected_name,
      manifest.profile_patch,
      manifest.roles,
      manifest.capabilities,
      manifest.source_urls,
      manifest.classification_confidence
    from supplier_enrichment_manifest
      as manifest
    where classification_confidence = 'high'
    order by rn
  loop
    v_operation_id := md5(
      'vinabike_supplier_enrichment_20260809_profile:' ||
      v_row.supplier_id::text
    )::uuid;

    -- Match the canonical command's operation -> aggregate lock order before
    -- reading the merge payload. This prevents a concurrent candidate review
    -- or profile edit from being omitted and then closed by this save.
    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_profile_operation:' || v_tenant_id::text || ':' ||
      v_operation_id::text,
      0
    ));

    if exists (
      select 1
      from public.supplier_profile_command_receipts receipt
      where receipt.tenant_id = v_tenant_id
        and receipt.operation_id = v_operation_id
    ) then
      continue;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_profile:' || v_tenant_id::text || ':' ||
      v_row.supplier_id::text,
      0
    ));

    select supplier.party_id, supplier.updated_at
    into strict v_supplier
    from public.suppliers supplier
    where supplier.tenant_id = v_tenant_id
      and supplier.id = v_row.supplier_id
      and (
        supplier.name = v_row.expected_name
        or (
          v_row.profile_patch ? 'display_name'
          and supplier.name = nullif(
            btrim(v_row.profile_patch->>'display_name'), ''
          )
        )
      );

    select coalesce(jsonb_agg(item order by code), '[]'::jsonb)
    into v_roles
    from (
      select
        assignment.role_code as code,
        jsonb_build_object(
          'id', assignment.id,
          'code', assignment.role_code,
          'metadata', assignment.metadata
        ) as item
      from public.supplier_relationship_roles assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = v_row.supplier_id
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
      union all
      select
        target.code,
        jsonb_build_object(
          'code', target.code,
          'metadata', jsonb_build_object(
            'source', 'curated_supplier_enrichment',
            'batch', '2026-08-09',
            'confidence', v_row.classification_confidence,
            'source_urls', v_row.source_urls
          )
        )
      from jsonb_array_elements_text(v_row.roles) target(code)
      where not exists (
        select 1
        from public.supplier_relationship_roles assignment
        where assignment.tenant_id = v_tenant_id
          and assignment.supplier_id = v_row.supplier_id
          and assignment.role_code = target.code
          and assignment.assignment_source <> 'observed'
          and assignment.valid_to is null
      )
    ) role_items;

    select coalesce(jsonb_agg(item order by code), '[]'::jsonb)
    into v_capabilities
    from (
      select
        assignment.capability_code as code,
        jsonb_build_object(
          'id', assignment.id,
          'code', assignment.capability_code,
          'metadata', assignment.metadata
        ) as item
      from public.supplier_relationship_capabilities assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = v_row.supplier_id
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
      union all
      select
        target.code,
        jsonb_build_object(
          'code', target.code,
          'metadata', jsonb_build_object(
            'source', 'curated_supplier_enrichment',
            'batch', '2026-08-09',
            'confidence', v_row.classification_confidence,
            'source_urls', v_row.source_urls
          )
        )
      from jsonb_array_elements_text(v_row.capabilities) target(code)
      where not exists (
        select 1
        from public.supplier_relationship_capabilities assignment
        where assignment.tenant_id = v_tenant_id
          and assignment.supplier_id = v_row.supplier_id
          and assignment.capability_code = target.code
          and assignment.assignment_source <> 'observed'
          and assignment.valid_to is null
      )
    ) capability_items;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', assignment.id,
          'code', assignment.tag_code,
          'metadata', assignment.metadata
        ) order by assignment.tag_code
      ),
      '[]'::jsonb
    )
    into v_tags
    from public.supplier_relationship_tags assignment
    where assignment.tenant_id = v_tenant_id
      and assignment.supplier_id = v_row.supplier_id
      and assignment.assignment_source <> 'observed'
      and assignment.valid_to is null;

    select jsonb_build_object(
      'operation_id', v_operation_id,
      'party_metadata',
        coalesce(party.metadata, '{}'::jsonb) ||
        jsonb_build_object(
          'supplier_enrichment',
          jsonb_build_object(
            'batch', '2026-08-09',
            'source', 'public_and_erp_evidence',
            'source_urls', v_row.source_urls
          )
        )
    ) || v_row.profile_patch
    into v_profile
    from public.external_parties party
    where party.tenant_id = v_tenant_id
      and party.id = v_supplier.party_id;

    perform public.save_supplier_relationship_profile(
      v_tenant_id,
      v_row.supplier_id,
      v_supplier.updated_at,
      v_profile,
      v_roles,
      v_capabilities,
      v_tags
    );
  end loop;

  -- local/national describes geographic scope, not what the supplier does.
  for v_candidate in
    select candidate.id
    from public.supplier_classification_candidates candidate
    where candidate.tenant_id = v_tenant_id
      and candidate.status = 'pending'
      and candidate.source_kind = 'legacy_supplier_type'
      and candidate.target_vocabulary = 'role'
    order by candidate.id
  loop
    perform public.review_supplier_classification_candidate(
      v_tenant_id,
      v_candidate.id,
      'rejected',
      null,
      'Legacy local/national scope is geographic, not an operational supplier relation, and cannot determine a canonical role.'
    );
  end loop;

  -- Resolve deterministic legacy accounting vocabulary without guessing payroll.
  for v_candidate in
    select candidate.id, candidate.source_value
    from public.supplier_classification_candidates candidate
    where candidate.tenant_id = v_tenant_id
      and candidate.status = 'pending'
      and candidate.source_kind = 'legacy_expense_category'
      and candidate.target_vocabulary = 'operational_nature'
    order by candidate.id
  loop
    v_nature_code := case v_candidate.source_value
      when 'Arriendo' then 'rent_lease'
      when 'Costo de Ventas' then 'inventory_goods'
      when 'Gastos por Transporte' then 'freight_logistics'
      when 'Otros Gastos' then 'other_operating_expense'
      when 'Servicios Básicos' then 'utilities'
      when 'Servicios Digitales' then 'digital_services'
      when 'Suministros de Oficina' then 'other_operating_expense'
      else null
    end;
    v_decision := case when v_nature_code is null then 'rejected'
      else 'confirmed' end;

    perform public.review_supplier_classification_candidate(
      v_tenant_id,
      v_candidate.id,
      v_decision,
      v_nature_code,
      case
        when v_nature_code is null
          then 'Payroll is outside supplier operational-nature classification.'
        else 'Deterministic semantic mapping reviewed during supplier enrichment.'
      end
    );
  end loop;

  for v_row in
    select
      engagement.supplier,
      engagement.supplier_id,
      engagement.code,
      engagement.kind,
      engagement.name,
      engagement.status,
      engagement.starts_on,
      engagement.effective_from,
      engagement.billing_cycle,
      engagement.currency_code,
      engagement.expected_amount,
      engagement.external_reference,
      engagement.service_identifier,
      engagement.portal_url,
      engagement.terms
    from supplier_enrichment_engagements as engagement
    order by engagement.supplier, engagement.code
  loop
    v_operation_id := md5(
      'vinabike_supplier_enrichment_20260809_engagement:' ||
      v_row.supplier_id::text || ':' || v_row.code
    )::uuid;

    if not exists (
      select 1
      from public.supplier_engagements engagement
      where engagement.tenant_id = v_tenant_id
        and engagement.operation_id = v_operation_id
    ) then
      v_effective_from := coalesce(
        v_row.effective_from,
        public.tenant_business_date(v_tenant_id)
      );

      perform public.create_supplier_engagement(
        v_tenant_id,
        v_row.supplier_id,
        jsonb_strip_nulls(jsonb_build_object(
          'operation_id', v_operation_id,
          'engagement_kind', v_row.kind,
          'code', v_row.code,
          'name', v_row.name,
          'status', v_row.status,
          'starts_on', v_row.starts_on,
          'metadata', jsonb_build_object(
            'source', 'curated_supplier_enrichment',
            'batch', '2026-08-09'
          )
        )),
        jsonb_strip_nulls(jsonb_build_object(
          'effective_from', v_effective_from,
          'external_reference', v_row.external_reference,
          'service_identifier', v_row.service_identifier,
          'billing_cycle', v_row.billing_cycle,
          'currency_code', v_row.currency_code,
          'expected_amount', v_row.expected_amount,
          'portal_url', v_row.portal_url,
          'terms', v_row.terms
        ))
      );
    end if;
  end loop;

  for v_row in
    select
      policy.supplier,
      policy.supplier_id,
      policy.code,
      policy.name,
      policy.engagement_code,
      policy.nature,
      policy.category_id,
      policy.debit_account_id,
      policy.tax_treatment,
      policy.expected_document_type,
      policy.line_nature,
      policy.evidence_count
    from supplier_enrichment_policies as policy
    order by policy.supplier, policy.code
  loop
    v_operation_id := md5(
      'vinabike_supplier_enrichment_20260809_policy:' ||
      v_row.supplier_id::text || ':' || v_row.code
    )::uuid;

    if not exists (
      select 1
      from public.supplier_accounting_policies policy
      where policy.tenant_id = v_tenant_id
        and policy.operation_id = v_operation_id
    ) then
      select engagement.id
      into strict v_engagement_id
      from public.supplier_engagements engagement
      where engagement.tenant_id = v_tenant_id
        and engagement.supplier_id = v_row.supplier_id
        and engagement.code = v_row.engagement_code;

      perform public.create_supplier_accounting_policy(
        v_tenant_id,
        v_row.supplier_id,
        jsonb_build_object(
          'operation_id', v_operation_id,
          'engagement_id', v_engagement_id,
          'code', v_row.code,
          'name', v_row.name,
          'status', 'active',
          'priority', 100,
          'allow_exact_autofill', false
        ),
        jsonb_strip_nulls(jsonb_build_object(
          'effective_from', public.tenant_business_date(v_tenant_id),
          'operational_nature_code', v_row.nature,
          'legacy_expense_category_id', v_row.category_id,
          'debit_account_id', v_row.debit_account_id,
          'tax_treatment', v_row.tax_treatment,
          'expected_document_type', v_row.expected_document_type,
          'currency_code', 'CLP',
          'line_nature', v_row.line_nature,
          'posture', jsonb_build_object(
            'source', 'curated_erp_evidence',
            'evidence_count', v_row.evidence_count,
            'configuration_only', true
          )
        )),
        '[]'::jsonb
      );
    end if;
  end loop;

  if exists (
    select 1
    from supplier_enrichment_manifest manifest
    left join public.supplier_profile_read_model profile
      on profile.tenant_id = v_tenant_id
     and profile.supplier_id = manifest.supplier_id
    where manifest.classification_confidence = 'high'
      and (
        profile.supplier_id is null
        or (
          manifest.profile_patch ? 'display_name'
          and profile.display_name is distinct from nullif(
            btrim(manifest.profile_patch->>'display_name'), ''
          )
        )
        or (
          manifest.profile_patch ? 'party_kind'
          and profile.party_kind is distinct from lower(
            btrim(manifest.profile_patch->>'party_kind')
          )
        )
        or (
          manifest.profile_patch ? 'legal_name'
          and profile.legal_name is distinct from nullif(
            btrim(manifest.profile_patch->>'legal_name'), ''
          )
        )
        or (
          manifest.profile_patch ? 'trade_name'
          and profile.trade_name is distinct from nullif(
            btrim(manifest.profile_patch->>'trade_name'), ''
          )
        )
        or (
          manifest.profile_patch ? 'country_code'
          and profile.country_code is distinct from nullif(
            upper(btrim(manifest.profile_patch->>'country_code')), ''
          )
        )
        or (
          manifest.profile_patch ? 'tax_identifier'
          and profile.tax_identifier is distinct from nullif(
            btrim(manifest.profile_patch->>'tax_identifier'), ''
          )
        )
        or (
          manifest.profile_patch ? 'tax_country_code'
          and profile.tax_country_code is distinct from nullif(
            upper(btrim(manifest.profile_patch->>'tax_country_code')), ''
          )
        )
        or (
          manifest.profile_patch ? 'email'
          and profile.email is distinct from nullif(
            btrim(manifest.profile_patch->>'email'), ''
          )
        )
        or (
          manifest.profile_patch ? 'phone'
          and profile.phone is distinct from nullif(
            btrim(manifest.profile_patch->>'phone'), ''
          )
        )
        or (
          manifest.profile_patch ? 'website'
          and profile.website is distinct from nullif(
            btrim(manifest.profile_patch->>'website'), ''
          )
        )
        or (
          manifest.profile_patch ? 'address'
          and profile.address is distinct from nullif(
            btrim(manifest.profile_patch->>'address'), ''
          )
        )
        or (
          manifest.profile_patch ? 'city'
          and profile.city is distinct from nullif(
            btrim(manifest.profile_patch->>'city'), ''
          )
        )
        or (
          manifest.profile_patch ? 'region'
          and profile.region is distinct from nullif(
            btrim(manifest.profile_patch->>'region'), ''
          )
        )
        or (
          manifest.profile_patch ? 'comuna'
          and profile.comuna is distinct from nullif(
            btrim(manifest.profile_patch->>'comuna'), ''
          )
        )
        or (
          jsonb_typeof(manifest.profile_patch->'aliases') = 'array'
          and to_jsonb(profile.aliases) is distinct from
            manifest.profile_patch->'aliases'
        )
      )
  ) then
    raise exception 'Supplier enrichment profile read-back failed'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from supplier_enrichment_manifest manifest
    cross join lateral jsonb_array_elements_text(manifest.roles) target(code)
    where manifest.classification_confidence = 'high'
      and not exists (
      select 1
      from public.supplier_relationship_roles assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = manifest.supplier_id
        and assignment.role_code = target.code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    )
  ) or exists (
    select 1
    from supplier_enrichment_manifest manifest
    cross join lateral jsonb_array_elements_text(
      manifest.capabilities
    ) target(code)
    where manifest.classification_confidence = 'high'
      and not exists (
      select 1
      from public.supplier_relationship_capabilities assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = manifest.supplier_id
        and assignment.capability_code = target.code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    )
  ) then
    raise exception 'Supplier enrichment classification read-back failed'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.supplier_classification_candidates candidate
    where candidate.tenant_id = v_tenant_id
      and candidate.status = 'pending'
      and candidate.source_kind = 'legacy_supplier_type'
      and candidate.target_vocabulary = 'role'
  ) then
    raise exception 'Legacy supplier role candidates remain pending'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.supplier_classification_candidates candidate
    where candidate.tenant_id = v_tenant_id
      and candidate.status = 'pending'
      and candidate.source_kind = 'legacy_expense_category'
      and candidate.target_vocabulary = 'operational_nature'
  ) then
    raise exception 'Legacy expense-nature candidates remain pending'
      using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.supplier_engagements engagement
    join supplier_enrichment_engagements target
      on target.supplier_id = engagement.supplier_id
     and target.code = engagement.code
    where engagement.tenant_id = v_tenant_id
  ) <> (select count(*) from supplier_enrichment_engagements) then
    raise exception 'Supplier engagement read-back failed'
      using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.supplier_accounting_policies policy
    join supplier_enrichment_policies target
      on target.supplier_id = policy.supplier_id
     and target.code = policy.code
    where policy.tenant_id = v_tenant_id
      and policy.status = 'active'
  ) <> (select count(*) from supplier_enrichment_policies) then
    raise exception 'Supplier accounting-policy read-back failed'
      using errcode = 'P0001';
  end if;
end
$migration$;

commit;
