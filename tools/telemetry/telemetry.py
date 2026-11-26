#!/usr/bin/env python3
"""Collect anonymous TechPie events and report local aggregate measurements."""
import argparse
import csv
import json
import sqlite3
import sys
from contextlib import closing
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from reports import make_report
from storage import MAX_BODY, connect, import_installs, ingest, initialize, is_ms


class CollectorServer(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        print('Collector request interrupted', file=sys.stderr)


def unique_fields(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError('Duplicate field')
    return result


class Collector(BaseHTTPRequestHandler):
    timeout = 10

    def log_message(self, *_):
        # The standard request log includes peer addresses and the raw request target.
        pass

    def respond(self, status):
        self.send_response(status)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_OPTIONS(self):
        self.respond(204 if self.path == '/api/telemetry' else 404)

    def do_POST(self):
        if self.path != '/api/telemetry':
            return self.respond(404)
        if 'Cookie' in self.headers or 'Authorization' in self.headers:
            return self.respond(400)
        if self.headers.get_content_type() != 'application/json':
            return self.respond(415)
        lengths = self.headers.get_all('Content-Length', [])
        if 'Transfer-Encoding' in self.headers or len(lengths) != 1:
            return self.respond(411)
        if not lengths[0].isascii() or not lengths[0].isdigit():
            return self.respond(400)
        if len(lengths[0]) > 5 or int(lengths[0]) > MAX_BODY:
            return self.respond(413)
        try:
            body = self.rfile.read(int(lengths[0]))
            if len(body) != int(lengths[0]):
                return self.respond(400)
            batch = json.loads(body.decode('utf-8'), object_pairs_hook=unique_fields)
            with closing(connect(self.server.db_path)) as db:
                ingest(db, batch)
        except (ValueError, RecursionError):
            return self.respond(400)
        except TimeoutError:
            return self.respond(408)
        except sqlite3.OperationalError:
            return self.respond(503)
        self.respond(204)


def as_of(value):
    try:
        stamp = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if stamp.tzinfo is not None:
            utc_value = stamp.astimezone(timezone.utc)
            delta = utc_value - datetime(1970, 1, 1, tzinfo=timezone.utc)
            millis = (delta.days * 86_400 + delta.seconds) * 1000 + delta.microseconds // 1000
            if is_ms(millis):
                return millis
    except (ValueError, OverflowError):
        pass
    raise argparse.ArgumentTypeError('Use ISO 8601 with a timezone from 1970 UTC, e.g. 2026-11-25T00:00:00Z')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True, help='SQLite file for events and store aggregates')
    commands = parser.add_subparsers(dest='command', required=True)
    serve = commands.add_parser('serve')
    serve.add_argument('--host', default='127.0.0.1')
    serve.add_argument('--port', type=int, default=8787)
    report = commands.add_parser('report')
    report.add_argument('--as-of', type=as_of, help='Event-time cutoff (inclusive)')
    importer = commands.add_parser('import-installs')
    importer.add_argument('csv_file')
    args = parser.parse_args()
    with closing(connect(args.db)) as db:
        initialize(db)
        if args.command == 'report':
            cutoff = args.as_of if args.as_of is not None else int(datetime.now(timezone.utc).timestamp() * 1000)
            db.execute('BEGIN')  # Consistent read across every metric under concurrent ingest.
            print(json.dumps(make_report(db, cutoff), indent=2))
            return
        if args.command == 'import-installs':
            try:
                with open(args.csv_file, newline='', encoding='utf-8-sig') as source:
                    import_installs(db, source)
            except (csv.Error, OSError, ValueError) as error:
                parser.error(str(error))
            return
    with CollectorServer((args.host, args.port), Collector) as server:
        server.db_path = args.db
        print(f'Listening at {args.host}:{server.server_port}/api/telemetry', flush=True)
        server.serve_forever()


if __name__ == '__main__':
    main()
