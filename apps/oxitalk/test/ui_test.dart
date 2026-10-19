import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/ui/avatar.dart';
import 'package:oxitalk/src/ui/format.dart';

void main() {
  final now = DateTime(2026, 10, 18, 15, 30); // a Sunday

  test('list times: clock today, weekday this week, date before', () {
    expect(listTime(DateTime(2026, 10, 18, 9, 5), now: now), '09:05');
    expect(listTime(DateTime(2026, 10, 14, 9, 5), now: now), 'Wed');
    expect(listTime(DateTime(2026, 10, 11, 9, 5), now: now), '11.10.26');
  });

  test('day labels', () {
    expect(dayLabel(DateTime(2026, 10, 18, 1), now: now), 'Today');
    expect(dayLabel(DateTime(2026, 10, 17, 23), now: now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 3, 2), now: now), '2 March');
    expect(dayLabel(DateTime(2025, 12, 31), now: now), '31 December 2025');
  });

  test('initials', () {
    expect(initials('Team Room'), 'TR');
    expect(initials('@bob:example.org'), 'BE');
    expect(initials('alice'), 'A');
    expect(initials(''), '?');
  });
}
