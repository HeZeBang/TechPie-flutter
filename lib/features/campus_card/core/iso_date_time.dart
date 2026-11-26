import 'package:intl/intl.dart';

final _isoDateTime = RegExp(
  r'^(\d{4}-\d{2}-\d{2})(?:[Tt ](\d{2}:\d{2}(?::\d{2})?)'
  r'(?:[.,]\d+)?(?: ?(?:[Zz]|[+-](?:[01]\d|2[0-3])(?::?[0-5]\d)?))?)?$',
);

DateTime? parseIsoDateTime(String source) {
  final match = _isoDateTime.firstMatch(source);
  if (match == null) return null;
  final time = match.group(2);
  final pattern = time == null
      ? 'yyyy-MM-dd'
      : time.length == 5
          ? 'yyyy-MM-dd HH:mm'
          : 'yyyy-MM-dd HH:mm:ss';
  try {
    // The SDK parser normalizes overflowing dates; validate local components first.
    DateFormat(pattern).parseStrict(
      '${match.group(1)}${time == null ? '' : ' $time'}',
      true,
    );
  } on FormatException {
    return null;
  }
  return DateTime.tryParse(source);
}
