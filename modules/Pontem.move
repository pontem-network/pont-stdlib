address 0x1 {

/// Pontem is a governance module which handles balances merging. It's basically
/// a mediator or wrapper around money-related operations. It holds knowledge about
/// registered coins and rules of their usage. Also it lessens load from 0x1::Account
module Pontem {

    use 0x1::Signer;

    const ERR_INSUFFICIENT_PRIVILEGES: u64 = 101;
    const ERR_CANT_WITHDRAW: u64 = 104;
    const ERR_NON_ZERO_DEPOSIT: u64 = 105;

    struct T<Coin> has store {
        value: u128
    }

    struct Info<Coin> has key {
        denom: vector<u8>,
        decimals: u8,

        // for tokens
        is_token: bool,
        owner: address,
        total_supply: u128
    }

    public fun value<Coin>(coin: &T<Coin>): u128 {
        coin.value
    }

    public fun zero<Coin>(): T<Coin> {
        T<Coin> { value: 0 }
    }

    public fun split<Coin>(coin: T<Coin>, amount: u128): (T<Coin>, T<Coin>) {
        let other = withdraw(&mut coin, amount);
        (coin, other)
    }

    public fun join<Coin>(coin1: T<Coin>, coin2: T<Coin>): T<Coin> {
        deposit(&mut coin1, coin2);
        coin1
    }

    public fun deposit<Coin>(coin: &mut T<Coin>, check: T<Coin>) {
        let T { value } = check; // destroy check
        coin.value = coin.value + value;
    }

    public fun withdraw<Coin>(coin: &mut T<Coin>, amount: u128): T<Coin> {
        assert(coin.value >= amount, ERR_CANT_WITHDRAW);
        coin.value = coin.value - amount;
        T { value: amount }
    }

    public fun destroy_zero<Coin>(coin: T<Coin>) {
        let T { value } = coin;
        assert(value == 0, ERR_NON_ZERO_DEPOSIT)
    }

    /// Working with CoinInfo - coin registration procedure, 0x1 account used

    /// What can be done here:
    ///   - proposals API: user creates resource Info, pushes it into queue
    ///     0x1 government reads and registers proposed resources by taking them
    ///   - try to find the way to share Info using custom module instead of
    ///     writing into main register (see above)

    /// getter for denom. reads denom information from 0x1 resource
    public fun denom<Coin: store>(): vector<u8> acquires Info {
        *&borrow_global<Info<Coin>>(0x1).denom
    }

    /// getter for currency decimals
    public fun decimals<Coin: store>(): u8 acquires Info {
        borrow_global<Info<Coin>>(0x1).decimals
    }

    /// getter for is_token property of Info
    public fun is_token<Coin: store>(): bool acquires Info {
        borrow_global<Info<Coin>>(0x1).is_token
    }

    /// getter for total_supply property of Info
    public fun total_supply<Coin: store>(): u128 acquires Info {
        borrow_global<Info<Coin>>(0x1).total_supply
    }

    /// getter for owner property of Info
    public fun owner<Coin: store>(): address acquires Info {
        borrow_global<Info<Coin>>(0x1).owner
    }

    /// only 0x1 address and add denom descriptions, 0x1 holds information resource
    public fun register_coin<Coin: store>(account: &signer, denom: vector<u8>, decimals: u8) {
        assert_can_register_coin(account);

        move_to<Info<Coin>>(account, Info {
            denom,
            decimals,
            owner: 0x1,
            total_supply: 0,
            is_token: false
        });
    }

    /// check whether sender is 0x1, helper method
    fun assert_can_register_coin(account: &signer) {
        assert(Signer::address_of(account) == 0x1, ERR_INSUFFICIENT_PRIVILEGES);
    }

    native fun create_signer(addr: address): signer;
    native fun destroy_signer(sig: signer);
}
}
