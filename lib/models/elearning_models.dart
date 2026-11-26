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
