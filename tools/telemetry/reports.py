"""Event-time aggregates. All timestamps and calendar windows use UTC."""
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from math import floor

DAY = 86_400_000


def utc(ms):
    return datetime(1970, 1, 1, tzinfo=timezone.utc) + timedelta(milliseconds=ms)


def percent(count, total):
    return round(100 * count / total, 3) if total else None


def adoption(db, cutoff):
    weeks = {}
    launches = db.execute("""
        WITH firsts AS (
            SELECT installation, min(at) AS launch FROM event
            WHERE kind = 'first_launch' AND at <= ? GROUP BY installation
        )
        SELECT launch, EXISTS (
            SELECT 1 FROM event e WHERE e.installation = f.installation
                AND e.kind = 'first_login' AND e.at BETWEEN launch AND min(launch + ?, ?)
        ) AS logged_in FROM firsts f ORDER BY launch
    """, (cutoff, 7 * DAY, cutoff))
    for launch, logged_in in launches:
        week = launch - launch % DAY - utc(launch).weekday() * DAY
        if week not in weeks:
            weeks[week] = {
                'week_start': utc(week).date().isoformat(),
                'status': 'complete' if cutoff >= week + 14 * DAY - 1 else 'provisional',
                'first_launches': 0, 'first_login_within_7d': 0, 'fully_observed_installations': 0,
            }
        row = weeks[week]
        row['first_launches'] += 1
        row['first_login_within_7d'] += logged_in
        row['fully_observed_installations'] += launch + 7 * DAY <= cutoff
    for row in weeks.values():
        row['first_login_percent'] = percent(row['first_login_within_7d'], row['first_launches'])
    active = db.execute("""
        SELECT count(DISTINCT installation) FROM event
        WHERE kind IN ('first_launch', 'app_open') AND at > ? AND at <= ?
    """, (cutoff - 30 * DAY, cutoff)).fetchone()[0]
    # Complete distributor days only; each row is the distributor's daily total.
    last_complete_day = utc(cutoff + 1 - DAY).date().isoformat()
    stores = db.execute("""
        SELECT day, distributor, platform, installs FROM store_install WHERE day <= ?
        ORDER BY day, distributor, platform
    """, (last_complete_day,))
    return {
        'store_installs': [dict(row) for row in stores],
        'participating_first_launches': sum(row['first_launches'] for row in weeks.values()),
        'first_login_cohorts': list(weeks.values()), 'active_installations_30d': active,
    }


def visits(db, feature, cutoff, columns):
    # The first open defines each visit even if the client sends several open events.
    # Rows are joined by source timestamps, so arbitrary upload order is safe.
    return db.execute(f"""
        WITH opens AS (
            SELECT *, row_number() OVER (
                PARTITION BY installation, visit ORDER BY at, id
            ) AS occurrence FROM event WHERE kind = ? AND at <= ?
        )
        SELECT o.installation, o.at, o.version, o.platform, {columns}
        FROM opens o LEFT JOIN event e ON e.installation = o.installation
            AND e.visit = o.visit AND e.at BETWEEN o.at AND ?
        WHERE o.occurrence = 1 GROUP BY o.installation, o.visit
        ORDER BY o.version, o.platform
    """, (feature + '_open', cutoff, cutoff))


def feedback(db, cutoff):
    counts = dict.fromkeys((
        'forms_opened', 'forms_delivered', 'failed_submission_responses',
        'under_24h', 'delivered_within_24h', 'undelivered_at_24h_no_attempt',
        'undelivered_at_24h_failed_or_unconfirmed',
    ), 0)
    for row in visits(db, 'feedback', cutoff, """
        min(CASE WHEN e.kind = 'feedback_success' THEN e.at END) AS success,
        min(CASE WHEN e.kind IN ('feedback_attempt', 'feedback_failure') THEN e.at END) AS attempt,
        sum(CASE WHEN e.kind = 'feedback_failure' THEN 1 ELSE 0 END) AS errors
    """):
        counts['forms_opened'] += 1
        counts['forms_delivered'] += row['success'] is not None
        counts['failed_submission_responses'] += row['errors']
        deadline = row['at'] + DAY
        if cutoff < deadline:
            counts['under_24h'] += 1
        elif row['success'] is not None and row['success'] <= deadline:
            counts['delivered_within_24h'] += 1
        elif row['attempt'] is not None and row['attempt'] <= deadline:
            counts['undelivered_at_24h_failed_or_unconfirmed'] += 1
        else:
            counts['undelivered_at_24h_no_attempt'] += 1
    return counts


def percentile(sorted_values, fraction):
    if not sorted_values:
        return None
    index = (len(sorted_values) - 1) * fraction
    left = floor(index)
    right = min(left + 1, len(sorted_values) - 1)
    return round(sorted_values[left] + (index - left) * (sorted_values[right] - sorted_values[left]), 3)


class RecordingStats:
    def __init__(self):
        self.visits = self.errors = self.early_errors = self.pending_errors = self.pending_exits = 0
        self.affected = set()
        self.load_times = []
        self.exits = dict.fromkeys(('ready_only', 'error_only', 'ready_and_error', 'neither'), 0)

    def add(self, row, cutoff):
        self.visits += 1
        exit_ms, error, ready = row['exit_ms'], row['error'], row['ready']
        if exit_ms is not None:
            if error is not None and error > exit_ms:
                error = None
            if ready is not None and ready > exit_ms:
                ready = None
        self.errors += error is not None
        if ready is not None:
            self.load_times.append(ready)
        if error is not None and error <= 10_000:
            self.early_errors += 1
            self.affected.add(row['installation'])
        elif exit_ms is None and cutoff < row['at'] + 10_000:
            self.pending_errors += 1
        if exit_ms is not None and exit_ms <= 30_000:
            if ready is not None:
                key = 'ready_and_error' if error is not None else 'ready_only'
            else:
                key = 'error_only' if error is not None else 'neither'
            self.exits[key] += 1
        elif exit_ms is None and cutoff < row['at'] + 30_000:
            self.pending_exits += 1

    def result(self):
        self.load_times.sort()
        exits = sum(self.exits.values())
        return {
            'visits': self.visits, 'visits_with_error': self.errors,
            'visits_with_error_percent': percent(self.errors, self.visits),
            'error_within_10s': self.early_errors,
            'error_within_10s_percent': percent(self.early_errors, self.visits),
            'error_window_still_open': self.pending_errors,
            'installations_with_early_error': len(self.affected),
            'exit_within_30s': exits, 'exit_within_30s_percent': percent(exits, self.visits),
            'exit_window_still_open': self.pending_exits,
            'early_exits_by_state': self.exits,
            'usable_lists': len(self.load_times),
            'median_load_ms': percentile(self.load_times, 0.5),
            'p95_load_ms': percentile(self.load_times, 0.95),
        }


def recordings(db, cutoff):
    total = RecordingStats()
    groups = defaultdict(RecordingStats)
    for row in visits(db, 'recording', cutoff, """
        min(CASE WHEN e.kind = 'recording_error' THEN e.elapsed END) AS error,
        min(CASE WHEN e.kind = 'recording_ready' THEN e.elapsed END) AS ready,
        min(CASE WHEN e.kind = 'recording_exit' THEN e.elapsed END) AS exit_ms
    """):
        total.add(row, cutoff)
        groups[(row['version'], row['platform'])].add(row, cutoff)
    return {
        'all': total.result(),
        'by_version_platform': [
            {'version': version, 'platform': platform, **stats.result()}
            for (version, platform), stats in groups.items()
        ],
    }


def make_report(db, cutoff):
    daily = db.execute("""
        SELECT date(at / 1000, 'unixepoch') AS day, feature,
            count(DISTINCT installation) AS installations
        FROM event WHERE kind = 'feature_open' AND at <= ?
        GROUP BY day, feature ORDER BY day, feature
    """, (cutoff,))
    return {
        'as_of_utc': utc(cutoff).isoformat(timespec='milliseconds'),
        'adoption': adoption(db, cutoff), 'daily_features': [dict(row) for row in daily],
        'feedback': feedback(db, cutoff), 'recordings': recordings(db, cutoff),
    }
