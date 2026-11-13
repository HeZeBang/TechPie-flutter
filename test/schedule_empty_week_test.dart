import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/schedule_page.dart';

void main() {
  // The timetable is only fetched once an IDS binding exists, and that fetch can
  // fail — so "this week is empty" is a claim the app can only make in one of the
  // three cases below. Getting it wrong is what a freshly bound account saw.
  test('an empty week says which of the three things it is', () {
    expect(
      emptyWeekStateOf(hasSemester: false, hasError: false),
      EmptyWeekState.loading,
      reason: 'nothing fetched yet: the ring, not a claim',
    );
    expect(
      emptyWeekStateOf(hasSemester: false, hasError: true),
      EmptyWeekState.failed,
      reason: 'a failed fetch must say so: pull-to-refresh is the way out',
    );
    expect(
      emptyWeekStateOf(hasSemester: true, hasError: true),
      EmptyWeekState.failed,
      reason: 'a stale table plus a failed refresh is still a failure to report',
    );
    expect(
      emptyWeekStateOf(hasSemester: true, hasError: false),
      EmptyWeekState.noClasses,
      reason: 'only with a timetable in hand is an empty week a fact',
    );
  });
}
