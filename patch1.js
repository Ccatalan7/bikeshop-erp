const fs = require('fs');

let content = fs.readFileSync('lib/shared/widgets/product_autocomplete_field.dart', 'utf8');

const startStr = '        child: ClipRRect(\r\n          borderRadius: BorderRadius.circular(4),\r\n          child: ListView.builder(';
let start = content.indexOf(startStr);
if (start === -1) {
    const startStrAlt = '        child: ClipRRect(\n          borderRadius: BorderRadius.circular(4),\n          child: ListView.builder(';
    start = content.indexOf(startStrAlt);
}

const endStr = '  Widget _buildCustomItemTile(ThemeData theme) {';
const end = content.indexOf(endStr);
if (start === -1 || end === -1) {
  console.log("NOT FOUND", {start, end});
  process.exit(1);
}

const newStr = `        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFiltersBar(theme),
              Flexible(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount:
                      _filteredProducts.length + (widget.allowCustomItems ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Custom item option at the end
                    if (widget.allowCustomItems &&
                        index == _filteredProducts.length) {
                      if (_controller.text.trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _buildCustomItemTile(theme);
                    }

                    final product = _filteredProducts[index];
                    return _buildProductTile(product, theme);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersBar(ThemeData theme) {
    // Extract unique categories, brands, suppliers from _allFetchedProducts
    final categories = _allFetchedProducts
        .map((p) => p.categoryName)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    final brands = _allFetchedProducts
        .map((p) => p.brand)
        .where((b) => b != null && b.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    final suppliers = _allFetchedProducts
        .map((p) => p.supplierName)
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Filter by Title
          Text(
            'Filtros:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),

          // In Stock Toggle
          FilterChip(
            label: const Text('En stock'),
            selected: _onlyInStock,
            onSelected: (val) {
              setState(() => _onlyInStock = val);
              // rebuild dropdown
              _showOverlay(); 
            },
            visualDensity: VisualDensity.compact,
            labelStyle: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 8),

          // Products Toggle
          FilterChip(
            label: const Text('Productos'),
            selected: _showProducts,
            onSelected: (val) {
              setState(() => _showProducts = val);
              _showOverlay();
            },
            visualDensity: VisualDensity.compact,
            labelStyle: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 8),

          // Services Toggle
          FilterChip(
            label: const Text('Servicios'),
            selected: _showServices,
            onSelected: (val) {
              setState(() => _showServices = val);
              _showOverlay();
            },
            visualDensity: VisualDensity.compact,
            labelStyle: const TextStyle(fontSize: 12),
          ),
          
          if (categories.isNotEmpty || brands.isNotEmpty || suppliers.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 24, color: theme.colorScheme.outlineVariant),
            const SizedBox(width: 12),
          ],

          // Category Dropdown
          if (categories.isNotEmpty) ...[
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedCategory,
                hint: const Text('Categoría', style: TextStyle(fontSize: 12)),
                isDense: true,
                style: theme.textTheme.bodySmall,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas las categorías')),
                  ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (val) {
                  setState(() => _selectedCategory = val);
                  _showOverlay();
                },
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Brand Dropdown
          if (brands.isNotEmpty) ...[
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBrand,
                hint: const Text('Marca', style: TextStyle(fontSize: 12)),
                isDense: true,
                style: theme.textTheme.bodySmall,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas las marcas')),
                  ...brands.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                ],
                onChanged: (val) {
                  setState(() => _selectedBrand = val);
                  _showOverlay();
                },
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Supplier Dropdown
          if (suppliers.isNotEmpty) ...[
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedSupplier,
                hint: const Text('Proveedor', style: TextStyle(fontSize: 12)),
                isDense: true,
                style: theme.textTheme.bodySmall,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos los proveedores')),
                  ...suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) {
                  setState(() => _selectedSupplier = val);
                  _showOverlay();
                },
              ),
            ),
          ],
          
          const Spacer(),
          Text(
            \`\${_filteredProducts.length} resultados\`,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

`;

content = content.substring(0, start) + newStr + content.substring(end);
fs.writeFileSync('lib/shared/widgets/product_autocomplete_field.dart', content);
console.log("SUCCESS");