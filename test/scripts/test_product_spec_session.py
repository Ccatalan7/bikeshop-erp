"""The preparatory transport uses an existing actor and only declared reads."""
import base64
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse

SPEC = importlib.util.spec_from_file_location('spec_session', Path(__file__).resolve().parents[2] / 'scripts/inventory/product_spec_session.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReadSessionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = 'abcdefghijklmnopqrst'
        self.origin = f'https://{self.project}.supabase.co'
        self.actor = 'synthetic-actor'
        (self.root / 'supabase/.temp').mkdir(parents=True)
        (self.root / 'supabase/.temp/project-ref').write_text(self.project)
        config = self.root / 'lib/shared/config/supabase_config.dart'
        config.parent.mkdir(parents=True)
        config.write_text("static const String url = String.fromEnvironment('url', defaultValue: '%s');\nstatic const String anonKey = String.fromEnvironment('anonKey', defaultValue: 'synthetic-public-key');" % self.origin)
        self.bundle = 'com.vinabike.vinabikeErp.debug'
        self.prefs = self.root / 'Library/Containers' / self.bundle / 'Data/Library/Preferences' / f'{self.bundle}.plist'
        self.prefs.parent.mkdir(parents=True)
        self.claims = {'sub': self.actor, 'iss': self.origin + '/auth/v1', 'exp': time.time() + 300}
        self.store()
        self.calls = []

        def open_request(request, timeout):
            self.calls.append(request)
            data = {'id': self.actor, 'role': 'authenticated'} if request.full_url.endswith('/auth/v1/user') else {'result': 'synthetic'}
            return io.BytesIO(json.dumps(data).encode())

        self.opener = type('FakeOpener', (), {})()
        self.opener.open = open_request
        self.addCleanup(patch.stopall)
        patch.object(MODULE.Path, 'home', return_value=self.root).start()
        patch.object(MODULE.urllib.request, 'build_opener', return_value=self.opener).start()

    def store(self):
        claims = base64.urlsafe_b64encode(json.dumps(self.claims).encode()).rstrip(b'=').decode()
        self.token = 'synthetic.' + claims + '.signature'
        self.prefs.write_bytes(plistlib.dumps({f'flutter.sb-{self.project}-auth-token': json.dumps({'access_token': self.token, 'refresh_token': 'never-used'})}))

    def test_server_validates_actor_before_any_spec_read(self):
        client = MODULE.ProductSpecSession(self.root)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0].full_url, self.origin + '/auth/v1/user')
        self.assertEqual(self.calls[0].method, 'GET')
        self.assertEqual(client.actor_id, self.actor)
        self.assertEqual(client.read('get_product_spec_contexts_v1', {'p_product_ids': []}), {'result': 'synthetic'})
        self.assertEqual(self.calls[1].full_url, self.origin + '/rest/v1/rpc/get_product_spec_contexts_v1')
        self.assertEqual(self.calls[1].method, 'POST')

    def test_writer_or_arbitrary_path_cannot_reach_http(self):
        client = MODULE.ProductSpecSession(self.root)
        for command in ['save_product_with_specs_v1', 'record_product_spec_reading_v1', '../auth/v1/token', 'https://unrelated.invalid']:
            with self.assertRaises(MODULE.SessionUnavailable):
                client.read(command, {})
            with self.assertRaises(MODULE.SessionUnavailable):
                client._request('/rest/v1/rpc/' + command, {})
        self.assertEqual(len(self.calls), 1)

    def test_wrong_project_or_expired_session_never_contacts_server(self):
        for delta in [{'iss': 'https://foreign.invalid/auth/v1'}, {'exp': time.time() - 1}]:
            original = dict(self.claims)
            self.claims.update(delta)
            self.store()
            with self.assertRaises(MODULE.SessionUnavailable):
                MODULE.ProductSpecSession(self.root)
            self.assertFalse(self.calls)
            self.claims = original

    def test_identity_mismatch_is_rejected(self):
        self.opener.open = lambda *_args, **_kwargs: io.BytesIO(b'{"id":"another-actor","role":"authenticated"}')
        with self.assertRaises(MODULE.SessionUnavailable):
            MODULE.ProductSpecSession(self.root)

    def test_http_error_cannot_echo_credentials(self):
        client = MODULE.ProductSpecSession(self.root)
        def fail(*_args, **_kwargs):
            raise urllib.error.HTTPError(self.origin, 401, self.token, {'Authorization': self.token}, io.BytesIO(self.token.encode()))
        self.opener.open = fail
        with self.assertRaises(MODULE.SessionUnavailable) as result:
            client.read('get_product_spec_contexts_v1', {})
        self.assertEqual(str(result.exception), 'Authenticated request failed (HTTP 401)')
        self.assertNotIn(self.token, str(result.exception))

    def test_redirect_is_rejected_before_forwarding_authorization(self):
        with self.assertRaises(MODULE.SessionUnavailable):
            MODULE.NoRedirect().redirect_request(None, None, 307, 'redirect', {}, 'https://unrelated.invalid')

    def test_metadata_uses_fixed_projection_get_and_exact_ids(self):
        client = MODULE.ProductSpecSession(self.root)
        template_id = '11111111-1111-4111-8111-111111111111'
        client.read_template_metadata([template_id])
        request = self.calls[-1]
        url = urllib.parse.urlsplit(request.full_url)
        self.assertEqual(url.path, '/rest/v1/spec_templates')
        self.assertEqual(urllib.parse.parse_qs(url.query), {
            'select': [MODULE.TEMPLATE_METADATA_SELECT],
            'id': ['in.(' + template_id + ')'], 'order': ['key']})
        self.assertEqual(request.method, 'GET')
        self.assertIsNone(request.data)

    def test_metadata_cannot_inject_filters_or_use_foreign_paths(self):
        client = MODULE.ProductSpecSession(self.root)
        valid = '11111111-1111-4111-8111-111111111111'
        for ids in [[], [valid, valid], [valid + ')&select=*'], [None], [valid] * 106]:
            with self.assertRaises(MODULE.SessionUnavailable):
                client.read_template_metadata(ids)
        for path in ['/rest/v1/products', '/rest/v1/rpc/save_product_with_specs_v1',
                     'https://foreign.invalid/spec_templates']:
            with self.assertRaises(MODULE.SessionUnavailable):
                client._request(path, {'ids': [valid]}, metadata_read=True)
        with self.assertRaises(MODULE.SessionUnavailable):
            client._request('/rest/v1/spec_templates', {'ids': [valid], 'select': '*'}, metadata_read=True)
        self.assertEqual(len(self.calls), 1)


if __name__ == '__main__':
    unittest.main()
