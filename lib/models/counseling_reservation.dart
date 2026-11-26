/// The counseling page keeps these display fields only for its current visit.
class CounselingReservation {
  const CounselingReservation(
    this.date,
    this.period,
    this.place,
    this.name,
    this.bio,
    this.contact,
  );
  final String date, period, place, name, bio, contact;
  factory CounselingReservation.fromJson(Map<String, dynamic> row) => CounselingReservation(
        _text(row, 'YYRQ'),
        _text(row, 'SDMC'),
        _text(row, 'YYDD'),
        _text(row, 'XM'),
        _text(row, 'JJ'),
        _text(row, 'LXDH'),
      );
}

String _text(Map<String, dynamic> row, String key) => row[key]?.toString().trim() ?? '';

class CounselingSlot {
  const CounselingSlot(
    this.name,
    this.bio,
    this.place,
    this.periodLabel,
    this.time,
    this.availabilityLabel, {
    this.counselorId = '',
    this.periodCode = '',
    this.campusCode = '',
    this.statusCode = '',
  });
  final String name,
      bio,
      place,
      periodLabel,
      time,
      availabilityLabel,
      counselorId,
      periodCode,
      campusCode,
      statusCode;

  String get displayStatus => availabilityLabel.isNotEmpty
      ? availabilityLabel
      : switch (statusCode) {
          '0' => '可预约',
          '1' => '已约满',
          _ => '',
        };

  bool get isBookable =>
      counselorId.isNotEmpty &&
      (statusCode == '0' || availabilityLabel.contains('可预约')) &&
      !(statusCode == '1' ||
          availabilityLabel.contains('约满') ||
          availabilityLabel.contains('已满') ||
          availabilityLabel.contains('不可'));

  factory CounselingSlot.fromJson(Map<String, dynamic> row) => CounselingSlot(
        _text(row, 'XM'),
        _text(row, 'JJ'),
        _text(row, 'ZXDD'),
        _text(row, 'SDMC'),
        _text(row, 'ZXSJ'),
        _text(row, 'YYZT_DISPLAY'),
        counselorId: _text(row, 'ZGH'),
        periodCode: _text(row, 'SDDM'),
        campusCode: _text(row, 'XQDM'),
        statusCode: _text(row, 'YYZT'),
      );
}
