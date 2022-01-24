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
    const ERR_CANNOT_CREATE_AT_CORE_ADDRESS: u64 = 5;

    /// Deposit `Token<TokenType>` to payee account.
    public fun deposit<TokenType>(payer: &signer, payee: address, token: Token<TokenType>)
    acquires PontAccount, Balance {
        deposit_with_metadata(payer, payee, token, b"")
    }

    public fun deposit_with_metadata<TokenType>(
        payer_acc: &signer,
        payee: address,
        token: Token<TokenType>,
        metadata: vector<u8>
    ) acquires Balance, PontAccount {
        PontTimestamp::assert_operating();

        // Check that the `token` amount is non-zero
        let token_amount = Token::value(&token);
        assert!(token_amount > 0, Errors::invalid_argument(ERR_TOKEN_DEPOSIT_IS_ZERO));

        // Create signer for payee.
        let payee_acc = create_signer(payee);

        // Check that an account exists at `payee`
        if (!exists<PontAccount>(payee)) {
            add_user_account(&payee_acc);
        };

        if (!balance_exists<TokenType>(payee)) {
            add_balance<TokenType>(&payee_acc);
        };

        // Deposit the `to_deposit` token
        Token::deposit(&mut borrow_global_mut<Balance<TokenType>>(payee).token, token);

        // Log a received event
        Event::emit_event<ReceivedPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payee).received_events,
            ReceivedPaymentEvent{
                amount: token_amount,
                symbol: Token::symbol<TokenType>(),
                payer: Signer::address_of(payer_acc),
                metadata
            }
        );
    }
    spec deposit_with_metadata {
        pragma opaque;

        modifies global<Balance<TokenType>>(payee);
        include ModifiesPontAccount { account_addr: payee };

        let amount = token.value;
        let payer = Signer::address_of(payer_acc);
//        let balance = global<Balance<TokenType>>(payee);

        include DepositAbort<TokenType>{ amount: token.value, payee };
//        include Token::AbortsIfDepositOverflow<TokenType> { token: global<Balance<TokenType>>(payee).token, check: token };

        include DepositEnsures<TokenType>{ amount };
//        include DepositEmits<TokenType>{ payer, amount };
    }
    spec schema DepositAbort<TokenType> {
        payee: address;
        amount: u64;

        include PontTimestamp::AbortsIfNotOperating;
        include Token::AbortsIfTokenNotRegistered<TokenType>;

        aborts_if amount == 0 with Errors::INVALID_ARGUMENT;
        aborts_if !exists<PontAccount>(payee)
                  && payee == @PontemFramework with Errors::INVALID_ARGUMENT;
    }
    spec schema DepositEnsures<TokenType> {
        payee: address;
        amount: u64;

        ensures exists<PontAccount>(payee);
        ensures exists<Balance<TokenType>>(payee);
        ensures old(exists<Balance<TokenType>>(payee)) ==>
                balance<TokenType>(payee) == old(balance<TokenType>(payee)) + amount;
    }
    spec schema DepositEmits<TokenType> {
        payer: address;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let handle = global<PontAccount>(payee).received_events;
        let msg = ReceivedPaymentEvent{
            amount,
            symbol: Token::spec_symbol<TokenType>(),
            payer,
            metadata
        };
        emits msg to handle;
    }

    /// Withdraw `amount` `Token<TokenType>`'s from the account balance and return.
    public fun withdraw<TokenType>(
        payer: &signer,
        amount: u64,
    ): Token<TokenType> acquires Balance {
        PontTimestamp::assert_operating();

        let payer_address = Signer::address_of(payer);
        assert!(exists<Balance<TokenType>>(payer_address), Errors::not_published(ERR_PAYER_DOESNT_HOLD_TOKEN));

        let account_balance = borrow_global_mut<Balance<TokenType>>(payer_address);
        withdraw_from_balance<TokenType>(account_balance, amount)
    }

    public fun pay_from<TokenType>(
        payer: &signer,
        payee: address,
        amount: u64,
    ) acquires PontAccount, Balance {
        pay_from_with_metadata<TokenType>(
            payer,
            payee,
            amount,
            b""
        );
    }

    /// Withdraw the balance from payer account and deposit to payee.
    public fun pay_from_with_metadata<TokenType>(
        payer_acc: &signer,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ) acquires PontAccount, Balance {
        let withdrawn_tokens = withdraw_from(payer_acc, payee, amount, copy metadata);
        deposit_with_metadata<TokenType>(
            payer_acc,
            payee,
            withdrawn_tokens,
            metadata
        );
    }
    spec pay_from_with_metadata {
        let payer = Signer::address_of(payer_acc);
        modifies global<PontAccount>(payer);
        modifies global<PontAccount>(payee);
        modifies global<Balance<TokenType>>(payer);
        modifies global<Balance<TokenType>>(payee);

        ensures exists<Balance<TokenType>>(payer);
        ensures exists<Balance<TokenType>>(payee);

//        include PayFromAbortsIf<TokenType>;
        include PayFromEnsures<TokenType> { payer, payee };
//        include PayFromEmits<TokenType>;
    }
    spec schema PayFromEnsures<TokenType> {
        payer: address;
        payee: address;
        amount: u64;
        ensures payer == payee
                ==> balance<TokenType>(payer) == old(balance<TokenType>(payer));
        ensures payer != payee
                ==> balance<TokenType>(payer) == old(balance<TokenType>(payer)) - amount;
        ensures payer != payee && old(balance_exists<TokenType>(payee))
                ==> balance<TokenType>(payee) == old(balance<TokenType>(payee)) + amount;
    }
//    spec schema PayFromEmits<TokenType> {
//        payer: address;
//        payee: address;
//        amount: u64;
//        include DepositEmits<TokenType>{ payer };
//        include WithdrawFromEmits<TokenType> { payer };
//    }

    /// Return the current balance of the account at `addr`.
    public fun balance<TokenType>(addr: address): u64 acquires Balance {
        assert!(exists<Balance<TokenType>>(addr), Errors::not_published(ERR_PAYER_DOESNT_HOLD_TOKEN));
        balance_for(borrow_global<Balance<TokenType>>(addr))
    }
    spec balance {
        aborts_if !exists<Balance<TokenType>>(addr) with Errors::NOT_PUBLISHED;
    }

    /// Add a balance of `TokenType` type to the sending account.
    public fun add_balance<TokenType>(account: &signer) {
        let addr = Signer::address_of(account);

        // aborts if `Token` is not a token type in the system
        Token::assert_is_token<TokenType>();

        // aborts if this account already has a balance in `Token`
        assert!(
            !exists<Balance<TokenType>>(addr),
            Errors::already_published(ERR_ADD_EXISTING_TOKEN)
        );
        move_to(account, Balance<TokenType>{ token: Token::zero<TokenType>() })
    }
    spec add_balance {
        /// An account must exist at the address
        include AddBalanceAborts<TokenType> { account };

        let account_addr = Signer::address_of(account);
        /// `account` cannot have an existing balance in `Token`
        aborts_if exists<Balance<TokenType>>(account_addr) with Errors::ALREADY_PUBLISHED;

        include AddTokenEnsures<TokenType> { account_addr };
    }
    spec schema AddBalanceAborts<TokenType> {
        account: signer;
        include Token::AbortsIfTokenNotRegistered<TokenType>;
        /// `account` cannot have an existing balance in `Token`
        aborts_if exists<Balance<TokenType>>(Signer::address_of(account)) with Errors::ALREADY_PUBLISHED;
    }
    spec schema AddTokenEnsures<TokenType> {
        account_addr: address;
        modifies global<Balance<TokenType>>(account_addr);
        // This publishes a `Balance<TokenType>` to the caller's account
        ensures exists<Balance<TokenType>>(account_addr);
        ensures global<Balance<TokenType>>(account_addr).token.value == 0;
    }


    ///////////////////////////////////////////////////////////////////////////
    // General purpose methods
    ///////////////////////////////////////////////////////////////////////////
    ///
    /// Helper to return the u64 value of the `balance` for `account`
    fun balance_for<TokenType>(balance: &Balance<TokenType>): u64 {
        Token::value<TokenType>(&balance.token)
    }

    /// If `Balance<TokenType>` exists on account.
    fun balance_exists<TokenType>(account: address): bool {
        exists<Balance<TokenType>>(account)
    }

    spec schema AbortsIfPontemFrameworkAccount {
        acc: signer;
        aborts_if Signer::address_of(acc) == @PontemFramework with Errors::INVALID_ARGUMENT;
    }

    /// Create a new account.
    /// Used to automatically create new accounts when needed.
    fun add_user_account(acc: &signer) {
        assert!(
            Signer::address_of(acc) != @PontemFramework,
            Errors::invalid_argument(ERR_CANNOT_CREATE_AT_CORE_ADDRESS)
        );
        move_to(acc, PontAccount{
            received_events: Event::new_event_handle<ReceivedPaymentEvent>(acc),
            sent_events: Event::new_event_handle<SentPaymentEvent>(acc),
        });
    }
    spec add_user_account {
        let account_addr = Signer::address_of(acc);
        include ModifiesPontAccount { account_addr };

        ensures exists<PontAccount>(account_addr);
//        include PontemFrameworkAccountAbort { acc };
    }
    spec schema ModifiesPontAccount {
        account_addr: address;
        modifies global<PontAccount>(account_addr);
    }

    /// Withdraw `amount` `Token<TokenType>`'s from the account balance.
    fun withdraw_from<TokenType>(
        payer_acc: &signer,
        payee: address,
        amount: u64,
        metadata: vector<u8>,
    ): Token<TokenType> acquires Balance, PontAccount {
        PontTimestamp::assert_operating();

        let payer_address = Signer::address_of(payer_acc);

        // Check that an account exists at `payee`
        if (!exists<PontAccount>(payer_address)) {
            add_user_account(payer_acc);
        };

        if (!balance_exists<TokenType>(payer_address)) {
            add_balance<TokenType>(payer_acc);
        };

        let account_balance = borrow_global_mut<Balance<TokenType>>(payer_address);

        // Load the payer's account and emit an event to record the withdrawal
        Event::emit_event<SentPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payer_address).sent_events,
            SentPaymentEvent{
                amount,
                symbol: Token::symbol<TokenType>(),
                payee,
                metadata
            },
        );
        withdraw_from_balance<TokenType>(account_balance, amount)
    }
    spec withdraw_from {
        let payer = Signer::address_of(payer_acc);

        include ModifiesPontAccount { account_addr: payer };
        modifies global<Balance<TokenType>>(payer);

        include WithdrawFromAborts<TokenType> { payer };
//        include Token::WithdrawAborts<TokenType> { token: global<Balance<TokenType>>(payer).token, amount };

        ensures exists<PontAccount>(payer);
        ensures exists<Balance<TokenType>>(payer);

//        ensures TRACE(balance<TokenType>(payer)) == TRACE(old(balance<TokenType>(payer))) - amount;
//        include WithdrawFromBalanceEnsures<TokenType>{ balance: global<Balance<TokenType>>(payer) };
//        include WithdrawFromEmits<TokenType> { payer };
    }
    spec schema WithdrawFromAborts<TokenType> {
        payer: address;
        payee: address;
        amount: u64;

        include PontTimestamp::AbortsIfNotOperating;
        include Token::AbortsIfTokenNotRegistered<TokenType>;
        aborts_if !exists<PontAccount>(payer)
                  && payer == @PontemFramework with Errors::INVALID_ARGUMENT;
//        include Token::WithdrawAbortsIf<TokenType> { token: global<Balance<TokenType>>(payer).token, amount };
    }
    spec schema WithdrawFromEmits<TokenType> {
        payer: address;
        payee: address;
        amount: u64;
        metadata: vector<u8>;
        let handle = global<PontAccount>(payer).sent_events;
        let msg = SentPaymentEvent{
            amount,
            symbol: Token::spec_symbol<TokenType>(),
            payee,
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
        assert_enough_tokens_available(token, amount);

        Token::withdraw(token, amount)
    }
    spec withdraw_from_balance {
        include PontTimestamp::AbortsIfNotOperating;
        include Token::WithdrawAborts<TokenType> { token: balance.token, amount };

        include WithdrawFromBalanceEnsures<TokenType>;
    }
    spec schema WithdrawFromBalanceEnsures<TokenType> {
        balance: Balance<TokenType>;
        amount: u64;
        result: Token<TokenType>;

        ensures balance.token.value == old(balance.token.value) - amount;
        ensures result.value == amount;
    }

    fun assert_enough_tokens_available<TokenType>(token: &Token<TokenType>, amount: u64) {
        // Abort if this withdrawal would make the `payer`'s balance go negative
        assert!(Token::value(token) >= amount, Errors::limit_exceeded(ERR_INSUFFICIENT_BALANCE));
    }
    spec assert_enough_tokens_available {
        pragma opaque;
        pragma verify = false;
        aborts_if false;
    }

    native fun create_signer(addr: address): signer;
    spec create_signer {
        pragma opaque;
        aborts_if false;
        ensures Signer::address_of(result) == addr;
    }
}
