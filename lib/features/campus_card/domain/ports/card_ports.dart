import '../models/card_models.dart';
import '../models/profile_models.dart';

abstract interface class CardRepository {
  Future<CampusCard?> currentCard();
  Future<UserProfile> profile();
  Future<BindCardResult> bind(BindCardCommand command);
  Future<void> unbind({required String cardPassword});
}

/// A card repository that can paint cached data before refreshing the network.
abstract interface class CacheFirstCardRepository implements CardRepository {
  Future<CampusCard?> readCachedCard();
  Future<CampusCard?> refreshCard();
}

/// Verified snapshots committed by either the account or code endpoint.
abstract interface class CardSnapshotSource {
  Stream<CampusCard?> get snapshots;
}
