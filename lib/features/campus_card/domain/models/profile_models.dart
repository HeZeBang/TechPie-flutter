final class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.maskedCardNumber,
    required this.positionName,
    this.avatarBytes,
  });

  final String displayName;
  final String maskedCardNumber;
  final String positionName;
  final List<int>? avatarBytes;
}
