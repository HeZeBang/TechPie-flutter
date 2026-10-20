import http.client
import importlib.util
import threading
import tempfile
import json
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('proxy', Path(__file__).resolve().parents[2] / 'tool/genai_preview_proxy.py')
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)
ORIGIN = 'http://127.0.0.1:18767'


class Response:
    status = 200

    def __init__(self, chunks=None, content_type='text/event-stream'):
        self.content_type = content_type
        self.chunks = iter(chunks or [b'{"success":true,"code":200,"result":{}}'])

    def getheader(self, name, default=None):
        return self.content_type if name == 'Content-Type' else default

    def read1(self, _size):
        return next(self.chunks, b'')


class Upstream:
    def __init__(self, response):
        self.response = response
        self.request_args = None
        self.closed = False

    def request(self, *args, **kwargs):
        self.request_args = (args, kwargs)

    def getresponse(self):
        return self.response

    def close(self):
        self.closed = True


class ProxyTest(unittest.TestCase):
    def setUp(self):
        self.server = proxy.PreviewServer(('127.0.0.1', 0), ORIGIN)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.client = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        self.addCleanup(self.client.close)

    def request(self, method, path, headers=None, body=None):
        self.client.request(method, path, headers=headers or {}, body=body)
        return self.client.getresponse()

    def test_foreign_origin_is_rejected_without_upstream(self):
        with patch.object(proxy.http.client, 'HTTPSConnection') as upstream:
            response = self.request('GET', '/htk/ai/aiModel/list', {'Origin': 'https://evil.example', 'X-Access-Token': 'real-token'})
            self.assertEqual(response.status, 403)
            self.assertIsNone(response.getheader('Access-Control-Allow-Origin'))
            response.read()
            upstream.assert_not_called()

    def test_preflight_permits_only_the_preview_origin(self):
        response = self.request('OPTIONS', '/htk/ai/aiModel/list', {
            'Origin': ORIGIN, 'Access-Control-Request-Method': 'GET',
            'Access-Control-Request-Headers': 'x-access-token,content-type,tenant-id'})
        self.assertEqual(response.status, 204)
        self.assertEqual(response.getheader('Access-Control-Allow-Origin'), ORIGIN)
        self.assertIn('tenant-id', response.getheader('Access-Control-Allow-Headers', ''))
        response.read()

    def test_synthetic_token_does_not_leave_process(self):
        with patch.object(proxy.http.client, 'HTTPSConnection') as upstream:
            response = self.request('GET', '/htk/ai/aiModel/list', {'X-Access-Token': 'synthetic-preview-token'})
            self.assertEqual(response.status, 401)
            response.read()
            upstream.assert_not_called()

    def test_platform_routes_are_explicit_and_signed_headers_are_forwarded(self):
        paths = ['/htk/ai/history/listByContentGroup', '/htk/ai/history/getByChatGroupId',
                 '/htk/ai-image-history/list', '/htk/ai-api-gateway/my/summary',
                 '/htk/ai-trade-order/my/list', '/htk/ai/history/delete/groupId',
                 '/htk/ai-image-history/delete']
        for path in paths:
            self.assertTrue(proxy.allowed_route('GET', path + '?pageNo=1'))
        self.assertFalse(proxy.allowed_route('POST', '/htk/ai-api-gateway/my/reset'))
        self.assertFalse(proxy.allowed_route('GET', '/htk/ai-api-gateway/my/plain'))
        connection = Upstream(Response())
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection):
            response = self.request('GET', paths[3], {'Origin': ORIGIN,
                'X-Access-Token': 'real-token', 'X-Sign': 'signature', 'X-TIMESTAMP': '20261019120000'})
            self.assertEqual(response.status, 200)
            response.read()
            self.assertEqual(connection.request_args[1]['headers']['X-Sign'], 'signature')
            self.assertEqual(connection.request_args[1]['headers']['X-TIMESTAMP'], '20261019120000')

    def test_image_request_keeps_json_accept_and_normalizes_optional_success_flag(self):
        connection = Upstream(Response([b'{"success":true,"data":[{"url":"images/test.png"}]}'], content_type='application/json'))
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection):
            response = self.request('POST', '/htk/chat/start/chat', {
                'Origin': ORIGIN, 'X-Access-Token': 'real-token', 'Accept': 'application/json', 'tenant-id': '0'}, '{"aiSecType":"1"}')
            self.assertEqual(response.status, 200)
            self.assertEqual(connection.request_args[1]['headers']['Accept'], 'application/json, text/plain, */*')
            self.assertEqual(connection.request_args[1]['headers']['tenant-id'], '0')
            self.assertEqual(response.read(), b'{"data": [{"url": "images/test.png"}]}')

    def test_unknown_routes_do_not_reach_upstream(self):
        with patch.object(proxy.http.client, 'HTTPSConnection') as upstream:
            response = self.request('POST', '/htk/chat/unknown/route', {'X-Access-Token': 'real-token'}, '{}')
            self.assertEqual(response.status, 403)
            response.read()
            upstream.assert_not_called()

    def test_fixed_upstream_and_no_cookie_forwarding(self):
        connection = Upstream(Response())
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection) as factory:
            response = self.request('GET', '/htk/ai/aiModel/list?_t=1', {
                'Origin': ORIGIN, 'X-Access-Token': 'real-token', 'Cookie': 'must-not-forward=secret'})
            self.assertEqual(response.status, 200)
            self.assertTrue(response.read())
            self.assertEqual(factory.call_args.args[0], 'genai.shanghaitech.edu.cn')
            self.assertEqual(connection.request_args[0], ('GET', '/htk/ai/aiModel/list?_t=1'))
            self.assertNotIn('Cookie', connection.request_args[1]['headers'])
            self.assertIsNotNone(factory.call_args.kwargs['context'])

    def test_stream_delivers_first_chunk_before_terminal_chunk(self):
        release = threading.Event()
        def chunks():
            yield b'data: first\n\n'
            if not release.wait(2):
                raise OSError('client never received first chunk')
            yield b'data: [DONE]\n\n'
        connection = Upstream(Response(chunks()))
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection):
            response = self.request('POST', '/htk/chat/start/chat', {'Origin': ORIGIN, 'X-Access-Token': 'real-token'}, '{}')
            try:
                self.assertEqual(response.read1(), b'data: first\n\n')
            finally:
                release.set()
            self.assertEqual(response.read(), b'data: [DONE]\n\n')

    def test_ids_bridge_returns_only_a_separate_genai_token(self):
        with patch.object(proxy, 'exchange_ids', return_value='separate.genai.token') as exchange:
            response = self.request('POST', '/preview/ids-exchange',
                {'Origin': ORIGIN, 'Content-Type': 'application/json'}, '{"cookies":"CASTGC=existing-tgc"}')
            self.assertEqual(response.status, 200)
            self.assertIn(b'separate.genai.token', response.read())
            exchange.assert_called_once_with('CASTGC=existing-tgc')

    def test_existing_techpie_binder_is_forwarded_to_techpie_only(self):
        connection = Upstream(Response())
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection) as factory:
            response = self.request('POST', '/api/auth/third-party/egate',
                {'Origin': ORIGIN, 'Content-Type': 'application/json'}, '{"account":"student","password":"private"}')
            self.assertEqual(response.status, 200)
            response.read()
            self.assertEqual(factory.call_args.args[0], 'techpie.geekpie.club')
            self.assertNotIn('X-Access-Token', connection.request_args[1]['headers'])
            self.assertIn(b'"password":"private"', connection.request_args[1]['body'])

    def test_absolute_urls_and_other_routes_are_disallowed(self):
        self.assertFalse(proxy.allowed_route('GET', 'https://evil.example/htk/ai/aiModel/list'))
        self.assertFalse(proxy.allowed_route('POST', '/htk/chat/start/chat?other=1'))
        self.assertFalse(proxy.allowed_route('GET', '/htk/user/info/../../other'))
        self.assertTrue(proxy.allowed_route('GET', '/htk/user/info/real.token?_t=1'))

    def test_static_image_forwarding_requires_no_token_and_sets_cors(self):
        connection = Upstream(Response([b'\x89PNG\r\n\x1a\n...fake'], content_type='image/png'))
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection) as factory:
            response = self.request('GET', '/sys/common/static/image15test/test.png', {'Origin': ORIGIN})
            self.assertEqual(response.status, 200)
            self.assertEqual(response.getheader('Content-Type'), 'image/png')
            self.assertEqual(response.getheader('Access-Control-Allow-Origin'), ORIGIN)
            self.assertEqual(factory.call_args.args[0], 'genaipic.shanghaitech.edu.cn')
            self.assertEqual(connection.request_args[0], ('GET', '/sys/common/static/image15test/test.png'))
            self.assertNotIn('X-Access-Token', connection.request_args[1]['headers'])

    def test_delete_image_record_is_forwarded(self):
        connection = Upstream(Response([b'{"success":true,"code":200,"message":"ok"}'], content_type='application/json'))
        with patch.object(proxy.http.client, 'HTTPSConnection', return_value=connection):
            response = self.request('DELETE', '/htk/ai-image-history/delete?id=test-123', {
                'Origin': ORIGIN, 'X-Access-Token': 'real-token', 'Accept': 'application/json'})
            self.assertEqual(response.status, 200)
            self.assertEqual(connection.request_args[0], ('DELETE', '/htk/ai-image-history/delete?id=test-123'))
            self.assertEqual(connection.request_args[1]['headers']['X-Access-Token'], 'real-token')


class ImageDiagnosticTest(unittest.TestCase):
    def test_opt_in_error_metadata_redacts_credentials_prompt_and_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'diagnostic.json'
            proxy.record_image_diagnostic(str(path), {
                'success': False, 'code': 500,
                'message': 'signature mismatch private-token private-prompt https://example.test/?token=secret sk-privatekey',
                'result': {'appKey': 'must-never-be-stored'},
            }, b'{"count":"1","chatInfo":"private-prompt","imageBase64":null,"imageBase64List":null}', 'private-token')
            raw = path.read_text()
            for secret in ['private-token', 'private-prompt', 'example.test', 'sk-privatekey', 'must-never-be-stored']:
                self.assertNotIn(secret, raw)
            data = json.loads(raw)
            self.assertEqual(data['count_type'], 'str')
            self.assertTrue(data['absent_image_input'])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


class IdsExchangeTest(unittest.TestCase):
    def test_existing_cookie_is_scoped_to_ids_not_genai(self):
        with patch.object(proxy.urllib.request, 'build_opener') as build:
            build.return_value.open.side_effect = proxy._TokenFound('separate.genai.token')
            self.assertEqual(proxy.exchange_ids('CASTGC=existing-real-tgc; session=ids'), 'separate.genai.token')
            processor = next(h for h in build.call_args.args if isinstance(h, proxy.urllib.request.HTTPCookieProcessor))
            ids = proxy.urllib.request.Request('https://ids.shanghaitech.edu.cn/authserver/login')
            genai = proxy.urllib.request.Request('https://genai.shanghaitech.edu.cn/htk/user/login')
            processor.cookiejar.add_cookie_header(ids)
            processor.cookiejar.add_cookie_header(genai)
            self.assertIn('CASTGC=existing-real-tgc', ids.get_header('Cookie'))
            self.assertIsNone(genai.get_header('Cookie'))

    def test_invalid_redirects_and_duplicate_tokens_are_rejected(self):
        for url in ['https://evil.example/?token=private',
                    'http://ids.shanghaitech.edu.cn/authserver/login',
                    'https://user:secret@genai.shanghaitech.edu.cn/',
                    'https://genai.shanghaitech.edu.cn:444/',
                    'https://genai.shanghaitech.edu.cn/?token=one&token=']:
            with self.assertRaises(proxy.IdsSessionRequired):
                proxy.checked_sso_url(url)

    def test_callback_token_is_captured_before_loading_the_page(self):
        with self.assertRaises(proxy._TokenFound) as caught:
            proxy.checked_sso_url('https://genai.shanghaitech.edu.cn/?token=genai.jwt')
        self.assertEqual(caught.exception.token, 'genai.jwt')
        self.assertNotIn('genai.jwt', str(caught.exception))

    def test_synthetic_and_malformed_cookies_never_start_sso(self):
        with patch.object(proxy.urllib.request, 'build_opener') as build:
            for cookies in ['', 'CASTGC=synthetic-token', 'CASTGC=private\r\nInjected=1']:
                with self.assertRaises(proxy.IdsSessionRequired):
                    proxy.exchange_ids(cookies)
            build.assert_not_called()

    def test_school_login_form_requires_existing_ids_reauthentication(self):
        with patch.object(proxy.urllib.request, 'build_opener') as build:
            with self.assertRaises(proxy.IdsSessionRequired):
                proxy.exchange_ids('CASTGC=expired-real-tgc')
            build.return_value.open.assert_called_once()


if __name__ == '__main__':
    unittest.main()
