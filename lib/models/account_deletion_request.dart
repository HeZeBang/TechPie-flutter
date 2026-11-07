class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.id,
    required this.requestedAt,
    required this.completed,
  });

  final String id;
  final DateTime requestedAt;
  final bool completed;

  factory AccountDeletionRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final status = json['status'];
    final date = DateTime.tryParse(json['requestedAt'] as String? ?? '');
    if (id is! String ||
        id.isEmpty ||
        date == null ||
        (status != 'pending' && status != 'completed')) {
      throw const FormatException('Invalid deletion request receipt');
    }
    return AccountDeletionRequest(id: id, requestedAt: date, completed: status == 'completed');
  }
}

class AccountDeletionRequestException implements Exception {
  const AccountDeletionRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}
