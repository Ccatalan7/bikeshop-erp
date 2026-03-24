import json
import urllib.request
from collections import Counter
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
        '&status=eq.posted&select=id,entry_number,entry_date,type,source_module,source_reference,description'
        '&order=entry_date.asc'
    )

    source_counts = Counter((entry.get('source_module') or 'null') for entry in entries)

    interesting_entries = []
    interesting_types = {'manual', 'opening_balance', 'initial_balance', 'adjustment', 'migration', 'null'}
    for entry in entries:
        source_module = entry.get('source_module') or 'null'
        if source_module in interesting_types:
            interesting_entries.append(entry)

    output = {
        'total_posted_entries': len(entries),
        'source_type_counts': dict(sorted(source_counts.items())),
        'first_25_entries': entries[:25],
        'interesting_entries': interesting_entries[:100],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()