address 0x1 {

/// Account is the access point for assets flow. It holds withdraw-deposit handlers
/// for generic currency <Token>. It also stores log of sent and received events
/// for every account.
module Account {

    use 0x1::Pontem;
    use 0x1::Signer;
    use 0x1::Event;

    const ERR_ZERO_DEPOSIT: u64 = 7;

    /// holds account data, currently, only events
    struct T has key {}

    struct Balance<Coin> has key {
        coin: Pontem::T<Coin>
    }

    /// Message for sent events
    struct SentPaymentEvent {
        amount: u128,
        denom: vector<u8>,
        payee: address,
        metadata: vector<u8>,
    }

    /// Message for received events
    struct ReceivedPaymentEvent {
        amount: u128,
        denom: vector<u8>,
        payer: address,
        metadata: vector<u8>,
    }

    public fun has_balance<Coin: store>(payee: address): bool {
        exists<Balance<Coin>>(payee)
    }

    public fun balance<Coin: store>(account: &signer): u128 acquires Balance {
        balance_for<Coin>(Signer::address_of(account))
    }

    public fun balance_for<Coin: store>(addr: address): u128 acquires Balance {
        Pontem::value(&borrow_global<Balance<Coin>>(addr).coin)
    }

    public fun deposit_to_sender<Coin: store>(
        account: &signer,
        to_deposit: Pontem::T<Coin>
    ) acquires Balance {
        deposit<Coin>(
            account,
            Signer::address_of(account),
            to_deposit
        )
    }

    public fun deposit<Coin: store>(
        account: &signer,
        payee: address,
        to_deposit: Pontem::T<Coin>
    ) acquires Balance {
        deposit_with_metadata<Coin>(
            account,
            payee,
            to_deposit,
            b""
        )
    }

    public fun deposit_with_metadata<Coin: store>(
        account: &signer,
        payee: address,
        to_deposit: Pontem::T<Coin>,
        metadata: vector<u8>
    ) acquires Balance {
        deposit_with_sender_and_metadata<Coin>(
            account,
            payee,
            to_deposit,
            metadata
        )
    }

    public fun pay_from_sender<Coin: store>(
        account: &signer,
        payee: address,
        amount: u128
    ) acquires Balance {
        pay_from_sender_with_metadata<Coin>(
            account, payee, amount, b""
        )
    }

    public fun pay_from_sender_with_metadata<Coin: store>(
        account: &signer,
        payee: address,
        amount: u128,
        metadata: vector<u8>
    )
    acquires Balance {
        deposit_with_metadata<Coin>(
            account,
            payee,
            withdraw_from_sender<Coin>(account, amount),
            metadata
        )
    }

    fun deposit_with_sender_and_metadata<Coin: store>(
        sender: &signer,
        payee: address,
        to_deposit: Pontem::T<Coin>,
        metadata: vector<u8>
    ) acquires Balance {
        let amount = Pontem::value(&to_deposit);
        assert(amount > 0, ERR_ZERO_DEPOSIT);

        let denom = Pontem::denom<Coin>();

        // add event as sent into account
        Event::emit<SentPaymentEvent>(
            sender,
            SentPaymentEvent {
                amount, // u64 can be copied
                payee,
                denom: copy denom,
                metadata: copy metadata
            },
        );

        // there's no way to improve this place as payee is not sender :(
        if (!has_balance<Coin>(payee)) {
            create_balance<Coin>(payee);
        };

        let payee_balance = borrow_global_mut<Balance<Coin>>(payee);

        // send money to payee
        Pontem::deposit(&mut payee_balance.coin, to_deposit);
        // update payee's account with new event
        Event::emit<ReceivedPaymentEvent>(
            sender,
            ReceivedPaymentEvent {
                amount,
                denom,
                metadata,
                payer: Signer::address_of(sender)
            }
        )
    }

    public fun withdraw_from_sender<Coin: store>(
        account: &signer,
        amount: u128
    ): Pontem::T<Coin> acquires Balance {
        let balance = borrow_global_mut<Balance<Coin>>(Signer::address_of(account));

        withdraw_from_balance<Coin>(balance, amount)
    }

    fun withdraw_from_balance<Coin: store>(balance: &mut Balance<Coin>, amount: u128): Pontem::T<Coin> {
        Pontem::withdraw(&mut balance.coin, amount)
    }

    fun create_balance<Coin: store>(addr: address) {
        let sig = create_signer(addr);

        move_to<Balance<Coin>>(&sig, Balance {
            coin: Pontem::zero<Coin>()
        });

        destroy_signer(sig);
    }

    native fun create_signer(addr: address): signer;
    native fun destroy_signer(sig: signer);
}
}
