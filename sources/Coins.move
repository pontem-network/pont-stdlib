address 0x1 {

module Coins {
    struct ETH has key, store {}
    struct BTC has key, store {}
    struct USDT has key, store {}

    struct Price<Curr1: key + store, Curr2: key + store> has key, store {
        value: u128
    }

    public fun get_price<Curr1: key + store, Curr2: key + store>(): u128 acquires Price {
        borrow_global<Price<Curr1, Curr2>>(0x1).value
    }

    public fun has_price<Curr1: key + store, Curr2: key + store>(): bool {
        exists<Price<Curr1, Curr2>>(0x1)
    }
}
}
