"""SQLite storage and input contracts for TechPie telemetry."""
import csv
import re
import sqlite3
from datetime import date

ID = re.compile(r'[0-9a-f]{32}')
VERSION = re.compile(r'[0-9]{1,6}(?:\.[0-9]{1,6}){2}(?:-rc\.[0-9]{1,6})?(?:\+[0-9]{1,12})?')
PLATFORMS = set('android ios linux windows macos ohos web fuchsia unknown'.split())
FEATURES = set('''
    home schedule deadlines settings profile campus_services feedback
    elrc_recordings ecourse student_leave campus_card oa_gym egate_xshd study_plan
    blackboard student_allowance grades course_catalog pnp_minor academic_certificates
    more holiday_travel campus_jobs counseling
'''.split())
BASE = {'id', 'kind', 'at', 'version', 'platform'}
EXTRAS = {
    **dict.fromkeys(('first_launch', 'app_open', 'first_login'), set()),
    'feature_open': {'feature'},
    **dict.fromkeys(('feedback_open', 'feedback_attempt', 'feedback_success',
                     'feedback_failure', 'recording_open'), {'visit'}),
    **dict.fromkeys(('recording_ready', 'recording_error', 'recording_exit'),
                    {'visit', 'elapsed'}),
}
MAX_BODY = 65536
MAX_BATCH = 100
LAST_MS = 253402300799999  # Last millisecond of year 9999 UTC.


def connect(path):
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    return db


def initialize(db):
    db.execute('PRAGMA journal_mode=WAL')
    db.executescript("""
        CREATE TABLE IF NOT EXISTS event (
            installation TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
            at INTEGER NOT NULL, version TEXT NOT NULL, platform TEXT NOT NULL,
            visit TEXT, elapsed INTEGER, feature TEXT, PRIMARY KEY (installation, id)
        ) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS event_kind_time ON event(kind, at);
        CREATE INDEX IF NOT EXISTS event_login ON event(installation, at)
            WHERE kind = 'first_login';
        CREATE INDEX IF NOT EXISTS event_visit ON event(installation, visit, at)
            WHERE visit IS NOT NULL;
        CREATE TABLE IF NOT EXISTS store_install (
            day TEXT NOT NULL, distributor TEXT NOT NULL, platform TEXT NOT NULL,
            installs INTEGER NOT NULL, PRIMARY KEY(day, distributor, platform)
        ) WITHOUT ROWID;
    """)


def matches(value, pattern):
    return isinstance(value, str) and bool(pattern.fullmatch(value))


def is_ms(value):
    return type(value) is int and 0 <= value <= LAST_MS


def ingest(db, batch):
    if not isinstance(batch, dict) or batch.keys() != {'installation', 'events'}:
        raise ValueError('Invalid envelope')
    installation, events = batch['installation'], batch['events']
    if not matches(installation, ID) or not isinstance(events, list) or not 1 <= len(events) <= MAX_BATCH:
        raise ValueError('Invalid installation or batch size')

    rows = []
    for e in events:
        if not isinstance(e, dict) or not isinstance(e.get('kind'), str):
            raise ValueError('Invalid event')
        extra = EXTRAS.get(e['kind'])
        if extra is None or e.keys() != BASE | extra:
            raise ValueError('Invalid event fields')
        if not (matches(e['id'], ID) and matches(e['version'], VERSION) and is_ms(e['at'])
                and isinstance(e['platform'], str) and e['platform'] in PLATFORMS):
            raise ValueError('Invalid event values')
        if 'feature' in extra and not (isinstance(e['feature'], str) and e['feature'] in FEATURES):
            raise ValueError('Unknown feature')
        if 'visit' in extra and not matches(e['visit'], ID):
            raise ValueError('Invalid visit')
        if 'elapsed' in extra and not is_ms(e['elapsed']):
            raise ValueError('Invalid elapsed time')
        rows.append((installation, e['id'], e['kind'], e['at'], e['version'],
                     e['platform'], e.get('visit'), e.get('elapsed'), e.get('feature')))
    with db:
        db.executemany("""
            INSERT INTO event VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(installation, id) DO NOTHING
        """, rows)


def import_installs(db, source):
    reader = csv.DictReader(source)
    if reader.fieldnames != ['day', 'distributor', 'platform', 'installs']:
        raise ValueError('Expected CSV header day,distributor,platform,installs')
    with db:
        for row in reader:
            day, distributor, platform, installs = [row[key] or '' for key in reader.fieldnames]
            if (None in row or not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', day)
                    or not re.fullmatch(r'[a-z][a-z0-9_-]{0,39}', distributor)
                    or platform not in PLATFORMS or not re.fullmatch(r'[0-9]{1,12}', installs)):
                raise ValueError(f'Invalid store aggregate at CSV line {reader.line_num}')
            date.fromisoformat(day)
            db.execute("""
                INSERT INTO store_install VALUES (?, ?, ?, ?)
                ON CONFLICT(day, distributor, platform) DO UPDATE SET installs=excluded.installs
            """, (day, distributor, platform, int(installs)))
