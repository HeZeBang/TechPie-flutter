import '../money_fen.dart';

enum RechargeChannel { bankTransfer, campusCardTransfer, thirdParty }

enum RechargeOrderState { created, processing, succeeded, failed }

final class RechargeOrder {
  const RechargeOrder({
    required this.id,
    required this.amount,
    required this.channel,
    required this.state,
    required this.createdAt,
    this.message,
  });

  final String id;
  final MoneyFen amount;
  final RechargeChannel channel;
  final RechargeOrderState state;
  final DateTime createdAt;
  final String? message;
}

/// Read-only result of entering the real recharge flow.
///
/// This does not represent an order and cannot be used to claim that a charge
/// was submitted or paid.
final class RechargeInitialization {
  const RechargeInitialization({
    required this.accountKey,
    required this.balance,
    this.disableAccountPrefix,
    this.applicationId,
  });

  /// Opaque account key required by a future, separately authorized order
  /// contract. Presentation code must not render or log it.
  final String accountKey;
  final MoneyFen balance;
  final String? disableAccountPrefix;
  final String? applicationId;
}

final class RechargeChannelInfo {
  const RechargeChannelInfo({required this.payWay, required this.payName});

  final String payWay;
  final String payName;

  @override
  bool operator ==(Object other) =>
      other is RechargeChannelInfo &&
      other.payWay == payWay &&
      other.payName == payName;

  @override
  int get hashCode => Object.hash(payWay, payName);
}

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
