/// The `Pontem` module describes the concept of a coin in the Pontem framework. It introduces the
/// resource `Pontem::Pontem<CoinType>`, representing a coin of given coin type.
/// The module defines functions operating on coins as well as functionality like
/// minting and burning of coins.
module PontemFramework::Pontem {
    use PontemFramework::CoreAddresses;
    use PontemFramework::NativeCurrencies;
    use Std::Errors;
    use Std::Event::{Self, EventHandle};
    use Std::Signer;
    use Std::Reflect;

    /// The `Pontem` resource defines the Pontem coin for each currency in
    /// Pontem. Each "coin" is coupled with a type `CoinType` specifying the
    /// currency of the coin, and a `value` field specifying the value
    /// of the coin (in the base units of the currency `CoinType`
    /// and specified in the `CurrencyInfo` resource for that `CoinType`
    /// published under the `@CurrencyInfo` account address).
    struct Pontem<phantom CoinType> has store {
        /// The value of this coin in the base units for `CoinType`
        value: u64
    }

    /// A `MintEvent` is emitted every time a Diem coin is minted. This
    /// contains the `amount` minted (in base units of the currency being
    /// minted) along with the `currency_code` for the coin(s) being
    /// minted, and that is defined in the `currency_code` field of the
    /// `CurrencyInfo` resource for the currency.
    struct MintEvent has drop, store {
        /// Funds added to the system
        amount: u64,
        /// ASCII encoded symbol for the coin type (e.g., "PONT")
        currency_code: vector<u8>,
    }

    /// A `BurnEvent` is emitted every time a non-synthetic Diem coin
    /// (i.e., a Diem coin with false `is_synthetic` field) is
    /// burned. It contains the `amount` burned in base units for the
    /// currency, along with the `currency_code` for the coins being burned
    /// (and as defined in the `CurrencyInfo` resource for that currency).
    /// It also contains the `preburn_address` from which the coin is
    /// extracted for burning.
    struct BurnEvent has drop, store {
        /// Funds removed from the system
        amount: u64,
        /// ASCII encoded symbol for the coin type (e.g., "PONT")
        currency_code: vector<u8>,
    }

     /// The `MintCapability` resource defines a capability to allow minting
    /// of coins of `CoinType` currency by the holder of this capability.
    /// This capability is held only either by the `CoreAddresses::TREASURY_COMPLIANCE_ADDRESS()`
    /// account or the `0x1::PONT` module (and `CoreAddresses::DIEM_ROOT_ADDRESS()` in testnet).
    struct MintCapability<phantom CoinType> has key, store {}

    /// The `BurnCapability` resource defines a capability to allow coins
    /// of `CoinType` currency to be burned by the holder of it.
    struct BurnCapability<phantom CoinType> has key, store {}

    /// The `CurrencyInfo<CoinType>` resource stores the various
    /// pieces of information needed for a currency (`CoinType`) that is
    /// registered on-chain. This resource _must_ be published under the
    /// address given by `@CurrencyInfo` in order for the registration of
    /// `CoinType` as a recognized currency on-chain to be successful. At
    /// the time of registration, the `MintCapability<CoinType>` and
    /// `BurnCapability<CoinType>` capabilities are returned to the caller.
    /// Unless they are specified otherwise the fields in this resource are immutable.
    struct CurrencyInfo<phantom CoinType> has key {
        /// The total value for the currency represented by `CoinType`. Mutable.
        total_value: u128,
        /// Amount of decimals.
        decimals: u8,
        /// The code symbol for this `CoinType`. ASCII encoded.
        /// e.g. for "PONT" this is x"504f4e54". No character limit.
        currency_code: vector<u8>,
        /// Minting of new currency of CoinType is allowed only if this field is true.
        /// We may want to disable the ability to mint further coins of a
        /// currency while that currency is still around. This allows us to
        /// keep the currency in circulation while disallowing further
        /// creation of coins in the `CoinType` currency. Mutable.
        can_mint: bool,
        /// Event stream for minting and where `MintEvent`s will be emitted.
        mint_events: EventHandle<MintEvent>,
        /// Event stream for burning, and where `BurnEvent`s will be emitted.
        burn_events: EventHandle<BurnEvent>,
    }

    /// Maximum u64 value.
    const MAX_U64: u64 = 18446744073709551615;
    /// Maximum u128 value.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// A property expected of a `CurrencyInfo` resource didn't hold
    const ECURRENCY_INFO: u64 = 1;
    /// Minting is not allowed for the specified currency
    const EMINTING_NOT_ALLOWED: u64 = 2;
    /// A property expected of the coin provided didn't hold
    const ECOIN: u64 = 3;
    /// The destruction of a non-zero coin was attempted. Non-zero coins must be burned.
    const EDESTRUCTION_OF_NONZERO_COIN: u64 = 4;
    /// A withdrawal greater than the value of the coin was attempted.
    const EAMOUNT_EXCEEDS_COIN_VALUE: u64 = 5;
    /// When currency registered not from deployer.
    const EWRONG_DEPLOYER: u64 = 6;

    /// Create a new `Pontem<CoinType>` with a value of `0`. Anyone can call
    /// this and it will be successful as long as `CoinType` is a registered currency.
    public fun zero<CoinType>(): Pontem<CoinType> {
        assert_is_currency<CoinType>();
        Pontem<CoinType> { value: 0 }
    }

    /// Returns the `value` of the passed in `coin`. The value is
    /// represented in the base units for the currency represented by
    /// `CoinType`.
    public fun value<CoinType>(coin: &Pontem<CoinType>): u64 {
        coin.value
    }

    /// Removes `amount` of value from the passed in `coin`. Returns the
    /// remaining balance of the passed in `coin`, along with another coin
    /// with value equal to `amount`. Calls will fail if `amount > Diem::value(&coin)`.
    public fun split<CoinType>(coin: Pontem<CoinType>, amount: u64): (Pontem<CoinType>, Pontem<CoinType>) {
        let other = withdraw(&mut coin, amount);
        (coin, other)
    }
    spec split {
        aborts_if coin.value < amount with Errors::LIMIT_EXCEEDED;
        ensures result_1.value == coin.value - amount;
        ensures result_2.value == amount;
    }


    /// Withdraw `amount` from the passed-in `coin`, where the original coin is modified in place.
    /// After this function is executed, the original `coin` will have
    /// `value = original_value - amount`, and the new coin will have a `value = amount`.
    /// Calls will abort if the passed-in `amount` is greater than the
    /// value of the passed-in `coin`.
    public fun withdraw<CoinType>(coin: &mut Pontem<CoinType>, amount: u64): Pontem<CoinType> {
        // Check that `amount` is less than the coin's value
        assert(coin.value >= amount, Errors::limit_exceeded(EAMOUNT_EXCEEDS_COIN_VALUE));
        coin.value = coin.value - amount;
        Pontem { value: amount }
    }
    spec withdraw {
        pragma opaque;
        include WithdrawAbortsIf<CoinType>;
        ensures coin.value == old(coin.value) - amount;
        ensures result.value == amount;
    }
    spec schema WithdrawAbortsIf<CoinType> {
        coin: Pontem<CoinType>;
        amount: u64;
        aborts_if coin.value < amount with Errors::LIMIT_EXCEEDED;
    }

    /// Return a `Pontem<CoinType>` worth `coin.value` and reduces the `value` of the input `coin` to
    /// zero. Does not abort.
    public fun withdraw_all<CoinType>(coin: &mut Pontem<CoinType>): Pontem<CoinType> {
        let val = coin.value;
        withdraw(coin, val)
    }
    spec withdraw_all {
        pragma opaque;
        aborts_if false;
        ensures result.value == old(coin.value);
        ensures coin.value == 0;
    }

    /// Takes two coins as input, returns a single coin with the total value of both coins.
    /// Destroys on of the input coins.
    public fun join<CoinType>(coin1: Pontem<CoinType>, coin2: Pontem<CoinType>): Pontem<CoinType>  {
        deposit(&mut coin1, coin2);
        coin1
    }
    spec join {
        pragma opaque;
        aborts_if coin1.value + coin2.value > max_u64() with Errors::LIMIT_EXCEEDED;
        ensures result.value == coin1.value + coin2.value;
    }


    /// "Merges" the two coins.
    /// The coin passed in by reference will have a value equal to the sum of the two coins
    /// The `check` coin is consumed in the process
    public fun deposit<CoinType>(coin: &mut Pontem<CoinType>, check: Pontem<CoinType>) {
        let Pontem { value } = check;
        assert(MAX_U64 - coin.value >= value, Errors::limit_exceeded(ECOIN));
        coin.value = coin.value + value;
    }
    spec deposit {
        pragma opaque;
        include DepositAbortsIf<CoinType>;
        ensures coin.value == old(coin.value) + check.value;
    }
    spec schema DepositAbortsIf<CoinType> {
        coin: Pontem<CoinType>;
        check: Pontem<CoinType>;
        aborts_if coin.value + check.value > MAX_U64 with Errors::LIMIT_EXCEEDED;
    }

    /// Destroy a zero-value coin. Calls will fail if the `value` in the passed-in `coin` is non-zero
    /// so it is impossible to "burn" any non-zero amount of `Diem` without having
    /// a `BurnCapability` for the specific `CoinType`.
    public fun destroy_zero<CoinType>(coin: Pontem<CoinType>) {
        let Pontem { value } = coin;
        assert(value == 0, Errors::invalid_argument(EDESTRUCTION_OF_NONZERO_COIN))
    }
    spec destroy_zero {
        pragma opaque;
        aborts_if coin.value > 0 with Errors::INVALID_ARGUMENT;
    }

    /// Mint new coins.
    public fun mint<CoinType>(
        value: u64,
        _capability: &MintCapability<CoinType>
    ): Pontem<CoinType> acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        let currency_code = currency_code<CoinType>();

        let deployer = get_deployer<CoinType>();

        // update market cap resource to reflect minting
        let info = borrow_global_mut<CurrencyInfo<CoinType>>(deployer);

        assert(info.can_mint, Errors::invalid_state(EMINTING_NOT_ALLOWED));
        assert(MAX_U128 - info.total_value >= (value as u128), Errors::limit_exceeded(ECURRENCY_INFO));
        
        info.total_value = info.total_value + (value as u128);

        Event::emit_event(
            &mut info.mint_events,
            MintEvent{
                amount: value,
                currency_code,
            }
        );

        Pontem<CoinType> { value }
    }
    spec mint_with_capability {
        pragma opaque;
        modifies global<CurrencyInfo<CoinType>>(get_deployer<CoinType>());
        ensures exists<CurrencyInfo<CoinType>>(get_deployer<CoinType>());
        include MintAbortsIf<CoinType>;
        include MintEnsures<CoinType>;
        include MintEmits<CoinType>;
    }
    spec schema MintAbortsIf<CoinType> {
        value: u64;
        include AbortsIfNoCurrency<CoinType>;
        aborts_if !spec_currency_info<CoinType>().can_mint with Errors::INVALID_STATE;
        aborts_if spec_currency_info<CoinType>().total_value + value > max_u128() with Errors::LIMIT_EXCEEDED;
    }
    spec schema MintEnsures<CoinType> {
        value: u64;
        result: Diem<CoinType>;
        let currency_info = global<CurrencyInfo<CoinType>>(get_deployer<CoinType>());
        let post post_currency_info = global<CurrencyInfo<CoinType>>(get_deployer<CoinType>());
        ensures exists<CurrencyInfo<CoinType>>(get_deployer<CoinType>());
        ensures post_currency_info == update_field(currency_info, total_value, currency_info.total_value + value);
        ensures result.value == value;
    }
    spec schema MintEmits<CoinType> {
        value: u64;
        let currency_info = global<CurrencyInfo<CoinType>>(get_deployer<CoinType>());
        let handle = currency_info.mint_events;
        let msg = MintEvent{
            amount: value,
            currency_code: currency_info.currency_code,
        };
        emits msg to handle if !currency_info.is_synthetic;
    }

    /// Burn coins.
    public fun burn<CoinType> (
        to_burn: &mut Pontem<CoinType>,
        _capability: &BurnCapability<CoinType>,
    ) acquires CurrencyInfo {
        assert_is_currency<CoinType>();

        let deployer = get_deployer<CoinType>();
        let currency_code = currency_code<CoinType>();

        // Destroying coins.
        let Pontem { value } = withdraw_all<CoinType>(to_burn);
        
        let info = borrow_global_mut<CurrencyInfo<CoinType>>(deployer);

        assert(info.total_value >= (value as u128), Errors::limit_exceeded(ECURRENCY_INFO));
        info.total_value = info.total_value - (value as u128);

        Event::emit_event(
            &mut info.burn_events,
            BurnEvent {
                amount: value,
                currency_code,
            }
        );
    }


    /// Register native currency.
    public fun register_native_currency<CoinType: store>(
        root_account: &signer,
        decimals: u8,
        currency_code: vector<u8>,
        native_key: vector<u8>
    ): (MintCapability<CoinType>, BurnCapability<CoinType>) {
        CoreAddresses::assert_root(root_account);
        NativeCurrencies::register_currency<CoinType>(root_account, native_key);

        register_currency<CoinType>(
            root_account,
            decimals,
            currency_code
        )
    }

    public fun register_currency<CoinType>(
        account: &signer,
        decimals: u8,
        currency_code: vector<u8>,
    ): (MintCapability<CoinType>, BurnCapability<CoinType>)
    {
        // assert it's called by token module deployer.
        let (deployer, _, _) = Reflect::type_of<CoinType>();
        assert(Signer::address_of(account) == deployer, Errors::custom(EWRONG_DEPLOYER));

        assert(
            !exists<CurrencyInfo<CoinType>>(Signer::address_of(account)),
            Errors::already_published(ECURRENCY_INFO)
        );

        move_to(account, CurrencyInfo<CoinType> {
            total_value: 0,
            decimals,
            currency_code: copy currency_code,
            can_mint: true,
            mint_events: Event::new_event_handle<MintEvent>(account),
            burn_events: Event::new_event_handle<BurnEvent>(account),
        });
        (MintCapability<CoinType>{}, BurnCapability<CoinType>{})
    }
    spec register_currency {
        include RegisterCurrencyAbortsIf<CoinType>;
        include RegisterCurrencyEnsures<CoinType>;
    }
    spec schema RegisterCurrencyAbortsIf<CoinType> {
        account: signer;
        currency_code: vector<u8>;
        decimals: u8;

        aborts_if exists<CurrencyInfo<CoinType>>(Signer::address_of(account))
            with Errors::ALREADY_PUBLISHED;
    }

    /// Returns the total amount of currency minted of type `CoinType`.
    public fun market_cap<CoinType>(): u128
    acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        borrow_global<CurrencyInfo<CoinType>>(get_deployer<CoinType>()).total_value
    }
    /// Returns the market cap of CoinType.
    spec fun spec_market_cap<CoinType>(): u128 {
        global<CurrencyInfo<CoinType>>(get_deployer<CoinType>()).total_value
    }

    /// Get deployer of token.
    fun get_deployer<CoinType>(): address {
        let (deployer, _, _) = Reflect::type_of<CoinType>();
        deployer
    }

    /// Returns `true` if the type `CoinType` is a registered currency.
    /// Returns `false` otherwise.
    public fun is_currency<CoinType>(): bool {
        let deployer = get_deployer<CoinType>();
        exists<CurrencyInfo<CoinType>>(deployer)
    }

    /// Returns the decimals for the `CoinType` currency as defined
    /// in its `CurrencyInfo`.
    public fun decimals<CoinType>(): u8
    acquires CurrencyInfo {
        let deployer = get_deployer<CoinType>();
        assert_is_currency<CoinType>();
        borrow_global<CurrencyInfo<CoinType>>(deployer).decimals
    }
    spec fun spec_decimals<CoinType>(): u8 {
        global<CurrencyInfo<CoinType>>(get_deployer<CoinType>()).decimals
    }

    /// Returns the currency code for the registered currency as defined in
    /// its `CurrencyInfo` resource.
    public fun currency_code<CoinType>(): vector<u8>
    acquires CurrencyInfo {
        let deployer = get_deployer<CoinType>();
        assert_is_currency<CoinType>();
        *&borrow_global<CurrencyInfo<CoinType>>(deployer).currency_code
    }
    spec currency_code {
        pragma opaque;
        include AbortsIfNoCurrency<CoinType>;
        ensures result == spec_currency_code<CoinType>();
    }
    spec fun spec_currency_code<CoinType>(): vector<u8> {
        spec_currency_info<CoinType>().currency_code
    }

    ///////////////////////////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////////////////////////

    /// Asserts that `CoinType` is a registered currency.
    public fun assert_is_currency<CoinType>() {
        assert(is_currency<CoinType>(), Errors::not_published(ECURRENCY_INFO));
    }
    spec assert_is_currency {
        pragma opaque;
        include AbortsIfNoCurrency<CoinType>;
    }
    spec schema AbortsIfNoCurrency<CoinType> {
        aborts_if !spec_is_currency<CoinType>() with Errors::NOT_PUBLISHED;
    }
}
