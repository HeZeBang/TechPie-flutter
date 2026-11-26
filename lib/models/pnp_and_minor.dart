enum ApplicationWindow {
  open('开放中'),
  closed('未开放'),
  unknown('开放状态待确认');

  const ApplicationWindow(this.label);
  final String label;
}

class AcademicApplicationRow {
  const AcademicApplicationRow(this.title, this.fields);
  final String title;
  final Map<String, String> fields;
  Map<String, Object> toJson() => {'title': title, 'fields': fields};
  factory AcademicApplicationRow.fromJson(Map<String, dynamic> item) => AcademicApplicationRow(
        item['title'] as String,
        (item['fields'] as Map).cast<String, String>(),
      );
}
