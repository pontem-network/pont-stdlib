/// KSM (Kusama) native token.
module PontemFramework::KSM {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Token;
    use PontemFramework::PontTimestamp;
    use Std::ASCII;

    const ERR_NO_KSM_TOKEN: u64 = 0;

    /// The resource to use if you want to work with KSM balances.
    struct KSM has key, store {}

    /// Just drop mint and burn capabilities by storing in inaccessible resource forever.
    struct KSMCapabilities has key {
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
            ASCII::string(b"KSM"),
            b"KSM",
        );

        move_to(root_account, KSMCapabilities{ mint_cap, burn_cap });
    }

    #[test_only]
    public fun mint(root_acc: &signer, value: u64): Token::Token<KSM> acquires KSMCapabilities {
        assert!(
            PontemFramework::NativeToken::exists_native_token<KSM>(root_acc),
            ERR_NO_KSM_TOKEN
        );
        let mint_cap = &borrow_global<KSMCapabilities>(Std::Signer::address_of(root_acc)).mint_cap;
        Token::mint(value, mint_cap)
    }

    #[test_only]
    public fun burn(root_acc: &signer, to_burn: Token::Token<KSM>) acquires KSMCapabilities {
        assert!(
            PontemFramework::NativeToken::exists_native_token<KSM>(root_acc),
            ERR_NO_KSM_TOKEN
        );
        let burn_cap = &borrow_global<KSMCapabilities>(Std::Signer::address_of(root_acc)).burn_cap;
        Token::burn(to_burn, burn_cap)
    }
}
