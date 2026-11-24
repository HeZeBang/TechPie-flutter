import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/library_reservation_service.dart';
import 'package:techpie/widgets/library_reservation_timeline.dart';

void main() {
  const room = LibraryRoom(
    id: 'r1',
    name: '研讨室 201',
    capacity: 6,
    disabled: false,
    slots: {
      480: LibrarySlotStatus.available,
      510: LibrarySlotStatus.available,
      540: LibrarySlotStatus.occupied,
      570: LibrarySlotStatus.available,
      600: LibrarySlotStatus.available,
      630: LibrarySlotStatus.available,
      660: LibrarySlotStatus.available,
      690: LibrarySlotStatus.available,
      720: LibrarySlotStatus.available,
      750: LibrarySlotStatus.available,
      780: LibrarySlotStatus.available,
    },
  );

  testWidgets('mobile timeline opens an eight-hour window and pans both rows',
      (tester) async {
    final offset = ValueNotifier<double>(0);
    addTearDown(offset.dispose);
    const day = LibraryAvailability(
      rooms: [room],
      cycleDays: 7,
      openStart: 480,
      openEnd: 1200,
      stepMinutes: 30,
      minMinutes: 60,
      maxMinutes: 90,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            child: Column(
              children: [
                for (var row = 0; row < 2; row++)
                  LibraryReservationTimeline(
                    availability: day,
                    room: room,
                    scrollOffset: offset,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('16:00'), findsNWidgets(2));
    final row = find.byType(LibraryReservationTimeline).first;
    await tester.drag(row, const Offset(-400, 0));
    await tester.pump();
    expect(find.text('12:00'), findsNWidgets(2));
    expect(find.text('20:00'), findsNWidgets(2));
  });
}
