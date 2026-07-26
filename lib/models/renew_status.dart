/// Outcome of the most recent renewal attempt for a session node (top-level
/// bindings cpdaily/gradescope/hydro, or derived children eams/elearning).
/// Local-only — never part of the cloud-sync envelope (renewal history is
/// device-specific and irrelevant to restoring bindings on another device).
class RenewStatus {
  final DateTime at;
  final bool success;
  final String? error;

  const RenewStatus({required this.at, required this.success, this.error});

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'success': success,
        if (error != null) 'error': error,
      };

  static RenewStatus? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    return RenewStatus(
      at: at,
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }
}
