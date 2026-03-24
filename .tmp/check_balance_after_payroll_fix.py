import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

TENANT = '5443b130-cc28-45af-a420-cd500b288890'
BASE = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1'
ENV_PATH = Path('/Users/Claudio/Dev/bikeshop-erp/.env')
PAGE_SIZE = 1000


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


def fetch_paged(path_prefix: str):
    rows = []
    offset = 0
    while True:
        path = f"{path_prefix}&limit={PAGE_SIZE}&offset={offset}"
        batch = fetch(path)
        rows.extend(batch)
        if len(batch) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return rows


accounts = fetch(
    f"accounts?tenant_id=eq.{TENANT}&type=in.(asset,liability,equity)&is_active=eq.true"
    "&select=id,code,name,type,category"
    "&order=code"
)
account_map = {row['id']: row for row in accounts}
account_ids = set(account_map.keys())

posted_entries = fetch_paged(
    f"journal_entries?tenant_id=eq.{TENANT}&status=eq.posted&select=id"
)
posted_entry_ids = {row['id'] for row in posted_entries}

journal_lines = fetch_paged(
    f"journal_lines?tenant_id=eq.{TENANT}&select=entry_id,account_id,debit_amount,credit_amount"
)

balances = {}
for line in journal_lines:
    if line['entry_id'] not in posted_entry_ids:
        continue
    account_id = line['account_id']
    if account_id not in account_ids:
        continue
    account = account_map[account_id]
    bucket = balances.setdefault(account_id, {
        'code': account['code'],
        'name': account['name'],
        'type': account['type'],
        'debits': 0.0,
        'credits': 0.0,
    })
    bucket['debits'] += float(line['debit_amount'])
    bucket['credits'] += float(line['credit_amount'])

for bucket in balances.values():
    if bucket['type'] == 'asset':
        bucket['amount'] = round(bucket['debits'] - bucket['credits'], 2)
    else:
        bucket['amount'] = round(bucket['credits'] - bucket['debits'], 2)

assets = round(sum(v['amount'] for v in balances.values() if v['type'] == 'asset'), 2)
liabilities = round(sum(v['amount'] for v in balances.values() if v['type'] == 'liability'), 2)
equity = round(sum(v['amount'] for v in balances.values() if v['type'] == 'equity'), 2)
diff = round(assets - (liabilities + equity), 2)

liability_equity_accounts = sorted(
    [v for v in balances.values() if v['type'] in ('liability', 'equity') and abs(v['amount']) > 0.005],
    key=lambda x: (-abs(x['amount']), x['code'])
)

print(json.dumps({
    'total_assets': assets,
    'total_liabilities': liabilities,
    'total_equity': equity,
    'accounting_equation_difference': diff,
    'top_liability_equity_accounts': liability_equity_accounts[:20],
}, indent=2, ensure_ascii=False))
