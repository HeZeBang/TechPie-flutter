class StudentLeave {
  StudentLeave(Map<String, dynamic> source)
      : fields = {
          for (final key in _keys)
            if ((source[key] is String || source[key] is num) &&
                source[key].toString().trim().isNotEmpty)
              key: source[key].toString().trim(),
        };

  static const _keys = {
    'SQBH',
    'SHZT',
    'SHZT_DISPALY',
    'SHZT_DISPLAY',
    'XJZT',
    'XJZT_DISPLAY',
    'QJLX',
    'QJLX_DISPLAY',
    'QJXZ',
    'QJXZ_DISPLAY',
    'SQRQ',
    'QJKSRQ',
    'QJJSRQ',
    'QJTS',
    'QJRQ',
    'SQSM',
    'DZ_QJQX',
    'DZ_XXDZ',
    'DZ_KCMC',
    'QJSY',
  };
  final Map<String, String> fields;
  String operator [](String key) => fields[key] ?? '';
  String get id => this['SQBH'];
  String get type => fields['QJLX_DISPLAY'] ?? this['QJLX'];
  String get status => fields['SHZT_DISPLAY'] ?? fields['SHZT_DISPALY'] ?? this['SHZT'];
  Map<String, String> get summary => {
        for (final key in [
          'SQBH',
          'SHZT',
          'SHZT_DISPLAY',
          'SHZT_DISPALY',
          'XJZT',
          'XJZT_DISPLAY',
          'QJLX',
          'QJLX_DISPLAY',
          'SQRQ',
          'QJKSRQ',
          'QJJSRQ',
          'QJTS',
        ])
          if (fields.containsKey(key)) key: this[key],
      };
}

class LeaveKind {
  const LeaveKind(this.id, this.label, this.startRule);
  final String id, label, startRule;

  DateTime earliestStart(DateTime now) =>
      DateTime(now.year, now.month, now.day - (startRule == '0' ? 0 : 7));
}

class LeaveApplicationInfo {
  const LeaveApplicationInfo({
    required this.daysUsed,
    required this.eligible,
    required this.reason,
    required this.properties,
  });
  final String daysUsed, reason;
  final bool eligible;
  final Map<String, String> properties;
}

/// IDs from the mobile history identify that service's approval records.
class LeaveApprovalRecord {
  const LeaveApprovalRecord(this.id, this.title, this.period);
  final String id, title, period;
}

class LeaveApprovalDetail {
  const LeaveApprovalDetail(this.status, this.comment, this.reason);
  final String status, comment, reason;
}
