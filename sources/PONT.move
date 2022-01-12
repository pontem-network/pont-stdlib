/// PONT (Pontem) native token.
module PontemFramework::PONT {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Token;
    use PontemFramework::PontTimestamp;

    /// The resource to use if you want to work with PONT balances.
    struct PONT has key, store {}

    /// Just drop mint and burn capabilities by storing in inaccessible resource forever.
    struct Drop has key {
        mint_cap: Token::MintCapability<PONT>,
        burn_cap: Token::BurnCapability<PONT>,
    }

    /// Registers the `PONT` token as native token. This can only be called from genesis.
    public fun initialize(
        root_account: &signer,
    ) {
        PontTimestamp::assert_genesis();
        CoreAddresses::assert_root(root_account);

        let (mint_cap, burn_cap) = Token::register_native_token<PONT>(
            root_account,
            10,
            b"PONT",
            b"PONT"
        );

        move_to(root_account, Drop {mint_cap, burn_cap});
    }
}
