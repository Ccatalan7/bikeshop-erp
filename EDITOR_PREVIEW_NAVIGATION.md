# 🔄 Editor ↔ Preview Navigation

## ✨ Easy Back-and-Forth Navigation

You can now **seamlessly switch** between editing and previewing your website!

## 🎯 Navigation Flow

```
┌─────────────┐         ┌──────────────┐
│   Editor    │ ◄─────► │   Preview    │
│  (Edit)     │         │  (Live Site) │
└─────────────┘         └──────────────┘
```

## 📍 From Editor → Preview

### Option 1: Green "Vista Previa" Button (Top Right)
1. Look at the **top toolbar** in the editor
2. Find the **green button** labeled **"Vista Previa"** with eye icon 👁️
3. Click it
4. Opens the public store at `/tienda`

**Visual:**
```
┌─────────────────────────────────────────────┐
│  ⟲ ⟳  [Auto-save]  [Vista Previa 👁️]  [Guardar] │ ← Click here!
└─────────────────────────────────────────────┘
```

## 📍 From Preview → Editor

### New! "Editar Sitio" Floating Button (Bottom Right)
1. Look at the **bottom right** corner of the public store
2. You'll see **TWO floating buttons:**
   - 💬 WhatsApp (green)
   - ✏️ **Editar Sitio** (blue) ← **NEW!**
3. Click the **blue "Editar Sitio"** button
4. **Opens the Odoo-style editor directly** (full screen, no intermediate pages)

**Visual:**
```
┌─────────────────────────────────────────┐
│                                         │
│     Your Website Content                │
│                                         │
│                                         │
│                               ┌───────┐ │
│                               │ 💬    │ │ ← WhatsApp
│                               └───────┘ │
│                       ┌──────────────┐  │
│                       │ ✏️ Editar    │  │ ← Click here!
│                       │   Sitio      │  │
│                       └──────────────┘  │
└─────────────────────────────────────────┘
```

## 🔐 Security Features

### "Editar Sitio" Button Visibility
- ✅ **Shows:** When you're logged in (authenticated user)
- ❌ **Hidden:** For anonymous visitors to the public store
- 🎯 **Purpose:** Only admins/editors can access the editor

### How It Works
```dart
// Checks if user is logged in
final isLoggedIn = supabase.auth.currentUser != null;

// Only show button to logged-in users
if (isLoggedIn) {
  // Show "Editar Sitio" button
}
```

## 🎨 Button Styling

### Editor's "Vista Previa" Button
- **Color:** Green (`Colors.green.shade600`)
- **Icon:** Eye (👁️)
- **Label:** "Vista Previa"
- **Style:** Elevated button with white text

### Preview's "Editar Sitio" Button
- **Color:** Blue (`Colors.blue`)
- **Icon:** Edit (✏️)
- **Label:** "Editar Sitio"
- **Style:** Floating action button (extended)
- **Position:** Bottom right, next to WhatsApp button

## 📐 Button Positioning

### Spacing Logic
```
Right edge: 24px
WhatsApp button: 56px wide
Spacing: 24px
"Editar Sitio" button position: 24 + 56 + 24 = 104px from right
```

**Layout:**
```
┌───────────────────────────────────────┐
│                                       │
│                                       │
│                 [Editar Sitio] [💬]   │
│                    ↑          ↑       │
│                  104px       24px     │
│                 from right  from right│
└───────────────────────────────────────┘
```

## 🚀 User Workflow

### Typical Editing Session
1. **Start:** Dashboard → Website module → "Abrir Editor"
2. **Edit:** Make changes in the editor
3. **Preview:** Click green "Vista Previa" button
4. **Check:** Review changes on live preview
5. **Go Back:** Click blue "Editar Sitio" button
6. **Refine:** Make more edits
7. **Repeat:** Steps 3-6 as needed
8. **Save:** Click "Guardar" when satisfied

### Speed
- ⚡ **Editor → Preview:** 1 click, instant
- ⚡ **Preview → Editor:** 1 click, instant
- 🎯 **Total:** Seamless back-and-forth!

## 🎯 Benefits

### Before (Manual Navigation)
```
Editor → Preview: Click "Vista Previa" ✅
Preview → Editor: Navigate to /website → Find editor → Click "Abrir Editor" ❌ (3 steps!)
```

### After (Automated Navigation)
```
Editor → Preview: Click "Vista Previa" ✅
Preview → Editor: Click "Editar Sitio" ✅ (1 click!)
```

**Result:** 67% faster! 🚀

## 🔧 Technical Implementation

### Files Modified

1. **`lib/public_store/widgets/public_store_layout.dart`**
   - Added Supabase import
   - Added auth check: `supabase.auth.currentUser != null`
   - Added conditional "Editar Sitio" button in Stack

2. **`lib/modules/website/pages/odoo_style_editor_page.dart`**
   - Changed "Vista Previa" from TextButton → ElevatedButton
   - Added green background color
   - Made it more prominent

### Code Snippet (Public Store)
```dart
// Check if user is logged in
final supabase = Supabase.instance.client;
final isLoggedIn = supabase.auth.currentUser != null;

// Add floating button (only for logged-in users)
if (isLoggedIn)
  Positioned(
    bottom: 24,
    right: 104,
    child: FloatingActionButton.extended(
      onPressed: () {
        // Navigate directly to the editor
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const OdooStyleEditorPage(),
          ),
        );
      },
      backgroundColor: Colors.blue,
      icon: const Icon(Icons.edit, color: Colors.white),
      label: const Text('Editar Sitio'),
    ),
  ),
```

### Code Snippet (Editor)
```dart
// Preview button - Now more prominent
ElevatedButton.icon(
  onPressed: () => context.go('/tienda'),
  icon: const Icon(Icons.visibility),
  label: const Text('Vista Previa'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.green.shade600,
    foregroundColor: Colors.white,
  ),
),
```

## 📱 Mobile/Tablet Considerations

### Desktop
- Both buttons visible
- Positioned in corners
- Clear spacing

### Mobile
- Buttons may overlap on small screens
- Consider: Collapse to single "Edit" icon on mobile
- Future enhancement: Responsive button sizing

## 🎨 Visual Identity

### Color Coding
- **Green (Vista Previa):** "Go see it" - positive action
- **Blue (Editar Sitio):** "Edit it" - primary action
- **Orange (Guardar):** "Save changes" - important action

### Icon Semantics
- 👁️ **Visibility:** Preview/view
- ✏️ **Edit:** Editor/modify
- 💾 **Save:** Persist changes

## 🔜 Future Enhancements

### Potential Improvements
1. 🔄 **Context Preservation:** Return to same block you were editing
2. 📍 **Scroll Position:** Remember where you were in preview
3. ⌨️ **Keyboard Shortcut:** Ctrl+P for preview, Ctrl+E for edit
4. 📱 **Mobile Optimization:** Smaller buttons on small screens
5. 🎯 **Preview Mode:** Open preview in new tab vs same tab option
6. 💬 **Quick Feedback:** "Show me what changed" highlight
7. ⏱️ **Auto-refresh:** Preview updates as you type

## ✅ Testing Checklist

- [ ] Click "Vista Previa" from editor
- [ ] Verify public store opens at `/tienda`
- [ ] Verify "Editar Sitio" button is visible (when logged in)
- [ ] Click "Editar Sitio" button
- [ ] Verify editor opens at `/website`
- [ ] Repeat cycle 5 times
- [ ] Verify no navigation errors
- [ ] Test with logged out user (button should be hidden)
- [ ] Test button positioning on different screen sizes
- [ ] Verify buttons don't overlap

## 🎉 Result

**You now have seamless editor ↔ preview navigation!**

No more manual navigation. Just click and go! 🚀

---

*"The best interface lets you focus on your work, not on navigation."*

**Enjoy your improved workflow!** ✨
