/// Native tokens registration for Pontem Network.
/// Pontem node's using current module to connect native balances with VM's balances.
module PontemFramework::NativeToken {
    use Std::Errors;
    use Std::Signer;

    friend PontemFramework::Token;

    /// When native token already published
    const ERR_NATIVE_TOKEN: u64 = 0;

    /// The resource to store access path for `TokenType` native token
    struct NativeToken<phantom TokenType> has key, store {
        access_path: vector<u8>,
    }

    /// Register new native token
    public(friend) fun register_token<TokenType>(account: &signer, access_path: vector<u8>) {
        assert!(
            !exists_native_token<TokenType>(account),
            Errors::already_published(ERR_NATIVE_TOKEN)
        );
        move_to(account, NativeToken<TokenType> { access_path })
    }
    spec register_token {
        modifies global<NativeToken<TokenType>>(Signer::address_of(account));
    }

    public fun exists_native_token<TokenType>(account: &signer): bool {
        exists<NativeToken<TokenType>>(Signer::address_of(account))
    }
}
