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

    /// Tried to deposit a token whose value was zero
    const ERR_ZERO_DEPOSIT_AMOUNT: u64 = 1;
    /// The account does not hold a large enough balance in the specified token
    const ERR_INSUFFICIENT_BALANCE: u64 = 2;
    /// Tried to add a balance in a token that this account already has
    const ERR_TOKEN_BALANCE_ALREADY_EXISTS: u64 = 3;
    /// Tried to withdraw funds in a token that the account does hold
    const ERR_NO_BALANCE_FOR_TOKEN: u64 = 4;
    /// An account cannot be created at the reserved core code address of 0x1
    const ERR_CANNOT_CREATE_AT_CORE_ADDRESS: u64 = 5;

    /// Deposit `Token<TokenType>` to payee account.
    public fun deposit_token<TokenType>(to_addr: address, token: Token<TokenType>, from_addr: address)
    acquires PontAccount, Balance {
        deposit_token_with_metadata(from_addr, to_addr, token, b"")
    }

    public fun deposit_token_with_metadata<TokenType>(
        payer: address,
        payee: address,
        token: Token<TokenType>,
        metadata: vector<u8>
    ) acquires Balance, PontAccount {
        PontTimestamp::assert_operating();
        Token::assert_is_token<TokenType>();

        // Check that the `token` amount is non-zero
        let token_amount = Token::value(&token);
        assert!(token_amount > 0, Errors::invalid_argument(ERR_ZERO_DEPOSIT_AMOUNT));

        // Create signer for payee.
        let payee_acc = create_signer(payee);

        // Create PontAccount storage for events, if doesn't exist.
        ensure_pont_account_exists(&payee_acc);

        if (!has_token_balance<TokenType>(payee)) {
            create_token_balance<TokenType>(&payee_acc);
        };

        // Deposit the `to_deposit` token
        Token::deposit(&mut borrow_global_mut<Balance<TokenType>>(payee).token, token);

        // Log a received event
        Event::emit_event<ReceivedPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payee).received_events,
            ReceivedPaymentEvent{
                amount: token_amount,
                symbol: Token::symbol<TokenType>(),
                payer,
                metadata
            }
        );
    }
    spec deposit_token_with_metadata {
        include PontTimestamp::AbortsIfNotOperating;
        include Token::AbortsIfTokenNotRegistered<TokenType>;
        include AbortsIfCoreAddress { addr: payee };

        let deposit_amount = token.value;
        aborts_if deposit_amount == 0 with Errors::INVALID_ARGUMENT;

        ensures exists<PontAccount>(payee);
        ensures exists<Balance<TokenType>>(payee);
        ensures old(exists<Balance<TokenType>>(payee)) ==>
                balance<TokenType>(payee) == old(balance<TokenType>(payee)) + deposit_amount;
    }

    /// Withdraw `amount` `Token<TokenType>`'s from the account balance and return.
    public fun withdraw_tokens<TokenType>(
        payer_acc: &signer,
        amount: u64,
    ): Token<TokenType> acquires Balance {
        PontTimestamp::assert_operating();

        // Create PontAccount storage for events, if doesn't exist.
        ensure_pont_account_exists(payer_acc);

        let payer_address = Signer::address_of(payer_acc);
        assert!(exists<Balance<TokenType>>(payer_address), Errors::not_published(ERR_NO_BALANCE_FOR_TOKEN));

        let payer_balance = borrow_global_mut<Balance<TokenType>>(payer_address);

        let token = &mut payer_balance.token;
        assert!(Token::value(token) >= amount, Errors::limit_exceeded(ERR_INSUFFICIENT_BALANCE));

        Token::withdraw(token, amount)
    }
    spec withdraw_tokens {
        include PontTimestamp::AbortsIfNotOperating;

        let payer_addr = Signer::address_of(payer_acc);
        include AbortsIfCoreAddress { addr: payer_addr };
        aborts_if !has_token_balance<TokenType>(payer_addr) with Errors::NOT_PUBLISHED;

        let payer_balance = global<Balance<TokenType>>(payer_addr);
        aborts_if Token::value(payer_balance.token) < amount with Errors::LIMIT_EXCEEDED;

        ensures exists<PontAccount>(payer_addr);
        ensures exists<Balance<TokenType>>(payer_addr);
        ensures result.value == amount;
    }

    public fun transfer_tokens<TokenType>(
        payer: &signer,
        payee: address,
        amount: u64,
    ) acquires PontAccount, Balance {
        transfer_tokens_with_metadata<TokenType>(
            payer,
            payee,
            amount,
            b""
        );
    }
    spec transfer_tokens {
        include TransferTokenEnsures<TokenType> {
            payer_addr: Signer::address_of(payer),
            payee_addr: payee,
            amount,
        };
    }

    /// Withdraw the balance from payer account and deposit to payee.
    public fun transfer_tokens_with_metadata<TokenType>(
        payer_acc: &signer,
        payee_addr: address,
        amount: u64,
        metadata: vector<u8>,
    ) acquires PontAccount, Balance {
        let tokens = withdraw_tokens<TokenType>(payer_acc, amount);
        let payer_addr = Signer::address_of(payer_acc);
        deposit_token_with_metadata<TokenType>(
            payer_addr,
            payee_addr,
            tokens,
            copy metadata
        );
        Event::emit_event<SentPaymentEvent>(
            &mut borrow_global_mut<PontAccount>(payer_addr).sent_events,
            SentPaymentEvent{
                amount,
                symbol: Token::symbol<TokenType>(),
                payee: payee_addr,
                metadata
            },
        );
    }
    spec transfer_tokens_with_metadata {
        include TransferTokenEnsures<TokenType> {
            payer_addr: Signer::address_of(payer_acc),
            payee_addr,
            amount,
        };
    }

    spec schema TransferTokenEnsures<TokenType> {
        payer_addr: address;
        payee_addr: address;
        amount: u64;
        ensures payer_addr == payee_addr
                ==> balance<TokenType>(payer_addr) == old(balance<TokenType>(payer_addr));
        ensures payer_addr != payee_addr
                ==> balance<TokenType>(payer_addr) == old(balance<TokenType>(payer_addr)) - amount;
        ensures payer_addr != payee_addr && old(has_token_balance<TokenType>(payee_addr))
                ==> balance<TokenType>(payee_addr) == old(balance<TokenType>(payee_addr)) + amount;
        ensures payer_addr != payee_addr && old(!has_token_balance<TokenType>(payee_addr))
                ==> balance<TokenType>(payee_addr) == amount;
    }

    /// Return the current balance of the account at `addr`.
    public fun balance<TokenType>(addr: address): u64 acquires Balance {
        assert!(exists<Balance<TokenType>>(addr), Errors::not_published(ERR_NO_BALANCE_FOR_TOKEN));
        let balance = borrow_global<Balance<TokenType>>(addr);
        Token::value<TokenType>(&balance.token)
    }
    spec balance {
        aborts_if !exists<Balance<TokenType>>(addr) with Errors::NOT_PUBLISHED;
    }

    /// Add a balance of `TokenType` type to the sending account.
    public fun create_token_balance<TokenType>(acc: &signer) {
        let addr = Signer::address_of(acc);

        // aborts if `Token` is not a token type in the system
        Token::assert_is_token<TokenType>();

        // aborts if this account already has a balance in `Token`
        assert!(
            !exists<Balance<TokenType>>(addr),
            Errors::already_published(ERR_TOKEN_BALANCE_ALREADY_EXISTS)
        );
        move_to(acc, Balance<TokenType>{ token: Token::zero<TokenType>() })
    }
    spec create_token_balance {
        include Token::AbortsIfTokenNotRegistered<TokenType>;

        let acc_addr = Signer::address_of(acc);
        aborts_if exists<Balance<TokenType>>(acc_addr) with Errors::ALREADY_PUBLISHED;

        ensures exists<Balance<TokenType>>(acc_addr);
        ensures balance<TokenType>(acc_addr) == 0;
    }

    ///////////////////////////////////////////////////////////////////////////
    // General purpose methods
    ///////////////////////////////////////////////////////////////////////////
    /// If `Balance<TokenType>` exists on account.
    fun has_token_balance<TokenType>(account: address): bool {
        exists<Balance<TokenType>>(account)
    }

    fun ensure_pont_account_exists(acc: &signer) {
        let addr = Signer::address_of(acc);
        assert!(
            addr != @PontemFramework,
            Errors::invalid_argument(ERR_CANNOT_CREATE_AT_CORE_ADDRESS)
        );
        if (!exists<PontAccount>(addr)) {
            move_to(acc, PontAccount{
                received_events: Event::new_event_handle<ReceivedPaymentEvent>(acc),
                sent_events: Event::new_event_handle<SentPaymentEvent>(acc),
            });
        };
    }
    spec ensure_pont_account_exists {
        let acc_addr = Signer::address_of(acc);
        include AbortsIfCoreAddress { addr: acc_addr };
        ensures exists<PontAccount>(acc_addr);
    }

    spec schema AbortsIfCoreAddress {
        addr: address;
        aborts_if addr == @PontemFramework with Errors::INVALID_ARGUMENT;
    }

    native fun create_signer(addr: address): signer;
}
