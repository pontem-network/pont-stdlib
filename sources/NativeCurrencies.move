/// Native currencies registration for Pontem Network.
/// Pontem node's using current module to connect native balances with VM's balances.
module PontemFramework::NativeCurrencies {
    use Std::Errors;
    use Std::Signer;

    friend PontemFramework::Pontem;

    /// When native currency already published.
    const ENATIVE_CURRENCY: u64 = 0;

    /// The resource to store access path for `CoinType` native currency.
    struct NativeCurrency<phantom CoinType> has key, store {
        access_path: vector<u8>,
    }

    /// Register new native currency.
    public(friend) fun register_currency<CoinType>(account: &signer, access_path: vector<u8>) {
        assert(
            !exists<NativeCurrency<CoinType>>(Signer::address_of(account)),
            Errors::already_published(ENATIVE_CURRENCY)
        );
        move_to(account, NativeCurrency<CoinType> { access_path: access_path })
    }
}
