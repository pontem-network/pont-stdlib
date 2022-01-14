/// PONT (Pontem) native token.
module PontemFramework::PONT {
    use PontemFramework::CoreAddresses;
    use PontemFramework::Token::{Self, Token};
    use PontemFramework::PontTimestamp;
    use PontemFramework::NativeToken;
    use Std::ASCII;
    use Std::Signer;

    const ERR_NO_PONT_TOKEN: u64 = 0;

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
            ASCII::string(b"PONT"),
            b"PONT"
        );

        move_to(root_account, Drop {mint_cap, burn_cap});
    }

    #[test_only]
    public fun mint(root_acc: &signer, value: u64): Token<PONT> acquires Drop {
        assert(
            NativeToken::exists_native_token<PONT>(root_acc),
            ERR_NO_PONT_TOKEN
        );
        let mint_cap = &borrow_global<Drop>(Signer::address_of(root_acc)).mint_cap;
        Token::mint(value, mint_cap)
    }
}
