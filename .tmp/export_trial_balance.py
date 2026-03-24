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


def fetch_all(path: str, page_size: int = 1000):
    rows = []
    offset = 0
    while True:
        separator = '&' if '?' in path else '?'
        page = fetch(f'{path}{separator}limit={page_size}&offset={offset}')
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def main() -> None:
    accounts = fetch_all(
        f'/accounts?tenant_id=eq.{TENANT_ID}'
        '&select=id,code,name,type,category,is_active&order=code'
    )
    posted_entries = fetch_all(
        f'/journal_entries?tenant_id=eq.{TENANT_ID}'
        '&status=eq.posted&select=id'
    )
    posted_ids = {row['id'] for row in posted_entries}
    journal_lines = fetch_all(
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
    totals = {
        'asset': 0.0,
        'liability': 0.0,
        'equity': 0.0,
        'income': 0.0,
        'expense': 0.0,
    }

    for account in accounts:
        balance = balances_by_account.get(account['id'], {'debits': 0.0, 'credits': 0.0})
        if account['type'] in {'asset', 'expense'}:
            amount = round(balance['debits'] - balance['credits'], 2)
        else:
            amount = round(balance['credits'] - balance['debits'], 2)

        if amount == 0:
            continue

        totals[account['type']] += amount
        rows.append(
            {
                'code': account['code'],
                'name': account['name'],
                'type': account['type'],
                'category': account['category'],
                'debits': round(balance['debits'], 2),
                'credits': round(balance['credits'], 2),
                'amount': amount,
            }
        )

    output = {
        'totals': {key: round(value, 2) for key, value in totals.items()},
        'debit_side_total': round(totals['asset'] + totals['expense'], 2),
        'credit_side_total': round(totals['liability'] + totals['equity'] + totals['income'], 2),
        'difference': round(
            (totals['asset'] + totals['expense'])
            - (totals['liability'] + totals['equity'] + totals['income']),
            2,
        ),
        'rows': rows,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()