/// An inclusive range of payment months. The school's form accepts YYYY-MM,
/// not days or timestamps.
class StudentAllowancePeriod {
  factory StudentAllowancePeriod(DateTime start, DateTime end) {
    final first = DateTime.utc(start.year, start.month);
    final last = DateTime.utc(end.year, end.month);
    if (first.year < 1 || last.year > 9999 || first.isAfter(last)) {
      throw ArgumentError('Invalid student allowance month range');
    }
    return StudentAllowancePeriod._(first, last);
  }

  const StudentAllowancePeriod._(this.start, this.end);

  final DateTime start;
  final DateTime end;

  String get startParameter => _parameter(start);
  String get endParameter => _parameter(end);

  static String _parameter(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
}

/// Amounts use integer fen, so no rounding is needed. An empty cell is distinct
/// from a reported 0.00.
class StudentAllowanceCategory {
  const StudentAllowanceCategory({
    required this.label,
    required this.grossFen,
    required this.netFen,
  });

  final String label;
  final int? grossFen;
  final int? netFen;
}

class StudentAllowanceEntry {
  StudentAllowanceEntry({
    required this.month,
    required Iterable<StudentAllowanceCategory> categories,
    required this.grossFen,
    required this.deductionsFen,
    required this.taxFen,
    required this.netFen,
  }) : categories = List.unmodifiable(categories);

  /// Null for the school's total row for the selected period.
  final DateTime? month;
  final List<StudentAllowanceCategory> categories;
  final int? grossFen;
  final int? deductionsFen;
  final int? taxFen;
  final int? netFen;
}

class StudentAllowanceReport {
  StudentAllowanceReport({
    required Iterable<StudentAllowanceEntry> months,
    required this.total,
  }) : months = List.unmodifiable(months);

  final List<StudentAllowanceEntry> months;
  final StudentAllowanceEntry? total;
}
