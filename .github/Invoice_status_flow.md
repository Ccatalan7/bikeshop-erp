INVOICE STATUS FLOW — ERP LOGIC, GUI BEHAVIOR & BACKEND TRIGGERS (Zoho Books Model)

This ERP module must replicate the invoice lifecycle logic observed in Zoho Books. The invoice transitions through multiple statuses, each triggered by explicit user actions (button presses), and each status change must activate corresponding backend logic. The goal is to ensure accounting integrity, inventory accuracy, and intuitive navigation for Chilean users.

STATUS FLOW OVERVIEW

Draft — Status label: “Borrador”. Fields are locked by default. Button: “Editar” unlocks fields for editing. Button: “Marcar como enviado” triggers status change to “Enviado”, which reduces inventory based on invoice items and creates a journal entry for revenue and COGS. No payment record is created at this stage.

Created/Sent — Status label: “Enviado”. Inventory and journal entry already processed. Button: “Registrar pago” navigates to the payment form.

Payment Form — User enters payment method, amount, date, and notes. Button: “Guardar como pagado” or “Pagar” triggers status change to “Pagado”, which creates a payment record and a journal entry for the payment. No further inventory change occurs.

Paid — Status label: “Pagado”. Invoice is locked from further edits. All financial records are finalized.

SQL TRIGGER REFERENCE

On status change to “Enviado”: CREATE TRIGGER reduce_inventory_and_log_revenue AFTER UPDATE ON invoices FOR EACH ROW WHEN NEW.status = 'sent' BEGIN UPDATE products SET stock = stock - (SELECT quantity FROM invoice_items WHERE invoice_id = NEW.id AND product_id = products.id); INSERT INTO journal_entries (type, amount, reference_id, reference_type) VALUES ('revenue', NEW.total, NEW.id, 'invoice'); END;

On status change to “Pagado”: CREATE TRIGGER log_payment_and_create_record AFTER UPDATE ON invoices FOR EACH ROW WHEN NEW.status = 'paid' BEGIN INSERT INTO payments (invoice_id, amount, method, date) VALUES (NEW.id, NEW.total, NEW.payment_method, CURRENT_DATE); INSERT INTO journal_entries (type, amount, reference_id, reference_type) VALUES ('payment', NEW.total, NEW.id, 'invoice'); END;

GUI & NAVIGATION BEHAVIOR

Draft View (Screenshot #1) — Invoice form loads with fields locked. Button: “Editar” unlocks fields for editing. Button: “Marcar como enviado” triggers status change to “Enviado” and backend logic.

Created/Sent View (Screenshot #2) — Status label updates to “Enviado”. Inventory and journal entry already processed. Button: “Registrar pago” navigates to payment form.

Payment Form (Screenshot #3) — User enters payment details. Button: “Guardar como pagado” or “Pagar” triggers status change to “Pagado” and backend logic.

Paid View (Screenshot #4) — Status label: “Pagado”. Invoice locked. Payment record and journal entry finalized.

DESIGN PRINCIPLES

Status transitions must be explicitly triggered via UI buttons. Each status change must activate its corresponding backend logic. GUI must reflect current status clearly and guide user through next steps. Navigation between invoice and payment form must be seamless and intuitive. All labels, buttons, and messages must be localized for Chilean users (CLP currency, Spanish UI).

AGENT INSTRUCTIONS

Ensure all status transitions are button-driven, not implicit. Validate backend triggers are firing correctly on status change. Keep GUI minimal, consistent, and localized. Confirm inventory and journal entries reflect real-time changes. Use screenshots as reference for layout, button placement, and navigation flow.