# 🎨 GUI DESIGN PRINCIPLES - VINABIKE ERP

**Philosophy:** Professional, minimalist, data-dense interfaces that prioritize functionality over decoration, with a restrained premium/performance edge expressed through discipline rather than color noise.

---

## 🎯 Core Design Principles

### 1. **Minimalism Over Decoration**
- ❌ **AVOID:** Excessive colors, gradients, shadows, or decorative elements
- ❌ **AVOID:** Rainbow color palettes and "AI/startup circus" aesthetics
- ❌ **AVOID:** Unnecessary icons cluttering every action
- ❌ **AVOID:** Painting whole screens in bright blue/green by default just to force a "modern" look
- ✅ **USE:** Clean whites, off-whites, charcoal/slate neutrals, and one restrained accent chosen deliberately for the context
- ✅ **USE:** Strategic icon placement (only where they add clarity)
- ✅ **USE:** Generous whitespace and clear visual hierarchy
- ✅ **USE:** Typography, contrast, spacing rhythm, and material restraint to create a premium technical feel

**Example:**
```dart
// ❌ WRONG: Excessive decoration
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
    boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text('Invoice', style: TextStyle(color: Colors.white, fontSize: 24)),
)

// ✅ CORRECT: Clean and minimal
Text(
  'Invoice',
  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
)
```

---

### 2. **Data Density & Space Optimization**
- ✅ Maximize visible data without scrolling
- ✅ Use compact spacing (8-16px padding, not 24-32px)
- ✅ Tables should show 10-15 rows on desktop without scrolling
- ✅ Forms should group related fields efficiently
- ❌ Avoid wasting space with oversized headers or empty areas

**Spacing Standards:**
- Card padding: `12-16px`
- List item spacing: `8-12px`
- Section gaps: `16-24px`
- Page margins: `16px` (mobile), `24px` (desktop)

---

### 3. **Typography & Readability**
- **Body text:** 14px (default)
- **Labels:** 12-13px (slightly smaller, medium weight)
- **Headers:** 18-24px (bold)
- **Table cells:** 13-14px
- **Monospace:** Use for codes, SKUs, invoice numbers

**Font weights:**
- Normal: `FontWeight.w400`
- Medium: `FontWeight.w500` (labels, secondary headings)
- Bold: `FontWeight.w600` or `w700` (primary headings)

---

### 4. **Color Strategy**

#### Primary Palette (Neutral-First)
```dart
// Neutral base
Colors.white         // Backgrounds
Colors.grey[50]      // Subtle backgrounds
Colors.grey[200]     // Borders
Colors.grey[600]     // Secondary text
Colors.grey[900]     // Primary text

// Deliberate accent
// Choose one restrained accent for the experience if truly needed.
// Follow the established module/brand palette outside the requested surface.

// Semantic colors (use sparingly)
Colors.green[700]    // Success, confirmations
Colors.red[700]      // Errors, destructive actions
Colors.orange[700]   // Warnings
Colors.amber[800]    // Secondary caution states
```

#### Status Badge Colors
- Draft: `Colors.grey` (neutral)
- Informational / in progress: neutral or restrained accent with label/icon support
- Paid/Complete: `Colors.green` (success)
- Overdue/Error: `Colors.red` (urgent)
- Cancelled: `Colors.orange` (warning)

**Usage Rules:**
- ❌ Don't use more than 2-3 colors per screen
- ❌ Don't use color as the only indicator (add icons/text)
- ❌ Don't build dashboards from rows of saturated KPI cards unless the color carries real operational meaning
- ❌ Don't use bright green and bright blue as the app's generic personality layer
- ❌ A localized redesign must never replace the global app theme, host-page
  palette, navigation styling, list styling, or unrelated status treatments.
- ✅ Sobriety does not mean monochrome. Use a restrained accent, warm/cool
  surface variation, and semantic color to create hierarchy and identity.
- ✅ Preserve the established module/brand palette outside the exact surface
  the user requested to change.
- ✅ Use color to reinforce meaning, not create it
- ✅ Prefer neutral surfaces with small semantic markers over full-surface color fills

#### KPI & Summary Surfaces
- ✅ Prefer concise summaries, tabular metrics, and restrained section headers over colorful scorecard grids
- ✅ If a KPI card is truly needed, keep the card surface neutral and let status color live in a border, icon, label, or small highlight
- ❌ Avoid "dashboard candy": multicolor stat cards, oversized badges, glowing trend chips, and decorative gradients with little informational value
- ✅ Restrained color families and subtle tonal surfaces are appropriate when
  they create hierarchy; removing all color is not a substitute for design.

---

### 5. **Tables - Clean & Professional**

#### Standard Table Design
```dart
// Compact, borderless table with subtle dividers
DataTable(
  horizontalMargin: 16,
  columnSpacing: 24,
  headingRowHeight: 40,
  dataRowHeight: 48,
  decoration: BoxDecoration(
    border: Border(
      top: BorderSide(color: Colors.grey[200]!),
      bottom: BorderSide(color: Colors.grey[200]!),
    ),
  ),
  columns: [
    DataColumn(
      label: Text(
        'Invoice #',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[700],
        ),
      ),
    ),
    // ...
  ],
  rows: [
    DataRow(
      cells: [
        DataCell(Text('INV-001', style: TextStyle(fontSize: 14))),
        // ...
      ],
    ),
  ],
)
```

#### Table Best Practices
- ✅ Use subtle borders (`Colors.grey[200]`) for row separation
- ✅ Align numbers to the right, text to the left
- ✅ Make headers slightly smaller and bold (13px, w600)
- ✅ Use monospace font for codes/numbers
- ✅ Add hover effect on rows (subtle gray background)
- ❌ Avoid heavy borders or alternating row colors
- ❌ Don't use icons in every cell (only for actions)

#### Column Width Guidelines
- **Checkbox:** 48px
- **Index/Row #:** 40-60px
- **Status badge:** 100-120px
- **Codes (SKU, Invoice #):** 120-150px
- **Names/Descriptions:** Flexible (min 200px)
- **Numbers (qty, price):** 100-130px
- **Dates:** 100-120px
- **Actions:** 48-80px (icon buttons)

---

### 6. **Forms - Efficient & Scannable**

#### Layout Patterns
```dart
// Two-column form (desktop)
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      child: Column(
        children: [
          TextField(label: 'Customer'),
          SizedBox(height: 12),
          TextField(label: 'Invoice Number'),
        ],
      ),
    ),
    SizedBox(width: 24),
    Expanded(
      child: Column(
        children: [
          TextField(label: 'Date'),
          SizedBox(height: 12),
          TextField(label: 'Due Date'),
        ],
      ),
    ),
  ],
)
```

#### Form Best Practices
- ✅ Group related fields together
- ✅ Use consistent field heights (48-56px)
- ✅ Mark required fields with `*` (not color alone)
- ✅ Show validation errors below the field
- ✅ Use placeholder text sparingly (prefer labels)
- ✅ Design around the operator's decision, not the persistence model. Historical
  totals, derived balances and internal state buckets belong in secondary
  context unless the operator can act on them directly.
- ✅ Separate observation from disposition in exception workflows. First record
  what physically happened; then offer a distinct, optional step for the
  commercial, accounting or logistics resolution.
- ✅ Let unresolved exceptions remain explicit and discoverable. A user must be
  able to choose `Resolver después` without the UI inventing a credit, loss,
  return or future delivery.
- ❌ Avoid excessive helper text (keep it minimal)
- ❌ Don't use floating labels (use fixed labels above)
- ❌ Don't expose one editable table column per backend enum or quantity bucket
  when one calculated difference plus a reason selector expresses the task.

---

### 7. **Buttons & Actions**

#### Button Hierarchy
```dart
// Primary action (most important)
FilledButton(
  onPressed: () {},
  child: Text('Save Invoice'),
)

// Secondary action (common)
OutlinedButton(
  onPressed: () {},
  child: Text('Cancel'),
)

// Tertiary/Destructive action
TextButton(
  onPressed: () {},
  style: TextButton.styleFrom(foregroundColor: Colors.red),
  child: Text('Delete'),
)
```

#### Action Button Rules
- ✅ **1 primary action** per screen (filled button)
- ✅ **2-3 secondary actions** max (outlined/text buttons)
- ✅ Use icons ONLY when they add clarity
- ✅ Keep button text concise (1-2 words)
- ✅ Let hierarchy come from placement, weight, and contrast before it comes from saturated fills
- ❌ Don't use more than 1 filled button in the same context
- ❌ Don't add icons to every button (visual noise)
- ❌ Don't build "fun" button systems with mixed bright colors, oversized pills, or decorative gradients on ERP screens

#### Icon-Only Buttons
```dart
// Use for compact actions in tables/toolbars
IconButton(
  icon: Icon(Icons.edit_outlined, size: 20),
  onPressed: () {},
  tooltip: 'Edit', // Always provide tooltip!
)
```

---

### 8. **Split-Pane Layout (Selective Use)**

#### When to Use Split-Pane
✅ **USE for:**
- Master-detail views (list + detail)
- Document management (invoices, orders, quotes)
- Entity browsers (customers, products, suppliers)
- Workflows that benefit from context preservation

❌ **DON'T USE for:**
- Simple forms (create new entity)
- Dashboard widgets
- Settings pages
- Reports (full-width preferred)
- Mobile views (use navigation instead)

#### Implementation Pattern
```dart
Row(
  children: [
    // Left pane: List (resizable)
    AnimatedContainer(
      width: _listPaneWidth, // 400-800px
      child: ListView(...),
    ),
    
    // Divider (resize handle)
    GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() => _listPaneWidth += details.delta.dx);
      },
      child: Container(
        width: 1,
        color: Colors.grey[300],
      ),
    ),
    
    // Right pane: Detail (fills remaining space)
    Expanded(
      child: _selectedItem == null
        ? Center(child: Text('Select an item'))
        : DetailView(item: _selectedItem),
    ),
  ],
)
```

#### Split-Pane Best Practices
- ✅ Make left pane resizable (save width in SharedPreferences)
- ✅ Min width: 300px, max width: 50% of screen
- ✅ Show "Select an item" placeholder when nothing selected
- ✅ Highlight selected row in list
- ✅ Add keyboard navigation (arrow keys)
- ✅ Preserve the host while a document workflow is open: an action launched
  from a split detail replaces that detail pane inline, not the entire route.
- ✅ The same workflow launched from a routed form stays inside its existing
  `MainLayout`; it must not mount a nested top-level `Scaffold` or `AppBar`.
- ❌ Don't use split-pane on mobile (< 900px width)
- ❌ Don't make both panes scrollable independently (confusing)

---

### 9. **Status & Feedback**

#### Status Badges
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: statusColor.withOpacity(0.15),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    statusText,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: statusColor,
    ),
  ),
)
```

#### Snackbar Messages
```dart
// Success (green)
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Invoice saved successfully'),
    backgroundColor: Colors.green[700],
    duration: Duration(seconds: 2),
  ),
)

// Error (red)
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Failed to save invoice'),
    backgroundColor: Colors.red[700],
    duration: Duration(seconds: 4),
  ),
)
```

#### Loading States
- ✅ Use `CircularProgressIndicator` (default size: 24-32px)
- ✅ Disable buttons during async operations
- ✅ Show skeleton loaders for lists (shimmer effect)
- ❌ Don't block entire screen with loading overlay (unless necessary)

---

### 10. **Navigation & Workflow**

#### Breadcrumb Pattern
```dart
// Show context and hierarchy
Row(
  children: [
    TextButton(
      onPressed: () => context.go('/sales'),
      child: Text('Sales'),
    ),
    Icon(Icons.chevron_right, size: 16),
    Text('Invoices', style: TextStyle(fontWeight: FontWeight.w600)),
  ],
)
```

#### Action Bar Pattern (Invoice-style)
```dart
// Top action bar with status and buttons
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
  ),
  child: Row(
    children: [
      // Entity info
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoice INV-001', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Customer Name', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
      
      // Status badge
      StatusBadge(status: status),
      SizedBox(width: 16),
      
      // Actions (1-3 buttons max)
      OutlinedButton(onPressed: () {}, child: Text('Edit')),
      SizedBox(width: 8),
      FilledButton(onPressed: () {}, child: Text('Confirm')),
    ],
  ),
)
```

---

### 11. **Responsive Breakpoints**

```dart
// Define breakpoints
const double mobileBreakpoint = 600;
const double tabletBreakpoint = 900;
const double desktopBreakpoint = 1200;

// Responsive layout
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < mobileBreakpoint) {
      return MobileLayout();
    } else if (constraints.maxWidth < tabletBreakpoint) {
      return TabletLayout();
    } else {
      return DesktopLayout();
    }
  },
)
```

#### Responsive Rules
- **Mobile (<600px):** Single column, stacked forms, card-based lists
- **Tablet (600-900px):** Two columns, collapsible sidebar
- **Desktop (>900px):** Multi-column, split-pane, full tables

---

### 12. **Common Anti-Patterns to AVOID**

❌ **Rainbow Dashboards**
- Don't use 6+ colors on the same screen
- Don't use gradients or color transitions
- Don't color-code everything

❌ **Icon Overload**
- Don't add icons to every button/label
- Don't use decorative icons
- Don't use icons without labels (unless universally known)

❌ **Excessive Shadows/Depth**
- Don't use `elevation: 8` on every card
- Don't stack shadows (card in card in card)
- Use elevation sparingly (0-2 for most elements)

❌ **Wasted Space**
- Don't use 48px padding around everything
- Don't center-align everything (use left-align for data)
- Don't use giant headers that push content down

❌ **Inconsistent Spacing**
- Don't use random spacing values (8, 12, 15, 17, 20...)
- Stick to 4px increments: 8, 12, 16, 24, 32

---

## 📋 Module-by-Module Application Guide

### When to Use Split-Pane Layout

#### ✅ **RECOMMENDED FOR:**
1. **Sales Module**
   - Invoices list + detail view
   - Quotes list + detail view
   - Payments history + detail

2. **Purchases Module**
   - Purchase orders + detail
   - Supplier invoices + detail

3. **Inventory Module**
   - Products list + detail/edit
   - Stock movements + filter/detail

4. **CRM Module**
   - Customers list + profile view
   - Suppliers list + profile view

5. **Bikeshop (Trabajos) Module**
   - Jobs list + detail/timeline
   - Client logbook + bike history

6. **HR Module**
   - Employees list + profile
   - Attendance logs + detail

#### ❌ **NOT RECOMMENDED FOR:**
1. **Accounting Module**
   - Journal entries (prefer full-width table)
   - Chart of accounts (tree view)
   - Reports (need full width)

2. **Analytics/Dashboard**
   - Dashboards (widgets need full space)
   - Reports (charts need full width)

3. **Settings Module**
   - Configuration forms (simple forms)
   - User management (simple tables)

4. **POS Module**
   - Point of sale (needs full screen)

### When to Use Full-Width Layout

#### ✅ **USE FOR:**
- Dashboards with multiple widgets
- Wide tables with many columns (>8 columns)
- Forms with complex layouts
- Reports with charts/graphs
- Standalone high-throughput data entry screens (for example POS). A workflow
  launched from an existing master/detail document keeps that host and context,
  even when the inner table is horizontally scrollable.

---

## 🎯 Quick Checklist for New Modules

Before implementing ANY new module UI:

- [ ] Color palette limited to 2-3 colors maximum
- [ ] Tables use subtle borders, no alternating colors
- [ ] Buttons follow hierarchy (1 primary, 2-3 secondary)
- [ ] Spacing uses 4px increments (8, 12, 16, 24)
- [ ] Icons used strategically (not everywhere)
- [ ] Status badges use semantic colors only
- [ ] Forms are scannable (clear labels, grouped fields)
- [ ] Typography follows size/weight standards
- [ ] Responsive breakpoints implemented
- [ ] Split-pane only if module fits use case
- [ ] No loud decorative gradients or heavy shadows; subtle localized tonal
      depth is allowed when it improves hierarchy
- [ ] Data density optimized (10-15 rows visible)

---

## 🔍 Examples: Before & After

### ❌ BEFORE: Cluttered Dashboard
```dart
// Excessive colors, shadows, icons
Card(
  elevation: 8,
  color: Colors.blue[100],
  child: ListTile(
    leading: CircleAvatar(
      backgroundColor: Colors.purple,
      child: Icon(Icons.attach_money, color: Colors.yellow),
    ),
    title: Text('Total Sales', style: TextStyle(color: Colors.blue[900])),
    subtitle: Text('\$45,000', style: TextStyle(fontSize: 24, color: Colors.green)),
    trailing: Icon(Icons.trending_up, color: Colors.orange, size: 32),
  ),
)
```

### ✅ AFTER: Clean Dashboard
```dart
// Minimal, focused on data
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: Colors.grey[200]!),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Total Sales',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      SizedBox(height: 4),
      Text(
        '\$45,000',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
    ],
  ),
)
```

---

## 🚀 Migration Strategy

When redesigning existing modules:

1. **Audit current UI** - Screenshot and list issues
2. **Apply spacing standards** - Fix padding/margins first
3. **Simplify color usage** - Remove excessive colors
4. **Clean up tables** - Apply table design principles
5. **Standardize buttons** - Follow button hierarchy
6. **Add split-pane (if applicable)** - Only for list+detail modules
7. **Test responsiveness** - Verify mobile/tablet/desktop
8. **Remove decorations** - Strip gradients, heavy shadows, unnecessary icons

---

## 📚 Reference Implementation

**Primary Example:** `lib/modules/sales/pages/invoice_list_page.dart`
- Split-pane layout
- Clean table design
- Minimalist action bar
- Status badges
- Resizable panels

**Study These Patterns:**
- Two-row action bar (invoice number + buttons)
- Borderless button styling
- Compact spacing (4px vertical padding on buttons)
- Subtle dividers (1px gray borders)
- Professional status badges

---

**Remember:** Professional software looks BORING. That's the goal. Prioritize clarity, efficiency, and data density over visual flair.
