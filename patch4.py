
import re
with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

idx1 = text.find('decoration: const InputDecoration(labelText: \'Dirección\')')
if idx1 == -1: print('FAIL 1'); quit()

# find end of the expanded
idx2 = text.find('const SizedBox(height: 32)', idx1)
if idx2 == -1: print('FAIL 2'); quit()

new_content = '''decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionTitle('Portal B2B (Sitio del Proveedor)'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  labelText: 'URL del Portal / Sitio Web',
                  prefixIcon: Icon(Icons.language),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 52,
              child: AppButton(
                text: 'Abrir Portal',
                icon: Icons.open_in_browser,
                onPressed: _openWebsiteWorkspace,
                type: ButtonType.primary,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        '''

# We also need to remove the existing _buildSectionTitle('Portal B2B (Sitio del Proveedor)') and following SizedBox(height:16)
idx3 = text.find('Row(', idx2)

text = text[:idx1] + new_content + text[idx3:]

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print('YAY')

