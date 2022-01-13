/// Module allows to work with Pontem account balances, events.
module PontemFramework::PontAccount {
    use PontemFramework::PontTimestamp;
    use PontemFramework::Token::{Self, Token};
    use Std::Event::{Self, EventHandle};
    use Std::Errors;
    use Std::Signer;
    use Std::ASCII::String;

    /// The resource stores sent/recieved event handlers for account.
    struct PontAccount has key {
        /// Event handle to which ReceivePaymentEvents are emitted when
        /// payments are received.
        received_events: EventHandle<ReceivedPaymentEvent>,
        /// Event handle to which SentPaymentEvents are emitted when
        /// payments are sent.
        sent_events: EventHandle<SentPaymentEvent>,
    }

    /// A resource that holds the total value of tokens of type `TokenType`
    /// currently held by the account.
    struct Balance<phantom TokenType> has key {
        /// Stores the value of the balance in its balance field. A token has
        /// a `value` field. The amount of money in the balance is changed
        /// by modifying this field.
        token: Token<TokenType>,
    }

    /// Message for sent events
    struct SentPaymentEvent has drop, store {
        /// The amount of Token<TokenType> sent
        amount: u64,
        /// The code symbol for the token that was sent
        symbol: String,
        /// The address that was paid
        payee: address,
        /// Metadata associated with the payment
        metadata: vector<u8>,
    }

    /// Message for received events
    struct ReceivedPaymentEvent has drop, store {
        /// The amount of Token<TokenType> received
        amount: u64,
        /// The code symbol for the token that was received
        symbol: String,
        /// The address that sent the token
        payer: address,
        /// Metadata associated with the payment
        metadata: vector<u8>,
    }

    /// The `PontAccount` resource is not in the required state
    const ERR_ACCOUNT: u64 = 0;
    /// Tried to deposit a token whose value was zero
    const ERR_TOKEN_DEPOSIT_IS_ZERO: u64 = 1;
    /// The account does not hold a large enough balance in the specified token
    const ERR_INSUFFICIENT_BALANCE: u64 = 2;
    /// Tried to add a balance in a token that this account already has
    const ERR_ADD_EXISTING_TOKEN: u64 = 3;
    /// Tried to withdraw funds in a token that the account does hold
    const ERR_PAYER_DOESNT_HOLD_TOKEN: u64 = 4;
    /// An account cannot be created at the reserved core code address of 0x1
    const ERR_CANNOT_CREATE_AT_CORE_CODE: u64 = 5;

    /// If `Balance<TokenType>` exists on account.
    fun balance_exists<TokenType>(account: address): bool {
        exists<Balance<TokenType>>(account)
    }

    /// If `PontAccount` exists on account.
    fun account_exists(account: address): bool {
        exists<PontAccount>(account)   
    }

    /// Create a new account.
    /// Used to automatically create new accounts when needed.
    fun create_account(account: &signer) {
        assert(
            Signer::address_of(account) != @PontemFramework,
            Errors::invalid_argument(ERR_CANNOT_CREATE_AT_CORE_CODE)
        );

        move_to(account, PontAccount {
            received_events: Event::new_event_handle<ReceivedPaymentEvent>(account),
            sent_events: Event::new_event_handle<SentPaymentEvent>(account),
        });
    }

    /// Deposit `Token<TokenType>` to payee account.
    public fun deposit<TokenType>(
        payer: &signer,
        payee: address,
        to_deposit: Token<TokenType>,
        metadata: vector<u8>,
    ) acquires PontAccount, Balance {
        PontTimestamp::assert_operating();

        // Check that the `to_deposit` token is non-zero
        let deposit_value = Token::value(&to_deposit);
        assert(deposit_value > 0, Errors::invalid_argument(ERR_TOKEN_DEPOSIT_IS_ZERO));

        // Create signer for payee.
        let payee_account = create_signer(payee);

        // Check that an account exists at `payee`
        if (!account_exists(payee)) {
            create_account(&payee_account);
        };

        if (!balance_exists<TokenType>(payee)) {
            add_token<TokenType>(&payee_account);
        };

        // Deposit the `to_deposit` token
        Token::deposit(&mut borrow_global_mut<Balance<TokenType>>(payee).token, to_deposit);

        // Log a received event
        Event::emit_event<ReceivedPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payee).received_events,
            ReceivedPaymentEvent {
                amount: deposit_value,
                symbol: Token::symbol<TokenType>(),
                payer: Signer::address_of(payer),
                metadata
            }
        );
    }
    spec deposit {
        pragma opaque;
        modifies global<Balance<TokenType>>(payee);
        modifies global<PontAccount>(payee);
        let amount = to_deposit.value;
        include DepositAbortsIf<TokenType>{amount: amount};
        include DepositEnsures<TokenType>{amount: amount};
        include DepositEmits<TokenType>{amount: amount};
    }
    spec schema DepositAbortsIf<TokenType> {
        payer: address;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        include DepositAbortsIfRestricted<TokenType>;
        aborts_if !exists<Balance<TokenType>>(payee) with Errors::INVALID_ARGUMENT;
        aborts_if !exists_at(payee) with Errors::NOT_PUBLISHED;
    }
    spec schema DepositOverflowAbortsIf<TokenType> {
        payee: address;
        amount: u64;
        aborts_if balance<TokenType>(payee) + amount > max_u64() with Errors::LIMIT_EXCEEDED;
    }
    spec schema DepositAbortsIfRestricted<TokenType> {
        payer: &signer;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        include PontTimestamp::AbortsIfNotOperating;
        aborts_if amount == 0 with Errors::INVALID_ARGUMENT;
        include Token::AbortsIfNoToken<TokenType>;
    }
    spec schema DepositEnsures<TokenType> {
        payee: address;
        amount: u64;

        // TODO(wrwg): precisely specify what changed in the modified resources using `update_field`
        ensures exists<Balance<TokenType>>(payee);
        ensures balance<TokenType>(payee) == old(balance<TokenType>(payee)) + amount;

        ensures exists<PontAccount>(payee);

        ensures Event::spec_guid_eq(global<PontAccount>(payee).sent_events,
                                    old(global<PontAccount>(payee).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payee).received_events,
                                    old(global<PontAccount>(payee).received_events));
    }
    spec schema DepositEmits<TokenType> {
        payer: address;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let handle = global<PontAccount>(payee).received_events;
        let msg = ReceivedPaymentEvent {
            amount,
            symbol: Token::symbol<TokenType>(),
            payer,
            metadata
        };
        emits msg to handle;
    }

    /// Helper to withdraw `amount` from the given account balance and return the withdrawn Diem<Token>
    fun withdraw_from_balance<TokenType>(
        balance: &mut Balance<TokenType>,
        amount: u64
    ): Token<TokenType> {
        PontTimestamp::assert_operating();

        let token = &mut balance.token;

        // Abort if this withdrawal would make the `payer`'s balance go negative
        assert(Token::value(token) >= amount, Errors::limit_exceeded(ERR_INSUFFICIENT_BALANCE));
        Token::withdraw(token, amount)
    }
    spec withdraw_from_balance {
        include WithdrawFromBalanceAbortsIf<TokenType>;
        include WithdrawFromBalanceEnsures<TokenType>;
    }
    spec schema WithdrawFromBalanceEnsures<TokenType> {
        balance: Balance<TokenType>;
        amount: u64;
        result: Pontem<TokenType>;
        ensures balance.token.value == old(balance.token.value) - amount;
        ensures result.value == amount;
    }

    /// Withdraw `amount` `Token<TokenType>`'s from the account balance and return.
    public fun withdraw<TokenType>(
        payer: &signer,
        amount: u64,
    ): Token<TokenType> acquires Balance {
        PontTimestamp::assert_operating();

        let payer_address = Signer::address_of(payer);
        assert(exists<Balance<TokenType>>(payer_address), Errors::not_published(ERR_PAYER_DOESNT_HOLD_TOKEN));

        let account_balance = borrow_global_mut<Balance<TokenType>>(payer_address);   

        withdraw_from_balance<TokenType>(account_balance, amount)
    }

    /// Withdraw `amount` `Token<TokenType>`'s from the account balance.
    fun withdraw_from<TokenType>(
        payer: &signer,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ): Token<TokenType> acquires Balance, PontAccount {
        PontTimestamp::assert_operating();
        
        let payer_address = Signer::address_of(payer);

        // Check that an account exists at `payee`
        if (!account_exists(payer_address)) {
            create_account(payer);
        };

        if (!balance_exists<TokenType>(payer_address)) {
            add_token<TokenType>(payer);
        };

        let account_balance = borrow_global_mut<Balance<TokenType>>(payer_address);

        // Load the payer's account and emit an event to record the withdrawal
        Event::emit_event<SentPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payer_address).sent_events,
            SentPaymentEvent {
                amount,
                symbol: Token::symbol<TokenType>(),
                payee,
                metadata
            },
        );
        withdraw_from_balance<TokenType>(account_balance, amount)
    }
    spec withdraw_from {
        let payer = cap.account_address;
        modifies global<Balance<TokenType>>(payer);
        modifies global<PontAccount>(payer);
        ensures exists<PontAccount>(payer);
        ensures Event::spec_guid_eq(global<PontAccount>(payer).sent_events,
                                    old(global<PontAccount>(payer).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payer).received_events,
                                    old(global<PontAccount>(payer).received_events));
        include WithdrawFromAbortsIf<TokenType>;
        include WithdrawFromBalanceEnsures<Token>{balance: global<Balance<TokenType>>(payer)};
        include WithdrawOnlyFromCapAddress<TokenType>;
        include WithdrawFromEmits<TokenType>;
    }
    spec schema WithdrawFromAbortsIf<TokenType> {
        payer: &signer;
        payee: address;
        amount: u64;
        include PontTimestamp::AbortsIfNotOperating;
        include Token::AbortsIfNoToken<TokenType>;
        include WithdrawFromBalanceAbortsIf<TokenType>{payer, balance: global<Balance<TokenType>>(payer)};
    }
    spec schema WithdrawFromEmits<TokenType> {
        payer: &signer;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let handle = global<PontAccount>(payer).sent_events;
        let msg = SentPaymentEvent {
            amount,
            symbol: Token::spec_symbol<Token>(),
            payee,
            metadata
        };
        emits msg to handle;
    }

    /// Withdraw the balance from payer account and deposit to payee.
    public fun pay_from<TokenType>(
        payer: &signer,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ) acquires PontAccount, Balance {
        deposit<TokenType>(
            payer,
            payee,
            withdraw_from(payer, payee, amount, copy metadata),
            metadata
        );
    }
    spec schema PayFromWithoutDualAttestation<TokenType> {
        payer: &signer;
        payee: address;
        amount: u64;
        metadata: vector<u8>;

        modifies global<PontAccount>(payer);
        modifies global<PontAccount>(payee);
        modifies global<Balance<TokenType>>(payer);
        modifies global<Balance<TokenType>>(payee);
        ensures exists_at(payer);
        ensures exists_at(payee);
        ensures exists<Balance<TokenType>>(payer);
        ensures exists<Balance<TokenType>>(payee);
        ensures Event::spec_guid_eq(global<PontAccount>(payer).sent_events,
                                    old(global<PontAccount>(payer).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payer).received_events,
                                    old(global<PontAccount>(payer).received_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payee).sent_events,
                                    old(global<PontAccount>(payee).sent_events));
        ensures Event::spec_guid_eq(global<PontAccount>(payee).received_events,
                                    old(global<PontAccount>(payee).received_events));
        include PayFromAbortsIf<TokenType>;
        include PayFromEnsures<TokenType>{payer};
        include PayFromEmits<TokenType>;
    }
    spec schema PayFromEnsures<TokenType> {
        payer: address;
        payee: address;
        amount: u64;
        ensures payer == payee ==> balance<TokenType>(payer) == old(balance<TokenType>(payer));
        ensures payer != payee ==> balance<TokenType>(payer) == old(balance<TokenType>(payer)) - amount;
        ensures payer != payee ==> balance<TokenType>(payee) == old(balance<TokenType>(payee)) + amount;
    }
    spec schema PayFromEmits<TokenType> {
        cap: WithdrawCapability;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let payer = cap.account_address;
        include DepositEmits<TokenType>{payer: payer};
        include WithdrawFromEmits<TokenType>;
    }

    /// Add new token to account.
    fun add_token_to_account<TokenType>(
        account: &signer,
    ) {
        add_token<TokenType>(account);
    }
    spec add_token_to_account {
        let new_account_addr = Signer::address_of(account);
        aborts_if exists<Balance<TokenType>>(new_account_addr) with Errors::ALREADY_PUBLISHED;
        aborts_if !exists_at(new_account_addr) with Errors::NOT_PUBLISHED;
    }

    ///////////////////////////////////////////////////////////////////////////
    // General purpose methods
    ///////////////////////////////////////////////////////////////////////////
    native fun create_signer(addr: address): signer;

    /// Helper to return the u64 value of the `balance` for `account`
    fun balance_for<TokenType>(balance: &Balance<TokenType>): u64 {
        Token::value<TokenType>(&balance.token)
    }

    /// Return the current balance of the account at `addr`.
    public fun balance<TokenType>(addr: address): u64 acquires Balance {
        assert(exists<Balance<TokenType>>(addr), Errors::not_published(ERR_PAYER_DOESNT_HOLD_TOKEN));
        balance_for(borrow_global<Balance<TokenType>>(addr))
    }
    spec balance {
        aborts_if !exists<Balance<TokenType>>(addr) with Errors::NOT_PUBLISHED;
    }

    /// Add a balance of `TokenType` type to the sending account.
    public fun add_token<TokenType>(account: &signer) {
        let addr = Signer::address_of(account);

        // aborts if `Token` is not a token type in the system
        Token::assert_is_token<TokenType>();
        
        // aborts if this account already has a balance in `Token`
        assert(
            !exists<Balance<TokenType>>(addr),
            Errors::already_published(ERR_ADD_EXISTING_TOKEN)
        );

        move_to(account, Balance<TokenType>{ token: Token::zero<TokenType>() })
    }
    spec add_token {
        /// An account must exist at the address
        let addr = Signer::address_of(account);
        include AddTokenAbortsIf<Token>;
        include AddTokenEnsures<Token>;
    }
    spec schema AddTokenAbortsIf<TokenType> {
        account: signer;
        /// `Token` must be valid
        include Token::AbortsIfNoToken<TokenType>;
        /// `account` cannot have an existing balance in `Token`
        aborts_if exists<Balance<TokenType>>(Signer::address_of(account)) with Errors::ALREADY_PUBLISHED;
    }
    spec schema AddTokenEnsures<TokenType> {
        addr: address;
        /// This publishes a `Balance<TokenType>` to the caller's account
        ensures exists<Balance<TokenType>>(addr);
        ensures global<Balance<TokenType>>(addr)
            == Balance<Token>{ token: Token<TokenType> { value: 0 } };
    }
}
