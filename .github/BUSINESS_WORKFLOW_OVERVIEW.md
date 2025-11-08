# 🚴 Bikeshop Business Workflow Overview

**Date**: November 7, 2025  
**Context**: Migration from Notion + Zoho Books → Flutter ERP App

---

## 📊 System Migration

### **Current System (Legacy)**
- **Notion** → Job tracking, client data, status management, communication history
- **Zoho Books** → Invoicing, inventory, accounting

### **Future System (Flutter App)**
- **Pegas Module** → Replaces Notion (mechanic jobs, client data, bike history, status tracking)
- **Inventory + Accounting Module** → Replaces Zoho Books (products, invoicing, payments, journal entries)
- **POS Module** → Fast checkout for quick sales/services

---

## 🏪 4 Business Scenarios

### **Scenario 1: Quick Product Sale**
**Type**: Walk-in customer buying a product  
**Duration**: ~2 minutes  
**Flow**:
1. Client enters store
2. Selects product
3. Pays at checkout
4. Leaves

**Modules Used**:
- **POS Module** → Fast checkout
- **Inventory Module** → Auto stock deduction
- **Accounting Module** → Auto journal entry creation

**Characteristics**:
- No job tracking needed
- Instant transaction
- Primarily cash/card payments

---

### **Scenario 2: Emergency Service + Products (Hybrid)**
**Type**: Urgent repair with parts/accessories  
**Duration**: ≤1 hour  
**Flow**:
1. Client arrives with urgent problem
2. Mechanic diagnoses and fixes immediately
3. Client often buys:
   - Spare parts used in repair
   - Additional services
   - Accessories

**Modules Used**:
- **Option A**: **POS Module** (for speed) → Quick checkout with parts + labor + accessories
- **Option B**: Quick **Pegas Job** (for tracking) → Minimal data entry → Generate invoice

**Decision Point**: Speed vs. History Tracking
- Use POS if client wants to leave immediately
- Use Pegas if you want bike service history recorded

---

### **Scenario 3: Rush Service Only**
**Type**: Urgent service without parts  
**Duration**: ≤1 hour  
**Flow**:
1. Client needs quick service (e.g., brake adjustment, tire inflation)
2. Service completed on the spot
3. Labor charge applied

**Modules Used**:
- **POS Module** → Labor as service item
- OR **Sales Invoice** → Manual invoice creation

**Characteristics**:
- No complex tracking
- Minimal data entry
- Quick payment processing

---

### **Scenario 4: Long-Term/Complex Service (MAJORITY)**
**Type**: Full mechanic job with diagnosis, parts ordering, multi-day work  
**Duration**: Days to weeks  
**Flow**:

#### **Phase 1: Job Intake**
- Client brings bicycle to store (Viña del Mar, Chile)
- Appointment scheduled if bike not available immediately
- Client explains problem → Initial assessment

#### **Phase 2: Diagnosis (Pegas Module)**
- Client data saved in **Pegas Module**:
  - Name, phone number
  - Bike details: brand, model, color
  - Problem description
- Mechanic performs full diagnosis
- Job status tracked throughout lifecycle

**Job Statuses**:
- `en conversacion` (in conversation)
- `contactar` (to contact)
- `diagnostico` (diagnosis phase)
- `terminada` (completed)
- `probada` (tested)
- `entregada` (delivered)
- `esperando componentes` (waiting for parts)

#### **Phase 3: Budgeting & Approval**
- Diagnosis completed → Budget created
- **Invoice generated manually** (NOT auto-generated) in **Accounting Module**:
  - Products/parts needed (from **Inventory Module**)
  - Services/labor costs
- Invoice sent to client via **WhatsApp** for confirmation
- **Timing is flexible**: Invoice can be created immediately, after diagnosis, or even days later

#### **Phase 4: Payment Collection**
**Payment Methods**:

1. **Cash**
   - No receipt needed
   - Money placed in drawer
   - Tax tracking: Not registered with SII

2. **Card (POS Terminal)**
   - Card terminal generates receipt
   - Connected to **SII** (Chilean tax service)
   - 19% IVA automatically registered
   - Tax tracking: Full compliance

3. **Wire Transfer**
   - Bank details provided to client
   - Instant transfers in Chile (no extra fees)
   - Tax tracking: Not registered with SII

**Business Preference**: Cash or wire transfer (better cash flow, less fees)

**Process**:
- Client name requested to link payment to invoice
- Payment manually recorded in **Accounting Module**

#### **Phase 5: Job Execution**
- After payment confirmed → Work begins
- Check spare parts availability → Order if needed (links to **Inventory Module**)
- Perform repair/service
- Contact client when job is ready

#### **Phase 6: Testing & Delivery**
- Bike given to client with **1-week test period guarantee**
- If problems arise during test → Guarantee covers it
- Client tests bike for issues
- Final confirmation via WhatsApp
- Job status updated to `entregada` (delivered)

---

## 🔗 Module Integration Points

### **Pegas Module → Inventory Module**
- Check parts availability before starting job
- Reserve stock for ongoing jobs
- Deduct inventory when parts are used
- Trigger restocking if parts unavailable

### **Pegas Module → Accounting Module**
- Manual invoice generation from job details
- Link invoice back to job (`mechanic_jobs.invoice_id`)
- Record payments against job
- Track labor costs

### **Inventory Module → Accounting Module**
- Auto-create journal entries when inventory moves
- Update COGS (Cost of Goods Sold)
- Track inventory valuation

### **POS Module → Inventory + Accounting**
- Real-time stock deduction on sale
- Auto-generate journal entries (Debit: Cash/Card, Credit: Sales + IVA)
- Payment method tracking

---

## 💡 Key Business Rules

### **Invoice Timing (Pegas Jobs)**
- Invoices are **NOT auto-generated** when job is created
- Mechanic/manager creates invoice **manually when ready**:
  - After diagnosis
  - After client approval
  - After job completion
  - Or even days later
- Allows for:
  - Budget adjustments
  - Client negotiations
  - Parts availability changes
  - Scope changes during job

### **Tax Tracking**
- **Cards**: Full IVA registration with SII (19%)
- **Cash/Wire Transfer**: No automatic tax registration
- All sales must be tracked internally regardless of payment method

### **Payment Recording**
- All payments must be manually recorded in accounting system
- Link payment to specific invoice
- Track payment method for reconciliation

### **Job Status Updates**
- Status updated throughout entire job lifecycle
- Visible to all team members
- Used for client communication tracking

### **Guarantee Period**
- 1-week test period after delivery
- Client can return if issues arise
- Covered under job guarantee

---

## 🎯 Module Usage Decision Tree

```
Client arrives
    |
    ├─ Wants to buy product only?
    │  └─ YES → **POS Module** (2 min checkout)
    |
    ├─ Needs urgent service (<1 hour)?
    │  └─ YES → **POS Module** OR Quick **Sales Invoice**
    |      └─ Wants history tracked? → Quick **Pegas Job**
    |
    └─ Needs complex service/diagnosis?
       └─ YES → **Pegas Module** (full workflow)
           └─ Creates invoice manually when ready
```

---

## 📦 Data Flow Summary

### **Quick Sale (POS)**
```
Client → POS → Payment → Stock Deduction → Journal Entry → Done
```

### **Rush Service**
```
Client → POS/Invoice → Payment → (Optional) Pegas Job → Done
```

### **Complex Service (Pegas Workflow)**
```
Client → Pegas Job Created → Diagnosis → Manual Invoice Created → 
Client Approval → Payment → Parts Ordered → Job Execution → 
Testing → Delivery → Status: Entregada
```

---

## 🔄 Migration Benefits

### **From Notion + Zoho Books → Flutter App**

**Before**:
- Data scattered across 2 platforms
- Manual data entry in both systems
- No real-time integration
- Difficult to track job → invoice → payment flow

**After (Flutter App)**:
- **Single unified system**
- Real-time integration between modules
- Automatic accounting entries
- Clear job → invoice → payment linking
- Mobile access for mechanics
- Offline capability
- Multi-tenant support (future expansion)

---

## 📝 Important Notes

1. **Pegas Module is for tracking**, not for quick transactions
2. **Invoice creation is manual and flexible** in Pegas workflow
3. **POS Module is the fast lane** for quick sales/services
4. **Payment methods matter** for tax compliance
5. **Status updates are critical** for team coordination
6. **Client communication happens via WhatsApp** (invoices, updates, confirmations)
7. **Guarantee period is standard** (1 week test period)

---

## 🚀 Future Enhancements

- WhatsApp API integration for automated invoice sending
- Automated status update notifications to clients
- Online appointment booking
- Client portal for job status tracking
- SMS reminders for bike pickup
- Automated parts ordering when stock is low
- Analytics dashboard for job completion times, revenue by service type

---

**End of Document**
