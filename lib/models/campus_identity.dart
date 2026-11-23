enum CampusStudentKind { undergraduate, graduate, unknown }

enum CampusScheduleSource { automatic, undergraduate, graduate }

/// An authoritative response that cannot safely reuse a previous classification.
class CampusIdentityConflict extends FormatException {
  const CampusIdentityConflict(super.message);
}

/// A classification of the current IDS principal, never a guess from a student
/// number or from whether another school's application happens to open.
class CampusIdentity {
  const CampusIdentity(this.kind, this.categoryName);

  final CampusStudentKind kind;
  final String categoryName;

  factory CampusIdentity.fromIds(
    Map<String, dynamic> profile,
    String expectedSid, {
    Map<String, dynamic>? associatedAccounts,
  }) {
    final data = profile['datas'];
    if (profile['code']?.toString() != '0' || data is! Map) {
      throw const FormatException('IDS 用户信息读取失败，请检查学校登录会话');
    }
    final uid = data['uid']?.toString().trim() ?? '';
    if (uid.isEmpty) {
      throw const FormatException('IDS 当前账号信息缺少 uid，无法识别身份');
    }
    // A phone/email login or an older CpDaily binding may not include a school
    // number. In that case the authenticated CASTGC principal remains the
    // authority; never compare its uid with an empty string or an internal UUID.
    if (expectedSid.trim().isNotEmpty && uid != expectedSid.trim()) {
      throw const CampusIdentityConflict('IDS 当前账号与学校绑定学号不一致，请检查 CpDaily / IDS 绑定');
    }
    var category = data['categoryName']?.toString().trim() ?? '';
    if (category.isEmpty && associatedAccounts != null) {
      final rows = associatedAccounts['bindingUserList'];
      if (rows is List) {
        final matches = rows
            .whereType<Map<dynamic, dynamic>>()
            .where((r) => r['userId']?.toString() == uid && r['accountStatus'] == '账号正常')
            .toList();
        if (matches.length == 1) category = matches.single['categoryName']?.toString().trim() ?? '';
      }
    }
    return CampusIdentity.fromCategory(category);
  }

  factory CampusIdentity.fromCategory(String category) {
    final label = category.replaceAll(RegExp(r'\s+'), '');
    if (RegExp('校友|离校|毕业|教职工|教师|退休').hasMatch(label)) {
      return CampusIdentity(CampusStudentKind.unknown, category);
    }
    final undergraduate = label.contains('本科');
    final graduate = RegExp('研究生|硕士|博士').hasMatch(label);
    return CampusIdentity(
      undergraduate == graduate
          ? CampusStudentKind.unknown
          : undergraduate
              ? CampusStudentKind.undergraduate
              : CampusStudentKind.graduate,
      category,
    );
  }

  Map<String, dynamic> toJson() => {'kind': kind.name, 'categoryName': categoryName};

  factory CampusIdentity.fromJson(Map<String, dynamic> json) {
    final identity = CampusIdentity.fromCategory(json['categoryName'] as String? ?? '');
    if (json['kind'] != identity.kind.name) throw const FormatException('学生身份缓存无效');
    return identity;
  }
}
