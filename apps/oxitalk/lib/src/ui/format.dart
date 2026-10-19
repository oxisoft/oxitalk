/// Dates and times the way Telegram shows them. English only until localization (M1).
library;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// `14:05`.
String clockTime(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

DateTime _day(DateTime time) => DateTime(time.year, time.month, time.day);

/// For the chat list: the time today, the weekday this week, else `18.10.26`.
String listTime(DateTime time, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  final day = _day(time);
  if (day == today) return clockTime(time);
  if (today.difference(day).inDays < 7 && !day.isAfter(today)) {
    return _weekdays[time.weekday - 1];
  }
  return '${_two(time.day)}.${_two(time.month)}.${_two(time.year % 100)}';
}

/// For day dividers: `Today`, `Yesterday`, `18 October`, or `18 October 2025` for another year.
String dayLabel(DateTime time, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  final day = _day(time);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  final label = '${time.day} ${_months[time.month - 1]}';
  return time.year == today.year ? label : '$label ${time.year}';
}
