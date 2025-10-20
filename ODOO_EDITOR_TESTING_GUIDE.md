# 🧪 ODOO-STYLE EDITOR - TESTING GUIDE

## 🎯 How to Test the New Editor

### Step 1: Navigate to the Editor
1. Open the app at `http://localhost:52010`
2. Login (if not already logged in)
3. Go to **Dashboard**
4. Click on **"Website"** in the sidebar
5. Look for the **featured card** with the editor icon
6. Click **"Abrir Editor"** button

### Step 2: Test Click-to-Edit
1. You should see:
   - **LEFT:** Live preview with blocks
   - **RIGHT:** 3-tab panel (Agregar | Editar | Tema)
2. Click on the **Hero block** in the preview
3. Verify:
   - ✅ Blue border appears around hero block
   - ✅ Shadow/glow effect visible
   - ✅ Block label shows "Hero / Banner"
   - ✅ Floating toolbar shows (⬆️ ⬇️ 📋 🗑️)
   - ✅ Right panel automatically switches to "Editar" tab
   - ✅ Edit controls for hero appear

### Step 3: Edit Content
1. With hero block selected, edit:
   - Change the **title** text
   - Change the **subtitle** text
   - Change the **button text**
2. Watch the preview update **in real-time**
3. Toggle **"Mostrar Overlay"** switch
4. Adjust **"Opacidad del Overlay"** slider
5. Verify changes are instant

### Step 4: Test Block Selection
1. Click the **Products block** (second block)
2. Verify:
   - ✅ Hero loses blue border
   - ✅ Products gets blue border
   - ✅ Edit panel shows products controls
   - ✅ Can change "Items per Row" slider
   - ✅ Can change layout dropdown
3. Click the **Services block** (third block)
4. Verify selection switches again

### Step 5: Test Block Actions
1. Select the **About block** (fourth block)
2. Click **⬆️** (Move Up) in floating toolbar
3. Verify about block moves above services
4. Click **⬇️** (Move Down) twice
5. Verify about block returns to bottom
6. Click **📋** (Duplicate)
7. Verify a copy appears below
8. Click **🗑️** (Delete) on the duplicate
9. Confirm deletion in dialog

### Step 6: Test Add Blocks (Agregar Tab)
1. Click **"➕ Agregar"** tab at top of right panel
2. Verify you see:
   - List of 9 block templates
   - Each with icon, name, description, "Añadir" button
3. Click **"Añadir"** on **"Testimonios"**
4. Verify:
   - New block appears at bottom of preview
   - Block is auto-selected (blue border)
   - Panel switches to "Editar" tab
   - Shows testimonials edit controls

### Step 7: Test Global Theme (Tema Tab)
1. Click **"🎨 Tema"** tab
2. Click the **"Color Primario"** color picker
3. Change color (use color wheel)
4. Click "APLICAR"
5. Verify all blocks update with new primary color
6. Test other theme settings:
   - Accent color
   - Background color
   - Text color
   - Heading font (dropdown)
   - Body font (dropdown)
   - Heading size (slider)
   - Body size (slider)
   - Section spacing (slider)
   - Container padding (slider)
7. Watch preview update in real-time

### Step 8: Test Undo/Redo
1. Make several changes (edit titles, move blocks, etc.)
2. Click **⟲ (Undo)** button in toolbar
3. Verify changes revert one by one
4. Click **⟳ (Redo)** button
5. Verify changes come back

### Step 9: Test Responsive Preview
1. Look at toolbar above preview
2. Click **"Tablet"** device button
3. Verify preview resizes to tablet width
4. Click **"Móvil"** device button
5. Verify preview resizes to mobile width
6. Click **"Desktop"** device button
7. Verify preview returns to full width

### Step 10: Test Zoom Controls
1. Click **zoom out (-)** button
2. Verify preview scales down
3. Check percentage label updates (e.g., "90%")
4. Click **zoom in (+)** button multiple times
5. Verify preview scales up
6. Check percentage label updates (e.g., "110%", "120%")

### Step 11: Test Auto-Save
1. Make a change (edit a title)
2. Notice **"Sin guardar"** badge appears in toolbar
3. Wait **30 seconds** (or toggle auto-save OFF then ON)
4. Verify **"Auto-guardado ✓"** badge appears
5. Check console for save confirmation (if developer tools open)

### Step 12: Test Manual Save
1. Make a change
2. Verify **"Guardar"** button becomes enabled (blue)
3. Click **"Guardar"** button
4. Verify:
   - Button shows "Guardando..."
   - Loading spinner appears briefly
   - Success snackbar appears: "✅ Cambios guardados exitosamente"
   - "Sin guardar" badge disappears

### Step 13: Test Unsaved Changes Dialog
1. Make a change (don't save)
2. Verify "Sin guardar" badge visible
3. Click **back arrow** (←) in top left
4. Verify dialog appears:
   - Title: "⚠️ Cambios sin Guardar"
   - Message: "Tienes cambios sin guardar..."
   - Buttons: "Descartar", "Cancelar", "Guardar y Salir"
5. Click **"Cancelar"** → stays in editor
6. Click **back arrow** again
7. Click **"Guardar y Salir"** → saves and exits

### Step 14: Test Image Upload (Placeholder)
1. Select **Hero block**
2. Click **"Cambiar Imagen de Fondo"** button
3. Verify file picker opens
4. Select an image
5. Verify snackbar: "📷 Imagen seleccionada. Implementar subida a Supabase."
   *(Note: This is a TODO for Supabase integration)*

### Step 15: Test Block Duplication
1. Select **Products block**
2. Click **📋 (Duplicate)** in floating toolbar
3. Verify:
   - Copy appears immediately below original
   - Copy is auto-selected
   - Both blocks have identical content
   - Can edit copy independently

### Step 16: Test Block Visibility
1. Count total blocks in preview (should be 4-6 depending on adds/deletes)
2. All blocks should be visible by default
3. Click between different blocks
4. Verify selection always works

### Step 17: Test Preview Accuracy
1. Edit the **Hero title** to "TEST TITLE"
2. Verify preview shows "TEST TITLE" immediately
3. Change **Primary color** to red
4. Verify all primary-colored elements turn red
5. Compare preview to actual website (/tienda)
   - Should look very similar (preview may lack real products/data)

### Step 18: Test Performance
1. Add **10 blocks** (any types)
2. Verify:
   - Preview renders smoothly
   - No lag when clicking blocks
   - Scrolling is smooth
   - Selection is instant
3. Undo all additions
4. Verify history works even with many actions

### Step 19: Test Edge Cases
1. **Empty state:** Delete all blocks except one
   - Verify you can't delete the last block (or editor shows "Add a block")
2. **Many blocks:** Add 20+ blocks
   - Verify scrolling works
   - Selection still works
3. **Rapid clicking:** Click blocks very quickly
   - Verify selection keeps up
   - No visual glitches

### Step 20: Test Mobile View
1. Switch to **Móvil** preview mode
2. Verify:
   - Blocks stack vertically
   - Text is readable
   - Images fit
   - Buttons are clickable
3. Edit content in mobile view
4. Switch back to desktop
5. Verify changes persist

## ✅ Expected Results

After completing all tests, you should verify:

### Visual Feedback
- ✅ Blue borders on selected blocks
- ✅ Shadow/glow effect on selection
- ✅ Floating toolbar with 4 action buttons
- ✅ Block label showing block type
- ✅ Smooth animations (borders, containers)

### Functionality
- ✅ Click-to-select works on all blocks
- ✅ Edit panel changes based on selection
- ✅ All 3 tabs work (Agregar, Editar, Tema)
- ✅ Block actions work (move, duplicate, delete)
- ✅ Undo/Redo with 50-step history
- ✅ Auto-save every 30 seconds
- ✅ Manual save button
- ✅ Unsaved changes dialog
- ✅ Responsive preview (mobile/tablet/desktop)
- ✅ Zoom controls (50%-200%)
- ✅ Real-time preview updates
- ✅ Color picker works
- ✅ Image upload picker opens

### Performance
- ✅ No lag or stuttering
- ✅ Instant selection feedback
- ✅ Smooth scrolling
- ✅ Fast tab switching
- ✅ Handles 20+ blocks easily

### UX
- ✅ Intuitive (no documentation needed)
- ✅ Visual-first (click what you see)
- ✅ Context-aware controls
- ✅ Clear feedback (badges, snackbars)
- ✅ Professional feel

## 🐛 Known Issues / TODOs

### Currently Placeholder
1. **Image Upload**: Opens file picker but doesn't upload to Supabase yet
   - **Status:** Shows notification "Implementar subida a Supabase"
   - **Next:** Integrate with Supabase Storage

2. **Database Save**: Simulates save with 1-second delay
   - **Status:** Shows success notification but doesn't persist
   - **Next:** Save blocks to `website_blocks` table

3. **Block Types 5-9**: Have basic preview but limited edit controls
   - Testimonials
   - Features
   - CTA
   - Gallery
   - Contact
   - **Next:** Build full edit controls for each

### Future Enhancements
1. **Drag & Drop Reordering**: Currently uses ⬆️⬇️ buttons
2. **Block Visibility Toggle**: Show/hide without deleting
3. **Block Search/Filter**: Find blocks by name
4. **Keyboard Shortcuts**: Ctrl+Z, Ctrl+C, Ctrl+V
5. **Block Templates**: Save/load custom configs
6. **Version History**: Restore previous saves

## 📊 Testing Checklist

Print this and check off as you test:

```
□ Navigate to editor
□ Click-to-edit works
□ Blue border selection
□ Floating toolbar visible
□ Agregar tab shows templates
□ Add new block works
□ Editar tab adapts to block
□ Edit controls work
□ Tema tab shows global settings
□ Theme changes apply globally
□ Move block up/down works
□ Duplicate block works
□ Delete block works
□ Undo/Redo works
□ Auto-save triggers
□ Manual save works
□ Unsaved changes dialog
□ Responsive preview modes
□ Zoom controls work
□ Image picker opens
□ Performance is smooth
□ No console errors
```

## 🎯 Success Criteria

**The editor PASSES if:**
- ✅ All 20 test steps complete without errors
- ✅ UI is responsive and smooth
- ✅ No console errors
- ✅ Feels intuitive and professional
- ✅ User says "Wow, this is so much better!"

**The editor NEEDS WORK if:**
- ❌ Clicking blocks doesn't select them
- ❌ Edit panel doesn't update
- ❌ Preview doesn't match edits
- ❌ Lots of bugs or glitches
- ❌ User is confused how to use it

## 🚀 After Testing

If all tests pass:
1. ✅ Mark "Test complete Odoo-style editor flow" as DONE in todo list
2. 🎉 Celebrate! This is a HUGE achievement!
3. 📝 Document any bugs/issues found
4. 🔜 Move to deployment phase

If tests fail:
1. 📝 Document specific failures
2. 🐛 Fix bugs one by one
3. 🔄 Retest after fixes
4. ✅ Repeat until all tests pass

---

**Happy Testing!** 🧪✨
