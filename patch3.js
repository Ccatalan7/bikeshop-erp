const fs = require('fs');
const file = 'c:\\dev\\ProjectVinabike\\lib\\shared\\widgets\\product_autocomplete_field.dart';
let c = fs.readFileSync(file, 'utf8');

c = c.replace(/setState\(\(\) => _filterInStockOnly = val\);\s*\/\/\s*rebuild dropdown\s*_showOverlay\(\);/g, 
  "setState(() => _filterInStockOnly = val);\n              _updateOverlay();\n              _focusNode.requestFocus();");

c = c.replace(/setState\(\(\) => _filterShowProducts = val\);\s*_showOverlay\(\);/g, 
  "setState(() => _filterShowProducts = val);\n              _updateOverlay();\n              _focusNode.requestFocus();");

c = c.replace(/setState\(\(\) => _filterShowServices = val\);\s*_showOverlay\(\);/g, 
  "setState(() => _filterShowServices = val);\n              _updateOverlay();\n              _focusNode.requestFocus();");

c = c.replace(/setState\(\(\) => _selectedCategory = val\);\s*_showOverlay\(\);/g, 
  "setState(() => _selectedCategory = val);\n                  _updateOverlay();\n                  _focusNode.requestFocus();");

c = c.replace(/setState\(\(\) => _selectedBrand = val\);\s*_showOverlay\(\);/g, 
  "setState(() => _selectedBrand = val);\n                  _updateOverlay();\n                  _focusNode.requestFocus();");

c = c.replace(/setState\(\(\) => _selectedSupplier = val\);\s*_showOverlay\(\);/g, 
  "setState(() => _selectedSupplier = val);\n                  _updateOverlay();\n                  _focusNode.requestFocus();");

fs.writeFileSync(file, c);
console.log('done!');