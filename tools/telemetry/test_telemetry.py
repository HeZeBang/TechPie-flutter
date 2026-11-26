import argparse
import csv
import http.client
import io
import itertools
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import closing

from reports import DAY, make_report
from storage import FEATURES, LAST_MS, MAX_BODY, connect, import_installs, ingest, initialize
from telemetry import Collector, CollectorServer, as_of

MONDAY = as_of('2026-11-02T00:00:00Z')
CLI = pathlib.Path(__file__).with_name('telemetry.py')


def token(n):
    return f'{n:032x}'


class MetricsTest(unittest.TestCase):
    def setUp(self):
        self.db = connect(':memory:')
        self.addCleanup(self.db.close)
        initialize(self.db)
        self.ids = itertools.count(1)

    def emit(self, install, kind, at, **extra):
        entry = dict(id=token(next(self.ids)), kind=kind, at=at, version='1.1.0+32',
                     platform='linux')
        entry.update(extra)
        ingest(self.db, {'installation': token(install), 'events': [entry]})

    def test_candidate_versions_and_timestamp_limits(self):
        self.emit(1, 'first_launch', 0, version='1.1.0-rc.1+32')
        self.emit(2, 'recording_open', LAST_MS, version='1.1.0-rc.2', visit=token(1))
        self.assertEqual(make_report(self.db, 0)['adoption']['participating_first_launches'], 1)
        report = make_report(self.db, as_of('9999-12-31T23:59:59.999Z'))
        self.assertEqual(report['recordings']['by_version_platform'][0]['version'], '1.1.0-rc.2')
        for invalid in ('1.1.0-rc.+32', '1.1.0-rc.1234567', '1.1.0-rc.1+hello',
                        '1.1.0-rc.1+1234567890123', '1.1.0-private', '1.1.0-rc.1@host'):
            with self.subTest(version=invalid), self.assertRaises(ValueError):
                self.emit(1, 'app_open', MONDAY, version=invalid)
        for cutoff in ('0001-01-01T00:00:00+01:00', '1969-12-31T23:59:59Z',
                       '9999-12-31T23:59:59-01:00', '2026-11-25'):
            with self.subTest(cutoff=cutoff), self.assertRaises(argparse.ArgumentTypeError):
                as_of(cutoff)

    def test_login_and_activity_boundaries(self):
        end = MONDAY + 32 * DAY
        self.emit(1, 'first_launch', MONDAY)
        self.emit(1, 'first_launch', MONDAY + DAY)
        self.emit(1, 'first_login', MONDAY + 7 * DAY)
        self.emit(2, 'first_launch', MONDAY + 2 * DAY)
        self.emit(2, 'first_login', MONDAY + 9 * DAY + 1)
        self.emit(3, 'app_open', end - 30 * DAY + 1)
        self.emit(3, 'app_open', end)
        self.emit(4, 'first_launch', end - DAY)
        self.emit(4, 'first_login', end + 1)
        self.emit(5, 'app_open', end + 1)
        adoption = make_report(self.db, end)['adoption']
        self.assertEqual(adoption['participating_first_launches'], 3)
        self.assertEqual(adoption['active_installations_30d'], 2)
        complete, provisional = adoption['first_login_cohorts']
        self.assertEqual((complete['week_start'], complete['first_login_within_7d'],
                          complete['first_login_percent'], complete['status']),
                         ('2026-11-02', 1, 50, 'complete'))
        self.assertEqual((provisional['status'], provisional['fully_observed_installations'],
                          provisional['first_login_within_7d']), ('provisional', 0, 0))

    def test_feature_day_and_registry(self):
        for install, at, feature in [(1, MONDAY, 'home'), (1, MONDAY, 'home'),
                                     (2, MONDAY, 'home'), (1, MONDAY, 'grades'),
                                     (1, MONDAY + DAY, 'home')]:
            self.emit(install, 'feature_open', at, feature=feature)
        rows = make_report(self.db, MONDAY + DAY)['daily_features']
        self.assertEqual([(r['day'], r['feature'], r['installations']) for r in rows],
                         [('2026-11-02', 'grades', 1), ('2026-11-02', 'home', 2),
                          ('2026-11-03', 'home', 1)])
        registry = CLI.parents[2] / 'lib/models/feature.dart'
        self.assertTrue(
            set(re.findall(r"\bid: '([a-z_]+)'", registry.read_text(encoding='utf-8'))) <= FEATURES
        )

    def test_feedback_out_of_order_unconfirmed_retry_and_late_delivery(self):
        for form in range(1, 6):
            self.emit(1, 'feedback_open', MONDAY, visit=token(form))
        self.emit(2, 'feedback_open', MONDAY + 2, visit=token(1))
        self.emit(1, 'feedback_success', MONDAY + DAY, visit=token(1))
        self.emit(1, 'feedback_failure', MONDAY + 2, visit=token(1))
        self.emit(1, 'feedback_attempt', MONDAY + 1, visit=token(1))
        self.emit(1, 'feedback_success', MONDAY + DAY + 1, visit=token(1))
        self.emit(1, 'feedback_attempt', MONDAY + DAY, visit=token(2))
        self.emit(1, 'feedback_failure', MONDAY + DAY, visit=token(3))
        self.emit(1, 'feedback_attempt', MONDAY + DAY + 1, visit=token(4))
        self.emit(1, 'feedback_success', MONDAY + DAY + 1, visit=token(4))
        result = make_report(self.db, MONDAY + DAY + 1)['feedback']
        self.assertEqual(result, {
            'forms_opened': 6, 'forms_delivered': 2, 'failed_submission_responses': 2,
            'under_24h': 1, 'delivered_within_24h': 1,
            'undelivered_at_24h_no_attempt': 2, 'undelivered_at_24h_failed_or_unconfirmed': 2,
        })

    def test_recording_boundaries_states_percentiles_and_affected_installs(self):
        def record(install, visit, kind, elapsed=None, version='1.1.0+32'):
            self.emit(install, 'recording_' + kind, MONDAY + (elapsed or 0), visit=token(visit),
                      version=version, **({} if elapsed is None else {'elapsed': elapsed}))

        for form in range(1, 5):
            record(1, form, 'open')
            record(1, form, 'exit', 30_000)
        record(1, 1, 'error', 10_000)
        record(1, 1, 'ready', 2000)
        record(1, 1, 'ready', 3000)
        record(1, 2, 'error', 1000)
        record(1, 3, 'ready', 4000)
        record(1, 4, 'error', 30_001)
        record(2, 5, 'open', version='1.2.0')
        record(2, 5, 'error', 10_001, version='1.2.0')
        record(2, 5, 'exit', 30_001, version='1.2.0')
        self.emit(3, 'recording_open', MONDAY + DAY, visit=token(1), platform='android')
        result = make_report(self.db, MONDAY + DAY)['recordings']
        total = result['all']
        self.assertEqual(total['visits'], 6)
        self.assertEqual((total['error_within_10s'], total['installations_with_early_error'],
                          total['error_within_10s_percent']), (2, 1, 33.333))
        self.assertEqual((total['visits_with_error'], total['exit_within_30s'],
                          total['exit_within_30s_percent']), (3, 4, 66.667))
        self.assertEqual((total['error_window_still_open'], total['exit_window_still_open']), (1, 1))
        self.assertEqual(total['early_exits_by_state'],
                         dict(ready_only=1, error_only=1, ready_and_error=1, neither=1))
        self.assertEqual((total['median_load_ms'], total['p95_load_ms']), (3000, 3900))
        self.assertEqual(len(result['by_version_platform']), 3)
        for group in result['by_version_platform']:
            if group['version'] == '1.2.0':
                self.assertEqual(group['visits_with_error_percent'], 100)
                self.assertIsNone(group['p95_load_ms'])

    def test_csv_atomic_import_corrections_and_cutoff(self):
        header = 'day,distributor,platform,installs\n'
        day1 = '2026-11-02,campus,android,'
        import_installs(self.db, io.StringIO(header + day1 + '3\n'))
        with self.assertRaises(ValueError):
            import_installs(self.db, io.StringIO(header + day1 + '5\ninvalid\n'))
        self.assertEqual(self.db.execute('SELECT installs FROM store_install').fetchone()[0], 3)
        import_installs(self.db, io.StringIO(header + day1 + '4\n2026-11-03,campus,android,0\n'))
        store = make_report(self.db, MONDAY + DAY - 1)['adoption']['store_installs']
        self.assertEqual(store, [dict(day='2026-11-02', distributor='campus', platform='android', installs=4)])
        self.assertEqual(make_report(self.db, MONDAY)['adoption']['store_installs'], [])


class HttpTest(unittest.TestCase):
    def test_collector_persists_retries_and_reports_via_cli(self):
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / 'events.sqlite'
            with closing(connect(path)) as db:
                initialize(db)
            with CollectorServer(('127.0.0.1', 0), Collector) as server:
                server.db_path = path
                thread = threading.Thread(target=server.serve_forever)
                thread.start()
                try:
                    def post(body, **headers):
                        with closing(http.client.HTTPConnection(*server.server_address)) as client:
                            client.request('POST', '/api/telemetry', body,
                                           {'Content-Type': 'application/json', **headers})
                            return client.getresponse().status

                    event = dict(id=token(1), kind='first_launch', at=MONDAY, version='1.1.0+32', platform='ios')
                    batch = {'installation': token(2), 'events': [event]}
                    self.assertEqual(post(json.dumps(batch)), 204)
                    self.assertEqual(post(json.dumps(batch)), 204)
                    self.assertEqual(post(json.dumps(batch), Cookie='session=redacted'), 400)
                    self.assertEqual(post(b' ' * (MAX_BODY + 1)), 413)
                    self.assertEqual(post(json.dumps({**batch, 'events': [event] * 101})), 400)
                    for bad in (dict(studentId='123'), dict(feature='grades'), dict(kind='feedback_open'),
                                dict(at=True), dict(kind='feature_open', feature='private'),
                                dict(kind='recording_exit', visit=token(1), elapsed=-1)):
                        events = [{**event, 'id': token(3)}, {**event, **bad}]
                        self.assertEqual(post(json.dumps({**batch, 'events': events})), 400)
                    self.assertEqual(post(b'{"events":[],"events":[]}'), 400)
                    for malformed in (b'\xff', b'[]', b'null', b'[' * 1200 + b']' * 1200):
                        self.assertEqual(post(malformed), 400)
                    for wrong_type in (dict(kind=[]), dict(platform={}), dict(version=None)):
                        self.assertEqual(post(json.dumps({**batch, 'events': [{**event, **wrong_type}]})), 400)
                finally:
                    server.shutdown()
                    thread.join()
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM event').fetchone()[0], 1)
            csv_file = pathlib.Path(temp) / 'installs.csv'
            with csv_file.open('w', newline='') as target:
                writer = csv.writer(target)
                writer.writerows([['day', 'distributor', 'platform', 'installs'],
                                  ['2026-11-02', 'sample', 'ios', 6]])
            subprocess.run([sys.executable, CLI, '--db', path, 'import-installs', csv_file], check=True)
            output = subprocess.check_output([sys.executable, CLI, '--db', path, 'report', '--as-of',
                                              '2026-11-03T00:00:00Z'])
            report = json.loads(output)
            self.assertEqual(report['adoption']['active_installations_30d'], 1)
            self.assertEqual(report['adoption']['store_installs'][0]['installs'], 6)
            self.assertNotIn(token(2).encode(), output)


if __name__ == '__main__':
    unittest.main()
