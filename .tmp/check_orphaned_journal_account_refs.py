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
        '&select=id,code,name,type,tenant_id'
    )
    account_ids = {account['id'] for account in accounts}

    posted_entries = fetch_all(
        f'/journal_entries?tenant_id=eq.{TENANT_ID}'
        '&status=eq.posted&select=id'
    )
    posted_ids = {entry['id'] for entry in posted_entries}

    journal_lines = fetch_all(
        f'/journal_lines?tenant_id=eq.{TENANT_ID}'
        '&select=id,entry_id,account_id,debit_amount,credit_amount'
    )

    orphaned = {}
    for line in journal_lines:
        if line['entry_id'] not in posted_ids:
            continue
        if line['account_id'] in account_ids:
            continue

        group = orphaned.setdefault(
            line['account_id'],
            {
                'debits': 0.0,
                'credits': 0.0,
                'lines': [],
            },
        )
        group['debits'] += float(line.get('debit_amount') or 0)
        group['credits'] += float(line.get('credit_amount') or 0)
        if len(group['lines']) < 20:
            group['lines'].append(
                {
                    'journal_line_id': line['id'],
                    'entry_id': line['entry_id'],
                    'debit_amount': float(line.get('debit_amount') or 0),
                    'credit_amount': float(line.get('credit_amount') or 0),
                }
            )

    output = {
        'orphaned_account_count': len(orphaned),
        'orphaned_accounts': [
            {
                'account_id': account_id,
                'debits': round(data['debits'], 2),
                'credits': round(data['credits'], 2),
                'net_debit_minus_credit': round(data['debits'] - data['credits'], 2),
                'sample_lines': data['lines'],
            }
            for account_id, data in orphaned.items()
        ],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()