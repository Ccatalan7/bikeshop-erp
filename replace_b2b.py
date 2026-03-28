
import sys

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

import re

# We will use regex to find everything from 'const InputDecoration(labelText: \'Dirección\')' to 'prefixIcon: Icon(Icons.password)'

pattern = re.compile(r'Expanded\(\s*child: TextFormField\(\s*controller: _addressController,\s*decoration: const InputDecoration\(labelText: \'Dirección\'\),\s*\),\s*\),\s*const SizedBox\(width: 16\),\s*Expanded\(\s*child: TextFormField\(\s*controller: _websiteController,\s*decoration: const InputDecoration\(labelText: \'Sitio Web\'\),\s*\),\s*\),\s*\],\s*\),\s*const SizedBox\(height: 32\),\s*_buildSectionTitle\(\'Portal B2B \(Sitio del Proveedor\)\'\),\s*const SizedBox\(height: 16\)', re.MULTILINE)

match = pattern.search(content)
if match:
    new_text = '''Expanded(
              child: TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: \'Dirección\'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionTitle(\'Portal B2B (Sitio del Proveedor)\'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  labelText: \'URL del Portal / Sitio Web\',
                  prefixIcon: Icon(Icons.language),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 52,
              child: AppButton(
                text: \'Abrir Portal\',
                icon: Icons.open_in_browser,
                onPressed: _openWebsiteWorkspace,
                type: ButtonType.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16)'''
    content = content[:match.start()] + new_text + content[match.end():]
    with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS REGEX')
else:
    print('REGEX FAILED')
