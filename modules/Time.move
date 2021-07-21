address 0x1 {

module Time {

    const SECONDS_IN_DAY: u64 = 86400;
    const SECONDS_IN_MIN: u64 = 60;
    const MICROSECONDS_TO_SECONDS_FACTOR: u64 = 1000000;

    const ERR_INCORRECT_ARG: u64 = 101;
    const ERR_NOT_GENESIS: u64 = 102;
    const ERR_NOT_OPERATING: u64 = 103;

    /// A singleton resource holding the current Unix time in seconds
    struct CurrentTimestamp has key {
        microseconds: u64,
    }

    /// Get the timestamp representing `now` in seconds.
    public fun now_seconds(): u64 acquires CurrentTimestamp {
        borrow_global<CurrentTimestamp>(0x1).microseconds * MICROSECONDS_TO_SECONDS_FACTOR
    }

    /// Get the timestamp representing `now` in microseconds.
    public fun now_microseconds(): u64 acquires CurrentTimestamp {
        borrow_global<CurrentTimestamp>(0x1).microseconds
    }

    /// Find days difference between given timestamp and now()
    public fun days_from(ts: u64): u64 acquires CurrentTimestamp {
        let rn = now_seconds();
        assert(rn >= ts, ERR_INCORRECT_ARG);
        (rn - ts) / SECONDS_IN_DAY
    }

    /// Find minutes difference between given timestamp and now()
    public fun minutes_from(ts: u64): u64 acquires CurrentTimestamp {
        let rn = now_seconds();
        assert(rn >= ts, ERR_INCORRECT_ARG);
        (rn - ts) / SECONDS_IN_MIN
    }

    /// Helper function to determine if the blockchain is at genesis state.
    public fun is_genesis(): bool {
        !exists<Self::CurrentTimestamp>(0x1)
    }

    public fun assert_genesis() {
        assert(is_genesis(), ERR_NOT_GENESIS);
    }

    public fun assert_operating() {
        assert(!is_genesis(), ERR_NOT_GENESIS);
    }
}
}
