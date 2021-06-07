address 0x1 {
module NativeCurrencies {
    use 0x1::Errors;
    use 0x1::Signer;

    const NATIVE_CURRENCY: u64 = 0;

    struct NativeCurrency<CoinType: store> has key, store {
        access_path: vector<u8>,
    }

    public fun register_currency<CoinType: store>(account: &signer, access_path: vector<u8>) {
        assert(
            !exists<NativeCurrency<CoinType>>(Signer::address_of(account)),
            Errors::already_published(NATIVE_CURRENCY)
        );
        move_to(account, NativeCurrency<CoinType> { access_path: access_path })
    }
}
}