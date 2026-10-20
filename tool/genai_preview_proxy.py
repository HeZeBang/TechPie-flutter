#!/usr/bin/env python3
"""Loopback-only GenAI web preview proxy; contacts upstream only on a request.

No credentials, request paths, payloads or upstream responses are logged.
Only profile, model discovery and text chat routes are permitted.
"""
import argparse
import os
import http.client
import json
import re
import ssl
import http.cookiejar
import http.cookies
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

UPSTREAM = 'genai.shanghaitech.edu.cn'
IMAGE_CDN_UPSTREAM = 'genaipic.shanghaitech.edu.cn'
TOKEN = re.compile(r'[A-Za-z0-9._~-]{1,8192}')
MAX_BODY = 32 * 1024 * 1024
AUTH_PATHS = {'/api/auth/third-party/egate', '/api/auth/mobile/send-sms', '/api/auth/renew'}


class IdsSessionRequired(Exception):
    pass


class _TokenFound(Exception):
    def __init__(self, token):
        super().__init__('GenAI credential returned')
        self.token = token


def checked_sso_url(url):
    parsed = urlsplit(url)
    try:
        valid = (parsed.scheme == 'https' and parsed.port in (None, 443) and
                 parsed.hostname in {UPSTREAM, 'ids.shanghaitech.edu.cn'} and
                 not parsed.username and not parsed.password and not parsed.fragment)
    except ValueError:
        valid = False
    if not valid:
        raise IdsSessionRequired()
    params = parse_qs(parsed.query, keep_blank_values=True)
    if parsed.hostname == UPSTREAM and parsed.path in ('', '/') and 'token' in params:
        values = params['token']
        if len(values) == 1 and TOKEN.fullmatch(values[0]):
            raise _TokenFound(values[0])
        raise IdsSessionRequired()
    return parsed


class _IdsRedirect(urllib.request.HTTPRedirectHandler):
    max_redirections = 12

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        try:
            checked_sso_url(newurl)
        except (IdsSessionRequired, _TokenFound):
            fp.close()
            raise
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class _IdsCookiePolicy(http.cookiejar.DefaultCookiePolicy):
    def return_ok(self, cookie, request):
        if cookie.name == 'CASTGC' and urlsplit(request.full_url).hostname != 'ids.shanghaitech.edu.cn':
            return False
        return super().return_ok(cookie, request)


def exchange_ids(cookies):
    if not isinstance(cookies, str) or len(cookies) > 65536 or any(ord(c) < 32 for c in cookies):
        raise IdsSessionRequired()
    parsed = http.cookies.SimpleCookie()
    try:
        parsed.load(cookies)
    except http.cookies.CookieError:
        raise IdsSessionRequired() from None
    tgc = parsed.get('CASTGC')
    if not tgc or not tgc.value or tgc.value.startswith('synthetic-'):
        raise IdsSessionRequired()
    jar = http.cookiejar.CookieJar(policy=_IdsCookiePolicy())
    for morsel in parsed.values():
        jar.set_cookie(http.cookiejar.Cookie(
            version=0, name=morsel.key, value=morsel.value,
            port=None, port_specified=False, domain='ids.shanghaitech.edu.cn',
            domain_specified=False, domain_initial_dot=False, path='/', path_specified=True,
            secure=True, expires=None, discard=True, comment=None, comment_url=None,
            rest={'HttpOnly': None}, rfc2109=False))
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(context=ssl.create_default_context()), _IdsRedirect())
    try:
        with opener.open('https://' + UPSTREAM + '/htk/user/login', timeout=30):
            raise IdsSessionRequired()
    except _TokenFound as found:
        return found.token
    except urllib.error.HTTPError:
        raise IdsSessionRequired() from None


def allowed_route(method, target):
    url = urlsplit(target)
    if url.scheme or url.netloc or url.fragment:
        return False
    if method in {'GET', 'DELETE'}:
        if url.path.startswith('/sys/common/static/'):
            return method == 'GET' and not url.query and not any(part in ('..', '.') for part in url.path.split('/'))
        return url.path in {'/htk/ai/aiModel/list', '/htk/ai/history/listByContentGroup',
            '/htk/ai/history/getByChatGroupId', '/htk/ai-image-history/list',
            '/htk/ai-api-gateway/my/summary', '/htk/ai-trade-order/my/list',
            '/htk/ai/history/delete/groupId', '/htk/ai-image-history/delete'} or bool(re.fullmatch(
            r'/htk/user/info/[A-Za-z0-9._~-]{1,8192}', url.path))
    if method == 'POST':
        if url.path == '/htk/chat/upload/chat/file':
            return not any(c in url.query for c in '<>"\n\r')
        post_paths = {'/htk/chat/start/chat', '/htk/chat/net/search',
                      '/sys/common/upload', '/htk/chat/convert2wav',
                      '/htk/chat/recognize', '/preview/ids-exchange',
                      '/htk/ai/history/delete/groupId', '/htk/ai-image-history/delete'} | AUTH_PATHS
        return url.path in post_paths and not url.query
    return False


def record_image_diagnostic(path, result, body, token):
    """Opt-in, private, redacted error metadata; never stores the response body."""
    if not path or not isinstance(result, dict):
        return
    try:
        request = json.loads(body or b'{}')
        if not isinstance(request, dict):
            request = {}
        message = result.get('message') or result.get('errMsg') or ''
        if not isinstance(message, str):
            message = ''
        for value in (token, request.get('chatInfo')):
            if isinstance(value, str) and value:
                message = message.replace(value, '[redacted]')
        message = re.sub(r'https?://[^\s]+', '[URL]', message)
        message = re.sub(r'(?i)bearer\s+\S+|sk-[A-Za-z0-9_-]+|[A-Za-z0-9._~-]{24,}', '[redacted]', message)
        metadata = {
            'success': result.get('success') is True,
            'code': result.get('code') if isinstance(result.get('code'), int) else None,
            'message': message[:1500],
            'count_type': type(request.get('count')).__name__,
            'absent_image_input': request.get('imageBase64') is None and request.get('imageBase64List') is None,
            'has_images': isinstance(result.get('data'), list) and bool(result['data']),
        }
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as out:
            json.dump(metadata, out, ensure_ascii=False)
    except (OSError, ValueError):
        pass


class PreviewServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, origin, image_diagnostics=None):
        self.image_diagnostics = image_diagnostics
        self.allowed_origin = origin
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', self.server.allowed_origin)
        self.send_header('Vary', 'Origin')
        self.send_header('Cache-Control', 'no-store')

    def _error(self, status):
        self.close_connection = True
        data = json.dumps({'success': False, 'code': status,
                           'message': 'GenAI preview proxy request failed'}).encode()
        self.send_response(status)
        if self.headers.get('Origin') == self.server.allowed_origin:
            self._cors()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(data)

    def _valid_origin(self):
        return self.headers.get('Origin') in (None, self.server.allowed_origin)

    def do_OPTIONS(self):
        requested_headers = {s.strip().lower() for s in
                             self.headers.get('Access-Control-Request-Headers', '').split(',') if s.strip()}
        if (self.headers.get('Origin') != self.server.allowed_origin or
            not allowed_route(self.headers.get('Access-Control-Request-Method'), self.path) or
            not requested_headers <= {'content-type', 'x-access-token', 'accept', 'x-sign', 'x-timestamp', 'tenant-id', 'token'}):
            self._error(403)
            return
        self.send_response(204)
        self._cors()
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Access-Token, Accept, X-Sign, X-TIMESTAMP, tenant-id, token')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        self._forward()

    def do_POST(self):
        self._forward()

    def do_DELETE(self):
        self._forward()

    def _forward(self):
        self.connection.settimeout(180)
        if not self._valid_origin() or not allowed_route(self.command, self.path):
            self._error(403)
            return
        is_pic_upload = urlsplit(self.path).path == '/sys/common/upload'
        is_static = urlsplit(self.path).path.startswith('/sys/common/static/')
        special = (urlsplit(self.path).path in AUTH_PATHS or
                   self.path == '/preview/ids-exchange' or
                   is_static or is_pic_upload)
        token = self.headers.get('X-Access-Token', '')
        if not special and (not TOKEN.fullmatch(token) or token.startswith('synthetic-')):
            self._error(401)
            return
        if self.headers.get('Transfer-Encoding'):
            self._error(400)
            return
        raw_length = self.headers.get('Content-Length', '0')
        if not raw_length.isdecimal() or int(raw_length) > MAX_BODY:
            self._error(413)
            return
        length = int(raw_length)
        if self.command in ('GET', 'DELETE') and length:
            self._error(400)
            return
        connection = None
        started = False
        try:
            body = self.rfile.read(length) if length else None
            if body is not None and len(body) != length:
                self._error(400)
                return
            if self.path == '/preview/ids-exchange':
                try:
                    data = json.loads(body or b'{}')
                    if not isinstance(data, dict):
                        raise IdsSessionRequired()
                    token = exchange_ids(data.get('cookies'))
                    encoded = json.dumps({'success': True, 'code': 200,
                                          'result': {'token': token}}).encode()
                    self.send_response(200)
                    self._cors()
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(encoded)))
                    self.end_headers()
                    self.wfile.write(encoded)
                except (IdsSessionRequired, ValueError):
                    self._error(401)
                return
            is_pic_upload = urlsplit(self.path).path == '/sys/common/upload'
            host = IMAGE_CDN_UPSTREAM if (is_static or is_pic_upload) else ('techpie.geekpie.club' if urlsplit(self.path).path in AUTH_PATHS else UPSTREAM)
            connection = http.client.HTTPSConnection(
                host, timeout=180, context=ssl.create_default_context())
            accept = self.headers.get('Accept', '')
            if is_static:
                out_accept = 'image/*,*/*'
            elif urlsplit(self.path).path == '/htk/chat/convert2wav':
                out_accept = 'audio/*,*/*'
            elif 'text/event-stream' in accept:
                out_accept = 'text/event-stream'
            else:
                out_accept = 'application/json, text/plain, */*'
            headers = {'Accept': out_accept, 'Accept-Encoding': 'identity'}
            if not is_static:
                headers['tenant-id'] = self.headers.get('tenant-id', '0')
                if is_pic_upload:
                    headers['token'] = self.headers.get('token', '2ea38f293adb4abca21132feba61eaa3')
                elif special:
                    headers.pop('X-Access-Token', None)
                else:
                    headers['X-Access-Token'] = token
                    for name in ('X-Sign', 'X-TIMESTAMP'):
                        value = self.headers.get(name)
                        if value:
                            headers[name] = value
            if self.command == 'POST':
                content_type_in = self.headers.get('Content-Type', '')
                if content_type_in.startswith('multipart/form-data'):
                    headers['Content-Type'] = content_type_in
                else:
                    headers['Content-Type'] = 'application/json'
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            if response.status != 200:
                self._error(response.status if response.status in (401, 403, 404, 429) else 502)
                return
            content_type = response.getheader('Content-Type', '').lower()
            if is_static or content_type.startswith('audio/'):
                self.send_response(200)
                self._cors()
                self.send_header('Content-Type', content_type or ('image/png' if is_static else 'audio/wav'))
                if is_static:
                    self.send_header('Cache-Control', 'public, max-age=86400')
                self.send_header('Transfer-Encoding', 'chunked')
                self.end_headers()
                started = True
                while True:
                    chunk = response.read1(8192)
                    if not chunk:
                        break
                    self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                    self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
                return
            if not content_type.startswith(('application/json', 'text/event-stream')):
                self._error(502)
                return
            if self.path == '/htk/chat/start/chat' and accept == 'application/json' and content_type.startswith('application/json'):
                image_bytes = bytearray()
                while True:
                    chunk = response.read1(4096)
                    if not chunk:
                        break
                    image_bytes.extend(chunk)
                    if len(image_bytes) > MAX_BODY:
                        self._error(502)
                        return
                result = json.loads(image_bytes)
                record_image_diagnostic(self.server.image_diagnostics, result, body, token)
                data = result.get('data') if isinstance(result, dict) else None
                print('Image upstream full response: ' + json.dumps(result, ensure_ascii=False), flush=True)
                print('Image request headers: ' + json.dumps({k: (v if k != 'X-Access-Token' else '[token]') for k, v in headers.items()}), flush=True)
                print('Image request body: ' + repr(body.decode('utf-8', 'replace') if body else None), flush=True)
                print('Image response schema: ' + json.dumps({
                    'has_data': isinstance(data, list),
                    'has_url': bool(isinstance(data, list) and data and isinstance(data[0], dict) and 'url' in data[0]),
                    'has_result': isinstance(result, dict) and 'result' in result,
                    'success': result.get('success') if isinstance(result, dict) and isinstance(result.get('success'), bool) else None,
                    'code': result.get('code') if isinstance(result, dict) and isinstance(result.get('code'), int) else None,
                }), flush=True)
                # The earlier loaded preview expects the documented raw image
                # form. Preserve failures; normalize only successful data arrays.
                if isinstance(result, dict) and isinstance(data, list) and result.get('success') is not False and result.get('code') in (None, 0, 200):
                    image_bytes = json.dumps({'data': data}, ensure_ascii=False).encode()
                self.send_response(200)
                self._cors()
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(image_bytes)))
                self.end_headers()
                self.wfile.write(image_bytes)
                return
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', content_type)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            started = True
            while True:
                chunk = response.read1(4096)
                if not chunk:
                    break
                self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                self.wfile.flush()
            self.wfile.write(b'0\r\n\r\n')
            self.wfile.flush()
        except (OSError, ValueError, http.client.HTTPException, ssl.SSLError):
            self.close_connection = True
            if not started:
                try:
                    self._error(502)
                except OSError:
                    pass
        finally:
            if connection:
                connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18768)
    parser.add_argument('--origin', default='http://127.0.0.1:18767')
    parser.add_argument('--image-diagnostics', help='Optional private file for redacted image error metadata')
    args = parser.parse_args()
    origin = urlsplit(args.origin)
    if (origin.scheme != 'http' or origin.hostname != '127.0.0.1' or
        not origin.port or origin.username or origin.password or
        origin.path or origin.query or origin.fragment):
        parser.error('--origin must be an exact loopback HTTP origin with a port')
    server = PreviewServer(('127.0.0.1', args.port), args.origin, args.image_diagnostics)
    print(f'GenAI preview proxy listening on 127.0.0.1:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
