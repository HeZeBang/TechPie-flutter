class CatalogCourse {
  const CatalogCourse(
    this.code,
    this.name,
    this.englishName,
    this.department,
    this.type,
    this.credits,
    this.hours,
    this.weekHours,
    this.weeks,
    this.teacher,
  );
  final String code, name, englishName, department, type, credits, hours, weekHours, weeks, teacher;

  factory CatalogCourse.fromRow(Map<String, String> row) => CatalogCourse(
        row['课程代码'] ?? row['课程编码'] ?? row['代码'] ?? '',
        row['课程名称'] ?? row['课程中文名'] ?? row['名称'] ?? '',
        row['英文名称'] ?? row['英文名'] ?? row['课程英文名'] ?? '',
        row['开课院系'] ?? row['开课部门'] ?? row['开课单位'] ?? row['院系'] ?? '',
        row['课程类别'] ?? row['课程类型'] ?? row['类别'] ?? '',
        row['学分'] ?? '',
        row['总学时'] ?? row['学时'] ?? row['课时'] ?? '',
        row['周学时'] ?? '',
        row['周次'] ?? row['周数'] ?? '',
        row['授课教师'] ?? row['主讲教师'] ?? row['教师'] ?? '',
      );

  Map<String, String> get details => {
        '课程代码': code,
        '英文名': englishName,
        '院系': department,
        '课程类别': type,
        '学分': credits,
        '总学时': hours,
        '周学时': weekHours,
        '周次': weeks,
        '教师': teacher,
      };
}
