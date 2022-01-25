/// NOX (Nox Pontem Kusama) native token.
module PontemFramework::NOX {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Token;
    use PontemFramework::PontTimestamp;
    use Std::ASCII;

    const ERR_NOX_NATIVE_TOKEN_DOES_NOT_EXIST: u64 = 0;

    /// The resource to use if you want to work with NOX balances.
    struct NOX has key, store {}

    /// Just drop mint and burn capabilities by storing in inaccessible resource forever.
    struct NOXCapabilities has key {
        mint_cap: Token::MintCapability<NOX>,
        burn_cap: Token::BurnCapability<NOX>,
    }

    /// Registers the `NOX` token as native token. This can only be called from genesis.
    public fun initialize(
        root_account: &signer,
    ) {
        PontTimestamp::assert_genesis();
        CoreAddresses::assert_root(root_account);

        let (mint_cap, burn_cap) = Token::register_native_token<NOX>(
            root_account,
            10,
            ASCII::string(b"NOX"),
            b"NOX"
        );

        move_to(root_account, NOXCapabilities{ mint_cap, burn_cap });
    }

    #[test_only]
    public fun mint(root_acc: &signer, value: u64): Token::Token<NOX> acquires NOXCapabilities {
        assert!(
            PontemFramework::NativeToken::exists_native_token<NOX>(root_acc),
            Std::Errors::invalid_state(ERR_NOX_NATIVE_TOKEN_DOES_NOT_EXIST)
        );
        let mint_cap = &borrow_global<NOXCapabilities>(Std::Signer::address_of(root_acc)).mint_cap;
        Token::mint(value, mint_cap)
    }

    #[test_only]
    public fun burn(root_acc: &signer, to_burn: Token::Token<NOX>) acquires NOXCapabilities {
        assert!(
            PontemFramework::NativeToken::exists_native_token<NOX>(root_acc),
            Std::Errors::invalid_state(ERR_NOX_NATIVE_TOKEN_DOES_NOT_EXIST)
        );
        let burn_cap = &borrow_global<NOXCapabilities>(Std::Signer::address_of(root_acc)).burn_cap;
        Token::burn(to_burn, burn_cap)
    }
}
