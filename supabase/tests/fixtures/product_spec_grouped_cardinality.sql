create temporary table grouped_cardinality_document(doc jsonb);
insert into grouped_cardinality_document values ($grouped_fixture${
  "schema_version": 1,
  "purpose": "Synthetic per-configuration ownership/count boundaries. No OEM fitment, stock quantity, or model-variant selection assertion.",
  "contract": {
    "rules_version": 2,
    "allowed_when": {},
    "required_when": {},
    "allowed_options": {},
    "prerequisites": {},
    "roles": {
      "assemblies": "contents",
      "members": "contents",
      "total": "contents",
      "enabled": "contents"
    },
    "row_coherence": {
      "version": 3,
      "links": [
        {
          "id": "member_assembly",
          "field": "members",
          "column": "parent_row_id",
          "target_field": "assemblies",
          "label_columns": [
            "name"
          ]
        }
      ],
      "cardinalities": [
        {
          "id": "assembly_quantity",
          "field": "members",
          "group_by": "member_assembly",
          "total_column": "quantity"
        }
      ]
    }
  },
  "fields": {
    "assemblies": {
      "data_type": "json",
      "schema": {
        "version": 1,
        "columns": [
          {
            "key": "name",
            "label": "name",
            "type": "text"
          },
          {
            "key": "quantity",
            "label": "quantity",
            "type": "integer",
            "validation": {
              "min": "0"
            }
          }
        ],
        "unique_by": [
          [
            "name"
          ]
        ]
      },
      "validation_rules": {
        "rows_schema": {
          "version": 1,
          "columns": [
            {
              "key": "name",
              "label": "name",
              "type": "text"
            },
            {
              "key": "quantity",
              "label": "quantity",
              "type": "integer",
              "validation": {
                "min": "0"
              }
            }
          ],
          "unique_by": [
            [
              "name"
            ]
          ]
        }
      }
    },
    "members": {
      "data_type": "json",
      "schema": {
        "version": 1,
        "columns": [
          {
            "key": "parent_row_id",
            "label": "parent_row_id",
            "type": "text"
          },
          {
            "key": "position",
            "label": "position",
            "type": "integer",
            "validation": {
              "positive": true
            }
          },
          {
            "key": "note",
            "label": "note",
            "type": "text"
          }
        ],
        "unique_by": [
          [
            "parent_row_id",
            "position"
          ]
        ]
      },
      "validation_rules": {
        "rows_schema": {
          "version": 1,
          "columns": [
            {
              "key": "parent_row_id",
              "label": "parent_row_id",
              "type": "text"
            },
            {
              "key": "position",
              "label": "position",
              "type": "integer",
              "validation": {
                "positive": true
              }
            },
            {
              "key": "note",
              "label": "note",
              "type": "text"
            }
          ],
          "unique_by": [
            [
              "parent_row_id",
              "position"
            ]
          ]
        }
      }
    },
    "total": {
      "data_type": "number",
      "validation_rules": {
        "integer": true,
        "min": "0"
      }
    },
    "enabled": {
      "data_type": "boolean",
      "validation_rules": {}
    }
  },
  "cases": [
    {
      "id": "both_configurations_complete_scalar_remains_two",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": []
    },
    {
      "id": "one_short_one_long_cannot_cancel",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b3",
              "values": {
                "parent_row_id": "b",
                "position": "3"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        },
        {
          "code": "row_cardinality_conflict",
          "field": "assemblies",
          "row_id": "b",
          "column": "quantity",
          "blocking": true,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "one_parent_without_observations",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "b",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "no_children_does_not_invent_members",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        },
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "b",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "unknown_parent_total",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "A"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "zero_is_a_confirmed_total",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "A",
                "quantity": "0"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "zero_cannot_discard_observations",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "A",
                "quantity": "0"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_conflict",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": true,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "missing_configuration",
      "values": {},
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "missing_parent_table_preserves_link",
      "values": {
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_reference_pending",
          "field": "members",
          "row_id": "a1",
          "column": "parent_row_id",
          "blocking": false,
          "collection_field": null
        },
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "missing_owner_never_counts_under_another_parent",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_reference_pending",
          "field": "members",
          "row_id": "a1",
          "column": "parent_row_id",
          "blocking": false,
          "collection_field": null
        },
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "unknown_owner_is_pending",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "Desconocido / sin confirmar",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_reference_pending",
          "field": "members",
          "row_id": "a1",
          "column": "parent_row_id",
          "blocking": false,
          "collection_field": null
        },
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "dangling_owner_is_blocking",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "foreign",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_reference_unresolved",
          "field": "members",
          "row_id": "a1",
          "column": "parent_row_id",
          "blocking": true,
          "collection_field": null
        },
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "moving_one_row_is_not_global_equality",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "members",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "valid_reassignment_updates_both_counts",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "b",
                "position": "3"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        },
        {
          "code": "row_cardinality_conflict",
          "field": "assemblies",
          "row_id": "b",
          "column": "quantity",
          "blocking": true,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "duplicate_id_assemblies",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "a",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "malformed_assemblies",
      "values": {
        "assemblies": {},
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "duplicate_id_members",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "members",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "malformed_members",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {},
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "members",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "invalid_parent_total_18",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "-1"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "invalid_parent_total_19",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "1.5"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "invalid_parent_total_20",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "Desconocido / sin confirmar"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "assemblies",
          "row_id": null,
          "column": null,
          "blocking": true,
          "collection_field": null
        }
      ]
    },
    {
      "id": "quoted_huge_total_stays_exact",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "1e20"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "assemblies",
          "row_id": "a",
          "column": "quantity",
          "blocking": false,
          "collection_field": "members"
        }
      ]
    },
    {
      "id": "order_and_source_labels_do_not_change_ownership",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "a",
              "values": {
                "name": "Configuration A",
                "quantity": "2"
              },
              "sources": []
            },
            {
              "id": "b",
              "values": {
                "name": "Configuration B",
                "quantity": "2"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "b2",
              "values": {
                "parent_row_id": "b",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "b1",
              "values": {
                "parent_row_id": "b",
                "position": "1"
              },
              "sources": []
            },
            {
              "id": "a2",
              "values": {
                "parent_row_id": "a",
                "position": "2"
              },
              "sources": []
            },
            {
              "id": "a1",
              "values": {
                "parent_row_id": "a",
                "position": "1"
              },
              "sources": []
            }
          ]
        },
        "total": "2"
      },
      "expected": []
    },
    {
      "id": "stable_id_is_not_a_display_unknown_token",
      "values": {
        "assemblies": {
          "schema_version": 1,
          "rows": [
            {
              "id": "unknown",
              "values": {
                "name": "A",
                "quantity": "1"
              },
              "sources": []
            }
          ]
        },
        "members": {
          "schema_version": 1,
          "rows": [
            {
              "id": "child",
              "values": {
                "parent_row_id": "unknown",
                "position": "1"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": []
    }
  ],
  "invalid_metadata": [
    {
      "id": "grouped_v2_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "future_version_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 4,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "mixed_forms_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "dangling_group_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "absent",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "link_from_other_collection_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "assemblies",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "unknown_total_column_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "absent"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "non_numeric_total_column_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "name"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "duplicate_count_rule_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            },
            {
              "id": "another",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "link_id_collision_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "member_assembly",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "partial_form_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "free_text_override_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity",
              "conditions": "compatible"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "decimal_total_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "decimal",
                "validation": {
                  "min": "0"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "decimal",
                  "validation": {
                    "min": "0"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "negative_domain_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {
                  "min": "-1"
                }
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {
                    "min": "-1"
                  }
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "missing_minimum_rejected",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "assemblies": "contents",
          "members": "contents",
          "total": "contents",
          "enabled": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [
            {
              "id": "member_assembly",
              "field": "members",
              "column": "parent_row_id",
              "target_field": "assemblies",
              "label_columns": [
                "name"
              ]
            }
          ],
          "cardinalities": [
            {
              "id": "assembly_quantity",
              "field": "members",
              "group_by": "member_assembly",
              "total_column": "quantity"
            }
          ]
        }
      },
      "fields": {
        "assemblies": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "name",
                "label": "name",
                "type": "text"
              },
              {
                "key": "quantity",
                "label": "quantity",
                "type": "integer",
                "validation": {}
              }
            ],
            "unique_by": [
              [
                "name"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "name",
                  "label": "name",
                  "type": "text"
                },
                {
                  "key": "quantity",
                  "label": "quantity",
                  "type": "integer",
                  "validation": {}
                }
              ],
              "unique_by": [
                [
                  "name"
                ]
              ]
            }
          }
        },
        "members": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "parent_row_id",
                "label": "parent_row_id",
                "type": "text"
              },
              {
                "key": "position",
                "label": "position",
                "type": "integer",
                "validation": {
                  "positive": true
                }
              },
              {
                "key": "note",
                "label": "note",
                "type": "text"
              }
            ],
            "unique_by": [
              [
                "parent_row_id",
                "position"
              ]
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "parent_row_id",
                  "label": "parent_row_id",
                  "type": "text"
                },
                {
                  "key": "position",
                  "label": "position",
                  "type": "integer",
                  "validation": {
                    "positive": true
                  }
                },
                {
                  "key": "note",
                  "label": "note",
                  "type": "text"
                }
              ],
              "unique_by": [
                [
                  "parent_row_id",
                  "position"
                ]
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "enabled": {
          "data_type": "boolean",
          "validation_rules": {}
        }
      }
    }
  ]
}
$grouped_fixture$::jsonb);
