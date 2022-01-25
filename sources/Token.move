/// The `Token` module describes the concept of a token in the Pontem framework. It introduces the
/// resource `Token::Token<TokenType>`, representing a token of given type.
/// The module defines functions operating on tokens as well as functionality like
/// minting and burning of tokens.
module PontemFramework::Token {
    use PontemFramework::CoreAddresses;
    use PontemFramework::NativeToken;
    use Std::Errors;
    use Std::Event::{Self, EventHandle};
    use Std::Signer;
    use Std::Reflect;
    use Std::ASCII::String;

    /// The `Token` resource defines the token in the Pontem ecosystem.
    /// Each "token" is coupled with a type `TokenType` specifying the
    /// token type, and a `value` field specifying the value of the token.
    struct Token<phantom TokenType> has store {
        /// The value of this token in the base units for `TokenType`
        value: u64
    }

    /// A `MintEvent` is emitted every time a Token is minted. This
    /// contains the `amount` minted (in base units of the token being
    /// minted) along with the `symbol` for the token(s) being
    /// minted, and that is defined in the `symbol` field of the `TokenInfo` 
    /// resource for the token.
    struct MintEvent has drop, store {
        /// Funds added to the system
        amount: u64,
        /// Symbol, e.g. "NOX".
        symbol: String,
    }

    /// A `BurnEvent` is emitted every time Token is burned.
    /// It contains the `amount` burned in base units for the
    /// token, along with the `symbol` for the tokens being burned.
    struct BurnEvent has drop, store {
        /// Funds removed from the system
        amount: u64,
        /// Symbol, e.g. "NOX".
        symbol: String,
    }

    /// The `MintCapability` resource defines a capability to allow minting
    /// of token of `TokenType` by the holder of this capability.
    /// This capability should be held by minter of the token or can be dropped.
    struct MintCapability<phantom TokenType> has key, store {}

    /// The `BurnCapability` resource defines a capability to allow tokens
    /// of `TokenType` token to be burned by the holder of it.
    /// This capability should be held by minter of the token or can be dropped.
    /// The token deployer can create additional functions in his token module to allow users to burn their tokens.
    struct BurnCapability<phantom TokenType> has key, store {}

    /// The `TokenInfo<TokenType>` resource stores the various
    /// pieces of information needed for a token (`TokenType`) that is
    /// registered on-chain. This resource _must_ be published under the
    /// address of token module deployer in order for the registration of
    /// `TokenType` as a recognized token on-chain to be successful. At
    /// the time of registration, the `MintCapability<TokenType>` and
    /// `BurnCapability<TokenType>` capabilities are returned to the caller.
    /// Unless they are specified otherwise the fields in this resource are immutable.
    struct TokenInfo<phantom TokenType> has key {
        /// The total value for the token represented by `TokenType`. Mutable.
        total_value: u128,
        /// Decimals amount of `TokenType` token.
        decimals: u8,
        /// The code symbol for this `TokenType`.
        /// e.g. for "NOX" this is x"504f4e54". No character limit.
        symbol: String,
        /// Event stream for minting and where `MintEvent`s will be emitted.
        mint_events: EventHandle<MintEvent>,
        /// Event stream for burning, and where `BurnEvent`s will be emitted.
        burn_events: EventHandle<BurnEvent>,
    }

    /// Maximum u64 value.
    const MAX_U64: u64 = 18446744073709551615;
    /// Maximum u128 value.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// A property expected of a `TokenInfo` resource didn't hold
    const ERR_TOKEN_INFO: u64 = 1;
    /// A property expected of the token provided didn't hold
    const ERR_TOKEN: u64 = 2;
    /// The destruction of a non-zero token was attempted. Non-zero tokens must be burned.
    const ERR_DESTRUCTION_OF_NONZERO_TOKEN: u64 = 3;
    /// A withdrawal greater than the value of the token was attempted.
    const ERR_AMOUNT_EXCEEDS_TOKEN_VALUE: u64 = 4;
    /// When token registered not from deployer.
    const ERR_ACC_IS_NOT_TOKEN_DEPLOYER: u64 = 5;

    /// Create a new `Token<TokenType>` with a value of `0`. Anyone can call
    /// this and it will be successful as long as `TokenType` is a registered token.
    public fun zero<TokenType>(): Token<TokenType> {
        assert_is_token<TokenType>();
        Token<TokenType> { value: 0 }
    }
    spec zero {
//        pragma opaque;
        aborts_if !is_token<TokenType>() with Errors::NOT_PUBLISHED;
        ensures result.value == 0;
    }

    /// Returns the `value` of the passed in `token`. The value is
    /// represented in the base units for the token represented by
    /// `TokenType`.
    public fun value<TokenType>(token: &Token<TokenType>): u64 {
        token.value
    }

    /// Removes `amount` of value from the passed in `token`. Returns the
    /// remaining balance of the passed in `token`, along with another token
    /// with value equal to `amount`. Calls will fail if `amount > Token::value(&token)`.
    public fun split<TokenType>(token: Token<TokenType>, amount: u64): (Token<TokenType>, Token<TokenType>) {
        let other = withdraw(&mut token, amount);
        (token, other)
    }
    spec split {
        aborts_if token.value < amount with Errors::LIMIT_EXCEEDED;
        ensures result_1.value == token.value - amount;
        ensures result_2.value == amount;
    }

    /// Withdraw `amount` from the passed-in `token`, where the original token is modified in place.
    /// After this function is executed, the original `token` will have
    /// `value = original_value - amount`, and the new token will have a `value = amount`.
    /// Calls will abort if the passed-in `amount` is greater than the
    /// value of the passed-in `token`.
    public fun withdraw<TokenType>(token: &mut Token<TokenType>, amount: u64): Token<TokenType> {
        // Check that `amount` is less than the token's value
        assert!(token.value >= amount, Errors::limit_exceeded(ERR_AMOUNT_EXCEEDS_TOKEN_VALUE));
        token.value = token.value - amount;
        Token { value: amount }
    }
    spec withdraw {
        pragma opaque;
        pragma verify = false;
        aborts_if false;
//        include WithdrawAborts<TokenType> { token, amount };

        ensures token.value == old(token.value) - amount;
        ensures result.value == amount;
    }
    spec schema WithdrawAborts<TokenType> {
        token: Token<TokenType>;
        amount: u64;

        aborts_if token.value < amount with Errors::LIMIT_EXCEEDED;
    }

    /// Return a `Token<TokenType>` worth `token.value` and reduces the `value` of the input `token` to
    /// zero. Does not abort.
    public fun withdraw_all<TokenType>(token: &mut Token<TokenType>): Token<TokenType> {
        let val = token.value;
        withdraw(token, val)
    }
    spec withdraw_all {
        pragma opaque;
        ensures result.value == old(token.value);
        ensures token.value == 0;
    }

    /// Takes two tokens as input, returns a single token with the total value of both tokens.
    /// Destroys on of the input tokens.
    public fun join<TokenType>(token1: Token<TokenType>, token2: Token<TokenType>): Token<TokenType>  {
        deposit(&mut token1, token2);
        token1
    }
    spec join {
        pragma opaque;
        aborts_if token1.value + token2.value > max_u64() with Errors::LIMIT_EXCEEDED;
        ensures result.value == token1.value + token2.value;
    }

    /// "Merges" the two tokens.
    /// The token passed in by reference will have a value equal to the sum of the two tokens
    /// The `check` tokens is consumed in the process
    public fun deposit<TokenType>(token: &mut Token<TokenType>, check: Token<TokenType>) {
        let Token { value } = check;
        assert!(MAX_U64 - token.value >= value, Errors::limit_exceeded(ERR_TOKEN));
        token.value = token.value + value;
    }
    spec deposit {
        pragma opaque;
        pragma verify = false;
        aborts_if false;
//        aborts_if false;
//        include AbortsIfDepositOverflow<TokenType>;
        ensures token.value == old(token.value) + check.value;
    }
    spec schema AbortsIfDepositOverflow<TokenType> {
        token: Token<TokenType>;
        check: Token<TokenType>;
        aborts_if token.value + check.value > MAX_U64 with Errors::LIMIT_EXCEEDED;
    }

    /// Destroy a zero-value token. Calls will fail if the `value` in the passed-in `token` is non-zero
    /// so it is impossible to "burn" any non-zero amount of `Pontem` without having
    /// a `BurnCapability` for the specific `TokenType`.
    public fun destroy_zero<TokenType>(token: Token<TokenType>) {
        let Token { value } = token;
        assert!(value == 0, Errors::invalid_argument(ERR_DESTRUCTION_OF_NONZERO_TOKEN))
    }
    spec destroy_zero {
        pragma opaque;
        aborts_if token.value > 0 with Errors::INVALID_ARGUMENT;
    }

    /// Mint new tokens of `TokenType`.
    /// The function requires `MintCapability`, returns created tokens `Token<TokenType>`.
    public fun mint<TokenType>(
        value: u64,
        _capability: &MintCapability<TokenType>
    ): Token<TokenType> acquires TokenInfo {
        assert_is_token<TokenType>();

        let symbol = symbol<TokenType>();
        let deployer_addr = get_deployer_addr<TokenType>();

        // update market cap resource to reflect minting
        let info = borrow_global_mut<TokenInfo<TokenType>>(deployer_addr);

        assert!(MAX_U128 - info.total_value >= (value as u128), Errors::limit_exceeded(ERR_TOKEN_INFO));

        info.total_value = info.total_value + (value as u128);

        Event::emit_event(
            &mut info.mint_events,
            MintEvent{
                amount: value,
                symbol,
            }
        );

        Token<TokenType> { value }
    }
    spec mint {
        pragma opaque;
        let deployer_addr = get_deployer_addr<TokenType>();
        modifies global<TokenInfo<TokenType>>(deployer_addr);
        ensures exists<TokenInfo<TokenType>>(deployer_addr);
        include MintAbortsIf<TokenType> { deployer_addr };
        include MintEnsures<TokenType>;
        include MintEmits<TokenType>;
    }
    spec schema MintAbortsIf<TokenType> {
        value: u64;
        deployer_addr: address;
        include AbortsIfTokenNotRegistered<TokenType>;
        let token_info = global<TokenInfo<TokenType>>(deployer_addr);
        aborts_if token_info.total_value + value > max_u128() with Errors::LIMIT_EXCEEDED;
    }
    spec schema MintEnsures<TokenType> {
        value: u64;
        result: Token<TokenType>;
        let deployer_addr = get_deployer_addr<TokenType>();
        let info = global<TokenInfo<TokenType>>(deployer_addr);
        let post post_info = global<TokenInfo<TokenType>>(deployer_addr);
        ensures exists<TokenInfo<TokenType>>(deployer_addr);
        ensures post_info == update_field(info, total_value, info.total_value + value);
        ensures result.value == value;
    }
    spec schema MintEmits<TokenType> {
        value: u64;
        let info = global<TokenInfo<TokenType>>(get_deployer_addr<TokenType>());
        let msg = MintEvent{
            amount: value,
            symbol: info.symbol,
        };
        emits msg to info.mint_events;
    }

    /// Burn `to_burn` tokens.
    /// The function requires `BurnCapability`.
    public fun burn<TokenType> (
        to_burn: Token<TokenType>,
        _capability: &BurnCapability<TokenType>,
    ) acquires TokenInfo {
        assert_is_token<TokenType>();

        let deployer_addr = get_deployer_addr<TokenType>();
        let symbol = symbol<TokenType>();

        // Destroying tokens.
        let Token { value } = to_burn;
        let info = borrow_global_mut<TokenInfo<TokenType>>(deployer_addr);

        assert!(info.total_value >= (value as u128), Errors::limit_exceeded(ERR_TOKEN_INFO));
        info.total_value = info.total_value - (value as u128);

        Event::emit_event(
            &mut info.burn_events,
            BurnEvent {
                amount: value,
                symbol,
            }
        );
    }

    /// Register native token.
    /// Only `@Root` can call it.
    /// The `native_key` used by Pontem node to match VM tokens and native ones.
    public fun register_native_token<TokenType: store>(
        root_account: &signer,
        decimals: u8,
        symbol: String,
        native_key: vector<u8>
    ): (MintCapability<TokenType>, BurnCapability<TokenType>) {
        CoreAddresses::assert_root(root_account);
        NativeToken::register_token<TokenType>(root_account, native_key);

        register_token<TokenType>(
            root_account,
            decimals,
            symbol
        )
    }

    /// Register new token. 
    /// Should be called the deployer of module contains `TokenType`.
    /// Registering new token.
    public fun register_token<TokenType>(
        account: &signer,
        decimals: u8,
        symbol: String,
    ): (MintCapability<TokenType>, BurnCapability<TokenType>)
    {
        // check it's called from module deployer.
        let deployer_addr = get_deployer_addr<TokenType>();
        assert!(Signer::address_of(account) == deployer_addr, Errors::custom(ERR_ACC_IS_NOT_TOKEN_DEPLOYER));

        assert!(
            !exists<TokenInfo<TokenType>>(Signer::address_of(account)),
            Errors::already_published(ERR_TOKEN_INFO)
        );

        move_to(account, TokenInfo<TokenType> {
            total_value: 0,
            decimals,
            symbol,
            mint_events: Event::new_event_handle<MintEvent>(account),
            burn_events: Event::new_event_handle<BurnEvent>(account),
        });
        (MintCapability<TokenType>{}, BurnCapability<TokenType>{})
    }
    spec register_token {
        include RegisterTokenAbortsIf<TokenType>;
    }
    spec schema RegisterTokenAbortsIf<TokenType> {
        decimals: u8;
        account: signer;

        let acc_addr = Signer::address_of(account);
        aborts_if exists<TokenInfo<TokenType>>(acc_addr) with Errors::ALREADY_PUBLISHED;
        aborts_if acc_addr != get_deployer_addr<TokenType>() with Errors::CUSTOM;
    }

    /// Returns the total amount of token minted of type `TokenType`.
    public fun total_value<TokenType>(): u128
    acquires TokenInfo {
        assert_is_token<TokenType>();
        borrow_global<TokenInfo<TokenType>>(get_deployer_addr<TokenType>()).total_value
    }
    /// Returns the market cap of `TokenType`.
    spec fun spec_total_value<TokenType>(): u128 {
        spec_token_info<TokenType>().total_value
    }

    /// Get deployer of token.
    fun get_deployer_addr<TokenType>(): address {
        let deployer_addr = Reflect::mod_address_of<TokenType>();
        // implementation detail:
        // Node signs deployment PontemFramework modules with @Root, but deploys them at @Std.
        // That @Std module -> @Root signature relationship should be reflected in get_deployer_addr() calls.
        if (deployer_addr == @Std) {
            @Root
        } else {
            deployer_addr
        }
    }

    /// Returns `true` if the type `TokenType` is a registered token.
    /// Returns `false` otherwise.
    public fun is_token<TokenType>(): bool {
        let deployer_addr = get_deployer_addr<TokenType>();
        exists<TokenInfo<TokenType>>(deployer_addr)
    }
    spec is_token {
//        pragma opaque;
        pragma verify = false;
        aborts_if false;
    }

    /// Returns the decimals for the `TokenType` token as defined
    /// in its `TokenInfo`.
    public fun decimals<TokenType>(): u8
    acquires TokenInfo {
        assert_is_token<TokenType>();
        let deployer = get_deployer_addr<TokenType>();
        borrow_global<TokenInfo<TokenType>>(deployer).decimals
    }
    spec fun spec_decimals<TokenType>(): u8 {
        spec_token_info<TokenType>().decimals
    }

    /// Returns the token code for the registered token as defined in
    /// its `TokenInfo` resource.
    public fun symbol<TokenType>(): String
    acquires TokenInfo {
//        assert_is_token<TokenType>();
        assert!(is_token<TokenType>(), Errors::not_published(ERR_TOKEN_INFO));
//        let deployer = get_deployer_addr<TokenType>();
        *&borrow_global<TokenInfo<TokenType>>(get_deployer_addr<TokenType>()).symbol
    }
    spec symbol {
        pragma opaque;
        include AbortsIfTokenNotRegistered<TokenType>;
        ensures result == spec_symbol<TokenType>();
    }
    spec fun spec_symbol<TokenType>(): String {
        spec_token_info<TokenType>().symbol
    }

    ///////////////////////////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////////////////////////

    /// Asserts that `TokenType` is a registered token.
    public fun assert_is_token<TokenType>() {
        assert!(is_token<TokenType>(), Errors::not_published(ERR_TOKEN_INFO));
    }
    spec assert_is_token {
        pragma opaque;
        include AbortsIfTokenNotRegistered<TokenType>;
    }
    spec schema AbortsIfTokenNotRegistered<TokenType> {
        aborts_if !is_token<TokenType>() with Errors::NOT_PUBLISHED;
    }

    spec fun spec_token_info<TokenType>(): TokenInfo<TokenType> {
        let deployer_addr = get_deployer_addr<TokenType>();
        global<TokenInfo<TokenType>>(deployer_addr)
    }
}
