const fs = require('fs');
const env = Object.fromEntries(
  fs.readFileSync('.env','utf8').split('\n')
    .filter(l => l && !l.startsWith('#') && l.includes('='))
    .map(l => { const i = l.indexOf('='); return [l.slice(0,i), l.slice(i+1)]; })
);
const KEY = env['SUPABASE_SERVICE_ROLE_KEY'];
const BASE = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1';
const TID = '5443b130-cc28-45af-a420-cd500b288890';
const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };

(async () => {
  // The invoice
  const r1 = await fetch(BASE + '/sales_invoices?select=*&tenant_id=eq.' + TID + '&invoice_number=eq.TEST-IVA-001', { headers: H });
  const invs = await r1.json();
  console.log('=== INVOICE ===');
  console.log(JSON.stringify(invs[0], null, 2));

  // The JE
  const r2 = await fetch(BASE + '/journal_entries?select=*&tenant_id=eq.' + TID + '&source_reference=eq.TEST-IVA-001', { headers: H });
  const jes = await r2.json();
  console.log('\n=== JOURNAL ENTRY ===');
  console.log(JSON.stringify(jes[0], null, 2));

  // The JE lines
  if (jes[0]) {
    const r3 = await fetch(BASE + '/journal_lines?select=account_code,account_name,debit_amount,credit_amount&entry_id=eq.' + jes[0].id, { headers: H });
    const lines = await r3.json();
    console.log('\n=== JE LINES ===');
    for (const l of lines) console.log(`  ${l.account_code} ${l.account_name.padEnd(40)} DR:${String(l.debit_amount).padStart(12)}  CR:${String(l.credit_amount).padStart(12)}`);
  }
})().catch(console.error);
