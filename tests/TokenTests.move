module 0x42::UCOIN {
    use PontemFramework::Token::{Self, Token, MintCapability, BurnCapability};
    use Std::ASCII::string;

    struct UCOIN has key, store {}

    struct TokenCapabilities has key {
        mint_cap: MintCapability<UCOIN>,
        burn_cap: BurnCapability<UCOIN>
    }

    public fun register_ucoin_token(minter_acc: &signer) {
        let (mint_cap, burn_cap) =
            Token::register_token<UCOIN>(minter_acc, 8, string(b"UCOIN"));
        let token_caps = TokenCapabilities{ mint_cap, burn_cap };
        move_to(minter_acc, token_caps);
    }

    public fun mint(minter_acc: &signer, value: u64): Token<UCOIN> acquires TokenCapabilities {
        let mint_cap = &borrow_global<TokenCapabilities>(Std::Signer::address_of(minter_acc)).mint_cap;
        Token::mint(value, mint_cap)
    }

    public fun burn(minter_acc: &signer, to_burn: Token<UCOIN>) acquires TokenCapabilities {
        let burn_cap = &borrow_global<TokenCapabilities>(Std::Signer::address_of(minter_acc)).burn_cap;
        Token::burn(to_burn, burn_cap)
    }
}

#[test_only]
module PontemFramework::TokenTests {
    use 0x42::UCOIN::{Self, UCOIN};
    use PontemFramework::Token;
    use PontemFramework::Genesis;
    use PontemFramework::PontAccount;
    use Std::Signer;

    #[test(root_acc = @Root, minter_acc = @0x42, user_acc = @0x3)]
    fun test_custom_user_token(root_acc: signer, minter_acc: signer, user_acc: signer) {
        Genesis::setup(&root_acc, 1);
        UCOIN::register_ucoin_token(&minter_acc);

        let ucoins = UCOIN::mint(&minter_acc, 10);
        assert!(Token::value(&ucoins) == 10, 1);

        let user_addr = Signer::address_of(&user_acc);
        PontAccount::deposit(&minter_acc, user_addr, ucoins);
        assert!(PontAccount::balance<UCOIN>(user_addr) == 10, 2);

        let withdrawn_ucoins = PontAccount::withdraw<UCOIN>(&user_acc, 3);
        assert!(PontAccount::balance<UCOIN>(user_addr) == 7, 2);

        UCOIN::burn(&minter_acc, withdrawn_ucoins);
        assert!(Token::total_value<UCOIN>() == 7, 3);
    }
}
