# 🛠 Bikeshop Mechanic & Service Manager Module (Gestión de Taller y Clientes)

> [!WARNING]
> **Historical business context; not UI authority.** Preserve relevant workshop
> behavior and relationships only after reconciling them with the current
> workshop architecture. Every visual, layout, navigation, component, color,
> spacing, modal/dialog/snackbar, responsive, and platform recipe below is
> superseded by [`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md) and
> [`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> imitate a reference product, screenshot, or old local widget. Choose inline, in-block,
> pane, popover, sheet, blocking surface, or full route from the actual task;
> none is an automatic module-wide pattern.

## 🎯 Objective

Develop a complete **Bikeshop Mechanic & Service Manager module** integrated into the ERP system.  
The purpose of this module is to manage mechanical works, bike maintenance jobs, and client service histories — functioning as a mix between a **CRM** and a **mechanic workshop manager**.  
It must be tightly integrated with existing ERP modules (Clients, Inventory, Sales, Accounting, HR, Reports).

---

## ⚙️ Architecture Context
- **IDE:** Visual Studio Code  
- **Language:** Dart  
- **Framework:** Flutter  
- **Backend:** Supabase (PostgreSQL + Auth + Storage Bucket)  
- **Country/Language:** Chile / Spanish  
- **Modules in ERP:** Accounting (core), Clients, Inventory, Sales, Purchases, POS, Configuración, HR (RRHH), Reports  
- **Future modules:** Website integration  
- **Schema file:** All database definitions must go inside **`supabase/sql/core_schema.sql`** (never create additional SQL files).

---

## 🧩 Module Structure

Add a new entry in the navigation pane named **Bikeshop**, containing two submenus:

```
Bikeshop
 ├── Clientes
 └── Trabajos (en curso)
```

---

## 👥 Submenu 1: Clientes

This view lists customers and provides access to bicycles, service history,
and current workshop work. Its current composition must be derived from the
operating task and canonical GUI guides.
It lists all customers and provides access to their bicycles, service history, and current mechanic jobs.

### 🧾 Historical information fields
| Column | Description |
|--------|--------------|
| Nombre del Cliente | Linked to `clients` table (foreign key) |
| Teléfono | Contact number (read from client profile) |
| Estado del Servicio | Semantic status (`COMENZAR`, `DIAGNÓSTICO`, `COMPONENTES`, `EN CURSO`, `FINALIZADO`), legible without color alone |
| Fecha de Ingreso | Date the client delivered the bike |
| Antecedentes de Bicicleta | Free text or structured notes (bike age, maintenance history, type of use) |
| Solicitud de Cliente | Client’s request or reported issues |
| Diagnóstico / Comentarios | Mechanic’s notes, diagnosis, or work performed |

### 🧭 Behavior
- Each row represents an active or past job.
- Clicking on a **client name** opens the **Client Logbook View**, showing:
  - Chronological access to all past and current services.
  - Attached photos of the bicycle.
  - Invoices related to the client.
  - Used products and services.
  - A comprehensible chronological history; choose its representation from the
    current task rather than prescribing a graphical timeline.

### 🧱 Database Relations
- Linked to `clients`, `bikes`, `sales_invoices`, and `inventory` tables.
- The **bike logbook** view aggregates all service data per client and per bike.

---

## 🔧 Submenu 2: Trabajos (en curso)

A high-throughput view for active workshop jobs. Its desktop, tablet, and phone
representations may differ while composing the same business commands.

### 📋 Columns
| Column | Description |
|--------|--------------|
| Job ID | Primary key |
| Cliente | Linked to `clients` table (searchable dropdown) |
| Bicicleta | Linked to `bikes` table |
| Fecha de Ingreso | Date the client left the bike |
| Plazo / Deadline | Expected delivery date |
| Tiempo restante | Calculated automatically (deadline - current date) |
| Estado | Label (Pending, In Progress, Waiting for Parts, Done) |
| Técnico asignado | Linked to `employees` table (RRHH) |
| Diagnóstico | Mechanic notes |
| Productos / Servicios usados | Linked to `products` and `services` tables |
| Monto estimado | Numeric field (optional) |

### 💡 Behavior
- New jobs can be added via “+ Nuevo Trabajo”.
- Selecting a **Client** automatically fills related fields:
  - Client ID  
  - Bicycle list  
  - Default contact info  
- Jobs marked as **Done** remain in the database but are hidden by default (filter toggle: “Show completed”).
- Clicking a client name takes you to the **Client Logbook**.
- Supports **search, filters, sorting, and clear semantic status treatment**
  without copying another product or depending on color alone.

---

## 🧮 Database Schema (add to `core_schema.sql`)

Use normalized tables with clear foreign key references:

```sql
CREATE TABLE bikes (
  id SERIAL PRIMARY KEY,
  client_id INTEGER REFERENCES clients(id),
  brand TEXT,
  model TEXT,
  serial_number TEXT,
  image_url TEXT,
  notes TEXT
);

CREATE TABLE mechanic_jobs (
  id SERIAL PRIMARY KEY,
  client_id INTEGER REFERENCES clients(id),
  bike_id INTEGER REFERENCES bikes(id),
  arrival_date DATE NOT NULL,
  deadline DATE,
  status TEXT CHECK (status IN ('COMENZAR','DIAGNÓSTICO','COMPONENTES','EN CURSO','FINALIZADO')),
  assigned_to INTEGER REFERENCES employees(id),
  diagnosis TEXT,
  request TEXT,
  notes TEXT
);

CREATE TABLE mechanic_job_items (
  id SERIAL PRIMARY KEY,
  job_id INTEGER REFERENCES mechanic_jobs(id),
  product_id INTEGER REFERENCES products(id),
  quantity INTEGER,
  price NUMERIC
);

CREATE TABLE mechanic_job_images (
  id SERIAL PRIMARY KEY,
  job_id INTEGER REFERENCES mechanic_jobs(id),
  image_url TEXT
);
```

### 🔄 Triggers / Functions
Follow the same pattern as existing functions like:
- `handle_sales_invoice_change()`
- `create_purchase_journal_entry()`

Add:
- `handle_mechanic_job_change()` → updates timestamps, audit log, and triggers accounting link if invoiced.  
- `create_mechanic_job_invoice_entry()` → posts accounting journal entry when service completed.

---

## 🧭 Integration Logic
- Mechanic jobs are linked to **clients** and **bikes**.
- When an invoice is generated for a job:
  - It automatically links to the corresponding mechanic job via FK.
  - Products/services used update inventory and accounting.
- Images uploaded to Supabase Storage (path stored in DB).
- All operations must respect **primary key consistency** across modules.

---

## 🎨 UI & UX Rules
- Follow both canonical GUI guides linked in the warning above.
- Use theme-owned visual roles and clear text/semantics for status; historical
  screenshots and literal palettes are not precedent.
- Lists: searchable, sortable, and paginated.
- Make chronological history understandable; a timeline is one candidate, not
  a mandatory visual pattern.
- Support **image upload** and display carousel.
- Support the application themes and accessibility modes owned by the current
  design system.
- Default language: **Spanish (Chile)**.
- Date format: **DD/MM/YYYY**.

---

## 🧠 Technical Checklist
- ✅ Create new folder: `lib/modules/bikeshop/`
- ✅ Add files:
  - `clients_list_page.dart`
  - `client_logbook_page.dart`
  - `trabajos_list_page.dart`
  - `mechanic_job_form.dart`
- ✅ Add models: `Bike`, `MechanicJob`, `MechanicJobItem`
- ✅ Add service: `BikeshopService` (CRUD + storage upload)
- ✅ Update sidebar navigation and routes
- ✅ Update `core_schema.sql` (no new SQL files)
- ✅ Reuse existing `ImageService`
- ✅ Maintain naming consistency across all entities

---

## 💾 Workflow Example
1. Client leaves a bike → mechanic creates a new “trabajo”.
2. Mechanic adds notes, expected deadline, and attaches photos.
3. Job appears in “Trabajos” view, status “DIAGNÓSTICO”.
4. When invoiced → auto-linked to Accounting + Inventory.
5. Once marked “FINALIZADO” → moves to hidden completed jobs list.
6. Client’s logbook updates automatically with full history.

---

## 🚀 Optional Enhancements
- Add priority labels (Urgente, Normal, Baja)
- Add technician calendar (linked to HR)
- Enable status notifications (email/push)
- Export service report to PDF
- Sync with Website module for client self-tracking

---

## ⚠️ Remember
- Always edit `core_schema.sql` (no other SQL files).
- Always check for existing similar tables/functions before adding new ones.
- Reuse helper functions like `ensure_account()`, `consume_inventory()`.
- Keep all new entities integrated with accounting logic.
- Compile and test after every schema or navigation change.
