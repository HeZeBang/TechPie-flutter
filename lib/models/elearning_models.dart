class BlackboardCourse {
  const BlackboardCourse(this.id, this.code, this.name, this.term);
  final String id, code, name, term;
  factory BlackboardCourse.fromJson(Map<String, dynamic> row) => BlackboardCourse(
        row['id'] as String,
        row['courseId'] as String? ?? '',
        row['name'] as String? ?? '',
        row['term'] as String? ?? '',
      );
  Map<String, String> toJson() => {'id': id, 'courseId': code, 'name': name, 'term': term};
}

int? _parseDelimitedTermOrdinal(String rest, int startYear, int endYear) {
  final digitMatch = RegExp(
    r'(?:^|[\s\-_(（第sStT])0?([123])(?:$|[\s)）])',
  ).firstMatch(rest);
  return switch (digitMatch?.group(1)) {
    '1' => startYear * 100 + 9,
    '2' => endYear * 100 + 2,
    '3' => endYear * 100 + 7,
    _ => null,
  };
}

int? _parseCompactTermCode(String text) {
  final compact = RegExp(
    r'(?<!\d)((?:19|20)\d{2})(0?[123])(?!\d)',
  ).firstMatch(text);
  if (compact == null) return null;
  final year = int.parse(compact.group(1)!);
  return switch (compact.group(2)) {
    '1' || '01' => year * 100 + 9,
    '2' || '02' => (year + 1) * 100 + 2,
    '3' || '03' => (year + 1) * 100 + 7,
    _ => null,
  };
}

bool _isUnassignedBlackboardTerm(String rawTerm) {
  final trimmed = rawTerm.trim();
  return trimmed.isEmpty || trimmed == '其他学期';
}

/// Parses a Blackboard semester name into a comparable `YYYYMM` chronological
/// key so newer semesters sort before older ones. Returns `null` when empty,
/// `'其他学期'`, or no year can be extracted.
int? parseBlackboardTermSortKey(String rawTerm) {
  final text = rawTerm.trim();
  if (_isUnassignedBlackboardTerm(text)) return null;

  final rangeMatch = RegExp(
    r'(?<!\d)((?:19|20)\d{2})\s*[-–—~/／]\s*((?:19|20)?\d{2})(?!\d)',
  ).firstMatch(text);
  if (rangeMatch != null) {
    final startYear = int.parse(rangeMatch.group(1)!);
    final rawEnd = int.parse(rangeMatch.group(2)!);
    final endYear = rawEnd < 100 ? (startYear ~/ 100) * 100 + rawEnd : rawEnd;
    if (endYear == startYear + 1) {
      final rest = text.replaceRange(rangeMatch.start, rangeMatch.end, ' ').toLowerCase();
      if (RegExp(
        r'暑|夏|短学期|小学期|第三学期|第3学期|summer|(?<![a-z])su(?![a-z])|term\s*3|semester\s*3',
      ).hasMatch(rest)) {
        return endYear * 100 + 7;
      }
      if (RegExp(
        r'春|第二学期|第2学期|spring|(?<![a-z])sp(?![a-z])|term\s*2|semester\s*2',
      ).hasMatch(rest)) {
        return endYear * 100 + 2;
      }
      if (RegExp(r'冬|寒|winter|(?<![a-z])wi(?![a-z])').hasMatch(rest)) {
        return endYear * 100 + 1;
      }
      if (RegExp(
        r'秋|第一学期|第1学期|fall|autumn|(?<![a-z])fa(?![a-z])|term\s*1|semester\s*1',
      ).hasMatch(rest)) {
        return startYear * 100 + 9;
      }
      return _parseDelimitedTermOrdinal(rest, startYear, endYear) ??
          startYear * 100 + 8;
    }
  }

  final yearMatch = RegExp(r'(?<!\d)((?:19|20)\d{2})(?!\d)').firstMatch(text);
  if (yearMatch != null) {
    final year = int.parse(yearMatch.group(1)!);
    final rest = text.replaceRange(yearMatch.start, yearMatch.end, ' ').toLowerCase();
    if (RegExp(r'秋|fall|autumn|(?<![a-z])fa(?![a-z])').hasMatch(rest)) {
      return year * 100 + 9;
    }
    if (RegExp(r'暑|夏|短学期|小学期|summer|(?<![a-z])su(?![a-z])').hasMatch(rest)) {
      return year * 100 + 7;
    }
    if (RegExp(r'春|spring|(?<![a-z])sp(?![a-z])').hasMatch(rest)) {
      return year * 100 + 2;
    }
    if (RegExp(r'冬|寒|winter|(?<![a-z])wi(?![a-z])').hasMatch(rest)) {
      return year * 100 + 1;
    }
    if (RegExp(r'第一学期|第1学期|term\s*1|semester\s*1').hasMatch(rest)) {
      return year * 100 + 9;
    }
    if (RegExp(r'第二学期|第2学期|term\s*2|semester\s*2').hasMatch(rest)) {
      return (year + 1) * 100 + 2;
    }
    if (RegExp(r'第三学期|第3学期|term\s*3|semester\s*3').hasMatch(rest)) {
      return (year + 1) * 100 + 7;
    }
    return _parseDelimitedTermOrdinal(rest, year, year + 1) ??
        _parseCompactTermCode(rest) ??
        year * 100;
  }

  return _parseCompactTermCode(text);
}

/// Orders Blackboard term labels descending (newest first), keeping empty
/// or `'其他学期'` groups last and undated named terms before unassigned ones.
int compareBlackboardTermNames(String a, String b) {
  final unassignedA = _isUnassignedBlackboardTerm(a);
  final unassignedB = _isUnassignedBlackboardTerm(b);
  if (unassignedA != unassignedB) return unassignedA ? 1 : -1;
  if (unassignedA && unassignedB) return 0;

  final keyA = parseBlackboardTermSortKey(a);
  final keyB = parseBlackboardTermSortKey(b);
  if (keyA != null && keyB != null) return keyB.compareTo(keyA);
  if (keyA != null || keyB != null) return keyA != null ? -1 : 1;
  return 0;
}

class BlackboardContent {
  const BlackboardContent(this.id, this.title, this.body, this.folder, this.assignment);
  final String id, title, body;
  final bool folder, assignment;
}

class BlackboardAttachment {
  const BlackboardAttachment(this.id, this.name);
  final String id, name;
}

class BlackboardGrade {
  const BlackboardGrade(
    this.id,
    this.title,
    this.score,
    this.possible,
    this.status,
    this.attemptUrl,
  );
  final String id, title, score, possible, status;
  final Uri? attemptUrl;
}

class BlackboardReceipt {
  const BlackboardReceipt(this.number, this.assignment, this.date, this.submission, this.size);
  final String number, assignment, date, submission, size;
}

class BlackboardReceiptPage {
  const BlackboardReceiptPage(this.total, this.receipts);
  final int total;
  final List<BlackboardReceipt> receipts;
}

class BlackboardAnnouncement {
  const BlackboardAnnouncement(this.title, this.text);
  final String title, text;
  Map<String, String> toJson() => {'title': title, 'text': text};
  factory BlackboardAnnouncement.fromJson(Map<String, dynamic> row) =>
      BlackboardAnnouncement(row['title'] as String, row['text'] as String);
}

class BlackboardGroup {
  const BlackboardGroup(this.name, this.description);
  final String name, description;
}

BlackboardCourse? matchBlackboardCourse(String timetableName, List<BlackboardCourse> courses) {
  final code =
      RegExp(r'(?<![a-z0-9])[a-z]{1,8}[- ]?\d{2,5}[a-z]?(?![a-z0-9])', caseSensitive: false);
  Set<String> codes(String name) => code
      .allMatches(name.toLowerCase())
      .map((m) => m.group(0)!.replaceAll(RegExp('[- ]'), ''))
      .toSet();
  final keys = codes(timetableName);
  String normalize(String name) => name
      .toLowerCase()
      .replaceAll(code, '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final name = normalize(timetableName);
  var maximum = 0;
  final matches = <BlackboardCourse>[];
  for (final course in courses) {
    final named = normalize(course.name);
    final sameCode = keys.intersection(codes('${course.code} ${course.name}')).isNotEmpty;
    final sameName = name.isNotEmpty && named == name;
    final partial =
        name.length >= 3 && named.length >= 3 && (named.contains(name) || name.contains(named));
    final rank = (sameCode ? 4 : 0) +
        (sameName
            ? 2
            : partial
                ? 1
                : 0);
    if (rank == 0 || rank < maximum) continue;
    if (rank > maximum) matches.clear();
    maximum = rank;
    matches.add(course);
  }
  return matches.length == 1 ? matches.single : null;
}
