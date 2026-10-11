import '../models/merchant_alias_models.dart';

abstract interface class MerchantAliasPort {
  MerchantAliasConfig get current;
  Stream<MerchantAliasConfig> get changes;
}

final class EmptyMerchantAliasPort implements MerchantAliasPort {
  const EmptyMerchantAliasPort();

  @override
  MerchantAliasConfig get current => const MerchantAliasConfig.empty();

  @override
  Stream<MerchantAliasConfig> get changes => const Stream.empty();
}
