import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

void main() {
  group('MoneyFen', () {
    test('parses integer fen without floating-point arithmetic', () {
      expect(MoneyFen.fromApiFen(1234), const MoneyFen(1234));
      expect(MoneyFen.fromApiFen('0012'), const MoneyFen(12));
      expect(() => MoneyFen.fromApiFen(12.5), throwsFormatException);
    });

    test('converts exact yuan decimals at the adapter boundary', () {
      expect(MoneyFen.fromApiYuan('12.34'), const MoneyFen(1234));
      expect(MoneyFen.fromApiYuan(12), const MoneyFen(1200));
      expect(MoneyFen.fromApiYuan('0.1'), const MoneyFen(10));
      expect(MoneyFen.fromApiYuan('1.2300'), const MoneyFen(123));
      expect(() => MoneyFen.fromApiYuan('1.231'), throwsFormatException);
    });

    test('formats negative and positive values exactly', () {
      expect(const MoneyFen(1234).toYuanFixed(), '12.34');
      expect(const MoneyFen(-5).toYuanFixed(), '-0.05');
    });
  });
}
