-- Numerical facts are measurements/counts, not universal component-fit limits.
-- Sources: https://www.sheldonbrown.com/cribsheet-bcd.html (BCD 58, 145, 146)
-- https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards-and-terminology
-- (PF41 shell widths include 132 mm). Other former stock-sized caps have no
-- universal evidence. Removing a cap permits recording an observation; it
-- never approves installation. Model-specific/reference checks stay intact.
-- No product, fact, category, reference, price or stock backfill.
begin;
create temporary table spec_numeric_review on commit drop as
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
$review$::jsonb) as r(key text, old_rules jsonb, new_rules jsonb);

do $$
begin
 if (select count(*) from public.spec_definitions d join spec_numeric_review r on r.key=d.key
   where d.tenant_id is null and d.data_type='number' and d.validation_rules=r.old_rules) <> 35 then
   raise exception 'Numeric specification baseline drifted; review before applying';
 end if;
 -- Existing observations are never erased or silently relabelled to make this pass.
 if exists(select 1 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
   join spec_numeric_review r on r.key=d.key where d.tenant_id is null and f.value_number is not null
   and ((r.new_rules->>'positive'='true' and f.value_number<=0)
     or (r.new_rules->>'integer'='true' and f.value_number<>trunc(f.value_number))
     or (r.new_rules ? 'min' and f.value_number<(r.new_rules->>'min')::numeric))) then
   raise exception 'Existing facts need review before stronger numeric domain constraints';
 end if;
end $$;

update public.spec_definitions d set validation_rules=r.new_rules
 from spec_numeric_review r where d.key=r.key and d.tenant_id is null;
-- product_spec_definition_revision advances every affected template version.
-- Preserve that owner; do not add a second bump or audit notes to form_contract.
commit;
