/// The user-local diary day, as a `YYYY-MM-DD` string.
///
/// This exists because the obvious thing is wrong. `DateTime.now()
/// .toIso8601String().substring(0, 10)` looks correct and is correct for
/// about eighteen hours a day in India — then a user logs dinner at 11pm
/// IST, `toUtc()` rolls the clock back to 17:30 the same day, and it works
/// anyway. But `DateTime.parse` on a stored UTC timestamp, or any code path
/// that normalises to UTC first, silently files the meal under *yesterday*.
/// The bug only appears in the evening, only for users east of UTC, and the
/// data is already wrong by the time anyone notices.
///
/// The backend stores this field as a plain string with no timezone by
/// design — a diary day is a local calendar day, not an instant. So the
/// conversion happens exactly once, here, from the device's local fields.
class DiaryDate {
  const DiaryDate._();

  /// Today, on the device's own clock.
  static String today() => of(DateTime.now());

  /// The local calendar day of [moment].
  ///
  /// Reads `.year`/`.month`/`.day` directly rather than formatting an ISO
  /// string, so a `DateTime` that happens to be flagged UTC cannot shift
  /// the answer.
  static String of(DateTime moment) {
    final DateTime local = moment.isUtc ? moment.toLocal() : moment;
    return format(local.year, local.month, local.day);
  }

  static String format(int year, int month, int day) =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Parses back into a local midnight, or null if malformed.
  static DateTime? parse(String value) {
    if (!isValid(value)) return null;
    final List<String> parts = value.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static final RegExp _shape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Mirrors `diaryDateSchema` on the server: right shape *and* a real
  /// calendar date, so `2026-02-30` is rejected here rather than 400ing.
  static bool isValid(String value) {
    if (!_shape.hasMatch(value)) return false;
    final List<String> parts = value.split('-');
    final int year = int.parse(parts[0]);
    final int month = int.parse(parts[1]);
    final int day = int.parse(parts[2]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    // DateTime rolls over rather than throwing, so a date that survives the
    // round trip unchanged is a date that actually exists.
    final DateTime probe = DateTime(year, month, day);
    return probe.year == year && probe.month == month && probe.day == day;
  }

  /// Steps by whole calendar days.
  ///
  /// Built from the date fields, not `add(Duration(days: n))` — a duration
  /// is an exact 24 hours, so adding one across a DST boundary lands on the
  /// same calendar day again and the diary appears to skip a date.
  static String shift(String value, int days) {
    final DateTime? base = parse(value);
    if (base == null) return value;
    // Round-trip through DateTime: it is the only thing here that
    // normalises an out-of-range day. Passing `day + days` straight to
    // [format] — which is pure string padding — yields "2026-09-00" for
    // the day before the 1st, and the diary then sticks, because that
    // string fails [isValid] and every later shift returns it unchanged.
    final DateTime moved = DateTime(base.year, base.month, base.day + days);
    return format(moved.year, moved.month, moved.day);
  }

  static String previous(String value) => shift(value, -1);
  static String next(String value) => shift(value, 1);

  static bool isToday(String value) => value == today();

  /// "Today" / "Yesterday" / "Mon, 3 Sep" for diary headers.
  static String label(String value) {
    if (isToday(value)) return 'Today';
    if (value == previous(today())) return 'Yesterday';
    if (value == next(today())) return 'Tomorrow';

    final DateTime? date = parse(value);
    if (date == null) return value;
    final String weekday = _weekdays[date.weekday - 1];
    final String month = _months[date.month - 1];
    return '$weekday, ${date.day} $month';
  }

  static const List<String> _weekdays = <String>[
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
