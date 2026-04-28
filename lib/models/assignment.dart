class Assignment {
  final String id;
  final String platform;
  final String title;
  final String course;
  final DateTime due;
  final String? status;
  final String? url;
  final bool submitted;

  const Assignment({
    required this.id,
    required this.platform,
    required this.title,
    required this.course,
    required this.due,
    this.status,
    this.url,
    required this.submitted,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as String? ?? '',
      platform: json['platform'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      course: json['course'] as String? ?? '',
      due: json['due'] != null 
          ? DateTime.fromMillisecondsSinceEpoch((json['due'] as int) * 1000) 
          : DateTime.now(),
      status: json['status'] as String?,
      url: json['url'] as String?,
      submitted: json['submitted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'title': title,
    'course': course,
    'due': due.millisecondsSinceEpoch ~/ 1000,
    'status': status,
    'url': url,
    'submitted': submitted,
  };
}
