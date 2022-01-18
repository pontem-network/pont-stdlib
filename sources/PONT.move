/// PONT (Pontem) native token.
module PontemFramework::PONT {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Token;
    use PontemFramework::PontTimestamp;
    use Std::ASCII;

    const ERR_PONT_NATIVE_TOKEN_DOES_NOT_EXIST: u64 = 0;

    /// The resource to use if you want to work with PONT balances.
    struct PONT has key, store {}

    /// Just drop mint and burn capabilities by storing in inaccessible resource forever.
    struct PONTCapabilities has key {
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
            ASCII::string(b"PONT"),
            b"PONT"
        );

        move_to(root_account, PONTCapabilities{ mint_cap, burn_cap });
    }

    #[test_only]
    public fun mint(root_acc: &signer, value: u64): Token::Token<PONT> acquires PONTCapabilities {
        assert!(
            PontemFramework::NativeToken::exists_native_token<PONT>(root_acc),
            Std::Errors::invalid_state(ERR_PONT_NATIVE_TOKEN_DOES_NOT_EXIST)
        );
        let mint_cap = &borrow_global<PONTCapabilities>(Std::Signer::address_of(root_acc)).mint_cap;
        Token::mint(value, mint_cap)
    }

    #[test_only]
    public fun burn(root_acc: &signer, to_burn: Token::Token<PONT>) acquires PONTCapabilities {
        assert!(
            PontemFramework::NativeToken::exists_native_token<PONT>(root_acc),
            Std::Errors::invalid_state(ERR_PONT_NATIVE_TOKEN_DOES_NOT_EXIST)
        );
        let burn_cap = &borrow_global<PONTCapabilities>(Std::Signer::address_of(root_acc)).burn_cap;
        Token::burn(to_burn, burn_cap)
    }
}
