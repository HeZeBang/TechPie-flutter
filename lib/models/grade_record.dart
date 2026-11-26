class CourseGrade {
  const CourseGrade({
    required this.semester,
    required this.courseCode,
    required this.courseName,
    required this.courseType,
    required this.credits,
    required this.scoreText,
    required this.gradePoint,
    required this.passed,
    required this.isRetake,
  });

  final String semester, courseCode, courseName, courseType, scoreText;
  final double credits;
  final double? gradePoint;
  final bool? passed;
  final bool isRetake;

  Map<String, Object?> toJson() => {
        'semester': semester,
        'code': courseCode,
        'name': courseName,
        'type': courseType,
        'credits': credits,
        'score': scoreText,
        'point': gradePoint,
        'passed': passed,
        'retake': isRetake,
      };

  factory CourseGrade.fromJson(Map<String, dynamic> row) => CourseGrade(
        semester: row['semester'] as String,
        courseCode: row['code'] as String,
        courseName: row['name'] as String,
        courseType: row['type'] as String,
        credits: (row['credits'] as num).toDouble(),
        scoreText: row['score'] as String,
        gradePoint: (row['point'] as num?)?.toDouble(),
        passed: row['passed'] as bool?,
        isRetake: row['retake'] as bool,
      );
}

class GradeSummary {
  const GradeSummary(this.gpa, this.earnedCredits, this.gradedCredits, this.courseCount);
  final double? gpa;
  final double earnedCredits, gradedCredits;
  final int courseCount;

  factory GradeSummary.of(Iterable<CourseGrade> courses) {
    double weighted = 0, earned = 0, graded = 0;
    var count = 0;
    for (final course in courses) {
      count++;
      if (course.credits <= 0) continue;
      if (course.passed == true) earned += course.credits;
      final point = course.gradePoint;
      if (point == null) continue;
      graded += course.credits;
      weighted += point * course.credits;
    }
    return GradeSummary(graded == 0 ? null : weighted / graded, earned, graded, count);
  }
}

class OtherEnglishGrade {
  const OtherEnglishGrade(this.exam, this.semester, this.score, this.status);
  final String exam, semester, score, status;
}
