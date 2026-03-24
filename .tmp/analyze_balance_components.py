import json
import urllib.request
from pathlib import Path


ROOT = Path('/Users/Claudio/Dev/bikeshop-erp')
BASE_URL = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1'
TENANT_ID = '5443b130-cc28-45af-a420-cd500b288890'


def load_service_role_key() -> str:
    for line in (ROOT / '.env').read_text().splitlines():
        if line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
            return line.split('=', 1)[1].strip()
    raise RuntimeError('SUPABASE_SERVICE_ROLE_KEY not found in .env')


SERVICE_ROLE_KEY = load_service_role_key()
HEADERS = {
    'apikey': SERVICE_ROLE_KEY,
    'Authorization': f'Bearer {SERVICE_ROLE_KEY}',
}


def fetch(path: str):
    request = urllib.request.Request(f'{BASE_URL}{path}', headers=HEADERS)
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def main() -> None:
    accounts = fetch(
        f'/accounts?tenant_id=eq.{TENANT_ID}'
        '&select=id,code,name,type,category,is_active&order=code'
    )
    posted_entries = fetch(
        f'/journal_entries?tenant_id=eq.{TENANT_ID}'
        '&status=eq.posted&select=id'
    )
    posted_ids = {row['id'] for row in posted_entries}
    journal_lines = fetch(
        f'/journal_lines?tenant_id=eq.{TENANT_ID}'
        '&select=entry_id,account_id,debit_amount,credit_amount'
    )

    balances_by_account = {}
    for line in journal_lines:
        if line['entry_id'] not in posted_ids:
            continue
        account_balance = balances_by_account.setdefault(
            line['account_id'],
            {'debits': 0.0, 'credits': 0.0},
        )
        account_balance['debits'] += float(line.get('debit_amount') or 0)
        account_balance['credits'] += float(line.get('credit_amount') or 0)

    rows = []
    for account in accounts:
        totals = balances_by_account.get(account['id'], {'debits': 0.0, 'credits': 0.0})
        if account['type'] in {'asset', 'expense'}:
            amount = round(totals['debits'] - totals['credits'], 2)
        else:
            amount = round(totals['credits'] - totals['debits'], 2)

        if amount == 0:
            continue

        rows.append(
            {
                'code': account['code'],
                'name': account['name'],
                'type': account['type'],
                'category': account['category'],
                'amount': amount,
                'debits': round(totals['debits'], 2),
                'credits': round(totals['credits'], 2),
            }
        )

    summary = {
        'equity_accounts': [row for row in rows if row['type'] == 'equity'],
        'negative_asset_accounts': [row for row in rows if row['type'] == 'asset' and row['amount'] < 0],
        'negative_liability_accounts': [row for row in rows if row['type'] == 'liability' and row['amount'] < 0],
        'top_asset_accounts': sorted(
            [row for row in rows if row['type'] == 'asset'],
            key=lambda row: abs(row['amount']),
            reverse=True,
        )[:15],
        'top_liability_accounts': sorted(
            [row for row in rows if row['type'] == 'liability'],
            key=lambda row: abs(row['amount']),
            reverse=True,
        )[:15],
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()