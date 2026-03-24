import json
from pathlib import Path
from urllib.request import Request, urlopen

TENANT = '5443b130-cc28-45af-a420-cd500b288890'
BASE = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1'
ENV_PATH = Path('/Users/Claudio/Dev/bikeshop-erp/.env')


def load_key() -> str:
    for line in ENV_PATH.read_text().splitlines():
        if line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
            return line.split('=', 1)[1].strip().strip('"').strip("'")
    raise RuntimeError('SUPABASE_SERVICE_ROLE_KEY missing')


KEY = load_key()
HEADERS = {
    'apikey': KEY,
    'Authorization': f'Bearer {KEY}',
    'Accept': 'application/json',
}


def fetch(path: str):
    req = Request(f'{BASE}/{path}', headers=HEADERS)
    with urlopen(req) as resp:
        return json.load(resp)


expenses = fetch(
    f"expenses?tenant_id=eq.{TENANT}&reference=ilike.Semana%25"
    "&select=id,expense_number,reference,notes,total_amount,created_at&limit=500"
)
expense_numbers = [row['expense_number'] for row in expenses]

expense_jes = fetch(
    f"journal_entries?tenant_id=eq.{TENANT}&source_module=eq.expenses&source_reference=in.({','.join(expense_numbers)})"
    "&select=id,source_reference,description,entry_date&limit=500"
) if expense_numbers else []
expense_je_ids = [row['id'] for row in expense_jes]
expense_lines = fetch(
    f"journal_lines?tenant_id=eq.{TENANT}&entry_id=in.({','.join(expense_je_ids)})"
    "&select=entry_id,account_code,account_name,debit_amount,credit_amount&limit=4000"
) if expense_je_ids else []

expense_lines_by_entry = {}
for row in expense_lines:
    expense_lines_by_entry.setdefault(row['entry_id'], []).append(row)

wrong_expense_entries = []
corrected_expense_entries = []
for je in expense_jes:
    lines = expense_lines_by_entry.get(je['id'], [])
    wrong_credits = [
        line for line in lines
        if line['credit_amount'] > 0 and line['account_code'] in ('1101', '1110', '2105')
    ]
    payroll_credit_2106 = [
        line for line in lines
        if line['credit_amount'] > 0 and line['account_code'] == '2106'
    ]
    if wrong_credits:
        wrong_expense_entries.append({
            'source_reference': je['source_reference'],
            'description': je['description'],
            'wrong_credits': wrong_credits,
        })
    if payroll_credit_2106:
        corrected_expense_entries.append({
            'source_reference': je['source_reference'],
            'description': je['description'],
            'credit_2106': payroll_credit_2106,
        })

payment_jes = fetch(
    f"journal_entries?tenant_id=eq.{TENANT}&source_module=eq.expense_payments"
    "&description=like.Pago%20gasto%20GTO-%25"
    "&select=id,description,source_reference,entry_date&limit=500"
)
payment_je_ids = [row['id'] for row in payment_jes]
payment_lines = fetch(
    f"journal_lines?tenant_id=eq.{TENANT}&entry_id=in.({','.join(payment_je_ids)})"
    "&select=entry_id,account_code,account_name,debit_amount,credit_amount&limit=4000"
) if payment_je_ids else []

payment_lines_by_entry = {}
for row in payment_lines:
    payment_lines_by_entry.setdefault(row['entry_id'], []).append(row)

payment_2106_debits = []
invalid_payment_refs = []
for je in payment_jes:
    lines = payment_lines_by_entry.get(je['id'], [])
    debit_2106 = [
        line for line in lines
        if line['debit_amount'] > 0 and line['account_code'] == '2106'
    ]
    if debit_2106:
        payment_2106_debits.append({
            'description': je['description'],
            'source_reference': je['source_reference'],
            'debit_2106': debit_2106,
        })
    if isinstance(je['source_reference'], str) and je['source_reference'].startswith('GTO-'):
        invalid_payment_refs.append({
            'description': je['description'],
            'source_reference': je['source_reference'],
        })

posted_entries = fetch(
    f"journal_entries?tenant_id=eq.{TENANT}&status=eq.posted"
    "&select=id&limit=4000"
)
posted_entry_ids = {row['id'] for row in posted_entries}

all_2106_lines = fetch(
    f"journal_lines?tenant_id=eq.{TENANT}&account_code=eq.2106"
    "&select=debit_amount,credit_amount,entry_id&limit=4000"
)

posted_2106_lines = [
    row for row in all_2106_lines
    if row['entry_id'] in posted_entry_ids
]

total_2106_debits = sum(row['debit_amount'] for row in posted_2106_lines)
total_2106_credits = sum(row['credit_amount'] for row in posted_2106_lines)
net_2106 = total_2106_credits - total_2106_debits

print(json.dumps({
    'wrong_expense_entry_count': len(wrong_expense_entries),
    'corrected_expense_entry_count': len(corrected_expense_entries),
    'payment_2106_debit_count': len(payment_2106_debits),
    'invalid_payment_source_reference_count': len(invalid_payment_refs),
    'total_2106_debits': total_2106_debits,
    'total_2106_credits': total_2106_credits,
    'net_2106': net_2106,
    'sample_corrected_expenses': corrected_expense_entries[:10],
    'sample_invalid_payment_refs': invalid_payment_refs[:10],
    'sample_payment_2106_debits': payment_2106_debits[:10],
}, indent=2, ensure_ascii=False))
