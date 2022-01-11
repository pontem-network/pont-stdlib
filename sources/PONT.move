/// PONT (Pontem) native coin.
module PontemFramework::PONT {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Pontem;
    use PontemFramework::PontTimestamp;

    /// The resource to use if you want to work with PONT balances.
    struct PONT has key, store {}

    /// Just drop mint and burn capabilities by storing in inaccessible resource forever.
    struct Drop has key {
        mint_cap: Pontem::MintCapability<PONT>,
        burn_cap: Pontem::BurnCapability<PONT>,
    }

    /// Registers the `PONT` token as native currency. This can only be called from genesis.
    public fun initialize(
        root_account: &signer,
    ) {
        PontTimestamp::assert_genesis();
        CoreAddresses::assert_root(root_account);

        let (mint_cap, burn_cap) = Pontem::register_native_currency<PONT>(
            root_account,
            10,
            b"PONT",
            b"PONT"
        );

        move_to(root_account, Drop {mint_cap, burn_cap});
    }
}
