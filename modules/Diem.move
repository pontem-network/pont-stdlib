address 0x1 {

/// The `Diem` module describes the concept of a coin in the Diem framework. It introduces the
/// resource `Diem::Diem<CoinType>`, representing a coin of given coin type.
/// The module defines functions operating on coins as well as functionality like
/// minting and burning of coins.
module Diem {
    use 0x1::CoreAddresses;
    use 0x1::Errors;
    use 0x1::Event::{Self, EventHandle};
    use 0x1::Signer;
    use 0x1::Roles;
    use 0x1::Vector;
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

    /// The `MintCapability` resource defines a capability to allow minting
    /// of coins of `CoinType` currency by the holder of this capability.
    /// This capability is held only either by the `CoreAddresses::TREASURY_COMPLIANCE_ADDRESS()`
    /// account or the `0x1::PONT` module (and `CoreAddresses::DIEM_ROOT_ADDRESS()` in testnet).
    struct MintCapability<CoinType> has key, store {}

    /// The `BurnCapability` resource defines a capability to allow coins
    /// of `CoinType` currency to be burned by the holder of it.
    struct BurnCapability<CoinType> has key, store {}

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
        /// Address with the `PreburnQueue` resource that stored the now-burned funds
        preburn_address: address,
    }

    /// A `PreburnEvent` is emitted every time an `amount` of funds with
    /// a coin type `currency_code` is enqueued in the `PreburnQueue` resource under
    /// the account at the address `preburn_address`.
    struct PreburnEvent has drop, store {
        /// The amount of funds waiting to be removed (burned) from the system
        amount: u64,
        /// ASCII encoded symbol for the coin type (e.g., "PONT")
        currency_code: vector<u8>,
        /// Address with the `PreburnQueue` resource that now holds the funds
        preburn_address: address,
    }

    /// A `CancelBurnEvent` is emitted every time funds of `amount` in a `Preburn`
    /// resource held in a `PreburnQueue` at `preburn_address` is canceled (removed from the
    /// preburn queue, but not burned). The currency of the funds is given by the
    /// `currency_code` as defined in the `CurrencyInfo` for that currency.
    struct CancelBurnEvent has drop, store {
        /// The amount of funds returned
        amount: u64,
        /// ASCII encoded symbol for the coin type (e.g., "PONT")
        currency_code: vector<u8>,
        /// Address of the `PreburnQueue` resource that held the now-returned funds.
        preburn_address: address,
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
        /// Value of funds that are in the process of being burned.  Mutable.
        preburn_value: u64,
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
        /// Event stream for preburn requests, and where all
        /// `PreburnEvent`s for this `CoinType` will be emitted.
        preburn_events: EventHandle<PreburnEvent>,
        /// Event stream for all cancelled preburn requests for this
        /// `CoinType`.
        cancel_burn_events: EventHandle<CancelBurnEvent>
    }

    /// The maximum value for `CurrencyInfo.scaling_factor`
    const MAX_SCALING_FACTOR: u64 = 10000000000;

    /// A holding area where funds that will subsequently be burned wait while their underlying
    /// assets are moved off-chain.
    /// This resource can only be created by the holder of a `BurnCapability`
    /// or during an upgrade process to the `PreburnQueue` by a designated
    /// dealer. An account that contains this address has the authority to
    /// initiate a burn request. A burn request can be resolved by the holder
    /// of a `BurnCapability` by either (1) burning the funds, or (2) returning
    /// the funds to the account that initiated the burn request.
    struct Preburn<CoinType> has key, store {
        /// A single pending burn amount. This is an element in the
        /// `PreburnQueue` resource published under each Designated Dealer account.
        to_burn: Diem<CoinType>,
    }

    /// A preburn request, along with (an opaque to Move) metadata that is
    /// associated with the preburn request.
    struct PreburnWithMetadata<CoinType> has store {
        preburn: Preburn<CoinType>,
        metadata: vector<u8>,
    }

    /// A queue of preburn requests. This is a FIFO queue whose elements
    /// are indexed by the value held within each preburn resource in the
    /// `preburns` field. When burning or cancelling a burn of a given
    /// `amount`, the `Preburn` resource with with the smallest index in this
    /// queue matching `amount` in its `to_burn` coin's `value` field will be
    /// removed and its contents either (1) burned, or (2) returned
    /// back to the holding DD's account balance. Every `Preburn` resource in
    /// the `PreburnQueue` must have a nonzero coin value within it.
    /// This resource can be created by either the TreasuryCompliance
    /// account, or during the upgrade process, by a designated dealer with an
    /// existing `Preburn` resource in `CoinType`
    struct PreburnQueue<CoinType> has key {
        /// The queue of preburn requests
        preburns: vector<PreburnWithMetadata<CoinType>>,
    }

    /// Maximum u64 value.
    const MAX_U64: u64 = 18446744073709551615;
    /// Maximum u128 value.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// A `BurnCapability` resource is in an unexpected state.
    const EBURN_CAPABILITY: u64 = 0;
    /// A property expected of a `CurrencyInfo` resource didn't hold
    const ECURRENCY_INFO: u64 = 1;
    /// A property expected of a `Preburn` resource didn't hold
    const EPREBURN: u64 = 2;
    /// The preburn slot is already occupied with coins to be burned.
    const EPREBURN_OCCUPIED: u64 = 3;
    /// A burn was attempted on `Preburn` resource that cointained no coins
    const EPREBURN_EMPTY: u64 = 4;
    /// Minting is not allowed for the specified currency
    const EMINTING_NOT_ALLOWED: u64 = 5;
    /// The currency specified is a synthetic (non-fiat) currency
    const EIS_SYNTHETIC_CURRENCY: u64 = 6;
    /// A property expected of the coin provided didn't hold
    const ECOIN: u64 = 7;
    /// The destruction of a non-zero coin was attempted. Non-zero coins must be burned.
    const EDESTRUCTION_OF_NONZERO_COIN: u64 = 8;
    /// A property expected of `MintCapability` didn't hold
    const EMINT_CAPABILITY: u64 = 9;
    /// A withdrawal greater than the value of the coin was attempted.
    const EAMOUNT_EXCEEDS_COIN_VALUE: u64 = 10;
    /// A property expected of the `PreburnQueue` resource didn't hold.
    const EPREBURN_QUEUE: u64 = 11;
    /// A preburn with a matching amount in the preburn queue was not found.
    const EPREBURN_NOT_FOUND: u64 = 12;

    /// The maximum number of preburn requests that can be outstanding for a
    /// given designated dealer/currency.
    const MAX_OUTSTANDING_PREBURNS: u64 = 256;

    /// Publishes the `BurnCapability` `cap` for the `CoinType` currency under `account`. `CoinType`
    /// must be a registered currency type. The caller must pass a treasury compliance account.
    public fun publish_burn_capability<CoinType: store>(
        tc_account: &signer,
        cap: BurnCapability<CoinType>,
    ) {
        Roles::assert_treasury_compliance(tc_account);
        assert_is_currency<CoinType>();
        assert(
            !exists<BurnCapability<CoinType>>(Signer::address_of(tc_account)),
            Errors::already_published(EBURN_CAPABILITY)
        );
        move_to(tc_account, cap)
    }

    /// Burns the coins held in the first `Preburn` request in the `PreburnQueue`
    /// resource held under `preburn_address` that is equal to `amount`.
    /// Calls to this functions will fail if the `account` does not have a
    /// published `BurnCapability` for the `CoinType` published under it, or if
    /// there is not a `Preburn` request in the `PreburnQueue` that does not
    /// equal `amount`.
    public fun burn<CoinType: store>(
        account: &signer,
        preburn_address: address,
        amount: u64,
    ) acquires BurnCapability, CurrencyInfo, PreburnQueue {
        let addr = Signer::address_of(account);
        assert(exists<BurnCapability<CoinType>>(addr), Errors::requires_capability(EBURN_CAPABILITY));
        burn_with_capability(
            preburn_address,
            borrow_global<BurnCapability<CoinType>>(addr),
            amount
        )
    }

    /// Cancels the `Preburn` request in the `PreburnQueue` resource held
    /// under the `preburn_address` with a value equal to `amount`, and returns the coins.
    /// Calls to this will fail if the sender does not have a published
    /// `BurnCapability<CoinType>`, or if there is no preburn request
    /// outstanding in the `PreburnQueue` resource under `preburn_address` with
    /// a value equal to `amount`.
    public fun cancel_burn<CoinType: store>(
        account: &signer,
        preburn_address: address,
        amount: u64,
    ): Diem<CoinType> acquires BurnCapability, CurrencyInfo, PreburnQueue {
        let addr = Signer::address_of(account);
        assert(exists<BurnCapability<CoinType>>(addr), Errors::requires_capability(EBURN_CAPABILITY));
        cancel_burn_with_capability(
            preburn_address,
            borrow_global<BurnCapability<CoinType>>(addr),
            amount,
        )
    }

    /// Add the `coin` to the `preburn.to_burn` field in the `Preburn` resource
    /// held in the preburn queue at the address `preburn_address` if it is
    /// empty, otherwise raise a `EPREBURN_OCCUPIED` Error. Emits a
    /// `PreburnEvent` to the `preburn_events` event stream in the
    /// `CurrencyInfo` for the `CoinType` passed in. However, if the currency
    /// being preburned is a synthetic currency (`is_synthetic = true`) then no
    /// `PreburnEvent` will be emitted.
    fun preburn_with_resource<CoinType: store>(
        coin: Diem<CoinType>,
        preburn: &mut Preburn<CoinType>,
        preburn_address: address,
    ) acquires CurrencyInfo {
        let coin_value = value(&coin);
        // Throw if already occupied
        assert(value(&preburn.to_burn) == 0, Errors::invalid_state(EPREBURN_OCCUPIED));
        deposit(&mut preburn.to_burn, coin);
        let currency_code = currency_code<CoinType>();
        let info = borrow_global_mut<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS());
        assert(MAX_U64 - info.preburn_value >= coin_value, Errors::limit_exceeded(ECOIN));
        info.preburn_value = info.preburn_value + coin_value;
        // don't emit preburn events for synthetic currenices as this does not
        // change the total value of fiat currencies held on-chain, and
        // therefore no off-chain movement of the backing coins needs to be
        // performed.
        if (!info.is_synthetic) {
            Event::emit_event(
                &mut info.preburn_events,
                PreburnEvent{
                    amount: coin_value,
                    currency_code,
                    preburn_address,
                }
            );
        };
    }

    ///////////////////////////////////////////////////////////////////////////
    // Treasury Compliance specific methods for DDs
    ///////////////////////////////////////////////////////////////////////////

    /// Create a `Preburn<CoinType>` resource.
    /// This is useful for places where a module needs to be able to burn coins
    /// outside of a Designated Dealer, e.g., for transaction fees, or for the PONT reserve.
    public fun create_preburn<CoinType: store>(
        tc_account: &signer
    ): Preburn<CoinType> {
        Roles::assert_treasury_compliance(tc_account);
        assert_is_currency<CoinType>();
        Preburn<CoinType> { to_burn: zero<CoinType>() }
    }

    /// Publish an empty `PreburnQueue` resource under the Designated Dealer
    /// dealer account `account`.
    fun publish_preburn_queue<CoinType: store>(
        account: &signer
    ) {
        let account_addr = Signer::address_of(account);
        Roles::assert_designated_dealer(account);
        assert_is_currency<CoinType>();
        assert(
            !exists<Preburn<CoinType>>(account_addr),
            Errors::invalid_state(EPREBURN)
        );
        assert(
            !exists<PreburnQueue<CoinType>>(account_addr),
            Errors::already_published(EPREBURN_QUEUE)
        );
        move_to(account, PreburnQueue<CoinType> {
            preburns: Vector::empty()
        })
    }

    /// Publish a `Preburn` resource under `account`. This function is
    /// used for bootstrapping the designated dealer at account-creation
    /// time, and the association TC account `tc_account` (at `CoreAddresses::TREASURY_COMPLIANCE_ADDRESS()`) is creating
    /// this resource for the designated dealer `account`.
    public fun publish_preburn_queue_to_account<CoinType: store>(
        account: &signer,
        tc_account: &signer
    ) acquires CurrencyInfo {
        Roles::assert_designated_dealer(account);
        Roles::assert_treasury_compliance(tc_account);
        assert(!is_synthetic_currency<CoinType>(), Errors::invalid_argument(EIS_SYNTHETIC_CURRENCY));
        publish_preburn_queue<CoinType>(account)
    }
    ///////////////////////////////////////////////////////////////////////////


    /// Upgrade a designated dealer account from using a single `Preburn`
    /// resource to using a `PreburnQueue` resource so that multiple preburn
    /// requests can be outstanding in the same currency for a designated dealer.
    fun upgrade_preburn<CoinType: store>(account: &signer)
    acquires Preburn, PreburnQueue {
        Roles::assert_designated_dealer(account);
        let sender = Signer::address_of(account);
        let preburn_exists = exists<Preburn<CoinType>>(sender);
        let preburn_queue_exists = exists<PreburnQueue<CoinType>>(sender);
        // The DD must already have an existing `Preburn` resource, and not a
        // `PreburnQueue` resource already, in order to be upgraded.
        if (preburn_exists && !preburn_queue_exists) {
            let Preburn { to_burn } = move_from<Preburn<CoinType>>(sender);
            publish_preburn_queue<CoinType>(account);
            // If the DD has an old preburn balance, this is converted over
            // into the new preburn queue when it's upgraded.
            if (to_burn.value > 0)  {
                add_preburn_to_queue(account, PreburnWithMetadata {
                    preburn: Preburn { to_burn },
                    metadata: x"",
                })
            } else {
                destroy_zero(to_burn)
            };
        }
    }

    /// Add the `preburn` request to the preburn queue of `account`, and check that the
    /// number of preburn requests does not exceed `MAX_OUTSTANDING_PREBURNS`.
    fun add_preburn_to_queue<CoinType: store>(account: &signer, preburn: PreburnWithMetadata<CoinType>)
    acquires PreburnQueue {
        let account_addr = Signer::address_of(account);
        assert(exists<PreburnQueue<CoinType>>(account_addr), Errors::invalid_state(EPREBURN_QUEUE));
        assert(value(&preburn.preburn.to_burn) > 0, Errors::invalid_argument(EPREBURN));
        let preburns = &mut borrow_global_mut<PreburnQueue<CoinType>>(account_addr).preburns;
        assert(
            Vector::length(preburns) < MAX_OUTSTANDING_PREBURNS,
            Errors::limit_exceeded(EPREBURN_QUEUE)
        );
        Vector::push_back(preburns, preburn);
    }

    /// Sends `coin` to the preburn queue for `account`, where it will wait to either be burned
    /// or returned to the balance of `account`.
    /// Calls to this function will fail if:
    /// * `account` does not have a `PreburnQueue<CoinType>` resource published under it; or
    /// * the preburn queue is already at capacity (i.e., at `MAX_OUTSTANDING_PREBURNS`); or
    /// * `coin` has a `value` field of zero.
    public fun preburn_to<CoinType: store>(
        account: &signer,
        coin: Diem<CoinType>
    ) acquires CurrencyInfo, Preburn, PreburnQueue {
        Roles::assert_designated_dealer(account);
        // any coin that is preburned needs to have a nonzero value
        assert(value(&coin) > 0, Errors::invalid_argument(ECOIN));
        let sender = Signer::address_of(account);
        // After an upgrade a `Preburn` resource no longer exists in this
        // currency, and it is replaced with a `PreburnQueue` resource
        // for the same currency.
        upgrade_preburn<CoinType>(account);

        let preburn = PreburnWithMetadata {
            preburn: Preburn { to_burn: zero<CoinType>() },
            metadata: x"",
        };
        preburn_with_resource(coin, &mut preburn.preburn, sender);
        add_preburn_to_queue(account, preburn);
    }

    /// Remove the oldest preburn request in the `PreburnQueue<CoinType>`
    /// resource published under `preburn_address` whose value is equal to `amount`.
    /// Calls to this function will fail if:
    /// * `preburn_address` doesn't have a `PreburnQueue<CoinType>` resource published under it; or
    /// * a preburn request with the correct value for `amount` cannot be found in the preburn queue for `preburn_address`;
    fun remove_preburn_from_queue<CoinType: store>(preburn_address: address, amount: u64): PreburnWithMetadata<CoinType>
    acquires PreburnQueue {
        assert(exists<PreburnQueue<CoinType>>(preburn_address), Errors::not_published(EPREBURN_QUEUE));
        // We search from the head of the queue
        let index = 0;
        let preburn_queue = &mut borrow_global_mut<PreburnQueue<CoinType>>(preburn_address).preburns;
        let queue_length = Vector::length(preburn_queue);

        while (index < queue_length) {
            let elem = Vector::borrow(preburn_queue, index);
            if (value(&elem.preburn.to_burn) == amount) {
                let preburn = Vector::remove(preburn_queue, index);
                // Make sure that the value is correct
                return preburn
            };
            index = index + 1;
        };

        // If we didn't return already, we couldn't find a preburn with a matching value.
        abort Errors::invalid_state(EPREBURN_NOT_FOUND)
    }

    /// Permanently removes the coins in the oldest preburn request in the
    /// `PreburnQueue` resource under `preburn_address` that has a `to_burn`
    /// value of `amount` and updates the market cap accordingly.
    /// This function can only be called by the holder of a `BurnCapability<CoinType: store>`.
    /// Calls to this function will fail if the there is no `PreburnQueue<CoinType: store>`
    /// resource under `preburn_address`, or, if there is no preburn request in
    /// the preburn queue with a `to_burn` amount equal to `amount`.
    public fun burn_with_capability<CoinType: store>(
        preburn_address: address,
        capability: &BurnCapability<CoinType>,
        amount: u64,
    ) acquires CurrencyInfo, PreburnQueue {

        // Remove the preburn request
        let PreburnWithMetadata{ preburn, metadata: _ } = remove_preburn_from_queue<CoinType>(preburn_address, amount);

        // Burn the contained coins
        burn_with_resource_cap(&mut preburn, preburn_address, capability);

        let Preburn { to_burn } = preburn;
        destroy_zero(to_burn);
    }

    /// Permanently removes the coins held in the `Preburn` resource (in `to_burn` field)
    /// that was stored in a `PreburnQueue` at `preburn_address` and updates the market cap accordingly.
    /// This function can only be called by the holder of a `BurnCapability<CoinType: store>`.
    /// Calls to this function will fail if the preburn `to_burn` area for `CoinType` is empty.
    fun burn_with_resource_cap<CoinType: store>(
        preburn: &mut Preburn<CoinType>,
        preburn_address: address,
        _capability: &BurnCapability<CoinType>
    ) acquires CurrencyInfo {
        let currency_code = currency_code<CoinType>();
        // Abort if no coin present in preburn area
        assert(preburn.to_burn.value > 0, Errors::invalid_state(EPREBURN_EMPTY));
        // destroy the coin in Preburn area
        let Diem { value } = withdraw_all<CoinType>(&mut preburn.to_burn);
        // update the market cap
        assert_is_currency<CoinType>();
        let info = borrow_global_mut<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS());
        assert(info.total_value >= (value as u128), Errors::limit_exceeded(ECURRENCY_INFO));
        info.total_value = info.total_value - (value as u128);
        assert(info.preburn_value >= value, Errors::limit_exceeded(EPREBURN));
        info.preburn_value = info.preburn_value - value;
        // don't emit burn events for synthetic currenices as this does not
        // change the total value of fiat currencies held on-chain.
        if (!info.is_synthetic) {
            Event::emit_event(
                &mut info.burn_events,
                BurnEvent {
                    amount: value,
                    currency_code,
                    preburn_address,
                }
            );
        };
    }

    /// Cancels the oldest preburn request held in the `PreburnQueue` resource under
    /// `preburn_address` with a `to_burn` amount matching `amount`. It then returns these coins to the caller.
    /// This function can only be called by the holder of a
    /// `BurnCapability<CoinType>`, and will fail if the `PreburnQueue<CoinType>` resource
    /// at `preburn_address` does not contain a preburn request of the right amount.
    public fun cancel_burn_with_capability<CoinType: store>(
        preburn_address: address,
        _capability: &BurnCapability<CoinType>,
        amount: u64,
    ): Diem<CoinType> acquires CurrencyInfo, PreburnQueue {

        // destroy the coin in the preburn area
        let PreburnWithMetadata{ preburn: Preburn { to_burn }, metadata: _ } = remove_preburn_from_queue<CoinType>(preburn_address, amount);

        // update the market cap
        let currency_code = currency_code<CoinType>();
        let info = borrow_global_mut<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS());
        assert(info.preburn_value >= amount, Errors::limit_exceeded(EPREBURN));
        info.preburn_value = info.preburn_value - amount;
        // Don't emit cancel burn events for synthetic currencies. cancel_burn
        // shouldn't be be used for synthetic coins in the first place.
        if (!info.is_synthetic) {
            Event::emit_event(
                &mut info.cancel_burn_events,
                CancelBurnEvent {
                    amount,
                    currency_code,
                    preburn_address,
                }
            );
        };

        to_burn
    }

    /// A shortcut for immediately burning a coin. This calls preburn followed by a subsequent burn, and is
    /// used for administrative burns, like unpacking an PONT coin or charging fees.
    public fun burn_now<CoinType: store>(
        coin: Diem<CoinType>,
        preburn: &mut Preburn<CoinType>,
        preburn_address: address,
        capability: &BurnCapability<CoinType>
    ) acquires CurrencyInfo {
        assert(coin.value > 0, Errors::invalid_argument(ECOIN));
        preburn_with_resource(coin, preburn, preburn_address);
        burn_with_resource_cap(preburn, preburn_address, capability);
    }

    /// Removes and returns the `BurnCapability<CoinType>` from `account`.
    /// Calls to this function will fail if `account` does  not have a
    /// published `BurnCapability<CoinType>` resource at the top-level.
    public fun remove_burn_capability<CoinType: store>(account: &signer): BurnCapability<CoinType>
    acquires BurnCapability {
        let addr = Signer::address_of(account);
        assert(exists<BurnCapability<CoinType>>(addr), Errors::requires_capability(EBURN_CAPABILITY));
        move_from<BurnCapability<CoinType>>(addr)
    }

    /// Returns the total value of `Diem<CoinType>` that is waiting to be
    /// burned throughout the system (i.e. the sum of all outstanding
    /// preburn requests across all preburn resources for the `CoinType`
    /// currency).
    public fun preburn_value<CoinType: store>(): u64 acquires CurrencyInfo {
        assert_is_currency<CoinType>();
        borrow_global<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS()).preburn_value
    }

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
    public fun join<CoinType: store>(coin1: Diem<CoinType>, coin2: Diem<CoinType>): Diem<CoinType>  {
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
        native_key: vector<u8>): (MintCapability<CoinType>, BurnCapability<CoinType>) {
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
    ): (MintCapability<CoinType>, BurnCapability<CoinType>)
    {
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
            preburn_value: 0,
            is_synthetic,
            scaling_factor,
            fractional_part,
            currency_code: copy currency_code,
            can_mint: true,
            mint_events: Event::new_event_handle<MintEvent>(diem_root_acc),
            burn_events: Event::new_event_handle<BurnEvent>(diem_root_acc),
            preburn_events: Event::new_event_handle<PreburnEvent>(diem_root_acc),
            cancel_burn_events: Event::new_event_handle<CancelBurnEvent>(diem_root_acc)
        });
        (MintCapability<CoinType>{}, BurnCapability<CoinType>{})
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
        let (mint_cap, burn_cap) =
            register_currency<CoinType>(
                dr_account,
                false,   // is_synthetic
                scaling_factor,
                fractional_part,
                currency_code,
            );
        assert(
            !exists<MintCapability<CoinType>>(Signer::address_of(tc_account)),
            Errors::already_published(EMINT_CAPABILITY)
        );
        move_to(tc_account, mint_cap);
        publish_burn_capability<CoinType>(tc_account, burn_cap);
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

    /// There may be situations in which we disallow the further minting of
    /// coins in the system without removing the currency. This function
    /// allows the association treasury compliance account to control whether or not further coins of
    /// `CoinType` can be minted or not. If this is called with `can_mint = true`,
    /// then minting is allowed, if `can_mint = false` then minting is
    /// disallowed until it is turned back on via this function. All coins
    /// start out in the default state of `can_mint = true`.
    public fun update_minting_ability<CoinType: store>(
        tc_account: &signer,
        can_mint: bool,
        )
    acquires CurrencyInfo {
        Roles::assert_treasury_compliance(tc_account);
        assert_is_currency<CoinType>();
        let currency_info = borrow_global_mut<CurrencyInfo<CoinType>>(CoreAddresses::CURRENCY_INFO_ADDRESS());
        currency_info.can_mint = can_mint;
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
