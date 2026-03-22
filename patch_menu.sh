#!/bin/bash
FILE="lib/modules/bikeshop/pages/pegas_table_page.dart"
perl -0777 -pi -e 's/itemBuilder: \(context\) => \[\n                const PopupMenuItem\(/itemBuilder: (context) => [\n                if (job.jobType == JobType.warranty || job.jobType == JobType.quotation)\n                  const PopupMenuItem(\n                    value: '"'convert'"',\n                    child: Row(\n                      children: [\n                        Icon(Icons.transform, size: 18),\n                        SizedBox(width: 8),\n                        Text('"'"'Convertir a Normal'"'"'),\n                      ],\n                    ),\n                  ),\n                const PopupMenuItem(/s' "$FILE"

perl -0777 -pi -e 's/if \(value == '"'"'complete'"'"'\) \{/if (value == '"'"'convert'"'"') {\n                  _convertToService(job);\n                } else if (value == '"'"'complete'"'"') {/s' "$FILE"
