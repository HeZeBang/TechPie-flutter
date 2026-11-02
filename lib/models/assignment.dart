enum DeadlineKind {
  assignment('assignment', '作业'),
  exam('exam', '考试');

  final String id;
  final String label;

  const DeadlineKind(this.id, this.label);

  static DeadlineKind fromJson(dynamic value) {
    final id = value?.toString().toLowerCase();
    return DeadlineKind.values.firstWhere(
      (kind) => kind.id == id,
      orElse: () => DeadlineKind.assignment,
    );
  }
}

class Assignment {
  final String id;
  final String platform;
  final DeadlineKind kind;
  final String title;
  final String course;
  final DateTime due;
  final DateTime? lateDue;
  final String? status;
  final String? url;

  const Assignment({
    required this.id,
    required this.platform,
    this.kind = DeadlineKind.assignment,
    required this.title,
    required this.course,
    required this.due,
    this.lateDue,
    this.status,
    this.url,
  });

  bool get submitted => status == 'Submitted' || status == 'Graded';

  /// Only Gradescope exposes a late-submission deadline. Other platforms use
  /// their primary [due] time as the final deadline.
  bool get supportsLateDue => platform.toLowerCase() == 'gradescope';

  DateTime? get effectiveLateDue => supportsLateDue ? lateDue : null;

  DateTime get effectiveDue => effectiveLateDue ?? due;

  factory Assignment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000);
      }
      if (v is String) {
        final asNum = num.tryParse(v);
        if (asNum != null) {
          return DateTime.fromMillisecondsSinceEpoch(asNum.toInt() * 1000);
        }
        final parsed = DateTime.tryParse(v);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    final kind = DeadlineKind.fromJson(json['kind']);
    final due = json['due'] != null ? parseDate(json['due']) : DateTime.now();
    final lateDue = json['lateDue'] != null ? parseDate(json['lateDue']) : null;
    if (kind == DeadlineKind.exam) {
      final rawExam = json['exam'];
      final exam = rawExam is Map ? rawExam.cast<String, dynamic>() : const <String, dynamic>{};
      final id = json['id'] as String? ?? '';
      return ExamAssignment(
        id: id,
        title: json['title'] as String? ?? '',
        course: json['course'] as String? ?? '',
        due: due,
        lateDue: lateDue,
        status: json['status'] as String?,
        url: json['url'] as String?,
        semesterId: exam['semesterId'] as String? ?? _semesterIdFromExamId(id),
        location: exam['location'] as String? ?? '',
        batchName: exam['batchName'] as String? ?? '',
      );
    }

    return Assignment(
      id: json['id'] as String? ?? '',
      platform: json['platform'] as String? ?? 'unknown',
      kind: kind,
      title: json['title'] as String? ?? '',
      course: json['course'] as String? ?? '',
      due: due,
      lateDue: lateDue,
      status: json['status'] as String?,
      url: json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'platform': platform,
        'kind': kind.id,
        'title': title,
        'course': course,
        'due': due.millisecondsSinceEpoch ~/ 1000,
        if (lateDue != null) 'lateDue': lateDue!.millisecondsSinceEpoch ~/ 1000,
        'status': status,
        'url': url,
      };
}

class ExamAssignment extends Assignment {
  final String semesterId;
  final String location;
  final String batchName;

  const ExamAssignment({
    required super.id,
    required super.title,
    required super.course,
    required super.due,
    super.lateDue,
    super.status,
    super.url,
    required this.semesterId,
    required this.location,
    required this.batchName,
  }) : super(platform: 'exam', kind: DeadlineKind.exam);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'exam': {
          'semesterId': semesterId,
          'location': location,
          'batchName': batchName,
        },
      };
}

String _semesterIdFromExamId(String id) {
  final separator = id.indexOf(':');
  return separator < 0 ? '' : id.substring(0, separator);
}
