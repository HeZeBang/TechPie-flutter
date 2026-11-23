import '../money_fen.dart';

/// Read-only result of opening the password-change service.
///
/// It proves only that the server recognizes the current card context. It does
/// not imply that the write endpoint is enabled.
final class SpendingPasswordInitialization {
  const SpendingPasswordInitialization({
    required this.accountKey,
    required this.haveCard,
    this.displayName,
  });

  /// Opaque identity value used for server-side cross-checks only.
  final String accountKey;
  final bool haveCard;
  final String? displayName;
}

final class SpendingLimits {
  const SpendingLimits({
    required this.idSerial,
    required this.cardId,
    required this.qrCodeId,
    required this.haveCard,
    required this.haveQrCode,
    required this.cardPerTransaction,
    required this.cardPerDay,
    required this.qrPerTransaction,
    required this.qrPerDay,
    this.displayName,
  });

  final String idSerial;
  final String cardId;
  final String qrCodeId;
  final bool haveCard;
  final bool haveQrCode;
  final MoneyFen cardPerTransaction;
  final MoneyFen cardPerDay;
  final MoneyFen qrPerTransaction;
  final MoneyFen qrPerDay;
  final String? displayName;

  SpendingLimits copyWith({
    MoneyFen? cardPerTransaction,
    MoneyFen? cardPerDay,
    MoneyFen? qrPerTransaction,
    MoneyFen? qrPerDay,
  }) =>
      SpendingLimits(
        idSerial: idSerial,
        cardId: cardId,
        qrCodeId: qrCodeId,
        haveCard: haveCard,
        haveQrCode: haveQrCode,
        cardPerTransaction: cardPerTransaction ?? this.cardPerTransaction,
        cardPerDay: cardPerDay ?? this.cardPerDay,
        qrPerTransaction: qrPerTransaction ?? this.qrPerTransaction,
        qrPerDay: qrPerDay ?? this.qrPerDay,
        displayName: displayName,
      );
}
