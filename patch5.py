import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add required imports
if 'import \'dart:typed_data\';' not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'dart:typed_data';\nimport 'package:flutter/material.dart';")
if 'import \'../../../shared/services/image_service.dart\';' not in content:
    content = content.replace("import '../../../shared/utils/chilean_utils.dart';", "import '../../../shared/utils/chilean_utils.dart';\nimport '../../../shared/services/image_service.dart';\nimport '../../../shared/constants/storage_constants.dart';")

# 2. Add variables for image handling
content = content.replace(
    "final _imageUrlController = TextEditingController();",
    "String? _imageUrl;\n  Uint8List? _selectedImageBytes;\n  String? _selectedImageName;"
)

# 3. Remove dispose
content = content.replace(
    "    _imageUrlController.dispose();\n",
    ""
)

# 4. Initialize from existing
content = content.replace(
    "        _imageUrlController.text = supplier.imageUrl ?? '';",
    "        _imageUrl = supplier.imageUrl;"
)

# 5. Save with new image logic.
# Change the _save method to upload image
save_method_start = """  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      // Switch to the edit tab if validation fails
      if (widget.supplierId != null) {
        _tabController.animateTo(2);
      }
      return;
    }

    setState(() => _isSaving = true);
    
    try {"""

save_method_old = """  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      // Switch to the edit tab if validation fails
      if (widget.supplierId != null) {
        _tabController.animateTo(2);
      }
      return;
    }

    final now = DateTime.now();"""

content = content.replace(save_method_old, save_method_start)

# Add image logic before saving supplier instance
creating_supplier_old = """    final supplier = Supplier(
      id: _existing?.id ?? '',
      tenantId: _existing?.tenantId ?? '',
      name: _nameController.text.trim(),"""

creating_supplier_new = """      String? finalImageUrl = _imageUrl;

      if (_selectedImageBytes != null && _selectedImageName != null) {
        final uploadUrl = await ImageService.uploadBytes(
          bytes: _selectedImageBytes!,
          fileName: _selectedImageName!,
          bucket: StorageConfig.defaultBucket,
          folder: StorageFolders.suppliers,
        );

        if (uploadUrl == null) {
          throw Exception('No se pudo subir la imagen del proveedor. Intenta nuevamente.');
        }

        finalImageUrl = uploadUrl;
      }

      final now = DateTime.now();
      final supplier = Supplier(
        id: _existing?.id ?? '',
        tenantId: _existing?.tenantId ?? '',
        name: _nameController.text.trim(),"""

content = content.replace(creating_supplier_old, creating_supplier_new)

# Update imageUrl param in supplier construction
content = content.replace(
"""      imageUrl: _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),""",
    "      imageUrl: finalImageUrl,"
)

# Move setState to try/catch
set_state_saving_old = """    setState(() => _isSaving = true);

    try {"""

# We already added above! Let's just remove the old one:
content = content.replace(
"""    setState(() => _isSaving = true);

    try {
      await _purchaseService.saveSupplier(supplier);""",
"""      await _purchaseService.saveSupplier(supplier);"""
)

# Add _selectImage method
select_image_method = """
  Future<void> _selectImage() async {
    try {
      final result = await ImageService.pickImage();
      if (result != null) {
        setState(() {
          _selectedImageBytes = result.bytes;
          _selectedImageName = result.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seleccionando imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override"""

content = content.replace("  @override\n  Widget build(BuildContext context) {", select_image_method)

# Fix Avatar
old_avatar = """                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade100,
                    backgroundImage: _imageUrlController.text.isNotEmpty
                        ? NetworkImage(_imageUrlController.text)
                        : null,
                    child: _imageUrlController.text.isEmpty
                        ? Text(
                            _nameController.text.isNotEmpty
                                ? _nameController.text
                                    .substring(0, 1)
                                    .toUpperCase()
                                : '?',
                            style: TextStyle(
                                fontSize: 40, color: Colors.grey.shade400),
                          )
                        : null,
                  ),
                  Positioned("""

new_avatar = """                children: [
                  GestureDetector(
                    onTap: _selectImage,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey[300]!, width: 2),
                      ),
                      child: _selectedImageBytes != null
                          ? ClipOval(
                              child: Image.memory(
                                _selectedImageBytes!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : ImageService.buildAvatarImage(
                              imageUrl: _imageUrl,
                              radius: 50,
                              initials: _nameController.text.isNotEmpty 
                                  ? _nameController.text.substring(0, 1).toUpperCase() 
                                  : '?',
                            ),
                    ),
                  ),
                  Positioned("""

content = content.replace(old_avatar, new_avatar)

# Also adding a button or making it clickable? The avatar handles the click. But let's check profile panel update!
profile_panel_builder = """  Widget _buildProfilePanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _nameController,
        _typeController ?? ChangeNotifier(), // just a placeholder approach, actually let's use value listenables or just rebuild inside
      ]),"""

# Wait, instead of hacking an AnimatedBuilder, I can just replace `Widget _buildProfilePanel() { return Card(` with `Widget _buildProfilePanel() { return AnimatedBuilder( animation: Listenable.merge([_nameController, _rutController, _emailController, _phoneController, _websiteController, _addressController, _portalUsernameController, _portalPasswordController, _salesRepNameController, _salesRepPhoneController, _salesRepEmailController]), builder: (context, _) { return Card(`
# And add `}); }` at the end.

old_profile_panel_start = """  Widget _buildProfilePanel() {
    return Card("""

new_profile_panel_start = """  Widget _buildProfilePanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _nameController,
        _rutController,
        _emailController,
        _phoneController,
        _websiteController,
        _addressController,
        _portalUsernameController,
        _portalPasswordController,
        _salesRepNameController,
        _salesRepPhoneController,
        _salesRepEmailController,
      ]),
      builder: (context, _) {
        return Card("""

content = content.replace(old_profile_panel_start, new_profile_panel_start)

# End of profile panel
old_profile_panel_end = """          ],
        ),
      ),
    );
  }"""

new_profile_panel_end = """          ],
        ),
      ),
    );
      },
    );
  }"""

content = content.replace(old_profile_panel_end, new_profile_panel_end, 1)

# Remove the imageUrl field in the right panel!
old_image_field = """        const SizedBox(height: 16),
        TextFormField(
          controller: _imageUrlController,
          decoration: const InputDecoration(
            labelText: 'URL Imagen de Perfil (Logo)',
            hintText: 'https://...',
            prefixIcon: Icon(Icons.image),
          ),
        ),"""

content = content.replace(old_image_field, "")

# Remove the text button for selecting image if it's not intuitive enough or we can add it to the profile panel.
add_camera_button = """                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _selectImage,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Cambiar Logo'),
              ),
            ),
            const SizedBox(height: 8),
            Center("""

content = content.replace(
"""                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(""", add_camera_button
)

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
