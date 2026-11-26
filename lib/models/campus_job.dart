enum CampusJobProgram {
  workStudy('勤工助学', 'qgzxapp', '4626034165844765'),
  teachingAssistant('助教岗位', 'zjglapp_shanghaitech', '5368946393722896');

  const CampusJobProgram(this.label, this.app, this.appId);
  final String label, app, appId;
  String get webUrl => 'https://egate.shanghaitech.edu.cn/xsfw/sys/$app/*default/index.do';
}

String _field(Map<String, dynamic> row, String key) => row[key]?.toString().trim() ?? '';

String _display(Map<String, dynamic> row, String key) {
  final label = _field(row, '${key}_DISPLAY');
  return label.isEmpty ? _field(row, key) : label;
}

/// The opening index and the requirements table are separate EMAP models.
class CampusJobOpening {
  const CampusJobOpening({
    required this.id,
    required this.code,
    required this.unitCode,
    required this.name,
    required this.unit,
    required this.year,
    required this.term,
    required this.category,
    required this.headcount,
    required this.rate,
    required this.basis,
    required this.monthlyLimit,
    required this.fourWeekPay,
  });

  CampusJobOpening.fromJson(Map<String, dynamic> row)
      : id = _field(row, 'WID'),
        code = _field(row, 'GWDM'),
        unitCode = _field(row, 'DWDM'),
        name = _field(row, 'GWMC'),
        unit = _field(row, 'DWMC'),
        year = _field(row, 'XN'),
        term = _field(row, 'XQ'),
        category = _display(row, 'KCLBDM'),
        headcount = _field(row, 'XQRS'),
        rate = _field(row, 'BCBZ'),
        basis = _display(row, 'JSDW'),
        monthlyLimit = _field(row, 'YGZSX'),
        fourWeekPay = _field(row, 'YL5');
  final String id,
      code,
      unitCode,
      name,
      unit,
      year,
      term,
      category,
      headcount,
      rate,
      basis,
      monthlyLimit,
      fourWeekPay;
  String get title => name.isNotEmpty ? name : (code.isEmpty ? '岗位' : code);

  bool samePosition(CampusJobOpening other) {
    if (id.isNotEmpty && other.id.isNotEmpty) return id == other.id;
    return code.isNotEmpty &&
        unitCode.isNotEmpty &&
        year.isNotEmpty &&
        term.isNotEmpty &&
        (code, unitCode, year, term) == (other.code, other.unitCode, other.year, other.term);
  }

  /// Combines catalog metadata with fetched requirement details without losing keys.
  CampusJobOpening merge(CampusJobOpening? detail) {
    if (detail == null) return this;
    String pick(String a, String b) => a.isNotEmpty ? a : b;
    return CampusJobOpening(
      id: pick(detail.id, id),
      code: pick(detail.code, code),
      unitCode: pick(detail.unitCode, unitCode),
      name: pick(detail.name, name),
      unit: pick(detail.unit, unit),
      year: pick(detail.year, year),
      term: pick(detail.term, term),
      category: pick(detail.category, category),
      headcount: pick(detail.headcount, headcount),
      rate: pick(detail.rate, rate),
      basis: pick(detail.basis, basis),
      monthlyLimit: pick(detail.monthlyLimit, monthlyLimit),
      fourWeekPay: pick(detail.fourWeekPay, fourWeekPay),
    );
  }
}

class CampusJobRecord {
  CampusJobRecord.fromJson(Map<String, dynamic> row)
      : job = _display(row, 'GWDM'),
        unit = _display(row, 'DWDM'),
        reference = _field(row, 'SQBH'),
        applied = _field(row, 'SQRQ'),
        reason = _field(row, 'SQLY'),
        status = _display(row, 'SHZT'),
        start = _field(row, 'GZKSRQ'),
        end = _field(row, 'GZJSRQ');
  final String job, unit, reference, applied, reason, status, start, end;
}

class CampusJobPay {
  CampusJobPay.fromJson(Map<String, dynamic> row)
      : month = _field(row, 'FFYF'),
        rate = _field(row, 'BCBZ'),
        hours = _field(row, 'GS'),
        calculated = _field(row, 'JSJE'),
        paid = _field(row, 'SFJE');
  final String month, rate, hours, calculated, paid;
}

typedef CampusJobEmployment = ({
  List<CampusJobRecord> positions,
  String total,
  List<CampusJobPay> payments,
  String? positionsError,
  String? totalError,
  String? paymentsError,
});
