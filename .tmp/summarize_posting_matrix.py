import json
import urllib.request
from collections import defaultdict
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
    entries = fetch_all(
        f'/journal_entries?tenant_id=eq.{TENANT_ID}'
        '&status=eq.posted&select=id,source_module,type'
    )
    entry_meta = {entry['id']: entry for entry in entries}

    lines = fetch_all(
        f'/journal_lines?tenant_id=eq.{TENANT_ID}'
        '&select=entry_id,account_code,account_name,debit_amount,credit_amount'
    )

    by_module_account = defaultdict(lambda: {'debits': 0.0, 'credits': 0.0, 'account_name': ''})
    module_totals = defaultdict(lambda: {'debits': 0.0, 'credits': 0.0})

    for line in lines:
        entry = entry_meta.get(line['entry_id'])
        if entry is None:
            continue
        source_module = entry.get('source_module') or 'null'
        account_code = line.get('account_code') or 'NO_CODE'
        key = (source_module, account_code)
        by_module_account[key]['debits'] += float(line.get('debit_amount') or 0)
        by_module_account[key]['credits'] += float(line.get('credit_amount') or 0)
        by_module_account[key]['account_name'] = line.get('account_name') or ''
        module_totals[source_module]['debits'] += float(line.get('debit_amount') or 0)
        module_totals[source_module]['credits'] += float(line.get('credit_amount') or 0)

    output = {
        'module_totals': {
            module: {
                'debits': round(totals['debits'], 2),
                'credits': round(totals['credits'], 2),
            }
            for module, totals in sorted(module_totals.items())
        },
        'module_account_rows': [
            {
                'source_module': module,
                'account_code': account_code,
                'account_name': data['account_name'],
                'debits': round(data['debits'], 2),
                'credits': round(data['credits'], 2),
                'net_debit_minus_credit': round(data['debits'] - data['credits'], 2),
            }
            for (module, account_code), data in sorted(by_module_account.items())
        ],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()