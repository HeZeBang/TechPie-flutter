import 'package:flutter/foundation.dart';

@immutable
final class MoneyFen implements Comparable<MoneyFen> {
  const MoneyFen(this.value);

  static const zero = MoneyFen(0);

  final int value;

  factory MoneyFen.fromApiFen(Object? raw, {String field = 'amount'}) {
    if (raw is int) return MoneyFen(raw);
    if (raw is num && raw.isFinite && raw == raw.truncateToDouble()) {
      return MoneyFen(raw.toInt());
    }
    if (raw is String && RegExp(r'^-?\d+$').hasMatch(raw.trim())) {
      return MoneyFen(int.parse(raw.trim()));
    }
    throw FormatException('$field must be an integer fen value');
  }

  factory MoneyFen.fromApiYuan(Object? raw, {String field = 'amount'}) {
    final source = switch (raw) {
      int value => value.toString(),
      String value => value.trim(),
      num value when value.isFinite => value.toString(),
      _ => throw FormatException('$field must be an exact yuan value'),
    };
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(source);
    if (match == null) {
      throw FormatException('$field must be an exact yuan value');
    }
    final fraction = match.group(3) ?? '';
    if (fraction.length > 2 &&
        fraction.substring(2).contains(RegExp('[1-9]'))) {
      throw FormatException('$field has precision below one fen');
    }
    final paddedFraction = '${fraction}00'.substring(0, 2);
    final absolute =
        int.parse(match.group(2)!) * 100 + int.parse(paddedFraction);
    return MoneyFen(match.group(1) == '-' ? -absolute : absolute);
  }

  MoneyFen operator +(MoneyFen other) => MoneyFen(value + other.value);
  MoneyFen operator -(MoneyFen other) => MoneyFen(value - other.value);

  bool get isNegative => value < 0;
  bool get isZero => value == 0;

  String toYuanFixed() {
    final absolute = value.abs();
    final yuan = absolute ~/ 100;
    final fen = (absolute % 100).toString().padLeft(2, '0');
    return '${value < 0 ? '-' : ''}$yuan.$fen';
  }

  @override
  int compareTo(MoneyFen other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is MoneyFen && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MoneyFen($value)';
}
