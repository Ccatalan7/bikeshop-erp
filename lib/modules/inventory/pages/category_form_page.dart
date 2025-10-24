import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/constants/storage_constants.dart';
import '../models/category_models.dart';
import '../services/category_service.dart';

class CategoryFormPage extends StatefulWidget {
  final String? categoryId;
  final String? parentCategoryId; // New: context-aware parent

  const CategoryFormPage({
    super.key,
    this.categoryId,
    this.parentCategoryId,
  });

  @override
  State<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends State<CategoryFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(); // Just the category name
  final _descriptionController = TextEditingController();

  bool _isActive = true;
  String? _imageUrl;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

  bool _isLoading = false;
  bool _isSaving = false;
  Category? _existingCategory;
  Category? _selectedParent; // User-selected parent via tree navigator

  late CategoryService _categoryService;

  @override
  void initState() {
    super.initState();
    _categoryService = CategoryService(
      Provider.of<DatabaseService>(context, listen: false),
    );

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    try {
      if (widget.categoryId != null) {
        // Edit mode
        await _loadCategory();
      } else if (widget.parentCategoryId != null) {
        // Create mode with context
        _selectedParent = await _categoryService.getCategoryById(widget.parentCategoryId!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategory() async {
    try {
      final category =
          await _categoryService.getCategoryById(widget.categoryId!);
      if (category != null) {
        setState(() {
          _existingCategory = category;
          _nameController.text = category.name;
          _descriptionController.text = category.description ?? '';
          _isActive = category.isActive;
          _imageUrl = category.imageUrl;
          
          // Load parent if exists
          if (category.parentId != null) {
            _categoryService.getCategoryById(category.parentId!).then((parent) {
              if (parent != null && mounted) {
                setState(() => _selectedParent = parent);
              }
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando categoría: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
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

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? finalImageUrl = _imageUrl;

      // Upload new image if selected
      if (_selectedImageBytes != null && _selectedImageName != null) {
        final uploadUrl = await ImageService.uploadBytes(
          bytes: _selectedImageBytes!,
          fileName: _selectedImageName!,
          bucket: StorageConfig.defaultBucket,
          folder: StorageFolders.categories,
        );

        if (uploadUrl == null) {
          throw Exception(
              'No se pudo subir la imagen de la categoría. Intenta nuevamente.');
        }

        finalImageUrl = uploadUrl;
      }

      final categoryName = _nameController.text.trim();
      
      // Build full path from parent + name
      String fullPath;
      String? parentId;
      int level;
      
      if (_selectedParent != null) {
        fullPath = '${_selectedParent!.fullPath} / $categoryName';
        parentId = _selectedParent!.id;
        level = _selectedParent!.level + 1;
      } else {
        fullPath = categoryName;
        parentId = null;
        level = 0;
      }
      
      final category = Category(
        id: _existingCategory?.id,
        name: categoryName,
        fullPath: fullPath,
        parentId: parentId,
        level: level,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        imageUrl: finalImageUrl,
        isActive: _isActive,
      );

      if (_existingCategory != null) {
        await _categoryService.updateCategory(category);
      } else {
        await _categoryService.createCategory(category);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_existingCategory != null
                ? 'Categoría actualizada exitosamente'
                : 'Categoría creada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando categoría: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _showParentPicker() async {
    final selected = await showDialog<Category?>(
      context: context,
      builder: (context) => _CategoryTreePicker(
        categoryService: _categoryService,
        currentSelection: _selectedParent,
        excludeId: widget.categoryId, // Don't allow selecting self or children
      ),
    );
    
    if (selected != null || selected == null && _selectedParent != null) {
      // User made a selection or cleared it
      setState(() => _selectedParent = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _existingCategory != null
                        ? 'Editar Categoría'
                        : 'Nueva Categoría',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Guardar',
                  icon: Icons.save,
                  onPressed: _isSaving ? null : _saveCategory,
                  isLoading: _isSaving,
                ),
              ],
            ),
          ),

          // Form content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Parent Category Picker Section
                    const Text(
                      'Ubicación',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Interactive Parent Selector
                    InkWell(
                      onTap: _showParentPicker,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedParent != null ? Icons.folder : Icons.folder_open,
                              color: Theme.of(context).colorScheme.primary,
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedParent != null
                                        ? 'Categoría Padre'
                                        : 'Categoría Raíz (sin padre)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedParent?.fullPath ?? '📁 Nivel superior',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.navigate_next, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    Text(
                      '💡 Toca para elegir dónde crear esta categoría. Puedes navegar por la jerarquía completa.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),

                    const SizedBox(height: 24),

                    // Category Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la Categoría *',
                        hintText: 'Ej: Bicicletas, Asientos, Tijas',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'El nombre es requerido';
                        }
                        if (value.trim().length < 2) {
                          return 'El nombre debe tener al menos 2 caracteres';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 8),
                    
                    // Preview of full path
                    if (_nameController.text.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Se creará: ${_selectedParent != null ? "${_selectedParent!.fullPath} / " : ""}${_nameController.text.trim()}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        hintText: 'Descripción opcional de la categoría',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 50),
                          child: Icon(Icons.description),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Image Section
                    const Text(
                      'Imagen',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Image picker
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _buildImagePicker(),
                    ),

                    const SizedBox(height: 24),

                    // Status
                    const Text(
                      'Estado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    SwitchListTile(
                      title: const Text('Categoría Activa'),
                      subtitle: Text(_isActive
                          ? 'La categoría está disponible para su uso'
                          : 'La categoría está oculta y no se puede usar'),
                      value: _isActive,
                      onChanged: (value) {
                        setState(() => _isActive = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    if (_selectedImageBytes != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _selectedImageBytes!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedImageBytes = null;
                    _selectedImageName = null;
                  });
                },
              ),
            ),
          ),
        ],
      );
    }

    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ImageService.buildCachedImage(
              imageUrl: _imageUrl!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _imageUrl = null;
                  });
                },
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'Toca para agregar imagen',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '(Opcional)',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Interactive Category Tree Picker Dialog
class _CategoryTreePicker extends StatefulWidget {
  final CategoryService categoryService;
  final Category? currentSelection;
  final String? excludeId; // Prevent circular reference when editing

  const _CategoryTreePicker({
    required this.categoryService,
    this.currentSelection,
    this.excludeId,
  });

  @override
  State<_CategoryTreePicker> createState() => _CategoryTreePickerState();
}

class _CategoryTreePickerState extends State<_CategoryTreePicker> {
  Category? _selectedCategory;
  final Set<String> _expandedCategories = {};
  bool _isLoading = true;
  List<Category> _rootCategories = [];
  final Map<String, List<Category>> _childrenCache = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  List<Category> _allCategories = []; // For search

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.currentSelection;
    _loadRootCategories();
    _loadAllCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRootCategories() async {
    setState(() => _isLoading = true);
    try {
      final categories = await widget.categoryService.getRootCategories();
      setState(() {
        _rootCategories = categories.where((c) => c.id != widget.excludeId).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar categorías: $e')),
        );
      }
    }
  }

  Future<void> _loadAllCategories() async {
    try {
      final categories = await widget.categoryService.getCategories();
      setState(() {
        _allCategories = categories.where((c) => c.id != widget.excludeId).toList();
      });
    } catch (e) {
      // Silent fail, search just won't work
    }
  }

  Future<List<Category>> _loadChildren(String parentId) async {
    if (_childrenCache.containsKey(parentId)) {
      return _childrenCache[parentId]!;
    }
    
    final children = await widget.categoryService.getSubcategories(parentId);
    final filtered = children.where((c) => c.id != widget.excludeId).toList();
    _childrenCache[parentId] = filtered;
    return filtered;
  }

  void _toggleExpanded(String categoryId) {
    setState(() {
      if (_expandedCategories.contains(categoryId)) {
        _expandedCategories.remove(categoryId);
      } else {
        _expandedCategories.add(categoryId);
      }
    });
  }

  Widget _buildTreeView() {
    if (_rootCategories.isEmpty) {
      return const Center(
        child: Text(
          'No hay categorías disponibles',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    
    return ListView(
      children: _rootCategories.map((category) {
        return _buildCategoryTile(category, 0);
      }).toList(),
    );
  }

  Widget _buildSearchResults() {
    final filteredCategories = _allCategories.where((category) {
      return category.name.toLowerCase().contains(_searchTerm) ||
             category.fullPath.toLowerCase().contains(_searchTerm);
    }).toList();

    if (filteredCategories.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron categorías',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredCategories.length,
      itemBuilder: (context, index) {
        final category = filteredCategories[index];
        final isSelected = _selectedCategory?.id == category.id;
        
        return ListTile(
          leading: Icon(
            Icons.folder,
            color: isSelected ? Colors.blue : Colors.orange,
          ),
          title: Text(
            category.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue : null,
            ),
          ),
          subtitle: Text(
            category.fullPath,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          tileColor: isSelected ? Colors.blue.withOpacity(0.1) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
          onTap: () {
            setState(() => _selectedCategory = category);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.folder_open, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Seleccionar Categoría Padre',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            
            // Current selection breadcrumb
            if (_selectedCategory != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Seleccionado: ${_selectedCategory!.fullPath}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar categoría...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchTerm.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchTerm = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (value) {
                  setState(() => _searchTerm = value.toLowerCase());
                },
              ),
            ),

            // Root option
            ListTile(
              leading: Icon(
                Icons.home,
                color: _selectedCategory == null ? Colors.blue : Colors.grey,
              ),
              title: Text(
                'Categoría Raíz (sin padre)',
                style: TextStyle(
                  fontWeight: _selectedCategory == null ? FontWeight.bold : FontWeight.normal,
                  color: _selectedCategory == null ? Colors.blue : null,
                ),
              ),
              tileColor: _selectedCategory == null ? Colors.blue.withOpacity(0.1) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: _selectedCategory == null ? Colors.blue : Colors.transparent,
                  width: 2,
                ),
              ),
              onTap: () {
                setState(() => _selectedCategory = null);
              },
            ),
            const SizedBox(height: 8),
            const Divider(),
            
            // Tree view or search results
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchTerm.isNotEmpty
                      ? _buildSearchResults()
                      : _buildTreeView(),
            ),
            
            const Divider(),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(_selectedCategory);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Seleccionar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(Category category, int depth) {
    final isExpanded = _expandedCategories.contains(category.id);
    final isSelected = _selectedCategory?.id == category.id;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + (depth * 24.0)),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Expand/collapse button
              FutureBuilder<List<Category>>(
                future: _loadChildren(category.id!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      width: 24,
                      height: 24,
                      child: Padding(
                        padding: EdgeInsets.all(4.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  
                  final hasChildren = snapshot.hasData && snapshot.data!.isNotEmpty;
                  
                  if (!hasChildren) {
                    return const SizedBox(width: 24); // Empty space for alignment
                  }
                  
                  return IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _toggleExpanded(category.id!),
                  );
                },
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.folder,
                color: isSelected ? Colors.blue : Colors.orange,
              ),
            ],
          ),
          title: Text(
            category.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue : null,
            ),
          ),
          tileColor: isSelected ? Colors.blue.withOpacity(0.1) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
          onTap: () {
            setState(() => _selectedCategory = category);
          },
        ),
        
        // Children (if expanded)
        if (isExpanded)
          FutureBuilder<List<Category>>(
            future: _loadChildren(category.id!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.only(left: 40.0 + (depth * 24.0)),
                  child: const LinearProgressIndicator(),
                );
              }
              
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              
              return Column(
                children: snapshot.data!.map((child) {
                  return _buildCategoryTile(child, depth + 1);
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}
