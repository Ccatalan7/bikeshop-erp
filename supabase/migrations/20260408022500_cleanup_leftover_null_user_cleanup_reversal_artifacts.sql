-- Cleanup leftover cleanup-reversal artifacts created on 2026-04-08.
-- These rows were emitted by trg_track_product_stock_changes during the first
-- null-user cleanup reversal run. They are audit noise only.
-- Do NOT reverse product stock here: current product stock already reflects
-- the intended cleanup reversal.

with target_adjustments as (
  select sa.id, sa.tenant_id, sa.product_id, sa.created_at
    from public.stock_adjustments sa
   where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and sa.adjustment_type = 'manual'
     and sa.created_by is null
     and sa.reason = 'Ajuste Manual'
     and sa.created_at = '2026-04-08 01:00:47.921421+00'::timestamptz
     and sa.product_id in (
       '083d9540-d25e-468f-a388-650f3d29aa05',
       '5443ddf6-712c-4286-82ed-4f296becdde2',
       '69f12463-9068-40be-8798-da84a8b75859',
       '73fee801-dd0c-43b8-a05a-7a47bda4bd9e',
       '770dbf83-66a7-4cd1-9912-4d1a20212955',
       '779ffcb0-e88b-42dd-b8d5-e81a7c923511',
       '7aca0a2c-3cf7-4bc5-8795-9bd2a2e3e445',
       '7c748b44-915d-4ed5-9da0-cdee6f9d3931',
       '87b19076-1626-478c-8941-32823cfec205',
       '88d93317-b93d-4085-a807-bdd25d13d37a',
       '89003840-7e5b-4a54-8e8d-32af9e160a7c',
       '8ab9c7f1-bc66-4904-b943-b098ae615358',
       '98fe588b-2847-4a50-9ff8-e2682ef9550a',
       'bfc1155a-b36e-4220-ae3f-9913164f6dff',
       'e28bf124-1b03-4c9d-b7e9-122dd2d8acba',
       'ff5080a9-9e1d-45df-8703-1d4cc274ebe9'
     )
), deleted_movements as (
  delete from public.stock_movements sm
   using target_adjustments ta
   where sm.tenant_id = ta.tenant_id
     and sm.product_id = ta.product_id
     and sm.created_at = ta.created_at
     and sm.movement_type = 'manual'
  returning sm.id
)
delete from public.stock_adjustments sa
 using target_adjustments ta
 where sa.id = ta.id;