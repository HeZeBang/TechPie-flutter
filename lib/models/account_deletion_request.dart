class AccountDeletionRequestException implements Exception {
  const AccountDeletionRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}
