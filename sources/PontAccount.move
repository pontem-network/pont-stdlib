module PontemFramework::PontAccount {
    use PontemFramework::PontTimestamp;
    use PontemFramework::Pontem::{Self, Pontem};
    use Std::Event::{Self, EventHandle};
    use Std::Errors;
    use Std::Signer;

    struct PontAccount has key {
        /// Event handle to which ReceivePaymentEvents are emitted when
        /// payments are received.
        received_events: EventHandle<ReceivedPaymentEvent>,
        /// Event handle to which SentPaymentEvents are emitted when
        /// payments are sent.
        sent_events: EventHandle<SentPaymentEvent>,
    }

    /// A resource that holds the total value of currency of type `Token`
    /// currently held by the account.
    struct Balance<phantom Token> has key {
        /// Stores the value of the balance in its balance field. A coin has
        /// a `value` field. The amount of money in the balance is changed
        /// by modifying this field.
        coin: Pontem<Token>,
    }

    /// Message for sent events
    struct SentPaymentEvent has drop, store {
        /// The amount of Pontem<Token> sent
        amount: u64,
        /// The code symbol for the currency that was sent
        currency_code: vector<u8>,
        /// The address that was paid
        payee: address,
        /// Metadata associated with the payment
        metadata: vector<u8>,
    }

    /// Message for received events
    struct ReceivedPaymentEvent has drop, store {
        /// The amount of Pontem<Token> received
        amount: u64,
        /// The code symbol for the currency that was received
        currency_code: vector<u8>,
        /// The address that sent the coin
        payer: address,
        /// Metadata associated with the payment
        metadata: vector<u8>,
    }

    const MAX_U64: u128 = 18446744073709551615;

    /// The `PontAccount` resource is not in the required state
    const EACCOUNT: u64 = 0;
    /// Tried to deposit a coin whose value was zero
    const ECOIN_DEPOSIT_IS_ZERO: u64 = 1;
    /// The account does not hold a large enough balance in the specified currency
    const EINSUFFICIENT_BALANCE: u64 = 2;
    /// Tried to add a balance in a currency that this account already has
    const EADD_EXISTING_CURRENCY: u64 = 3;
    /// Tried to withdraw funds in a currency that the account does hold
    const EPAYER_DOESNT_HOLD_CURRENCY: u64 = 4;
    /// An account cannot be created at the reserved core code address of 0x1
    const ECANNOT_CREATE_AT_CORE_CODE: u64 = 5;

    /// If `Balance<Token>` exists on account.
    fun balance_exists<Token>(account: address): bool {
        exists<Balance<Token>>(account)
    }

    /// If `PontAccount` exists on account.
    fun account_exists(account: address): bool {
        exists<PontAccount>(account)   
    }

    fun create_account(account: &signer) {
        assert(
            Signer::address_of(account) != @PontemFramework,
            Errors::invalid_argument(ECANNOT_CREATE_AT_CORE_CODE)
        );

        move_to(account, PontAccount {
            received_events: Event::new_event_handle<ReceivedPaymentEvent>(account),
            sent_events: Event::new_event_handle<SentPaymentEvent>(account),
        });
    }

    /// Deposit `Pontem<Token>` to payee account.
    public fun deposit<Token>(
        payer: &signer,
        payee: address,
        to_deposit: Pontem<Token>,
        metadata: vector<u8>,
    ) acquires PontAccount, Balance {
        PontTimestamp::assert_operating();

        // Check that the `to_deposit` coin is non-zero
        let deposit_value = Pontem::value(&to_deposit);
        assert(deposit_value > 0, Errors::invalid_argument(ECOIN_DEPOSIT_IS_ZERO));

        // Create signer for payee.
        let payee_account = create_signer(payee);

        // Check that an account exists at `payee`
        if (!account_exists(payee)) {
            create_account(&payee_account);
        };

        if (!balance_exists<Token>(payee)) {
            add_currency<Token>(&payee_account);
        };

        // Deposit the `to_deposit` coin
        Pontem::deposit(&mut borrow_global_mut<Balance<Token>>(payee).coin, to_deposit);

        // Log a received event
        Event::emit_event<ReceivedPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payee).received_events,
            ReceivedPaymentEvent {
                amount: deposit_value,
                currency_code: Pontem::currency_code<Token>(),
                payer: Signer::address_of(payer),
                metadata
            }
        );
    }
    spec deposit {
        pragma opaque;
        modifies global<Balance<Token>>(payee);
        modifies global<PontAccount>(payee);
        let amount = to_deposit.value;
        include DepositAbortsIf<Token>{amount: amount};
        include DepositEnsures<Token>{amount: amount};
        include DepositEmits<Token>{amount: amount};
    }
    spec schema DepositAbortsIf<Token> {
        payer: address;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        include DepositAbortsIfRestricted<Token>;
        aborts_if !exists<Balance<Token>>(payee) with Errors::INVALID_ARGUMENT;
        aborts_if !exists_at(payee) with Errors::NOT_PUBLISHED;
    }
    spec schema DepositOverflowAbortsIf<Token> {
        payee: address;
        amount: u64;
        aborts_if balance<Token>(payee) + amount > max_u64() with Errors::LIMIT_EXCEEDED;
    }
    spec schema DepositAbortsIfRestricted<Token> {
        payer: &signer;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        include PontTimestamp::AbortsIfNotOperating;
        aborts_if amount == 0 with Errors::INVALID_ARGUMENT;
        include Pontem::AbortsIfNoCurrency<Token>;
    }
    spec schema DepositEnsures<Token> {
        payee: address;
        amount: u64;

        // TODO(wrwg): precisely specify what changed in the modified resources using `update_field`
        ensures exists<Balance<Token>>(payee);
        ensures balance<Token>(payee) == old(balance<Token>(payee)) + amount;

        ensures exists<PontAccount>(payee);

        ensures Event::spec_guid_eq(global<PontAccount>(payee).sent_events,
                                    old(global<PontAccount>(payee).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payee).received_events,
                                    old(global<PontAccount>(payee).received_events));
    }
    spec schema DepositEmits<Token> {
        payer: address;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let handle = global<PontAccount>(payee).received_events;
        let msg = ReceivedPaymentEvent {
            amount,
            currency_code: Pontem::spec_currency_code<Token>(),
            payer,
            metadata
        };
        emits msg to handle;
    }

    /// Helper to withdraw `amount` from the given account balance and return the withdrawn Diem<Token>
    fun withdraw_from_balance<Token>(
        balance: &mut Balance<Token>,
        amount: u64
    ): Pontem<Token> {
        PontTimestamp::assert_operating();

        let coin = &mut balance.coin;

        // Abort if this withdrawal would make the `payer`'s balance go negative
        assert(Pontem::value(coin) >= amount, Errors::limit_exceeded(EINSUFFICIENT_BALANCE));
        Pontem::withdraw(coin, amount)
    }
    spec withdraw_from_balance {
        include WithdrawFromBalanceAbortsIf<Token>;
        include WithdrawFromBalanceEnsures<Token>;
    }
    spec schema WithdrawFromBalanceEnsures<Token> {
        balance: Balance<Token>;
        amount: u64;
        result: Pontem<Token>;
        ensures balance.coin.value == old(balance.coin.value) - amount;
        ensures result.value == amount;
    }

    /// Withdraw `amount` `Pontem<Token>`'s from the account balance and return.
    public fun withdraw<Token>(
        payer: &signer,
        amount: u64,
    ): Pontem<Token> acquires Balance {
        PontTimestamp::assert_operating();

        let payer_address = Signer::address_of(payer);
        assert(exists<Balance<Token>>(payer_address), Errors::not_published(EPAYER_DOESNT_HOLD_CURRENCY));

        let account_balance = borrow_global_mut<Balance<Token>>(payer_address);   

        withdraw_from_balance<Token>(account_balance, amount)
    }

    /// Withdraw `amount` `Pontem<Token>`'s from the account balance.
    fun withdraw_from<Token>(
        payer: &signer,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ): Pontem<Token> acquires Balance, PontAccount {
        PontTimestamp::assert_operating();
        
        let payer_address = Signer::address_of(payer);

        // Check that an account exists at `payee`
        if (!account_exists(payer_address)) {
            create_account(payer);
        };

        if (!balance_exists<Token>(payer_address)) {
            add_currency<Token>(payer);
        };

        let account_balance = borrow_global_mut<Balance<Token>>(payer_address);

        // Load the payer's account and emit an event to record the withdrawal
        Event::emit_event<SentPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payer_address).sent_events,
            SentPaymentEvent {
                amount,
                currency_code: Pontem::currency_code<Token>(),
                payee,
                metadata
            },
        );
        withdraw_from_balance<Token>(account_balance, amount)
    }
    spec withdraw_from {
        let payer = cap.account_address;
        modifies global<Balance<Token>>(payer);
        modifies global<PontAccount>(payer);
        ensures exists<PontAccount>(payer);
        ensures Event::spec_guid_eq(global<DiemAccount>(payer).sent_events,
                                    old(global<DiemAccount>(payer).sent_events));
        ensures Event::spec_guid_eq(global<DiemAccount>(payer).received_events,
                                    old(global<DiemAccount>(payer).received_events));
        include WithdrawFromAbortsIf<Token>;
        include WithdrawFromBalanceEnsures<Token>{balance: global<Balance<Token>>(payer)};
        include WithdrawOnlyFromCapAddress<Token>;
        include WithdrawFromEmits<Token>;
    }
    spec schema WithdrawFromAbortsIf<Token> {
        payer: &signer;
        payee: address;
        amount: u64;
        include PontTimestamp::AbortsIfNotOperating;
        include Pontem::AbortsIfNoCurrency<Token>;
        include WithdrawFromBalanceAbortsIf<Token>{payer, balance: global<Balance<Token>>(payer)};
    }
    spec schema WithdrawFromEmits<Token> {
        payer: &signer;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let handle = global<PontAccount>(payer).sent_events;
        let msg = SentPaymentEvent {
            amount,
            currency_code: Pontem::spec_currency_code<Token>(),
            payee,
            metadata
        };
        emits msg to handle;
    }

    /// Withdraw the balance from payer account and deposit to payee.
    public fun pay_from<Token>(
        payer: &signer,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ) acquires PontAccount, Balance {
        deposit<Token>(
            payer,
            payee,
            withdraw_from(payer, payee, amount, copy metadata),
            metadata
        );
    }
    spec schema PayFromWithoutDualAttestation<Token> {
        payer: &signer;
        payee: address;
        amount: u64;
        metadata: vector<u8>;

        modifies global<PontAccount>(payer);
        modifies global<PontAccount>(payee);
        modifies global<Balance<Token>>(payer);
        modifies global<Balance<Token>>(payee);
        ensures exists_at(payer);
        ensures exists_at(payee);
        ensures exists<Balance<Token>>(payer);
        ensures exists<Balance<Token>>(payee);
        ensures Event::spec_guid_eq(global<PontAccount>(payer).sent_events,
                                    old(global<PontAccount>(payer).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payer).received_events,
                                    old(global<PontAccount>(payer).received_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payee).sent_events,
                                    old(global<PontAccount>(payee).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payee).received_events,
                                    old(global<PontAccount>(payee).received_events));
        include PayFromAbortsIf<Token>;
        include PayFromEnsures<Token>{payer};
        include PayFromEmits<Token>;
    }
    spec schema PayFromEnsures<Token> {
        payer: address;
        payee: address;
        amount: u64;
        ensures payer == payee ==> balance<Token>(payer) == old(balance<Token>(payer));
        ensures payer != payee ==> balance<Token>(payer) == old(balance<Token>(payer)) - amount;
        ensures payer != payee ==> balance<Token>(payee) == old(balance<Token>(payee)) + amount;
    }
    spec schema PayFromEmits<Token> {
        cap: WithdrawCapability;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let payer = cap.account_address;
        include DepositEmits<Token>{payer: payer};
        include WithdrawFromEmits<Token>;
    }

    /// Add new currency to account.
    fun add_currencies_for_account<Token>(
        account: &signer,
    ) {
        add_currency<Token>(account);
    }
    spec add_currencies_for_account {
        let new_account_addr = Signer::address_of(account);
        aborts_if exists<Balance<Token>>(new_account_addr) with Errors::ALREADY_PUBLISHED;
        aborts_if !exists_at(new_account_addr) with Errors::NOT_PUBLISHED;
    }

    ///////////////////////////////////////////////////////////////////////////
    // General purpose methods
    ///////////////////////////////////////////////////////////////////////////
    native fun create_signer(addr: address): signer;

    /// Helper to return the u64 value of the `balance` for `account`
    fun balance_for<Token>(balance: &Balance<Token>): u64 {
        Pontem::value<Token>(&balance.coin)
    }

    /// Return the current balance of the account at `addr`.
    public fun balance<Token>(addr: address): u64 acquires Balance {
        assert(exists<Balance<Token>>(addr), Errors::not_published(EPAYER_DOESNT_HOLD_CURRENCY));
        balance_for(borrow_global<Balance<Token>>(addr))
    }
    spec balance {
        aborts_if !exists<Balance<Token>>(addr) with Errors::NOT_PUBLISHED;
    }

    /// Add a balance of `Token` type to the sending account.
    public fun add_currency<Token>(account: &signer) {
        let addr = Signer::address_of(account);

        // aborts if `Token` is not a currency type in the system
        Pontem::assert_is_currency<Token>();
        
        // aborts if this account already has a balance in `Token`
        assert(
            !exists<Balance<Token>>(addr),
            Errors::already_published(EADD_EXISTING_CURRENCY)
        );

        move_to(account, Balance<Token>{ coin: Pontem::zero<Token>() })
    }
    spec add_currency {
        /// An account must exist at the address
        let addr = Signer::address_of(account);
        include AddCurrencyAbortsIf<Token>;
        include AddCurrencyEnsures<Token>;
    }
    spec schema AddCurrencyAbortsIf<Token> {
        account: signer;
        /// `Currency` must be valid
        include Pontem::AbortsIfNoCurrency<Token>;
        /// `account` cannot have an existing balance in `Currency`
        aborts_if exists<Balance<Token>>(Signer::address_of(account)) with Errors::ALREADY_PUBLISHED;
    }
    spec schema AddCurrencyEnsures<Token> {
        addr: address;
        /// This publishes a `Balance<Currency>` to the caller's account
        ensures exists<Balance<Token>>(addr);
        ensures global<Balance<Token>>(addr)
            == Balance<Token>{ coin: Diem<Token> { value: 0 } };
    }
}
