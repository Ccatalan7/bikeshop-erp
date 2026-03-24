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
    "&select=id,expense_number,reference,notes,posting_status,payment_status,balance,total_amount,liability_account_id,payment_account_id,payment_method_id,paid_at,created_at"
    "&order=created_at.desc&limit=20"
)

expense_ids = [row['id'] for row in expenses]
payments = []
if expense_ids:
    payments = fetch(
        f"expense_payments?tenant_id=eq.{TENANT}&expense_id=in.({','.join(expense_ids)})"
        "&select=id,expense_id,amount,payment_date,payment_account_id,payment_method_id,created_at"
        "&order=created_at.desc&limit=50"
    )

jes = fetch(
    f"journal_entries?tenant_id=eq.{TENANT}&source_module=eq.expense_payments"
    "&description=like.Pago%20gasto%20GTO-%25"
    "&select=id,entry_date,description,source_reference,total_debit,total_credit,created_at"
    "&order=entry_date.desc&limit=30"
)

je_ids = [row['id'] for row in jes]
lines = []
if je_ids:
    lines = fetch(
        f"journal_lines?tenant_id=eq.{TENANT}&entry_id=in.({','.join(je_ids)})"
        "&select=entry_id,account_code,account_name,debit_amount,credit_amount"
        "&order=created_at.asc"
    )

lines_by_entry = {}
for line in lines:
    lines_by_entry.setdefault(line['entry_id'], []).append(line)

print('=== PAYROLL EXPENSES ===')
print(json.dumps(expenses, indent=2, ensure_ascii=False))
print('=== PAYMENTS ===')
print(json.dumps(payments, indent=2, ensure_ascii=False))
print('=== PAYMENT_JES ===')
print(json.dumps([
    {
        'id': row['id'],
        'entry_date': row['entry_date'],
        'description': row['description'],
        'source_reference': row['source_reference'],
        'lines': lines_by_entry.get(row['id'], []),
    }
    for row in jes
], indent=2, ensure_ascii=False))
