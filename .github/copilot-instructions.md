# 🧠 Project Overview

This is a modular ERP-style app for managing a bikeshop. It includes accounting, inventory, POS, customer management, maintenance tracking, HR, website builder, marketing, and analytics. The app is built in **Flutter/Dart**, targeting **Windows, Android, Web**, and optionally macOS/iOS.

The backend uses Supabase exclusively, with PostgreSQL as the relational database, Supabase Auth for authentication (including OAuth2 support like Google login), and Supabase Storage for file management. All business logic follows an accounting-first approach, with audit-ready data structures and strong relational integrity across modules.

---

# 🚨 CRITICAL RULE: ALWAYS USE CORE_SCHEMA.SQL

**⚠️ NEVER CREATE NEW SQL FILES!**

**ALL database changes MUST go into `supabase/sql/core_schema.sql`:**
- ✅ New tables → Add to `core_schema.sql`
- ✅ New functions → Add to `core_schema.sql`
- ✅ New triggers → Add to `core_schema.sql`
- ✅ Schema fixes → Fix in `core_schema.sql`
- ✅ Missing columns → Add to `core_schema.sql`
- ✅ Wrong constraints → Fix in `core_schema.sql`
- ❌ NEVER create `FIX_*.sql`, `DEPLOY_*.sql`, `add_*.sql`, etc.

**⚠️ CRITICAL: AVOID DUPLICATES!**

**BEFORE creating ANY database object, you MUST:**
1. 🔍 **SEARCH `core_schema.sql` for existing similar functions/triggers/tables**
2. ❌ **NEVER assume a function/trigger doesn't exist - ALWAYS verify first**
3. 🔄 **UPDATE existing functions rather than creating new ones with different names**
4. ⚠️ **Example of what NOT to do:**
   - ❌ Creating `handle_purchase_invoice_change()` when `handle_sales_invoice_change()` pattern already exists
   - ❌ Creating `create_purchase_journal_entry()` when similar function already exists
   - ❌ Creating new triggers without checking for existing trigger patterns
5. ✅ **Example of what TO do:**
   - ✅ Find existing `handle_sales_invoice_change()` function
   - ✅ Check how it works and what pattern it uses
   - ✅ Create `handle_purchase_invoice_change()` following the SAME pattern
   - ✅ Reuse existing helper functions like `ensure_account()`, `consume_inventory()`, etc.

**Common mistakes to AVOID:**
- ❌ Creating duplicate functions with slightly different names
- ❌ Creating new helper functions when similar ones exist
- ❌ Not checking existing trigger patterns before creating new ones
- ❌ Assuming tables/columns don't exist without checking
- ❌ Creating inconsistent naming (one module uses `handle_*_change`, another uses `process_*_update`)

**Before making any database changes:**
1. 🔍 **ALWAYS check `core_schema.sql` first**
2. 🔍 **SEARCH for existing functions/triggers with similar names or purposes**
3. 📖 Read the relevant section (tables, functions, triggers)
4. 🤔 **Ask: "Does something similar already exist?"**
5. ✏️ Make changes directly in `core_schema.sql`
6. 💾 Save and inform user to deploy the updated file

**This is the ONLY database schema file. Everything else has been deleted.**

---

# 🔧 COPILOT WORKFLOW CHECKLIST

**For ANY database-related task:**

1. ✅ **READ** `supabase/sql/core_schema.sql` first - ENTIRE file if needed
2. ✅ **SEARCH** for existing tables/functions/triggers with similar names or purposes
3. ✅ **CHECK** if similar patterns already exist (e.g., `handle_sales_invoice_change` → use same pattern for purchases)
4. ✅ **REUSE** existing helper functions (`ensure_account`, `consume_inventory`, etc.)
5. ✅ **UPDATE** existing code or add new code following EXISTING patterns
6. ✅ **NEVER** create duplicate functions/triggers with different names
7. ✅ **VERIFY** column names match what's in `core_schema.sql`
8. ✅ **INFORM** user to deploy updated `core_schema.sql`

**CRITICAL: Before creating ANY function/trigger:**
- 🔍 Search `core_schema.sql` for: `CREATE OR REPLACE FUNCTION public.[function_name]`
- 🔍 Search for similar patterns (e.g., if creating purchase trigger, look for sales trigger)
- 🔍 Check what helper functions exist (ensure_account, consume_inventory, etc.)
- ❌ NEVER create `create_purchase_invoice_journal_entry` if `create_sales_invoice_journal_entry` already exists - study the existing one first!

**For ANY Flutter code changes:**

1. ✅ Check if database schema needs updating first
2. ✅ **READ `core_schema.sql`** to verify table/column names
3. ✅ Adapt Flutter code to match database schema (not vice versa)
4. ✅ Use correct column names from `core_schema.sql`
5. ✅ Test compilation before marking complete

**For ANY new feature:**

1. ✅ **Database schema first (in `core_schema.sql`)**
   - Check what tables/functions/triggers already exist
   - Follow existing patterns and naming conventions
   - Reuse existing helper functions
2. ✅ Backend triggers/functions (in `core_schema.sql`)
   - Search for similar triggers/functions first
   - Use same pattern as existing code
3. ✅ Flutter models and services
4. ✅ UI implementation
5. ✅ Navigation integration (add to main menu)

**REMEMBER:**
- 🚫 No new SQL files
- 🚫 No duplicate functions/triggers (search first!)
- 🚫 No markdown guides for simple tasks
- 🚫 No assumptions about schema - always check first
- 🚫 No creating new patterns when existing patterns work
- ✅ Always search for existing similar code
- ✅ Always follow existing naming conventions
- ✅ Always reuse existing helper functions
- ✅ Always verify changes compile before finishing

---

# 🧱 Modular Architecture

Each module is independent but shares a unified data layer. Modules include:

- **Sales**: Invoices, payments, discounts
- **Purchases**: Purchase orders, supplier credits, receipts
- **Inventory**: Products, stock movements, warehouses
- **Maintenance**: Work orders, parts used, labor cost
- **CRM**: Customer profiles, bike history, loyalty
- **Accounting**: Chart of accounts, journal entries, tax rules
- **HR (RRHH)**: Employees, contracts, attendance, payroll, planning
- **Website Builder**: Product catalog, online orders, CMS
- **Marketing**: Campaigns, email/SMS, customer segmentation
- **Analytics**: Dashboards, KPIs, sales trends, inventory turnover
- **Settings**: Company info, currency, theme, language, timezone

---

# 🔗 Integration Logic

- Online orders from Website Builder deduct inventory and generate invoices
- Marketing campaigns use CRM data and feed into Analytics
- POS, Website, and Maintenance all sync with Inventory and Accounting
- HR data (attendance, payroll) flows into Accounting
- Analytics pulls from all modules for unified dashboards

---

# 🧮 Database Schema (PostgreSQL)

Use normalized tables with foreign keys and constraints. Example:

`sql
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name TEXT,
  sku TEXT UNIQUE,
  price NUMERIC,
  cost NUMERIC,
  inventory_qty INTEGER
);

CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER REFERENCES customers(id),
  source TEXT CHECK (source IN ('POS', 'Website')),
  date TIMESTAMP,
  total NUMERIC
);

CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER REFERENCES orders(id),
  product_id INTEGER REFERENCES products(id),
  quantity INTEGER,
  price NUMERIC
);
`

Use triggers or service logic to update inventory and accounting entries.

---

# 🔐 Authentication

Use Supabase Auth with OAuth2 (Google, GitHub, etc.) for secure login. Supports:

- Email/password
- Social login
- Role-based access control via Row Level Security (RLS)
- Token expiration and automatic refresh
- Seamless integration with PostgreSQL user tables

---

# 🧭 Navigation Design Rules

- Use minimalistic menu structure with one entry per module
- Avoid redundant submenus like “New Purchase Invoice”
- Use in-page navigation for actions (e.g., “+ New Invoice” button)
- Maintain consistent drawer/sidebar layout across all modules
- Use local routing (Navigator.push, GoRouter) for transitions
- Role-based menu visibility (admin, cashier, mechanic, accountant)

---

## 🔗 Module Integration Rules
- Every new module must:
  - Be imported into `main.dart` (or the central navigation file).
  - Add its main ListPage (e.g., CustomerListPage, InventoryListPage) to the sidebar/drawer.
  - Add a dashboard shortcut if relevant (e.g., “Clientes”, “Inventario”).
  - Ensure navigation works end-to-end: Dashboard → Module → Detail/Form pages.
- No module is considered “done” until it is visible and accessible from the main navigation.


---

# 🎨 GUI Design System

Use a unified widget set across all screens:

- Buttons: consistent style (primary, secondary, danger)
- Forms: reusable components with validation
- Lists: paginated, searchable, filterable
- Modals: consistent layout and behavior
- Icons: use Material Icons or custom SVGs

Support:

- Dark mode toggle (global)
- Language selector (i18n)
- Time zone sync (auto-detect or manual)

---

# 🌍 Localization & Regional Context

App is primarily used in Chile

- Currency: CLP (Chilean Peso)
- Tax: IVA (19%), applied to invoices and purchases
- Language: Spanish (default), English (optional)
- Date format: DD/MM/YYYY
- Time zone: America/Santiago

---

# 👥 HR & Workforce Management (RRHH)

Include the following modules:

- Employees: personal data, job title, department
- Contracts: salary, working hours, legal terms
- Attendance: clock-in/out, calendar view, kiosk mode
- Payroll: salary computation, tax, payment status
- Planning: shift scheduling, technician availability
- Leaves: vacation, sick leave, approval workflows
- Timesheets: logged hours per task/project
- Roles & Permissions: access control per module

---

# 🌐 Website Builder

- Product catalog with images, descriptions, prices
- Online orders sync with Inventory and Accounting
- CMS for homepage, blog, promotions
- Customer login and order history
- Payment gateway integration (free-tier or mock)

---

# 📣 Marketing Module

- Campaign builder (email, SMS, push)
- Customer segmentation based on CRM data
- Promotion rules (discounts, bundles)
- Scheduled and triggered campaigns
- Integration with Analytics for performance tracking

---

# 📊 Analytics Dashboard

- Sales by product/category/date
- Inventory turnover and valuation
- Customer lifetime value
- Maintenance cost breakdown
- HR metrics (attendance, payroll trends)
- Campaign performance (open rate, conversion)

---

# 📦 Suggested Folder Structure

`plaintext
lib/
├── modules/
│   ├── sales/
│   ├── purchases/
│   ├── inventory/
│   ├── maintenance/
│   ├── accounting/
│   ├── crm/
│   ├── hr/
│   ├── website/
│   ├── marketing/
│   ├── analytics/
│   └── settings/
├── shared/
│   ├── models/
│   ├── services/
│   ├── widgets/
│   └── themes/
`

Each module:

- Has its own routes (GoRouter)
- Uses shared models (e.g. Product, Order, Customer, Employee)
- Follows the same UI design system

---

# 🧠 Copilot Expectations

Copilot must:

- Maintain consistent naming across modules
- Reuse shared models and widgets
- Respect business rules (e.g. inventory deduction, tax calculation)
- Avoid GUI fragmentation (no random button styles)
- Handle dark mode, language, and time zone globally
- Generate audit-ready accounting logic
- Use PostgreSQL syntax and constraints
- Avoid hardcoded values—use config or constants
- Use modular architecture with clean separation of concerns

---

# 🖼️ Image Handling Rules

- All modules that involve products, customers, employees, or marketing must support images.
- Use a unified image service (`ImageService`) in `lib/shared/services/` for:
  - Uploading images (to Supabase storage or Firebase storage).
  - Fetching images with caching (use `CachedNetworkImage`).
  - Handling placeholders (default icon if no image).
  - Handling errors (broken link → fallback image).
- Store only the image URL/path in the database, not the binary.
- Organize assets in `assets/images/` for static icons, logos, and placeholders.
- For product images:
  - Support multiple images per product.
  - Use thumbnails in lists, full-size in detail pages.
- For employee/customer profile pictures:
  - Circular avatar style, consistent sizing.
- For marketing/website:
  - Support banners and campaign images with responsive scaling.
- Always optimize for performance:
  - Use lazy loading for lists.
  - Use compressed formats (WebP/optimized JPEG).
- Respect dark mode (ensure images/icons adapt or remain visible).

---

# 🔍 Search & Filtering Rules

- Any list or dropdown with more than ~10 possible items must include a search bar at the top.
- Examples:
  - Chart of Accounts → searchable by code and name.
  - Customer/Supplier selection → searchable by name, RUT, or email.
  - Product selection → searchable by SKU, name, or category.
- Use a consistent search widget across modules:
  - TextField with prefix search icon.
  - Real-time filtering as the user types.
  - Case-insensitive matching.
- For very large datasets (100+ items), implement pagination or lazy loading with search.
- Always place the search bar **above the list** (not hidden in a menu).
- Respect localization: search must work with Spanish characters (ñ, á, é, í, ó, ú).