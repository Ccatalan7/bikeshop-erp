// Accounting diagnosis queries — run with: node .tmp/q.js
const fs = require('fs');
const env = Object.fromEntries(
  fs.readFileSync('.env','utf8').split('\n')
    .filter(l => l && !l.startsWith('#') && l.includes('='))
    .map(l => { const i = l.indexOf('='); return [l.slice(0,i), l.slice(i+1)]; })
);
const KEY = env['SUPABASE_SERVICE_ROLE_KEY'];
const BASE = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1';
const TID = '5443b130-cc28-45af-a420-cd500b288890';

async function rest(path) {
  const r = await fetch(`${BASE}${path}`, {
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, Range: '0-9999' }
  });
  const data = await r.json();
  if (!Array.isArray(data)) { console.error('REST error:', JSON.stringify(data)); process.exit(1); }
  return data;
}

// Fetch ALL rows by paginating 1000 at a time
async function restAll(path) {
  const pageSize = 1000;
  let offset = 0, all = [];
  while (true) {
    const r = await fetch(`${BASE}${path}`, {
      headers: {
        apikey: KEY, Authorization: `Bearer ${KEY}`,
        Range: `${offset}-${offset + pageSize - 1}`,
        'Range-Unit': 'items',
        Prefer: 'count=none'
      }
    });
    const data = await r.json();
    if (!Array.isArray(data) || data.length === 0) break;
    all.push(...data);
    if (data.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

const BAD_REFS = ['FV-00323','FV-00292','FV-00354','FV-00072','FV-00424','FV-00403','FV-00182','FV-00364','FV-00399','FV-00426'];

async function main() {
  console.log('='.repeat(70));
  console.log('  ACCOUNTING HEALTH CHECK');
  console.log('='.repeat(70));

  // ── 1. GLOBAL TRIAL BALANCE ─────────────────────────────────────────────
  console.log('\n[1] GLOBAL TRIAL BALANCE');
  const allLines = await restAll(`/journal_lines?select=debit_amount,credit_amount&tenant_id=eq.${TID}`);
  let gDR = 0, gCR = 0;
  for (const l of allLines) { gDR += +l.debit_amount; gCR += +l.credit_amount; }
  const gDiff = gDR - gCR;
  console.log(`    Lines: ${allLines.length}  DR: ${gDR.toFixed(2)}  CR: ${gCR.toFixed(2)}  Diff: ${gDiff.toFixed(2)}`);
  console.log(`    ${Math.abs(gDiff) < 0.01 ? '✅ BALANCED' : '❌ IMBALANCED'}`);

  // ── 2. BALANCE PER SOURCE MODULE ────────────────────────────────────────
  console.log('\n[2] BALANCE PER SOURCE MODULE');
  const jesFull = await restAll(`/journal_entries?select=id,source_module,total_debit,total_credit&tenant_id=eq.${TID}&status=eq.posted`);
  const byModule = {};
  for (const je of jesFull) {
    const m = je.source_module || 'unknown';
    byModule[m] = byModule[m] || { count: 0, dr: 0, cr: 0, bad: 0 };
    byModule[m].count++;
    byModule[m].dr += +je.total_debit;
    byModule[m].cr += +je.total_credit;
    if (Math.abs(+je.total_debit - +je.total_credit) > 0.01) byModule[m].bad++;
  }
  for (const [mod, s] of Object.entries(byModule).sort()) {
    const ok = Math.abs(s.dr - s.cr) < 0.01 && s.bad === 0;
    console.log(`    ${ok ? '✅' : '❌'} ${mod.padEnd(25)} entries:${String(s.count).padStart(4)}  DR:${s.dr.toFixed(2).padStart(14)}  CR:${s.cr.toFixed(2).padStart(14)}  bad_headers:${s.bad}`);
  }

  // ── 3. JE LINES BALANCE PER MODULE (line-level, not header) ────────────
  console.log('\n[3] LINE-LEVEL BALANCE PER MODULE (catches header vs lines mismatch)');
  const jeIdsByModule = {};
  for (const je of jesFull) {
    const m = je.source_module || 'unknown';
    (jeIdsByModule[m] = jeIdsByModule[m] || []).push(je.id);
  }
  for (const [mod, ids] of Object.entries(jeIdsByModule).sort()) {
    // chunk requests to avoid URL length limit
    let mDR = 0, mCR = 0, badJEs = 0;
    const chunkSize = 200;
    for (let i = 0; i < ids.length; i += chunkSize) {
      const chunk = ids.slice(i, i + chunkSize);
      const ls = await restAll(`/journal_lines?select=entry_id,debit_amount,credit_amount&entry_id=in.(${chunk.join(',')})&tenant_id=eq.${TID}`);
      const sums = {};
      for (const l of ls) {
        sums[l.entry_id] = sums[l.entry_id] || { dr: 0, cr: 0 };
        sums[l.entry_id].dr += +l.debit_amount;
        sums[l.entry_id].cr += +l.credit_amount;
        mDR += +l.debit_amount; mCR += +l.credit_amount;
      }
      for (const s of Object.values(sums)) if (Math.abs(s.dr - s.cr) > 0.01) badJEs++;
    }
    const ok = Math.abs(mDR - mCR) < 0.01 && badJEs === 0;
    console.log(`    ${ok ? '✅' : '❌'} ${mod.padEnd(25)} DR:${mDR.toFixed(2).padStart(14)}  CR:${mCR.toFixed(2).padStart(14)}  imbalanced_JEs:${badJEs}`);
  }

  // ── 4. SALES INVOICES: posted w/o JE ────────────────────────────────────
  // Only flag invoices in states that ARE accounting events (paid, confirmed).
  // 'sent' = invoice emailed to customer, still pending — NOT a posting event.
  console.log('\n[4] CONFIRMED/PAID SALES INVOICES WITHOUT A JOURNAL ENTRY');
  const postedSales = await restAll(
    `/sales_invoices?select=invoice_number,total,status&tenant_id=eq.${TID}` +
    `&status=in.(paid,pagado,pagada,confirmed,confirmado,confirmada,posted)`
  );
  const salesJEs = await restAll(`/journal_entries?select=source_reference&source_module=eq.sales_invoices&tenant_id=eq.${TID}`);
  const salesJESet = new Set(salesJEs.map(j => j.source_reference));
  const salesMissing = postedSales.filter(i => !salesJESet.has(i.invoice_number));
  console.log(`    Posted invoices: ${postedSales.length}  With JE: ${salesJEs.length}  Missing JE: ${salesMissing.length}`);
  if (salesMissing.length) salesMissing.forEach(i => console.log(`    ❌ ${i.invoice_number} (${i.status}) total=${i.total}`));
  else console.log(`    ✅ All posted sales invoices have journal entries`);

  // ── 5. PURCHASE INVOICES: posted w/o JE ─────────────────────────────────
  console.log('\n[5] POSTED PURCHASE INVOICES WITHOUT A JOURNAL ENTRY');
  const postedPurch = await restAll(
    `/purchase_invoices?select=invoice_number,total,status&tenant_id=eq.${TID}` +
    `&status=not.in.(draft,borrador,cancelled,cancelado,cancelada,anulado,anulada)`
  );
  const purchJEs = await restAll(`/journal_entries?select=source_reference&source_module=eq.purchase_invoices&tenant_id=eq.${TID}`);
  const purchJESet = new Set(purchJEs.map(j => j.source_reference));
  const purchMissing = postedPurch.filter(i => !purchJESet.has(i.invoice_number));
  console.log(`    Posted invoices: ${postedPurch.length}  With JE: ${purchJEs.length}  Missing JE: ${purchMissing.length}`);
  if (purchMissing.length) purchMissing.forEach(i => console.log(`    ❌ ${i.invoice_number} (${i.status}) total=${i.total}`));
  else console.log(`    ✅ All posted purchase invoices have journal entries`);

  // ── 6. AR RECONCILIATION ─────────────────────────────────────────────────
  console.log('\n[6] AR RECONCILIATION (1130 account balance vs invoice open balances)');
  const arLines = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=eq.1130&tenant_id=eq.${TID}`);
  let arDR = 0, arCR = 0;
  for (const l of arLines) { arDR += +l.debit_amount; arCR += +l.credit_amount; }
  const arBalance = arDR - arCR;
  const openSalesInvs = await restAll(`/sales_invoices?select=balance&tenant_id=eq.${TID}&status=not.in.(draft,borrador,cancelled,cancelado,cancelada,anulado,anulada)`);
  const openARTotal = openSalesInvs.reduce((s, i) => s + +i.balance, 0);
  const arDiff = Math.abs(arBalance - openARTotal);
  console.log(`    1130 journal balance: ${arBalance.toFixed(2)}`);
  console.log(`    Open invoice balances: ${openARTotal.toFixed(2)}`);
  console.log(`    Difference: ${arDiff.toFixed(2)}`);
  console.log(`    ${arDiff < 1 ? '✅ AR matches open invoices' : '⚠️  AR mismatch (expected if invoices paid via payments table)'}`);

  // ── 7. AP RECONCILIATION ─────────────────────────────────────────────────
  console.log('\n[7] AP RECONCILIATION (2101/2100 account balance vs purchase open balances)');
  const apLines = await restAll(`/journal_lines?select=account_code,debit_amount,credit_amount&account_code=in.(2100,2101)&tenant_id=eq.${TID}`);
  let apDR = 0, apCR = 0;
  for (const l of apLines) { apDR += +l.debit_amount; apCR += +l.credit_amount; }
  const apBalance = apCR - apDR; // AP is a liability: normal balance is credit
  const openPurchInvs = await restAll(`/purchase_invoices?select=balance&tenant_id=eq.${TID}&status=not.in.(draft,borrador,cancelled,cancelado,cancelada,anulado,anulada)`);
  const openAPTotal = openPurchInvs.reduce((s, i) => s + +i.balance, 0);
  const apDiff = Math.abs(apBalance - openAPTotal);
  console.log(`    2100/2101 journal balance (CR-DR): ${apBalance.toFixed(2)}`);
  console.log(`    Open purchase invoice balances: ${openAPTotal.toFixed(2)}`);
  console.log(`    Difference: ${apDiff.toFixed(2)}`);
  console.log(`    ${apDiff < 1 ? '✅ AP matches open invoices' : '⚠️  AP mismatch (expected if invoices paid via payments table)'}`);

  // ── 8. IVA / TAX ACCOUNTS ────────────────────────────────────────────────
  console.log('\n[8] IVA / TAX ACCOUNT BALANCES');
  const taxAccounts = ['2150', '2120', '2110'];
  for (const code of taxAccounts) {
    const ls = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=eq.${code}&tenant_id=eq.${TID}`);
    let dr = 0, cr = 0;
    for (const l of ls) { dr += +l.debit_amount; cr += +l.credit_amount; }
    const bal = cr - dr;
    const label = code === '2150' ? 'IVA Débito Fiscal (Sales IVA owed)' :
                  code === '2120' ? 'IVA Crédito Fiscal (Purchase IVA claimable)' :
                                   'IVA Débito (alt code)';
    console.log(`    ${code} ${label}: CR-DR = ${bal.toFixed(2)}  (${ls.length} lines)`);
  }
  const ivaDebitoLines = await restAll(`/journal_lines?select=credit_amount,debit_amount&account_code=in.(2150,2110)&tenant_id=eq.${TID}`);
  const ivaCreditoLines = await restAll(`/journal_lines?select=credit_amount,debit_amount&account_code=eq.2120&tenant_id=eq.${TID}`);
  let ivaDebNet = 0, ivaCreditNet = 0;
  for (const l of ivaDebitoLines) ivaDebNet += +l.credit_amount - +l.debit_amount;
  for (const l of ivaCreditoLines) ivaCreditNet += +l.credit_amount - +l.debit_amount;
  const netIVA = ivaDebNet - ivaCreditNet;
  console.log(`    Net IVA payable to SII: ${(ivaDebNet + ivaCreditNet).toFixed(2)} (Débito ${ivaDebNet.toFixed(2)} claimed ${(-ivaCreditNet).toFixed(2)})`);

  // ── 9. PAYROLL ACCOUNTS ──────────────────────────────────────────────────
  console.log('\n[9] PAYROLL ACCOUNTS (6101-xx)');
  const payrollAccts = await restAll(`/accounts?select=code,name&code=like.6101*&tenant_id=eq.${TID}&order=code.asc`);
  let totalPayrollExpense = 0;
  for (const acct of payrollAccts) {
    const ls = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=eq.${acct.code}&tenant_id=eq.${TID}`);
    const dr = ls.reduce((s, l) => s + +l.debit_amount, 0);
    const cr = ls.reduce((s, l) => s + +l.credit_amount, 0);
    totalPayrollExpense += dr - cr;
    console.log(`    ${acct.code} ${acct.name.padEnd(35)} expense: ${(dr - cr).toFixed(2)}`);
  }
  console.log(`    Total payroll expense recorded: ${totalPayrollExpense.toFixed(2)}`);
  // Cross-check: paid expenses with reference starting 'Semana' or 'Nómina'
  const payrollExpenses = await restAll(`/expenses?select=total,payment_status,balance&tenant_id=eq.${TID}&category=eq.payroll`);
  const paidPayroll = payrollExpenses.filter(e => e.payment_status === 'paid');
  const paidPayrollTotal = paidPayroll.reduce((s, e) => s + +e.total, 0);
  console.log(`    Payroll expenses (paid): ${paidPayroll.length} records, total: ${paidPayrollTotal.toFixed(2)}`);
  if (Math.abs(totalPayrollExpense - paidPayrollTotal) < 1)
    console.log(`    ✅ Payroll journal matches expense records`);
  else
    console.log(`    ⚠️  Payroll journal vs expense records diff: ${(totalPayrollExpense - paidPayrollTotal).toFixed(2)}`);

  // ── 10. CASH / BANK ACCOUNTS ────────────────────────────────────────────
  console.log('\n[10] CASH & BANK ACCOUNT BALANCES');
  const cashAccts = await restAll(`/accounts?select=code,name&code=like.110_&tenant_id=eq.${TID}&order=code.asc`);
  for (const acct of cashAccts) {
    const ls = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=eq.${acct.code}&tenant_id=eq.${TID}`);
    const dr = ls.reduce((s, l) => s + +l.debit_amount, 0);
    const cr = ls.reduce((s, l) => s + +l.credit_amount, 0);
    console.log(`    ${acct.code} ${acct.name.padEnd(40)} balance: ${(dr - cr).toFixed(2)}`);
  }

  // ── 11. RETAINED EARNINGS vs NET INCOME ────────────────────────────────
  console.log('\n[11] INCOME vs EXPENSE SUMMARY (accrual)');
  const incomeLines = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=like.4*&tenant_id=eq.${TID}`);
  const cogsLines   = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=like.5*&tenant_id=eq.${TID}`);
  const opexLines   = await restAll(`/journal_lines?select=debit_amount,credit_amount&account_code=like.6*&tenant_id=eq.${TID}`);
  const totalIncome = incomeLines.reduce((s, l) => s + +l.credit_amount - +l.debit_amount, 0);
  const totalCOGS   = cogsLines.reduce((s, l) => s + +l.debit_amount - +l.credit_amount, 0);
  const totalOpex   = opexLines.reduce((s, l) => s + +l.debit_amount - +l.credit_amount, 0);
  const grossProfit = totalIncome - totalCOGS;
  const netIncome   = grossProfit - totalOpex;
  console.log(`    Total Income (4xxx):        ${totalIncome.toFixed(2)}`);
  console.log(`    Cost of Goods Sold (5xxx):  ${totalCOGS.toFixed(2)}`);
  console.log(`    Gross Profit:               ${grossProfit.toFixed(2)}`);
  console.log(`    Operating Expenses (6xxx):  ${totalOpex.toFixed(2)}`);
  console.log(`    Net Income:                 ${netIncome.toFixed(2)}`);

  console.log('\n' + '='.repeat(70));
  console.log('  HEALTH CHECK COMPLETE');
  console.log('='.repeat(70));
}

main().catch(console.error);
