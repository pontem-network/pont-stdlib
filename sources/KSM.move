/// KSM (Kusama) native token.
module PontemFramework::KSM {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Token;
    use PontemFramework::PontTimestamp;

    /// The resource to use if you want to work with KSM balances.
    struct KSM has key, store {}

    /// Just drop mint and burn capabilities by storing in inaccessible resource forever.
    struct Drop has key {
        mint_cap: Token::MintCapability<KSM>,
        burn_cap: Token::BurnCapability<KSM>,
    }

    /// Registers the `KSM` token as native token. This can only be called from genesis.
    public fun initialize(
        root_account: &signer,
    ) {
        PontTimestamp::assert_genesis();
        CoreAddresses::assert_root(root_account);

        let (mint_cap, burn_cap) = Token::register_native_token<KSM>(
            root_account,
            12,
            b"KSM",
            b"KSM",
        );

        move_to(root_account, Drop {mint_cap, burn_cap});
    }
}
