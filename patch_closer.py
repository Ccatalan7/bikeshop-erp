import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Make profile panel end with });
pattern = r"(_buildInfoRow\(.*_salesRepEmailController\.text\),\n\s*\],\n\s*\),\n\s*\),\n\s*\);\n  })"
match = re.search(pattern, content)
if match:
    # Need to add }, ); at the end of the builder function
    content = content[:match.end()] + "\n      },\n    );" + content[match.end():]
    # Remove the first `)` `}` because we replaced it. Actually match already includes it. Let's do it cleanly!

    # A better way: replace `return Card(` to `return AnimatedBuilder... return Card(` which we DID!
    # And we just need to append `}, );` after the Card is closed.
    
    # Wait, let's just find the closing of `_buildProfilePanel` before `Widget _buildInfoRow`
    
    parts = content.split("Widget _buildInfoRow")
    
    # parts[0] has the profile panel
    profile_panel_source = parts[0]
    # it currently ends with:
    #           ],
    #         ),
    #       ),
    #     );
    #   }
    
    fixed_profile_panel_source = profile_panel_source.rstrip()[:-1].rstrip()[:-2].rstrip()[:-2].rstrip()[:-2]
    # basically remove the closing brackets, I'll just do a targeted replace
    
    # old:
    #       ],
    #     ),
    #   ),
    # );
    # }
    
    # new:
    #       ],
    #     ),
    #   ),
    # );
    #   },
    # );
    # }
    content = content.replace(
        "        ],\n        ),\n      ),\n    );\n  }",
        "        ],\n        ),\n      ),\n    );\n      },\n    );\n  }"
    )

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)

