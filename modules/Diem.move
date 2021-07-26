address 0x1 {

/// The `Diem` module describes the concept of a coin in the Diem framework. It introduces the
/// resource `Diem::Diem<CoinType>`, representing a coin of given coin type.
/// The module defines functions operating on coins as well as functionality like
/// minting and burning of coins.
module Diem {
    use 0x1::CoreAddresses;
    use 0x1::Errors;
    use 0x1::Signer;
    use 0x1::Roles;
    use 0x1::NativeCurrencies;

    /// The `Diem` resource defines the Diem coin for each currency in
    /// Diem. Each "coin" is coupled with a type `CoinType` specifying the
    /// currency of the coin, and a `value` field specifying the value
    /// of the coin (in the base units of the currency `CoinType`
    /// and specified in the `CurrencyInfo` resource for that `CoinType`
    /// published under the `CoreAddresses::CURRENCY_INFO_ADDRESS()` account address).
    struct Diem<CoinType> has store {
        /// The value of this coin in the base units for `CoinType`
        value: u64
    }

    /// The `CurrencyInfo<CoinType>` resource stores the various
    /// pieces of information needed for a currency (`CoinType`) that is
    /// registered on-chain. This resource _must_ be published under the
    /// address given by `CoreAddresses::CURRENCY_INFO_ADDRESS()` in order for the registration of
    /// `CoinType` as a recognized currency on-chain to be successful. At
    /// the time of registration, the `MintCapability<CoinType>` and
    /// `BurnCapability<CoinType>` capabilities are returned to the caller.
    /// Unless they are specified otherwise the fields in this resource are immutable.
    struct CurrencyInfo<CoinType> has key {
        /// The total value for the currency represented by `CoinType`. Mutable.
        total_value: u128,
        /// Holds whether or not this currency is synthetic (contributes to the
        /// off-chain reserve) or not. An example of such a synthetic
        ///currency would be the PONT.
        is_synthetic: bool,
        /// The scaling factor for the coin (i.e. the amount to divide by
        /// to get to the human-readable representation for this currency).
        /// e.g. 10^6 for `XUS`
        scaling_factor: u64,
        /// The smallest fractional part (number of decimal places) to be
        /// used in the human-readable representation for the currency (e.g.
        /// 10^2 for `XUS` cents)
        fractional_part: u64,
        /// The code symbol for this `CoinType`. ASCII encoded.
        /// e.g. for "PONT" this is x"584458". No character limit.
        currency_code: vector<u8>
    }

    /// The maximum value for `CurrencyInfo.scaling_factor`
    const MAX_SCALING_FACTOR: u64 = 10000000000;

    /// Maximum u64 value.
    const MAX_U64: u64 = 18446744073709551615;
    /// Maximum u128 value.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// A property expected of a `CurrencyInfo` resource didn't hold
    const ECURRENCY_INFO: u64 = 1;
    /// The currency specified is a synthetic (non-fiat) currency
    const EIS_SYNTHETIC_CURRENCY: u64 = 6;
    /// A property expected of the coin provided didn't hold
    const ECOIN: u64 = 7;
    /// The destruction of a non-zero coin was attempted. Non-zero coins must be burned.
    const EDESTRUCTION_OF_NONZERO_COIN: u64 = 8;
    /// A withdrawal greater than the value of the coin was attempted.
    const EAMOUNT_EXCEEDS_COIN_VALUE: u64 = 10;

    /// Create a new `Diem<CoinType>` with a value of `0`. Anyone can call
    /// this and it will be successful as long as `CoinType` is a registered currency.
    public fun zero<CoinType: store>(): Diem<CoinType> {
        assert_is_currency<CoinType>();
        Diem<CoinType> { value: 0 }
    }

    /// Returns the `value` of the passed in `coin`. The value is
    /// represented in the base units for the currency represented by
    /// `CoinType`.
    public fun value<CoinType: store>(coin: &Diem<CoinType>): u64 {
        coin.value
    }

    /// Removes `amount` of value from the passed in `coin`. Returns the
    /// remaining balance of the passed in `coin`, along with another coin
    /// with value equal to `amount`. Calls will fail if `amount > Diem::value(&coin)`.
    public fun split<CoinType: store>(coin: Diem<CoinType>, amount: u64): (Diem<CoinType>, Diem<CoinType>) {
        let other = withdraw(&mut coin, amount);
        (coin, other)
    }

    /// Withdraw `amount` from the passed-in `coin`, where the original coin is modified in place.
    /// After this function is executed, the original `coin` will have
    /// `value = original_value - amount`, and the new coin will have a `value = amount`.
    /// Calls will abort if the passed-in `amount` is greater than the
    /// value of the passed-in `coin`.
    public fun withdraw<CoinType: store>(coin: &mut Diem<CoinType>, amount: u64): Diem<CoinType> {
        // Check that `amount` is less than the coin's value
        assert(coin.value >= amount, Errors::limit_exceeded(EAMOUNT_EXCEEDS_COIN_VALUE));
        coin.value = coin.value - amount;
        Diem { value: amount }
    }

    /// Return a `Diem<CoinType>` worth `coin.value` and reduces the `value` of the input `coin` to
    /// zero. Does not abort.
    public fun withdraw_all<CoinType: store>(coin: &mut Diem<CoinType>): Diem<CoinType> {
        let val = coin.value;
        withdraw(coin, val)
    }

    /// Takes two coins as input, returns a single coin with the total value of both coins.
    /// Destroys on of the input coins.
    public fun join<CoinType: store>(coin1: Diem<CoinType>, coin2: Diem<CoinType>): Diem<CoinType> {
        deposit(&mut coin1, coin2);
        coin1
    }

    /// "Merges" the two coins.
    /// The coin passed in by reference will have a value equal to the sum of the two coins
    /// The `check` coin is consumed in the process
    public fun deposit<CoinType: store>(coin: &mut Diem<CoinType>, check: Diem<CoinType>) {
        let Diem { value } = check;
        assert(MAX_U64 - coin.value >= value, Errors::limit_exceeded(ECOIN));
        coin.value = coin.value + value;
    }

    /// Destroy a zero-value coin. Calls will fail if the `value` in the passed-in `coin` is non-zero
    /// so it is impossible to "burn" any non-zero amount of `Diem` without having
    /// a `BurnCapability` for the specific `CoinType`.
    public fun destroy_zero<CoinType: store>(coin: Diem<CoinType>) {
        let Diem { value } = coin;
        assert(value == 0, Errors::invalid_argument(EDESTRUCTION_OF_NONZERO_COIN))
    }

    public fun register_native_currency<CoinType: store>(
        dr_account: &signer,
        scaling_factor: u64,
        fractional_part: u64,
        currency_code: vector<u8>,
        native_key: vector<u8>
    ) {
        NativeCurrencies::register_currency<CoinType>(dr_account, native_key);
        register_currency<CoinType>(
            dr_account,
            true,
            scaling_factor,
            fractional_part,
            currency_code
        )
    }
    ///////////////////////////////////////////////////////////////////////////
    // Definition of Currencies
    ///////////////////////////////////////////////////////////////////////////

    /// Register the type `CoinType` as a currency. Until the type is
    /// registered as a currency it cannot be used as a coin/currency unit in Diem.
    /// The passed-in `dr_account` must be a specific address (`CoreAddresses::CURRENCY_INFO_ADDRESS()`) and
    /// `dr_account` must also have the correct `DiemRoot` account role.
    /// After the first registration of `CoinType` as a
    /// currency, additional attempts to register `CoinType` as a currency
    /// will abort.
    /// When the `CoinType` is registered it publishes the
    /// `CurrencyInfo<CoinType>` resource under the `CoreAddresses::CURRENCY_INFO_ADDRESS()` and
    /// adds the currency to the set of `RegisteredCurrencies`. It returns
    /// `MintCapability<CoinType>` and `BurnCapability<CoinType>` resources.
    public fun register_currency<CoinType: store>(
        diem_root_acc: &signer,
        is_synthetic: bool,
        scaling_factor: u64,
        fractional_part: u64,
        currency_code: vector<u8>,
    ) {
        Roles::assert_diem_root(diem_root_acc);
        // Operational constraint that it must be stored under a specific address.
        CoreAddresses::assert_currency_info(diem_root_acc);
        assert(
            !exists<CurrencyInfo<CoinType>>(Signer::address_of(diem_root_acc)),
            Errors::already_published(ECURRENCY_INFO)
        );
        assert(0 < scaling_factor && scaling_factor <= MAX_SCALING_FACTOR, Errors::invalid_argument(ECURRENCY_INFO));
        move_to(diem_root_acc, CurrencyInfo<CoinType> {
            total_value: 0,
            is_synthetic,
            scaling_factor,
            fractional_part,
            currency_code: copy currency_code,
        });
    }

    /// Registers a stable currency (SCS) coin -- i.e., a non-synthetic currency.
    /// Resources are published on two distinct
    /// accounts: The `CoinInfo` is published on the Diem root account, and the mint and
    /// burn capabilities are published on a treasury compliance account.
    /// This code allows different currencies to have different treasury compliance
    /// accounts.
    public fun register_SCS_currency<CoinType: store>(
        dr_account: &signer,
        tc_account: &signer,
        scaling_factor: u64,
        fractional_part: u64,
        currency_code: vector<u8>,
    ) {
        Roles::assert_treasury_compliance(tc_account);
        register_currency<CoinType>(
            dr_account,
            false, // is_synthetic
            scaling_factor,
            fractional_part,
            currency_code,
        )
    }

    /// Returns the total amount of currency minted of type `CoinType`.
    public fun market_cap<CoinType: store>(): u128
    acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        borrow_global<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS()).total_value
    }

    /// Returns `true` if the type `CoinType` is a registered currency.
    /// Returns `false` otherwise.
    public fun is_currency<CoinType: store>(): bool {
        exists<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS())
    }

    public fun is_SCS_currency<CoinType: store>(): bool acquires CurrencyInfo {
        is_currency<CoinType>() &&
        !borrow_global<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS()).is_synthetic
    }


    /// Returns `true` if `CoinType` is a synthetic currency as defined in
    /// its `CurrencyInfo`. Returns `false` otherwise.
    public fun is_synthetic_currency<CoinType: store>(): bool
    acquires CurrencyInfo {
        let addr = CoreAddresses::CURRENCY_INFO_ADDRESS();
        exists<CurrencyInfo<CoinType>>(addr) &&
        borrow_global<CurrencyInfo<CoinType>>(addr).is_synthetic
    }

    /// Returns the scaling factor for the `CoinType` currency as defined
    /// in its `CurrencyInfo`.
    public fun scaling_factor<CoinType: store>(): u64
    acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        borrow_global<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS()).scaling_factor
    }

    /// Returns the representable (i.e. real-world) fractional part for the
    /// `CoinType` currency as defined in its `CurrencyInfo`.
    public fun fractional_part<CoinType: store>(): u64
    acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        borrow_global<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS()).fractional_part
    }

    /// Returns the currency code for the registered currency as defined in
    /// its `CurrencyInfo` resource.
    public fun currency_code<CoinType: store>(): vector<u8>
    acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        *&borrow_global<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS()).currency_code
    }

    ///////////////////////////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////////////////////////

    /// Asserts that `CoinType` is a registered currency.
    public fun assert_is_currency<CoinType: store>() {
        assert(is_currency<CoinType>(), Errors::not_published(ECURRENCY_INFO));
    }

    public fun assert_is_SCS_currency<CoinType: store>() acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        assert(is_SCS_currency<CoinType>(), Errors::invalid_state(ECURRENCY_INFO));
    }
}
}
