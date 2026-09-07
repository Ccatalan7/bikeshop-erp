insert into row_cardinality_document(doc) values ($cardinality_fixture$
{
  "schema_version": 1,
  "purpose": "Synthetic cardinality boundaries; one stable row ID is one declared occurrence. No mechanical/OEM/stock assertion.",
  "fields": {
    "items": {
      "data_type": "json",
      "schema": {
        "version": 1,
        "columns": [
          {
            "key": "label",
            "label": "Nombre observado",
            "type": "text",
            "required": true
          },
          {
            "key": "measure",
            "label": "Medida",
            "type": "integer",
            "required": true,
            "validation": {
              "min": "0"
            }
          },
          {
            "key": "state",
            "label": "Estado",
            "type": "token",
            "required": true,
            "allowed_values": [
              "Confirmado",
              "Desconocido / sin confirmar"
            ]
          },
          {
            "key": "active",
            "label": "Activo",
            "type": "boolean"
          }
        ]
      },
      "validation_rules": {
        "rows_schema": {
          "version": 1,
          "columns": [
            {
              "key": "label",
              "label": "Nombre observado",
              "type": "text",
              "required": true
            },
            {
              "key": "measure",
              "label": "Medida",
              "type": "integer",
              "required": true,
              "validation": {
                "min": "0"
              }
            },
            {
              "key": "state",
              "label": "Estado",
              "type": "token",
              "required": true,
              "allowed_values": [
                "Confirmado",
                "Desconocido / sin confirmar"
              ]
            },
            {
              "key": "active",
              "label": "Activo",
              "type": "boolean"
            }
          ]
        }
      }
    },
    "other_items": {
      "data_type": "json",
      "schema": {
        "version": 1,
        "columns": [
          {
            "key": "label",
            "label": "Nombre observado",
            "type": "text",
            "required": true
          },
          {
            "key": "measure",
            "label": "Medida",
            "type": "integer",
            "required": true,
            "validation": {
              "min": "0"
            }
          },
          {
            "key": "state",
            "label": "Estado",
            "type": "token",
            "required": true,
            "allowed_values": [
              "Confirmado",
              "Desconocido / sin confirmar"
            ]
          },
          {
            "key": "active",
            "label": "Activo",
            "type": "boolean"
          }
        ]
      },
      "validation_rules": {
        "rows_schema": {
          "version": 1,
          "columns": [
            {
              "key": "label",
              "label": "Nombre observado",
              "type": "text",
              "required": true
            },
            {
              "key": "measure",
              "label": "Medida",
              "type": "integer",
              "required": true,
              "validation": {
                "min": "0"
              }
            },
            {
              "key": "state",
              "label": "Estado",
              "type": "token",
              "required": true,
              "allowed_values": [
                "Confirmado",
                "Desconocido / sin confirmar"
              ]
            },
            {
              "key": "active",
              "label": "Activo",
              "type": "boolean"
            }
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
    "other_total": {
      "data_type": "number",
      "validation_rules": {
        "integer": true,
        "min": "0"
      }
    },
    "description": {
      "data_type": "text",
      "validation_rules": {}
    }
  },
  "contract": {
    "rules_version": 2,
    "allowed_when": {},
    "required_when": {},
    "allowed_options": {},
    "prerequisites": {},
    "roles": {
      "items": "contents",
      "other_items": "contents",
      "total": "contents",
      "other_total": "contents",
      "description": "contents"
    },
    "row_coherence": {
      "version": 2,
      "links": [],
      "cardinalities": [
        {
          "id": "contents_total",
          "field": "items",
          "total_field": "total"
        }
      ]
    }
  },
  "cases": [
    {
      "id": "zero_without_rows",
      "values": {
        "total": "0"
      },
      "expected": []
    },
    {
      "id": "equal_two_rows",
      "values": {
        "total": "2",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "more_rows_than_total",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_conflict",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "fewer_rows_than_total",
      "values": {
        "total": "3",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "positive_total_missing_table",
      "values": {
        "total": "2"
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "total_missing_with_rows",
      "values": {
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "both_missing",
      "values": {},
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "explicit_null_total",
      "values": {
        "total": null,
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "declared_unknown_total",
      "values": {
        "total": "Desconocido / sin confirmar",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "blank_total",
      "values": {
        "total": "  ",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "zero_does_not_delete_rows",
      "values": {
        "total": "0",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_conflict",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "safe_json_number",
      "values": {
        "total": 2,
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "integral_decimal",
      "values": {
        "total": "2.000",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "localized_integral_decimal",
      "values": {
        "total": " +002,0 ",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "integral_exponent",
      "values": {
        "total": "20e-1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "exact_total_above_binary_precision",
      "values": {
        "total": "9007199254740993",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "postgres_high_total",
      "values": {
        "total": "1e131071",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_pending",
          "field": "items",
          "row_id": null,
          "blocking": false
        }
      ]
    },
    {
      "id": "zero_with_large_exponent",
      "values": {
        "total": "0e1073741823"
      },
      "expected": []
    },
    {
      "id": "same_measure_is_not_duplicate_identity",
      "values": {
        "total": "2",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "partial_cells_still_count_occurrences",
      "values": {
        "total": "2",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "partial-a",
              "values": {
                "label": "Pieza A"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "partial-b",
              "values": {
                "state": "Desconocido / sin confirmar"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": []
    },
    {
      "id": "other_collection_is_not_summed",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        },
        "other_items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r2",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        },
        "other_total": "300"
      },
      "expected": []
    },
    {
      "id": "invalid_total_negative",
      "values": {
        "total": "-1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_fractional",
      "values": {
        "total": "1.5",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_false",
      "values": {
        "total": false,
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_true",
      "values": {
        "total": true,
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_array",
      "values": {
        "total": [
          "2"
        ],
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_object",
      "values": {
        "total": {
          "number": "2"
        },
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_incomplete_sign",
      "values": {
        "total": "-",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_not_a_number",
      "values": {
        "total": "NaN",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_infinity",
      "values": {
        "total": "Infinity",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_exponent_too_large",
      "values": {
        "total": "1e131072",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_zero_exponent_too_large",
      "values": {
        "total": "0e1073741824",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "r0",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "r1",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_wrong_document",
      "values": {
        "total": "1",
        "items": {
          "rows": "bad"
        }
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_array",
      "values": {
        "total": "1",
        "items": [
          {
            "id": "one",
            "values": {
              "label": "Pieza",
              "measure": "0",
              "state": "Confirmado"
            },
            "sources": [
              "https://example.com/document"
            ]
          }
        ]
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_duplicate_id",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "same",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "same",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_invalid_present_cell",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "valid",
              "values": {
                "label": "Pieza",
                "measure": "0",
                "state": "Confirmado"
              },
              "sources": [
                "https://example.com/document"
              ]
            },
            {
              "id": "invalid",
              "values": {
                "measure": "1.5"
              },
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_missing_id",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "values": {
                "label": "pieza"
              },
              "sources": []
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_empty_values",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": [
            {
              "id": "empty",
              "values": {},
              "sources": [
                "https://example.com/document"
              ]
            }
          ]
        }
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_empty_document",
      "values": {
        "total": "1",
        "items": {
          "schema_version": 1,
          "rows": []
        }
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_total_empty_array",
      "values": {
        "total": []
      },
      "expected": [
        {
          "code": "row_cardinality_total",
          "field": "total",
          "row_id": null,
          "blocking": true
        }
      ]
    },
    {
      "id": "invalid_rows_empty_array",
      "values": {
        "total": "0",
        "items": []
      },
      "expected": [
        {
          "code": "row_shape",
          "field": "items",
          "row_id": null,
          "blocking": true
        }
      ]
    }
  ],
  "invalid_metadata": [
    {
      "id": "v1_cannot_ignore_cardinalities",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 1,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "v2_requires_cardinalities",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": []
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "unknown_version",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 3,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "string_version",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": "2",
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "fractional_version_token",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2.0,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "null_bucket",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": null
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "null_cardinalities",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": null
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "object_cardinalities",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": {}
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "unknown_bucket_key",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ],
          "autofill": true
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "unknown_rule_key",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total",
              "sum_members": true
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "null_rule",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            null
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "foreign_total",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "foreign"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "non_number_total",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "description"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "non_rows_source",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "total",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "missing_rows_schema",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": null,
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "duplicate_id",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            },
            {
              "id": "contents_total",
              "field": "other_items",
              "total_field": "other_total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "one_table_cannot_have_two_totals",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            },
            {
              "id": "other_count",
              "field": "items",
              "total_field": "other_total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "identifier_is_not_a_label",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "Dos piezas",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "missing_integer_domain",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "min": "0"
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "string_integer_flag",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": "true",
            "min": "0"
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "missing_minimum",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "negative_minimum",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "-1"
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "invalid_minimum",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "NaN"
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "invalid_maximum",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0",
            "max": "NaN"
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "inverted_domain",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "contents_total",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "2",
            "max": "1"
          }
        },
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    },
    {
      "id": "trailing_newline_identifier",
      "contract": {
        "rules_version": 2,
        "allowed_when": {},
        "required_when": {},
        "allowed_options": {},
        "prerequisites": {},
        "roles": {
          "items": "contents",
          "other_items": "contents",
          "total": "contents",
          "other_total": "contents",
          "description": "contents"
        },
        "row_coherence": {
          "version": 2,
          "links": [],
          "cardinalities": [
            {
              "id": "occurrence\n",
              "field": "items",
              "total_field": "total"
            }
          ]
        }
      },
      "fields": {
        "items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
              ]
            }
          }
        },
        "other_items": {
          "data_type": "json",
          "schema": {
            "version": 1,
            "columns": [
              {
                "key": "label",
                "label": "Nombre observado",
                "type": "text",
                "required": true
              },
              {
                "key": "measure",
                "label": "Medida",
                "type": "integer",
                "required": true,
                "validation": {
                  "min": "0"
                }
              },
              {
                "key": "state",
                "label": "Estado",
                "type": "token",
                "required": true,
                "allowed_values": [
                  "Confirmado",
                  "Desconocido / sin confirmar"
                ]
              },
              {
                "key": "active",
                "label": "Activo",
                "type": "boolean"
              }
            ]
          },
          "validation_rules": {
            "rows_schema": {
              "version": 1,
              "columns": [
                {
                  "key": "label",
                  "label": "Nombre observado",
                  "type": "text",
                  "required": true
                },
                {
                  "key": "measure",
                  "label": "Medida",
                  "type": "integer",
                  "required": true,
                  "validation": {
                    "min": "0"
                  }
                },
                {
                  "key": "state",
                  "label": "Estado",
                  "type": "token",
                  "required": true,
                  "allowed_values": [
                    "Confirmado",
                    "Desconocido / sin confirmar"
                  ]
                },
                {
                  "key": "active",
                  "label": "Activo",
                  "type": "boolean"
                }
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
        "other_total": {
          "data_type": "number",
          "validation_rules": {
            "integer": true,
            "min": "0"
          }
        },
        "description": {
          "data_type": "text",
          "validation_rules": {}
        }
      }
    }
  ]
}
$cardinality_fixture$::jsonb);
