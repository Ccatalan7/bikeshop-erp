with reviewed as (
 select * from jsonb_to_recordset($review$
[
  {
    "key": "bb_ball_count_per_side",
    "old_rules": {
      "max": 20,
      "min": 5
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "bb_bearing_width_mm",
    "old_rules": {
      "max": 20,
      "min": 5
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "bb_cup_outer_diameter_mm",
    "old_rules": {
      "max": 60,
      "min": 30
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "bb_shell_diameter_mm",
    "old_rules": {
      "max": 60,
      "min": 30
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "bb_shell_width_mm",
    "old_rules": {
      "max": 125,
      "min": 50
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "bb_spacer_stack_mm",
    "old_rules": {
      "max": 10,
      "min": 0
    },
    "new_rules": {
      "min": 0
    }
  },
  {
    "key": "bearing_inner_diameter_mm",
    "old_rules": {
      "max": 40,
      "min": 5
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "bearing_outer_diameter_mm",
    "old_rules": {
      "max": 60,
      "min": 10
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "chainline_mm",
    "old_rules": {
      "max": 60,
      "min": 35
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "chainring_bcd_mm",
    "old_rules": {
      "max": 144,
      "min": 64
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "chainring_offset_mm",
    "old_rules": {
      "max": 10,
      "min": -10
    },
    "new_rules": {}
  },
  {
    "key": "crank_arm_length_mm",
    "old_rules": {
      "max": 190,
      "min": 130
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "hose_length_mm",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "largest_cog_teeth",
    "old_rules": {
      "max": 60,
      "min": 14
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "pulley_teeth",
    "old_rules": {
      "max": 18,
      "min": 8
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "rear_derailleur_max_teeth",
    "old_rules": {
      "max": 60,
      "min": 24
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "rear_derailleur_min_teeth",
    "old_rules": {
      "max": 24,
      "min": 8
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "rear_derailleur_total_capacity_teeth",
    "old_rules": {
      "max": 60,
      "min": 10
    },
    "new_rules": {
      "min": 0,
      "integer": true
    }
  },
  {
    "key": "rim_erd_mm",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "rim_external_width_mm",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "rim_internal_width_mm",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "rotor_thickness_mm",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "sealant_volume_ml",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "single_cog_teeth",
    "old_rules": {
      "max": 24,
      "min": 9
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "smallest_cog_teeth",
    "old_rules": {
      "max": 24,
      "min": 8
    },
    "new_rules": {
      "positive": true,
      "integer": true
    }
  },
  {
    "key": "spacer_thickness_mm",
    "old_rules": {
      "max": 10,
      "min": 0.5
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "spindle_diameter_mm",
    "old_rules": {
      "max": 32,
      "min": 15
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "spindle_length_mm",
    "old_rules": {
      "max": 150,
      "min": 100
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "spoke_length_mm",
    "old_rules": {},
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "tire_width_in",
    "old_rules": {
      "max": 6,
      "min": 0.5
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "tire_width_mm",
    "old_rules": {
      "max": 150,
      "min": 15
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "tube_width_max_in",
    "old_rules": {
      "max": 6,
      "min": 0.5
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "tube_width_max_mm",
    "old_rules": {
      "max": 120,
      "min": 10
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "tube_width_min_in",
    "old_rules": {
      "max": 6,
      "min": 0.5
    },
    "new_rules": {
      "positive": true
    }
  },
  {
    "key": "tube_width_min_mm",
    "old_rules": {
      "max": 120,
      "min": 10
    },
    "new_rules": {
      "positive": true
    }
  }
]
$review$::jsonb) as r(key text, old_rules jsonb, new_rules jsonb)
), observed as (select r.key,d.validation_rules=r.old_rules as baseline_matches,
 d.validation_rules=r.new_rules as correction_applied,
 (select count(*) from public.spec_facts f where f.spec_definition_id=d.id and f.value_number is not null
   and ((r.new_rules->>'positive'='true' and f.value_number<=0)
     or (r.new_rules->>'integer'='true' and f.value_number<>trunc(f.value_number))
     or (r.new_rules ? 'min' and f.value_number<(r.new_rules->>'min')::numeric))) as facts_requiring_review
 from reviewed r left join public.spec_definitions d on d.key=r.key and d.tenant_id is null )
select 1 / (count(*)=35 and bool_and(correction_applied) and bool_and(facts_requiring_review=0))::integer as numeric_domains_verified from observed;

with expected as (select * from jsonb_to_recordset($versions$[{"id": "0251857d-dbc1-49fc-94c7-0cba60aa8921", "key": "brake_pad", "before": 2, "after": 2}, {"id": "047523e5-829c-4509-ae83-ea5b8cdd4b31", "key": "bottom_bracket_axle", "before": 2, "after": 4}, {"id": "0750e4ac-4615-4ad4-862e-95ac102b12f7", "key": "rear_derailleur", "before": 2, "after": 5}, {"id": "0aaec6de-c69d-4e1e-9b03-995805a30a9c", "key": "chain_guide", "before": 2, "after": 3}, {"id": "11aa1aa7-9589-4f19-ac74-df7fd35a3028", "key": "chainring", "before": 2, "after": 4}, {"id": "1819b68d-72d4-464a-b69d-ba3f2eaa59b3", "key": "tubeless_valve", "before": 2, "after": 2}, {"id": "1a4ff9ad-d0c1-4f6d-a0d6-13848828ea8b", "key": "crank_arm", "before": 2, "after": 3}, {"id": "22fdca94-afe0-4221-a436-959c8ce94a81", "key": "hydraulic_disc_brake", "before": 2, "after": 3}, {"id": "2da2770c-a4de-48df-840e-4d9dc1f4aea1", "key": "rim_strip", "before": 2, "after": 2}, {"id": "3a76d564-008d-487b-bd70-0c6179dec598", "key": "rim_brake", "before": 2, "after": 2}, {"id": "4d5edd21-5818-4c98-827a-7154d1eebfe4", "key": "tire", "before": 2, "after": 4}, {"id": "50c9c0f2-5aec-4ffb-a54e-fad0c62124f4", "key": "bottom_bracket_cup", "before": 2, "after": 4}, {"id": "564abb7f-94bc-4349-adfe-66ba7ed8e897", "key": "cassette_spacer", "before": 2, "after": 3}, {"id": "590232e5-d21a-4a47-9419-1bf42e6b1922", "key": "front_derailleur", "before": 2, "after": 2}, {"id": "5e92fbe9-9246-435a-abf7-a3fc9371dd5a", "key": "hub", "before": 2, "after": 2}, {"id": "61005a7e-a107-49f3-96c3-2fa2796d3299", "key": "shifter", "before": 2, "after": 2}, {"id": "6a02a0c2-b139-46ef-86d8-bba3797252bd", "key": "cassette", "before": 2, "after": 4}, {"id": "6d80cd0c-81ac-41c1-af17-7a59a2b04b61", "key": "drivetrain_kit", "before": 2, "after": 3}, {"id": "786de6d8-351a-4297-a8d2-70bf41c2da9c", "key": "tubeless_consumable", "before": 2, "after": 3}, {"id": "81547e3f-433c-462e-9dbe-a141aef745c9", "key": "rim", "before": 2, "after": 5}, {"id": "91a0c6d5-9c0a-443f-b2e9-2e0ab5f431ce", "key": "crankset", "before": 2, "after": 4}, {"id": "98f78948-c186-4340-ae78-ce315b3c3aef", "key": "bottom_bracket_bearing", "before": 2, "after": 7}, {"id": "9c93c819-cd05-4615-9e57-091af95cf1f0", "key": "chain_link", "before": 24, "after": 24}, {"id": "9d97103e-d49f-4d77-974d-23f775fb49c8", "key": "brake_caliper", "before": 2, "after": 2}, {"id": "a0cb2acf-1e70-4319-abbd-a4f9cae82f8e", "key": "spoke", "before": 2, "after": 3}, {"id": "a2ba0aad-9c5c-4563-a4f5-75cf2611a43a", "key": "rotor", "before": 2, "after": 3}, {"id": "a4f78fa2-219f-44c6-82c4-d7d63e79cb1d", "key": "bottom_bracket", "before": 2, "after": 9}, {"id": "a505c7c6-ef02-4706-900b-25d927886669", "key": "derailleur_hanger", "before": 2, "after": 2}, {"id": "a9d0494f-08b5-42df-9836-42e302d2d9f5", "key": "chain", "before": 6, "after": 6}, {"id": "b6df9356-898e-4f0b-aea8-d27db45e96d1", "key": "mechanical_disc_brake", "before": 2, "after": 2}, {"id": "be18a720-6f16-42e3-be65-44d6a9c8ce35", "key": "fixed_cog", "before": 2, "after": 3}, {"id": "c97799a4-b611-43c5-83f1-de4a407dd8f6", "key": "freewheel", "before": 2, "after": 4}, {"id": "d293dc44-f47a-4dd8-801f-3de0c5749da3", "key": "bearing", "before": 2, "after": 2}, {"id": "dee33c12-b165-48ea-ac1a-7a10b0144d1a", "key": "brake_lever", "before": 2, "after": 2}, {"id": "e009fd36-b385-4224-b4be-d448543be7bd", "key": "derailleur_pulley", "before": 2, "after": 3}, {"id": "e1adfef6-6dba-467d-838b-159dc65d8a7b", "key": "tube", "before": 2, "after": 6}, {"id": "f55b7846-c3df-45ba-b4b7-ac55970db612", "key": "headset", "before": 2, "after": 2}]$versions$::jsonb) r(id uuid,key text,before integer,after integer))
select 1 / (count(*)=37 and bool_and(t.contract_version=e.after))::integer as all_template_versions_verified
from expected e left join public.spec_templates t on t.id=e.id;

select 1 / (pg_get_functiondef('public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)'::regprocedure) is not null and md5((select prosrc from pg_proc where oid='public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)'::regprocedure)) = 'c5a5b460006822c752b662492b98ddc9')::integer as validator_unchanged;
