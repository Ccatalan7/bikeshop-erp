import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = re.compile(r'  Future<void> _save\(\) async \{.*?(?=  Future<void> _selectImage\(\) async \{)', re.DOTALL)
match = pattern.search(content)

if match:
    old_save = match.group(0)
    
    new_save = """  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      if (widget.supplierId != null) {
        _tabController.animateTo(2);
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? finalImageUrl = _imageUrl;

      if (_selectedImageBytes != null && _selectedImageName != null) {
        final uploadUrl = await ImageService.uploadBytes(
          bytes: _selectedImageBytes!,
          fileName: _selectedImageName!,
          bucket: StorageConfig.defaultBucket,
          folder: StorageFolders.suppliers,
        );

        if (uploadUrl == null) {
          throw Exception('No se pudo subir la imagen. Intenta de nuevo.');
        }
        finalImageUrl = uploadUrl;
      }

      final now = DateTime.now();
      final supplier = Supplier(
        id: _existing?.id ?? '',
        tenantId: _existing?.tenantId ?? '',
        name: _nameController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        rut: _rutController.text.trim().isEmpty ? null : _rutController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        region: _regionController.text.trim().isEmpty ? null : _regionController.text.trim(),
        comuna: _comunaController.text.trim().isEmpty ? null : _comunaController.text.trim(),
        type: _type,
        contactPerson: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
        website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
        bankDetails: _existing?.bankDetails ?? const {},
        paymentTerms: _paymentTerms,
        defaultTaxTreatment: _defaultTaxTreatment,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        imageUrl: finalImageUrl,
        portalUsername: _portalUsernameController.text.trim().isEmpty ? null : _portalUsernameController.text.trim(),
        portalPassword: _portalPasswordController.text.trim().isEmpty ? null : _portalPasswordController.text.trim(),
        salesRepName: _salesRepNameController.text.trim().isEmpty ? null : _salesRepNameController.text.trim(),
        salesRepPhone: _salesRepPhoneController.text.trim().isEmpty ? null : _salesRepPhoneController.text.trim(),
        salesRepEmail: _salesRepEmailController.text.trim().isEmpty ? null : _salesRepEmailController.text.trim(),
        purchaseInstructions: _purchaseInstructionsController.text.trim().isEmpty ? null : _purchaseInstructionsController.text.trim(),
        isActive: _isActive,
        createdAt: _existing?.createdAt ?? now,
        updatedAt: now,
      );

      await _purchaseService.saveSupplier(supplier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_existing == null ? 'Proveedor creado' : 'Proveedor actualizado'),
          backgroundColor: Colors.green,
        ),
      );
      _closePage(saved: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

"""
    content = content.replace(old_save, new_save)
    with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed _save!')
else:
    print('Could not find _save pattern')