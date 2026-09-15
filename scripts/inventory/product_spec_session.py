#!/usr/bin/env python3
"""Read product commands through the live macOS Debug user's real session.

No SQL, session refresh, credential output, login, or product writes. This is
the authenticated read transport for preparing/reviewing catalogue proposals;
the eventual applicator must have its own reviewed command and global gate.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from uuid import UUID


READ_COMMANDS = {
    'get_product_spec_research_snapshot_v1',
    'get_product_spec_research_snapshot_v2',
    'preview_product_spec_research_v1',
    'get_product_spec_snapshot_v1',
    'get_product_spec_bindings_v1',
    'get_product_spec_editor_context_v1',
    'get_product_spec_editor_context_v2',
    'get_product_spec_editor_context_v3',
    'get_product_spec_member_profiles_v1',
    'get_product_spec_member_template_v1',
    'get_product_spec_contexts_v1',
    'get_product_spec_typed_configurations_v1',
    'get_product_ids_for_spec_family_v1',
    'get_product_spec_references_v1',
    'get_product_spec_references_v2',
}

# Fixed projection for publication read-back. Callers choose only exact UUIDs;
# they cannot select other tables, columns, filters, or a write method.
TEMPLATE_METADATA_SELECT = (
    'id,tenant_id,key,name,technical_family,form_contract,is_active,contract_version,'
    'fields:spec_template_fields(id,tenant_id,template_id,spec_definition_id,'
    'section_key,sort_order,is_required,visibility_rules,option_rules,constraint_rules,'
    'definition:spec_definitions(id,tenant_id,key,label,data_type,unit,allowed_values,'
    'validation_rules,is_customer_visible,is_compatibility_relevant,'
    'options:spec_definition_values(id,tenant_id,spec_definition_id,code,label,sort_order,is_active)))')


class SessionUnavailable(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise SessionUnavailable('Authenticated requests cannot redirect')


class ProductSpecSession:
    def __init__(self, root: Path):
        project = (root / 'supabase/.temp/project-ref').read_text().strip()
        if not re.fullmatch(r'[a-z]{20}', project):
            raise SessionUnavailable('Invalid linked project identity')
        self._origin = f'https://{project}.supabase.co'
        config = (root / 'lib/shared/config/supabase_config.dart').read_text()

        def default(field):
            match = re.search(r'static const String ' + field +
                              r'\s*=\s*String.fromEnvironment\((.*?)\);', config, re.S)
            value = re.search(r"defaultValue:\s*'([^']*)'", match.group(1)) if match else None
            if not value:
                raise SessionUnavailable('Public client configuration unavailable')
            return value.group(1)

        if default('url') != self._origin:
            raise SessionUnavailable('Client and linked project disagree')
        self._api_key = default('anonKey')
        bundle = 'com.vinabike.vinabikeErp.debug'
        prefs = (Path.home() / 'Library/Containers' / bundle /
                 'Data/Library/Preferences' / f'{bundle}.plist')
        stored = plistlib.loads(prefs.read_bytes()).get(f'flutter.sb-{project}-auth-token')
        if not isinstance(stored, str):
            raise SessionUnavailable('Debug session is unavailable')
        session = json.loads(stored)
        token = session.get('access_token')
        if not isinstance(token, str) or len(token.split('.')) != 3:
            raise SessionUnavailable('Debug access session is unavailable')
        segment = token.split('.')[1]
        claims = json.loads(base64.urlsafe_b64decode(segment + '=' * (-len(segment) % 4)))
        # These are routing/expiry checks only. /auth/v1/user verifies the JWT.
        if claims.get('iss') != self._origin + '/auth/v1':
            raise SessionUnavailable('Stored session belongs to another project')
        if not isinstance(claims.get('exp'), (int, float)) or claims['exp'] <= time.time() + 30:
            raise SessionUnavailable('Debug session needs its normal app refresh')
        self._token = token
        self._opener = urllib.request.build_opener(NoRedirect())
        user = self._request('/auth/v1/user')
        if not user.get('id') or user.get('id') != claims.get('sub') or user.get('role') != 'authenticated':
            raise SessionUnavailable('Server did not confirm the Debug actor')
        self.actor_id = user['id']
        self.project = project
        self.expires_at = claims['exp']

    def _request(self, path, params=None, *, metadata_read=False):
        is_actor_check = path == '/auth/v1/user' and params is None
        is_spec_read = (isinstance(params, dict) and
                        path in {'/rest/v1/rpc/' + name for name in READ_COMMANDS})
        if metadata_read:
            ids = params.get('ids') if isinstance(params, dict) else None
            if (path != '/rest/v1/spec_templates' or set(params or {}) != {'ids'}
                    or not isinstance(ids, list) or not 1 <= len(ids) <= 105):
                raise SessionUnavailable('Metadata reads require exact template IDs')
            try:
                if any(not isinstance(value, str) or str(UUID(value)) != value for value in ids):
                    raise ValueError('Noncanonical UUID')
            except (ValueError, AttributeError, TypeError):
                raise SessionUnavailable('Metadata reads require canonical UUIDs') from None
            if len(set(ids)) != len(ids):
                raise SessionUnavailable('Metadata reads require unique IDs')
            path += '?' + urllib.parse.urlencode({
                'select': TEMPLATE_METADATA_SELECT,
                'id': 'in.(' + ','.join(ids) + ')', 'order': 'key'})
            params = None
        elif not is_actor_check and not is_spec_read:
            raise SessionUnavailable('Only actor verification and declared spec reads are available')
        request = urllib.request.Request(
            self._origin + path,
            data=None if params is None else json.dumps(params).encode(),
            headers={'apikey': self._api_key, 'Authorization': 'Bearer ' + self._token,
                     'Content-Type': 'application/json'},
            method='GET' if params is None else 'POST')
        try:
            with self._opener.open(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Never print headers, request objects, session values or bodies.
            raise SessionUnavailable(f'Authenticated request failed (HTTP {error.code})') from None
        except (urllib.error.URLError, TimeoutError):
            raise SessionUnavailable('Authenticated request could not complete') from None

    def read(self, command, params):
        if command not in READ_COMMANDS or not isinstance(params, dict):
            raise SessionUnavailable('Only declared read commands are available')
        return self._request('/rest/v1/rpc/' + command, params)

    def read_template_metadata(self, template_ids):
        return self._request('/rest/v1/spec_templates', {'ids': template_ids},
                             metadata_read=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['probe', 'read'])
    parser.add_argument('--command', choices=sorted(READ_COMMANDS))
    parser.add_argument('--params', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    client = ProductSpecSession(Path(__file__).resolve().parents[2])
    if args.action == 'probe':
        print(json.dumps({'authenticated': True, 'actor_id': client.actor_id,
                          'project': client.project, 'expires_at': client.expires_at}))
        return
    if not args.command or not args.params or not args.output:
        parser.error('read requires --command, --params and --output')
    result = client.read(args.command, json.loads(args.params.read_text()))
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({'authenticated': True, 'actor_id': client.actor_id,
                      'command': args.command, 'output': str(args.output)}))


if __name__ == '__main__':
    try:
        main()
    except SessionUnavailable as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, TypeError, KeyError):
        print('Session/configuration/output could not be processed', file=sys.stderr)
        sys.exit(1)
