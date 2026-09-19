import '../money_fen.dart';

enum CampusCardStatus {
  normal,
  lost,
  frozen,
  closed,
  preclosed,
  manualFrozen,
  unknown,
}

extension CampusCardStatusRules on CampusCardStatus {
  bool get permitsPayment => this == CampusCardStatus.normal;

  static CampusCardStatus fromApi(Object? value) => switch (value?.toString()) {
        '正常' => CampusCardStatus.normal,
        '挂失' => CampusCardStatus.lost,
        '冻结' => CampusCardStatus.frozen,
        '销户' => CampusCardStatus.closed,
        '预销户' => CampusCardStatus.preclosed,
        '手工冻结' => CampusCardStatus.manualFrozen,
        '1' => CampusCardStatus.normal,
        _ => CampusCardStatus.unknown,
      };
}

final class CampusCard {
  const CampusCard({
    required this.id,
    required this.maskedNumber,
    required this.ownerName,
    required this.balance,
    required this.status,
    required this.positionName,
    required this.offlineCodeAllowed,
    this.positionCode,
    this.schoolName,
    this.departmentName,
    this.validUntil,
    this.lastTransactionAt,
    this.accountType,
    this.detailsAvailable = true,
    this.updatedAt,
  });

  final String id;
  final String maskedNumber;
  final String ownerName;
  final MoneyFen balance;
  final CampusCardStatus status;
  final String positionName;
  final String? positionCode;
  final bool offlineCodeAllowed;
  final String? schoolName;
  final String? departmentName;
  final DateTime? validUntil;
  final DateTime? lastTransactionAt;
  final String? accountType;
  final bool detailsAvailable;
  final DateTime? updatedAt;
  CampusCard withBalance(MoneyFen value) => CampusCard(
    id: id, maskedNumber: maskedNumber, ownerName: ownerName, balance: value,
    status: status, positionName: positionName, positionCode: positionCode,
    offlineCodeAllowed: offlineCodeAllowed, schoolName: schoolName,
    departmentName: departmentName, validUntil: validUntil,
    lastTransactionAt: lastTransactionAt, accountType: accountType,
    detailsAvailable: detailsAvailable, updatedAt: updatedAt,
  );

}

final class CampusPositionProfile {
  const CampusPositionProfile({
    required this.code,
    required this.name,
    required this.cardPerTransactionFen,
    required this.cardPerDayFen,
    required this.validityMonths,
    this.special,
  });

  final String code;
  final String name;
  final int cardPerTransactionFen;
  final int cardPerDayFen;
  final int validityMonths;
  final String? special;
}

abstract final class CampusPositionCatalog {
  static const profiles = <String, CampusPositionProfile>{
    '01': CampusPositionProfile(
      code: '01',
      name: '学生',
      cardPerTransactionFen: 5000,
      cardPerDayFen: 20000,
      validityMonths: 48,
      special: '押金0/工本费0',
    ),
    '02': CampusPositionProfile(
      code: '02',
      name: '教工',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 120,
    ),
    '03': CampusPositionProfile(
      code: '03',
      name: '校外人员',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 60,
      special: '押金1/工本费5',
    ),
    '04': CampusPositionProfile(
      code: '04',
      name: '物业门禁卡',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 120,
      special: '工本费100',
    ),
    '05': CampusPositionProfile(
      code: '05',
      name: '在聘职工（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 36,
    ),
    '06': CampusPositionProfile(
      code: '06',
      name: '测试人员',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 15000,
      validityMonths: 48,
    ),
    '07': CampusPositionProfile(
      code: '07',
      name: '特聘教授（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '08': CampusPositionProfile(
      code: '08',
      name: '外聘教师（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '09': CampusPositionProfile(
      code: '09',
      name: '访问学者（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '10': CampusPositionProfile(
      code: '10',
      name: '博士后（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '11': CampusPositionProfile(
      code: '11',
      name: '访问学生（学生）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '12': CampusPositionProfile(
      code: '12',
      name: '租赁住宿人员（学生）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '13': CampusPositionProfile(
      code: '13',
      name: '租赁住宿人员（校外）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '14': CampusPositionProfile(
      code: '14',
      name: '物业工作人员（校外）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 60,
    ),
    '15': CampusPositionProfile(
      code: '15',
      name: '商铺工作人员（校外）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '16': CampusPositionProfile(
      code: '16',
      name: '教师公寓家属（就餐）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '17': CampusPositionProfile(
      code: '17',
      name: '教师公寓家属（门禁）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
      special: '工本费100',
    ),
    '18': CampusPositionProfile(
      code: '18',
      name: '部门公务卡（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '19': CampusPositionProfile(
      code: '19',
      name: '新职工周转卡（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '20': CampusPositionProfile(
      code: '20',
      name: '施工人员周转卡',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 60,
    ),
    '21': CampusPositionProfile(
      code: '21',
      name: '科研合作项目（校外）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 60,
    ),
    '22': CampusPositionProfile(
      code: '22',
      name: '科研合作项目（教工）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '23': CampusPositionProfile(
      code: '23',
      name: '企业导师（校外）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 15000,
      validityMonths: 48,
    ),
    '24': CampusPositionProfile(
      code: '24',
      name: '校外人员（无管理费）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '25': CampusPositionProfile(
      code: '25',
      name: '校外人员（外聘教师）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 50000,
      validityMonths: 48,
    ),
    '26': CampusPositionProfile(
      code: '26',
      name: '校内长期合作单位',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '27': CampusPositionProfile(
      code: '27',
      name: '校内科研相关学生',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 36,
    ),
    '28': CampusPositionProfile(
      code: '28',
      name: '校内长期服务保障团队',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 36,
    ),
    '29': CampusPositionProfile(
      code: '29',
      name: '纯住宿学生',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
    '30': CampusPositionProfile(
      code: '30',
      name: '部门公务卡',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 60,
    ),
    '31': CampusPositionProfile(
      code: '31',
      name: '纯住宿学生（高研院）',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 50000,
      validityMonths: 48,
    ),
    '32': CampusPositionProfile(
      code: '32',
      name: '跨校选课生',
      cardPerTransactionFen: 100000,
      cardPerDayFen: 500000,
      validityMonths: 120,
      special: '特殊高限额',
    ),
    '33': CampusPositionProfile(
      code: '33',
      name: '附属学校学生',
      cardPerTransactionFen: 10000,
      cardPerDayFen: 20000,
      validityMonths: 48,
    ),
  };

  static CampusPositionProfile? fromCode(Object? value) {
    final code = value?.toString().trim().padLeft(2, '0');
    return code == null ? null : profiles[code];
  }

  static String displayName(Object? value, {String? fallback}) {
    final profile = fromCode(value);
    if (profile != null) return profile.name;
    final fallbackText = fallback?.trim();
    if (fallbackText != null && fallbackText.isNotEmpty) return fallbackText;
    final code = value?.toString().trim();
    return code == null || code.isEmpty ? '—' : code;
  }
}

enum IdentityDocumentType {
  nationalId('1001'),
  militaryId('1002'),
  passport('1003'),
  workId('1004');

  const IdentityDocumentType(this.apiCode);
  final String apiCode;
}

final class BindCardCommand {
  const BindCardCommand({
    required this.cardNumber,
    required this.queryPassword,
    required this.identityNumber,
    required this.identityType,
    required this.phoneNumber,
  });

  final String cardNumber;
  final String queryPassword;
  final String identityNumber;
  final IdentityDocumentType identityType;
  final String phoneNumber;

  void validate() {
    if (cardNumber.trim().isEmpty) {
      throw const FormatException('Card number is required');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(queryPassword)) {
      throw const FormatException(
        'Card query password must contain six digits',
      );
    }
    if (identityNumber.trim().isEmpty) {
      throw const FormatException('Identity number is required');
    }
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phoneNumber)) {
      throw const FormatException('Phone number is invalid');
    }
  }
}

final class BindCardResult {
  const BindCardResult({required this.offlineCodeAllowed});
  final bool offlineCodeAllowed;
}
