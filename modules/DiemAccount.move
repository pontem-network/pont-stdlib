address 0x1 {

/// The `DiemAccount` module manages accounts. It defines the `DiemAccount` resource and
/// numerous auxiliary data structures. It also defines the prolog and epilog that run
/// before and after every transaction.

module DiemAccount {
    use 0x1::CoreAddresses;
    use 0x1::AccountLimits::{Self, AccountLimitMutationCapability};
    use 0x1::DualAttestation;
    use 0x1::Errors;
    use 0x1::Event::{Self, EventHandle};
    use 0x1::BCS;
    use 0x1::Time;
    use 0x1::Signer;
    use 0x1::VASP;
    use 0x1::Vector;
    use 0x1::Diem::{Self, Diem};
    use 0x1::Option::{Self, Option};
    use 0x1::Roles;
    use 0x1::PONT::PONT;

    /// An `address` is a Diem Account iff it has a published DiemAccount resource.
    struct DiemAccount has key {
        /// The current authentication key.
        /// This can be different from the key used to create the account
        authentication_key: vector<u8>,
        /// A `withdraw_capability` allows whoever holds this capability
        /// to withdraw from the account. At the time of account creation
        /// this capability is stored in this option. It can later be removed
        /// by `extract_withdraw_capability` and also restored via `restore_withdraw_capability`.
        withdraw_capability: Option<WithdrawCapability>,
        /// A `key_rotation_capability` allows whoever holds this capability
        /// the ability to rotate the authentication key for the account. At
        /// the time of account creation this capability is stored in this
        /// option. It can later be "extracted" from this field via
        /// `extract_key_rotation_capability`, and can also be restored via
        /// `restore_key_rotation_capability`.
        key_rotation_capability: Option<KeyRotationCapability>,
        /// Event handle to which ReceivePaymentEvents are emitted when
        /// payments are received.
        received_events: EventHandle<ReceivedPaymentEvent>,
        /// Event handle to which SentPaymentEvents are emitted when
        /// payments are sent.
        sent_events: EventHandle<SentPaymentEvent>,
        /// The current sequence number of the account.
        /// Incremented by one each time a transaction is submitted by
        /// this account.
        sequence_number: u64,
    }

    /// A resource that holds the total value of currency of type `Token`
    /// currently held by the account.
    struct Balance<Token> has key {
        /// Stores the value of the balance in its balance field. A coin has
        /// a `value` field. The amount of money in the balance is changed
        /// by modifying this field.
        coin: Diem<Token>,
    }

    /// The holder of WithdrawCapability for account_address can withdraw Diem from
    /// account_address/DiemAccount/balance.
    /// There is at most one WithdrawCapability in existence for a given address.
    struct WithdrawCapability has store {
        /// Address that WithdrawCapability was associated with when it was created.
        /// This field does not change.
        account_address: address,
    }

    /// The holder of KeyRotationCapability for account_address can rotate the authentication key for
    /// account_address (i.e., write to account_address/DiemAccount/authentication_key).
    /// There is at most one KeyRotationCapability in existence for a given address.
    struct KeyRotationCapability has store {
        /// Address that KeyRotationCapability was associated with when it was created.
        /// This field does not change.
        account_address: address,
    }

    /// A wrapper around an `AccountLimitMutationCapability` which is used to check for account limits
    /// and to record freeze/unfreeze events.
    struct AccountOperationsCapability has key {
        limits_cap: AccountLimitMutationCapability,
        creation_events: Event::EventHandle<CreateAccountEvent>,
    }

    /// A resource that holds the event handle for all the past WriteSet transactions that have been committed on chain.
    struct DiemWriteSetManager has key {
        upgrade_events: Event::EventHandle<Self::AdminTransactionEvent>,
    }


    /// Message for sent events
    struct SentPaymentEvent has drop, store {
        /// The amount of Diem<Token> sent
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
        /// The amount of Diem<Token> received
        amount: u64,
        /// The code symbol for the currency that was received
        currency_code: vector<u8>,
        /// The address that sent the coin
        payer: address,
        /// Metadata associated with the payment
        metadata: vector<u8>,
    }

    /// Message for committed WriteSet transaction.
    struct AdminTransactionEvent has drop, store {
        // The block time when this WriteSet is committed.
        committed_timestamp_secs: u64,
    }

    /// Message for creation of a new account
    struct CreateAccountEvent has drop, store {
        /// Address of the created account
        created: address,
        /// Role of the created account
        role_id: u64
    }

    const MAX_U64: u128 = 18446744073709551615;

    /// The `DiemAccount` resource is not in the required state
    const EACCOUNT: u64 = 0;
    /// Tried to deposit a coin whose value was zero
    const ECOIN_DEPOSIT_IS_ZERO: u64 = 2;
    /// Tried to deposit funds that would have surpassed the account's limits
    const EDEPOSIT_EXCEEDS_LIMITS: u64 = 3;
    /// Tried to create a balance for an account whose role does not allow holding balances
    const EROLE_CANT_STORE_BALANCE: u64 = 4;
    /// The account does not hold a large enough balance in the specified currency
    const EINSUFFICIENT_BALANCE: u64 = 5;
    /// The withdrawal of funds would have exceeded the the account's limits
    const EWITHDRAWAL_EXCEEDS_LIMITS: u64 = 6;
    /// The `WithdrawCapability` for this account has already been extracted
    const EWITHDRAW_CAPABILITY_ALREADY_EXTRACTED: u64 = 7;
    /// The provided authentication had an invalid length
    const EMALFORMED_AUTHENTICATION_KEY: u64 = 8;
    /// The `KeyRotationCapability` for this account has already been extracted
    const EKEY_ROTATION_CAPABILITY_ALREADY_EXTRACTED: u64 = 9;
    /// An account cannot be created at the reserved VM address of 0x0
    const ECANNOT_CREATE_AT_VM_RESERVED: u64 = 10;
    /// The `WithdrawCapability` for this account is not extracted
    const EWITHDRAW_CAPABILITY_NOT_EXTRACTED: u64 = 11;
    /// Tried to add a balance in a currency that this account already has
    const EADD_EXISTING_CURRENCY: u64 = 15;
    /// Attempted to send funds to an account that does not exist
    const EPAYEE_DOES_NOT_EXIST: u64 = 17;
    /// Attempted to send funds in a currency that the receiving account does not hold.
    /// e.g., `Diem<PONT>` to an account that exists, but does not have a `Balance<PONT>` resource
    const EPAYEE_CANT_ACCEPT_CURRENCY_TYPE: u64 = 18;
    /// Tried to withdraw funds in a currency that the account does hold
    const EPAYER_DOESNT_HOLD_CURRENCY: u64 = 19;
    /// An invalid amount of gas units was provided for execution of the transaction
    const EGAS: u64 = 20;
    /// The `AccountOperationsCapability` was not in the required state
    const EACCOUNT_OPERATIONS_CAPABILITY: u64 = 22;
    /// The `DiemWriteSetManager` was not in the required state
    const EWRITESET_MANAGER: u64 = 23;
    /// An account cannot be created at the reserved core code address of 0x1
    const ECANNOT_CREATE_AT_CORE_CODE: u64 = 24;

    /// Prologue errors. These are separated out from the other errors in this
    /// module since they are mapped separately to major VM statuses, and are
    /// important to the semantics of the system.
    const PROLOGUE_EACCOUNT_FROZEN: u64 = 1000;
    const PROLOGUE_EINVALID_ACCOUNT_AUTH_KEY: u64 = 1001;
    const PROLOGUE_ESEQUENCE_NUMBER_TOO_OLD: u64 = 1002;
    const PROLOGUE_ESEQUENCE_NUMBER_TOO_NEW: u64 = 1003;
    const PROLOGUE_EACCOUNT_DNE: u64 = 1004;
    const PROLOGUE_ECANT_PAY_GAS_DEPOSIT: u64 = 1005;
    const PROLOGUE_ETRANSACTION_EXPIRED: u64 = 1006;
    const PROLOGUE_EBAD_CHAIN_ID: u64 = 1007;
    const PROLOGUE_ESCRIPT_NOT_ALLOWED: u64 = 1008;
    const PROLOGUE_EMODULE_NOT_ALLOWED: u64 = 1009;
    const PROLOGUE_EINVALID_WRITESET_SENDER: u64 = 1010;
    const PROLOGUE_ESEQUENCE_NUMBER_TOO_BIG: u64 = 1011;
    const PROLOGUE_EBAD_TRANSACTION_FEE_CURRENCY: u64 = 1012;

    /// Initialize this module. This is only callable from genesis.
    public fun initialize(
        dr_account: &signer,
        dummy_auth_key_prefix: vector<u8>,
    ) acquires AccountOperationsCapability {
        Time::assert_genesis();
        // Operational constraint, not a privilege constraint.
        CoreAddresses::assert_diem_root(dr_account);

        create_diem_root_account(
            copy dummy_auth_key_prefix,
        );
        create_treasury_compliance_account(
            dr_account,
            copy dummy_auth_key_prefix,
        );
    }

    /// Return `true` if `addr` has already published account limits for `Token`
    fun has_published_account_limits<Token: store>(addr: address): bool {
        if (VASP::is_vasp(addr)) {
            VASP::has_account_limits<Token>(addr)
        }
        else {
            AccountLimits::has_window_published<Token>(addr)
        }
    }

    /// Returns whether we should track and record limits for the `payer` or `payee` account.
    /// Depending on the `is_withdrawal` flag passed in we determine whether the
    /// `payer` or `payee` account is being queried. `VASP->any` and
    /// `any->VASP` transfers are tracked in the VASP.
    fun should_track_limits_for_account<Token: store>(
        payer: address, payee: address, is_withdrawal: bool
    ): bool {
        if (is_withdrawal) {
            has_published_account_limits<Token>(payer) &&
            VASP::is_vasp(payer) &&
            !VASP::is_same_vasp(payer, payee)
        } else {
            has_published_account_limits<Token>(payee) &&
            VASP::is_vasp(payee) &&
            !VASP::is_same_vasp(payee, payer)
        }
    }

    /// Record a payment of `to_deposit` from `payer` to `payee` with the attached `metadata`
    fun deposit<Token: store>(
        payer: address,
        payee: address,
        to_deposit: Diem<Token>,
        metadata: vector<u8>,
        metadata_signature: vector<u8>
    ) acquires DiemAccount, Balance, AccountOperationsCapability {
        Time::assert_operating();

        // Check that the `to_deposit` coin is non-zero
        let deposit_value = Diem::value(&to_deposit);
        assert(deposit_value > 0, Errors::invalid_argument(ECOIN_DEPOSIT_IS_ZERO));
        // Check that an account exists at `payee`
        assert(exists_at(payee), Errors::not_published(EPAYEE_DOES_NOT_EXIST));
        // Check that `payee` can accept payments in `Token`
        assert(
            exists<Balance<Token>>(payee),
            Errors::invalid_argument(EPAYEE_CANT_ACCEPT_CURRENCY_TYPE)
        );

        // Check that the payment complies with dual attestation rules
        DualAttestation::assert_payment_ok<Token>(
            payer, payee, deposit_value, copy metadata, metadata_signature
        );
        // Ensure that this deposit is compliant with the account limits on
        // this account.
        if (should_track_limits_for_account<Token>(payer, payee, false)) {
            assert(
                AccountLimits::update_deposit_limits<Token>(
                    deposit_value,
                    VASP::parent_address(payee),
                    &borrow_global<AccountOperationsCapability>(CoreAddresses::DIEM_ROOT_ADDRESS()).limits_cap
                ),
                Errors::limit_exceeded(EDEPOSIT_EXCEEDS_LIMITS)
            )
        };

        // Deposit the `to_deposit` coin
        Diem::deposit(&mut borrow_global_mut<Balance<Token>>(payee).coin, to_deposit);

        // Log a received event
        Event::emit_event<ReceivedPaymentEvent>(
            &mut borrow_global_mut<DiemAccount>(payee).received_events,
            ReceivedPaymentEvent {
                amount: deposit_value,
                currency_code: Diem::currency_code<Token>(),
                payer,
                metadata
            }
        );
    }

    /// Helper to withdraw `amount` from the given account balance and return the withdrawn Diem<Token>
    fun withdraw_from_balance<Token: store>(
        payer: address,
        payee: address,
        balance: &mut Balance<Token>,
        amount: u64
    ): Diem<Token> acquires AccountOperationsCapability {
        Time::assert_operating();
        // Make sure that this withdrawal is compliant with the limits on
        // the account if it's a inter-VASP transfer,
        if (should_track_limits_for_account<Token>(payer, payee, true)) {
            let can_withdraw = AccountLimits::update_withdrawal_limits<Token>(
                    amount,
                    VASP::parent_address(payer),
                    &borrow_global<AccountOperationsCapability>(CoreAddresses::DIEM_ROOT_ADDRESS()).limits_cap
            );
            assert(can_withdraw, Errors::limit_exceeded(EWITHDRAWAL_EXCEEDS_LIMITS));
        };
        let coin = &mut balance.coin;
        // Abort if this withdrawal would make the `payer`'s balance go negative
        assert(Diem::value(coin) >= amount, Errors::limit_exceeded(EINSUFFICIENT_BALANCE));
        Diem::withdraw(coin, amount)
    }

    /// Withdraw `amount` `Diem<Token>`'s from the account balance under
    /// `cap.account_address`
    fun withdraw_from<Token: store>(
        cap: &WithdrawCapability,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ): Diem<Token> acquires Balance, AccountOperationsCapability, DiemAccount {
        Time::assert_operating();
        let payer = cap.account_address;
        assert(exists_at(payer), Errors::not_published(EACCOUNT));
        assert(exists<Balance<Token>>(payer), Errors::not_published(EPAYER_DOESNT_HOLD_CURRENCY));
        let account_balance = borrow_global_mut<Balance<Token>>(payer);
        // Load the payer's account and emit an event to record the withdrawal
        Event::emit_event<SentPaymentEvent>(
            &mut borrow_global_mut<DiemAccount>(payer).sent_events,
            SentPaymentEvent {
                amount,
                currency_code: Diem::currency_code<Token>(),
                payee,
                metadata
            },
        );
        withdraw_from_balance<Token>(payer, payee, account_balance, amount)
    }

    /// Return a unique capability granting permission to withdraw from the sender's account balance.
    public fun extract_withdraw_capability(
        sender: &signer
    ): WithdrawCapability acquires DiemAccount {
        let sender_addr = Signer::address_of(sender);
        // Abort if we already extracted the unique withdraw capability for this account.
        assert(
            !delegated_withdraw_capability(sender_addr),
            Errors::invalid_state(EWITHDRAW_CAPABILITY_ALREADY_EXTRACTED)
        );
        assert(exists_at(sender_addr), Errors::not_published(EACCOUNT));
        let account = borrow_global_mut<DiemAccount>(sender_addr);
        Option::extract(&mut account.withdraw_capability)
    }

    /// Return the withdraw capability to the account it originally came from
    public fun restore_withdraw_capability(cap: WithdrawCapability)
    acquires DiemAccount {
        assert(exists_at(cap.account_address), Errors::not_published(EACCOUNT));
        // Abort if the withdraw capability for this account is not extracted,
        // indicating that the withdraw capability is not unique.
        assert(
            delegated_withdraw_capability(cap.account_address),
            Errors::invalid_state(EWITHDRAW_CAPABILITY_NOT_EXTRACTED)
        );
        let account = borrow_global_mut<DiemAccount>(cap.account_address);
        Option::fill(&mut account.withdraw_capability, cap)
    }

    /// Withdraw `amount` Diem<Token> from the address embedded in `WithdrawCapability` and
    /// deposits it into the `payee`'s account balance.
    /// The included `metadata` will appear in the `SentPaymentEvent` and `ReceivedPaymentEvent`.
    /// The `metadata_signature` will only be checked if this payment is subject to the dual
    /// attestation protocol
    public fun pay_from<Token: store>(
        cap: &WithdrawCapability,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
        metadata_signature: vector<u8>
    ) acquires DiemAccount, Balance, AccountOperationsCapability {
        deposit<Token>(
            *&cap.account_address,
            payee,
            withdraw_from(cap, payee, amount, copy metadata),
            metadata,
            metadata_signature
        );
    }

    /// Rotate the authentication key for the account under cap.account_address
    public fun rotate_authentication_key(
        cap: &KeyRotationCapability,
        new_authentication_key: vector<u8>,
    ) acquires DiemAccount  {
        assert(exists_at(cap.account_address), Errors::not_published(EACCOUNT));
        let sender_account_resource = borrow_global_mut<DiemAccount>(cap.account_address);
        // Don't allow rotating to clearly invalid key
        assert(
            Vector::length(&new_authentication_key) == 32,
            Errors::invalid_argument(EMALFORMED_AUTHENTICATION_KEY)
        );
        sender_account_resource.authentication_key = new_authentication_key;
    }

    /// Return a unique capability granting permission to rotate the sender's authentication key
    public fun extract_key_rotation_capability(account: &signer): KeyRotationCapability
    acquires DiemAccount {
        let account_address = Signer::address_of(account);
        // Abort if we already extracted the unique key rotation capability for this account.
        assert(
            !delegated_key_rotation_capability(account_address),
            Errors::invalid_state(EKEY_ROTATION_CAPABILITY_ALREADY_EXTRACTED)
        );
        assert(exists_at(account_address), Errors::not_published(EACCOUNT));
        let account = borrow_global_mut<DiemAccount>(account_address);
        Option::extract(&mut account.key_rotation_capability)
    }

    /// Return the key rotation capability to the account it originally came from
    public fun restore_key_rotation_capability(cap: KeyRotationCapability)
    acquires DiemAccount {
        assert(exists_at(cap.account_address), Errors::not_published(EACCOUNT));
        let account = borrow_global_mut<DiemAccount>(cap.account_address);
        Option::fill(&mut account.key_rotation_capability, cap)
    }

    /// Add balances for `Token` to `new_account`.  If `add_all_currencies` is true,
    /// then add for both token types.
    fun add_currencies_for_account<Token: store>(
        new_account: &signer,
        add_all_currencies: bool,
    ) {
        let new_account_addr = Signer::address_of(new_account);
        add_currency<Token>(new_account);
        if (add_all_currencies) {
            if (!exists<Balance<PONT>>(new_account_addr)) {
                add_currency<PONT>(new_account);
            };
        };
    }

    /// Creates a new account with account at `new_account_address` with
    /// authentication key `auth_key_prefix` | `fresh_address`.
    /// Aborts if there is already an account at `new_account_address`.
    ///
    /// Creating an account at address 0x0 will abort as it is a reserved address for the MoveVM.
    fun make_account(
        new_account: signer,
        auth_key_prefix: vector<u8>,
    ) acquires AccountOperationsCapability {
        let new_account_addr = Signer::address_of(&new_account);
        // cannot create an account at the reserved address 0x0
        assert(
            new_account_addr != CoreAddresses::VM_RESERVED_ADDRESS(),
            Errors::invalid_argument(ECANNOT_CREATE_AT_VM_RESERVED)
        );
        assert(
            new_account_addr != CoreAddresses::CORE_CODE_ADDRESS(),
            Errors::invalid_argument(ECANNOT_CREATE_AT_CORE_CODE)
        );

        // Construct authentication key.
        let authentication_key = create_authentication_key(&new_account, auth_key_prefix);

        // Publish AccountFreezing::FreezingBit (initially not frozen)
        // The AccountOperationsCapability is published during Genesis, so it should
        // always exist.  This is a sanity check.
        assert(
            exists<AccountOperationsCapability>(CoreAddresses::DIEM_ROOT_ADDRESS()),
            Errors::not_published(EACCOUNT_OPERATIONS_CAPABILITY)
        );
        // Emit the CreateAccountEvent
        Event::emit_event(
            &mut borrow_global_mut<AccountOperationsCapability>(CoreAddresses::DIEM_ROOT_ADDRESS()).creation_events,
            CreateAccountEvent { created: new_account_addr, role_id: Roles::get_role_id(new_account_addr) },
        );
        // Publishing the account resource last makes it possible to prove invariants that simplify
        // aborts_if's, etc.
        move_to(
            &new_account,
            DiemAccount {
                authentication_key,
                withdraw_capability: Option::some(
                    WithdrawCapability {
                        account_address: new_account_addr
                }),
                key_rotation_capability: Option::some(
                    KeyRotationCapability {
                        account_address: new_account_addr
                }),
                received_events: Event::new_event_handle<ReceivedPaymentEvent>(&new_account),
                sent_events: Event::new_event_handle<SentPaymentEvent>(&new_account),
                sequence_number: 0,
            }
        );
        destroy_signer(new_account);
    }

    /// Construct an authentication key, aborting if the prefix is not valid.
    fun create_authentication_key(account: &signer, auth_key_prefix: vector<u8>): vector<u8> {
        let authentication_key = auth_key_prefix;
        Vector::append(
            &mut authentication_key, BCS::to_bytes(Signer::borrow_address(account))
        );
        assert(
            Vector::length(&authentication_key) == 32,
            Errors::invalid_argument(EMALFORMED_AUTHENTICATION_KEY)
        );
        authentication_key
    }

    /// Creates the diem root account (during genesis). Publishes the Diem root role,
    /// Sets up event generator, publishes
    /// AccountOperationsCapability, WriteSetManager, and finally makes the account.
    fun create_diem_root_account(
        auth_key_prefix: vector<u8>,
    ) acquires AccountOperationsCapability {
        Time::assert_genesis();
        let dr_account = create_signer(CoreAddresses::DIEM_ROOT_ADDRESS());
        CoreAddresses::assert_diem_root(&dr_account);
        Roles::grant_diem_root_role(&dr_account);
        Event::publish_generator(&dr_account);

        assert(
            !exists<AccountOperationsCapability>(CoreAddresses::DIEM_ROOT_ADDRESS()),
            Errors::already_published(EACCOUNT_OPERATIONS_CAPABILITY)
        );
        move_to(
            &dr_account,
            AccountOperationsCapability {
                limits_cap: AccountLimits::grant_mutation_capability(&dr_account),
                creation_events: Event::new_event_handle<CreateAccountEvent>(&dr_account),
            }
        );
        assert(
            !exists<DiemWriteSetManager>(CoreAddresses::DIEM_ROOT_ADDRESS()),
            Errors::already_published(EWRITESET_MANAGER)
        );
        move_to(
            &dr_account,
            DiemWriteSetManager {
                upgrade_events: Event::new_event_handle<Self::AdminTransactionEvent>(&dr_account),
            }
        );
        make_account(dr_account, auth_key_prefix)
    }

    /// Create a treasury/compliance account at `new_account_address` with authentication key
    /// `auth_key_prefix` | `new_account_address`.  Can only be called during genesis.
    /// Also, publishes the treasury compliance role and
    /// event handle generator, then makes the account.
    fun create_treasury_compliance_account(
        dr_account: &signer,
        auth_key_prefix: vector<u8>,
    ) acquires AccountOperationsCapability {
        Time::assert_genesis();
        Roles::assert_diem_root(dr_account);
        let new_account_address = CoreAddresses::TREASURY_COMPLIANCE_ADDRESS();
        let new_account = create_signer(new_account_address);
        Roles::grant_treasury_compliance_role(&new_account, dr_account);
        Event::publish_generator(&new_account);
        make_account(new_account, auth_key_prefix)
    }

    ///////////////////////////////////////////////////////////////////////////
    // VASP methods
    ///////////////////////////////////////////////////////////////////////////

    /// Create an account with the ParentVASP role at `new_account_address` with authentication key
    /// `auth_key_prefix` | `new_account_address`.  If `add_all_currencies` is true, 0 balances for
    /// all available currencies in the system will also be added.
    public fun create_parent_vasp_account<Token: store>(
        creator_account: &signer,  // TreasuryCompliance
        new_account_address: address,
        auth_key_prefix: vector<u8>,
        human_name: vector<u8>,
        add_all_currencies: bool
    ) acquires AccountOperationsCapability {
        let new_account = create_signer(new_account_address);
        Roles::new_parent_vasp_role(creator_account, &new_account);
        VASP::publish_parent_vasp_credential(&new_account, creator_account);
        Event::publish_generator(&new_account);
        DualAttestation::publish_credential(&new_account, creator_account, human_name);
        add_currencies_for_account<Token>(&new_account, add_all_currencies);
        make_account(new_account, auth_key_prefix)
    }

    /// Create an account with the ChildVASP role at `new_account_address` with authentication key
    /// `auth_key_prefix` | `new_account_address` and a 0 balance of type `Token`. If
    /// `add_all_currencies` is true, 0 balances for all avaialable currencies in the system will
    /// also be added. This account will be a child of `creator`, which must be a ParentVASP.
    public fun create_child_vasp_account<Token: store>(
        parent: &signer,
        new_account_address: address,
        auth_key_prefix: vector<u8>,
        add_all_currencies: bool,
    ) acquires AccountOperationsCapability {
        let new_account = create_signer(new_account_address);
        Roles::new_child_vasp_role(parent, &new_account);
        VASP::publish_child_vasp_credential(
            parent,
            &new_account,
        );
        Event::publish_generator(&new_account);
        add_currencies_for_account<Token>(&new_account, add_all_currencies);
        make_account(new_account, auth_key_prefix)
    }

    ///////////////////////////////////////////////////////////////////////////
    // General purpose methods
    ///////////////////////////////////////////////////////////////////////////

    native fun create_signer(addr: address): signer;
    native fun destroy_signer(sig: signer);

    /// Helper to return the u64 value of the `balance` for `account`
    fun balance_for<Token: store>(balance: &Balance<Token>): u64 {
        Diem::value<Token>(&balance.coin)
    }

    /// Return the current balance of the account at `addr`.
    public fun balance<Token: store>(addr: address): u64 acquires Balance {
        assert(exists<Balance<Token>>(addr), Errors::not_published(EPAYER_DOESNT_HOLD_CURRENCY));
        balance_for(borrow_global<Balance<Token>>(addr))
    }

    /// Add a balance of `Token` type to the sending account
    public fun add_currency<Token: store>(account: &signer) {
        // aborts if `Token` is not a currency type in the system
        Diem::assert_is_currency<Token>();
        // Check that an account with this role is allowed to hold funds
        assert(
            Roles::can_hold_balance(account),
            Errors::invalid_argument(EROLE_CANT_STORE_BALANCE)
        );
        // aborts if this account already has a balance in `Token`
        let addr = Signer::address_of(account);
        assert(!exists<Balance<Token>>(addr), Errors::already_published(EADD_EXISTING_CURRENCY));

        move_to(account, Balance<Token>{ coin: Diem::zero<Token>() })
    }

    /// Return whether the account at `addr` accepts `Token` type coins
    public fun accepts_currency<Token: store>(addr: address): bool {
        exists<Balance<Token>>(addr)
    }

    /// Helper to return the sequence number field for given `account`
    fun sequence_number_for_account(account: &DiemAccount): u64 {
        account.sequence_number
    }

    /// Return the current sequence number at `addr`
    public fun sequence_number(addr: address): u64 acquires DiemAccount {
        assert(exists_at(addr), Errors::not_published(EACCOUNT));
        sequence_number_for_account(borrow_global<DiemAccount>(addr))
    }

    /// Return the authentication key for this account
    public fun authentication_key(addr: address): vector<u8> acquires DiemAccount {
        assert(exists_at(addr), Errors::not_published(EACCOUNT));
        *&borrow_global<DiemAccount>(addr).authentication_key
    }

    /// Return true if the account at `addr` has delegated its key rotation capability
    public fun delegated_key_rotation_capability(addr: address): bool
    acquires DiemAccount {
        assert(exists_at(addr), Errors::not_published(EACCOUNT));
        Option::is_none(&borrow_global<DiemAccount>(addr).key_rotation_capability)
    }

    /// Return true if the account at `addr` has delegated its withdraw capability
    public fun delegated_withdraw_capability(addr: address): bool
    acquires DiemAccount {
        assert(exists_at(addr), Errors::not_published(EACCOUNT));
        Option::is_none(&borrow_global<DiemAccount>(addr).withdraw_capability)
    }

    /// Return a reference to the address associated with the given withdraw capability
    public fun withdraw_capability_address(cap: &WithdrawCapability): &address {
        &cap.account_address
    }

    /// Return a reference to the address associated with the given key rotation capability
    public fun key_rotation_capability_address(cap: &KeyRotationCapability): &address {
        &cap.account_address
    }

    /// Checks if an account exists at `check_addr`
    public fun exists_at(check_addr: address): bool {
        exists<DiemAccount>(check_addr)
    }
}
}
