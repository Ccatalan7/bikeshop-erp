const fs = require('fs');
const env = Object.fromEntries(
  fs.readFileSync('.env','utf8').split('\n')
    .filter(l => l && !l.startsWith('#') && l.includes('='))
    .map(l => { const i = l.indexOf('='); return [l.slice(0,i), l.slice(i+1)]; })
);
const KEY = env['SUPABASE_SERVICE_ROLE_KEY'];
const BASE = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1';
const TID = '5443b130-cc28-45af-a420-cd500b288890';
const H = { apikey: KEY, Authorization: 'Bearer ' + KEY, Range: '0-999' };

async function get(path) {
  const r = await fetch(BASE + path, { headers: H });
  return r.json();
}

(async () => {
  // ── Missing JE invoices ──────────────────────────────────────────────
  const invs = await get(
    '/sales_invoices?select=id,invoice_number,status,total,net_amount,iva_amount,subtotal,tax_treatment,customer_name,date' +
    '&tenant_id=eq.' + TID +
    '&invoice_number=in.(FV-00457,FV-00406)'
  );
  console.log('=== INVOICES WITH MISSING JEs ===');
  for (const inv of invs) {
    console.log(`  ${inv.invoice_number}  status=${inv.status}  customer="${inv.customer_name}"  date=${inv.date}`);
    console.log(`    total=${inv.total}  net_amount=${inv.net_amount}  iva_amount=${inv.iva_amount}  subtotal=${inv.subtotal}  tax_treatment=${inv.tax_treatment}`);
    console.log(`    id=${inv.id}`);
  }

  // ── AP breakdown ─────────────────────────────────────────────────────
  const apLines = await get(
    '/journal_lines?select=account_code,debit_amount,credit_amount&account_code=in.(2100,2101)&tenant_id=eq.' + TID
  );
  let apDR = 0, apCR = 0;
  for (const l of apLines) { apDR += +l.debit_amount; apCR += +l.credit_amount; }
  console.log('\n=== AP ACCOUNT (2100/2101) ===');
  console.log(`  Lines: ${apLines.length}  DR: ${apDR.toFixed(2)}  CR: ${apCR.toFixed(2)}  Net(CR-DR): ${(apCR - apDR).toFixed(2)}`);

  // ── Purchase payment JEs: which account gets the DR? ─────────────────
  const ppJEs = await get(
    '/journal_entries?select=id&source_module=eq.purchase_payments&tenant_id=eq.' + TID
  );
  const ppIds = ppJEs.map(j => j.id).slice(0, 50); // sample first 50
  if (ppIds.length > 0) {
    const ppLines = await get(
      '/journal_lines?select=account_code,debit_amount,credit_amount&entry_id=in.(' + ppIds.join(',') + ')&tenant_id=eq.' + TID
    );
    const byCode = {};
    for (const l of ppLines) {
      byCode[l.account_code] = byCode[l.account_code] || { dr: 0, cr: 0 };
      byCode[l.account_code].dr += +l.debit_amount;
      byCode[l.account_code].cr += +l.credit_amount;
    }
    console.log('\n=== PURCHASE PAYMENT JEs — account breakdown (first 50 JEs) ===');
    for (const [code, s] of Object.entries(byCode).sort()) {
      console.log(`  ${code}  DR: ${s.dr.toFixed(2)}  CR: ${s.cr.toFixed(2)}`);
    }
  }

  // ── Purchase invoice JEs: account breakdown ──────────────────────────
  const piJEs = await get(
    '/journal_entries?select=id&source_module=eq.purchase_invoices&tenant_id=eq.' + TID
  );
  const piIds = piJEs.map(j => j.id);
  if (piIds.length > 0) {
    const piLines = await get(
      '/journal_lines?select=account_code,debit_amount,credit_amount&entry_id=in.(' + piIds.join(',') + ')&tenant_id=eq.' + TID
    );
    const byCode = {};
    for (const l of piLines) {
      byCode[l.account_code] = byCode[l.account_code] || { dr: 0, cr: 0 };
      byCode[l.account_code].dr += +l.debit_amount;
      byCode[l.account_code].cr += +l.credit_amount;
    }
    console.log('\n=== PURCHASE INVOICE JEs — account breakdown ===');
    for (const [code, s] of Object.entries(byCode).sort()) {
      console.log(`  ${code}  DR: ${s.dr.toFixed(2)}  CR: ${s.cr.toFixed(2)}`);
    }
  }
})().catch(console.error);
