enum PlanCourseStatus {
  passed('已通过'),
  studying('在修'),
  pending('未修'),
  failed('未通过'),
  unknown('未提供');

  const PlanCourseStatus(this.label);
  final String label;
}

class PlanCourseItem {
  const PlanCourseItem(
    this.code,
    this.name,
    this.credits,
    this.term,
    this.requiredCourse,
    this.department,
    this.status,
  );
  final String code, name, term, department;
  final double? credits;
  final bool? requiredCourse;
  final PlanCourseStatus status;
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'credits': credits,
    'term': term,
    'required': requiredCourse,
    'department': department,
    'status': status.name,
  };
  factory PlanCourseItem.fromJson(Map<String, dynamic> j) => PlanCourseItem(
    j['code'] as String,
    j['name'] as String,
    (j['credits'] as num?)?.toDouble(),
    j['term'] as String,
    j['required'] as bool?,
    j['department'] as String,
    PlanCourseStatus.values.byName(j['status'] as String),
  );
}

class PlanCategoryProgress {
  PlanCategoryProgress(
    this.name,
    this.depth, {
    this.requiredCredits,
    this.completed,
    this.actual,
    this.met,
    List<PlanCategoryProgress>? children,
    List<PlanCourseItem>? courses,
  }) : children = children ?? [],
       courses = courses ?? [];
  final String name;
  final int depth;
  final double? requiredCredits, completed, actual;
  final bool? met;
  final List<PlanCategoryProgress> children;
  final List<PlanCourseItem> courses;
  Iterable<PlanCategoryProgress> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'depth': depth,
    'required': requiredCredits,
    'completed': completed,
    'actual': actual,
    'met': met,
    'children': children.map((c) => c.toJson()).toList(),
    'courses': courses.map((c) => c.toJson()).toList(),
  };
  factory PlanCategoryProgress.fromJson(Map<String, dynamic> j) => PlanCategoryProgress(
    j['name'] as String,
    j['depth'] as int,
    requiredCredits: (j['required'] as num?)?.toDouble(),
    completed: (j['completed'] as num?)?.toDouble(),
    actual: (j['actual'] as num?)?.toDouble(),
    met: j['met'] as bool?,
    children: (j['children'] as List)
        .map((c) => PlanCategoryProgress.fromJson(c as Map<String, dynamic>))
        .toList(),
    courses: (j['courses'] as List)
        .map((c) => PlanCourseItem.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

class StudyPlanSnapshot {
  StudyPlanSnapshot(this.categories, this.requiredCredits, this.completed, this.updated);
  final List<PlanCategoryProgress> categories;
  final double? requiredCredits, completed;
  final DateTime updated;
  double? get completionPercent =>
      requiredCredits == null || requiredCredits! <= 0 || completed == null
      ? null
      : 100 * completed! / requiredCredits!;
  Map<String, dynamic> toJson() => {
    'categories': categories.map((c) => c.toJson()).toList(),
    'required': requiredCredits,
    'completed': completed,
    'updated': updated.toIso8601String(),
  };
  factory StudyPlanSnapshot.fromJson(Map<String, dynamic> j) => StudyPlanSnapshot(
    (j['categories'] as List)
        .map((c) => PlanCategoryProgress.fromJson(c as Map<String, dynamic>))
        .toList(),
    (j['required'] as num?)?.toDouble(),
    (j['completed'] as num?)?.toDouble(),
    DateTime.parse(j['updated'] as String),
  );
}
