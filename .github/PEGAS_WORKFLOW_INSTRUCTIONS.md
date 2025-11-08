# 🚴 CRITICAL: PEGAS (MECHANIC JOBS) WORKFLOW - CORE BUSINESS

**⚠️ THIS IS THE PRIMARY REVENUE STREAM - UNDERSTAND THIS COMPLETELY**

## Business Context

The **Pegas Module** (mechanic jobs/maintenance) represents **the majority of the business**. This is a bike repair shop in Viña del Mar, Chile, not primarily a retail store. The workflow handles complex, multi-day repair jobs with diagnosis, budgeting, parts ordering, and client communication.

## The 4 Sales Scenarios (By Volume)

### **Scenario 4: Long-Term Service (MAJORITY - 70%+ of revenue)**
**This is what the business IS ABOUT.**
- Client brings bike → Diagnosis → Budget approval → Repair → Delivery
- Duration: Days to weeks
- Tracked in **Pegas Module** with full job lifecycle
- Invoice created **manually when ready** (NOT auto-generated on job creation)
- Links to Inventory (parts used) and Accounting (payments)

### **Scenario 1: Quick Product Sale (~15%)**
- Walk-in buys product → POS checkout → Done (2 minutes)

### **Scenario 2: Emergency Service + Products (~10%)**
- Urgent repair + parts/accessories → Fixed in ~1 hour
- Can use POS for speed OR quick Pegas job for tracking

### **Scenario 3: Rush Service Only (~5%)**
- Quick service (brake adjustment, tire inflation) → POS or manual invoice

## Pegas Workflow Architecture

### **Phase 1: Job Intake**
```
Client brings bike → Staff creates Pegas job record:
  - Customer info (name, phone, email)
  - Bike details (brand, model, color, problem description)
  - Initial status: 'en conversacion' or 'diagnostico'
```

### **Phase 2: Diagnosis**
```
Mechanic inspects bike → Updates job with findings
Status tracking: en conversacion → diagnostico → esperando componentes → terminada → probada → entregada
Job visible to all team members for coordination
```

### **Phase 3: Budgeting (FLEXIBLE TIMING)**
```
⚠️ CRITICAL: Invoice creation timing is FLEXIBLE!

Option 1: Create invoice WITH pega (if products/services selected during job creation)
  - Staff adds parts/labor while creating job
  - System creates invoice immediately
  - Invoice links back: mechanic_jobs.invoice_id = created_invoice.id

Option 2: Create invoice AFTER pega (most common for complex jobs)
  - Create job first (diagnosis phase)
  - Add parts as job progresses
  - Click "Generar Factura" button when ready (could be immediately, after diagnosis, or days later)
  - System pre-fills invoice with:
      - Customer from job
      - Parts from mechanic_job_parts table (if already added)
      - Labor cost from job.labor_cost field
  - Staff can edit before saving

Why flexible timing?
  - Budget may change during diagnosis
  - Client may negotiate price
  - Parts availability may affect scope
  - Job scope may expand/shrink
```

### **Phase 4: Client Approval**
```
Invoice sent to client via WhatsApp
Client reviews and approves
May request changes → Staff updates invoice
```

### **Phase 5: Payment Collection**
```
Payment Methods (ALL recorded manually in system FOR NOW):
  1. Cash → Staff counts, puts in drawer, clicks "Registrar Pago"
  2. Card (POS Terminal) → Staff processes card, gets receipt, clicks "Registrar Pago"
  3. Wire Transfer → Client transfers, staff sees in bank app, clicks "Registrar Pago"

Current State: Manual payment recording
  - Staff ALWAYS manually records payments in system
  - Cards generate SII tax receipt automatically (19% IVA), but staff still records in app
  - Cash/wire transfers require manual tax tracking

Future Enhancement: Payment Webhooks (Not Yet Implemented)
  - Card payments could auto-sync via Transbank API
  - Wire transfers could use bank aggregators (Fintoc, Klap)
  - For now: Manual is fine, automation only if volume justifies cost
```

### **Phase 6: Job Execution**
```
Payment confirmed → Mechanic starts work
Parts ordered if needed (links to Inventory Module)
Mechanic updates job status as work progresses
System tracks parts used via mechanic_job_parts table
```

### **Phase 7: Testing & Delivery**
```
Job completed → Status: 'terminada'
Client picks up bike → 1 week test period
If issues arise → Covered under guarantee (no additional charge)
Final status: 'entregada' (delivered)
```

## Database Schema (Pegas Core Tables)

```sql
-- Main job tracking
CREATE TABLE mechanic_jobs (
  id uuid PRIMARY KEY,
  tenant_id uuid REFERENCES tenants(id) NOT NULL,
  customer_id uuid REFERENCES customers(id) NOT NULL,
  invoice_id uuid REFERENCES sales_invoices(id), -- Links to invoice when created
  bike_brand text,
  bike_model text,
  bike_color text,
  problem_description text,
  diagnosis_notes text,
  labor_cost numeric DEFAULT 0,
  status text DEFAULT 'en conversacion',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Parts used in job
CREATE TABLE mechanic_job_parts (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL,
  job_id uuid REFERENCES mechanic_jobs(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  quantity integer DEFAULT 1,
  price numeric
);

-- Status values
-- 'en conversacion' - Initial contact
-- 'contactar' - Need to contact client
-- 'diagnostico' - Diagnosis phase
-- 'esperando componentes' - Waiting for parts
-- 'terminada' - Work completed
-- 'probada' - Tested/ready for pickup
-- 'entregada' - Delivered to client
```

## POS Integration Pattern (NEW - To Be Implemented)

```dart
// When customer is selected in POS
void _onCustomerSelected(Customer customer) async {
  // Check for pending invoices (posted but not fully paid)
  final pendingInvoices = await salesService.getPendingInvoices(
    customerId: customer.id,
    statuses: ['posted', 'partial'], // Exclude 'draft' and 'paid'
  );
  
  if (pendingInvoices.isNotEmpty) {
    // Show dialog: "Cliente tiene X facturas pendientes. ¿Abrir factura del pega?"
    final selectedInvoice = await _showPendingInvoiceDialog(context, pendingInvoices);
    
    if (selectedInvoice != null) {
      // Load invoice items into POS cart
      posService.clearCart();
      for (final item in selectedInvoice.items) {
        posService.addToCart(item.product, quantity: item.quantity, price: item.price);
      }
      
      // Link invoice to POS transaction
      posService.setLinkedInvoice(selectedInvoice);
      
      // On payment → Update existing invoice instead of creating new one
    }
  }
}
```

## Critical Business Rules

### **Invoice Timing**
- ✅ Invoice CAN be created WITH pega (if products/services selected during job creation)
- ✅ Invoice CAN be created AFTER pega (via "Generar Factura" button - most common for complex jobs)
- ✅ Staff decides when to create invoice based on job complexity
- ✅ Invoice can be created at ANY point in job lifecycle
- ✅ Invoice can be modified until payment is processed

### **Payment Recording (Current: Manual, Future: May Automate)**
- 🔄 **Current State:** Staff manually records ALL payments
  - Three-step process: 1) Client pays (physical), 2) Staff verifies, 3) Staff clicks "Registrar Pago"
  - This is the CORRECT workflow for small business at current volume
- 🔮 **Future Enhancement (Not Yet Implemented):**
  - Card payment webhooks via Transbank API (auto-sync)
  - Wire transfer webhooks via bank aggregators (Fintoc/Klap)
  - Automation only if transaction volume justifies the cost (~2-3% fees)

### **Job-Invoice Linking**
- ✅ Bidirectional link: `mechanic_jobs.invoice_id` ↔ `sales_invoices.id`
- ✅ Cascade delete: Deleting job → Deletes invoice | Deleting invoice → Deletes job
- ✅ Prevents orphaned records

### **Inventory Integration**
- ✅ Parts added to `mechanic_job_parts` table as job progresses
- ✅ When invoice is generated → Parts become invoice line items
- ✅ When invoice is posted → Inventory is deducted (via trigger)
- ✅ If job is deleted → Inventory is restored (if invoice was posted)

### **Multi-Tenant Isolation**
- ✅ ALL Pegas tables have `tenant_id` column
- ✅ ALL queries filter by `tenant_id`
- ✅ Jobs from different bike shops are completely isolated

## Module Boundaries

### **What Pegas Module DOES:**
- ✅ Track job lifecycle (status, notes, diagnosis)
- ✅ Store bike details and problem description
- ✅ Track parts used in repair
- ✅ Calculate labor cost
- ✅ Link to customer record
- ✅ Link to invoice record (when created)
- ✅ Provide UI for mechanics and front desk staff

### **What Pegas Module DOES NOT DO:**
- ❌ Generate invoices automatically
- ❌ Process payments (that's Accounting Module)
- ❌ Manage inventory (that's Inventory Module)
- ❌ Track accounting entries (that's handled by triggers)
- ❌ Send WhatsApp messages (manual, not automated)

### **Integration Points:**
- **CRM Module** → Customer data (name, phone, email, bike history)
- **Inventory Module** → Product lookup, stock checks, parts availability
- **Sales Module** → Manual invoice generation, invoice-job linking
- **Accounting Module** → Payment recording, journal entries (via triggers)
- **POS Module** → Load pending invoices for payment processing (NEW)

## AI Agent Guidelines

**When working on Pegas-related features:**

1. ✅ **Invoice creation is FLEXIBLE** - Can be created WITH pega (current feature) OR manually after (also supported)
2. ✅ **Keep both invoice creation paths working** - Don't break the existing "create invoice with pega" feature
3. 🔄 **Payment webhooks are FUTURE enhancement** - Manual recording is current state, but automation may come later
4. ✅ **ALWAYS preserve job-invoice bidirectional link** - Critical for data integrity
5. ✅ **ALWAYS filter by tenant_id** - Multi-tenant isolation is non-negotiable
6. ✅ **ALWAYS update both inventory_qty AND stock_quantity** - When parts are used
7. ✅ **ALWAYS check existing status values** - Don't invent new ones without confirmation
8. ✅ **ALWAYS link parts to jobs via mechanic_job_parts** - Don't add to invoice directly
9. ✅ **Test the full lifecycle** - Job creation → Invoice generation (both paths) → Payment → Delivery

**This is the CORE of the business. Get this right, and everything else falls into place.**
