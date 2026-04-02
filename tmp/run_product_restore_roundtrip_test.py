import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        values[key.strip()] = value.strip()
    return values


def request_json(base_url: str, method: str, endpoint: str, headers: dict[str, str] | None = None, payload=None):
    request = urllib.request.Request(base_url + endpoint, method=method)
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    body = None
    if payload is not None:
        body = json.dumps(payload).encode('utf-8')
        request.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(request, data=body) as response:
            raw = response.read().decode('utf-8')
            return response.status, dict(response.headers), json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode('utf-8')
        try:
            parsed = json.loads(raw) if raw else None
        except Exception:
            parsed = raw
        raise RuntimeError(f'HTTP {error.code} {method} {endpoint}: {parsed}') from error


def main() -> None:
    env = load_env(ROOT / '.env')
    base_url = env.get('SUPABASE_URL', 'https://xzdvtzdqjeyqxnkqprtf.supabase.co')
    anon_key = env.get('SUPABASE_ANON_KEY')
    service_role_key = env.get('SUPABASE_SERVICE_ROLE_KEY')
    if not anon_key:
        seed_script = (ROOT / 'scripts/seed_bikes_wheels.py').read_text()
        match = re.search(r'SUPABASE_KEY\s*=\s*"([^"]+)"', seed_script)
        if not match:
            raise RuntimeError('SUPABASE_ANON_KEY not found in .env or scripts/seed_bikes_wheels.py')
        anon_key = match.group(1)
    if not service_role_key:
        raise RuntimeError('SUPABASE_SERVICE_ROLE_KEY not found in .env')

    launch = json.loads((ROOT / '.vscode/launch.json').read_text())
    args = launch['configurations'][0]['args']
    email = next(arg.split('=', 1)[1] for arg in args if arg.startswith('--dart-define=DEBUG_EMAIL='))
    password = next(arg.split('=', 1)[1] for arg in args if arg.startswith('--dart-define=DEBUG_PASSWORD='))

    _, _, auth_data = request_json(
        base_url,
        'POST',
        '/auth/v1/token?grant_type=password',
        headers={'apikey': anon_key},
        payload={'email': email, 'password': password},
    )
    access_token = auth_data['access_token']
    user_id = auth_data['user']['id']

    user_headers = {
        'apikey': anon_key,
        'Authorization': f'Bearer {access_token}',
        'Prefer': 'return=representation',
    }
    admin_headers = {
        'apikey': service_role_key,
        'Authorization': f'Bearer {service_role_key}',
        'Prefer': 'return=representation',
    }

    _, _, profiles = request_json(
        base_url,
        'GET',
        f'/rest/v1/user_profiles?user_id=eq.{user_id}&select=tenant_id',
        headers=user_headers,
    )
    if not profiles:
        raise RuntimeError('No user_profiles row found for authenticated user')
    tenant_id = profiles[0]['tenant_id']

    stamp = int(time.time())
    sku = f'TEST-RSTR-{stamp}'
    name = f'TEST Restore Roundtrip {stamp}'

    product_payload = {
        'tenant_id': tenant_id,
        'name': name,
        'sku': sku,
        'price': 19990,
        'cost': 10000,
        'inventory_qty': 3,
        'stock_quantity': 3,
        'min_stock_level': 0,
        'max_stock_level': 10,
        'purchase_treatment': 'inventory',
        'product_type': 'product',
        'track_stock': True,
        'category': 'other',
        'category_name': 'TEST',
        'description': 'Temporary roundtrip test product for workshop consumable restore validation.',
        'unit': 'unit',
        'is_active': False,
        'is_published': False,
    }

    _, _, inserted = request_json(
        base_url,
        'POST',
        '/rest/v1/products',
        headers=user_headers,
        payload=product_payload,
    )
    product = inserted[0]
    product_id = product['id']

    _, _, convert_result = request_json(
        base_url,
        'POST',
        '/rest/v1/rpc/convert_product_inventory_to_non_stock',
        headers=user_headers,
        payload={
            'p_product_id': product_id,
            'p_target_purchase_treatment': 'workshop_consumable',
            'p_target_product_type': 'product',
            'p_reason': f'Test conversion {stamp}',
        },
    )

    _, _, restore_result = request_json(
        base_url,
        'POST',
        '/rest/v1/rpc/restore_product_conversion_state',
        headers=user_headers,
        payload={
            'p_product_id': product_id,
            'p_reason': f'Test restore {stamp}',
            'p_restore_inventory': True,
        },
    )

    _, _, product_check = request_json(
        base_url,
        'GET',
        f'/rest/v1/products?id=eq.{product_id}&select=id,tenant_id,sku,name,purchase_treatment,product_type,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level,is_active,is_published',
        headers=admin_headers,
    )

    _, _, adjustments = request_json(
        base_url,
        'GET',
        f'/rest/v1/stock_adjustments?product_id=eq.{product_id}&tenant_id=eq.{tenant_id}&select=id,adjustment_type,quantity,stock_before,stock_after,reason,reference,created_at&order=created_at.asc',
        headers=admin_headers,
    )

    convert_entry_id = convert_result.get('journal_entry_id')
    restore_entry_id = restore_result.get('journal_entry_id')

    def fetch_lines(entry_id: str | None):
        if not entry_id:
            return []
        _, _, lines = request_json(
            base_url,
            'GET',
            f'/rest/v1/journal_lines?entry_id=eq.{entry_id}&select=entry_id,account_code,account_name,debit_amount,credit_amount,description&order=account_code.asc',
            headers=admin_headers,
        )
        return lines

    convert_lines = fetch_lines(convert_entry_id)
    restore_lines = fetch_lines(restore_entry_id)

    _, _, activity_candidates = request_json(
        base_url,
        'GET',
        '/rest/v1/user_activity_log?select=action,details,created_at&order=created_at.desc&limit=100',
        headers=admin_headers,
    )
    activity_logs = [
        {
            'action': row['action'],
            'created_at': row['created_at'],
            'details': row['details'],
        }
        for row in activity_candidates
        if str((row.get('details') or {}).get('product_id', '')) == product_id
    ]

    summary = {
        'authenticated_user_id': user_id,
        'tenant_id': tenant_id,
        'created_product': {
            'id': product_id,
            'sku': sku,
            'name': name,
        },
        'convert_result': convert_result,
        'restore_result': restore_result,
        'product_after_restore': product_check[0] if product_check else None,
        'stock_adjustments': adjustments,
        'convert_journal_lines': convert_lines,
        'restore_journal_lines': restore_lines,
        'activity_logs': activity_logs,
    }

    out_path = ROOT / 'tmp' / f'product_restore_roundtrip_{stamp}.json'
    out_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False))

    print(json.dumps({
        'result_file': str(out_path),
        'product_id': product_id,
        'sku': sku,
        'convert_journal_entry_id': convert_entry_id,
        'restore_journal_entry_id': restore_entry_id,
        'final_purchase_treatment': product_check[0]['purchase_treatment'] if product_check else None,
        'final_product_type': product_check[0]['product_type'] if product_check else None,
        'final_inventory_qty': product_check[0]['inventory_qty'] if product_check else None,
        'final_stock_quantity': product_check[0]['stock_quantity'] if product_check else None,
        'stock_adjustment_count': len(adjustments),
        'activity_log_count': len(activity_logs),
    }, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
